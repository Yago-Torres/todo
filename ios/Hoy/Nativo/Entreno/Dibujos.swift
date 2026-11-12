import SwiftUI

// Los dibujos de Entreno: el monigote de cada ejercicio (static/monigotes.js, pasado a monigotes.json) y el mapa de
// músculos (react-body-highlighter, MIT, © 2020 GV79; en cuerpo.json). Los dos se pintan con Canvas y los colores del
// tema; el monigote va y viene entre la postura de inicio y la de final como en la web (2,4 s).

struct MonigoteDatos: Decodable {
    struct Cable: Decodable {
        var x: Double
        var y: Double
        var j: String
    }

    var lado: Bool
    var eq: [[Double]]
    var cable: [Cable]
    var peso: [String: Double]
    var placa: [String]
    var a: [String: [Double]]
    var b: [String: [Double]]

    static let todos: [String: MonigoteDatos] = {
        guard let url = Bundle.main.url(forResource: "monigotes", withExtension: "json"),
              let d = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: MonigoteDatos].self, from: d)) ?? [:]
    }()

    /// El de ese ejercicio (sin el « · 2ª vuelta» de las rutinas que lo repiten).
    static func de(_ ej: String) -> MonigoteDatos? {
        let limpio = ej.replacingOccurrences(of: " · 2ª vuelta", with: "")
        return todos[limpio]
    }
}

struct Monigote: View {
    let datos: MonigoteDatos
    @Environment(\.accessibilityReduceMotion) private var quieto

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: quieto)) { ctx in
            Canvas { g, tam in
                let t = quieto ? 0 : Self.fase(ctx.date.timeIntervalSinceReferenceDate)
                pinta(g, tam, t)
            }
        }
        .aspectRatio(60.0 / 44.0, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// 0 = postura a, 1 = postura b: a → b (40 %), quieto (10 %), b → a (40 %), quieto (10 %).
    static func fase(_ s: Double) -> Double {
        let x = s.truncatingRemainder(dividingBy: 2.4) / 2.4
        if x < 0.4 { return x / 0.4 }
        if x < 0.5 { return 1 }
        if x < 0.9 { return 1 - (x - 0.5) / 0.4 }
        return 0
    }

    private func pinta(_ g: GraphicsContext, _ tam: CGSize, _ t: Double) {
        let k = tam.width / 60
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * k, y: (y + 4) * k) }
        func j(_ n: String) -> CGPoint {
            let a = datos.a[n] ?? [30, 20], b = datos.b[n] ?? a
            return p(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
        }
        let color = Tema.texto
        let trazo = StrokeStyle(lineWidth: 2.2 * k, lineCap: .round, lineJoin: .round)
        func linea(_ a: CGPoint, _ b: CGPoint, opacidad: Double = 1, ancho: Double? = nil) {
            var path = Path()
            path.move(to: a)
            path.addLine(to: b)
            var s = trazo
            if let ancho { s.lineWidth = ancho * k }
            g.stroke(path, with: .color(color.opacity(opacidad)), style: s)
        }
        for l in datos.eq where l.count == 4 { linea(p(l[0], l[1]), p(l[2], l[3]), opacidad: 0.35, ancho: 1.6) }
        for c in datos.cable { linea(p(c.x, c.y), j(c.j), opacidad: 0.35, ancho: 1) }
        let lejos = datos.lado ? 0.4 : 1
        linea(j("n"), j("e2"), opacidad: lejos)
        linea(j("e2"), j("w2"), opacidad: lejos)
        linea(j("p"), j("k2"), opacidad: lejos)
        linea(j("k2"), j("f2"), opacidad: lejos)
        linea(j("n"), j("p"))
        linea(j("p"), j("k"))
        linea(j("k"), j("f"))
        linea(j("n"), j("e"))
        linea(j("e"), j("w"))
        for n in datos.placa {
            let c = j(n)
            linea(CGPoint(x: c.x + k, y: c.y - 5 * k), CGPoint(x: c.x + 3 * k, y: c.y + 4 * k), opacidad: 0.5)
        }
        let cab = j("h")
        g.fill(Path(ellipseIn: CGRect(x: cab.x - 3.4 * k, y: cab.y - 3.4 * k, width: 6.8 * k, height: 6.8 * k)), with: .color(color))
        for (n, r) in datos.peso {
            let c = j(n)
            g.fill(Path(ellipseIn: CGRect(x: c.x - r * k, y: c.y - r * k, width: 2 * r * k, height: 2 * r * k)), with: .color(color))
        }
    }
}

// MARK: el mapa de músculos

struct PiezaCuerpo: Decodable {
    var m: String
    var p: [Double]

    static let vistas: [(nombre: String, piezas: [PiezaCuerpo])] = {
        guard let url = Bundle.main.url(forResource: "cuerpo", withExtension: "json"),
              let d = try? Data(contentsOf: url),
              let todo = try? JSONDecoder().decode([String: [PiezaCuerpo]].self, from: d) else { return [] }
        return [("delante", todo["delante"] ?? []), ("detrás", todo["detras"] ?? [])]
    }()

    func camino(_ k: CGFloat) -> Path {
        var path = Path()
        var i = 0
        while i + 1 < p.count {
            let pt = CGPoint(x: p[i] * k, y: p[i + 1] * k)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            i += 2
        }
        path.closeSubpath()
        return path
    }
}

/// Delante y detrás, cada músculo del gris al acento según las series de los últimos 7 días. Tocar uno lo elige.
struct MapaCuerpo: View {
    let series: [String: Double]
    @Binding var elegido: String?

    var body: some View {
        HStack(spacing: Tema.Espacio.m) {
            ForEach(PiezaCuerpo.vistas, id: \.nombre) { vista in
                VStack(spacing: Tema.Espacio.xs) {
                    figura(vista.piezas)
                    Text(vista.nombre).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.tenue)
                }
                .frame(maxWidth: 170)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mapa de músculos. La misma información está en las barras de debajo.")
    }

    private func figura(_ piezas: [PiezaCuerpo]) -> some View {
        GeometryReader { geo in
            let k = geo.size.width / 100
            Canvas { g, _ in
                for pieza in piezas {
                    let path = pieza.camino(k)
                    g.fill(path, with: .color(color(pieza.m)))
                    let sel = !pieza.m.isEmpty && pieza.m == elegido
                    g.stroke(path, with: .color(sel ? Tema.texto : Tema.carta), lineWidth: sel ? 1.4 : 0.6)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { punto in
                let toca = piezas.last { !$0.m.isEmpty && $0.camino(k).contains(punto) }?.m
                withAnimation(Tema.Muelle.toque) { elegido = toca == elegido ? nil : toca }
                Haptica.shared.toca(.desmarcar)
            }
        }
        .aspectRatio(0.5, contentMode: .fit)
    }

    private func color(_ m: String) -> Color {
        guard !m.isEmpty else { return Tema.texto.opacity(0.12) }
        switch Musculos.nivel(series[m] ?? 0) {
        case 1: return Tema.acento.opacity(0.35)
        case 2: return Tema.acento.opacity(0.65)
        case 3: return Tema.acento
        default: return Tema.texto.opacity(0.16)
        }
    }
}
