import UIKit
import UserNotifications

/// Los «¿sigues?» del freno de apps. iOS no deja que una app te saque de otra a la fuerza (eso es Screen Time API, de pago),
/// así que Tom hace lo máximo que se puede sin ella: al «Entrar», avisos locales a los 5, 10, 15… min (configurable)
/// con «Salir» (abre Tom en la pantalla de freno con lo que llevas) y «5 min más» (amplía el pase sin abrir la app).
/// Se cancelan al cerrar la app frenada («App cerrada») o al decir «Mejor no».
enum FrenoAvisos {
    static let categoria = "freno"
    private static let accionSalir = "freno.salir"
    private static let accionMas = "freno.mas"
    private static let maxAvisos = 6
    /// Los ids NO empiezan por «hoy.»: Avisos.programa() borra los pendientes con ese prefijo.
    private static func id(_ app: AppFrenada, _ i: Int) -> String { "freno.aviso.\(app.rawValue).\(i)" }

    static var activos: Bool { Almacen.defaults.object(forKey: "freno.avisos") as? Bool ?? true }
    static var cada: Int { min(30, max(1, Almacen.defaults.object(forKey: "freno.avisoCada") as? Int ?? 5)) }
    static var veces: Int { min(maxAvisos, max(1, Almacen.defaults.object(forKey: "freno.avisoVeces") as? Int ?? 3)) }

    /// Los minutos de los avisos: 5, 10, 15 por defecto.
    static var minutos: [Int] { (1...veces).map { $0 * cada } }

    static func resumenMinutos(cada: Int, veces: Int) -> String {
        (1...max(1, veces)).map { String($0 * cada) }.joined(separator: ", ")
    }

    /// Los botones del aviso (los registra Avisos.registraCategorias junto a los demás).
    static func categoriaNotificacion() -> UNNotificationCategory {
        UNNotificationCategory(
            identifier: categoria,
            actions: [UNNotificationAction(identifier: accionSalir, title: "Salir", options: [.foreground]),
                      UNNotificationAction(identifier: accionMas, title: "\(Freno.minutosPase) min más", options: [])],
            intentIdentifiers: [], options: [])
    }

    /// Cuándo es el próximo aviso de esta app (para que la isla pase a «¿sigues?» justo entonces).
    static func siguiente(_ app: AppFrenada) -> Date? {
        guard activos, let inicio = Freno.inicio(app) else { return nil }
        return minutos.map { inicio.addingTimeInterval(Double($0) * 60) }.filter { $0 > Date() }.min()
    }

    static func cancela(_ app: AppFrenada) {
        let ids = (0..<maxAvisos + 1).map { id(app, $0) }
        let centro = UNUserNotificationCenter.current()
        centro.removePendingNotificationRequests(withIdentifiers: ids)
        centro.removeDeliveredNotifications(withIdentifiers: ids)
    }

    /// Programa los avisos que quedan desde el inicio del rato (los de antes se quitan). Si ya pasaron todos y sigues
    /// dentro (porque has ampliado), pone uno más dentro de «cada» minutos.
    static func programa(_ app: AppFrenada) async {
        cancela(app)
        guard activos else { return }
        let centro = UNUserNotificationCenter.current()
        let ajustes = await centro.notificationSettings()
        guard ajustes.authorizationStatus == .authorized || ajustes.authorizationStatus == .provisional else { return }
        // «urgente» necesita un permiso que la cuenta gratis no tiene: sin él, aviso normal
        let urgente = ajustes.timeSensitiveSetting != .notSupported

        let ahora = Date()
        let inicio = Freno.inicio(app) ?? ahora
        var marcas = minutos.map { ($0, inicio.addingTimeInterval(Double($0) * 60)) }.filter { $0.1 > ahora.addingTimeInterval(5) }
        if marcas.isEmpty {
            let m = Freno.llevados(app) + cada
            marcas = [(m, ahora.addingTimeInterval(Double(cada) * 60))]
        }
        for (i, (m, cuando)) in marcas.enumerated() {
            let c = UNMutableNotificationContent()
            c.title = "Tom"
            c.body = "Llevas \(m) min en \(app.nombre). ¿Sigues?"
            c.sound = .default
            c.categoryIdentifier = categoria
            c.threadIdentifier = "freno.\(app.rawValue)"
            if urgente { c.interruptionLevel = .timeSensitive }
            c.userInfo = ["app": app.rawValue]
            let disparo = UNTimeIntervalNotificationTrigger(timeInterval: max(1, cuando.timeIntervalSince(ahora)), repeats: false)
            try? await centro.add(UNNotificationRequest(identifier: id(app, i + 1), content: c, trigger: disparo))
        }
    }

    /// El toque o los botones de un aviso del freno. Devuelve true si era de aquí.
    static func maneja(_ respuesta: UNNotificationResponse, _ fin: @escaping () -> Void) -> Bool {
        let peticion = respuesta.notification.request
        guard peticion.content.categoryIdentifier == categoria,
              let nombre = peticion.content.userInfo["app"] as? String,
              let app = AppFrenada(rawValue: nombre) else { return false }
        if respuesta.actionIdentifier == accionMas {
            Task {
                await Freno.amplia(app, minutos: Freno.minutosPase)
                fin()
            }
        } else {
            // «Salir» o tocar el aviso: la app ya viene al frente; se abre su pantalla de freno con lo que llevas
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))   // con la app fría, que dé tiempo a montar la interfaz
                _ = await UIApplication.shared.open(app.revision)
                fin()
            }
        }
        return true
    }
}
