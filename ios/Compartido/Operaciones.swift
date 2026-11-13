import Foundation

// Cambios con intención para la cola de «sin conexión».
//
// En vez de guardar una copia del estado entero (que, mandada tarde, pisaría lo que el bot o la web cambiaron mientras
// tanto), se guarda QUÉ quieres hacer: {op: "habito.edita", id, cambios}, {op: "plan.pon", id, dia, si},
// {op: "gasto.borra", id}… Van en la misma cola de Local (método «OP», ruta = el estado que tocan), así que salen en
// orden con las marcas, las tareas y los gastos apuntados sin red.
//
// - Al apuntarla se aplica al momento sobre la copia local (la pantalla cambia ya y sigue cambiada tras cerrar la app).
// - Al salir (Hoy/Sincro.swift) se lee el estado FRESCO del servidor, se aplica la operación encima y se guarda con
//   su X-Version; en un 409 se vuelve a leer y a aplicar. Lo que hizo otro entre medias no se pisa.
// - La copia que se pinta es siempre «lo último del servidor + lo que aún no ha salido»: la base del servidor se guarda
//   aparte («BASE GET /api/state») y encima se reaplican los pendientes. Descartar uno lo quita de la vista sin red.
//
// Las marcas, tareas, documentos y gastos que ya iban a la cola como peticiones normales también se pintan así
// (`aplica` los entiende), y sus ids provisionales «tmp:…» se cambian por el real al llegar (Local.alias).
//
// La parte de arriba (MARK: lógica) es pura: solo diccionarios. Compila en la app y en el widget.

enum Operaciones {
    struct Rechazo: LocalizedError {
        let mensaje: String
        init(_ mensaje: String) { self.mensaje = mensaje }
        var errorDescription: String? { mensaje }
    }

    static let state = "/api/state"
    static let hoy = "/api/hoy"
    static let bandeja = "/api/bandeja"
    static let documentos = "/api/documentos"
    static let basesGastos = ["/api/gastos", "/api/gastos-aitana"]
    /// Cuántos hábitos admite el servidor (clean() corta en 20).
    static let maximoHabitos = 20

    /// Las copias que pueden llevar cambios pendientes encima.
    static let afectables: Set<String> = Set([state, hoy, bandeja, documentos] + basesGastos.map { $0 + "/estado" })

    /// Un cambio de la cola, ya leído.
    struct Pendiente {
        var metodo: String
        /// Sin query.
        var ruta: String
        var cuerpo: [String: Any]
        var cabeceras: [String: String] = [:]

        var op: String { (cuerpo["op"] as? String) ?? "" }
    }

    // MARK: lógica

    /// Las copias (rutas de GET) que cambian con este pendiente.
    static func rutas(_ p: Pendiente) -> [String] {
        switch p.metodo {
        case "OP":
            if p.ruta == state { return [state, hoy] }
            if p.ruta.hasPrefix("/api/comida/") { return [] }
            return [p.ruta]
        case "POST":
            if p.ruta == "/api/marca" { return [state, hoy] }
            if p.ruta == "/api/tarea" || p.ruta.hasPrefix("/api/tarea/") || p.ruta == "/api/leido" { return [bandeja] }
            if p.ruta == documentos || p.ruta.hasPrefix(documentos + "/") { return [documentos] }
            for b in basesGastos where p.ruta == b + "/gasto" || p.ruta == b + "/ingreso" { return [b + "/estado"] }
            return []
        default:
            return []
        }
    }

    /// Aplica el pendiente sobre `copia` (lo que devuelve GET `ruta`).
    /// - estricto: al mandarlo al servidor. Si lo que cambia ya no existe, lanza Rechazo con un texto para la persona.
    ///   Sin él (al pintar en local) eso se ignora.
    /// - alias: el id de ahora de un id provisional o viejo (Local.alias).
    static func aplica(_ p: Pendiente, en ruta: String, _ copia: inout [String: Any], estricto: Bool = false,
                       alias: @escaping (String) -> String = { $0 }) throws {
        switch (p.metodo, ruta) {
        case ("OP", state):
            try aplicaEstado(p.cuerpo, &copia, estricto: estricto)
        case ("OP", hoy):
            aplicaHoy(p.cuerpo, &copia)
        case ("OP", _) where ruta.hasSuffix("/estado"):
            try aplicaGastos(p.cuerpo, &copia, estricto: estricto)
        case ("POST", state) where p.ruta == "/api/marca":
            marcaEnEstado(p.cuerpo, &copia)
        case ("POST", hoy) where p.ruta == "/api/marca":
            marcaEnHoy(p.cuerpo, &copia)
        case ("POST", bandeja):
            tareaEnBandeja(p, &copia, alias: alias)
        case ("POST", documentos):
            documentoEnLista(p, &copia, alias: alias)
        case ("POST", _) where ruta.hasSuffix("/estado"):
            apunteEnGastos(p, &copia)
        default:
            break
        }
    }

    /// Pone los `cambios` encima de `d`. Un NSNull quita la clave. Cualquier campo vale: el servidor (clean()) decide.
    static func mezcla(_ d: [String: Any], _ cambios: [String: Any]) -> [String: Any] {
        var fuera = d
        for (k, v) in cambios {
            if v is NSNull { fuera[k] = nil } else { fuera[k] = v }
        }
        return fuera
    }

    private static func idDe(_ d: [String: Any]) -> String? {
        if let s = d["id"] as? String { return s }
        if let n = d["id"] as? NSNumber { return n.stringValue }
        return nil
    }

    private static func lista(_ x: Any?) -> [[String: Any]] { (x as? [[String: Any]]) ?? [] }

    // MARK: hábitos y plan (/api/state)

    static func aplicaEstado(_ op: [String: Any], _ e: inout [String: Any], estricto: Bool) throws {
        var habits = lista(e["habits"])
        let id = (op["id"] as? String) ?? ""
        let existe = habits.contains { idDe($0) == id }
        switch (op["op"] as? String) ?? "" {
        case "habito.crea":
            var campos = (op["campos"] as? [String: Any]) ?? [:]
            let nuevo = (campos["id"] as? String) ?? id
            guard !nuevo.isEmpty else { throw Rechazo("El hábito nuevo no tiene id.") }
            campos["id"] = nuevo
            if let i = habits.firstIndex(where: { idDe($0) == nuevo }) {
                habits[i] = mezcla(habits[i], campos)   // ya llegó otra vez: queda igual
            } else {
                if estricto, habits.count >= maximoHabitos {
                    throw Rechazo("Ya tienes \(maximoHabitos) hábitos, el máximo. Borra uno y vuelve a crear este.")
                }
                habits.append(campos)
            }
            e["habits"] = habits
        case "habito.edita":
            guard let i = habits.firstIndex(where: { idDe($0) == id }) else {
                if estricto { throw Rechazo("Ese hábito ya no existe: lo han borrado desde otro sitio.") }
                return
            }
            habits[i] = mezcla(habits[i], (op["cambios"] as? [String: Any]) ?? [:])
            habits[i]["id"] = id
            e["habits"] = habits
        case "habito.borra":
            guard existe else { return }
            e["habits"] = habits.filter { idDe($0) != id }
            // lo hecho y lo planificado de ese hábito se va con él (clean() del servidor hace lo mismo)
            for k in ["log", "plan"] {
                guard var m = e[k] as? [String: Any] else { continue }
                for (dia, v) in m {
                    guard var l = v as? [String] else { continue }
                    l.removeAll { $0 == id }
                    m[dia] = l.isEmpty ? nil : l
                }
                e[k] = m
            }
            if var sesion = e["sesion"] as? [String: Any] {
                for (dia, v) in sesion {
                    guard var d = v as? [String: Any] else { continue }
                    d[id] = nil
                    sesion[dia] = d.isEmpty ? nil : d
                }
                e["sesion"] = sesion
            }
        case "habito.ordena":
            let ids = (op["ids"] as? [String]) ?? []
            let primero = ids.compactMap { i in habits.first { idDe($0) == i } }
            let resto = habits.filter { !ids.contains(idDe($0) ?? "") }
            e["habits"] = primero + resto
        case "plan.pon":
            let dia = (op["dia"] as? String) ?? ""
            let si = (op["si"] as? Bool) ?? true
            guard !dia.isEmpty else { return }
            if si, !existe {
                if estricto { throw Rechazo("Ese hábito ya no existe: lo han borrado desde otro sitio.") }
                return
            }
            var plan = (e["plan"] as? [String: Any]) ?? [:]
            var l = (plan[dia] as? [String]) ?? []
            if si { if !l.contains(id) { l.append(id) } } else { l.removeAll { $0 == id } }
            plan[dia] = l.isEmpty ? nil : l
            e["plan"] = plan
        default:
            if estricto { throw Rechazo("Esta versión de Tom no sabe enviar «\((op["op"] as? String) ?? "")».") }
        }
    }

    /// Lo mismo en la copia de /api/hoy (lo que pintan Hoy y el widget), que el servidor calcula a partir del estado.
    static func aplicaHoy(_ op: [String: Any], _ h: inout [String: Any]) {
        var habitos = lista(h["habitos"])
        let id = (op["id"] as? String) ?? ""
        switch (op["op"] as? String) ?? "" {
        case "habito.crea":
            let campos = (op["campos"] as? [String: Any]) ?? [:]
            let nuevo = (campos["id"] as? String) ?? id
            guard !nuevo.isEmpty, !habitos.contains(where: { idDe($0) == nuevo }) else { return }
            habitos.append(["id": nuevo, "n": (campos["n"] as? String) ?? nuevo, "c": (campos["c"] as? String) ?? "#888888",
                            "plan": false, "hecho": false, "racha": 0])
        case "habito.edita":
            let cambios = (op["cambios"] as? [String: Any]) ?? [:]
            guard let i = habitos.firstIndex(where: { idDe($0) == id }) else { return }
            if let n = cambios["n"] as? String { habitos[i]["n"] = n }
            if let c = cambios["c"] as? String { habitos[i]["c"] = c }
        case "habito.borra":
            habitos.removeAll { idDe($0) == id }
        case "habito.ordena":
            let ids = (op["ids"] as? [String]) ?? []
            let primero = ids.compactMap { i in habitos.first { idDe($0) == i } }
            habitos = primero + habitos.filter { !ids.contains(idDe($0) ?? "") }
        case "plan.pon":
            guard (op["dia"] as? String) == (h["hoy"] as? String),
                  let i = habitos.firstIndex(where: { idDe($0) == id }) else { return }
            habitos[i]["plan"] = (op["si"] as? Bool) ?? true
        default:
            return
        }
        h["habitos"] = habitos
    }

    static func marcaEnEstado(_ m: [String: Any], _ e: inout [String: Any]) {
        guard let dia = m["dia"] as? String, let id = m["id"] as? String else { return }
        let hecho = (m["hecho"] as? Bool) ?? true
        var log = (e["log"] as? [String: Any]) ?? [:]
        var l = (log[dia] as? [String]) ?? []
        if hecho { if !l.contains(id) { l.append(id) } } else { l.removeAll { $0 == id } }
        log[dia] = l.isEmpty ? nil : l
        e["log"] = log
    }

    static func marcaEnHoy(_ m: [String: Any], _ h: inout [String: Any]) {
        guard let dia = m["dia"] as? String, dia == (h["hoy"] as? String), let id = m["id"] as? String else { return }
        let hecho = (m["hecho"] as? Bool) ?? true
        var habitos = lista(h["habitos"])
        guard let i = habitos.firstIndex(where: { idDe($0) == id }) else { return }
        if ((habitos[i]["hecho"] as? Bool) ?? false) != hecho {
            habitos[i]["hecho"] = hecho
            let racha = (habitos[i]["racha"] as? NSNumber)?.intValue ?? 0
            habitos[i]["racha"] = max(0, racha + (hecho ? 1 : -1))
        }
        h["habitos"] = habitos
    }

    // MARK: gastos (/api/gastos/estado y /api/gastos-aitana/estado)

    static func aplicaGastos(_ op: [String: Any], _ e: inout [String: Any], estricto: Bool) throws {
        var gastos = lista(e["gastos"])
        let id = (op["id"] as? String) ?? ""
        switch (op["op"] as? String) ?? "" {
        case "gasto.edita":
            guard let i = gastos.firstIndex(where: { idDe($0) == id }) else {
                if estricto { throw Rechazo("Ese gasto ya no está: lo han borrado desde otro sitio.") }
                return
            }
            gastos[i] = mezcla(gastos[i], (op["cambios"] as? [String: Any]) ?? [:])
            gastos[i]["id"] = id
            e["gastos"] = gastos
        case "gasto.borra":
            e["gastos"] = gastos.filter { idDe($0) != id }
        case "gasto.restaura":
            guard let g = op["gasto"] as? [String: Any], let gid = idDe(g) else { return }
            if !gastos.contains(where: { idDe($0) == gid }) { gastos.append(g) }
            e["gastos"] = gastos
        case "presupuesto.pon":
            var cats = lista(e["cats"])
            let valores = (op["valores"] as? [String: Any]) ?? [:]
            for (cat, v) in valores {
                guard let valor = (v as? NSNumber)?.doubleValue else { continue }
                guard let i = cats.firstIndex(where: { idDe($0) == cat }) else {
                    if estricto { throw Rechazo("La categoría «\(cat)» ya no existe: la han quitado desde otro sitio.") }
                    continue
                }
                cats[i]["presu"] = max(0, valor)
            }
            e["cats"] = cats
        default:
            // reglas de categoría y recurrentes (Compartido/OperacionesGastos.swift)
            if try ReglasGastos.aplica(op, &e, estricto: estricto) { return }
            if estricto { throw Rechazo("Esta versión de Tom no sabe enviar «\((op["op"] as? String) ?? "")».") }
        }
    }

    /// Un gasto o ingreso apuntado sin red (POST /gasto, /ingreso), ya en la lista.
    static func apunteEnGastos(_ p: Pendiente, _ e: inout [String: Any]) {
        let a = p.cuerpo
        guard let id = a["id"] as? String else { return }
        let ingreso = p.ruta.hasSuffix("/ingreso")
        let clave = ingreso ? "ingresos" : "gastos"
        var l = lista(e[clave])
        guard !l.contains(where: { idDe($0) == id }) else { return }
        var nuevo: [String: Any] = ["id": id, "dia": (a["dia"] as? String) ?? "", "importe": a["importe"] ?? 0,
                                    "cat": (a["cat"] as? String) ?? "", "nota": (a["nota"] as? String) ?? ""]
        if ingreso { nuevo["tipo"] = (a["tipo"] as? String) ?? "extra" } else {
            nuevo["src"] = (a["src"] as? String) ?? "web"
            nuevo["comercio"] = ""
            for k in ["viaje", "reparto"] { if let v = a[k] as? String { nuevo[k] = v } }   // saldar un viaje compartido
        }
        l.append(nuevo)
        e[clave] = l
    }

    // MARK: tareas (/api/bandeja)

    static func tareaEnBandeja(_ p: Pendiente, _ b: inout [String: Any], alias: @escaping (String) -> String) {
        let a = p.cuerpo
        var tareas = lista(b["tareas"])
        // la tarea puede estar en la copia con el id de antes o con el de ahora
        func indice(_ crudo: String) -> Int? {
            let ahora = alias(crudo)
            return tareas.firstIndex { idDe($0) == crudo || idDe($0) == ahora }
        }
        switch p.ruta {
        case "/api/tarea":
            guard let tmp = p.cabeceras["x-tom-tmp"], indice(tmp) == nil, let t = a["t"] as? String else { return }
            var nueva: [String: Any] = ["id": alias(tmp), "t": t, "grupo": "Pendientes", "fija": false]
            if let due = a["due"] as? String { nueva["due"] = due }
            if let hora = a["hora"] as? String { nueva["hora"] = hora }
            tareas.append(nueva)
        case "/api/tarea/edita":
            guard let id = a["id"] as? String, let i = indice(id) else { return }
            if let t = a["t"] as? String { tareas[i]["t"] = t }
            let due = (a["due"] as? String) ?? ""
            tareas[i]["due"] = due
            tareas[i]["hora"] = due.isEmpty ? "" : ((a["hora"] as? String) ?? "")
            tareas[i]["id"] = alias(id)
        case "/api/tarea/hecha":
            guard let id = a["id"] as? String, (a["hecha"] as? Bool) != false, let i = indice(id) else { return }
            tareas.remove(at: i)
        case "/api/tarea/borra":
            guard let id = a["id"] as? String, let i = indice(id) else { return }
            tareas.remove(at: i)
        case "/api/leido":
            guard let ruta = a["ruta"] as? String else { return }
            b["leer"] = lista(b["leer"]).filter { ($0["ruta"] as? String) != ruta }
            return
        default:
            return
        }
        b["tareas"] = tareas
    }

    // MARK: documentos (/api/documentos)

    /// Los datos de un documento de la cabecera X-Doc (JSON con encodeURIComponent).
    static func metaDocumento(_ cabeceras: [String: String]) -> [String: Any] {
        guard let x = cabeceras["x-doc"]?.removingPercentEncoding, let d = x.data(using: .utf8) else { return [:] }
        return ((try? JSONSerialization.jsonObject(with: d)) as? [String: Any]) ?? [:]
    }

    static func documentoEnLista(_ p: Pendiente, _ l: inout [String: Any], alias: @escaping (String) -> String) {
        var docs = lista(l["docs"])
        func indice(_ crudo: String) -> Int? {
            let ahora = alias(crudo)
            return docs.firstIndex { idDe($0) == crudo || idDe($0) == ahora }
        }
        let partes = p.ruta.split(separator: "/").map(String.init)   // api, documentos, <id>, [borra]
        if p.ruta == documentos {
            guard let tmp = p.cabeceras["x-tom-tmp"], indice(tmp) == nil else { return }
            let meta = metaDocumento(p.cabeceras)
            let nombre = (meta["nombre"] as? String) ?? ""
            let ext = (nombre as NSString).pathExtension.lowercased()
            let id = alias(tmp)
            var n = (meta["n"] as? String) ?? ""
            if n.isEmpty { n = (nombre as NSString).deletingPathExtension }
            docs.append(["id": id, "n": n.isEmpty ? "Documento" : n, "cat": (meta["cat"] as? String) ?? "otros",
                         "titular": (meta["titular"] as? String) ?? "", "caduca": (meta["caduca"] as? String) ?? "",
                         "notas": (meta["notas"] as? String) ?? "", "fichero": "\(id).\(ext.isEmpty ? "pdf" : ext)",
                         "subido": p.cabeceras["x-tom-dia"] ?? ""])
        } else if partes.count == 3 {
            guard let i = indice(partes[2]) else { return }
            for k in ["n", "cat", "titular", "caduca", "notas"] {
                if let v = p.cuerpo[k] as? String { docs[i][k] = v }
            }
        } else if partes.count == 4, partes[3] == "borra" {
            guard let i = indice(partes[2]) else { return }
            docs.remove(at: i)
        } else {
            return
        }
        l["docs"] = docs
    }
}

// MARK: con la base local

extension Operaciones {
    /// Dónde se guarda lo último que dijo el servidor de `ruta`, sin nada pendiente encima.
    static func claveBase(_ ruta: String) -> String { "BASE " + Local.clave("GET", ruta) }

    static func pendiente(_ c: Local.Cambio) -> Pendiente {
        let cuerpo = (c.cuerpo.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
        return Pendiente(metodo: c.metodo, ruta: c.rutaSinQuery, cuerpo: cuerpo, cabeceras: c.cabeceras)
    }

    /// Los de la cola que aún esperan salir, en orden. Sin el cuerpo de los documentos (pueden ser megas).
    static func pendientes(excepto: Int64? = nil) -> [Pendiente] {
        Local.cambios().filter { $0.estado == .pendiente && $0.id != excepto }.map { c -> Pendiente in
            if c.rutaSinQuery == documentos { return Pendiente(metodo: c.metodo, ruta: c.rutaSinQuery, cuerpo: [:], cabeceras: c.cabeceras) }
            return pendiente(c)
        }
    }

    private static func hayEstadoEntero(_ ruta: String) -> Bool {
        Local.cambios().contains { $0.estado == .pendiente && $0.metodo == "PUT" && $0.rutaSinQuery == ruta }
    }

    /// `base` con los pendientes que tocan `ruta` encima. tocado = alguno la cambió.
    static func vista(_ base: Data, ruta: String, _ lista: [Pendiente]) -> (datos: Data, tocado: Bool) {
        let suyos = lista.filter { rutas($0).contains(ruta) }
        guard !suyos.isEmpty, var objeto = (try? JSONSerialization.jsonObject(with: base)) as? [String: Any] else {
            return (base, false)
        }
        for p in suyos { try? aplica(p, en: ruta, &objeto, alias: Local.alias) }
        guard let datos = try? JSONSerialization.data(withJSONObject: objeto) else { return (base, false) }
        return (datos, true)
    }

    /// Lo que llega fresco del servidor para `ruta`: se guarda como base y se le ponen encima los cambios que aún no
    /// han salido. Devuelve lo que hay que pintar (y lo deja guardado como copia).
    @discardableResult
    static func llega(_ ruta: String, _ datos: Data, tipo: String = "application/json", version: String? = nil,
                      fecha: Date = Date()) -> Data {
        let clave = Local.clave("GET", ruta)
        let soloRuta = ruta.components(separatedBy: "?").first ?? ruta
        guard afectables.contains(soloRuta) else {
            Local.guarda(clave, cuerpo: datos, tipo: tipo, version: version, fecha: fecha)
            return datos
        }
        Local.guarda(claveBase(ruta), cuerpo: datos, tipo: tipo, version: version, fecha: fecha, forzar: true)
        // un PUT del estado entero espera en la cola (Entreno, la web): su copia manda, como antes
        if hayEstadoEntero(soloRuta), let r = Local.lee(clave), r.local { return r.cuerpo }
        let (v, tocado) = vista(datos, ruta: soloRuta, pendientes())
        Local.guarda(clave, cuerpo: v, tipo: tipo, version: version, fecha: fecha, local: tocado, forzar: true)
        return v
    }

    /// Vuelve a montar la copia de `ruta` (base + pendientes) tras apuntar, mandar o descartar un cambio.
    /// `nuevo`: con un PUT del estado entero en la cola no hay base fiable, y solo se pone este encima de la copia.
    static func recalcula(_ ruta: String, nuevo: Pendiente? = nil) {
        let clave = Local.clave("GET", ruta)
        if hayEstadoEntero(ruta) {
            guard let nuevo, let r = Local.lee(clave),
                  var objeto = (try? JSONSerialization.jsonObject(with: r.cuerpo)) as? [String: Any] else { return }
            try? aplica(nuevo, en: ruta, &objeto, alias: Local.alias)
            if let d = try? JSONSerialization.data(withJSONObject: objeto) {
                Local.guarda(clave, cuerpo: d, tipo: r.tipo, version: r.version, fecha: Date(), local: true, forzar: true)
            }
            return
        }
        let base: Local.Respuesta
        if let b = Local.lee(claveBase(ruta)) {
            base = b
        } else if let r = Local.lee(clave) {
            // la primera vez: lo que hay es lo mejor que tenemos del servidor
            base = r
            Local.guarda(claveBase(ruta), cuerpo: r.cuerpo, tipo: r.tipo, version: r.version, fecha: r.fecha, forzar: true)
        } else {
            return
        }
        let (v, tocado) = vista(base.cuerpo, ruta: ruta, pendientes())
        Local.guarda(clave, cuerpo: v, tipo: base.tipo, version: base.version, fecha: tocado ? Date() : base.fecha,
                     local: tocado, forzar: true)
        if ruta == hoy { Almacen.guardaHoy(v) }
    }

    static func recalcula(para c: Local.Cambio) {
        let p = pendiente(c)
        for r in rutas(p) { recalcula(r) }
    }

    /// Ya en el servidor: lo que hizo se pasa a la base (para que no parpadee hasta la próxima descarga) y se
    /// recalcula la copia. `respuesta` es el estado que devolvió el PUT de una operación (la base nueva).
    static func alMandar(_ c: Local.Cambio, respuesta: Data?, version: String?) {
        let p = pendiente(c)
        var restantes = rutas(p)
        if c.metodo == "OP", let respuesta, restantes.contains(c.rutaSinQuery) {
            // el estado entero tal como quedó en el servidor: la base nueva
            llega(c.rutaSinQuery, respuesta, version: version)
            restantes.removeAll { $0 == c.rutaSinQuery }
        }
        for ruta in restantes {
            if let b = Local.lee(claveBase(ruta)),
               var objeto = (try? JSONSerialization.jsonObject(with: b.cuerpo)) as? [String: Any] {
                try? aplica(p, en: ruta, &objeto, alias: Local.alias)
                if let d = try? JSONSerialization.data(withJSONObject: objeto) {
                    Local.guarda(claveBase(ruta), cuerpo: d, tipo: b.tipo, version: b.version, fecha: b.fecha, forzar: true)
                }
            }
            recalcula(ruta)
        }
    }

    /// Apunta una operación y la pinta ya en la copia local. Devuelve su id en la cola (nil si no se pudo guardar).
    @discardableResult
    static func encola(_ ruta: String, _ op: [String: Any]) -> Int64? {
        guard let cuerpo = try? JSONSerialization.data(withJSONObject: op),
              let id = Local.encolaOperacion(ruta: ruta, cuerpo: cuerpo) else { return nil }
        let p = Pendiente(metodo: "OP", ruta: ruta, cuerpo: op)
        for r in rutas(p) { recalcula(r, nuevo: p) }
        return id
    }

    /// Tareas y documentos cambian de id al guardarse: si ya hay uno de los suyos en la cola, lo nuevo va detrás.
    static func esperaEnCola(_ ruta: String) -> Bool {
        let soloRuta = ruta.components(separatedBy: "?").first ?? ruta
        let familia = rutas(Pendiente(metodo: "POST", ruta: soloRuta, cuerpo: [:]))
        guard familia == [bandeja] || familia == [documentos] else { return false }
        return Local.cambios().contains { c in
            c.estado == .pendiente && rutas(Pendiente(metodo: c.metodo, ruta: c.rutaSinQuery, cuerpo: [:])) == familia
        }
    }

    /// Una petición normal que acaba de ir a la cola (escribeOEncola): a la copia local.
    static func anota(metodo: String, ruta: String, json: [String: Any], cabeceras: [String: String] = [:]) {
        let p = Pendiente(metodo: metodo.uppercased(), ruta: ruta.components(separatedBy: "?").first ?? ruta,
                          cuerpo: json, cabeceras: cabeceras)
        for r in rutas(p) { recalcula(r, nuevo: p) }
    }

    /// Cambia los ids provisionales o viejos de una petición de la cola por los de ahora (ruta y "id" del cuerpo).
    static func resuelveIds(ruta: String, cuerpo: Data?) -> (ruta: String, cuerpo: Data?) {
        let partes = ruta.components(separatedBy: "?")
        let camino = partes[0].split(separator: "/", omittingEmptySubsequences: false).map { s -> String in
            let t = String(s)
            return t.isEmpty || t == "api" ? t : Local.alias(t)
        }.joined(separator: "/")
        let nuevaRuta = camino + (partes.count > 1 ? "?" + partes.dropFirst().joined(separator: "?") : "")
        guard let cuerpo, var objeto = (try? JSONSerialization.jsonObject(with: cuerpo)) as? [String: Any],
              let id = objeto["id"] as? String else { return (nuevaRuta, cuerpo) }
        let ahora = Local.alias(id)
        guard ahora != id else { return (nuevaRuta, cuerpo) }
        objeto["id"] = ahora
        return (nuevaRuta, (try? JSONSerialization.data(withJSONObject: objeto)) ?? cuerpo)
    }
}
