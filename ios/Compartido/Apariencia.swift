import SwiftUI
import UIKit

// La apariencia elegida (paleta, acento, letra, esquinas, fondo, modo) y el orden de las secciones. El catálogo es el
// mismo que usa la web (GET /apariencia.json, con copia en el bundle) y lo elegido se guarda en el servidor
// (/api/apariencia): cambiarlo en la web o en Tom cambia los dos. Compila en la app y en el widget (que solo lee los
// colores ya resueltos que deja la app en el app group).

struct Catalogo: Codable {
    var version: Int?
    var defecto: Eleccion
    var paletas: [PaletaCat]
    var acentos: [AcentoCat]
    var fuentes: [FuenteCat]
    var esquinas: [EsquinasCat]
    var fondos: [FondoCat]
    var fijos: Fijos

    struct Tonos: Codable, Hashable {
        var fondo: String
        var carta: String
        var carta_luz: String?
        var carta2: String
        var texto: String
        var suave: String
        var tenue: String
        var linea: String
        var dock: String
        var dock_texto: String
        var ascii: String
    }

    struct PaletaCat: Codable, Identifiable, Hashable {
        var id: String
        var nombre: String
        var familia: String
        var descripcion: String?
        var claro: Tonos
        var oscuro: Tonos
        var acento: String
    }

    struct TonoAcento: Codable, Hashable {
        var acento: String
        var texto: String
        var suave: String
    }

    struct AcentoCat: Codable, Identifiable, Hashable {
        var id: String
        var nombre: String
        var claro: TonoAcento
        var oscuro: TonoAcento
        var gota: String
        var gota_texto: String
    }

    struct FuenteCat: Codable, Identifiable, Hashable {
        var id: String
        var nombre: String
        var familia_ios: String?
    }

    struct EsquinasCat: Codable, Identifiable, Hashable {
        var id: String
        var nombre: String
        var carta: Double
        var boton: Double
        var celda: Double
    }

    struct FondoCat: Codable, Identifiable, Hashable {
        var id: String
        var nombre: String
        var intensidad: Double
    }

    struct TonosFijos: Codable, Hashable {
        var peligro: String
        var peligro_suave: String?
        var aviso: String
        var aviso_suave: String?
    }

    struct Fijos: Codable, Hashable {
        var claro: TonosFijos
        var oscuro: TonosFijos
    }

    func paleta(_ id: String) -> PaletaCat? { paletas.first { $0.id == id } }
    func acento(_ id: String) -> AcentoCat? { acentos.first { $0.id == id } }
}

/// Lo elegido. `acento` vacío = el de la paleta.
struct Eleccion: Codable, Equatable {
    var modo: String = "sistema"
    var paleta: String = "hormigon"
    var acento: String = "salvia"
    var fuente: String = "instrument"
    var esquinas: String = "suaves"
    var fondo: String = "sutil"
}

/// El orden y lo oculto de cada pantalla ("app-hoy", "app-dock"…; las de la web van por ruta y las lleva calma.js).
struct Bloques: Codable, Equatable {
    var orden: [String] = []
    var ocultos: [String] = []

    /// Los ids de `todos` en el orden guardado (los nuevos, al final), sin los ocultos si `visibles`.
    func aplica(_ todos: [String], visibles: Bool = true) -> [String] {
        let conocidos = orden.filter(todos.contains)
        let nuevos = todos.filter { !conocidos.contains($0) }
        let lista = conocidos + nuevos
        return visibles ? lista.filter { !ocultos.contains($0) } : lista
    }
}

extension UIColor {
    /// "#RRGGBB", "#RGB" o "rgba(r, g, b, a)" (los colores del catálogo). Lo que no se entienda, gris.
    convenience init(css: String) {
        let s = css.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.hasPrefix("rgb") {
            let numeros = s.drop(while: { $0 != "(" }).dropFirst().prefix(while: { $0 != ")" })
                .split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
            let r = numeros.count > 0 ? numeros[0] : 128, g = numeros.count > 1 ? numeros[1] : 128
            let b = numeros.count > 2 ? numeros[2] : 128, a = numeros.count > 3 ? numeros[3] : 1
            self.init(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
            return
        }
        var h = s
        if h.hasPrefix("#") { h.removeFirst() }
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else {
            self.init(white: 0.5, alpha: 1)
            return
        }
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    /// Claro u oscuro según donde se pinte.
    static func dinamico(claro: String, oscuro: String) -> UIColor {
        let c = UIColor(css: claro), o = UIColor(css: oscuro)
        return UIColor { $0.userInterfaceStyle == .dark ? o : c }
    }
}

/// Los colores ya resueltos que la app deja en el app group para el widget y la Live Activity.
enum ColoresGuardados {
    static let clave = "apariencia.widget"

    /// {"claro": {token: css}, "oscuro": {token: css}}
    static func guarda(claro: [String: String], oscuro: [String: String]) {
        if let d = try? JSONEncoder().encode(["claro": claro, "oscuro": oscuro]) {
            Almacen.defaults.set(d, forKey: clave)
        }
    }

    private static func lee() -> [String: [String: String]] {
        guard let d = Almacen.defaults.data(forKey: clave),
              let r = try? JSONDecoder().decode([String: [String: String]].self, from: d) else { return [:] }
        return r
    }

    /// El token en claro u oscuro según el widget; sin nada guardado, `claro`/`oscuro` de respaldo.
    static func color(_ token: String, claro: String, oscuro: String) -> Color {
        let g = lee()
        return Color(uiColor: .dinamico(claro: g["claro"]?[token] ?? claro, oscuro: g["oscuro"]?[token] ?? oscuro))
    }

    /// Solo el valor oscuro (la Live Activity y los widgets de fondo oscuro).
    static func oscuro(_ token: String, _ respaldo: String) -> Color {
        Color(uiColor: UIColor(css: lee()["oscuro"]?[token] ?? respaldo))
    }
}
