import ActivityKit
import Foundation
import UIKit
import UserNotifications
import WebKit

/// La Live Activity del modo serie a serie de /entreno.html. La web manda por el puente {accion:"entreno", estado}
/// al abrir la sesión, en cada serie y al empezar o acabar un descanso, y {accion:"entrenoFin"} al salir.
///
/// «Serie hecha» desde la isla o la pantalla de bloqueo:
/// - app delante: se pulsa la serie en la web (window.HoyEntreno.serieHecha()) y la web devuelve el estado nuevo.
/// - app en segundo plano, suspendida o cerrada: el JavaScript de la web está parado, así que la actividad avanza
///   aquí sola (siguiente serie y descanso, con su aviso) y la serie queda pendiente en Almacen. Al volver a primer
///   plano, o cuando la web reabre la sesión tras recargar, se marcan en la web las pendientes.
@MainActor
final class Entreno {
    static let shared = Entreno()

    weak var web: WKWebView?
    private var actividad: Activity<EntrenoActividad>?
    private var cola: Task<Void, Never>?   // en orden: dos mensajes seguidos no pueden adelantarse el uno al otro

    private init() {
        EntrenoPuente.manejador = { [weak self] in await self?.serieHecha() }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { _ in
            Task { @MainActor in Entreno.shared.encola { await $0.aplicaPendientes() } }
        }
        // las que quedaran de antes (app cerrada a medias): si la sesión sigue, la web la reabre y manda el estado
        for vieja in Activity<EntrenoActividad>.activities {
            Task { await vieja.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private func encola(_ trabajo: @escaping @MainActor (Entreno) async -> Void) {
        let previa = cola
        cola = Task { [weak self] in
            await previa?.value
            if let self { await trabajo(self) }
        }
    }

    // MARK: mensajes de la web

    func recibe(_ datos: [String: Any]) {
        guard let estado = EntrenoActividad.ContentState(web: datos) else { return }
        let nombre = (datos["nombre"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Entreno"
        EntrenoPuente.programaAviso(estado)
        encola { yo in
            await yo.muestra(nombre, estado)
            await yo.aplicaPendientes()
        }
    }

    func termina() {
        EntrenoPuente.quitaAviso()
        Almacen.defaults.removeObject(forKey: EntrenoPuente.clavePendientes)
        encola { yo in
            for a in Activity<EntrenoActividad>.activities {
                await a.end(nil, dismissalPolicy: .immediate)
            }
            yo.actividad = nil
        }
    }

    private func muestra(_ nombre: String, _ estado: EntrenoActividad.ContentState) async {
        if let actividad, actividad.activityState == .active, actividad.attributes.nombre == nombre {
            await actividad.update(estado.contenido)
            return
        }
        if let actividad { await actividad.end(nil, dismissalPolicy: .immediate) }
        actividad = nil
        // el aviso del fin del descanso sirve aunque las Live Activities estén desactivadas
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        actividad = try? Activity.request(attributes: EntrenoActividad(nombre: nombre),
                                          content: estado.contenido, pushType: nil)
    }

    // MARK: «Serie hecha»

    private func serieHecha() async {
        if UIApplication.shared.applicationState == .active, web != nil,
           (await evalua("window.HoyEntreno ? (window.HoyEntreno.serieHecha(), true) : false") as? Bool) == true {
            return   // la web la marcó (o enfocó las repes que faltan) y ya mandó el estado nuevo
        }
        await EntrenoPuente.avanzaSinWeb()
    }

    /// Las series marcadas con la web dormida. serieHecha() de la web: true = marcada, false = no se pudo (sin repes:
    /// se descartan, no vaya a quedarse reintentando), null = aún no hay sesión abierta (se guardan para luego).
    private func aplicaPendientes() async {
        guard UIApplication.shared.applicationState == .active, web != nil else { return }
        let d = Almacen.defaults
        var quedan = d.integer(forKey: EntrenoPuente.clavePendientes)
        while quedan > 0 {
            d.set(quedan - 1, forKey: EntrenoPuente.clavePendientes)
            let r = await evalua("window.HoyEntreno ? window.HoyEntreno.serieHecha() : null")
            if r is NSNull || r == nil {
                d.set(quedan, forKey: EntrenoPuente.clavePendientes)
                return
            }
            if r as? Bool != true {
                d.removeObject(forKey: EntrenoPuente.clavePendientes)
                return
            }
            quedan -= 1
        }
    }

    private func evalua(_ js: String) async -> Any? {
        guard let web else { return nil }
        return await withCheckedContinuation { (c: CheckedContinuation<Any?, Never>) in
            web.evaluateJavaScript(js) { resultado, _ in c.resume(returning: resultado) }
        }
    }
}

extension EntrenoActividad.ContentState {
    /// El estado tal como lo manda la web; finDescanso en milisegundos desde 1970 (0 = sin descanso).
    init?(web d: [String: Any]) {
        guard let ejercicio = d["ejercicio"] as? String else { return nil }
        func entero(_ k: String) -> Int { (d[k] as? NSNumber)?.intValue ?? 0 }
        self.ejercicio = ejercicio
        serie = entero("serie")
        total = entero("total")
        detalle = d["detalle"] as? String ?? ""
        descanso = entero("descanso")
        hecho = (d["hecho"] as? NSNumber)?.boolValue ?? false
        let ms = (d["finDescanso"] as? NSNumber)?.doubleValue ?? 0
        finDescanso = ms > 0 ? Date(timeIntervalSince1970: ms / 1000) : nil
    }
}
