import AVFoundation
import os
import UIKit

/// Los sonidos de cada tema, sintetizados al momento con AVAudioEngine (sin archivos): madera y bambú para los
/// japoneses, 8 bits para Terminal y Grafito, campanas suaves, clic mecánico para Braun, Bauhaus y Prensa, y
/// sintetizador para Miami (la clave `sonido` del catálogo). Suenan con cada háptica de Haptica.shared (marcar,
/// desmarcar, completar el día, error, fin del descanso…) si «sonidos» está encendido en Ajustes (/api/ajustes).
/// Sesión `.ambient` con mezcla: respeta el interruptor de silencio y no corta la música. El motor se para solo a
/// los pocos segundos sin sonar, para no gastar batería.
@MainActor
final class Sonidos {
    static let shared = Sonidos()

    private let clave = "decoracion.sonidos"
    /// El ajuste «sonidos» de Ajustes (lo mantiene al día PreferenciasDecoracion). Apagado por defecto, como en la web.
    var activos: Bool {
        get { Almacen.defaults.bool(forKey: clave) }
        set { Almacen.defaults.set(newValue, forKey: clave) }
    }

    private var motor: AVAudioEngine?
    private var sinte: Sinte?
    private var parada: Task<Void, Never>?

    private init() {
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { _ in
            // cambió la salida (auriculares, la llamada…): se monta de nuevo la próxima vez
            MainActor.assumeIsolated { Sonidos.shared.desmonta() }
        }
    }

    /// El sonido de una háptica, con el juego del tema actual.
    func toca(_ patron: Haptica.Patron) {
        guard activos else { return }
        reproduce(Juego(rawValue: Aspecto.shared.juegoSonidos) ?? .campanas, patron)
    }

    /// Para probar un juego (por ejemplo, desde Ajustes) aunque los sonidos estén apagados.
    func prueba(_ juego: String, _ patron: Haptica.Patron = .marcar) {
        reproduce(Juego(rawValue: juego) ?? .campanas, patron)
    }

    private func reproduce(_ juego: Juego, _ patron: Haptica.Patron) {
        guard let sinte = preparado() else { return }
        let notas = juego.notas(patron)
        sinte.programa(notas)
        let dura = notas.map { $0.retraso + $0.duracion }.max() ?? 0.5
        parada?.cancel()
        parada = Task { [weak self] in
            try? await Task.sleep(for: .seconds(dura + 4))
            guard !Task.isCancelled else { return }
            self?.motor?.pause()
        }
    }

    private func preparado() -> Sinte? {
        let sesion = AVAudioSession.sharedInstance()
        // con el modo voz (grabando) no se toca la sesión: se suena dentro de la suya
        if sesion.category != .playAndRecord && sesion.category != .record {
            if sesion.category != .ambient {
                try? sesion.setCategory(.ambient, options: [.mixWithOthers])
            }
            try? sesion.setActive(true)
        }
        if motor == nil {
            let m = AVAudioEngine()
            let frecuencia = m.outputNode.outputFormat(forBus: 0).sampleRate
            let s = Sinte(frecuencia: frecuencia > 0 ? frecuencia : 44_100)
            guard let formato = AVAudioFormat(standardFormatWithSampleRate: s.frecuencia, channels: 1) else { return nil }
            let fuente = AVAudioSourceNode(format: formato, renderBlock: s.bloque())
            m.attach(fuente)
            m.connect(fuente, to: m.mainMixerNode, format: formato)
            m.mainMixerNode.outputVolume = 1
            m.prepare()
            motor = m
            sinte = s
        }
        guard let motor else { return nil }
        if !motor.isRunning {
            do { try motor.start() } catch {
                desmonta()
                return nil
            }
        }
        return sinte
    }

    private func desmonta() {
        motor?.stop()
        motor = nil
        sinte = nil
    }
}

// MARK: - el sintetizador

/// Una nota: una onda con su envolvente (ataque y caída exponencial), un glissando opcional y parciales.
struct Nota {
    enum Onda { case seno, triangulo, cuadrada, ruido }
    var retraso: Double = 0
    var frecuencia: Double
    /// Desde dónde llega la frecuencia (glissando de `glis` segundos); nil = fija.
    var desde: Double?
    var glis: Double = 0.02
    var onda: Onda = .seno
    var ataque: Double = 0.003
    var caida: Double = 0.3
    var ganancia: Double = 0.5
    /// (proporción de frecuencia, ganancia, cuánto dura respecto a la fundamental)
    var parciales: [(Double, Double, Double)] = []
    /// Para las de 8 bits: corte seco a los `corte` segundos.
    var corte: Double?

    var duracion: Double { min(corte ?? .infinity, ataque + caida * 6) }
}

/// Lo que corre en el hilo de audio: una lista de voces protegida con un cerrojo, que el hilo principal rellena.
private final class Sinte: @unchecked Sendable {
    struct Voz {
        var nota: Nota
        var inicio: Int
        var fases: [Double]
    }

    let frecuencia: Double
    private let estado = OSAllocatedUnfairLock(uncheckedState: (reloj: 0, voces: [Voz](), ruido: UInt32(0x1234_5678)))

    init(frecuencia: Double) { self.frecuencia = frecuencia }

    func programa(_ notas: [Nota]) {
        let sr = frecuencia
        estado.withLockUnchecked { s in
            // un pelín de margen para que la primera muestra no se corte
            let base = s.reloj + Int(0.01 * sr)
            for n in notas {
                s.voces.append(Voz(nota: n, inicio: base + Int(n.retraso * sr), fases: Array(repeating: 0, count: n.parciales.count + 1)))
            }
            if s.voces.count > 48 { s.voces.removeFirst(s.voces.count - 48) }
        }
    }

    func bloque() -> AVAudioSourceNodeRenderBlock {
        return { [self] _, _, cuantos, lista in
            let buffers = UnsafeMutableAudioBufferListPointer(lista)
            let n = Int(cuantos)
            let sr = frecuencia
            estado.withLockUnchecked { s in
                for i in 0..<n {
                    var suma = 0.0
                    var v = 0
                    while v < s.voces.count {
                        let nota = s.voces[v].nota
                        let k = s.reloj - s.voces[v].inicio
                        if k < 0 { v += 1; continue }
                        let t = Double(k) / sr
                        if t > nota.duracion {
                            v += 1
                            continue
                        }
                        let env = (t < nota.ataque ? t / nota.ataque : 1) * exp(-max(0, t - nota.ataque) / nota.caida)
                        var f = nota.frecuencia
                        if let d = nota.desde { f = nota.frecuencia + (d - nota.frecuencia) * exp(-t / max(0.001, nota.glis)) }
                        var muestra = 0.0
                        for j in 0..<s.voces[v].fases.count {
                            let (proporcion, g, dura): (Double, Double, Double) = j == 0 ? (1, 1, 1) : nota.parciales[j - 1]
                            var fase = s.voces[v].fases[j] + f * proporcion / sr
                            if fase >= 1 { fase -= floor(fase) }
                            s.voces[v].fases[j] = fase
                            let onda: Double
                            switch nota.onda {
                            case .seno: onda = sin(2 * .pi * fase)
                            case .triangulo: onda = 4 * abs(fase - 0.5) - 1
                            case .cuadrada: onda = (fase < 0.5 ? 1 : -1) * 0.45
                            case .ruido:
                                s.ruido ^= s.ruido << 13; s.ruido ^= s.ruido >> 17; s.ruido ^= s.ruido << 5
                                onda = Double(s.ruido) / Double(UInt32.max) * 2 - 1
                            }
                            let decae = j == 0 ? 1 : exp(-t / (nota.caida * dura)) / max(1e-6, exp(-t / nota.caida))
                            muestra += onda * g * decae
                        }
                        suma += muestra * env * nota.ganancia
                        v += 1
                    }
                    s.reloj += 1
                    let salida = Float(tanh(suma * 0.32))
                    for b in buffers {
                        b.mData?.assumingMemoryBound(to: Float.self)[i] = salida
                    }
                }
                // las que ya acabaron, fuera (sin pedir memoria: compacta en el sitio)
                let reloj = s.reloj
                s.voces.removeAll { Double(reloj - $0.inicio) / sr > $0.nota.duracion }
            }
            return noErr
        }
    }
}

// MARK: - los juegos

private enum Juego: String {
    case campanas, madera, bambu, ochoBits = "8bit", clic, sintetizador

    // notas (Hz)
    static let do6 = 1046.5, mi6 = 1318.5, sol6 = 1568.0, do7 = 2093.0, la5 = 880.0, mi5 = 659.3, re5 = 587.3
    static let mib5 = 622.3, sol5 = 784.0, re6 = 1174.7, la4 = 440.0, mi7 = 2637.0, sol7 = 3136.0, do5 = 523.3

    private func campana(_ f: Double, _ t: Double = 0, _ g: Double = 0.5, _ caida: Double = 0.8) -> Nota {
        Nota(retraso: t, frecuencia: f, ataque: 0.004, caida: caida, ganancia: g,
             parciales: [(2.0, 0.3, 0.6), (2.76, 0.22, 0.45), (5.4, 0.1, 0.3)])
    }

    private func madera(_ f: Double, _ t: Double = 0, _ g: Double = 0.6, _ caida: Double = 0.05) -> [Nota] {
        [Nota(retraso: t, frecuencia: f, desde: f * 1.25, glis: 0.012, ataque: 0.001, caida: caida, ganancia: g,
              parciales: [(2.3, 0.4, 0.6), (4.1, 0.15, 0.4)]),
         Nota(retraso: t, frecuencia: 1, onda: .ruido, ataque: 0.0005, caida: 0.004, ganancia: g * 0.25)]
    }

    private func bambu(_ f: Double, _ t: Double = 0, _ g: Double = 0.55, _ caida: Double = 0.16) -> Nota {
        Nota(retraso: t, frecuencia: f, desde: f * 1.5, glis: 0.025, ataque: 0.002, caida: caida, ganancia: g,
             parciales: [(3.0, 0.25, 0.5), (5.0, 0.08, 0.3)])
    }

    private func chip(_ f: Double, _ t: Double = 0, _ dura: Double = 0.05, _ g: Double = 0.4, desde: Double? = nil) -> Nota {
        Nota(retraso: t, frecuencia: f, desde: desde, glis: dura / 2, onda: .cuadrada, ataque: 0.002, caida: dura * 3,
             ganancia: g, corte: dura)
    }

    private func clic(_ f: Double, _ t: Double = 0, _ g: Double = 0.6) -> [Nota] {
        [Nota(retraso: t, frecuencia: 1, onda: .ruido, ataque: 0.0003, caida: 0.0025, ganancia: g),
         Nota(retraso: t, frecuencia: f, ataque: 0.0005, caida: 0.01, ganancia: g * 0.5)]
    }

    private func sinte(_ f: Double, _ t: Double = 0, _ g: Double = 0.45, _ caida: Double = 0.35, desde: Double? = nil) -> Nota {
        Nota(retraso: t, frecuencia: f, desde: desde ?? f * 0.94, glis: 0.03, onda: .triangulo, ataque: 0.012, caida: caida,
             ganancia: g, parciales: [(1.006, 0.7, 1), (2.0, 0.18, 0.7)])
    }

    func notas(_ p: Haptica.Patron) -> [Nota] {
        let J = Juego.self
        switch self {
        case .campanas:
            switch p {
            case .marcar: return [campana(J.mi6, 0, 0.45)]
            case .desmarcar: return [campana(J.la5, 0, 0.3, 0.3)]
            case .serie: return [campana(J.do6, 0, 0.4, 0.5), campana(J.sol6, 0.11, 0.45, 0.6)]
            case .dia, .record:
                let largo = p == .record ? 1.8 : 1.3
                return [campana(J.do6, 0, 0.35, 0.6), campana(J.mi6, 0.09, 0.35, 0.6), campana(J.sol6, 0.18, 0.38, 0.7),
                        campana(J.do7, 0.3, 0.42, largo)]
            case .error: return [campana(415.3, 0, 0.45, 0.25), campana(392, 0.17, 0.45, 0.3)]
            case .descanso: return (0..<3).map { campana(J.re6, Double($0) * 0.6, 0.45 - Double($0) * 0.08, 0.9) }
            }
        case .madera:
            switch p {
            case .marcar: return madera(1100)
            case .desmarcar: return madera(700, 0, 0.4)
            case .serie: return madera(900) + madera(1200, 0.11)
            case .dia, .record:
                return [J.re5, J.sol5, J.la5, J.re6, 1568].enumerated().flatMap { madera($1, Double($0) * 0.085, 0.55, 0.12) }
            case .error: return madera(320, 0, 0.7, 0.08) + madera(300, 0.17, 0.7, 0.08)
            case .descanso: return (0..<3).flatMap { madera(1000, Double($0) * 0.6, 0.6) + madera(800, Double($0) * 0.6 + 0.13, 0.4) }
            }
        case .bambu:
            switch p {
            case .marcar: return [bambu(J.la5)]
            case .desmarcar: return [bambu(J.mib5, 0, 0.35, 0.1)]
            case .serie: return [bambu(J.sol5), bambu(J.re6, 0.11)]
            case .dia, .record:
                return [J.re5, J.mib5, J.sol5, J.la5, J.re6].enumerated().map { bambu($1, Double($0) * 0.09, 0.5, $0 == 4 ? 0.5 : 0.18) }
            case .error: return [bambu(311, 0, 0.6, 0.1), bambu(294, 0.17, 0.6, 0.12)]
            case .descanso: return (0..<3).map { bambu(J.sol5, Double($0) * 0.6, 0.5, 0.3) }
            }
        case .ochoBits:
            switch p {
            case .marcar: return [chip(J.do6, 0, 0.045), chip(J.sol6, 0.045, 0.07)]
            case .desmarcar: return [chip(J.sol5, 0, 0.045, 0.3), chip(J.do5, 0.045, 0.07, 0.3)]
            case .serie: return [chip(J.mi6, 0, 0.05), chip(J.sol6, 0.06, 0.05), chip(J.do7, 0.12, 0.08)]
            case .dia, .record:
                let escala = [J.do6, J.mi6, J.sol6, J.do7, J.mi7, J.sol7]
                return escala.enumerated().map { chip($1, Double($0) * 0.055, 0.05, 0.32) } + [chip(J.do7, 0.36, p == .record ? 0.5 : 0.28, 0.35)]
            case .error: return [chip(110, 0, 0.28, 0.4, desde: 220)]
            case .descanso: return (0..<3).map { chip(J.la5, Double($0) * 0.6, 0.09, 0.35) }
            }
        case .clic:
            switch p {
            case .marcar: return clic(3200)
            case .desmarcar: return clic(1800, 0, 0.4)
            case .serie: return clic(2600) + clic(3400, 0.11)
            case .dia, .record:
                return clic(2400) + clic(2800, 0.08) + clic(3200, 0.16) + [campana(1760, 0.28, 0.3, 0.6)]
            case .error: return clic(600, 0, 0.8) + clic(500, 0.17, 0.8)
            case .descanso: return (0..<3).flatMap { clic(2600, Double($0) * 0.6) }
            }
        case .sintetizador:
            switch p {
            case .marcar: return [sinte(J.la5, 0, 0.45, 0.3, desde: J.sol5)]
            case .desmarcar: return [sinte(J.re5, 0, 0.3, 0.18, desde: J.mi5)]
            case .serie: return [sinte(J.la5, 0, 0.4, 0.2), sinte(J.mi6, 0.11, 0.4, 0.3)]
            case .dia, .record:
                return [J.la5, J.do6, J.mi6, J.sol6, 1760].enumerated().map { sinte($1, Double($0) * 0.07, 0.38, $0 == 4 ? 0.9 : 0.25) }
                    + [sinte(J.la4, 0.35, 0.3, 1.0), sinte(J.mi5, 0.35, 0.25, 1.0)]
            case .error: return [sinte(220, 0, 0.5, 0.25, desde: 330)]
            case .descanso: return (0..<3).map { sinte(J.mi6, Double($0) * 0.6, 0.4, 0.4) }
            }
        }
    }
}
