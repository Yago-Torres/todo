import Foundation

struct APIError: LocalizedError {
    let mensaje: String
    var errorDescription: String? { mensaje }
}

/// Peticiones nativas: el service token pasa Cloudflare Access y el bearer, la contraseña de la app.
enum API {
    static func peticion(_ ruta: String, metodo: String = "GET", json: Any? = nil) throws -> URLRequest {
        guard let claves = Almacen.claves else { throw APIError(mensaje: "Faltan las claves: abre Hoy para configurarlo") }
        return try peticion(ruta, metodo: metodo, json: json, claves: claves)
    }

    static func peticion(_ ruta: String, metodo: String = "GET", json: Any? = nil, claves: Claves) throws -> URLRequest {
        guard let url = URL(string: ruta, relativeTo: Config.web)?.absoluteURL else {
            throw APIError(mensaje: "Ruta no válida: \(ruta)")
        }
        var p = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        p.httpMethod = metodo
        p.setValue(claves.cfId, forHTTPHeaderField: "CF-Access-Client-Id")
        p.setValue(claves.cfSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
        p.setValue("Bearer \(claves.pass)", forHTTPHeaderField: "Authorization")
        p.setValue("application/json", forHTTPHeaderField: "Accept")
        if let json {
            p.httpBody = try JSONSerialization.data(withJSONObject: json)
            p.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return p
    }

    @discardableResult
    static func datos(_ ruta: String, metodo: String = "GET", json: Any? = nil) async throws -> Data {
        try await manda(try peticion(ruta, metodo: metodo, json: json))
    }

    private static func manda(_ p: URLRequest) async throws -> Data {
        let resultado: (Data, URLResponse)
        do {
            resultado = try await URLSession.shared.data(for: p)
        } catch {
            throw APIError(mensaje: "Sin conexión con el servidor: \(error.localizedDescription)")
        }
        let (datos, respuesta) = resultado
        guard let http = respuesta as? HTTPURLResponse else { throw APIError(mensaje: "Respuesta rara del servidor") }
        // con un service token malo, Access redirige a su login (200 en HTML de otro host)
        if let host = http.url?.host, host != Config.web.host {
            throw APIError(mensaje: "Cloudflare Access no acepta el service token (CF-Access-Client-Id/Secret)")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(mensaje: detalle(datos) ?? "Error \(http.statusCode) del servidor")
        }
        return datos
    }

    /// El "detail" de FastAPI: un texto, o una lista de errores de validación.
    private static func detalle(_ datos: Data) -> String? {
        guard let objeto = try? JSONSerialization.jsonObject(with: datos) as? [String: Any],
              let d = objeto["detail"] else { return nil }
        if let s = d as? String { return s }
        if let lista = d as? [[String: Any]] {
            let textos = lista.compactMap { $0["msg"] as? String }
            if !textos.isEmpty { return textos.joined(separator: "; ") }
        }
        return String(describing: d)
    }

    static func hoy() async throws -> Hoy {
        let crudo = try await datos("/api/hoy")
        let hoy = try decodifica(crudo)
        Almacen.guardaHoy(crudo)
        return hoy
    }

    /// Para «Probar y guardar»: prueba unas claves sin guardarlas todavía.
    static func prueba(_ claves: Claves) async throws -> Hoy {
        let crudo = try await manda(try peticion("/api/hoy", claves: claves))
        return try decodifica(crudo)
    }

    private static func decodifica(_ datos: Data) throws -> Hoy {
        do {
            return try JSONDecoder().decode(Hoy.self, from: datos)
        } catch {
            throw APIError(mensaje: "No entiendo lo que devuelve /api/hoy")
        }
    }

    static func marca(habito: String, hecho: Bool, dia: String = Fecha.hoy()) async throws {
        try await datos("/api/marca", metodo: "POST", json: ["dia": dia, "id": habito, "hecho": hecho] as [String: Any])
    }

    static func tarea(_ texto: String, due: String? = nil, hora: String? = nil) async throws {
        var json: [String: Any] = ["t": texto]
        if let due { json["due"] = due }
        if let hora { json["hora"] = hora }
        try await datos("/api/tarea", metodo: "POST", json: json)
    }

    // MARK: gastos (por el proxy /api/gastos/* de todo, con las mismas claves)

    /// POST /api/gasto de gastos. `cat` es el id o el nombre («Comer fuera»); sin ella, gastos la adivina por la nota.
    /// Devuelve el texto que compone el servidor (el mismo de la notificación del atajo, con los avisos de presupuesto).
    @discardableResult
    static func apuntaGasto(importe: Double, nota: String? = nil, cat: String? = nil, src: String = "siri") async throws -> String {
        guard importe.isFinite, importe > 0 else { throw APIError(mensaje: "El importe tiene que ser mayor que cero") }
        var json: [String: Any] = ["importe": (importe * 100).rounded() / 100, "src": src]
        if let nota = nota?.trimmingCharacters(in: .whitespacesAndNewlines), !nota.isEmpty { json["nota"] = nota }
        if let cat = cat?.trimmingCharacters(in: .whitespacesAndNewlines), !cat.isEmpty { json["cat"] = cat }
        let crudo = try await datos("/api/gastos/gasto", metodo: "POST", json: json)
        let objeto = try? JSONSerialization.jsonObject(with: crudo) as? [String: Any]
        return (objeto?["texto"] as? String) ?? "Gasto apuntado"
    }

    /// Las categorías del ciclo (GET /api/gastos/resumen). Se guardan para Siri sin red.
    static func categoriasGasto() async throws -> [CategoriaGasto] {
        let crudo = try await datos("/api/gastos/resumen")
        guard let objeto = try JSONSerialization.jsonObject(with: crudo) as? [String: Any],
              let cats = objeto["cats"] as? [[String: Any]] else {
            throw APIError(mensaje: "No entiendo lo que devuelve /api/gastos/resumen")
        }
        let lista = cats.compactMap { c -> CategoriaGasto? in
            guard let id = c["id"] as? String, !id.isEmpty else { return nil }
            return CategoriaGasto(id: id, n: (c["n"] as? String) ?? id)
        }
        if let guardado = try? JSONEncoder().encode(lista) { Almacen.defaults.set(guardado, forKey: CategoriaGasto.clave) }
        return lista
    }

    // MARK: leer luego

    /// Desde la hoja de compartir: todo guarda la nota al momento y el bot la resume después (POST /api/leer/pendiente).
    @discardableResult
    static func guardaParaLeer(url: String, titulo: String? = nil) async throws -> String {
        var json: [String: Any] = ["url": url]
        if let titulo = titulo?.trimmingCharacters(in: .whitespacesAndNewlines), !titulo.isEmpty { json["titulo"] = titulo }
        let crudo = try await datos("/api/leer/pendiente", metodo: "POST", json: json)
        let objeto = try? JSONSerialization.jsonObject(with: crudo) as? [String: Any]
        return (objeto?["texto"] as? String) ?? "Guardado en Leer luego"
    }

    static func estado() async throws -> [String: Any] {
        let crudo = try await datos("/api/state")
        guard let objeto = try JSONSerialization.jsonObject(with: crudo) as? [String: Any] else {
            throw APIError(mensaje: "No entiendo lo que devuelve /api/state")
        }
        return objeto
    }
}

struct CategoriaGasto: Codable, Hashable {
    static let clave = "categoriasGasto"

    var id: String
    var n: String

    /// Las últimas que se bajaron, para cuando no hay red.
    static var guardadas: [CategoriaGasto] {
        guard let datos = Almacen.defaults.data(forKey: clave) else { return [] }
        return (try? JSONDecoder().decode([CategoriaGasto].self, from: datos)) ?? []
    }
}
