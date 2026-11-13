import Foundation

// Reglas de categoría y recurrentes de Gastos: las operaciones de la cola que las cambian (sin red, como gasto.edita)
// y la misma normalización que el servidor (~/gastos/main.py: norma, encaja, patron), para que lo que se pinta en el
// iPhone sea lo que hará el servidor. Puro: solo diccionarios y cadenas. Compila en la app y en el widget.
//
//   {op: "regla.pon", regla: {id, txt, cat}}    crea o cambia (por id; si otra tiene el mismo texto, la sustituye)
//   {op: "regla.borra", id}
//   {op: "regla.ordena", ids}                   la prioridad (la primera que casa gana)
//   {op: "regla.rechaza", txt}                  esa palabra no se vuelve a proponer
//   {op: "regla.aplica", txt, cat}              los gastos que casan pasan a esa categoría
//   {op: "recurrente.marca", clave, estado}     si (confirmado) | no (ignorado) | "" (como lo detecte el servidor)
//
// Y lo que en la web se cambia con el PUT del estado entero (viajes, hucha, ingreso, día de cobro, ingresos), aquí
// también como operaciones (OpsGastos, abajo):
//
//   {op: "viaje.pon", viaje: {id, n, desde, hasta, presu, moneda, cambio, con}, lleva?, asigna?}
//        crea o cambia. lleva: true (al crearlo) se lleva los gastos sin viaje que son suyos, como POST /viaje
//        (que_viaje del servidor); asigna: [ids] los devuelve a él (deshacer un borrado)
//   {op: "viaje.borra", id}                     sus gastos vuelven al ciclo
//   {op: "viaje.asigna", ids, viaje}            esos gastos pasan a ese viaje ("" = al ciclo)
//   {op: "ajustes.pon", cambios: {ingreso?, dia_cobro?, hucha?}}
//   {op: "ingreso.edita", id, cambios}  {op: "ingreso.borra", id}  {op: "ingreso.restaura", ingreso}

enum ReglasGastos {
    /// «Café  ÑOÑO-12» → «cafe nono 12»: sin tildes, en minúsculas y por palabras (a-z, 0-9 y &), como `norma()`.
    static func norma(_ s: String) -> String {
        let plano = s.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES"))
        var palabras: [String] = []
        var actual = ""
        for u in plano.unicodeScalars {
            let v = u.value
            if (97...122).contains(v) || (48...57).contains(v) || v == 38 {
                actual.unicodeScalars.append(u)
            } else if !actual.isEmpty {
                palabras.append(actual)
                actual = ""
            }
        }
        if !actual.isEmpty { palabras.append(actual) }
        return palabras.joined(separator: " ")
    }

    static func concepto(comercio: String, nota: String) -> String { norma("\(comercio) \(nota)") }

    /// Por palabras enteras: «bar» casa con «Bar Pepe» y no con «Barbería».
    static func encaja(_ txt: String, comercio: String, nota: String) -> Bool {
        !txt.isEmpty && " \(concepto(comercio: comercio, nota: nota)) ".contains(" \(txt) ")
    }

    /// Las palabras que no distinguen nada (las mismas que NADA en el servidor).
    static let nada: Set<String> = ["compra", "tarj", "tarjeta", "pago", "recibo", "www", "com", "cargo", "adeudo", "bizum",
                                    "transf", "con", "del", "las", "los", "para", "por", "una", "uno", "unos", "sin", "que",
                                    "the", "and", "mas", "visa", "sl", "sa", "slu", "online", "app", "store", "shop",
                                    "tienda", "pedido", "ajuste", "restar"]

    /// La palabra que distingue un gasto: la primera con sentido del comercio (o, sin él, de la nota).
    static func patron(comercio: String, nota: String) -> String {
        let fuente = comercio.trimmingCharacters(in: .whitespaces).isEmpty ? nota : comercio
        return norma(fuente).split(separator: " ").map(String.init).first { w in
            w.count >= 3 && w.contains(where: { $0.isLetter }) && !nada.contains(w)
        } ?? ""
    }

    private static func lista(_ x: Any?) -> [[String: Any]] { (x as? [[String: Any]]) ?? [] }
    private static func texto(_ d: [String: Any], _ k: String) -> String { (d[k] as? String) ?? "" }

    /// Aplica una de las operaciones de arriba sobre el estado de gastos. false si no es suya.
    static func aplica(_ op: [String: Any], _ e: inout [String: Any], estricto: Bool) throws -> Bool {
        var reglas = lista(e["reglas"])
        switch (op["op"] as? String) ?? "" {
        case "regla.pon":
            let r = (op["regla"] as? [String: Any]) ?? [:]
            let id = texto(r, "id"), txt = String(norma(texto(r, "txt")).prefix(40)), cat = texto(r, "cat")
            guard !id.isEmpty, !txt.isEmpty, !cat.isEmpty else { throw Operaciones.Rechazo("La regla necesita un texto y una categoría.") }
            if estricto, !lista(e["cats"]).contains(where: { texto($0, "id") == cat }) {
                throw Operaciones.Rechazo("La categoría de la regla ya no existe: la han quitado desde otro sitio.")
            }
            let nueva: [String: Any] = ["id": id, "txt": txt, "cat": cat]
            if let i = reglas.firstIndex(where: { texto($0, "id") == id }) {
                reglas[i] = nueva
                reglas.removeAll { texto($0, "txt") == txt && texto($0, "id") != id }
            } else if let i = reglas.firstIndex(where: { texto($0, "txt") == txt }) {
                reglas[i] = nueva
            } else {
                reglas.append(nueva)
            }
            e["reglas"] = reglas
        case "regla.borra":
            let id = texto(op, "id")
            e["reglas"] = reglas.filter { texto($0, "id") != id }
        case "regla.ordena":
            let ids = (op["ids"] as? [String]) ?? []
            let primero = ids.compactMap { i in reglas.first { texto($0, "id") == i } }
            e["reglas"] = primero + reglas.filter { !ids.contains(texto($0, "id")) }
        case "regla.rechaza":
            let txt = norma(texto(op, "txt"))
            var no = (e["rechazadas"] as? [String]) ?? []
            if !txt.isEmpty, !no.contains(txt) { no.append(txt) }
            e["rechazadas"] = no
        case "regla.aplica":
            let txt = norma(texto(op, "txt")), cat = texto(op, "cat")
            guard !txt.isEmpty, !cat.isEmpty else { return true }
            var gastos = lista(e["gastos"])
            for i in gastos.indices where encaja(txt, comercio: texto(gastos[i], "comercio"), nota: texto(gastos[i], "nota")) {
                gastos[i]["cat"] = cat
            }
            e["gastos"] = gastos
        case "recurrente.marca":
            let clave = texto(op, "clave"), estado = texto(op, "estado")
            guard !clave.isEmpty else { return true }
            var marcas = (e["recurrentes"] as? [String: Any]) ?? [:]
            marcas[clave] = (estado == "si" || estado == "no") ? estado : nil
            e["recurrentes"] = marcas
        default:
            return try OpsGastos.aplica(op, &e, estricto: estricto)
        }
        return true
    }
}

/// Viajes, hucha, ajustes e ingresos de Gastos como operaciones de la cola (ver arriba). Puro.
enum OpsGastos {
    /// Los fijos se pagan de golpe: un gasto fijo en las fechas de un viaje no es del viaje (FIJOS del servidor).
    static let fijos: Set<String> = ["casa", "suscripciones"]
    /// Lo que suena a reserva de viaje (PISTAS_VIAJE del servidor).
    static let pistasViaje: Set<String> = ["booking", "airbnb", "hotel", "hostal", "vuelo", "vuelos", "ryanair", "vueling",
                                           "iberia", "easyjet", "aeropuerto", "aena", "expedia", "skyscanner", "edreams",
                                           "wizz", "transavia", "kiwi", "lastminute"]

    private static func lista(_ x: Any?) -> [[String: Any]] { (x as? [[String: Any]]) ?? [] }
    private static func texto(_ d: [String: Any], _ k: String) -> String { (d[k] as? String) ?? "" }
    private static func antes(_ dia: String, dias: Int) -> String {
        guard let d = Fecha.fecha(dia), let r = Calendar(identifier: .gregorian).date(byAdding: .day, value: -dias, to: d) else { return dia }
        return Fecha.dia(r)
    }

    private static func palabras(_ s: String) -> Set<String> {
        Set(ReglasGastos.norma(s).split(separator: " ").map(String.init))
    }

    /// El viaje de un gasto, como que_viaje() del servidor: el que nombra la nota, el que está en curso ese día (salvo
    /// fijos) o, si es una reserva, el único que viene por delante (desde 180 días antes). "" si ninguno.
    static func queViaje(_ g: [String: Any], _ viajes: [[String: Any]]) -> String {
        let t = palabras("\(texto(g, "comercio")) \(texto(g, "nota"))")
        let dia = texto(g, "dia"), cat = texto(g, "cat")
        for v in viajes where !palabras(texto(v, "n")).filter({ $0.count >= 4 }).isDisjoint(with: t) {
            return texto(v, "id")
        }
        for v in viajes where texto(v, "desde") <= dia && dia <= texto(v, "hasta") && !fijos.contains(cat) {
            return texto(v, "id")
        }
        if !t.isDisjoint(with: pistasViaje), cat != "super" {
            let delante = viajes.filter { v in
                dia <= texto(v, "hasta") && antes(texto(v, "desde"), dias: 180) <= dia
            }
            if delante.count == 1 { return texto(delante[0], "id") }
        }
        return ""
    }

    static func aplica(_ op: [String: Any], _ e: inout [String: Any], estricto: Bool) throws -> Bool {
        var viajes = lista(e["viajes"])
        switch texto(op, "op") {
        case "viaje.pon":
            var v = (op["viaje"] as? [String: Any]) ?? [:]
            let id = texto(v, "id")
            let n = texto(v, "n").trimmingCharacters(in: .whitespaces)
            guard !id.isEmpty, !n.isEmpty, !texto(v, "desde").isEmpty else {
                throw Operaciones.Rechazo("Un viaje necesita nombre y fechas.")
            }
            let desde = texto(v, "desde"), hasta = max(texto(v, "hasta").isEmpty ? desde : texto(v, "hasta"), desde)
            v["n"] = String(n.prefix(40)); v["desde"] = min(desde, hasta); v["hasta"] = hasta
            let nuevo = !viajes.contains { texto($0, "id") == id }
            if let i = viajes.firstIndex(where: { texto($0, "id") == id }) { viajes[i] = v } else { viajes.append(v) }
            e["viajes"] = viajes
            var gastos = lista(e["gastos"])
            let asigna = Set((op["asigna"] as? [String]) ?? [])
            for i in gastos.indices {
                if asigna.contains(texto(gastos[i], "id")) {
                    gastos[i]["viaje"] = id
                } else if nuevo, (op["lleva"] as? Bool) == true, texto(gastos[i], "viaje").isEmpty,
                          !queViaje(gastos[i], [v]).isEmpty {
                    gastos[i]["viaje"] = id
                }
            }
            e["gastos"] = gastos
        case "viaje.borra":
            let id = texto(op, "id")
            e["viajes"] = viajes.filter { texto($0, "id") != id }
            var gastos = lista(e["gastos"])
            for i in gastos.indices where texto(gastos[i], "viaje") == id { gastos[i]["viaje"] = "" }
            e["gastos"] = gastos
        case "viaje.asigna":
            let ids = Set((op["ids"] as? [String]) ?? []), viaje = texto(op, "viaje")
            if estricto, !viaje.isEmpty, !viajes.contains(where: { texto($0, "id") == viaje }) {
                throw Operaciones.Rechazo("Ese viaje ya no está: lo han borrado desde otro sitio.")
            }
            var gastos = lista(e["gastos"])
            for i in gastos.indices where ids.contains(texto(gastos[i], "id")) { gastos[i]["viaje"] = viaje }
            e["gastos"] = gastos
        case "ajustes.pon":
            var a = (e["ajustes"] as? [String: Any]) ?? [:]
            let cambios = (op["cambios"] as? [String: Any]) ?? [:]
            for (k, v) in cambios where ["ingreso", "dia_cobro", "hucha"].contains(k) { a[k] = v }
            if let h = (a["hucha"] as? NSNumber)?.doubleValue {
                // la hucha empieza a contar el día que se pone; sin hucha, no hay «desde»
                if h <= 0 { a["hucha_desde"] = "" }
                else if texto(a, "hucha_desde").isEmpty { a["hucha_desde"] = Fecha.hoy() }
            }
            e["ajustes"] = a
        case "ingreso.edita":
            var l = lista(e["ingresos"])
            let id = texto(op, "id")
            guard let i = l.firstIndex(where: { texto($0, "id") == id }) else {
                if estricto { throw Operaciones.Rechazo("Ese ingreso ya no está: lo han borrado desde otro sitio.") }
                return true
            }
            l[i] = Operaciones.mezcla(l[i], (op["cambios"] as? [String: Any]) ?? [:])
            l[i]["id"] = id
            e["ingresos"] = l
        case "ingreso.borra":
            let id = texto(op, "id")
            e["ingresos"] = lista(e["ingresos"]).filter { texto($0, "id") != id }
        case "ingreso.restaura":
            guard let x = op["ingreso"] as? [String: Any], !texto(x, "id").isEmpty else { return true }
            var l = lista(e["ingresos"])
            if !l.contains(where: { texto($0, "id") == texto(x, "id") }) { l.append(x) }
            e["ingresos"] = l
        default:
            // los de Comida (/api/comida/estado) llegan por el mismo camino: Compartido/OperacionesComida.swift
            return try OpsComida.aplica(op, &e, estricto: estricto)
        }
        return true
    }
}
