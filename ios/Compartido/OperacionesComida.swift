import Foundation

// Cambios del estado de Comida (/api/comida/estado) como operaciones de la cola, igual que Gastos: se ven al momento en
// la copia local, funcionan sin red y Sincro los aplica sobre el estado fresco del servidor antes del PUT (así no pisan
// lo que cambió la web o el bot). Puro: solo diccionarios. Compila en la app y en el widget.
//
//   {op: "comida.tacha", id, si}                      ese ingrediente al carro (o fuera)
//   {op: "comida.pin", ing, cadena, pid}              el producto fijado a mano en esa cadena ("" = quitar el pin)
//   {op: "comida.variante", receta, linea, i, v}      la forma del ingrediente en esa línea de la receta ("" = la de por defecto)

enum OpsComida {
    private static func lista(_ x: Any?) -> [[String: Any]] { (x as? [[String: Any]]) ?? [] }
    private static func texto(_ d: [String: Any], _ k: String) -> String { (d[k] as? String) ?? "" }

    static func aplica(_ op: [String: Any], _ e: inout [String: Any], estricto: Bool) throws -> Bool {
        switch texto(op, "op") {
        case "comida.tacha":
            let id = texto(op, "id")
            guard !id.isEmpty else { return true }
            var t = (e["tachado"] as? [String: Any]) ?? [:]
            t[id] = (op["si"] as? Bool) == true ? true : nil
            e["tachado"] = t
        case "comida.pin":
            var ings = lista(e["ingredientes"])
            let id = texto(op, "ing"), cadena = texto(op, "cadena"), pid = texto(op, "pid")
            guard let k = ings.firstIndex(where: { texto($0, "id") == id }) else {
                if estricto { throw Operaciones.Rechazo("Ese ingrediente ya no está en Comida.") }
                return true
            }
            var pin = (ings[k]["pin"] as? [String: Any]) ?? [:]
            pin[cadena] = pid.isEmpty ? nil : pid
            ings[k]["pin"] = pin
            e["ingredientes"] = ings
        case "comida.variante":
            var recetas = lista(e["recetas"])
            let rid = texto(op, "receta"), ing = texto(op, "i"), v = texto(op, "v")
            let linea = (op["linea"] as? NSNumber)?.intValue ?? -1
            guard let k = recetas.firstIndex(where: { texto($0, "id") == rid }) else {
                if estricto { throw Operaciones.Rechazo("Esa receta ya no está en el menú.") }
                return true
            }
            var lineas = lista(recetas[k]["ing"])
            // la línea por su posición si sigue siendo ese ingrediente; si no, la primera con él
            let j = lineas.indices.contains(linea) && texto(lineas[linea], "i") == ing
                ? linea : lineas.firstIndex { texto($0, "i") == ing }
            guard let j else {
                if estricto { throw Operaciones.Rechazo("Esa receta ya no lleva ese ingrediente.") }
                return true
            }
            lineas[j]["v"] = v.isEmpty ? nil : v
            recetas[k]["ing"] = lineas
            e["recetas"] = recetas
        default:
            return false
        }
        return true
    }
}
