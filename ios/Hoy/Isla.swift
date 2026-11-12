import ActivityKit
import Foundation

/// Lo que Tom pone en la isla dinámica además del entreno serie a serie (EntrenoActividad):
/// - descanso suelto ({accion:"descanso", segundos, siguiente} desde la web); si hay entreno en marcha, va en el suyo,
/// - el pase del freno de apps («Instagram · 4:59»),
/// - la subida de un intento de escalada (comprimiendo / subiendo % / listo),
/// - «Día en la isla» (opcional, Configurar): anillos de hábitos, pasos y sueño hasta las 22:00.
/// Cada actividad caduca sola (staleDate) y se termina al acabar o la próxima vez que la app se activa.
@MainActor
enum Isla {
    nonisolated static let claveDia = "islaDia"

    private static var activas: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    private static func actividad(_ tipo: String) -> Activity<AvisoActividad>? {
        Activity<AvisoActividad>.activities.first { $0.attributes.tipo == tipo && $0.activityState == .active }
    }

    /// Pone o actualiza la actividad de ese tipo (una por tipo).
    private static func pon(_ tipo: String, _ estado: AvisoActividad.ContentState, caduca: Date? = nil) {
        if let a = actividad(tipo) {
            Task { await a.update(estado.contenido(caduca: caduca)) }
            return
        }
        guard activas else { return }
        _ = try? Activity.request(attributes: AvisoActividad(tipo: tipo), content: estado.contenido(caduca: caduca), pushType: nil)
    }

    private static func quita(_ tipo: String, final estado: AvisoActividad.ContentState? = nil, tras segundos: Double = 0) {
        for a in Activity<AvisoActividad>.activities where a.attributes.tipo == tipo {
            let politica: ActivityUIDismissalPolicy = segundos > 0 ? .after(Date().addingTimeInterval(segundos)) : .immediate
            Task { await a.end(estado.map { $0.contenido() }, dismissalPolicy: politica) }
        }
    }

    /// Termina lo que se quedó colgado (la app no estaba viva al acabar la cuenta atrás). Al activarse la app.
    static func limpia() {
        let ahora = Date()
        for a in Activity<AvisoActividad>.activities {
            let e = a.content.state
            let caducada = (e.fin.map { $0 < ahora } ?? false) || e.listo
            let diaAcabado = a.attributes.tipo == "dia" && (!Almacen.defaults.bool(forKey: claveDia) || finDelDia() < ahora)
            if caducada || diaAcabado { Task { await a.end(nil, dismissalPolicy: .immediate) } }
        }
    }

    // MARK: descanso

    static func descanso(segundos: Int, siguiente: String) {
        let fin = Date().addingTimeInterval(TimeInterval(max(0, segundos)))
        // con el entreno serie a serie en la isla, el descanso va en su actividad
        if let e = Activity<EntrenoActividad>.activities.first(where: { $0.activityState == .active }) {
            var s = e.content.state
            s.finDescanso = segundos > 0 ? fin : nil
            if segundos > 0 { s.descanso = segundos }
            EntrenoPuente.programaAviso(s)
            Task { await e.update(s.contenido) }
            return
        }
        guard segundos > 0 else {
            quita("descanso")
            return
        }
        pon("descanso", .init(titulo: "Descanso", detalle: siguiente.isEmpty ? "" : "Siguiente: \(siguiente)",
                              icono: "timer", inicio: Date(), fin: fin))
        // se quita sola un poco después de acabar (si la app sigue viva; si no, al volver)
        Task {
            try? await Task.sleep(for: .seconds(Double(segundos) + 3))
            if let a = actividad("descanso"), (a.content.state.fin ?? .distantFuture) <= Date() {
                await a.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    // MARK: freno de apps

    static func pase(_ app: String, minutos: Int) {
        let fin = Date().addingTimeInterval(TimeInterval(minutos * 60))
        pon("freno", .init(titulo: app, detalle: "Pase de \(minutos) min", icono: "hourglass", inicio: Date(), fin: fin))
        Task {
            try? await Task.sleep(for: .seconds(Double(minutos * 60) + 2))
            if let a = actividad("freno"), (a.content.state.fin ?? .distantFuture) <= Date() {
                await a.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    // MARK: subida de escalada

    static func subida(fase: String, progreso: Double?, texto: String) {
        switch fase {
        case "comprimiendo":
            pon("subida", .init(titulo: "Escalada", detalle: "Comprimiendo el vídeo", icono: "figure.climbing",
                                progreso: progreso ?? 0))
        case "subiendo":
            pon("subida", .init(titulo: "Escalada", detalle: "Subiendo", icono: "arrow.up.circle", progreso: progreso ?? 0))
        case "listo":
            quita("subida", final: .init(titulo: "Escalada", detalle: texto.isEmpty ? "Subido: el análisis llega en un rato" : texto,
                                         icono: "checkmark.circle", listo: true), tras: 8)
        case "error":
            quita("subida", final: .init(titulo: "Escalada", detalle: texto.isEmpty ? "No se ha podido subir" : texto,
                                         icono: "exclamationmark.triangle", listo: true), tras: 8)
        default:
            break
        }
    }

    // MARK: día en la isla

    static func finDelDia() -> Date {
        Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: Date()) ?? Date()
    }

    /// Con «Día en la isla» activado: los anillos del día (hábitos, pasos/10.000, sueño/8 h) hasta las 22:00.
    static func dia(habitos: Double, pasos: Double, sueno: Double, texto: String) {
        guard Almacen.defaults.bool(forKey: claveDia), Date() < finDelDia() else {
            quita("dia")
            return
        }
        pon("dia", .init(titulo: "Hoy", detalle: texto, icono: "sun.max", anillos: [habitos, pasos, sueno]),
            caduca: finDelDia())
    }

    static func apagaDia() { quita("dia") }
}
