import SwiftUI
import UIKit

// La apariencia elegida (paleta, acento, letra, esquinas, fondo, modo) y el orden de las secciones. El catálogo es el
// mismo que usa la web (GET /apariencia.json, con copia en el bundle) y lo elegido se guarda en el servidor
// (/api/apariencia): cambiarlo en la web o en Tom cambia los dos. Compila en la app y en el widget (que solo lee los
// colores ya resueltos que deja la app en el app group).

struct Catalogo: Codable {
    var version: Int?
    var defecto: Eleccion
    /// Los temas (al estilo monkeytype): base + acento + letras + esquinas + fondo + modo. Desde el catálogo v2.
    var temas: [TemaCat]?
    var sugerencias: Sugerencias?
    /// Solo por compatibilidad con el catálogo v1: ya no se usan.
    var paletas: [PaletaCat]?
    var acentos: [AcentoCat]?
    var fuentes: [FuenteCat]
    var esquinas: [EsquinasCat]
    var fondos: [FondoCat]
    var fijos: Fijos

    struct TemaCat: Codable, Identifiable, Hashable {
        var id: String
        var nombre: String
        var vibra: String?
        var base: String
        var acento: String
        var fuente: String
        var titulos: String?
        var esquinas: String
        var fondo: String
        var modo: String?
    }

    struct Sugerencias: Codable, Hashable {
        var acento: [String]
        var base: [String]
    }

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

    func tema(_ id: String) -> TemaCat? { temas?.first { $0.id == id } }
    func fuente(_ id: String) -> FuenteCat? { fuentes.first { $0.id == id } }
}

/// Lo elegido: un tema (id, o "propio" si se ha tocado algo después) y sus valores. base y acento son "#RRGGBB".
struct Eleccion: Codable, Equatable {
    var tema: String = "hormigon"
    var modo: String = "sistema"
    var base: String = "#F2F2F2"
    var acento: String = "#4E7A62"
    var fuente: String = "instrument"
    var titulos: String = "instrument"
    var esquinas: String = "suaves"
    var fondo: String = "sutil"

    init() {}

    /// Tolerante: lo guardado con el formato de antes (paleta + acento por id) cae en los valores por defecto.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Eleccion()
        tema = (try? c.decodeIfPresent(String.self, forKey: .tema)) ?? nil ?? d.tema
        modo = (try? c.decodeIfPresent(String.self, forKey: .modo)) ?? nil ?? d.modo
        let b = (try? c.decodeIfPresent(String.self, forKey: .base)) ?? nil
        base = b.flatMap { Oklch.esHex($0) ? $0 : nil } ?? d.base
        let a = (try? c.decodeIfPresent(String.self, forKey: .acento)) ?? nil
        acento = a.flatMap { Oklch.esHex($0) ? $0 : nil } ?? d.acento
        fuente = (try? c.decodeIfPresent(String.self, forKey: .fuente)) ?? nil ?? d.fuente
        titulos = (try? c.decodeIfPresent(String.self, forKey: .titulos)) ?? nil ?? fuente
        esquinas = (try? c.decodeIfPresent(String.self, forKey: .esquinas)) ?? nil ?? d.esquinas
        fondo = (try? c.decodeIfPresent(String.self, forKey: .fondo)) ?? nil ?? d.fondo
    }

    /// Los siete valores de un tema.
    init(tema t: Catalogo.TemaCat, modo: String? = nil) {
        tema = t.id
        self.modo = modo ?? t.modo ?? "sistema"
        base = t.base
        acento = t.acento
        fuente = t.fuente
        titulos = t.titulos ?? t.fuente
        esquinas = t.esquinas
        fondo = t.fondo
    }
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
