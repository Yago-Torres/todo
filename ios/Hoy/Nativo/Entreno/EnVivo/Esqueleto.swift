import CoreGraphics
import Foundation
import SwiftUI
import UIKit
import Vision

/// Lo común del modo en vivo y del vídeo para presumir: la pose (los 19 puntos de VistaPrevia, en el mismo orden),
/// el filtro que la suaviza, el centro de gravedad por segmentos, los ángulos y cómo se pinta el esqueleto. La misma
/// estética que la vista previa de Entreno y que el anotado de ~/escalada: huesos con borde oscuro, articulaciones
/// claras y el centro de gravedad con su estela.
struct PoseEsc {
    /// x, y en 0-1 con la y hacia abajo, sobre la imagen ya derecha.
    var p: [CGPoint]
    var c: [Float]

    static let n = 19
    static let umbral: Float = 0.3
    static let vacia = PoseEsc(p: Array(repeating: .zero, count: n), c: Array(repeating: 0, count: n))

    /// Los huesos (índices de VistaPrevia.articulaciones), los mismos que dibuja la vista previa.
    static let huesos: [(Int, Int)] = [(5, 6), (5, 8), (8, 10), (6, 9), (9, 11), (5, 13), (6, 14), (13, 14), (13, 15),
                                       (15, 17), (14, 16), (16, 18), (0, 7)]

    func ve(_ i: Int) -> Bool { c[i] >= Self.umbral }
    var hayCuerpo: Bool { c.filter { $0 >= Self.umbral }.count >= 6 }

    /// La persona más clara del resultado de Vision; nil si no hay nadie.
    init?(_ resultados: [VNHumanBodyPoseObservation]?) {
        func total(_ o: VNHumanBodyPoseObservation) -> Float {
            ((try? o.recognizedPoints(.all)) ?? [:]).values.reduce(0) { $0 + $1.confidence }
        }
        guard let cuerpo = (resultados ?? []).max(by: { total($0) < total($1) }),
              let puntos = try? cuerpo.recognizedPoints(.all) else { return nil }
        var p = [CGPoint](repeating: .zero, count: Self.n)
        var c = [Float](repeating: 0, count: Self.n)
        for (i, j) in VistaPrevia.articulaciones.enumerated() {
            if let q = puntos[j], q.confidence > 0 {
                p[i] = CGPoint(x: q.location.x, y: 1 - q.location.y)
                c[i] = q.confidence
            }
        }
        self.init(p: p, c: c)
        guard hayCuerpo else { return nil }
    }

    init(p: [CGPoint], c: [Float]) {
        self.p = p
        self.c = c
    }

    /// Mezcla lineal con otra pose (para interpolar entre análisis): un punto que solo está en una se queda en esa.
    func mezcla(_ otra: PoseEsc, _ w: CGFloat) -> PoseEsc {
        var r = self
        for i in 0..<Self.n {
            switch (ve(i), otra.ve(i)) {
            case (true, true):
                r.p[i] = CGPoint(x: p[i].x + (otra.p[i].x - p[i].x) * w, y: p[i].y + (otra.p[i].y - p[i].y) * w)
                r.c[i] = c[i] + (otra.c[i] - c[i]) * Float(w)
            case (false, true):
                r.p[i] = otra.p[i]
                r.c[i] = w > 0.5 ? otra.c[i] : 0
            case (true, false):
                r.c[i] = w < 0.5 ? c[i] : 0
            default: break
            }
        }
        return r
    }

    // MARK: medidas (en píxeles: los ángulos dependen de la proporción de la imagen)

    private func px(_ i: Int, _ tam: CGSize) -> CGPoint { CGPoint(x: p[i].x * tam.width, y: p[i].y * tam.height) }

    private func media(_ ids: [Int], _ tam: CGSize) -> CGPoint? {
        let vistos = ids.filter(ve)
        guard !vistos.isEmpty else { return nil }
        let s = vistos.reduce(CGPoint.zero) { CGPoint(x: $0.x + px($1, tam).x, y: $0.y + px($1, tam).y) }
        return CGPoint(x: s.x / CGFloat(vistos.count), y: s.y / CGFloat(vistos.count))
    }

    /// Hombros y caderas (o cuello y raíz si faltan).
    private func tronco(_ tam: CGSize) -> (CGPoint, CGPoint)? {
        guard let h = media([5, 6], tam) ?? (ve(7) ? px(7, tam) : nil),
              let c = media([13, 14], tam) ?? (ve(12) ? px(12, tam) : nil) else { return nil }
        return (h, c)
    }

    /// Lo que mide el tronco (hombros a caderas), en píxeles: da la escala del cuerpo (cerca o lejos).
    func largoTronco(_ tam: CGSize) -> CGFloat? {
        guard let t = tronco(tam) else { return nil }
        let (h, c) = t
        let d = hypot(h.x - c.x, h.y - c.y)
        return d > 1 ? d : nil
    }

    /// Centro de gravedad: la media de los centros de cada segmento pesada por su masa (tablas de Dempster), en
    /// píxeles. Los segmentos que no se ven no cuentan; sin tronco no hay centro.
    func centro(_ tam: CGSize) -> CGPoint? {
        guard let t = tronco(tam) else { return nil }
        let (hombros, caderas) = t
        var x = 0.0, y = 0.0, m = 0.0
        func suma(_ a: CGPoint, _ b: CGPoint, _ f: Double, _ masa: Double) {
            x += (Double(a.x) + (Double(b.x) - Double(a.x)) * f) * masa
            y += (Double(a.y) + (Double(b.y) - Double(a.y)) * f) * masa
            m += masa
        }
        suma(hombros, caderas, 0.5, 0.497)                              // tronco
        if ve(0) { suma(hombros, px(0, tam), 0.6, 0.081) }              // cabeza
        let segmentos: [(Int, Int, Double, Double)] = [
            (5, 8, 0.436, 0.028), (6, 9, 0.436, 0.028),                 // brazos
            (8, 10, 0.682, 0.022), (9, 11, 0.682, 0.022),               // antebrazo y mano
            (13, 15, 0.433, 0.100), (14, 16, 0.433, 0.100),             // muslos
            (15, 17, 0.606, 0.061), (16, 18, 0.606, 0.061),             // pierna y pie
        ]
        for (a, b, f, masa) in segmentos where ve(a) && ve(b) { suma(px(a, tam), px(b, tam), f, masa) }
        guard m > 0 else { return nil }
        return CGPoint(x: x / m, y: y / m)
    }

    /// El ángulo en b (grados, 180 = estirado), o nil si falta algún punto.
    func angulo(_ a: Int, _ b: Int, _ c: Int, _ tam: CGSize) -> Double? {
        guard ve(a), ve(b), ve(c) else { return nil }
        let pa = px(a, tam), pb = px(b, tam), pc = px(c, tam)
        let v1 = CGVector(dx: pa.x - pb.x, dy: pa.y - pb.y), v2 = CGVector(dx: pc.x - pb.x, dy: pc.y - pb.y)
        let l = hypot(v1.dx, v1.dy) * hypot(v2.dx, v2.dy)
        guard l > 0 else { return nil }
        let cos = max(-1, min(1, (v1.dx * v2.dx + v1.dy * v2.dy) / l))
        return Double(acos(cos)) * 180 / .pi
    }
}

// MARK: - el suavizado

/// Filtro One Euro (Casiez et al.): quieto no tiembla y rápido no se retrasa. Uno por coordenada.
struct UnEuro {
    var minimo: Double = 1.4
    var beta: Double = 2.5
    var derivada: Double = 1.0
    private var x: Double?
    private var dx: Double = 0
    private var t: Double = 0

    init(minimo: Double = 1.4, beta: Double = 2.5) {
        self.minimo = minimo
        self.beta = beta
    }

    private static func alfa(_ corte: Double, _ dt: Double) -> Double {
        let tau = 1 / (2 * .pi * corte)
        return 1 / (1 + tau / dt)
    }

    mutating func reinicia() { x = nil }

    mutating func filtra(_ valor: Double, _ ahora: Double) -> Double {
        guard let previo = x else {
            x = valor
            dx = 0
            t = ahora
            return valor
        }
        let dt = max(1.0 / 240, ahora - t)
        t = ahora
        let d = (valor - previo) / dt
        dx += Self.alfa(derivada, dt) * (d - dx)
        let corte = minimo + beta * abs(dx)
        let nuevo = previo + Self.alfa(corte, dt) * (valor - previo)
        x = nuevo
        return nuevo
    }
}

/// Suaviza una pose entera; un punto que se pierde aguanta unos instantes (sin temblar) y luego se apaga.
struct SuavizadorPose {
    private var fx = [UnEuro](repeating: UnEuro(), count: PoseEsc.n)
    private var fy = [UnEuro](repeating: UnEuro(), count: PoseEsc.n)
    private var ultimo = PoseEsc.vacia
    private var visto = [Double](repeating: -10, count: PoseEsc.n)

    mutating func filtra(_ nueva: PoseEsc?, _ t: Double) -> PoseEsc {
        var r = ultimo
        for i in 0..<PoseEsc.n {
            if let nueva, nueva.ve(i) {
                if t - visto[i] > 0.5 {
                    fx[i].reinicia()
                    fy[i].reinicia()
                }
                r.p[i] = CGPoint(x: fx[i].filtra(Double(nueva.p[i].x), t), y: fy[i].filtra(Double(nueva.p[i].y), t))
                r.c[i] = nueva.c[i]
                visto[i] = t
            } else if t - visto[i] > 0.4 {
                r.c[i] = 0
            }
        }
        ultimo = r
        return r
    }
}

// MARK: - colores y pintor

/// Los colores del esqueleto, resueltos del tema en su variante oscura (se pinta sobre vídeo). Se sacan en el hilo
/// principal y luego se usan en cualquier cola.
struct ColoresEsq: @unchecked Sendable {
    var hueso: UIColor
    var punto: UIColor
    var centro: UIColor
    var borde: UIColor

    static func delTema() -> ColoresEsq {
        let p = Tema.actual.paleta
        return ColoresEsq(hueso: UIColor(css: p.acento.oscuro), punto: UIColor(css: p.texto.oscuro),
                          centro: UIColor(css: p.aviso.oscuro), borde: UIColor(css: p.fondo.oscuro))
    }

    var huesoSwiftUI: Color { Color(uiColor: hueso) }
    var centroSwiftUI: Color { Color(uiColor: centro) }
}

/// Un punto de la estela: dónde estaba el centro de gravedad y cuándo.
struct PuntoEstela {
    var t: Double
    var p: CGPoint   // 0-1 sobre la imagen
}

enum PintorEsq {
    /// Pinta en un CGContext con la y hacia abajo. `aPx` lleva un punto 0-1 de la imagen a donde se pinta; `escala`
    /// es cuántos píxeles de destino mide un píxel de la imagen (el grosor va con el tamaño del cuerpo en pantalla).
    static func pinta(_ ctx: CGContext, pose: PoseEsc?, estela: [PuntoEstela], ahora: Double, duracionEstela: Double,
                      tamImagen: CGSize, escala: CGFloat, aPx: (CGPoint) -> CGPoint, colores: ColoresEsq) {
        let tronco = (pose?.largoTronco(tamImagen) ?? tamImagen.height * 0.15) * escala
        let g = max(2.5, min(18, tronco * 0.065))
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        // la estela del centro de gravedad: más fina y transparente cuanto más vieja, del acento al color del centro
        if estela.count > 1 {
            let saltoMax: CGFloat = 0.2   // un salto así entre dos puntos seguidos es un fotograma mal leído: no se une
            for k in 1..<estela.count {
                let a = estela[k - 1], b = estela[k]
                guard hypot(a.p.x - b.p.x, a.p.y - b.p.y) < saltoMax else { continue }
                let edad = max(0, min(1, (ahora - b.t) / duracionEstela))
                let viva = CGFloat(1 - edad)
                ctx.setStrokeColor(mezcla(colores.hueso, colores.centro, Double(viva)).withAlphaComponent(0.15 + 0.85 * viva).cgColor)
                ctx.setLineWidth(g * (0.35 + 0.9 * viva))
                ctx.move(to: aPx(a.p))
                ctx.addLine(to: aPx(b.p))
                ctx.strokePath()
            }
        }

        guard let pose else { return }
        // huesos: primero el borde oscuro, luego el acento encima
        let pares = PoseEsc.huesos.filter { pose.ve($0.0) && pose.ve($0.1) }
        for (ancho, color) in [(g + 3, colores.borde.withAlphaComponent(0.6)), (g, colores.hueso)] {
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(ancho)
            for (a, b) in pares {
                ctx.move(to: aPx(pose.p[a]))
                ctx.addLine(to: aPx(pose.p[b]))
            }
            ctx.strokePath()
        }
        // la cabeza, un aro alrededor de la nariz
        if pose.ve(0) {
            let c = aPx(pose.p[0]), r = tronco * 0.17
            ctx.setStrokeColor(colores.borde.withAlphaComponent(0.6).cgColor)
            ctx.setLineWidth(g + 3)
            ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ctx.setStrokeColor(colores.hueso.cgColor)
            ctx.setLineWidth(g)
            ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        }
        // articulaciones
        let r = g * 0.8
        for i in [5, 6, 8, 9, 10, 11, 13, 14, 15, 16, 17, 18] where pose.ve(i) {
            let c = aPx(pose.p[i])
            ctx.setFillColor(colores.borde.cgColor)
            ctx.fillEllipse(in: CGRect(x: c.x - r - 1.5, y: c.y - r - 1.5, width: (r + 1.5) * 2, height: (r + 1.5) * 2))
            ctx.setFillColor(colores.punto.cgColor)
            ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        }
        // el centro de gravedad
        if let cdg = pose.centro(tamImagen) {
            let c = aPx(CGPoint(x: cdg.x / tamImagen.width, y: cdg.y / tamImagen.height))
            let rc = g * 1.5 + 2
            ctx.setFillColor(colores.borde.cgColor)
            ctx.fillEllipse(in: CGRect(x: c.x - rc - 2, y: c.y - rc - 2, width: (rc + 2) * 2, height: (rc + 2) * 2))
            ctx.setFillColor(colores.centro.cgColor)
            ctx.fillEllipse(in: CGRect(x: c.x - rc, y: c.y - rc, width: rc * 2, height: rc * 2))
            ctx.setFillColor(colores.punto.cgColor)
            ctx.fillEllipse(in: CGRect(x: c.x - rc * 0.35, y: c.y - rc * 0.35, width: rc * 0.7, height: rc * 0.7))
        }
    }

    private static func mezcla(_ a: UIColor, _ b: UIColor, _ w: Double) -> UIColor {
        var ra: CGFloat = 0, ga: CGFloat = 0, ba: CGFloat = 0, aa: CGFloat = 0
        var rb: CGFloat = 0, gb: CGFloat = 0, bb: CGFloat = 0, ab: CGFloat = 0
        a.getRed(&ra, green: &ga, blue: &ba, alpha: &aa)
        b.getRed(&rb, green: &gb, blue: &bb, alpha: &ab)
        let f = CGFloat(w)
        return UIColor(red: ra + (rb - ra) * f, green: ga + (gb - ga) * f, blue: ba + (bb - ba) * f, alpha: 1)
    }
}

/// Lo que dice el medidor de los ángulos: 180° es estirado.
enum Medidor {
    /// 0 (muy doblado, 40°) a 1 (estirado, 180°).
    static func estiramiento(_ grados: Double?) -> Double? {
        grados.map { max(0, min(1, ($0 - 40) / 140)) }
    }

    static func frase(codos: [Double]) -> String {
        guard !codos.isEmpty else { return "Ponte entero en el encuadre" }
        let m = codos.reduce(0, +) / Double(codos.count)
        if m >= 150 { return "Brazos estirados: así ahorras fuerza" }
        if m >= 110 { return "Brazos a medias" }
        return "Bloqueando: tensión a tope"
    }
}
