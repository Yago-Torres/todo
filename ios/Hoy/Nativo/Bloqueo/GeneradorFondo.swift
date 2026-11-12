import SwiftUI
import UIKit
import ImageIO
import CoreImage
import UniformTypeIdentifiers

// El fondo de bloqueo: la foto elegida (encuadrada, oscurecida y desenfocada) + la capa de lo que toca, dibujado con
// ImageRenderer a la resolución nativa de la pantalla. Corre en la app (también lanzada en segundo plano por Atajos):
// la foto se decodifica ya al tamaño que hace falta (ImageIO) y los desenfoques se hacen con Core Image sobre copias
// pequeñas, así cabe en memoria y tarda menos de un segundo.

struct ErrorFondo: LocalizedError {
    let mensaje: String
    var errorDescription: String? { mensaje }
}

// MARK: las fotos

/// Las fotos del fondo, en el app group (legibles con el iPhone bloqueado: las automatizaciones corren así).
enum FotosFondo {
    private static var carpeta: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Config.grupo)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static func url(_ clave: String) -> URL { carpeta.appendingPathComponent("fondo-foto-\(clave).jpg") }

    static func existe(_ clave: String) -> Bool { FileManager.default.fileExists(atPath: url(clave).path) }

    /// La foto que usa un momento: la suya si la tiene (con fotos por momento) y, si no, la común.
    static func clave(_ a: AjustesFondo, _ m: MomentoFondo) -> String {
        let propia = a.claveFoto(m)
        return existe(propia) ? propia : AjustesFondo.comun
    }

    /// Guarda la foto elegida reducida a 3200 px de lado (de sobra para encuadrar con zoom) y ya girada.
    static func guarda(_ datos: Data, clave: String) throws {
        guard let fuente = CGImageSourceCreateWithData(datos as CFData, nil),
              let img = CGImageSourceCreateThumbnailAtIndex(fuente, 0, opciones(3200)),
              let jpg = Jpeg.datos(img, calidad: 0.9) else {
            throw ErrorFondo(mensaje: "No he podido leer esa foto. Prueba con otra o hazle una captura.")
        }
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        try jpg.write(to: url(clave), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func borra(_ clave: String) { try? FileManager.default.removeItem(at: url(clave)) }

    /// Decodificada como mucho a `maxPx` de lado: no se carga entera si no hace falta.
    static func carga(_ clave: String, maxPx: CGFloat) -> CGImage? {
        guard let fuente = CGImageSourceCreateWithURL(url(clave) as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(fuente, 0, opciones(maxPx))
    }

    private static func opciones(_ maxPx: CGFloat) -> CFDictionary {
        let o: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                  kCGImageSourceCreateThumbnailWithTransform: true,
                                  kCGImageSourceShouldCacheImmediately: true,
                                  kCGImageSourceThumbnailMaxPixelSize: max(64, Int(maxPx))]
        return o as CFDictionary
    }
}

enum Jpeg {
    static func datos(_ img: CGImage, calidad: Double) -> Data? {
        let salida = NSMutableData()
        guard let destino = CGImageDestinationCreateWithData(salida, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        let o: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: calidad]
        CGImageDestinationAddImage(destino, img, o as CFDictionary)
        guard CGImageDestinationFinalize(destino) else { return nil }
        return salida as Data
    }
}

// MARK: encuadre y desenfoque

/// La foto lista para pintar: nítida, desenfocada (si se pidió) y muy desenfocada para el cristal. Las tres con la
/// misma proporción, así que se encuadran igual.
struct FotoPreparada {
    let nitida: CGImage
    let desenfocada: CGImage?
    let cristal: CGImage?

    var tamano: CGSize { CGSize(width: nitida.width, height: nitida.height) }
}

enum Encuadre {
    /// Lo que mide la foto en el lienzo con «rellenar» y el zoom, y dónde va su centro.
    static func geometria(_ fuente: CGSize, _ lienzo: CGSize, _ a: AjusteFoto) -> (tam: CGSize, centro: CGPoint) {
        let b = limita(a, fuente, lienzo)
        let s = Double(relleno(fuente, lienzo)) * max(1, b.zoom)
        let w = Double(fuente.width) * s, h = Double(fuente.height) * s
        return (CGSize(width: w, height: h),
                CGPoint(x: Double(lienzo.width) * (0.5 + b.x), y: Double(lienzo.height) * (0.5 + b.y)))
    }

    static func relleno(_ fuente: CGSize, _ lienzo: CGSize) -> CGFloat {
        guard fuente.width > 0, fuente.height > 0 else { return 1 }
        return max(lienzo.width / fuente.width, lienzo.height / fuente.height)
    }

    /// Que la foto tape siempre el lienzo entero.
    static func limita(_ a: AjusteFoto, _ fuente: CGSize, _ lienzo: CGSize) -> AjusteFoto {
        var b = a
        b.zoom = min(4, max(1, a.zoom))
        let s = Double(relleno(fuente, lienzo)) * b.zoom
        let lw = max(1, Double(lienzo.width)), lh = max(1, Double(lienzo.height))
        let maxX: Double = max(0, (Double(fuente.width) * s - lw) / 2 / lw)
        let maxY: Double = max(0, (Double(fuente.height) * s - lh) / 2 / lh)
        b.x = min(maxX, max(-maxX, a.x))
        b.y = min(maxY, max(-maxY, a.y))
        return b
    }
}

enum ProcesaFoto {
    private static let contexto = CIContext(options: [.cacheIntermediates: false])

    /// `lienzo` en puntos: el desenfoque se mide en puntos del lienzo (hasta 24) para que la vista previa y el fondo
    /// de verdad se vean igual aunque la foto tenga otra resolución.
    static func prepara(_ img: CGImage, ajuste: AjusteFoto, lienzo: CGSize, cristal: Bool) -> FotoPreparada {
        let fuente = CGSize(width: img.width, height: img.height)
        let puntoEnPx = 1 / Encuadre.relleno(fuente, lienzo)   // píxeles de la foto por punto del lienzo
        let radio = CGFloat(ajuste.desenfoque) * 24 * puntoEnPx
        let desenfocada = radio > 0.5 ? desenfoca(img, lado: 900, radio: radio) : nil
        let vidrio = cristal ? desenfoca(img, lado: 360, radio: 30 * puntoEnPx) : nil
        return FotoPreparada(nitida: img, desenfocada: desenfocada, cristal: vidrio)
    }

    /// Reduce la foto a `lado` px como mucho y la desenfoca (`radio` en píxeles de la foto original).
    private static func desenfoca(_ img: CGImage, lado: CGFloat, radio: CGFloat) -> CGImage? {
        let f = min(1, lado / CGFloat(max(img.width, img.height)))
        var ci = CIImage(cgImage: img)
        if f < 1 { ci = ci.transformed(by: CGAffineTransform(scaleX: f, y: f)) }
        let marco = ci.extent.integral
        let borrosa = ci.clampedToExtent().applyingGaussianBlur(sigma: Double(radio * f)).cropped(to: marco)
        return contexto.createCGImage(borrosa, from: marco)
    }
}

// MARK: el estilo de la capa

/// Colores y letra de la capa, ya resueltos (nada dinámico: el fondo es una imagen fija).
struct EstiloFondo {
    var texto: Color
    var acento: Color
    /// El color de la tarjeta, la banda y la sombra.
    var velo: Color
    var familiaTexto: String?
    var familiaTitulo: String?
    var diseno: Font.Design
    var tamano: CGFloat
    var radio: CGFloat

    var suave: Color { texto.opacity(0.74) }

    private static let familias: Set<String> = Set(UIFont.familyNames)

    func fuente(_ tam: CGFloat, _ peso: Font.Weight, titulo: Bool = false) -> Font {
        let t = tam * tamano
        if let f = titulo ? familiaTitulo : familiaTexto, Self.familias.contains(f) {
            return Font.custom(f, fixedSize: t).weight(peso)
        }
        return Font.system(size: t, weight: peso, design: diseno)
    }

    @MainActor
    static func de(_ a: AjustesFondo) -> EstiloFondo {
        let p = Tema.actual.paleta
        let texto: UIColor, acento: UIColor, velo: UIColor
        switch a.colores {
        case .temaOscuro:
            texto = UIColor(css: p.texto.oscuro)
            acento = UIColor(css: p.acento.oscuro)
            velo = UIColor(css: p.fondo.oscuro)
        case .temaClaro:
            texto = UIColor(css: p.texto.claro)
            acento = UIColor(css: p.acento.claro)
            velo = UIColor(css: p.fondo.claro)
        case .propios:
            texto = UIColor(hex: a.textoPropio)
            acento = UIColor(hex: a.acentoPropio)
            velo = luminancia(texto) > 0.5 ? .black : .white
        }
        let f = Tema.actual.fuentes
        let familia: String? = a.letra == "tema" ? f.texto : Aspecto.shared.familia(a.letra)
        let titulo: String? = a.letra == "tema" ? f.titulo : familia
        return EstiloFondo(texto: Color(uiColor: texto), acento: Color(uiColor: acento), velo: Color(uiColor: velo),
                           familiaTexto: familia, familiaTitulo: titulo, diseno: f.diseno,
                           tamano: CGFloat(min(1.4, max(0.8, a.tamano))), radio: CGFloat(max(14, Tema.actual.radios.carta * 1.6)))
    }

    static func luminancia(_ c: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, al: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &al)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}

// MARK: generar

@MainActor
enum GeneradorFondo {
    struct Resultado {
        let datos: Data
        let momento: MomentoFondo
        let segundos: Double
        let pixeles: CGSize
    }

    /// La imagen del momento dado o, sin momento, del de ahora.
    static func genera(momento: MomentoFondo? = nil, ahora: Date = Date()) async throws -> Resultado {
        let (hoy, inst) = await DatosFondo.paraGenerar()
        let inicio = Date()
        let ajustes = AjustesFondo.lee()
        let contenido = ContenidoMomento.construye(ajustes, hoy: hoy, inst: inst, ahora: ahora, momento: momento)
        let m = contenido.momento
        let lienzo = PantallaFondo.puntos
        let escala = PantallaFondo.escala
        let clave = FotosFondo.clave(ajustes, m)
        let ajuste = ajustes.fotos[clave] ?? AjusteFoto()

        // la foto, ya al tamaño que se va a ver con su zoom (no más)
        let lado = max(lienzo.width, lienzo.height) * escala * CGFloat(min(4, max(1, ajuste.zoom)))
        let foto = autoreleasepool { () -> FotoPreparada? in
            guard let img = FotosFondo.carga(clave, maxPx: min(3200, lado)) else { return nil }
            return ProcesaFoto.prepara(img, ajuste: ajuste, lienzo: lienzo, cristal: ajustes.estilo != .sombra)
        }

        let vista = LienzoFondo(lienzo: lienzo, foto: foto, ajusteFoto: ajuste, ajustes: ajustes,
                                contenido: contenido, estilo: EstiloFondo.de(ajustes))
            .environment(\.locale, Locale(identifier: "es_ES"))
        let renderer = ImageRenderer(content: vista)
        renderer.scale = escala
        renderer.isOpaque = true
        renderer.proposedSize = ProposedViewSize(lienzo)
        guard let img = renderer.cgImage, let datos = Jpeg.datos(img, calidad: 0.92) else {
            throw ErrorFondo(mensaje: "No he podido dibujar el fondo. Abre Tom y vuelve a probar.")
        }
        return Resultado(datos: datos, momento: m, segundos: Date().timeIntervalSince(inicio),
                         pixeles: CGSize(width: img.width, height: img.height))
    }
}
