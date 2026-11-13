import Foundation

/// Configurar → Diagnóstico → «Comprobar conexión»: lo que hace falta para que Tom funcione, paso a paso y con lo que
/// responde cada cosa, para mandar una captura si algo falla.
enum Diagnostico {
    @MainActor
    static func comprueba(_ claves: Claves) async -> [String] {
        let contenedor = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Config.grupo) != nil
        let perfil = Firma.grupos()
        var lineas = ["Bundle: \(Bundle.main.bundleIdentifier ?? "?")",
                      "Versión: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))",
                      "App group: \(Config.grupo) \(contenedor ? "✓" : "✗ sin acceso: el widget y «Leer luego» no verán las claves")",
                      "Perfil: \(perfil.isEmpty ? "sin grupos" : perfil.joined(separator: ", "))",
                      "Salud en la firma: \(Salud.firmadaConSalud ? "✓" : "✗ (SideStore la quitó)")",
                      "Claves: \(claves.cfId.isEmpty || claves.cfSecret.isEmpty ? "✗ falta el service token" : "✓ service token") · \(claves.pass.isEmpty ? "✗ falta la contraseña" : "✓ contraseña")",
                      "Red: \(Red.shared.hayRed ? "sí" : "no")",
                      "Cambios sin enviar: \(Local.numeroPendientes())"]
        // sin caché ni cookies: lo que contesta el servidor ahora mismo
        let sesion = URLSession(configuration: .ephemeral)
        defer { sesion.finishTasksAndInvalidate() }
        let pasos: [(String, String)] = [
            ("API", "/api/hoy"),        // Access (service token) + la contraseña (Bearer)
            ("Apariencia", "/api/apariencia"),
        ]
        for (nombre, ruta) in pasos {
            guard let peticion = try? API.peticion(ruta, claves: claves) else {
                lineas.append("\(nombre): no se pudo montar la petición")
                continue
            }
            let inicio = Date()
            do {
                let (_, r) = try await sesion.data(for: peticion)
                let ms = Int(Date().timeIntervalSince(inicio) * 1000)
                let http = r as? HTTPURLResponse
                let host = http?.url?.host ?? "?"
                lineas.append("\(nombre): \(http?.statusCode ?? 0) de \(host) en \(ms) ms\(explica(http))")
            } catch {
                lineas.append("\(nombre): \(error.localizedDescription)")
            }
        }
        return lineas
    }

    /// Qué quiere decir una respuesta mala.
    private static func explica(_ http: HTTPURLResponse?) -> String {
        guard let http else { return "" }
        if let host = http.url?.host, host != Config.web.host { return " · Access no acepta el service token" }
        switch http.statusCode {
        case 200..<300: return " ✓"
        case 401, 403: return " · la contraseña no vale"
        case 502...530: return " · la Pi no contesta (Cloudflare llega, pero no hay nada detrás)"
        default: return ""
        }
    }
}
