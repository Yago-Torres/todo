import Foundation

// Las llamadas de Documentos que no son JSON: bajar el fichero y subirlo en crudo (el fichero va en el cuerpo y lo
// demás en la cabecera X-Doc, fuera de la URL y de los registros del servidor).

extension API {
    /// Una petición con cuerpo binario (o sin él) y las mismas comprobaciones que el resto: sin red, Cloudflare Access
    /// y errores del servidor con su mensaje.
    static func mandaCrudo(_ p: URLRequest, subiendo cuerpo: Data? = nil) async throws -> (datos: Data, respuesta: HTTPURLResponse) {
        let resultado: (Data, URLResponse)
        do {
            if let cuerpo {
                resultado = try await URLSession.shared.upload(for: p, from: cuerpo)
            } else {
                resultado = try await URLSession.shared.data(for: p)
            }
        } catch {
            let cancelada = (error as? URLError)?.code == .cancelled || error is CancellationError
            throw APIError(mensaje: "Sin conexión con el servidor: \(error.localizedDescription)", sinRed: !cancelada)
        }
        guard let http = resultado.1 as? HTTPURLResponse else { throw APIError(mensaje: "Respuesta rara del servidor") }
        if let host = http.url?.host, host != Config.web.host {
            throw APIError(mensaje: "Cloudflare Access no acepta el service token (CF-Access-Client-Id/Secret)")
        }
        guard (200..<300).contains(http.statusCode) else {
            let tipo = http.value(forHTTPHeaderField: "Content-Type") ?? ""
            var mensaje = "Error \(http.statusCode) del servidor"
            if let o = (try? JSONSerialization.jsonObject(with: resultado.0)) as? [String: Any], let d = o["detail"] as? String {
                mensaje = d
            }
            throw APIError(mensaje: mensaje, sinRed: esCaida(http.statusCode, tipo: tipo))
        }
        return (resultado.0, http)
    }

    /// GET /api/documentos/<id>/fichero
    static func ficheroDocumento(_ id: String) async throws -> (datos: Data, tipo: String) {
        var p = try peticion("/api/documentos/\(id)/fichero")
        p.timeoutInterval = 90
        p.setValue("*/*", forHTTPHeaderField: "Accept")
        let (datos, http) = try await mandaCrudo(p)
        return (datos, http.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream")
    }

    /// El valor de X-Doc: el JSON con encodeURIComponent, como lo manda la web.
    static func cabeceraDocumento(_ meta: [String: Any]) -> String {
        let json = (try? JSONSerialization.data(withJSONObject: meta)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        var permitidos = CharacterSet.alphanumerics
        permitidos.insert(charactersIn: "-_.!~*'()")
        return json.addingPercentEncoding(withAllowedCharacters: permitidos) ?? "%7B%7D"
    }

    /// POST /api/documentos con el fichero en crudo. Devuelve el documento nuevo (con `aviso` si apuntó renovarlo).
    static func subeDocumento(_ datos: Data, tipo: String, meta: [String: Any]) async throws -> [String: Any] {
        var p = try peticion("/api/documentos", metodo: "POST")
        p.timeoutInterval = 120
        p.setValue(tipo, forHTTPHeaderField: "Content-Type")
        p.setValue(cabeceraDocumento(meta), forHTTPHeaderField: "X-Doc")
        let (respuesta, _) = try await mandaCrudo(p, subiendo: datos)
        return ((try? JSONSerialization.jsonObject(with: respuesta)) as? [String: Any]) ?? [:]
    }
}
