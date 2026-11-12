import Foundation

enum Config {
    static let web = URL(string: "https://todo.yagotg.dev")!

    /// SideStore renombra la app group al firmar con un Apple ID gratis (group.dev.yagotg.hoy.<EQUIPO>) y ya no lo
    /// apunta en ALTAppGroups. Se busca en este orden: el perfil de firma de este bundle (la app y cada extensión
    /// llevan el suyo), ALTAppGroups (AltStore), el equipo que SideStore mete en el bundle id y, si nada, el original.
    static let grupo: String = {
        let base = "group.dev.yagotg.hoy"
        let delPerfil = Firma.grupos()
        if let g = delPerfil.first(where: { $0.hasPrefix(base) }) ?? delPerfil.first { return g }
        if let g = (Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String])?.first { return g }
        if let id = Bundle.main.bundleIdentifier, id.hasPrefix("dev.yagotg.hoy.") {
            let equipo = id.dropFirst("dev.yagotg.hoy.".count).split(separator: ".").first.map(String.init) ?? ""
            if equipo.count == 10, equipo.allSatisfy({ $0.isUppercase || $0.isNumber }) { return base + "." + equipo }
        }
        return base
    }()
}

/// Lo que dice embedded.mobileprovision: un plist XML dentro de una firma CMS, que se puede recortar a mano.
enum Firma {
    static func grupos() -> [String] {
        derechos()["com.apple.security.application-groups"] as? [String] ?? []
    }

    /// Los permisos con los que se firmó de verdad (SideStore quita los que la cuenta gratis no admite).
    static func derechos() -> [String: Any] {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let datos = try? Data(contentsOf: url),
              let inicio = datos.range(of: Data("<?xml".utf8)),
              let fin = datos.range(of: Data("</plist>".utf8), in: inicio.lowerBound..<datos.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: datos[inicio.lowerBound..<fin.upperBound],
                                                                       format: nil) as? [String: Any],
              let derechos = plist["Entitlements"] as? [String: Any] else { return [:] }
        return derechos
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
