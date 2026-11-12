import SwiftUI
import UIKit

/// El estilo de las pantallas nativas, en un solo sitio, con los nombres de los tokens de ~/estilo/calma.css. Los valores
/// por defecto son «Hormigón» + «Salvia»; los de verdad salen de Aspecto (catálogo + lo elegido). Las vistas nativas solo
/// usan lo de aquí, nunca un color o un tamaño suelto.
struct Paleta {
    /// Cada token con su valor en claro y en oscuro ("#hex" o "rgba(…)", como en el catálogo). El color se resuelve
    /// una vez al crearlo, no en cada acceso.
    struct Token {
        let claro: String
        let oscuro: String
        let color: Color

        init(claro: String, oscuro: String) {
            self.claro = claro
            self.oscuro = oscuro
            color = Color(uiColor: .dinamico(claro: claro, oscuro: oscuro))
        }
    }

    var fondo = Token(claro: "#F2F2F2", oscuro: "#111111")
    var carta = Token(claro: "#FFFFFF", oscuro: "#1B1B1B")
    var cartaLuz = Token(claro: "#FFFFFF", oscuro: "#212121")
    var carta2 = Token(claro: "#E8E8E8", oscuro: "#252525")
    var texto = Token(claro: "#161616", oscuro: "#EDEDED")
    var suave = Token(claro: "#6A6A6A", oscuro: "#9A9A9A")
    var tenue = Token(claro: "#A3A3A3", oscuro: "#6E6E6E")
    var linea = Token(claro: "#DEDEDE", oscuro: "#2F2F2F")
    var acento = Token(claro: "#4E7A62", oscuro: "#9FD3B4")
    var acentoTexto = Token(claro: "#FFFFFF", oscuro: "#14301F")
    var acentoSuave = Token(claro: "#E2EFE7", oscuro: "#24372C")
    var peligro = Token(claro: "#D64545", oscuro: "#F2726B")
    var aviso = Token(claro: "#B97A0E", oscuro: "#E8B04A")
    /// La barra de abajo: grafito en los dos temas, con la gota lima de la sección actual.
    var dock = Token(claro: "#262626", oscuro: "#262626")
    var dockTexto = Token(claro: "#B0B0B0", oscuro: "#B0B0B0")
    var gota = Token(claro: "#A8D5BA", oscuro: "#A8D5BA")
    var gotaTexto = Token(claro: "#173325", oscuro: "#173325")
    /// Los caracteres del fondo (calma.js): tenues, y los densos en acento.
    var ascii = Token(claro: "rgba(20, 20, 20, .08)", oscuro: "rgba(237, 237, 237, .06)")
}

/// Familias de letra (nombre de familia). nil = la del sistema (SF Pro). Instrument Sans va empaquetada (variable,
/// Hoy/InstrumentSans.ttf, en UIAppFonts): los pesos salen de .weight(). Para otra, el .ttf en Hoy/, UIAppFonts y su
/// nombre aquí. Si no carga, SF Pro.
struct Fuentes {
    var texto: String? = "Instrument Sans"
    var titulo: String? = "Instrument Sans"
    var cifras: String? = "Instrument Sans"
    /// El diseño del sistema cuando no hay familia propia (.default, .rounded, .serif, .monospaced).
    var diseno: Font.Design = .default
}

struct Radios {
    var carta: Double = 12
    var boton: Double = 8
    var celda: Double = 6
}

struct Tema {
    var paleta = Paleta()
    var fuentes = Fuentes()
    var radios = Radios()
    /// La intensidad del fondo de caracteres (0 = apagado, 0,5 sutil, 1 normal, 1,6 más presente).
    var fondo: Double = 0.5

    /// El tema en uso: lo construye Aspecto con el catálogo y lo elegido (Configurar → Apariencia, o la web).
    /// Leerlo dentro de un body hace que la vista se repinte cuando cambia.
    static var actual: Tema { Aspecto.shared.tema }

    // MARK: colores (atajos)
    static var fondo: Color { actual.paleta.fondo.color }
    static var carta: Color { actual.paleta.carta.color }
    static var carta2: Color { actual.paleta.carta2.color }
    static var texto: Color { actual.paleta.texto.color }
    static var suave: Color { actual.paleta.suave.color }
    static var tenue: Color { actual.paleta.tenue.color }
    static var linea: Color { actual.paleta.linea.color }
    static var acento: Color { actual.paleta.acento.color }
    static var acentoTexto: Color { actual.paleta.acentoTexto.color }
    static var acentoSuave: Color { actual.paleta.acentoSuave.color }
    static var peligro: Color { actual.paleta.peligro.color }
    static var aviso: Color { actual.paleta.aviso.color }
    static var dock: Color { actual.paleta.dock.color }
    static var dockTexto: Color { actual.paleta.dockTexto.color }
    static var gota: Color { actual.paleta.gota.color }
    static var gotaTexto: Color { actual.paleta.gotaTexto.color }
    static var ascii: Color { actual.paleta.ascii.color }

    // MARK: medidas (las de calma.css)
    enum Radio {
        static var carta: CGFloat { Tema.actual.radios.carta }
        static var boton: CGFloat { Tema.actual.radios.boton }     // botones y campos
        static var celda: CGFloat { Tema.actual.radios.celda }
        static let pastilla: CGFloat = 999
        static var dock: CGFloat { min(22, Tema.actual.radios.carta + 8) }
    }

    enum Espacio {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    /// Los muelles de todo lo que se mueve en nativo: uno para cambiar de pantalla y otro para los toques.
    enum Muelle {
        static let pantalla = Animation.spring(response: 0.42, dampingFraction: 0.86)
        static let toque = Animation.spring(response: 0.32, dampingFraction: 0.62)
        static let gota = Animation.spring(response: 0.5, dampingFraction: 0.7)
    }

    // MARK: letra
    /// La escala de letra: gigante 44, título 28, sección 20, destacado 17, texto 15, pequeño 13, etiqueta 11
    /// (en mayúsculas y con tracking: usa .estiloEtiqueta()). `cifra` es el título en 600 para las cifras de las cartas.
    enum Estilo {
        case gigante, titulo, seccion, destacado, texto, pequeno, etiqueta, cifra
    }

    private static let familiaCargada: Set<String> = Set(UIFont.familyNames)

    static func fuente(_ estilo: Estilo, peso: Font.Weight? = nil) -> Font {
        let f = actual.fuentes
        let (tam, relativo, pesoBase, familia): (CGFloat, Font.TextStyle, Font.Weight, String?) = {
            switch estilo {
            case .gigante: return (44, .largeTitle, .bold, f.cifras)
            case .titulo: return (28, .title, .bold, f.titulo)
            case .seccion: return (20, .title3, .bold, f.titulo)
            case .destacado: return (17, .headline, .semibold, f.texto)
            case .texto: return (15, .body, .regular, f.texto)
            case .pequeno: return (13, .footnote, .regular, f.texto)
            case .etiqueta: return (11, .caption2, .semibold, f.texto)
            case .cifra: return (28, .title, .semibold, f.cifras)
            }
        }()
        let base: Font
        if let familia, familiaCargada.contains(familia) {
            base = Font.custom(familia, size: tam, relativeTo: relativo)
        } else {
            base = Font.system(size: tam, design: f.diseno)
        }
        return base.weight(peso ?? pesoBase)
    }
}

extension UIColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt32(s, radix: 16) ?? 0x808080
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

/// Una carta de Calma: fondo de carta, radio 18 y el borde casi invisible.
struct EstiloCarta: ViewModifier {
    var relleno: CGFloat = Tema.Espacio.l
    func body(content: Content) -> some View {
        content
            .padding(relleno)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tema.carta, in: RoundedRectangle(cornerRadius: Tema.Radio.carta, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Tema.Radio.carta, style: .continuous)
                .strokeBorder(Tema.linea.opacity(0.6), lineWidth: 0.5))
    }
}

extension View {
    func carta(relleno: CGFloat = Tema.Espacio.l) -> some View { modifier(EstiloCarta(relleno: relleno)) }

    /// Etiqueta de Calma: 11, seminegrita, mayúsculas y tracking .07em.
    func estiloEtiqueta(peso: Font.Weight? = nil) -> some View {
        font(Tema.fuente(.etiqueta, peso: peso)).tracking(11 * 0.07).textCase(.uppercase)
    }
}

/// Botón que se hunde un poco al tocarlo, con muelle (para tarjetas y filas).
struct EstiloHundir: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Tema.Muelle.toque, value: configuration.isPressed)
    }
}
