import Observation
import SwiftUI
import UIKit

/// Cambiar de tema con un círculo: se hace una foto de la pantalla tal como está, se pone encima, se aplica el tema
/// nuevo debajo y la foto se va abriendo con un agujero redondo que crece desde el último toque (con muelle, ~0,5 s).
/// Con «reducir movimiento», el cambio es directo.
@MainActor
enum TransicionCirculo {
    static func cambia(_ cambio: () -> Void) {
        guard !UIAccessibility.isReduceMotionEnabled,
              let ventana = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first,
              let foto = ventana.snapshotView(afterScreenUpdates: false) else {
            cambio()
            return
        }
        let marco = ventana.bounds
        let centro = MovimientoFondo.shared.toque.map { CGPoint(x: min(max($0.x, 0), marco.width), y: min(max($0.y, 0), marco.height)) }
            ?? CGPoint(x: marco.midX, y: marco.midY)
        foto.frame = marco
        foto.isUserInteractionEnabled = false
        ventana.addSubview(foto)
        cambio()

        // la máscara: todo menos un círculo (regla par-impar); el círculo crece hasta la esquina más lejana
        let lejos = [CGPoint(x: 0, y: 0), CGPoint(x: marco.width, y: 0), CGPoint(x: 0, y: marco.height),
                     CGPoint(x: marco.width, y: marco.height)].map { hypot($0.x - centro.x, $0.y - centro.y) }.max() ?? 1000
        func camino(_ r: CGFloat) -> CGPath {
            let p = UIBezierPath(rect: marco)
            p.append(UIBezierPath(ovalIn: CGRect(x: centro.x - r, y: centro.y - r, width: 2 * r, height: 2 * r)))
            return p.cgPath
        }
        let mascara = CAShapeLayer()
        mascara.fillRule = .evenOdd
        mascara.frame = marco
        mascara.path = camino(lejos + 4)
        foto.layer.mask = mascara

        let muelle = CASpringAnimation(keyPath: "path")
        muelle.fromValue = camino(1)
        muelle.toValue = camino(lejos + 4)
        muelle.mass = 1
        muelle.stiffness = 140
        muelle.damping = 22
        muelle.initialVelocity = 0
        muelle.duration = min(0.8, muelle.settlingDuration)
        muelle.timingFunction = CAMediaTimingFunction(name: .easeIn)
        CATransaction.begin()
        CATransaction.setCompletionBlock { foto.removeFromSuperview() }
        mascara.add(muelle, forKey: "abre")
        CATransaction.commit()
    }
}

/// El icono de la app a juego con el tema (Assets.xcassets/Icono-<tema>.appiconset). iOS enseña un aviso cada vez
/// que cambia el icono: no se puede quitar.
@MainActor
enum IconoTema {
    static let clave = "decoracion.iconoATema"
    /// Los temas que traen icono en esta versión (un tema nuevo del servidor sin icono deja el que haya).
    static let conIcono: Set<String> = ["hormigon", "shibuya", "kioto", "sakura", "calma", "terminal", "prensa", "fiordo",
                                        "cafe", "bauhaus", "miami", "matcha", "lavanda", "medianoche", "braun", "bosque",
                                        "arena", "grafito"]

    static var activo: Bool { Almacen.defaults.object(forKey: clave) as? Bool ?? true }

    /// Pone el icono del tema (o el de siempre si el interruptor está apagado), tras un momento para no pisar la
    /// animación del cambio.
    static func aplica(_ tema: String?, retraso: Double = 0.8) {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons else { return }
        let nombre: String?
        if activo {
            guard let tema, conIcono.contains(tema) else { return }
            nombre = "Icono-\(tema)"
        } else {
            nombre = nil
        }
        guard app.alternateIconName != nombre else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(retraso))
            guard app.applicationState == .active, app.alternateIconName != nombre else { return }
            try? await app.setAlternateIconName(nombre)
        }
    }
}

/// Configurar → Apariencia: «Icono a juego con el tema».
struct InterruptorIconoTema: View {
    @AppStorage(IconoTema.clave, store: Almacen.defaults) private var iconoATema = true

    var body: some View {
        Toggle("Icono a juego con el tema", isOn: $iconoATema)
            .onChange(of: iconoATema) { _, _ in
                IconoTema.aplica(Aspecto.shared.temaDelCatalogo?.id, retraso: 0.3)
            }
            .accessibilityHint("Cambia el icono de Tom al elegir un tema. iOS avisa con un mensaje cada vez.")
    }
}

/// Vigila el tema elegido (aquí o en la web) para cambiar el icono cuando cambia.
@MainActor
final class VigiaTema {
    static let shared = VigiaTema()
    private var arrancado = false
    private var ultimo: String?

    func arranca() {
        guard !arrancado else { return }
        arrancado = true
        ultimo = Aspecto.shared.temaDelCatalogo?.id
        observa()
    }

    private func observa() {
        withObservationTracking {
            _ = Aspecto.shared.eleccion
        } onChange: {
            Task { @MainActor in
                VigiaTema.shared.cambio()
                VigiaTema.shared.observa()
            }
        }
    }

    private func cambio() {
        let id = Aspecto.shared.temaDelCatalogo?.id
        guard id != ultimo else { return }
        ultimo = id
        IconoTema.aplica(id)
    }
}

/// La fiesta de completar el día: confeti con los colores del tema, la háptica «día» y su sonido. Cada vez que
/// `disparo` cambia, suena. Con «reducir movimiento», solo la háptica y el sonido.
struct CelebracionDia: View {
    let disparo: Int
    @Environment(\.accessibilityReduceMotion) private var quieto
    @State private var inicio: Date?

    private static let duracion = 2.6

    var body: some View {
        let colores = [Tema.acento, Tema.gota, Tema.aviso, Tema.acentoSuave, Tema.texto]
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: inicio == nil)) { contexto in
            let t = inicio.map { contexto.date.timeIntervalSince($0) } ?? -1
            Canvas { ctx, tam in
                guard t >= 0, t < Self.duracion else { return }
                Self.pinta(ctx, tam, t, colores)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: disparo) { _, _ in
            Haptica.shared.toca(.dia)
            guard !quieto else { return }
            let ahora = Date()
            inicio = ahora
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.duracion))
                if inicio == ahora { inicio = nil }
            }
        }
    }

    private static func pinta(_ ctx: GraphicsContext, _ tam: CGSize, _ t: Double, _ colores: [Color]) {
        let origen = CGPoint(x: tam.width / 2, y: tam.height * 0.32)
        let gravedad = 900.0
        for i in 0..<90 {
            let ang = -Double.pi / 2 + (azarFijo(i * 4) - 0.5) * 2.6
            let v = 320 + azarFijo(i * 4 + 1) * 520
            // frenado del aire: la velocidad se apaga con e^(-t/0,9)
            let freno = 0.9 * (1 - exp(-t / 0.9))
            let x = origen.x + cos(ang) * v * freno
            let y = origen.y + sin(ang) * v * freno + 0.5 * gravedad * t * t * 0.55
            let alfa = max(0, min(1, (duracion - t) / 0.7))
            var c = ctx
            c.opacity = alfa
            c.translateBy(x: x, y: y)
            c.rotate(by: .radians(t * (3 + azarFijo(i * 4 + 2) * 8) + Double(i)))
            let color = colores[i % colores.count]
            let lado = 5 + azarFijo(i * 4 + 3) * 5
            if i % 3 == 0 {
                c.fill(Path(ellipseIn: CGRect(x: -lado / 2, y: -lado / 2, width: lado, height: lado)), with: .color(color))
            } else {
                // un papelito que gira sobre sí mismo
                let ancho = lado * abs(cos(t * 6 + Double(i)))
                c.fill(Path(CGRect(x: -ancho / 2, y: -lado * 0.35, width: max(1, ancho), height: lado * 0.7)), with: .color(color))
            }
        }
    }
}
