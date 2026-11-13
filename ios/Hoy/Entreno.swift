import ActivityKit
import Foundation
import UIKit
import UserNotifications

/// La Live Activity del modo serie a serie. La alimenta la pantalla nativa de Entreno (Hoy/Nativo/Entreno,
/// muestraNativo y `nativo`).
///
/// «Serie hecha» desde la isla o la pantalla de bloqueo:
/// - con la sesión nativa abierta, la marca la propia pantalla, también con la app en segundo plano (el intent corre
///   en el proceso de la app).
/// - sin ella (iOS cerró la app), la actividad avanza aquí sola (siguiente serie y descanso, con su aviso) y la serie
///   queda pendiente en Almacen; al reabrirse la sesión nativa se marcan las pendientes.
@MainActor
final class Entreno {
    static let shared = Entreno()

    /// La sesión nativa abierta: marca la serie que toca (false si no se pudo, p. ej. faltan las repes).
    var nativo: (() -> Bool)?
    private var actividad: Activity<EntrenoActividad>?
    private var cola: Task<Void, Never>?   // en orden: dos mensajes seguidos no pueden adelantarse el uno al otro

    private init() {
        EntrenoPuente.manejador = { [weak self] in await self?.serieHecha() }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { _ in
            Task { @MainActor in Entreno.shared.aplicaPendientesNativas() }
        }
        // las que quedaran de antes (app cerrada a medias): si la sesión sigue, se reabre y manda el estado nuevo
        for vieja in Activity<EntrenoActividad>.activities {
            Task { await vieja.end(nil, dismissalPolicy: .immediate) }
        }
        // iOS mató la app con una sesión o una rutina guiada en marcha (nativas): se vuelve a Entreno, que la reabre
        if SesionEnCurso.hayEnMarcha || GuiaEnCurso.hayEnMarcha {
            Task { @MainActor in Navegador.shared.abre("/entreno.html") }
        }
    }

    private func encola(_ trabajo: @escaping @MainActor (Entreno) async -> Void) {
        let previa = cola
        cola = Task { [weak self] in
            await previa?.value
            if let self { await trabajo(self) }
        }
    }

    /// La pantalla nativa: el estado nuevo (al abrir, en cada serie y al empezar o acabar un descanso).
    func muestraNativo(_ nombre: String, _ estado: EntrenoActividad.ContentState) {
        EntrenoPuente.programaAviso(estado)
        encola { yo in await yo.muestra(nombre, estado) }
    }

    /// Las «Serie hecha» que se pulsaron con la app cerrada (EntrenoPuente.avanzaSola las cuenta): con la sesión
    /// nativa abierta, se marcan aquí (al reabrirla y al volver a primer plano).
    func aplicaPendientesNativas() {
        guard let nativo else { return }
        let d = Almacen.defaults
        var quedan = d.integer(forKey: EntrenoPuente.clavePendientes)
        d.removeObject(forKey: EntrenoPuente.clavePendientes)
        while quedan > 0, nativo() { quedan -= 1 }
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
        if let nativo {
            _ = nativo()
            return
        }
        await EntrenoPuente.avanzaSola()
    }
}
