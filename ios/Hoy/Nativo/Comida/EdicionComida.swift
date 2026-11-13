import Foundation
import SwiftUI

// Lo que la web de Comida cambia y Tom no tenía: tachar la compra, fijar el producto de cada cadena, la variante de un
// ingrediente en una receta (operaciones de la cola sobre /api/comida/estado, OpsComida: sin red también) y el editor
// de ingredientes (POST /ingrediente y /variante, como la web; sin red se quedan en la cola y salen al volver).

/// Un producto que ha encontrado una cadena para un ingrediente (GET /api/comida/candidatos).
struct ProductoCadena: Decodable, Identifiable, Hashable {
    var cadena = ""
    var pid = ""
    var nombre = ""
    var marca: String?
    var categoria: String?
    var precio = 0.0
    var porUnidad = 0.0
    var unidad = ""

    var id: String { "\(cadena)|\(pid)" }

    enum CodingKeys: String, CodingKey {
        case cadena, pid, nombre, marca, categoria, precio, unidad
        case porUnidad = "por_unidad"
    }
}

/// Lo que propone Open Food Facts para un nombre (GET /api/comida/rellena).
struct PropuestaNutricion: Decodable, Identifiable, Hashable {
    var n = ""
    var marca: String?
    var fuente = ""
    var n100: Valores

    var id: String { "\(n)|\(fuente)" }

    struct Valores: Decodable, Hashable {
        var kcal: Double?
        var prot: Double?
        var hc: Double?
        var grasa: Double?
        var fibra: Double?
    }
}

extension DatosComida {
    /// Apunta la operación, la pinta y la manda. Devuelve true si se ha quedado en la cola (sin red).
    @discardableResult
    func opera(_ op: [String: Any]) async throws -> Bool {
        guard let id = Operaciones.encola(Operaciones.comida, op) else {
            throw APIError(mensaje: "No he podido guardar el cambio en el iPhone. Desbloquéalo y vuelve a probar.")
        }
        refrescaLocal()
        await Sincro.vacia()
        refrescaLocal()
        guard let c = Local.cambio(id) else { return false }
        if c.estado != .pendiente { throw APIError(mensaje: c.error ?? "El servidor de comida no ha aceptado el cambio.") }
        return true
    }

    func tacha(_ id: String, _ si: Bool) async throws -> Bool {
        try await opera(["op": "comida.tacha", "id": id, "si": si, "resumen": si ? "Tachar de la compra" : "Volver a la compra"])
    }

    func fija(_ ing: String, cadena: String, pid: String, nombre: String) async throws -> Bool {
        try await opera(["op": "comida.pin", "ing": ing, "cadena": cadena, "pid": pid,
                         "resumen": pid.isEmpty ? "Quitar el producto fijado de \(nombre)" : "Fijar el producto de \(nombre) en \(cadena.capitalized)"])
    }

    func ponVariante(receta: String, linea: Int, ing: String, v: String, nombre: String) async throws -> Bool {
        try await opera(["op": "comida.variante", "receta": receta, "linea": linea, "i": ing, "v": v,
                         "resumen": "Cambiar la forma de \(nombre) en una receta"])
    }

    /// POST /api/comida/ingrediente o /variante. Devuelve el aviso si se ha quedado en la cola.
    func guarda(_ ruta: String, _ cuerpo: [String: Any]) async throws -> String? {
        let r = try await API.escribeOEncola("/api/comida/\(ruta)", json: cuerpo)
        await carga()
        return r == nil ? "Guardado en el iPhone: se enviará en cuanto haya conexión." : nil
    }

    func candidatos(_ ing: String) async throws -> [ProductoCadena] {
        let q = ing.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ing
        let d = try await API.datos("/api/comida/candidatos?ing=\(q)")
        struct R: Decodable { var candidatos: [ProductoCadena] }
        return try JSONDecoder().decode(R.self, from: d).candidatos
    }

    func rellena(_ nombre: String) async throws -> [PropuestaNutricion] {
        let q = nombre.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? nombre
        let d = try await API.datos("/api/comida/rellena?n=\(q)")
        struct R: Decodable { var candidatos: [PropuestaNutricion] }
        return try JSONDecoder().decode(R.self, from: d).candidatos
    }
}
