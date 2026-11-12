import SwiftUI
import UIKit

/// El estilo de las pantallas nativas, en un solo sitio. Calcado de ~/estilo/calma.css (los mismos nombres que sus
/// tokens): las vistas nativas solo usan lo de aquí, nunca un color o un tamaño suelto. Para otro tema, otra `Paleta`
/// y otras `Fuentes`, y se cambia `Tema.actual` (pensado para elegirlo luego desde Configurar).
struct Paleta {
    /// Cada token con su valor en claro y en oscuro (hex de calma.css).
    struct Token {
        let claro: String
        let oscuro: String
        var color: Color {
            Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: oscuro) : UIColor(hex: claro) })
        }
    }

    var fondo = Token(claro: "#F4F5F0", oscuro: "#171A16")
    var carta = Token(claro: "#FFFFFF", oscuro: "#21251F")
    var carta2 = Token(claro: "#ECEEE6", oscuro: "#2B3028")
    var texto = Token(claro: "#1E211C", oscuro: "#EEF0E8")
    var suave = Token(claro: "#686D60", oscuro: "#A3A892")
    var tenue = Token(claro: "#A0A595", oscuro: "#737865")
    var linea = Token(claro: "#E2E5DB", oscuro: "#363C31")
    var acento = Token(claro: "#5E7A1E", oscuro: "#CDE77F")
    var acentoTexto = Token(claro: "#FFFFFF", oscuro: "#26300A")
    var acentoSuave = Token(claro: "#EBF3D6", oscuro: "#333D22")
    var peligro = Token(claro: "#D64545", oscuro: "#F2726B")
    var aviso = Token(claro: "#B97A0E", oscuro: "#E8B04A")
    /// La barra de abajo: grafito en los dos temas, con la gota lima de la sección actual.
    var dock = Token(claro: "#2E342B", oscuro: "#2E342B")
    var dockTexto = Token(claro: "#B5BAA6", oscuro: "#B5BAA6")
    var gota = Token(claro: "#CDE77F", oscuro: "#CDE77F")
    var gotaTexto = Token(claro: "#26300A", oscuro: "#26300A")
    /// Los caracteres del fondo (calma.js): tenues, y los densos en acento.
    var ascii = Token(claro: "#2C3226", oscuro: "#D6DEC4")
}

/// Familias de letra. nil = la del sistema (SF Pro). Para usar otra (p. ej. "Inter"), se empaqueta el .ttf/.otf en
/// Hoy/, se añade a UIAppFonts en Info.plist y se pone aquí su nombre PostScript: todas las pantallas la cogen.
struct Fuentes {
    var texto: String? = nil
    var titulo: String? = nil
    var cifras: String? = nil
    /// El diseño del sistema cuando no hay familia propia (.default, .rounded, .serif, .monospaced).
    var diseno: Font.Design = .default
}

struct Tema {
    var paleta = Paleta()
    var fuentes = Fuentes()

    /// El tema en uso. Hoy solo hay uno (Calma); el día que haya más, se elige aquí desde Configurar.
    static var actual = Tema()

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
        static let carta: CGFloat = 18
        static let boton: CGFloat = 12
        static let celda: CGFloat = 8
        static let dock: CGFloat = 22
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
    enum Estilo {
        case saludo, titulo, seccion, cuerpo, etiqueta, cifra, cifraGrande, pie
    }

    static func fuente(_ estilo: Estilo, peso: Font.Weight? = nil) -> Font {
        let f = actual.fuentes
        let (tam, relativo, pesoBase, familia): (CGFloat, Font.TextStyle, Font.Weight, String?) = {
            switch estilo {
            case .saludo: return (34, .largeTitle, .bold, f.titulo)
            case .titulo: return (22, .title2, .semibold, f.titulo)
            case .seccion: return (17, .headline, .semibold, f.titulo)
            case .cuerpo: return (16, .body, .regular, f.texto)
            case .etiqueta: return (12, .caption, .semibold, f.texto)
            case .cifra: return (26, .title, .semibold, f.cifras)
            case .cifraGrande: return (44, .largeTitle, .bold, f.cifras)
            case .pie: return (13, .footnote, .regular, f.texto)
            }
        }()
        let base: Font = familia.map { Font.custom($0, size: tam, relativeTo: relativo) }
            ?? Font.system(size: tam, design: f.diseno)
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
}

/// Botón que se hunde un poco al tocarlo, con muelle (para tarjetas y filas).
struct EstiloHundir: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Tema.Muelle.toque, value: configuration.isPressed)
    }
}
