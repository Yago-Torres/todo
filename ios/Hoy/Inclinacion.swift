import CoreMotion
import UIKit
import WebKit

/// La inclinación del iPhone para la web: {accion:"inclinacion", activa:true/false} por el puente.
/// Mientras está pedida, la app activa, la web a la vista y sin «Reducir movimiento», unas 30 veces por segundo:
///   window.dispatchEvent(new CustomEvent("tom-inclinacion", {detail: {x, y}}))
/// con la gravedad de -1 a 1: x hacia la derecha, y hacia abajo (de pie y en vertical, y ≈ 1; en la mesa, 0 y 0).
/// CMMotionManager.deviceMotion no pide permiso ni clave en Info.plist (NSMotionUsageDescription es para la
/// actividad y el podómetro).
@MainActor
final class Inclinacion: NSObject {
    weak var vista: WKWebView?

    private let movimiento = CMMotionManager()
    private let cola: OperationQueue = {
        let q = OperationQueue()
        q.name = "dev.yagotg.hoy.inclinacion"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInteractive
        return q
    }()
    private let puente = PuenteInclinacion()
    private var pedida = false
    private var appActiva = false
    private var enVuelo = false   // el evaluateJavaScript anterior aún no ha vuelto: esta muestra se descarta

    override init() {
        super.init()
        puente.destino = self
        appActiva = UIApplication.shared.applicationState == .active
        let centro = NotificationCenter.default
        centro.addObserver(self, selector: #selector(alActivarse),
                           name: UIApplication.didBecomeActiveNotification, object: nil)
        centro.addObserver(self, selector: #selector(alDesactivarse),
                           name: UIApplication.willResignActiveNotification, object: nil)
        centro.addObserver(self, selector: #selector(alDesactivarse),
                           name: UIApplication.didEnterBackgroundNotification, object: nil)
        centro.addObserver(self, selector: #selector(revisa),
                           name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    }

    /// Lo que pide la web. También se apaga al cambiar de página y al desmontar la vista.
    func pide(_ activa: Bool) {
        pedida = activa
        revisa()
    }

    @objc private func alActivarse() {
        appActiva = true
        revisa()
    }

    @objc private func alDesactivarse() {
        appActiva = false
        revisa()
    }

    @objc private func revisa() {
        let debe = pedida && appActiva && vista?.window != nil
            && !UIAccessibility.isReduceMotionEnabled && movimiento.isDeviceMotionAvailable
        if debe { arranca() } else { para() }
    }

    private func arranca() {
        guard !movimiento.isDeviceMotionActive else { return }
        enVuelo = false
        movimiento.deviceMotionUpdateInterval = 1.0 / 30.0
        movimiento.startDeviceMotionUpdates(to: cola, withHandler: Self.manejador(puente))
    }

    private func para() {
        if movimiento.isDeviceMotionActive { movimiento.stopDeviceMotionUpdates() }
    }

    /// Fuera del actor principal: corre en `cola` y solo pasa dos números al hilo principal.
    nonisolated private static func manejador(_ puente: PuenteInclinacion) -> CMDeviceMotionHandler {
        return { datos, _ in
            guard let g = datos?.gravity else { return }
            // gravity: x a la derecha, y hacia arriba del iPhone; la web quiere y hacia abajo
            let x = max(-1, min(1, g.x))
            let y = max(-1, min(1, -g.y))
            Task { @MainActor in puente.destino?.emite(x: x, y: y) }
        }
    }

    private func emite(x: Double, y: Double) {
        guard pedida, appActiva, !enVuelo, let vista, vista.window != nil,
              !UIAccessibility.isReduceMotionEnabled else { return }
        // con Configurar o el modo voz encima, la web no se ve: no hace falta moverla
        if vista.window?.rootViewController?.presentedViewController != nil { return }
        enVuelo = true
        let js = String(format: "window.dispatchEvent(new CustomEvent(\"tom-inclinacion\",{detail:{x:%.3f,y:%.3f}}));true", x, y)
        vista.evaluateJavaScript(js) { [weak self] _, _ in
            self?.enVuelo = false
        }
    }
}

/// Lo único que cruza de la cola del sensor al hilo principal: una referencia débil, leída siempre en el principal.
final class PuenteInclinacion: @unchecked Sendable {
    weak var destino: Inclinacion?
}
