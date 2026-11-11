import Foundation
import Network
import UserNotifications
import WidgetKit

/// Si hay camino a internet. Al volver la red se vacía la cola de cambios hechos sin conexión.
final class Red: @unchecked Sendable {
    static let shared = Red()

    private let monitor = NWPathMonitor()
    private let cerrojo = NSLock()
    private var conRed = true
    private var empezado = false

    var hayRed: Bool {
        cerrojo.lock()
        defer { cerrojo.unlock() }
        return conRed
    }

    func empieza() {
        cerrojo.lock()
        let ya = empezado
        empezado = true
        cerrojo.unlock()
        guard !ya else { return }
        monitor.pathUpdateHandler = { [weak self] camino in
            self?.cambia(camino.status == .satisfied)
        }
        monitor.start(queue: DispatchQueue(label: "dev.yagotg.hoy.red"))
    }

    private func cambia(_ ahora: Bool) {
        cerrojo.lock()
        let antes = conRed
        conRed = ahora
        cerrojo.unlock()
        guard ahora != antes else { return }
        Task { @MainActor in PuenteLocal.activo?.red(ahora) }
        if ahora { Task { await Sincro.vacia() } }
    }
}

/// Manda la cola de Local en orden y baja por detrás lo principal para que haya datos sin red.
enum Sincro {
    private actor Turno {
        private var ocupado = false

        func toma() -> Bool {
            if ocupado { return false }
            ocupado = true
            return true
        }

        func suelta() { ocupado = false }
    }

    enum Contestacion {
        case ok(Data, HTTPURLResponse)
        case estado(Int, Data)
        case sinRed
    }

    private enum Envio {
        case hecho
        case sinRed
        case fallo(Int, String)
        case choque(String)
    }

    private static let turno = Turno()
    private static let claveUltimaPrecarga = "localPrecarga"

    /// Las rutas que se guardan con un PUT del estado entero: al salir de la cola se juntan con lo del servidor.
    static func esEstadoCompleto(_ ruta: String) -> Bool {
        ["/api/state", "/api/gastos/estado", "/api/gastos-aitana/estado", "/api/comida/estado"].contains(ruta)
    }

    /// Al abrir la app o pasar a primer plano.
    static func alActivar() async {
        await vacia()
        await precarga()
    }

    // MARK: la cola

    /// Devuelve cuántos cambios han salido. `forzar` no espera al reintento programado («Sincronizar ahora»).
    @discardableResult
    static func vacia(forzar: Bool = false) async -> Int {
        guard Almacen.claves != nil else { return 0 }
        guard await turno.toma() else { return 0 }
        let enviados = await recorre(forzar: forzar)
        await turno.suelta()
        if enviados > 0 {
            await MainActor.run {
                PuenteLocal.activo?.sincronizado(enviados)
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
        return enviados
    }

    private static func recorre(forzar: Bool) async -> Int {
        Local.importaBuzon()
        var enviados = 0
        bucle: for c in Local.cambios() where c.estado == .pendiente {
            if Task.isCancelled { break }
            // en orden: si el primero espera su reintento, los de detrás también
            if !forzar, let proximo = c.proximo, proximo > Date() { break }
            let ruta = c.ruta
            switch await envia(c) {
            case .hecho:
                Local.borraCambio(c.id, rev: c.rev)
                enviados += 1
            case .sinRed:
                break bucle
            case .fallo(let codigo, let motivo):
                let intentos = c.intentos + 1
                // un 4xx no se arregla solo: 5 intentos. Un 5xx es la Pi o una app de detrás caída: más paciencia
                let limite = codigo >= 500 ? 10 : 5
                if intentos >= limite {
                    Local.actualiza(c.id, estado: .error, intentos: intentos, error: motivo, proximo: nil)
                    avisa("Un cambio no se ha podido guardar", "\(c.resumen): \(motivo). Lo tienes en Configurar → Sin conexión.")
                    await MainActor.run { PuenteLocal.activo?.conflicto(ruta, motivo) }
                } else {
                    let espera = min(3600, 30 * pow(2, Double(intentos - 1)))
                    Local.actualiza(c.id, estado: .pendiente, intentos: intentos, error: motivo,
                                    proximo: Date().addingTimeInterval(espera))
                    break bucle
                }
            case .choque(let motivo):
                Local.actualiza(c.id, estado: .conflicto, intentos: c.intentos + 1, error: motivo, proximo: nil)
                avisa("Cambio sin guardar por un conflicto",
                      "\(c.resumen): \(motivo). No se ha perdido: lo tienes en Configurar → Sin conexión.")
                await MainActor.run { PuenteLocal.activo?.conflicto(ruta, motivo) }
            }
        }
        if enviados > 0 { Local.ultimaSincronizacion = Date() }
        return enviados
    }

    private static func envia(_ c: Local.Cambio) async -> Envio {
        if c.metodo == "PUT" && esEstadoCompleto(c.rutaSinQuery) { return await fusionaYEnvia(c) }
        guard var p = try? API.peticion(c.ruta, metodo: c.metodo) else { return .fallo(0, "Faltan las claves") }
        p.httpBody = c.cuerpo
        if c.cuerpo != nil {
            p.setValue(c.cabeceras["content-type"] ?? "application/json", forHTTPHeaderField: "Content-Type")
        }
        switch await pide(p) {
        case .ok:
            return .hecho
        case .sinRed:
            return .sinRed
        case .estado(let codigo, let datos):
            return .fallo(codigo, motivo(codigo, datos))
        }
    }

    /// Un PUT del estado entero hecho sin red no puede pisar lo que cambió mientras tanto (el bot, los timers de la Pi,
    /// otro dispositivo): se pide lo de ahora y se juntan los dos lados a partir del estado del que partió el cambio.
    /// Si los dos tocaron lo mismo, conflicto; los hábitos marcados salen igual por /api/marca, que es idempotente.
    private static func fusionaYEnvia(_ c: Local.Cambio) async -> Envio {
        let ruta = c.rutaSinQuery
        let esState = ruta == "/api/state"
        guard let local = json(c.cuerpo) else { return .fallo(400, "El cambio guardado no es JSON") }
        let base = json(c.base)
        for _ in 0..<3 {
            guard let pg = try? API.peticion(ruta) else { return .fallo(0, "Faltan las claves") }
            let remoto: Any
            let version: String?
            switch await pide(pg) {
            case .sinRed:
                return .sinRed
            case .estado(let codigo, let datos):
                return .fallo(codigo, motivo(codigo, datos))
            case .ok(let datos, let http):
                guard let r = json(datos) else { return .fallo(500, "El servidor no devuelve JSON") }
                remoto = r
                version = http.value(forHTTPHeaderField: "X-Version")
            }

            var cuerpo: Any = local
            // sin la copia de antes solo vale si nadie ha escrito: la versión de entonces, y un 409 si no
            var cabeceraVersion = esState ? c.cabeceras["x-version"] : nil
            if let base {
                do {
                    guard let fundido = try Fusion.fusiona(base, local, remoto) else { return .hecho }
                    if Fusion.igual(fundido, remoto) { return .hecho }   // ya estaba todo en el servidor
                    cuerpo = fundido
                    cabeceraVersion = version
                } catch let choque as Fusion.Choque {
                    if esState { await mandaMarcas(base: base, local: local) }
                    return .choque("cambiado a la vez aquí y en el servidor (\(choque.donde))")
                } catch {
                    return .choque(error.localizedDescription)
                }
            }
            guard let datos = try? JSONSerialization.data(withJSONObject: cuerpo),
                  var p = try? API.peticion(ruta, metodo: "PUT") else { return .fallo(400, "No se puede preparar el envío") }
            p.httpBody = datos
            p.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let cabeceraVersion { p.setValue(cabeceraVersion, forHTTPHeaderField: "X-Version") }
            switch await pide(p) {
            case .ok(let d, let http):
                Local.guarda(Local.clave("GET", ruta), cuerpo: d,
                             tipo: http.value(forHTTPHeaderField: "Content-Type") ?? "application/json",
                             version: http.value(forHTTPHeaderField: "X-Version"), fecha: fechaDe(http), forzar: true)
                return .hecho
            case .sinRed:
                return .sinRed
            case .estado(409, _):
                if base == nil {
                    if esState { return .choque("el estado cambió en otro sitio y no hay copia de antes para juntarlo") }
                    return .fallo(409, "El servidor no acepta el cambio")
                }
                continue   // alguien escribió entre el GET y el PUT: otra vuelta
            case .estado(let codigo, let d):
                return .fallo(codigo, motivo(codigo, d))
            }
        }
        return .choque("el estado cambia sin parar en el servidor")
    }

    /// Lo único de un conflicto que se puede mandar sin pisar nada: cómo queda cada hábito marcado o desmarcado.
    private static func mandaMarcas(base: Any, local: Any) async {
        let b = ((base as? [String: Any])?["log"] as? [String: Any]) ?? [:]
        let l = ((local as? [String: Any])?["log"] as? [String: Any]) ?? [:]
        for dia in Set(b.keys).union(l.keys).sorted() {
            let antes = Set((b[dia] as? [String]) ?? [])
            let ahora = Set((l[dia] as? [String]) ?? [])
            for id in ahora.subtracting(antes).sorted() {
                _ = try? await API.datos("/api/marca", metodo: "POST", json: ["dia": dia, "id": id, "hecho": true] as [String: Any])
            }
            for id in antes.subtracting(ahora).sorted() {
                _ = try? await API.datos("/api/marca", metodo: "POST", json: ["dia": dia, "id": id, "hecho": false] as [String: Any])
            }
        }
    }

    // MARK: precarga

    /// Lo que piden las páginas al abrirse (sacado de sus fetch), para que haya datos aunque no se hayan abierto.
    private static func rutasPrincipales() -> [String] {
        let hoy = Fecha.hoy()
        let manana = Fecha.dia(Date().addingTimeInterval(24 * 3600))
        return ["/api/state", "/api/hoy", "/api/sueno", "/api/carrera", "/api/bandeja", "/api/documentos",
                "/api/fantasma", "/api/ajustes", "/api/escalada", "/api/pantalla",
                "/api/gastos/estado", "/api/gastos/resumen?dia=\(hoy)", "/api/comida/estado", "/api/comida/lista",
                "/api/toca?dia=\(hoy)", "/api/toca?dia=\(manana)", "/api/presupuesto"]
    }

    /// Como mucho cada 15 minutos (salvo `forzar`). Con el iPhone bloqueado no hay dónde guardar: no hace nada.
    static func precarga(forzar: Bool = false) async {
        guard Almacen.claves != nil, Local.disponible else { return }
        let ultima = Almacen.defaults.double(forKey: claveUltimaPrecarga)
        guard forzar || Date().timeIntervalSince1970 - ultima > 15 * 60 else { return }
        let pendientes = Set(Local.cambios().filter { $0.estado == .pendiente }.map(\.rutaSinQuery))
        let bien = await withTaskGroup(of: Bool.self, returning: Int.self) { grupo in
            for ruta in rutasPrincipales() {
                grupo.addTask { await baja(ruta, pendientes: pendientes) }
            }
            var n = 0
            for await ok in grupo where ok { n += 1 }
            return n
        }
        guard bien > 0 else { return }
        Almacen.defaults.set(Date().timeIntervalSince1970, forKey: claveUltimaPrecarga)
        Local.ultimaSincronizacion = Date()
        await bajaDocumentos()
    }

    private static func baja(_ ruta: String, pendientes: Set<String>) async -> Bool {
        guard let p = try? API.peticion(ruta) else { return false }
        guard case .ok(let datos, let http) = await pide(p) else { return false }
        let clave = Local.clave("GET", ruta)
        let soloRuta = ruta.components(separatedBy: "?").first ?? ruta
        // lo cambiado aquí que aún no ha salido no se tapa con lo del servidor
        if pendientes.contains(soloRuta), Local.lee(clave)?.local == true { return true }
        Local.guarda(clave, cuerpo: datos, tipo: http.value(forHTTPHeaderField: "Content-Type") ?? "application/json",
                     version: http.value(forHTTPHeaderField: "X-Version"), fecha: fechaDe(http))
        if ruta == "/api/hoy" { Almacen.guardaHoy(datos) }
        return true
    }

    /// Los ficheros de Documentos, para verlos sin red («Ver» abre /api/documentos/<id>/fichero). Solo los nuevos;
    /// los que ya no están en el índice se borran de aquí también.
    private static func bajaDocumentos() async {
        guard let r = Local.lee(Local.clave("GET", "/api/documentos")),
              let objeto = (try? JSONSerialization.jsonObject(with: r.cuerpo)) as? [String: Any],
              let docs = objeto["docs"] as? [[String: Any]] else { return }
        let ids = docs.compactMap { d -> String? in (d["id"] as? String) ?? (d["id"] as? NSNumber)?.stringValue }
        let vigentes = Set(ids.map { Local.clave("GET", "/api/documentos/\($0)/fichero") })
        for vieja in Local.claves(empezandoPor: "GET /api/documentos/") where vieja.hasSuffix("/fichero") && !vigentes.contains(vieja) {
            Local.borra(vieja)
        }
        for id in ids {
            if Task.isCancelled { return }
            let ruta = "/api/documentos/\(id)/fichero"
            let clave = Local.clave("GET", ruta)
            if Local.existe(clave) { continue }
            guard var p = try? API.peticion(ruta) else { return }
            p.timeoutInterval = 60
            p.setValue("*/*", forHTTPHeaderField: "Accept")
            guard case .ok(let datos, let http) = await pide(p), datos.count <= 30 * 1024 * 1024 else { continue }
            Local.guarda(clave, cuerpo: datos, tipo: http.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream",
                         version: nil, fecha: fechaDe(http))
        }
    }

    // MARK: red

    static func pide(_ p: URLRequest) async -> Contestacion {
        let resultado: (Data, URLResponse)
        do {
            resultado = try await URLSession.shared.data(for: p)
        } catch {
            return .sinRed
        }
        guard let http = resultado.1 as? HTTPURLResponse else { return .sinRed }
        // Access no acepta el service token: redirige a su login
        if let host = http.url?.host, host != Config.web.host { return .estado(401, Data()) }
        if API.esCaida(http.statusCode, tipo: http.value(forHTTPHeaderField: "Content-Type") ?? "") { return .sinRed }
        guard (200..<300).contains(http.statusCode) else { return .estado(http.statusCode, resultado.0) }
        return .ok(resultado.0, http)
    }

    /// La fecha del servidor (cabecera Date): la misma reloj que la de las copias que guarda la web.
    static func fechaDe(_ http: HTTPURLResponse) -> Date {
        guard let texto = http.value(forHTTPHeaderField: "Date") else { return Date() }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f.date(from: texto) ?? Date()
    }

    private static func json(_ datos: Data?) -> Any? {
        guard let datos else { return nil }
        return try? JSONSerialization.jsonObject(with: datos)
    }

    private static func motivo(_ codigo: Int, _ datos: Data) -> String {
        if let objeto = (try? JSONSerialization.jsonObject(with: datos)) as? [String: Any],
           let detalle = objeto["detail"] as? String {
            return detalle
        }
        return codigo == 401 ? "El servidor no acepta las claves" : "Error \(codigo) del servidor"
    }

    private static func avisa(_ titulo: String, _ cuerpo: String) {
        let c = UNMutableNotificationContent()
        c.title = titulo
        c.body = cuerpo
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "tom.sinred.\(UUID().uuidString)",
                                                                     content: c, trigger: nil))
    }
}

/// Fusión a tres bandas de JSON: lo que cambió aquí (base → local) encima de lo que hay en el servidor (remoto).
/// Diccionarios clave a clave, listas de objetos con "id" elemento a elemento y listas de textos o números sin
/// repetidos como conjuntos (log y plan de cada día). Si los dos lados cambiaron lo mismo de otra forma, Choque.
enum Fusion {
    struct Choque: Error {
        let donde: String
    }

    static func igual(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil):
            return true
        case let (x?, y?):
            return NSArray(object: x).isEqual(to: [y])
        default:
            return false
        }
    }

    static func fusiona(_ base: Any?, _ local: Any?, _ remoto: Any?, _ donde: String = "estado") throws -> Any? {
        if igual(local, base) { return remoto }
        if igual(remoto, base) { return local }
        if igual(local, remoto) { return local }
        if let l = local as? [String: Any], let r = remoto as? [String: Any] {
            let b = (base as? [String: Any]) ?? [:]
            var fuera: [String: Any] = [:]
            for k in Set(b.keys).union(l.keys).union(r.keys) {
                if let v = try fusiona(b[k], l[k], r[k], "\(donde).\(k)") { fuera[k] = v }
            }
            return fuera
        }
        if let l = local as? [Any], let r = remoto as? [Any] {
            let b = (base as? [Any]) ?? []
            if let v = try porId(b, l, r, donde) { return v }
            if let v = comoConjunto(b, l, r) { return v }
        }
        throw Choque(donde: donde)
    }

    private static func conIds(_ lista: [Any]) -> [(String, Any)]? {
        var vistos = Set<String>()
        var fuera: [(String, Any)] = []
        for x in lista {
            guard let d = x as? [String: Any], let id = d["id"] else { return nil }
            let clave = "\(id)"
            guard vistos.insert(clave).inserted else { return nil }
            fuera.append((clave, x))
        }
        return fuera
    }

    private static func porId(_ b: [Any], _ l: [Any], _ r: [Any], _ donde: String) throws -> [Any]? {
        guard let bi = conIds(b), let li = conIds(l), let ri = conIds(r) else { return nil }
        let bm = Dictionary(bi, uniquingKeysWith: { primero, _ in primero })
        let lm = Dictionary(li, uniquingKeysWith: { primero, _ in primero })
        var fuera: [Any] = []
        var vistos = Set<String>()
        for (id, rv) in ri {
            vistos.insert(id)
            if let v = try fusiona(bm[id], lm[id], rv, "\(donde)[\(id)]") { fuera.append(v) }
        }
        for (id, lv) in li where !vistos.contains(id) {
            if let v = try fusiona(bm[id], lv, nil, "\(donde)[\(id)]") { fuera.append(v) }
        }
        return fuera
    }

    private static func comoConjunto(_ b: [Any], _ l: [Any], _ r: [Any]) -> [Any]? {
        func claves(_ lista: [Any]) -> [String]? {
            var fuera: [String] = []
            for x in lista {
                if let s = x as? String {
                    fuera.append("s" + s)
                } else if let n = x as? NSNumber {
                    fuera.append("n" + n.stringValue)
                } else {
                    return nil
                }
            }
            return Set(fuera).count == fuera.count ? fuera : nil
        }
        guard let bk = claves(b), let lk = claves(l), let rk = claves(r) else { return nil }
        let quitados = Set(bk).subtracting(lk)
        let puestos = Set(lk).subtracting(bk)
        let enRemoto = Set(rk)
        var fuera: [Any] = []
        for (i, x) in r.enumerated() where !quitados.contains(rk[i]) { fuera.append(x) }
        for (i, x) in l.enumerated() where puestos.contains(lk[i]) && !enRemoto.contains(lk[i]) { fuera.append(x) }
        return fuera
    }
}
