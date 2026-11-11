import Foundation

enum Config {
    static let web = URL(string: "https://todo.yagotg.dev")!

    /// SideStore renombra las app groups al firmar con un Apple ID gratis y deja el id real en ALTAppGroups.
    static var grupo: String {
        (Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String])?.first ?? "group.dev.yagotg.hoy"
    }
}

/// Las tres claves que se pegan la primera vez. Nunca en el código: el repo es público.
struct Claves: Codable, Equatable {
    var cfId: String
    var cfSecret: String
    var pass: String
}

enum Almacen {
    static let defaults: UserDefaults = UserDefaults(suiteName: Config.grupo) ?? .standard

    /// El contenedor compartido con el widget; sin app group (firma rara) cae en la carpeta propia.
    private static var carpeta: URL {
        if let c = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Config.grupo) { return c }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private static var ficheroClaves: URL { carpeta.appendingPathComponent("claves.json") }
    private static var ficheroHoy: URL { carpeta.appendingPathComponent("hoy.json") }

    private static func escribe(_ datos: Data, en url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // hasta el primer desbloqueo tras reiniciar: el widget y las tareas de fondo leen con la pantalla bloqueada
        try? datos.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static var claves: Claves? {
        get {
            guard let datos = try? Data(contentsOf: ficheroClaves) else { return nil }
            return try? JSONDecoder().decode(Claves.self, from: datos)
        }
        set {
            if let newValue, let datos = try? JSONEncoder().encode(newValue) {
                escribe(datos, en: ficheroClaves)
            } else {
                try? FileManager.default.removeItem(at: ficheroClaves)
            }
        }
    }

    static func guardaHoy(_ datos: Data) {
        escribe(datos, en: ficheroHoy)
    }

    static func leeHoy() -> Hoy? {
        guard let datos = try? Data(contentsOf: ficheroHoy) else { return nil }
        return try? JSONDecoder().decode(Hoy.self, from: datos)
    }
}
