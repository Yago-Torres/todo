import SwiftUI

// El aparato Oficina (id "oficina"): la carcasa de invest y su pixel art, como en la web (~/estilo/oficina.css y
// oficina.js). Yago lo eligió en el probador de tres sobre su Hoy (se quedó con dos juntas, 25/11):
// - la base limpia de invest: blanco y negro, cartas planas con borde fino, Inter (PaletaAparato, EstiloCarta, Aspecto);
// - en Hoy, la franja de la oficina: cada hábito de hoy es un trabajador en su mesa; pendiente, teclea; hecho, deja el
//   papel y la banderita y se va a casa. El despacho de la derecha es el tuyo: te duermes cuando todos han acabado;
// - al final de Hoy, los becarios (en la web van en la esquina; en el iPhone no caben ahí): pasean, toman café, se duermen
//   y sueltan tonterías, precios inventados (de cosas o de tickers falsos: nunca de valores reales) y tus cifras.
// La luz sigue la altura real del sol en España: se mezcla entre noche, hora azul, atardecer, hora dorada y día.
// Todo se dibuja con rectángulos en un Canvas (sin imágenes); con «reducir movimiento», un fotograma por segundo.

extension Tema {
    /// Oficina: la base de invest con su pixel art.
    static var oficina: Bool { actual.aparato == "oficina" }
}

// MARK: la luz del día

/// Los colores de la oficina dibujada según la altura del sol (como luz() en oficina.js).
struct LuzOficina {
    private var colores: [String: Color] = [:]
    var noche = false
    var horizonte = false
    var solBajo = false
    /// 0–1: los flexos se van encendiendo al oscurecer.
    var lamparas = 0.0

    subscript(_ k: String) -> Color { colores[k] ?? .gray }

    private static let claves = ["pared", "zocalo", "suelo", "suelo2", "muro", "marco", "cielo", "cielo2", "nube",
                                 "mesa", "mesa2", "monitor", "apagada", "luz", "luz2", "papel", "tinta"]
    private static let noche_: [String] = ["#2c2e3d", "#23242f", "#3b3431", "#36302d", "#1c1d26", "#4d4a58", "#141a3a", "#141a3a", "#e8e6c8",
                                           "#73513a", "#56392a", "#16181d", "#2d333d", "#8ff0ff", "#e3fbff", "#e9e9ef", "#1f2228"]
    private static let azul: [String] = ["#5b5f7a", "#4e5169", "#6b6058", "#645a52", "#3e4055", "#5d5a68", "#3b4a86", "#c77d8f", "#e6d6e0",
                                         "#8a6143", "#6a4630", "#1e2127", "#363c47", "#86ecff", "#dcfaff", "#f1f1f5", "#262a30"]
    private static let atardecer: [String] = ["#efdfca", "#d8c6aa", "#dcc3a0", "#d3b994", "#b8a284", "#8c7a62", "#f4a261", "#f6c98b", "#ffe1b8",
                                              "#a3734b", "#7d5535", "#2b2f36", "#4a5260", "#7fe3ff", "#d2f7ff", "#ffffff", "#30343b"]
    private static let dorada: [String] = ["#f1e1c4", "#dccaa4", "#e2c79c", "#d9bc90", "#bea684", "#8f7b5f", "#f7c37c", "#fbe0a8", "#fff1d6",
                                           "#a3734b", "#7d5535", "#2b2f36", "#4a5260", "#7fe3ff", "#d2f7ff", "#ffffff", "#30343b"]
    private static let dia: [String] = ["#ebe4d2", "#d3c9b0", "#dcc9a6", "#d4c09a", "#b9ab8b", "#8c8068", "#a9d8f5", "#a9d8f5", "#ffffff",
                                        "#a3734b", "#7d5535", "#2b2f36", "#4a5260", "#7fe3ff", "#d2f7ff", "#ffffff", "#30343b"]

    /// La altura del sol (grados) en España (40,4° N, 3,7° O), con la declinación y la ecuación del tiempo.
    static func altura(_ d: Date = Date()) -> Double {
        let cal = Calendar.current
        let n = Double(cal.ordinality(of: .day, in: .year, for: d) ?? 1)
        let rad = Double.pi / 180
        let decl = 23.44 * rad * sin(2 * .pi * (284 + n) / 365)
        let b = 2 * Double.pi * (n - 81) / 364
        let eot = (9.87 * sin(2 * b) - 7.53 * cos(b) - 1.5 * sin(b)) / 60
        let huso = Double(TimeZone.current.secondsFromGMT(for: d)) / 3600
        let mediodia = 12 + 3.7 / 15 - eot + huso
        let c = cal.dateComponents([.hour, .minute], from: d)
        let hora = Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60
        let lat = 40.4 * rad, ang = (hora - mediodia) * 15 * rad
        return asin(sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(ang)) / rad
    }

    static func ahora(_ d: Date = Date()) -> LuzOficina {
        let e = altura(d)
        let marcas: [(Double, [String])] = [(-18, noche_), (-7, azul), (-1, atardecer), (7, dorada), (22, dia)]
        let i = marcas.firstIndex { e < $0.0 }
        let (x0, a) = marcas[max(0, (i ?? marcas.count) - 1)]
        let (x1, b) = marcas[min(i ?? marcas.count - 1, marcas.count - 1)]
        let f: Double = i == nil ? 1 : (i == 0 ? 0 : (e - x0) / (x1 - x0))
        var luz = LuzOficina()
        for (j, k) in claves.enumerated() { luz.colores[k] = mezcla(a[j], b[j], f) }
        luz.noche = e < -7
        luz.horizonte = e > -8 && e < 10
        luz.solBajo = e > -1.5 && e < 9
        luz.lamparas = max(0, min(1, (4 - e) / 12))
        return luz
    }

    private static func rgb(_ h: String) -> (Double, Double, Double) {
        let v = UInt32(h.dropFirst(), radix: 16) ?? 0
        return (Double((v >> 16) & 255), Double((v >> 8) & 255), Double(v & 255))
    }

    private static func mezcla(_ a: String, _ b: String, _ f: Double) -> Color {
        let (r1, g1, b1) = rgb(a), (r2, g2, b2) = rgb(b)
        return Color(red: (r1 + (r2 - r1) * f) / 255, green: (g1 + (g2 - g1) * f) / 255, blue: (b1 + (b2 - b1) * f) / 255)
    }
}

// MARK: dibujar con píxeles

/// Un pincel de píxeles: cada píxel lógico es un cuadrado de k puntos.
struct Pixeles {
    let g: GraphicsContext
    let k: CGFloat

    func r(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ c: Color) {
        g.fill(Path(CGRect(x: x * k, y: y * k, width: w * k, height: h * k)), with: .color(c))
    }
}

enum DibujoOficina {
    static let pelo = ["#2b1d14", "#5a3a1e", "#c08a3e", "#1a1a1a", "#8b4a2b", "#d9c27a", "#6d6d6d", "#a33b2b"].map { Color(hex: $0) }
    static let piel = ["#f2d0b1", "#e0b18f", "#c68c62", "#8d5a3b", "#f6dcc4"].map { Color(hex: $0) }
    static let camisa = ["#2a78d6", "#8b5cf6", "#eb6834", "#0e9bb5", "#d08a2e", "#64748b"].map { Color(hex: $0) }
    static let negro = Color(hex: "#222222")

    /// Un número fijo para cada nombre (el hashValue de Swift cambia en cada arranque).
    static func semilla(_ t: String) -> Int {
        var a: UInt32 = 7
        for u in t.unicodeScalars { a = a &* 31 &+ u.value }
        return Int(a % 100_000)
    }

    enum Pose { case teclea, quieto, duerme }

    /// Un muñeco de 8×10 visto de frente.
    static func muneco(_ p: Pixeles, _ x: Double, _ y: Double, semilla s: Int, pose: Pose, t: Int, camisa c: Color? = nil, corbata: Bool = false) {
        let pe = pelo[s % pelo.count], pi = piel[(s >> 3) % piel.count], ca = c ?? camisa[(s >> 5) % camisa.count]
        p.r(x + 2, y, 4, 1, pe); p.r(x + 1, y + 1, 6, 1, pe); p.r(x + 1, y + 2, 1, 2, pe); p.r(x + 6, y + 2, 1, 2, pe)
        if s % 3 == 0 { p.r(x + 1, y + 4, 1, 1, pe); p.r(x + 6, y + 4, 1, 1, pe) }
        p.r(x + 2, y + 2, 4, 3, pi); p.r(x + 3, y + 5, 2, 1, pi)
        let cerrados = pose == .duerme || (t + s * 7) % 37 == 0
        p.r(x + 3, y + 3, 1, 1, cerrados ? pi : negro); p.r(x + 5, y + 3, 1, 1, cerrados ? pi : negro)
        if pose == .duerme { p.r(x + 3, y + 4, 1, 1, negro); p.r(x + 5, y + 4, 1, 1, negro) }
        p.r(x + 1, y + 6, 6, 4, ca)
        p.r(x + 3, y + 6, 2, 1, .white)
        if corbata { p.r(x + 4, y + 7, 1, 2, Color(hex: "#30343b")) }
        if pose == .teclea {
            let f = Double((t + s) % 2)
            p.r(x + f, y + 8, 1, 1, pi); p.r(x + 6 + f, y + 8, 1, 1, pi)
        } else {
            p.r(x + 1, y + 8, 1, 1, pi); p.r(x + 6, y + 8, 1, 1, pi)
        }
    }

    enum Mesa { case teclea, quieta, hecha }

    /// La mesa delante del muñeco, con su pantalla (encendida si teclea), y el papel y la banderita de lo hecho.
    static func mesa(_ p: Pixeles, _ luz: LuzOficina, _ x: Double, _ y: Double, _ que: Mesa, t: Int, semilla s: Int, planta: Bool = false) {
        let mx = x - 3, my = y + 9, ancho = 15.0
        p.r(x + 8, y + 3, 6, 5, luz["monitor"]); p.r(x + 10, y + 8, 2, 1, luz["monitor"])
        p.r(x + 9, y + 4, 4, 3, que == .teclea ? ((t + s) % 4 < 2 ? luz["luz"] : luz["luz2"]) : luz["apagada"])
        if que == .teclea { p.r(x + 9, y + 4 + Double((t + s) % 3), Double(t % 3 + 2), 1, luz["monitor"]) }
        p.r(mx, my, ancho, 2, luz["mesa"])
        p.r(mx, my + 2, ancho, 4, luz["mesa2"]); p.r(mx + 1, my + 6, 1, 2, luz["mesa2"]); p.r(mx + ancho - 2, my + 6, 1, 2, luz["mesa2"])
        if que == .hecha {
            p.r(x + 1, my - 1, 4, 1, luz["papel"]); p.r(x + 2, my - 1, 2, 1, luz["tinta"])
            p.r(mx + ancho - 2, my - 5, 1, 5, Color(hex: "#8a8f98")); p.r(mx + ancho - 5, my - 5, 3, 2, Color(hex: "#0a9f5a"))
        }
        if planta {
            p.r(mx + ancho + 1, my - 6, 4, 5, Color(hex: "#3e8e4e")); p.r(mx + ancho, my - 8, 2, 3, Color(hex: "#3e8e4e"))
            p.r(mx + ancho + 1, my - 1, 4, 4, Color(hex: "#9a5b3a"))
        }
    }

    /// Las zetas de quien duerme.
    static func zetas(_ p: Pixeles, _ x: Double, _ y: Double, t: Int) {
        let z = Double((t >> 1) % 8)
        p.r(x + (z >= 4 ? 1 : 0), y - z, 2, 1, Color(hex: "#8a8f98"))
    }

    /// Paso de la franja: cada mesa ocupa 18 píxeles.
    static let paso = 18.0

    /// La franja de Hoy, de W×46 píxeles lógicos.
    static func franja(_ p: Pixeles, W: Double, habitos: [(String, Bool)], t: Int, luz: LuzOficina) {
        let H = 46.0
        p.r(0, 0, W, H, luz["suelo"])
        var y = 14.0
        while y < H {
            var x = Int(y / 6) % 2 == 1 ? 0.0 : 6.0
            while x < W { p.r(x, y, 6, 6, luz["suelo2"]); x += 12 }
            y += 6
        }
        p.r(0, 0, W, 12, luz["pared"]); p.r(0, 12, W, 2, luz["zocalo"])
        var vx = 14.0
        while vx < W - 44 {   // ventanas: nubes de día, horizonte y sol bajo al amanecer y al atardecer, estrellas de noche
            p.r(vx - 1, 2, 16, 9, luz["marco"]); p.r(vx, 3, 14, 7, luz["cielo"])
            if luz.horizonte {
                p.r(vx, 7, 14, 3, luz["cielo2"])
                if luz.solBajo { p.r(vx + 9, 7, 2, 2, Color(hex: "#ffd166")) }
            }
            if luz.noche {
                p.r(vx + 3, 5, 1, 1, luz["nube"]); p.r(vx + 10, 7, 1, 1, luz["nube"])
                if (t + Int(vx)) % 16 < 9 { p.r(vx + 12, 4, 1, 1, luz["nube"]) }
            } else {
                p.r(vx + Double((t / 6 + Int(vx)) % 11), 5, 3, 1, luz["nube"])
            }
            p.r(vx + 7, 3, 1, 7, luz["marco"])
            vx += 48
        }
        let todos = !habitos.isEmpty && habitos.allSatisfy { $0.1 }
        if luz.lamparas > 0 {   // flexos en las mesas con gente: se encienden al oscurecer
            for (i, h) in habitos.enumerated() where !h.1 {
                let x = 8 + Double(i) * paso
                for (radio, alfa) in [(9.0, 0.05), (7.0, 0.07), (5.0, 0.09)] {
                    p.r(x + 4 - radio, 24 - radio, radio * 2, radio * 2, Color(hex: "#ffd27a").opacity(alfa * luz.lamparas))
                }
            }
        }
        for (i, h) in habitos.enumerated() {
            let x = 8 + Double(i) * paso, s = semilla(h.0.isEmpty ? String(i) : h.0)
            if !h.1 { muneco(p, x, 18, semilla: s, pose: .teclea, t: t) }
            mesa(p, luz, x, 18, h.1 ? .hecha : .teclea, t: t, semilla: s)
        }
        // tu despacho, a la derecha
        p.r(W - 36, 0, 2, 14, luz["muro"]); p.r(W - 36, 31, 2, H - 31, luz["muro"])
        muneco(p, W - 24, 18, semilla: 99, pose: todos ? .duerme : .quieto, t: t, camisa: Color(hex: "#64748b"), corbata: true)
        mesa(p, luz, W - 24, 18, todos ? .hecha : .quieta, t: t, semilla: 99, planta: true)
        if todos { zetas(p, W - 14, 16, t: t) }
    }
}

// MARK: la franja de Hoy

/// Tus hábitos de hoy como un equipo: cada uno en su mesa. Los que caben (en un iPhone, unos 7).
struct FranjaOficina: View {
    let habitos: [Habito]
    @Environment(\.accessibilityReduceMotion) private var quieto
    @Environment(\.scenePhase) private var fase

    private let k: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let W = max(150, Double(Int(geo.size.width / k)))
            let cabe = max(3, Int((W - 46) / DibujoOficina.paso))
            let hs = habitos.prefix(cabe).map { ($0.n, $0.listo) }
            TimelineView(.animation(minimumInterval: quieto ? 1 : 0.15, paused: fase != .active)) { ctx in
                let t = Int(ctx.date.timeIntervalSinceReferenceDate / 0.15)
                let luz = LuzOficina.ahora(ctx.date)
                Canvas { g, _ in
                    DibujoOficina.franja(Pixeles(g: g, k: k), W: W, habitos: hs, t: t, luz: luz)
                }
            }
        }
        .frame(height: 46 * k)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Tema.linea, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tu equipo de hábitos: \(habitos.filter { !$0.listo }.count) trabajando y \(habitos.filter(\.listo).count) ya en casa")
    }
}

// MARK: los becarios

/// Los becarios de la oficina, al final de Hoy: sin suelo, con su sombra, haciendo cosas y soltando tonterías.
/// Todo sale del reloj (no guardan estado): cada uno tiene su ronda de paradas, y cada pocos segundos alguno habla.
struct BecariosOficina: View {
    /// Frases con tus cifras (las añade Hoy): «hábitos 5/13... el jefe mira».
    var datos: [String] = []
    @Environment(\.accessibilityReduceMotion) private var quieto
    @Environment(\.scenePhase) private var fase

    private let k: CGFloat = 3
    private static let frases = ["hfgnc... nose nose", "nose nose nose", "¿es viernes?", "brrr", "¿quién tiene mi grapadora?", "mmm... café", "zzz", "¿eh?",
                                 "nada, nada", "esto ya está descontado", "la línea sube", "bfff", "vale pero ¿por qué?", "primero café", "*mueve papeles*",
                                 "grblx...", "¿comemos?", "bip bup", "mmm.", "¡diversifica!", "¿y si no?", "hoy sí que sí", "mañana empiezo", "uf, qué sueño"]
    private static let cosas: [(String, Double)] = [("café", 1.2), ("plátanos/kg", 0.89), ("chicle", 0.5), ("pizza", 9.9), ("patito de goma", 3.5),
                                                     ("cruasán", 1.6), ("grapadora", 7.2), ("una siesta", 0.01), ("DUCK", 42), ("BNNA", 13.37),
                                                     ("SNAK", 4.2), ("MEOW", 88.8), ("NAP", 0.99), ("CAFE", 21.5), ("BLOOP", 6.66)]
    /// Las rondas de los dos que pasean: (x de la parada, ticks que se quedan). Planta 6, pantalla 27, cafetera 47.
    private static let rondas: [[(Double, Int)]] = [[(47, 50), (27, 40), (6, 30), (40, 25)], [(6, 35), (47, 45), (20, 30), (27, 40)]]

    var body: some View {
        TimelineView(.animation(minimumInterval: quieto ? 1 : 0.16, paused: fase != .active)) { ctx in
            let t = Int(ctx.date.timeIntervalSinceReferenceDate / 0.16)
            let luz = LuzOficina.ahora(ctx.date)
            let paseo = Self.rondas.enumerated().map { Self.donde($0.element, t: t + $0.offset * 97) }
            let durmiendo = (t / 180) % 5 == 0
            let habla = globo(t: t, paseo: paseo, durmiendo: durmiendo)
            ZStack(alignment: .topLeading) {
                Canvas { g, _ in
                    dibuja(Pixeles(g: g, k: k), luz: luz, t: t, paseo: paseo, durmiendo: durmiendo)
                }
                .frame(width: 62 * k, height: 40 * k)
                if let h = habla {
                    Text(h.0)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color(hex: "#222222"))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                        .position(x: h.1 * k, y: 4 * k)
                        .transition(.opacity)
                }
            }
            .frame(width: 62 * k, height: 40 * k)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .accessibilityHidden(true)
    }

    /// Dónde está uno que pasea y qué hace: (x, «anda» | «cafe» | «mira»).
    private static func donde(_ ronda: [(Double, Int)], t: Int) -> (Double, String) {
        var tramos: [(desde: Double, hasta: Double, anda: Int, queda: Int)] = []
        for (i, parada) in ronda.enumerated() {
            let previa = ronda[(i + ronda.count - 1) % ronda.count].0
            tramos.append((previa, parada.0, Int(abs(parada.0 - previa)) * 2, parada.1))
        }
        let total = tramos.reduce(0) { $0 + $1.anda + $1.queda }
        var r = t % max(1, total)
        for tr in tramos {
            if r < tr.anda {
                let f = Double(r) / Double(max(1, tr.anda))
                return ((tr.desde + (tr.hasta - tr.desde) * f).rounded(), "anda")
            }
            r -= tr.anda
            if r < tr.queda { return (tr.hasta, abs(tr.hasta - 47) < 3 ? "cafe" : "mira") }
            r -= tr.queda
        }
        return (ronda[0].0, "mira")
    }

    /// Quién habla ahora y qué dice (uno cada ~7 s, durante ~3,5 s).
    private func globo(t: Int, paseo: [(Double, String)], durmiendo: Bool) -> (String, Double)? {
        let ranura = t / 44
        let s = DibujoOficina.semilla("globo\(ranura)")
        guard s % 3 != 0, t % 44 < 22 else { return nil }
        let quien = s % 3
        let x = quien == 0 ? 17.0 : paseo[quien - 1].0 + 4
        if quien == 0 && durmiendo { return ("zzz...", x) }
        let r = (s / 7) % 100
        if !datos.isEmpty && r < 25 { return (datos[s % datos.count], x) }
        if r < 60 {
            let (que, base) = Self.cosas[s % Self.cosas.count]
            let precio = base * (0.7 + Double((s / 11) % 70) / 100)
            let euros = precio.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "es_ES"))) + " €"
            if que == que.uppercased() {
                let cambio = Double((s / 13) % 90) / 10 - 4.5
                let pct = abs(cambio).formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "es_ES")))
                return ("\(que) \(euros) \(cambio >= 0 ? "▲" : "▼")\(pct) %", x)
            }
            return ("\(que) \(euros)", x)
        }
        return (Self.frases[s % Self.frases.count], x)
    }

    private func dibuja(_ p: Pixeles, luz: LuzOficina, t: Int, paseo: [(Double, String)], durmiendo: Bool) {
        let sombra = Color.black.opacity(0.16)
        func suelo(_ x: Double, _ w: Double) { p.r(x + 1, 34, w - 2, 1, sombra); p.r(x, 35, w, 1, sombra) }
        // pantalla de pie con una gráfica que no significa nada, planta y cafetera
        p.r(19, 4, 20, 11, luz["monitor"]); p.r(20, 5, 18, 9, Color(hex: "#11161c"))
        var a = 4
        for i in 1..<18 {
            let v = max(0, min(8, 4 + (DibujoOficina.semilla("g\(t / 3 + i)") % 7) - 3))
            p.r(20 + Double(i), 5 + Double(min(a, v)), 1, Double(abs(a - v) + 1), Color(hex: v <= a ? "#2fd17a" : "#ff5d62"))
            a = v
        }
        p.r(28, 15, 2, 19, luz["monitor"]); p.r(24, 33, 10, 1, luz["monitor"])
        p.r(3, 22, 5, 7, Color(hex: "#3e8e4e")); p.r(2, 20, 2, 3, Color(hex: "#3e8e4e")); p.r(7, 19, 2, 4, Color(hex: "#3e8e4e")); p.r(3, 29, 5, 5, Color(hex: "#9a5b3a"))
        p.r(50, 20, 8, 14, Color(hex: "#6b6f78")); p.r(51, 25, 6, 4, Color(hex: "#454950")); p.r(56, 22, 1, 1, Color(hex: t % 10 < 5 ? "#ff5d62" : "#7a2a2c"))
        suelo(2, 7); suelo(23, 12); suelo(49, 10); suelo(9, 17)
        // el de la mesa: teclea, y a ratos se duerme
        DibujoOficina.muneco(p, 13, 17, semilla: 11, pose: durmiendo ? .duerme : .teclea, t: t)
        if durmiendo { DibujoOficina.zetas(p, 21, 17, t: t) }
        DibujoOficina.mesa(p, luz, 13, 17, durmiendo ? .quieta : .teclea, t: t, semilla: 11)
        // los dos que pasean
        for (i, (x, que)) in paseo.enumerated() {
            let s = i == 0 ? 23 : 47
            suelo(x, 8)
            DibujoOficina.muneco(p, x, 21, semilla: s, pose: .quieto, t: t)
            let gris = Color(hex: "#3b3f4a"), paso = que == "anda" ? (t >> 1) % 2 : 0
            p.r(x + 2, 31, 4, 2, gris)
            p.r(x + 2, 33, 1, paso == 1 ? 1 : 2, gris); p.r(x + 5, 33, 1, paso == 1 ? 2 : 1, gris)
            if que == "cafe" {
                p.r(x + 6, 28, 2, 2, .white)
                if t % 6 < 3 { p.r(x + 7, 26, 1, 1, Color(hex: "#c9c9c9")) }
            }
        }
    }
}
