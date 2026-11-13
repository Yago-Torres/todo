import Foundation
import SQLite3

// La copia local de todo lo que la app ha visto del servidor (documentos, salud, gastos...) y la cola de cambios
// hechos sin red. Vive solo en este iPhone, en el contenedor del app group: nada de esto va al repo ni a iCloud.
//
// Protección:
// - tom.sqlite, con NSFileProtectionComplete: solo se lee con el iPhone desbloqueado. Con la pantalla bloqueada
//   no se abre y todo lo de aquí devuelve nil o false (el widget sigue con hoy.json de Almacen).
// - Buzon/: si hay que apuntar un cambio con el iPhone bloqueado (Siri, el botón del widget, «Hecho» en un aviso),
//   va a un fichero nuevo con completeUnlessOpen, que se puede crear bloqueado pero no volver a leer hasta
//   desbloquear. La app los pasa a la cola en cuanto puede (importaBuzon).
// Compila en la app y en el widget (sin UIKit). HoyCompartir no lo incluye.

/// SQLITE_TRANSIENT: que SQLite copie el texto o el blob al enlazarlo (la macro de C no llega a Swift).
private let transitorio = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum Local {
    struct Respuesta {
        let cuerpo: Data
        let tipo: String
        let version: String?
        let fecha: Date
        /// Cambiada aquí sin red (un PUT del estado entero en la cola): todavía no es lo del servidor.
        let local: Bool
    }

    enum Estado: String {
        case pendiente, conflicto, error
    }

    struct Cambio: Identifiable, Hashable {
        let id: Int64
        let metodo: String
        let ruta: String
        let cuerpo: Data?
        let cabeceras: [String: String]
        let fecha: Date
        let intentos: Int
        let estado: Estado
        let error: String?
        /// Para los PUT del estado entero: el estado del servidor del que partió el cambio (la fusión a tres bandas).
        let base: Data?
        let proximo: Date?
        /// Sube cada vez que otro PUT de la misma ruta se junta en este: así no se borra uno que cambió mientras salía.
        let rev: Int

        var rutaSinQuery: String { ruta.components(separatedBy: "?").first ?? ruta }

        var resumen: String {
            let json = (cuerpo.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
            switch (metodo, rutaSinQuery) {
            case ("PUT", "/api/state"):
                return "Cambios en hábitos y entreno"
            case ("PUT", "/api/gastos/estado"), ("PUT", "/api/gastos-aitana/estado"):
                return "Cambios en gastos"
            case ("PUT", "/api/comida/estado"):
                return "Cambios en comida"
            case ("POST", "/api/marca"):
                let hecho = (json["hecho"] as? Bool) ?? true
                let id = (json["id"] as? String) ?? "hábito"
                let dia = (json["dia"] as? String) ?? ""
                return "\(hecho ? "Marcar" : "Desmarcar") \(id) (\(dia))"
            case ("POST", "/api/tarea"):
                return "Tarea: \((json["t"] as? String) ?? "")"
            case ("POST", "/api/tarea/edita"):
                return "Cambiar tarea: \((json["t"] as? String) ?? "")"
            case ("POST", "/api/tarea/hecha"):
                return "Tarea hecha"
            case ("POST", "/api/tarea/borra"):
                return "Borrar tarea"
            case ("POST", "/api/gastos/gasto"), ("POST", "/api/gastos-aitana/gasto"):
                let importe = (json["importe"] as? NSNumber)?.doubleValue ?? 0
                return "Gasto de \(String(format: "%.2f", importe).replacingOccurrences(of: ".", with: ",")) €"
            case ("POST", "/api/salud"):
                if let peso = json["peso"] as? NSNumber { return "Peso: \(peso.stringValue) kg" }
                return "Datos de Salud"
            default:
                return "\(metodo) \(rutaSinQuery)"
            }
        }
    }

    private static let cola = DispatchQueue(label: "dev.yagotg.hoy.local")
    private static var conexion: OpaquePointer?
    private static var roto = false

    private static var contenedor: URL {
        if let c = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Config.grupo) { return c }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private static var carpeta: URL { contenedor.appendingPathComponent("Local", isDirectory: true) }
    private static var buzon: URL { contenedor.appendingPathComponent("Buzon", isDirectory: true) }

    private static let esquema = """
        CREATE TABLE IF NOT EXISTS respuestas (
            clave TEXT PRIMARY KEY, cuerpo BLOB NOT NULL, tipo TEXT NOT NULL DEFAULT '', version TEXT,
            fecha REAL NOT NULL, local INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS cola (
            id INTEGER PRIMARY KEY AUTOINCREMENT, metodo TEXT NOT NULL, ruta TEXT NOT NULL, cuerpo BLOB,
            cabeceras TEXT NOT NULL DEFAULT '{}', fecha REAL NOT NULL, intentos INTEGER NOT NULL DEFAULT 0,
            estado TEXT NOT NULL DEFAULT 'pendiente', error TEXT, base BLOB, proximo REAL,
            rev INTEGER NOT NULL DEFAULT 0);
        """

    // MARK: la base

    /// Solo dentro de `cola`. El esquema lee y escribe el fichero: con el iPhone bloqueado falla aquí mismo.
    private static func abre() -> OpaquePointer? {
        if let abierta = conexion { return abierta }
        let fm = FileManager.default
        let proteccion: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.complete]
        do {
            try fm.createDirectory(at: carpeta, withIntermediateDirectories: true, attributes: proteccion)
        } catch {
            return nil
        }
        // lo que se crea dentro (el diario de SQLite) hereda la protección de la carpeta
        try? fm.setAttributes(proteccion, ofItemAtPath: carpeta.path)
        let fichero = carpeta.appendingPathComponent("tom.sqlite")
        var p: OpaquePointer?
        guard sqlite3_open_v2(fichero.path, &p, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let abierta = p else {
            sqlite3_close(p)
            return nil
        }
        sqlite3_busy_timeout(abierta, 3000)   // el widget puede estar escribiendo a la vez
        guard sqlite3_exec(abierta, esquema, nil, nil, nil) == SQLITE_OK else {
            sqlite3_close(abierta)
            return nil
        }
        try? fm.setAttributes(proteccion, ofItemAtPath: fichero.path)
        conexion = abierta
        return abierta
    }

    /// Con la base abierta, en la cola de Local; sin base (iPhone bloqueado), nil.
    private static func conBase<T>(_ trabajo: (OpaquePointer) -> T?) -> T? {
        cola.sync {
            guard let db = abre() else { return nil }
            let resultado = trabajo(db)
            if roto {
                // bloqueado con la base abierta: se cierra y se vuelve a abrir al desbloquear
                roto = false
                sqlite3_close_v2(db)
                conexion = nil
            }
            return resultado
        }
    }

    private static func falla(_ db: OpaquePointer) {
        let codigo = sqlite3_errcode(db) & 0xFF
        if [SQLITE_IOERR, SQLITE_CANTOPEN, SQLITE_AUTH, SQLITE_NOTADB, SQLITE_PERM].contains(codigo) { roto = true }
    }

    @discardableResult
    private static func ejecuta(_ db: OpaquePointer, _ sql: String, _ valores: [Any?] = [],
                                fila: ((OpaquePointer) -> Void)? = nil) -> Bool {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK, let sentencia = st else {
            sqlite3_finalize(st)
            falla(db)
            return false
        }
        defer { sqlite3_finalize(sentencia) }
        enlaza(sentencia, valores)
        while true {
            let r = sqlite3_step(sentencia)
            if r == SQLITE_ROW {
                fila?(sentencia)
                continue
            }
            if r == SQLITE_DONE { return true }
            falla(db)
            return false
        }
    }

    private static func enlaza(_ st: OpaquePointer, _ valores: [Any?]) {
        for (i, valor) in valores.enumerated() {
            let n = Int32(i + 1)
            switch valor {
            case let s as String:
                sqlite3_bind_text(st, n, s, -1, transitorio)
            case let d as Data:
                if d.isEmpty {
                    sqlite3_bind_zeroblob(st, n, 0)
                } else {
                    _ = d.withUnsafeBytes { b in
                        sqlite3_bind_blob(st, n, b.baseAddress, Int32(b.count), transitorio)
                    }
                }
            case let x as Int:
                sqlite3_bind_int64(st, n, Int64(x))
            case let x as Int64:
                sqlite3_bind_int64(st, n, x)
            case let x as Double:
                sqlite3_bind_double(st, n, x)
            default:
                sqlite3_bind_null(st, n)
            }
        }
    }

    private static func columnaTexto(_ st: OpaquePointer, _ i: Int32) -> String? {
        guard let c = sqlite3_column_text(st, i) else { return nil }
        return String(cString: c)
    }

    private static func columnaDatos(_ st: OpaquePointer, _ i: Int32) -> Data? {
        guard sqlite3_column_type(st, i) != SQLITE_NULL else { return nil }
        let p = sqlite3_column_blob(st, i)
        let n = Int(sqlite3_column_bytes(st, i))
        guard let p, n > 0 else { return Data() }
        return Data(bytes: p, count: n)
    }

    private static func columnaFecha(_ st: OpaquePointer, _ i: Int32) -> Date? {
        guard sqlite3_column_type(st, i) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(st, i))
    }

    /// Hay base: el iPhone está desbloqueado (o no tiene código).
    static var disponible: Bool {
        conBase { (db: OpaquePointer) -> Bool? in ejecuta(db, "SELECT 1 FROM respuestas LIMIT 1") } ?? false
    }

    // MARK: respuestas

    /// «GET /api/toca?dia=2026-11-11»: la ruta tal cual y la query ordenada y sin codificar, para que la misma petición
    /// dé siempre la misma clave.
    static func clave(_ metodo: String, _ ruta: String) -> String {
        guard let c = URLComponents(string: ruta) else { return "\(metodo) \(ruta)" }
        let pares = (c.queryItems ?? []).map { ($0.name, $0.value ?? "") }
            .sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
        let q = pares.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        return "\(metodo) \(c.percentEncodedPath)" + (q.isEmpty ? "" : "?\(q)")
    }

    /// Sin `forzar`, solo pisa una copia más vieja: la del service worker que llega tarde no tapa la buena.
    @discardableResult
    static func guarda(_ clave: String, cuerpo: Data, tipo: String, version: String?, fecha: Date,
                       local: Bool = false, forzar: Bool = false) -> Bool {
        let sql = forzar
            ? "INSERT OR REPLACE INTO respuestas (clave, cuerpo, tipo, version, fecha, local) VALUES (?, ?, ?, ?, ?, ?)"
            : """
              INSERT INTO respuestas (clave, cuerpo, tipo, version, fecha, local) VALUES (?, ?, ?, ?, ?, ?)
              ON CONFLICT(clave) DO UPDATE SET cuerpo = excluded.cuerpo, tipo = excluded.tipo,
              version = excluded.version, fecha = excluded.fecha, local = excluded.local
              WHERE excluded.fecha >= respuestas.fecha
              """
        let valores: [Any?] = [clave, cuerpo, tipo, version, fecha.timeIntervalSince1970, local ? 1 : 0]
        return conBase { (db: OpaquePointer) -> Bool? in ejecuta(db, sql, valores) } ?? false
    }

    static func lee(_ clave: String) -> Respuesta? {
        conBase { (db: OpaquePointer) -> Respuesta? in
            var r: Respuesta?
            ejecuta(db, "SELECT cuerpo, tipo, version, fecha, local FROM respuestas WHERE clave = ?", [clave]) { st in
                r = Respuesta(cuerpo: columnaDatos(st, 0) ?? Data(), tipo: columnaTexto(st, 1) ?? "",
                              version: columnaTexto(st, 2), fecha: columnaFecha(st, 3) ?? .distantPast,
                              local: sqlite3_column_int(st, 4) != 0)
            }
            return r
        }
    }

    /// Solo la fecha y si es un cambio local, sin leer el cuerpo.
    static func meta(_ clave: String) -> (fecha: Date, local: Bool)? {
        conBase { (db: OpaquePointer) -> (fecha: Date, local: Bool)? in
            var r: (fecha: Date, local: Bool)?
            ejecuta(db, "SELECT fecha, local FROM respuestas WHERE clave = ?", [clave]) { st in
                r = (columnaFecha(st, 0) ?? .distantPast, sqlite3_column_int(st, 1) != 0)
            }
            return r
        }
    }

    static func existe(_ clave: String) -> Bool { meta(clave) != nil }

    static func claves(empezandoPor prefijo: String) -> [String] {
        conBase { (db: OpaquePointer) -> [String]? in
            var lista: [String] = []
            ejecuta(db, "SELECT clave FROM respuestas WHERE substr(clave, 1, ?) = ?", [prefijo.count, prefijo]) { st in
                if let c = columnaTexto(st, 0) { lista.append(c) }
            }
            return lista
        } ?? []
    }

    static func borra(_ clave: String) {
        _ = conBase { (db: OpaquePointer) -> Bool? in ejecuta(db, "DELETE FROM respuestas WHERE clave = ?", [clave]) }
    }

    /// «Borrar datos locales»: la copia, no la cola (lo que no ha salido todavía no se tira sin preguntar).
    static func borraRespuestas() {
        _ = conBase { (db: OpaquePointer) -> Bool? in
            ejecuta(db, "DELETE FROM respuestas")
            return ejecuta(db, "VACUUM")   // que no quede nada en las páginas libres del fichero
        }
    }

    // MARK: la cola

    /// Apunta un cambio para mandarlo al volver la red. Un PUT (el estado entero) se junta con el pendiente de la
    /// misma ruta: solo cuenta el último, y conserva la `base` del primero.
    @discardableResult
    static func encola(metodo: String, ruta: String, cuerpo: Data?, cabeceras: [String: String] = [:],
                       base: Data? = nil) -> Bool {
        let metodo = metodo.uppercased()
        let fecha = Date().timeIntervalSince1970
        let hecho = conBase({ (db: OpaquePointer) -> Bool? in
            inserta(db, metodo: metodo, ruta: ruta, cuerpo: cuerpo, cabeceras: cabeceras, fecha: fecha, base: base)
        }) ?? false
        if hecho { return true }
        return alBuzon(metodo: metodo, ruta: ruta, cuerpo: cuerpo, cabeceras: cabeceras, fecha: fecha)
    }

    private static func inserta(_ db: OpaquePointer, metodo: String, ruta: String, cuerpo: Data?,
                                cabeceras: [String: String], fecha: Double, base: Data?) -> Bool {
        let cab = (try? JSONSerialization.data(withJSONObject: cabeceras)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        if metodo == "PUT" {
            var previo: Int64?
            ejecuta(db, "SELECT id FROM cola WHERE metodo = 'PUT' AND ruta = ? AND estado = 'pendiente' ORDER BY id DESC LIMIT 1",
                    [ruta]) { st in
                previo = sqlite3_column_int64(st, 0)
            }
            if let previo {
                return ejecuta(db, "UPDATE cola SET cuerpo = ?, fecha = ?, rev = rev + 1 WHERE id = ?", [cuerpo, fecha, previo])
            }
        }
        return ejecuta(db, "INSERT INTO cola (metodo, ruta, cuerpo, cabeceras, fecha, base) VALUES (?, ?, ?, ?, ?, ?)",
                       [metodo, ruta, cuerpo, cab, fecha, base])
    }

    private static func alBuzon(metodo: String, ruta: String, cuerpo: Data?, cabeceras: [String: String],
                                fecha: Double) -> Bool {
        var carta: [String: Any] = ["metodo": metodo, "ruta": ruta, "cabeceras": cabeceras, "fecha": fecha]
        if let cuerpo { carta["cuerpo"] = cuerpo.base64EncodedString() }
        guard let datos = try? JSONSerialization.data(withJSONObject: carta) else { return false }
        try? FileManager.default.createDirectory(at: buzon, withIntermediateDirectories: true)
        let nombre = "\(Int64(fecha * 1000))-\(UUID().uuidString).json"
        do {
            try datos.write(to: buzon.appendingPathComponent(nombre), options: [.atomic, .completeFileProtectionUnlessOpen])
            return true
        } catch {
            return false
        }
    }

    /// Lo apuntado con el iPhone bloqueado, a la cola. Si sigue bloqueado, se queda para la próxima.
    static func importaBuzon() {
        let fm = FileManager.default
        guard let nombres = try? fm.contentsOfDirectory(atPath: buzon.path) else { return }
        for nombre in nombres.sorted() where nombre.hasSuffix(".json") {
            let url = buzon.appendingPathComponent(nombre)
            guard let datos = try? Data(contentsOf: url) else { return }
            guard let carta = (try? JSONSerialization.jsonObject(with: datos)) as? [String: Any],
                  let metodo = carta["metodo"] as? String, let ruta = carta["ruta"] as? String else {
                try? fm.removeItem(at: url)
                continue
            }
            let cuerpo = (carta["cuerpo"] as? String).flatMap { Data(base64Encoded: $0) }
            let cabeceras = (carta["cabeceras"] as? [String: String]) ?? [:]
            let fecha = (carta["fecha"] as? Double) ?? Date().timeIntervalSince1970
            let ok = conBase({ (db: OpaquePointer) -> Bool? in
                inserta(db, metodo: metodo, ruta: ruta, cuerpo: cuerpo, cabeceras: cabeceras, fecha: fecha, base: nil)
            }) ?? false
            guard ok else { return }
            try? fm.removeItem(at: url)
        }
    }

    static func cambios() -> [Cambio] {
        conBase { (db: OpaquePointer) -> [Cambio]? in
            var lista: [Cambio] = []
            let sql = "SELECT id, metodo, ruta, cuerpo, cabeceras, fecha, intentos, estado, error, base, proximo, rev FROM cola ORDER BY id"
            ejecuta(db, sql) { st in
                let cab = columnaTexto(st, 4).flatMap { $0.data(using: .utf8) }
                    .flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: String] } ?? [:]
                lista.append(Cambio(id: sqlite3_column_int64(st, 0),
                                    metodo: columnaTexto(st, 1) ?? "",
                                    ruta: columnaTexto(st, 2) ?? "",
                                    cuerpo: columnaDatos(st, 3),
                                    cabeceras: cab,
                                    fecha: columnaFecha(st, 5) ?? Date(),
                                    intentos: Int(sqlite3_column_int(st, 6)),
                                    estado: Estado(rawValue: columnaTexto(st, 7) ?? "") ?? .pendiente,
                                    error: columnaTexto(st, 8),
                                    base: columnaDatos(st, 9),
                                    proximo: columnaFecha(st, 10),
                                    rev: Int(sqlite3_column_int(st, 11))))
            }
            return lista
        } ?? []
    }

    static func numeroPendientes() -> Int {
        conBase { (db: OpaquePointer) -> Int? in
            var n = 0
            ejecuta(db, "SELECT COUNT(*) FROM cola WHERE estado = 'pendiente'") { st in
                n = Int(sqlite3_column_int64(st, 0))
            }
            return n
        } ?? 0
    }

    static func actualiza(_ id: Int64, estado: Estado, intentos: Int, error: String?, proximo: Date?) {
        let valores: [Any?] = [estado.rawValue, intentos, error, proximo?.timeIntervalSince1970, id]
        _ = conBase { (db: OpaquePointer) -> Bool? in
            ejecuta(db, "UPDATE cola SET estado = ?, intentos = ?, error = ?, proximo = ? WHERE id = ?", valores)
        }
    }

    /// Enviado: fuera de la cola, salvo que mientras salía se le juntara otro PUT (entonces sale otra vez).
    static func borraCambio(_ id: Int64, rev: Int) {
        _ = conBase { (db: OpaquePointer) -> Bool? in ejecuta(db, "DELETE FROM cola WHERE id = ? AND rev = ?", [id, rev]) }
    }

    static func descarta(_ id: Int64) {
        _ = conBase { (db: OpaquePointer) -> Bool? in ejecuta(db, "DELETE FROM cola WHERE id = ?", [id]) }
    }

    static func reintenta(_ id: Int64) {
        _ = conBase { (db: OpaquePointer) -> Bool? in
            ejecuta(db, "UPDATE cola SET estado = 'pendiente', intentos = 0, error = NULL, proximo = NULL WHERE id = ?", [id])
        }
    }

    static var ultimaSincronizacion: Date? {
        get {
            let t = Almacen.defaults.double(forKey: "localSincro")
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set { Almacen.defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: "localSincro") }
    }

    // MARK: lo apuntado sin red, ya pintado

    /// Una marca que espera en la cola se ve ya en la copia de /api/state y /api/hoy (las pantallas sin red) y en hoy.json
    /// (el widget). Es la misma marca idempotente que mandará la cola, así que no puede contradecirla.
    static func apuntaMarca(dia: String, habito: String, hecho: Bool) {
        let cEstado = clave("GET", "/api/state")
        if let r = lee(cEstado), var estado = (try? JSONSerialization.jsonObject(with: r.cuerpo)) as? [String: Any] {
            var log = (estado["log"] as? [String: Any]) ?? [:]
            var hechos = Set((log[dia] as? [String]) ?? [])
            if hecho { hechos.insert(habito) } else { hechos.remove(habito) }
            log[dia] = hechos.isEmpty ? nil : hechos.sorted()
            estado["log"] = log
            if let d = try? JSONSerialization.data(withJSONObject: estado) {
                guarda(cEstado, cuerpo: d, tipo: r.tipo, version: r.version, fecha: Date(), local: r.local, forzar: true)
            }
        }
        let cHoy = clave("GET", "/api/hoy")
        if let r = lee(cHoy), var hoy = (try? JSONSerialization.jsonObject(with: r.cuerpo)) as? [String: Any],
           (hoy["hoy"] as? String) == dia, let habitos = hoy["habitos"] as? [[String: Any]] {
            hoy["habitos"] = habitos.map { h -> [String: Any] in
                guard (h["id"] as? String) == habito else { return h }
                var nuevo = h
                nuevo["hecho"] = hecho
                return nuevo
            }
            if let d = try? JSONSerialization.data(withJSONObject: hoy) {
                guarda(cHoy, cuerpo: d, tipo: r.tipo, version: r.version, fecha: Date(), local: r.local, forzar: true)
                Almacen.guardaHoy(d)
                return
            }
        }
        // bloqueado (sin base): al menos el widget
        if var h = Almacen.leeHoy(), h.hoy == dia, let i = h.habitos.firstIndex(where: { $0.id == habito }) {
            h.habitos[i].hecho = hecho
            if let d = try? JSONEncoder().encode(h) { Almacen.guardaHoy(d) }
        }
    }
}
