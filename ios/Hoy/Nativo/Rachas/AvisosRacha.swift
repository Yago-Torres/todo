import SwiftUI
import UserNotifications
import WidgetKit

/// Avisos locales de rachas, con lo que dice /api/rachas: a media tarde si una racha está en juego («Te quedan 5 h para
/// mantener tu racha de 12 días: Gimnasio y Core») y la última llamada por la noche. Como mucho dos al día, y la
/// última llamada se come el repaso de las 22:00 de ese día (lo que faltaba va dentro). Botones: Hecho, Usar comodín,
/// Descansar hoy. Al marcar desde el aviso y llegar a un hito, otro aviso lo celebra. Se programan desde Avisos.programa().
enum AvisosRacha {
    static let claveActivos = "avisosRacha"
    static let claveTarde = "avisosRacha.tarde"   // minutos desde las 00:00
    static let claveNoche = "avisosRacha.noche"
    static let claveHitos = "avisosRacha.hitos"
    static let tardePorDefecto = 18 * 60
    static let nochePorDefecto = 21 * 60 + 30

    private static let accionHecho = "racha.hecho"
    private static let accionComodin = "racha.comodin"
    private static let accionDescanso = "racha.descanso"
    private static let hitos: Set<Int> = [7, 14, 30, 50, 100, 200, 365, 500, 1000]

    static var activos: Bool { (Almacen.defaults.object(forKey: claveActivos) as? Bool) ?? true }
    private static var celebrarHitos: Bool { (Almacen.defaults.object(forKey: claveHitos) as? Bool) ?? true }
    private static func minutos(_ clave: String, _ porDefecto: Int) -> Int {
        (Almacen.defaults.object(forKey: clave) as? Int) ?? porDefecto
    }

    /// Las categorías (botones): uno o varios hábitos, con o sin comodines que gastar.
    static var categorias: [UNNotificationCategory] {
        func accion(_ id: String, _ titulo: String) -> UNNotificationAction {
            UNNotificationAction(identifier: id, title: titulo, options: [])
        }
        func categoria(_ id: String, varios: Bool, comodin: Bool) -> UNNotificationCategory {
            var acciones = [accion(accionHecho, varios ? "Hecho, todo" : "Hecho")]
            if comodin { acciones.append(accion(accionComodin, "Usar comodín")) }
            acciones.append(accion(accionDescanso, "Descansar hoy"))
            return UNNotificationCategory(identifier: id, actions: acciones, intentIdentifiers: [], options: [])
        }
        return [categoria("racha", varios: false, comodin: true), categoria("racha.varios", varios: true, comodin: true),
                categoria("racha.sin", varios: false, comodin: false), categoria("racha.varios.sin", varios: true, comodin: false)]
    }

    private struct Racha {
        var id: String
        var n: String
        var racha: Int
        var base: Int
        var enJuego: Bool
        var manana: Bool
    }

    /// Los avisos de hoy y mañana. Mañana solo con lo que hoy ya está a salvo (lo en juego se reprograma al marcarlo).
    static func avisos(cal: Calendar, hoy0: Date) async -> [UNNotificationRequest] {
        guard activos, let leido = try? await API.leeOCopia(DatosRachas.ruta),
              let o = (try? JSONSerialization.jsonObject(with: leido.datos)) as? [String: Any],
              (o["hoy"] as? String) == Fecha.dia(hoy0) else { return [] }
        let rs: [Racha] = ((o["habitos"] as? [[String: Any]]) ?? []).compactMap { h in
            guard let id = h["id"] as? String else { return nil }
            return Racha(id: id, n: (h["n"] as? String) ?? id, racha: (h["racha"] as? NSNumber)?.intValue ?? 0,
                         base: (h["base"] as? NSNumber)?.intValue ?? 0,
                         enJuego: (h["en_juego"] as? Bool) ?? false, manana: (h["manana"] as? Bool) ?? false)
        }
        let quedan = ((o["comodines"] as? [String: Any])?["quedan"] as? NSNumber)?.intValue ?? 0
        let tarde = minutos(claveTarde, tardePorDefecto), noche = minutos(claveNoche, nochePorDefecto)

        var salida: [UNNotificationRequest] = []
        let hoy = rs.filter(\.enJuego).sorted { $0.base > $1.base }
        salida += pareja(hoy, dias: hoy.first?.base ?? 0, dia: hoy0, tarde: tarde, noche: noche, quedan: quedan, cal: cal)
        if let manana0 = cal.date(byAdding: .day, value: 1, to: hoy0) {
            let manana = rs.filter { $0.manana && !$0.enJuego && $0.racha > 0 }.sorted { $0.racha > $1.racha }
            // la racha de mañana es la de hoy (hoy ya está a salvo); los comodines pueden cambiar: sin botón de comodín
            salida += pareja(manana.map { var r = $0; r.base = $0.racha; return r }, dias: manana.first?.racha ?? 0,
                             dia: manana0, tarde: tarde, noche: noche, quedan: 0, cal: cal)
        }
        return salida
    }

    /// El aviso de media tarde y la última llamada de un día (dos como mucho).
    private static func pareja(_ rs: [Racha], dias: Int, dia: Date, tarde: Int, noche: Int, quedan: Int,
                               cal: Calendar) -> [UNNotificationRequest] {
        guard !rs.isEmpty, dias > 0 else { return [] }
        let nombres = DatosRachasTexto.nombres(rs.map(\.n))
        let racha = DatosRachasTexto.dias(dias)
        let colchon = quedan > 0 ? " Si no, se gasta un comodín (te \(quedan == 1 ? "queda 1" : "quedan \(quedan)"))." : ""
        var out: [UNNotificationRequest] = []
        if tarde < noche, let r = aviso("tarde", dia: dia, minuto: tarde, rs: rs, quedan: quedan, cal: cal,
                                        titulo: "Tu racha de \(racha), en juego",
                                        cuerpo: "Te quedan \(max(1, (24 * 60 - tarde) / 60)) h para mantener tu racha de \(racha): \(nombres).\(colchon)") {
            out.append(r)
        }
        if let r = aviso("noche", dia: dia, minuto: noche, rs: rs, quedan: quedan, cal: cal,
                         titulo: "Última llamada",
                         cuerpo: "Tu racha de \(racha) se rompe a medianoche: \(nombres).\(colchon)") {
            out.append(r)
        }
        return out
    }

    private static func aviso(_ tag: String, dia: Date, minuto: Int, rs: [Racha], quedan: Int, cal: Calendar,
                              titulo: String, cuerpo: String) -> UNNotificationRequest? {
        guard let cuando = cal.date(bySettingHour: minuto / 60, minute: minuto % 60, second: 0, of: dia), cuando > Date() else { return nil }
        let clave = Fecha.dia(dia)
        let c = UNMutableNotificationContent()
        c.title = titulo
        c.body = cuerpo
        c.sound = .default
        c.threadIdentifier = "racha"
        c.categoryIdentifier = (rs.count == 1 ? "racha" : "racha.varios") + (quedan > 0 ? "" : ".sin")
        var bases: [String: Int] = [:]
        for r in rs { bases[r.id] = r.base }
        c.userInfo = ["ruta": "/", "dia": clave, "habitos": rs.map(\.id), "nombres": rs.map(\.n), "bases": bases]
        let comp = cal.dateComponents([.year, .month, .day, .hour, .minute], from: cuando)
        return UNNotificationRequest(identifier: "hoy.\(clave).racha.\(tag)", content: c,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: comp, repeats: false))
    }

    /// El día que hay última llamada de racha, el repaso de las 22:00 no sale aparte: lo que decía va dentro de ella.
    static func funde(_ nuevos: [UNNotificationRequest]) -> [UNNotificationRequest] {
        var salida = nuevos
        for (i, r) in nuevos.enumerated() where r.identifier.hasSuffix(".racha.noche") {
            let repasoId = r.identifier.replacingOccurrences(of: ".racha.noche", with: ".repaso")
            guard let j = salida.firstIndex(where: { $0.identifier == repasoId }),
                  let c = r.content.mutableCopy() as? UNMutableNotificationContent else { continue }
            c.body += " " + salida[j].content.body
            let nuevo = UNNotificationRequest(identifier: r.identifier, content: c, trigger: r.trigger)
            if let k = salida.firstIndex(where: { $0.identifier == nuevos[i].identifier }) { salida[k] = nuevo }
            salida.remove(at: j)
        }
        return salida
    }

    // MARK: botones

    /// Si el toque es de un aviso de racha, lo resuelve (sin abrir la app) y devuelve true.
    static func atiende(_ respuesta: UNNotificationResponse, _ fin: @escaping () -> Void) -> Bool {
        let accion = respuesta.actionIdentifier
        guard [accionHecho, accionComodin, accionDescanso].contains(accion) else { return false }
        let info = respuesta.notification.request.content.userInfo
        let dia = info["dia"] as? String ?? Fecha.hoy()
        let ids = info["habitos"] as? [String] ?? []
        let nombres = info["nombres"] as? [String] ?? []
        let bases = info["bases"] as? [String: Int] ?? [:]
        Task {
            do {
                switch accion {
                case accionHecho:
                    for id in ids { try await API.marcaOEncola(habito: id, hecho: true, dia: dia) }
                    if celebrarHitos, dia == Fecha.hoy() {
                        for (id, n) in zip(ids, nombres) where hitos.contains((bases[id] ?? -1) + 1) {
                            celebra(dias: (bases[id] ?? 0) + 1, nombre: n)
                        }
                    }
                case accionComodin:
                    _ = try await API.escribeOEncola("/api/comodin", json: ["dia": dia])
                default:
                    for id in ids { _ = try await API.escribeOEncola("/api/descanso", json: ["id": id, "dia": dia]) }
                }
                await Avisos.programa()   // lo que ya no está en juego deja de avisar
                WidgetCenter.shared.reloadAllTimelines()
            } catch {
                avisa("No se ha podido hacer", error.localizedDescription)
            }
            fin()
        }
        return true
    }

    /// «¡30 días de Gimnasio!» al llegar a un hito marcando desde un aviso (en la app lo celebra la animación).
    static func celebra(dias: Int, nombre: String) {
        avisa("¡\(DatosRachasTexto.dias(dias)) de \(nombre)!", "Nuevo hito de racha. Sigue así.")
    }

    private static func avisa(_ titulo: String, _ cuerpo: String) {
        let c = UNMutableNotificationContent()
        c.title = titulo
        c.body = cuerpo
        c.sound = .default
        c.threadIdentifier = "racha"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "hoy.racha.\(UUID().uuidString)", content: c, trigger: nil))
    }
}

/// Los textos de las rachas, fuera del MainActor (los avisos se programan en segundo plano).
enum DatosRachasTexto {
    static func nombres(_ xs: [String]) -> String {
        guard let ultimo = xs.last else { return "" }
        return xs.count == 1 ? ultimo : xs.dropLast().joined(separator: ", ") + " y " + ultimo
    }

    static func dias(_ n: Int) -> String { n == 1 ? "1 día" : "\(n) días" }
}

/// Configurar → Avisos de racha: activar, horas y celebrar hitos.
struct SeccionAvisosRacha: View {
    @AppStorage(AvisosRacha.claveActivos, store: Almacen.defaults) private var activos = true
    @AppStorage(AvisosRacha.claveTarde, store: Almacen.defaults) private var tarde = AvisosRacha.tardePorDefecto
    @AppStorage(AvisosRacha.claveNoche, store: Almacen.defaults) private var noche = AvisosRacha.nochePorDefecto
    @AppStorage(AvisosRacha.claveHitos, store: Almacen.defaults) private var hitos = true

    var body: some View {
        Section {
            Toggle("Avisar si una racha está en juego", isOn: $activos)
            if activos {
                DatePicker("A media tarde", selection: hora($tarde), displayedComponents: .hourAndMinute)
                DatePicker("Última llamada", selection: hora($noche), displayedComponents: .hourAndMinute)
            }
            Toggle("Celebrar los hitos (7, 30, 100… días)", isOn: $hitos)
        } header: {
            Text("Avisos de racha")
        } footer: {
            Text("Como mucho dos al día, y solo si hoy hay una racha que se puede romper. La última llamada lleva dentro el repaso de las 22:00.")
        }
        .onChange(of: [activos ? 1 : 0, tarde, noche]) { _, _ in
            Task { await Avisos.programa() }
        }
    }

    private func hora(_ minutos: Binding<Int>) -> Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: minutos.wrappedValue / 60, minute: minutos.wrappedValue % 60, second: 0, of: Date()) ?? Date()
        } set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            minutos.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
    }
}
