import CoreMotion
import Observation
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

extension Aspecto {
    /// El tema del catálogo que se ve. Con un tema «propio» (tocado a mano), el que tenga la misma base: así un
    /// Sakura con otro acento sigue teniendo sus pétalos.
    var temaDelCatalogo: Catalogo.TemaCat? {
        if let t = catalogo?.tema(eleccion.tema) { return t }
        return catalogo?.temas?.first { $0.base.uppercased() == eleccion.base.uppercased() }
    }

    /// El fondo animado del tema (FondoTema); sin catálogo nuevo, el ASCII de siempre. Recién arrancada (aún sin
    /// catálogo), el de la última vez.
    var decoracion: String { temaDelCatalogo?.decoracion ?? (catalogo == nil ? instantanea?.decoracion : nil) ?? "ascii" }

    /// El juego de sonidos del tema (Sonidos).
    var juegoSonidos: String { temaDelCatalogo?.sonido ?? (catalogo == nil ? instantanea?.sonido : nil) ?? "campanas" }
}

/// Lo que mueve los fondos y la mascota sin tocarlos: la inclinación del iPhone y el último toque en pantalla.
/// La inclinación sale de CoreMotion a 15 Hz (sin permiso) solo mientras alguien la pide, la app está activa y no hay
/// «reducir movimiento». El toque se observa con un reconocedor en la ventana que nunca se reconoce: no roba ningún
/// gesto. Los valores que cambian a cada momento no se observan (los fondos los leen en cada fotograma); solo
/// `activo` avisa, para despertar a los fondos quietos mientras algo se mueve.
@MainActor @Observable
final class MovimientoFondo {
    static let shared = MovimientoFondo()

    /// La gravedad suavizada de -1 a 1: x hacia la derecha, y hacia abajo (de pie, y ≈ 1).
    @ObservationIgnored private(set) var inclinacion = CGPoint(x: 0, y: 0.7)
    /// Dónde está (o estuvo) el dedo, en puntos de la ventana, y cuándo.
    @ObservationIgnored private(set) var toque: CGPoint?
    @ObservationIgnored private(set) var toqueFin: Date?
    @ObservationIgnored private(set) var tocando = false
    /// Algo se ha movido hace poco (dedo o inclinación): los fondos quietos se repintan mientras dura.
    private(set) var activo = false

    @ObservationIgnored private let sensor = CMMotionManager()
    @ObservationIgnored private var usuarios = 0
    @ObservationIgnored private var reconocedor: Observador?
    @ObservationIgnored private var apagado: Task<Void, Never>?
    @ObservationIgnored private var inclinacionVista = CGPoint(x: 0, y: 0.7)

    private init() {
        let centro = NotificationCenter.default
        centro.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in MovimientoFondo.shared.revisa() }
        }
        centro.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in MovimientoFondo.shared.revisa() }
        }
        centro.addObserver(forName: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in MovimientoFondo.shared.revisa() }
        }
    }

    /// Cuánto pesa el toque ahora: 1 con el dedo puesto y baja a 0 en un segundo después de soltar.
    func fuerzaToque(_ ahora: Date = Date()) -> Double {
        if tocando { return 1 }
        guard let fin = toqueFin else { return 0 }
        return max(0, 1 - ahora.timeIntervalSince(fin))
    }

    func engancha() {
        usuarios += 1
        instalaReconocedor()
        revisa()
    }

    func suelta() {
        usuarios = max(0, usuarios - 1)
        revisa()
    }

    /// CoreMotion tarda en arrancar y el fondo se ve igual quieto: no se enciende hasta que la app ya ha pintado.
    @ObservationIgnored private var arranqueHecho = false
    @ObservationIgnored private var esperaArranque: Task<Void, Never>?

    private func revisa() {
        if !arranqueHecho {
            guard esperaArranque == nil else { return }
            esperaArranque = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1500))
                MovimientoFondo.shared.arranqueHecho = true
                MovimientoFondo.shared.revisa()
            }
            return
        }
        let debe = usuarios > 0 && UIApplication.shared.applicationState == .active
            && !UIAccessibility.isReduceMotionEnabled && sensor.isDeviceMotionAvailable
        if debe, !sensor.isDeviceMotionActive {
            sensor.deviceMotionUpdateInterval = 1.0 / 15.0
            sensor.startDeviceMotionUpdates(to: .main) { datos, _ in
                guard let g = datos?.gravity else { return }
                MainActor.assumeIsolated { MovimientoFondo.shared.nueva(x: g.x, y: -g.y) }
            }
        } else if !debe, sensor.isDeviceMotionActive {
            sensor.stopDeviceMotionUpdates()
        }
    }

    private func nueva(x: Double, y: Double) {
        // filtro de paso bajo: que el fondo flote, no que tiemble
        inclinacion.x += (max(-1, min(1, x)) - inclinacion.x) * 0.2
        inclinacion.y += (max(-1, min(1, y)) - inclinacion.y) * 0.2
        if hypot(inclinacion.x - inclinacionVista.x, inclinacion.y - inclinacionVista.y) > 0.015 {
            inclinacionVista = inclinacion
            despierta()
        }
    }

    fileprivate func dedo(_ punto: CGPoint?, puesto: Bool) {
        if let punto { toque = punto }
        if tocando && !puesto { toqueFin = Date() }
        tocando = puesto
        despierta()
    }

    private func despierta() {
        if !activo { activo = true }
        apagado?.cancel()
        apagado = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.activo = false
        }
    }

    private func instalaReconocedor() {
        guard reconocedor?.view == nil else { return }
        let ventana = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        guard let ventana else {
            // la ventana aún no está: se vuelve a probar en un momento
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                MovimientoFondo.shared.instalaReconocedor()
            }
            return
        }
        let r = Observador()
        ventana.addGestureRecognizer(r)
        reconocedor = r
    }
}

/// Un reconocedor que solo mira: apunta dónde está el dedo y falla siempre, así que no cancela ni retrasa ningún
/// toque de la interfaz.
private final class Observador: UIGestureRecognizer, UIGestureRecognizerDelegate {
    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        MovimientoFondo.shared.dedo(touches.first?.location(in: view), puesto: true)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        MovimientoFondo.shared.dedo(touches.first?.location(in: view), puesto: true)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        MovimientoFondo.shared.dedo(touches.first?.location(in: view), puesto: false)
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        MovimientoFondo.shared.dedo(nil, puesto: false)
        state = .failed
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otro: UIGestureRecognizer) -> Bool { true }
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRequireFailureOf otro: UIGestureRecognizer) -> Bool { false }
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy otro: UIGestureRecognizer) -> Bool { false }
}
