import SwiftUI

// El dibujo de la mascota, portado de static/mascota.js con los mismos números (coordenadas del SVG de la web):
// el fantasma de píxeles (viewBox 30 30 100 120) y la flor de boli (viewBox 6 -8 190 106). Mismo generador de azar
// (mulberry32), así que con la misma semilla sale la misma forma que en la web.

/// mulberry32, igual que `azar` en mascota.js.
struct AzarMascota {
    private var a: UInt32

    init(_ semilla: Int) { a = UInt32(truncatingIfNeeded: semilla) }

    mutating func callAsFunction() -> Double {
        a = a &+ 0x6D2B_79F5
        var t = (a ^ (a >> 15)) &* (1 | a)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }
}

/// Un trozo de dibujo: un camino relleno o trazado, con su color (nil = la tinta de la mascota).
struct TrazoMascota {
    var camino: Path
    var color: Color?
    var relleno: Bool
    var grosor: CGFloat = 0.72
    var opacidad: Double = 1
    /// Es un ojo: parpadea (se aplasta en vertical sobre su centro).
    var ojo = false
}

enum DibujoMascota {
    static let tinta = Color(hex: "#1E211C")
    static let humo = Color(hex: "#A3A892")
    static let rojo = "#D9533A"
    static let cajaFantasma = CGRect(x: 30, y: 30, width: 100, height: 120)
    static let cajaFlor = CGRect(x: 6, y: -8, width: 190, height: 106)

    // MARK: curvas

    /// Un punto de una curva de Bézier de cualquier grado (de Casteljau).
    static func punto(_ c: [CGPoint], _ t: Double) -> CGPoint {
        var q = c
        while q.count > 1 {
            q = (1..<q.count).map { i in
                CGPoint(x: q[i - 1].x + (q[i].x - q[i - 1].x) * t, y: q[i - 1].y + (q[i].y - q[i - 1].y) * t)
            }
        }
        return q[0]
    }

    static func tramo(_ c: [CGPoint], _ n: Int) -> [CGPoint] { (0..<n).map { punto(c, Double($0) / Double(n)) } }

    // MARK: el fantasma

    /// El contorno del cuerpo como lista de puntos; fase 0 y 1 son los dos momentos de los flecos.
    static func contorno(_ p: MascotaAjustes, ancho: Double, alto: Double, fleco: Double, fase: Double) -> [CGPoint] {
        var R = AzarMascota(p.semilla)
        let cx = 80.0, yb = 122.0, h = alto, yt = yb - h, c = p.cola, g = p.grumos
        let wt = ancho * (1 - p.pera * 0.45), wb = ancho * (1 + p.pera * 0.3)
        let n = max(1, Int(p.flecos.rounded())), w = 2 * wb / Double(n)
        let j = (R() - 0.5) * g * 30, k = (R() - 0.5) * g * 30, top = (R() - 0.5) * g * 24
        func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }
        var out = tramo([P(cx - wb + c, yb), P(cx - wb + c * 0.2 + j, yt + h * 0.38), P(cx - wt, yt + abs(top) * 0.3), P(cx + top, yt)], 24)
        out += tramo([P(cx + top, yt), P(cx + wt, yt - abs(top) * 0.3), P(cx + wb + c * 0.2 + k, yt + h * 0.38), P(cx + wb + c, yb)], 24)
        var x = cx + wb + c, y = yb
        for i in 0..<n {
            let hd = fleco * (1 + g * (R() - 0.5) * 3) * (1 + 0.38 * sin(Double(i) * 1.9 + fase * .pi))
            let e = i == n - 1 ? yb : yb + (R() - 0.5) * g * 12
            out += tramo([P(x, y), P(x - w / 2 + sin(fase * .pi + Double(i)) * 2, min(156, yb + hd * 1.7)), P(x - w, e)], 8)
            x -= w
            y = e
        }
        return out
    }

    /// El contorno pasado a cuadraditos de `s`.
    static func pixeles(_ P: [CGPoint], _ s: Double) -> Path {
        func dentro(_ x: Double, _ y: Double) -> Bool {
            var c = false
            var j = P.count - 1
            for i in 0..<P.count {
                let a = P[i].x, b = P[i].y, u = P[j].x, v = P[j].y
                if (b > y) != (v > y), x < (u - a) * (y - b) / (v - b) + a { c.toggle() }
                j = i
            }
            return c
        }
        var p = Path()
        var y = 0.0
        while y < 165 {
            var x = 10.0
            while x < 155 {
                if dentro(x + s / 2, y + s / 2) { p.addRect(CGRect(x: x, y: y, width: s, height: s)) }
                x += s
            }
            y += s
        }
        return p
    }

    /// La cara del fantasma para el cuerpo en reposo (al deformarse, solo se sube o se baja).
    static func rostroFantasma(_ e: String, _ A: MascotaAjustes, px s: Double = 5) -> [TrazoMascota] {
        func sn(_ v: Double) -> Double { (v / s).rounded() * s }
        var out: [TrazoMascota] = []
        func R(_ x: Double, _ y: Double, _ w: Double, _ h: Double, ojo: Bool = false, color: Color? = nil, opacidad: Double = 1) {
            out.append(TrazoMascota(camino: Path(CGRect(x: x, y: y, width: w, height: h)), color: color ?? tinta, relleno: true,
                                    opacidad: opacidad, ojo: ojo))
        }
        let yt = 122 - A.alto, fx = 80 + A.cola * 0.2, ey = yt + A.alto * A.ojosY
        let sonrie = e == "feliz" || e == "contento", cerrados = e == "dormido" || e == "bostezo"
        for (q, z) in [(-1.0, A.ojoI), (1.0, A.ojoD)] {
            let X = sn(fx + q * A.sep / 2), Y = sn(ey), w = max(s, sn(z * 1.6))
            if sonrie {
                R(X - s, Y, s, s); R(X, Y - s, s, s); R(X + s, Y, s, s)
            } else if e == "susto" {
                R(X - s / 2, Y - s * 1.5, w + s, w + s * 2, ojo: true)
            } else if cerrados || (e == "guino" && q > 0) {
                R(X - s, Y, s * 3, s * 0.6)
            } else {
                R(X, Y - s, w, w + s, ojo: true)
            }
            if e == "animo" || e == "sorpresa" || e == "susto" { R(X - s, Y - s * (e == "susto" ? 3 : 2), s * 2, s * 0.6) }
            if e == "ausente" { R(X - s, Y - s * (q < 0 ? 2 : 3), s * 2, s * 0.6) }
            if e == "enfadado" { R(X + (q < 0 ? -s : s), Y - s * 2, s, s * 0.7); R(X, Y - s * 1.3, s, s * 0.7) }
            if A.extra == "gafas" {
                out.append(TrazoMascota(camino: Path(CGRect(x: X + w / 2 - s * 1.4, y: Y - s * 2, width: s * 2.8, height: s * 3.6)),
                                        color: tinta, relleno: false, grosor: 1.6))
            }
            if A.rubor { R(X + q * s, Y + s * 2, s * 2, s, color: Color(hex: "#E8927C"), opacidad: 0.7) }
        }
        if A.extra == "gafas" { R(sn(fx - A.sep / 2), sn(ey) - s, sn(A.sep), 1.6) }
        let X = sn(fx + 1), Y = sn(ey + max(A.ojoI, A.ojoD) * 1.1 + 7)
        switch e {
        case "feliz", "contento": R(X - s, Y, s * 3, s * 0.7); R(X, Y + s * 0.7, s, s * 0.7)
        case "enfadado":
            R(X - s, Y, s, s * 0.7); R(X, Y + s * 0.7, s, s * 0.7); R(X + s, Y, s, s * 0.7); R(X + s * 2, Y + s * 0.7, s, s * 0.7)
        case "ausente": R(X - s, Y + s * 0.7, s * 3, s * 0.7); R(X, Y, s, s * 0.7)
        case "bostezo": R(X - s, Y, s * 2, s * 3)
        case "susto": R(X - s * 0.5, Y, s * 2, s * 2)
        case "guino": R(X, Y, s * 2, s * 0.7); R(X + s * 2, Y - s * 0.7, s, s * 0.7)
        case "animo", "dormido", "sorpresa": R(X, Y, s, s)
        default: R(X - s, Y, s * 2, s * 0.7)
        }
        return out
    }

    /// El lazo o el gorro, en píxeles.
    static func adorno(_ A: MascotaAjustes, px s: Double = 5) -> TrazoMascota? {
        func sn(_ v: Double) -> Double { (v / s).rounded() * s }
        let y = sn(122 - A.alto), x = sn(80 + A.cola * 0.2)
        let datos: ([String], Double, Double, String)
        switch A.extra {
        case "lazo": datos = (["x.x", "xxx", "x.x"], x - s * 4, y + s, "#E8556F")
        case "gorro": datos = (["...x...", "..xxx..", ".xxxxx.", "xxxxxxx"], x - s * 3, y - s * 3, "#6C8EF5")
        default: return nil
        }
        let (filas, x0, y0, color) = datos
        var p = Path()
        for (j, f) in filas.enumerated() {
            for (i, v) in f.enumerated() where v == "x" {
                p.addRect(CGRect(x: x0 + Double(i) * s, y: y0 + Double(j) * s, width: s, height: s))
            }
        }
        return TrazoMascota(camino: p, color: Color(hex: color), relleno: true)
    }

    // MARK: la flor

    static let centroFlor = CGPoint(x: 104, y: 34)

    /// Una línea suave por una lista de puntos (curvas cuadráticas entre puntos medios).
    static func linea(_ P: [CGPoint], en p: inout Path) {
        guard let primero = P.first else { return }
        p.move(to: primero)
        guard P.count > 2 else {
            if P.count == 2 { p.addLine(to: P[1]) }
            return
        }
        for i in 0..<(P.count - 2) {
            let c = P[i + 1], s = P[i + 2]
            p.addQuadCurve(to: CGPoint(x: (c.x + s.x) / 2, y: (c.y + s.y) / 2), control: c)
        }
    }

    /// El trazo básico del dibujo: un óvalo a mano que va de un punto a otro. J pone el pulso de cada fotograma.
    static func ovillo(_ J: inout AzarMascota, _ p0: CGPoint, _ p1: CGPoint, _ b: Double, _ vueltas: Double = 1, en p: inout Path) {
        let cx = (p0.x + p1.x) / 2, cy = (p0.y + p1.y) / 2, a = hypot(p1.x - p0.x, p1.y - p0.y) / 2
        let div = 2 * a == 0 ? 1 : 2 * a
        let u = (p1.x - p0.x) / div, v = (p1.y - p0.y) / div
        let n = Int(ceil(11 * vueltas))
        let giro = J() * 6.3
        var pts: [CGPoint] = []
        for i in 0...n {
            let t = giro + Double(i) / Double(n) * vueltas * 2 * .pi
            let k = 1 + (J() - 0.5) * 0.14
            let x = a * cos(t) * k, y = b * sin(t) * k
            pts.append(CGPoint(x: cx + x * u - y * v, y: cy + x * v + y * u))
        }
        linea(pts, en: &p)
    }

    static func raya(_ a: CGPoint, _ b: CGPoint, en p: inout Path) {
        p.move(to: a)
        p.addLine(to: b)
    }

    static func petalos(_ R: inout AzarMascota, _ J: inout AzarMascota) -> Path {
        var d = Path()
        let C = centroFlor
        let n = 34
        for i in 0..<n {
            let g = Double(i) / Double(n) * 2 * .pi + (R() - 0.5) * 0.24, c = cos(g), s = sin(g)
            let abajo = s > 0.45 ? 0.78 : 1
            let ri = 1 + (R() - 0.5) * 0.3
            let ro = (0.78 + R() * 0.4) * abajo
            let dentro = CGPoint(x: C.x + c * 19 * ri, y: C.y + s * 14 * ri)
            let fuera = CGPoint(x: C.x + c * 47 * ro, y: C.y + s * 35 * ro)
            let b = 2 + R() * 2.2
            let lazos = 3 + Int(floor(R() * 2.4))
            for _ in 0..<lazos {
                let o = (R() - 0.5) * 7, largo = 0.62 + R() * 0.42
                let desde = CGPoint(x: dentro.x + (R() - 0.5) * 3, y: dentro.y + (R() - 0.5) * 2.5)
                let hasta = CGPoint(x: dentro.x + (fuera.x - dentro.x) * largo / 0.85 - s * o,
                                    y: dentro.y + (fuera.y - dentro.y) * largo / 0.85 + c * o * 0.7)
                let grueso = b * (0.6 + R() * 0.7)
                ovillo(&J, desde, hasta, grueso, en: &d)
            }
            if R() < 0.28 {
                raya(CGPoint(x: dentro.x + c * 5, y: dentro.y + s * 4), CGPoint(x: C.x + c * 53 * ro, y: C.y + s * 39 * ro), en: &d)
            }
        }
        return d
    }

    static func manita(_ R: inout AzarMascota, _ J: inout AzarMascota, _ centro: CGPoint, _ r: Double) -> Path {
        var d = Path()
        let cx = centro.x, cy = centro.y
        ovillo(&J, CGPoint(x: cx - 2.6, y: cy - 0.8), CGPoint(x: cx + 2.6, y: cy + 0.8), 2.4, 5, en: &d)
        ovillo(&J, CGPoint(x: cx - 1.4, y: cy + 1), CGPoint(x: cx + 1.6, y: cy - 1), 1.6, 4, en: &d)
        for i in 0..<9 {
            let g = Double(i) / 9 * 2 * .pi + (R() - 0.5) * 0.6, l = r * (0.65 + R() * 0.55)
            let f = CGPoint(x: cx + cos(g) * l, y: cy + sin(g) * l)
            let b1 = r * (0.13 + R() * 0.13)
            ovillo(&J, centro, f, b1, en: &d)
            let f2 = CGPoint(x: f.x + (R() - 0.5) * 3, y: f.y + (R() - 0.5) * 3)
            let b2 = r * (0.1 + R() * 0.12)
            ovillo(&J, centro, f2, b2, en: &d)
            if R() < 0.4 { raya(centro, CGPoint(x: cx + cos(g) * l * 1.35, y: cy + sin(g) * l * 1.35), en: &d) }
        }
        return d
    }

    /// El brazo: un tallo rayado de ida y vuelta.
    static func tallo(_ J: inout AzarMascota, _ a: CGPoint, _ b: CGPoint, _ w: Double, _ n: Int, en d: inout Path) {
        let l = hypot(b.x - a.x, b.y - a.y), nx = -(b.y - a.y) / l, ny = (b.x - a.x) / l
        var P: [CGPoint] = []
        for i in 0...n {
            let t = Double(i) / Double(n)
            let o = (i % 2 == 1 ? 1.0 : -1.0) * w * (0.5 + J() * 0.5) * (0.4 + 0.6 * t)
            P.append(CGPoint(x: a.x + (b.x - a.x) * t + nx * o, y: a.y + (b.y - a.y) * t + ny * o))
        }
        linea(P, en: &d)
        raya(a, b, en: &d)
    }

    struct PartesFlor {
        var petalos = Path(), bi = Path(), mi = Path(), bd = Path(), md = Path(), pi = Path(), pd = Path()
    }

    /// Las partes de la flor en un fotograma: R es el dibujo, siempre igual; J, el pulso de ese fotograma.
    static func partesFlor(_ semilla: Int, fotograma: Int) -> PartesFlor {
        var R = AzarMascota(semilla), J = AzarMascota(semilla * 31 + fotograma * 7 + 1)
        func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }
        var f = PartesFlor()
        f.petalos = petalos(&R, &J)
        tallo(&J, P(85, 37.5), P(31, 44.5), 2.2, 46, en: &f.bi)
        tallo(&J, P(66, 39), P(36, 44), 1.2, 22, en: &f.bi)
        f.mi = manita(&R, &J, P(25, 45), 15)
        tallo(&J, P(115.5, 42), P(168, 37), 1, 26, en: &f.bd)
        f.md = manita(&R, &J, P(175, 36.5), 12.5)
        ovillo(&J, P(90, 59), P(73, 79), 3.8, 2, en: &f.pi)
        ovillo(&J, P(88, 62), P(76, 77), 2.6, 2, en: &f.pi)
        ovillo(&J, P(80, 74), P(66, 86), 3.6, 2, en: &f.pi)
        ovillo(&J, P(74, 79), P(41, 84.5), 2.2, 2, en: &f.pi)
        ovillo(&J, P(72, 82), P(50, 83.5), 2.8, 2, en: &f.pi)
        ovillo(&J, P(109, 56), P(105, 79), 3.4, 3, en: &f.pd)
        ovillo(&J, P(107, 62), P(104, 74), 2.2, 2, en: &f.pd)
        ovillo(&J, P(106, 72), P(103, 88), 2.8, 2, en: &f.pd)
        ovillo(&J, P(103, 90), P(76, 91.5), 2.5, 3, en: &f.pd)
        ovillo(&J, P(100, 88.5), P(84, 92), 2.2, 2, en: &f.pd)
        return f
    }

    /// La cara de la flor: ojos de óvalos dentro de óvalos y la sonrisa torcida con su manchón.
    static func rostroFlor(_ estado: String, semilla: Int) -> [TrazoMascota] {
        let e = estado == "susto" ? "sorpresa" : estado
        var J = AzarMascota(semilla + 5)
        let sonrie = e == "feliz" || e == "contento", cerrados = e == "dormido" || e == "bostezo"
        var out: [TrazoMascota] = []
        func trazo(_ g: CGFloat = 0.72, ojo: Bool = false, relleno: Bool = false, _ f: (inout Path) -> Void) {
            var p = Path()
            f(&p)
            out.append(TrazoMascota(camino: p, color: nil, relleno: relleno, grosor: g, ojo: ojo))
        }
        func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }
        func ojoI() {
            var p = Path()
            ovillo(&J, P(89.5, 32.3), P(101.5, 32.1), 3, en: &p)
            ovillo(&J, P(92.5, 32.4), P(98.5, 32), 1.7, en: &p)
            p.move(to: P(95, 31.6)); p.addLine(to: P(96, 31.6))
            out.append(TrazoMascota(camino: p, color: nil, relleno: false, ojo: true))
        }
        func ojoD() {
            var p = Path()
            p.move(to: P(105.5, 33.2))
            p.addQuadCurve(to: P(123, 33), control: P(113, 28.8))
            p.addQuadCurve(to: P(105.5, 33.2), control: P(113, 36))
            p.closeSubpath()
            ovillo(&J, P(109, 33.2), P(118, 33), 1.1, en: &p)
            out.append(TrazoMascota(camino: p, color: nil, relleno: false, ojo: true))
        }
        func arco(_ x: Double, _ a: Double) {
            trazo(1.1) { p in p.move(to: P(x - 5.5, 33.5)); p.addQuadCurve(to: P(x + 5.5, 33.5), control: P(x, a)) }
        }
        if sonrie { arco(95.5, 27.5); arco(114, 27.5) }
        else if cerrados { arco(95.5, 36); arco(114, 36) }
        else if e == "guino" { ojoI(); arco(114, 36) }
        else { ojoI(); ojoD() }
        switch e {
        case "enfadado":
            trazo(1.5) { p in p.move(to: P(88, 25.5)); p.addLine(to: P(100, 30)); p.move(to: P(122, 26)); p.addLine(to: P(108, 30.2)) }
        case "animo", "sorpresa":
            trazo(1) { p in
                p.move(to: P(90, 26.5)); p.addQuadCurve(to: P(100, 26.5), control: P(95, 24.5))
                p.move(to: P(109, 26.5)); p.addQuadCurve(to: P(119, 26.5), control: P(114, 24.5))
            }
        case "ausente":
            trazo(1) { p in p.move(to: P(90, 29)); p.addLine(to: P(100, 26)); p.move(to: P(109, 26)); p.addLine(to: P(119, 29)) }
        default: break
        }
        func manchon() { trazo(2.3) { p in p.move(to: P(98.6, 41.2)); p.addLine(to: P(100.4, 42.6)) } }
        if sonrie {
            manchon()
            trazo(0.72, relleno: true) { p in
                p.move(to: P(99, 42)); p.addQuadCurve(to: P(111, 42), control: P(103, 50.5))
                p.addQuadCurve(to: P(99, 42), control: P(106, 44)); p.closeSubpath()
            }
        } else if e == "enfadado" {
            trazo(1) { p in
                p.move(to: P(98, 45.5))
                for (i, x) in [100.5, 103, 105.5, 108, 110.5].enumerated() { p.addLine(to: P(x, i % 2 == 0 ? 43 : 45.5)) }
            }
        } else if e == "ausente" {
            trazo(1) { p in p.move(to: P(99, 46.5)); p.addQuadCurve(to: P(110, 46.5), control: P(104, 41.5)) }
        } else if e == "bostezo" {
            trazo { p in ovillo(&J, P(101, 41), P(108, 50), 3.4, 2, en: &p) }
        } else if e == "guino" {
            manchon()
            trazo(1) { p in p.move(to: P(99.5, 42.5)); p.addQuadCurve(to: P(108, 42), control: P(103, 46.5)) }
        } else if e == "animo" || e == "dormido" || e == "sorpresa" {
            trazo { p in ovillo(&J, P(103, 42.5), P(106, 45.5), 1.5, 2, en: &p) }
        } else {
            manchon()
            trazo(0.95) { p in
                p.move(to: P(99.5, 42.8)); p.addQuadCurve(to: P(105, 46), control: P(101, 46))
                p.addQuadCurve(to: P(109.3, 42.2), control: P(107.8, 45.8))
            }
            trazo(0.55) { p in
                p.move(to: P(104, 45.4)); p.addLine(to: P(105.4, 43.4))
                p.move(to: P(106, 45.1)); p.addLine(to: P(107.2, 43.2))
                p.move(to: P(107.6, 44.4)); p.addLine(to: P(108.5, 42.8))
            }
        }
        return out
    }

    /// Mezcla dos colores hex (como `mezcla` en mascota.js).
    static func mezcla(_ a: String, _ b: String, _ t: Double) -> Color {
        let x = UIColor(css: a), y = UIColor(css: b)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        x.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        y.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let k = CGFloat(t)
        return Color(red: r1 + (r2 - r1) * k, green: g1 + (g2 - g1) * k, blue: b1 + (b2 - b1) * k)
    }
}
