import CoreHaptics
import UIKit

/// Los hápticos que pide la web por el puente: {accion:"haptica", patron:"marcar"}.
/// Con Core Haptics si el iPhone lo tiene (el motor arranca la primera vez que hace falta y se rearranca si el
/// sistema lo para o lo reinicia); si no, con los generadores de UIKit, que se parecen lo que pueden.
@MainActor
final class Haptica {
    static let shared = Haptica()

    enum Patron: String {
        case marcar, desmarcar, serie, record, descanso, error, dia
    }

    private let soportado = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var motor: CHHapticEngine?
    private var enMarcha = false
    private var ultimo: (any CHHapticPatternPlayer)?   // que el reproductor viva mientras suena

    private init() {}

    /// Un patrón desconocido (una web más nueva que la app) suena como un tic suave.
    func toca(_ nombre: String) {
        toca(Patron(rawValue: nombre) ?? .desmarcar)
    }

    func toca(_ patron: Patron) {
        Sonidos.shared.toca(patron)   // su sonido, con el juego del tema (si «sonidos» está encendido)
        guard soportado else {
            respaldo(patron)
            return
        }
        do {
            let m = try motorListo()
            let jugador = try m.makePlayer(with: try Self.patron(patron))
            try jugador.start(atTime: CHHapticTimeImmediate)
            ultimo = jugador
        } catch {
            enMarcha = false   // a la próxima se intenta arrancar de nuevo
            respaldo(patron)
        }
    }

    private func motorListo() throws -> CHHapticEngine {
        if let motor {
            if !enMarcha {
                try motor.start()
                enMarcha = true
            }
            return motor
        }
        let nuevo = try CHHapticEngine()
        nuevo.playsHapticsOnly = true        // no toca la sesión de audio: los sonidos de la web siguen a lo suyo
        nuevo.isAutoShutdownEnabled = true   // se apaga solo cuando no suena nada y ahorra batería
        // estos avisos llegan en una cola cualquiera; solo se apunta que hay que volver a arrancarlo
        nuevo.stoppedHandler = { _ in
            Task { @MainActor in Haptica.shared.enMarcha = false }
        }
        nuevo.resetHandler = {
            Task { @MainActor in Haptica.shared.enMarcha = false }
        }
        try nuevo.start()
        motor = nuevo
        enMarcha = true
        return nuevo
    }

    // MARK: patrones

    /// Un golpe seco: intensidad (fuerza) y sharpness (0 = sordo y redondo, 1 = nítido y metálico).
    private static func tic(_ t: TimeInterval, _ intensidad: Float, _ nitidez: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient,
                      parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: intensidad),
                                   CHHapticEventParameter(parameterID: .hapticSharpness, value: nitidez)],
                      relativeTime: t)
    }

    /// Una vibración sostenida, para dar cuerpo a un golpe.
    private static func zumbido(_ t: TimeInterval, _ duracion: TimeInterval,
                                _ intensidad: Float, _ nitidez: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticContinuous,
                      parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: intensidad),
                                   CHHapticEventParameter(parameterID: .hapticSharpness, value: nitidez)],
                      relativeTime: t, duration: duracion)
    }

    private static func patron(_ p: Patron) throws -> CHHapticPattern {
        switch p {
        case .marcar:
            // un tic nítido y corto, como un interruptor bueno
            return try CHHapticPattern(events: [tic(0, 0.8, 0.85)], parameters: [])

        case .desmarcar:
            // el mismo gesto, más flojo y más sordo
            return try CHHapticPattern(events: [tic(0, 0.45, 0.25)], parameters: [])

        case .serie:
            // doble toque: el segundo un poco más firme, «hecho»
            return try CHHapticPattern(events: [tic(0, 0.65, 0.55), tic(0.11, 0.9, 0.7)], parameters: [])

        case .record:
            // redoble que sube de fuerza y de brillo, una pausa y el golpe, que se apaga poco a poco
            var eventos: [CHHapticEvent] = []
            for n in 0..<6 {
                let paso = Float(n) / 5
                eventos.append(tic(Double(n) * 0.065, 0.3 + 0.55 * paso, 0.35 + 0.45 * paso))
            }
            let golpe: TimeInterval = 0.47
            eventos.append(tic(golpe, 1.0, 0.6))
            eventos.append(zumbido(golpe, 0.35, 0.8, 0.3))
            let caida = CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: 1),
                                CHHapticParameterCurve.ControlPoint(relativeTime: 0.08, value: 0.6),
                                CHHapticParameterCurve.ControlPoint(relativeTime: 0.35, value: 0)],
                relativeTime: golpe)
            return try CHHapticPattern(events: eventos, parameterCurves: [caida])

        case .descanso:
            // tres latidos (pum-pum), cada uno un poco más suave: se acabó el descanso, a por la siguiente
            var eventos: [CHHapticEvent] = []
            for n in 0..<3 {
                let t = Double(n) * 0.6
                let f = 1 - Float(n) * 0.15
                eventos.append(tic(t, 0.85 * f, 0.3))
                eventos.append(tic(t + 0.13, 0.55 * f, 0.2))
            }
            return try CHHapticPattern(events: eventos, parameters: [])

        case .error:
            // dos golpes graves con un poco de retumbo: «no»
            return try CHHapticPattern(events: [tic(0, 1.0, 0.1), zumbido(0, 0.09, 0.6, 0.05),
                                                tic(0.17, 1.0, 0.1), zumbido(0.17, 0.12, 0.6, 0.05)],
                                       parameters: [])

        case .dia:
            // escalera alegre: cuatro peldaños que suben y un destello arriba
            var eventos: [CHHapticEvent] = []
            for n in 0..<4 {
                let paso = Float(n) / 3
                eventos.append(tic(Double(n) * 0.085, 0.45 + 0.35 * paso, 0.4 + 0.4 * paso))
            }
            eventos.append(tic(0.42, 1.0, 1.0))
            eventos.append(tic(0.5, 0.5, 0.9))
            return try CHHapticPattern(events: eventos, parameters: [])
        }
    }

    // MARK: sin Core Haptics

    private func respaldo(_ p: Patron) {
        switch p {
        case .marcar:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.9)
        case .desmarcar:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
        case .serie:
            golpes(.medium, veces: 2, cada: 0.11)
        case .record, .dia:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .descanso:
            golpes(.light, veces: 3, cada: 0.6)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func golpes(_ estilo: UIImpactFeedbackGenerator.FeedbackStyle, veces: Int, cada: Double) {
        let generador = UIImpactFeedbackGenerator(style: estilo)
        generador.prepare()
        Task { @MainActor in
            for n in 0..<veces {
                if n > 0 { try? await Task.sleep(nanoseconds: UInt64(cada * 1_000_000_000)) }
                generador.impactOccurred()
            }
        }
    }
}
