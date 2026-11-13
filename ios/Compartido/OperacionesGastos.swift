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
            return false
        }
        return true
    }
}
