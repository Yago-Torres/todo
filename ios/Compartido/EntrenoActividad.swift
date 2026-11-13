import ActivityKit
import AppIntents
import Foundation
import UserNotifications

// Compila en la app y en el widget. La Live Activity del entreno, sin servidor ni push (no hay APNs con la firma
// gratis): la arranca y la actualiza la app mientras está abierta, y la cuenta atrás la pinta el sistema solo.

struct EntrenoActividad: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var ejercicio: String
        var serie: Int            // la que toca, de 1 a total
        var total: Int
        var detalle: String       // «70 kg · 8-10 rep»
        var finDescanso: Date?
        var descanso: Int         // segundos de descanso tras esta serie (90, o 60 si va por tiempo)
        var hecho: Bool           // no queda serie conocida: sesión acabada, o marcada fuera de la app y falta la siguiente
    }

    var nombre: String
}

extension EntrenoActividad.ContentState {
    var descansando: Bool { (finDescanso ?? .distantPast) > Date() }

    /// Caduca al acabar el descanso: el widget lo ve (isStale) y deja de enseñar «0:00».
    var contenido: ActivityContent<Self> {
        ActivityContent(state: self, staleDate: descansando ? finDescanso : nil)
    }
}

/// El botón «Serie hecha» de la isla y la pantalla de bloqueo. Al ser LiveActivityIntent, iOS lo ejecuta en el
/// proceso de la APP (despertándola en segundo plano si hace falta), no en el del widget.
struct SerieHechaIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Serie hecha"
    static var isDiscoverable: Bool { false }

    init() {}

    func perform() async throws -> some IntentResult {
        await EntrenoPuente.serieHecha()
        return .result()
    }
}

@MainActor
enum EntrenoPuente {
    static let clavePendientes = "entrenoPendientes"
    private static let avisoId = "entreno.descanso"   // sin el prefijo «hoy.»: Avisos borra los suyos por prefijo

    /// Lo pone la app al arrancar (Hoy/Entreno.swift). Sin él (app lanzada en frío solo para el intent) se avanza
    /// aquí y la sesión nativa marca las pendientes al reabrirse.
    static var manejador: (() async -> Void)?

    static func serieHecha() async {
        if let manejador { await manejador() } else { await avanzaSola() }
    }

    /// Sin la sesión nativa abierta: la serie se apunta como pendiente (se marca al reabrirla), la actividad avanza a
    /// la siguiente serie con su descanso y se programa el aviso del final.
    static func avanzaSola() async {
        guard let actividad = Activity<EntrenoActividad>.activities.first(where: { $0.activityState == .active }) else { return }
        var e = actividad.content.state
        guard !e.hecho else { return }
        Almacen.defaults.set(Almacen.defaults.integer(forKey: clavePendientes) + 1, forKey: clavePendientes)
        if e.serie < e.total { e.serie += 1 } else { e.hecho = true }
        e.finDescanso = e.descanso > 0 ? Date().addingTimeInterval(TimeInterval(e.descanso)) : nil
        programaAviso(e)
        await actividad.update(e.contenido)
    }

    /// Una notificación local al acabar el descanso: vibra aunque la app esté en segundo plano o bloqueada.
    /// Sin descanso en marcha (saltado o acabado), se quita la que hubiera.
    static func programaAviso(_ e: EntrenoActividad.ContentState) {
        let centro = UNUserNotificationCenter.current()
        guard let fin = e.finDescanso, fin.timeIntervalSinceNow > 1 else {
            centro.removePendingNotificationRequests(withIdentifiers: [avisoId])
            return
        }
        let c = UNMutableNotificationContent()
        c.title = "Descanso terminado"
        c.body = e.hecho ? "A por el siguiente ejercicio" : "\(e.ejercicio) · serie \(e.serie) de \(e.total)"
        c.sound = .default
        // sin "ruta": tocarla abre la app tal cual; navegar recargaría el entreno en marcha
        let disparo = UNTimeIntervalNotificationTrigger(timeInterval: fin.timeIntervalSinceNow, repeats: false)
        centro.add(UNNotificationRequest(identifier: avisoId, content: c, trigger: disparo))
    }

    static func quitaAviso() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [avisoId])
    }
}
