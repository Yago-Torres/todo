import Foundation
import UserNotifications
import BackgroundTasks
import WidgetKit

/// Avisos LOCALES: lo mismo que avisos.py (mañana, antes de entrenar, repaso) pero programado en el propio móvil.
/// Sin cuenta de pago de Apple no hay push (APNs), así que la web y el servidor no pueden llamar al iPhone.
/// Telegram sigue avisando también, a propósito: este aviso es el de reserva si Telegram no llega, y el de Telegram
/// lo es si iOS no deja correr la app en segundo plano y los avisos locales se quedan sin recalcular.
enum Avisos {
    /// SideStore reescribe BGTaskSchedulerPermittedIdentifiers con el bundle id nuevo (dev.yagotg.hoy.<EQUIPO>.refresco):
    /// con el id fijo, register() y submit() no fallan pero la tarea no llega nunca.
    static var tareaId: String { (Bundle.main.bundleIdentifier ?? "dev.yagotg.hoy") + ".refresco" }
    private static let prefijo = "hoy."
    private static let categoriaHecho = "hecho"
    private static let categoriaTarea = "tarea"
    private static let categoriaEntreno = "entreno"
    private static let accionHecho = "hecho"
    fileprivate static let accionTareaHecha = "tarea.hecha"
    fileprivate static let accionPospone = "tarea.pospone"
    fileprivate static let accionManana = "tarea.manana"
    fileprivate static let accionMueve = "entreno.mueve"
    /// El resumen de la semana, el domingo a las 20:00 (se apaga en Configurar → avisos). Por defecto, activado.
    static let claveSemana = "avisoSemana"

    static func pidePermiso() async -> Bool {
        let ok = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        return ok ?? false
    }

    /// Los botones de los avisos. Ninguno lleva .foreground: se resuelven sin abrir la app (AvisosDelegado).
    private static func registraCategorias() {
        func accion(_ id: String, _ titulo: String) -> UNNotificationAction {
            UNNotificationAction(identifier: id, title: titulo, options: [])
        }
        let hecho = UNNotificationCategory(identifier: categoriaHecho, actions: [accion(accionHecho, "Hecho")],
                                           intentIdentifiers: [], options: [])
        let tarea = UNNotificationCategory(identifier: categoriaTarea,
                                           actions: [accion(accionTareaHecha, "Hecho"), accion(accionPospone, "Posponer 1 h"),
                                                     accion(accionManana, "Mañana")],
                                           intentIdentifiers: [], options: [])
        let entreno = UNNotificationCategory(identifier: categoriaEntreno, actions: [accion(accionMueve, "Mover a mañana")],
                                             intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories(
            Set([hecho, tarea, entreno, FrenoAvisos.categoriaNotificacion()] + AvisosRacha.categorias))
    }

    private static func borraPendientes() async {
        let centro = UNUserNotificationCenter.current()
        let ids = await centro.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefijo) }
        centro.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Recalcula los avisos de los próximos 7 días con lo que hay en el servidor. Nunca avisa de algo ya marcado.
    static func programa() async {
        guard Almacen.defaults.bool(forKey: "avisos") else {
            await borraPendientes()
            return
        }
        guard let estado = try? await API.estado() else { return }   // sin red se quedan los avisos de la última vez
        registraCategorias()

        let habitos = estado["habits"] as? [[String: Any]] ?? []
        let rutinas = estado["rutinas"] as? [[String: Any]] ?? []
        let plan = estado["plan"] as? [String: [String]] ?? [:]
        let log = estado["log"] as? [String: [String]] ?? [:]
        let sesion = estado["sesion"] as? [String: [String: String]] ?? [:]

        var nombre: [String: String] = [:]
        for h in habitos { if let id = h["id"] as? String, let n = h["n"] as? String { nombre[id] = n } }
        var rutina: [String: String] = [:]
        for r in rutinas { if let id = r["id"] as? String, let n = r["n"] as? String { rutina[id] = n } }
        let movilidad = rutinas.first { ($0["tipo"] as? String) == "movilidad" }?["hab"] as? String

        let cal = Calendar.current
        let hoy0 = cal.startOfDay(for: Date())
        var nuevos: [UNNotificationRequest] = []

        for i in 0..<7 {
            guard let dia = cal.date(byAdding: .day, value: i, to: hoy0) else { continue }
            let clave = Fecha.dia(dia)
            let hechos = Set(log[clave] ?? [])
            let pendientes = (plan[clave] ?? []).filter { !hechos.contains($0) }
            let sesionDia = sesion[clave] ?? [:]
            func comoSeLlama(_ hid: String) -> String {
                sesionDia[hid].flatMap { rutina[$0] } ?? nombre[hid] ?? "algo"
            }
            func aviso(_ tag: String, _ hora: Int, _ minuto: Int, _ titulo: String, _ cuerpo: String,
                       _ ruta: String, _ hids: [String], categoria: String? = nil) {
                guard let cuando = cal.date(bySettingHour: hora, minute: minuto, second: 0, of: dia),
                      cuando > Date() else { return }   // las horas pasadas de hoy, fuera
                let c = UNMutableNotificationContent()
                c.title = titulo
                c.body = cuerpo
                c.sound = .default
                c.threadIdentifier = tag
                var info: [String: String] = ["ruta": ruta, "dia": clave]
                if hids.count == 1 {
                    info["habito"] = hids[0]
                    c.categoryIdentifier = categoriaHecho
                }
                if let categoria { c.categoryIdentifier = categoria }
                c.userInfo = info
                let comp = cal.dateComponents([.year, .month, .day, .hour, .minute], from: cuando)
                let disparo = UNCalendarNotificationTrigger(dateMatching: comp, repeats: false)
                nuevos.append(UNNotificationRequest(identifier: "\(prefijo)\(clave).\(tag)", content: c, trigger: disparo))
            }

            // 06:45 rutina de la mañana, si la de movilidad no está hecha
            if let hid = movilidad, !hechos.contains(hid) {
                let texto = pendientes.map(comoSeLlama).joined(separator: ", ")
                let cuerpo = pendientes.isEmpty ? "10 minutos y el día empieza ganando." : "10 minutos. Hoy toca: \(texto)."
                aviso("manana", 6, 45, "Rutina de la mañana", cuerpo, "/entreno.html", [hid])
            }
            // antes de entrenar: 17:15 L-J, 14:45 V, 11:00 fines de semana (weekday: 1 = domingo)
            if !pendientes.isEmpty {
                let (h, m): (Int, Int)
                switch cal.component(.weekday, from: dia) {
                case 2...5: (h, m) = (17, 15)
                case 6: (h, m) = (14, 45)
                default: (h, m) = (11, 0)
                }
                let texto = pendientes.map(comoSeLlama).joined(separator: " y ")
                aviso("antes", h, m, "En un rato entrenas", "Toca \(texto).", "/entreno.html", pendientes, categoria: categoriaEntreno)
            }
            // 22:00 repaso. Con un solo pendiente, tocar el aviso lo marca directo
            if !pendientes.isEmpty {
                let texto = pendientes.map(comoSeLlama).joined(separator: ", ")
                let ruta = pendientes.count == 1 ? "/habitos.html?hecho=\(pendientes[0])" : "/"
                aviso("repaso", 22, 0, "¿Lo has hecho?", "Sin marcar: \(texto).", ruta, pendientes)
            }
        }

        nuevos += await avisosDeTareas(cal: cal, hoy0: hoy0)
        nuevos += await avisoDeSemana(cal: cal, hoy0: hoy0)
        nuevos = AvisosRacha.funde(nuevos + (await AvisosRacha.avisos(cal: cal, hoy0: hoy0)))   // rachas (Nativo/Rachas)

        await borraPendientes()
        // iOS guarda como mucho 64 pendientes: primero los más próximos
        func cuando(_ n: UNNotificationRequest) -> Date {
            (n.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? Date.distantFuture
        }
        nuevos.sort { cuando($0) < cuando($1) }
        for n in nuevos.prefix(60) { try? await UNUserNotificationCenter.current().add(n) }
    }

    /// Las tareas con fecha de los próximos 7 días, a su hora (o a las 9:00 si no tienen), con Hecho / Posponer 1 h / Mañana.
    private static func avisosDeTareas(cal: Calendar, hoy0: Date) async -> [UNNotificationRequest] {
        guard let crudo = try? await API.datos("/api/bandeja?solo=tareas"),
              let objeto = (try? JSONSerialization.jsonObject(with: crudo)) as? [String: Any],
              let lista = objeto["tareas"] as? [[String: Any]] else { return [] }
        let limite = Fecha.dia(cal.date(byAdding: .day, value: 7, to: hoy0) ?? hoy0)
        let hoy = Fecha.dia(hoy0)
        var salida: [UNNotificationRequest] = []
        for tarea in lista {
            guard let id = tarea["id"] as? String, let texto = tarea["t"] as? String,
                  let due = tarea["due"] as? String, due >= hoy, due < limite,
                  let dia = Fecha.fecha(due) else { continue }
            let horaTexto = (tarea["hora"] as? String) ?? ""
            let hora: String? = horaTexto.count == 5 ? horaTexto : nil
            let h = hora == nil ? 9 : (Int(horaTexto.prefix(2)) ?? 9)
            let m = hora == nil ? 0 : (Int(horaTexto.suffix(2)) ?? 0)
            guard let cuando = cal.date(bySettingHour: h, minute: m, second: 0, of: dia), cuando > Date() else { continue }
            let c = UNMutableNotificationContent()
            c.title = hora == nil ? "Para hoy" : "A las \(hora ?? "")"
            c.body = texto
            c.sound = .default
            c.threadIdentifier = "tareas"
            c.categoryIdentifier = categoriaTarea
            c.userInfo = ["ruta": "/pendientes.html", "tarea": id, "texto": texto, "hora": hora ?? "", "dia": due]
            let comp = cal.dateComponents([.year, .month, .day, .hour, .minute], from: cuando)
            salida.append(UNNotificationRequest(identifier: "\(prefijo)\(due).tarea.\(id)", content: c,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: comp, repeats: false)))
            if salida.count >= 20 { break }
        }
        return salida
    }

    /// El domingo a las 20:00, el resumen de la semana (GET /api/semana). Se recalcula cada vez que se programa.
    private static func avisoDeSemana(cal: Calendar, hoy0: Date) async -> [UNNotificationRequest] {
        guard (Almacen.defaults.object(forKey: claveSemana) as? Bool) ?? true else { return [] }
        let domingo = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: hoy0) }
            .first { cal.component(.weekday, from: $0) == 1 }
        guard let domingo, let cuando = cal.date(bySettingHour: 20, minute: 0, second: 0, of: domingo), cuando > Date(),
              let crudo = try? await API.datos("/api/semana"),
              let objeto = (try? JSONSerialization.jsonObject(with: crudo)) as? [String: Any],
              let frases = objeto["resumen"] as? [String], !frases.isEmpty else { return [] }
        let c = UNMutableNotificationContent()
        c.title = "Tu semana en Tom"
        c.body = frases.joined(separator: " ")
        c.sound = .default
        c.threadIdentifier = "semana"
        c.userInfo = ["ruta": "/"]
        let comp = cal.dateComponents([.year, .month, .day, .hour, .minute], from: cuando)
        return [UNNotificationRequest(identifier: "\(prefijo)\(Fecha.dia(domingo)).semana", content: c,
                                      trigger: UNCalendarNotificationTrigger(dateMatching: comp, repeats: false))]
    }

    // MARK: segundo plano

    /// Se llama en didFinishLaunching: el delegado de notificaciones tiene que estar puesto antes de que llegue un toque.
    static func registraTareaFondo() {
        UNUserNotificationCenter.current().delegate = AvisosDelegado.shared
        registraCategorias()
        BGTaskScheduler.shared.register(forTaskWithIdentifier: tareaId, using: nil) { tarea in
            pideRefresco()   // el siguiente, ya
            let trabajo = Task {
                await Sincro.vacia()
                await Salud.sincroniza()
                await programa()
                await Sincro.precarga()   // con el iPhone bloqueado no hace nada (Local está cifrado)
                WidgetCenter.shared.reloadAllTimelines()
                if !Task.isCancelled { tarea.setTaskCompleted(success: true) }
            }
            tarea.expirationHandler = {
                trabajo.cancel()
                tarea.setTaskCompleted(success: false)
            }
        }
    }

    static func pideRefresco() {
        let peticion = BGAppRefreshTaskRequest(identifier: tareaId)
        peticion.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 3600)   // iOS decide cuándo; esto es el mínimo
        try? BGTaskScheduler.shared.submit(peticion)
    }

    fileprivate static func avisaDeError(_ texto: String) {
        let c = UNMutableNotificationContent()
        c.title = "No se ha podido hacer"
        c.body = texto
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "\(prefijo)error", content: c, trigger: nil))
    }
}

/// Qué pasa al tocar un aviso: abrir la sección, o marcar el hábito sin abrir la app.
final class AvisosDelegado: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AvisosDelegado()

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if FrenoAvisos.maneja(response, completionHandler) { return }   // los «¿sigues?» del freno (FrenoAvisos.swift)
        let info = response.notification.request.content.userInfo
        let ruta = info["ruta"] as? String
        let habito = info["habito"] as? String
        let dia = info["dia"] as? String ?? Fecha.hoy()
        let accion = response.actionIdentifier
        if AvisosRacha.atiende(response, completionHandler) { return }   // Hecho / Usar comodín / Descansar hoy de las rachas

        let tarea = info["tarea"] as? String
        let texto = info["texto"] as? String ?? ""
        let hora = info["hora"] as? String

        if accion == "hecho", let habito {
            Task {
                do {
                    try await API.marcaOEncola(habito: habito, hecho: true, dia: dia)   // sin red, a la cola
                    await Avisos.programa()   // el repaso de esta noche ya no hace falta
                    WidgetCenter.shared.reloadAllTimelines()
                } catch {
                    Avisos.avisaDeError(error.localizedDescription)
                }
                completionHandler()
            }
        } else if [Avisos.accionTareaHecha, Avisos.accionPospone, Avisos.accionManana].contains(accion), let tarea {
            Task {
                do {
                    switch accion {
                    case Avisos.accionTareaHecha:
                        Optimista.quitaTarea(id: tarea)
                        try await API.tareaHechaOEncola(id: tarea)
                    case Avisos.accionPospone:
                        try await API.pospone1hOEncola(id: tarea, texto: texto)
                    default:
                        try await API.tareaAMananaOEncola(id: tarea, texto: texto, hora: hora)
                    }
                    await Avisos.programa()   // el id de la tarea cambia al editarla: se vuelven a programar
                    WidgetCenter.shared.reloadAllTimelines()
                } catch {
                    Avisos.avisaDeError(error.localizedDescription)
                }
                completionHandler()
            }
        } else if accion == Avisos.accionMueve {
            Task {
                do {
                    let base = Fecha.fecha(dia) ?? Date()
                    let manana = Calendar.current.date(byAdding: .day, value: 1, to: base) ?? base.addingTimeInterval(86_400)
                    try await API.mueveEntrenoOEncola(a: Fecha.dia(manana), de: dia)
                    await Avisos.programa()
                    WidgetCenter.shared.reloadAllTimelines()
                } catch {
                    Avisos.avisaDeError(error.localizedDescription)
                }
                completionHandler()
            }
        } else if accion == UNNotificationDefaultActionIdentifier, let ruta {
            Task { @MainActor in
                Navegador.shared.abre(ruta)
                completionHandler()
            }
        } else {
            completionHandler()
        }
    }

    // con la app abierta también se ve el aviso
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
