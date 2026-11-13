import SwiftUI

/// El flujo del ciclo (la gráfica del README de Sure, hecha a nuestra manera): a la izquierda una barra con lo que entra
/// (sueldo + extras) y, de ella, una banda por categoría con grosor proporcional, la hucha de viajes y lo que queda.
/// Sin ingreso fijo, o si se gasta más de lo que entra, la barra es lo gastado. Las pequeñas (menos del 4 % o más allá de
/// la 7.ª) van juntas en «Otros». Tocar una banda la resalta y filtra los movimientos por esa categoría.
struct FlujoGastos: View {
    let r: ResumenGastos
    @Binding var filtro: String?
    @State private var datos = DatosGastos.shared
    /// La banda tocada que no es una sola categoría (Otros, la hucha, lo que queda): solo se resalta.
    @State private var elegida: String?
    @State private var avance: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reducir
    /// Hueco mínimo de cada etiqueta (nombre e importe): crece con el tamaño de letra y así nunca se pisan.
    @ScaledMetric(relativeTo: .footnote) private var hueco: CGFloat = 36

    struct Nodo: Identifiable {
        var id: String
        var nombre: String
        var valor: Double
        var color: Color
        var cats: [String]
        var agrupa: [String] = []
    }

    private struct Cuentas {
        var nodos: [Nodo] = []
        var entra = 0.0
        var gastado = 0.0
        var queda: Double { entra - gastado }
        var desdeIngresos: Bool { entra > 0 && queda >= 0 }
        var izquierda: Double { desdeIngresos ? entra : gastado }
    }

    private var cuentas: Cuentas {
        var l = r.cats.filter { $0.gastado > 0 }
            .map { Nodo(id: $0.id, nombre: $0.n, valor: $0.gastado, color: datos.color($0.id), cats: [$0.id]) }
        if r.aparte > 0 { l.append(Nodo(id: "_hucha", nombre: "Hucha de viajes", valor: r.aparte, color: Tema.acento, cats: [])) }
        l.sort { $0.valor > $1.valor }
        var c = Cuentas()
        c.gastado = l.reduce(0) { $0 + $1.valor }
        let pequenas = l.enumerated().filter { i, n in i >= 7 || n.valor < c.gastado * 0.04 || n.id == "otros" }.map(\.element)
        if pequenas.count > 1 {
            let ids = Set(pequenas.map(\.id))
            l.removeAll { ids.contains($0.id) }
            l.append(Nodo(id: "_otros", nombre: "Otros", valor: pequenas.reduce(0) { $0 + $1.valor },
                          color: datos.color("otros"), cats: pequenas.flatMap(\.cats), agrupa: pequenas.map(\.nombre)))
        }
        c.entra = r.ingreso > 0 ? r.ingreso + r.extra : 0
        if c.entra > 0 && c.queda > 0 {
            l.append(Nodo(id: "_queda", nombre: r.actual ? "Te queda" : "Ahorro", valor: c.queda, color: Tema.tenue, cats: []))
        }
        c.nodos = l
        return c
    }

    /// La banda resaltada: la de la categoría del filtro (venga de aquí o de «Por categoría») o la tocada.
    private func activa(_ nodos: [Nodo]) -> String? {
        if let filtro { return nodos.first { $0.cats.contains(filtro) }?.id }
        return elegida
    }

    var body: some View {
        let c = cuentas
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(c.desdeIngresos ? "Adónde va lo que entra" : "Adónde va lo gastado")
                    .font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
                Spacer()
                Text("\(c.desdeIngresos ? "Ingresos" : "Gastado") \(Eur.entero(c.izquierda))")
                    .font(Tema.fuente(.pequeno)).monospacedDigit().foregroundStyle(Tema.suave)
                    .contentTransition(.numericText(value: c.izquierda))
            }
            if c.nodos.isEmpty {
                Text("Nada que repartir en este ciclo.").font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            } else {
                grafica(c)
                Text(pie(c)).font(Tema.fuente(.pequeno)).foregroundStyle(c.entra > 0 && c.queda < 0 ? Tema.peligro : Tema.suave)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.interpolate)
            }
        }
        .carta()
        .onAppear { anima() }
        .onChange(of: r.inicio) { _, _ in anima() }
        .onChange(of: datos.instancia) { _, _ in anima() }
        .onChange(of: filtro) { _, nuevo in
            if nuevo == nil, let e = elegida, c.nodos.first(where: { $0.id == e })?.cats.count == 1 { elegida = nil }
        }
    }

    private func pie(_ c: Cuentas) -> String {
        if let a = activa(c.nodos), let n = c.nodos.first(where: { $0.id == a }), !n.agrupa.isEmpty {
            return "Otros junta: \(n.agrupa.joined(separator: ", "))."
        }
        if c.entra > 0 && c.queda < 0 { return "Gastas \(Eur.texto(-c.queda)) más de lo que entra este ciclo." }
        if c.entra > 0 {
            return "\(Eur.entero(c.gastado)) gastados, el \(Int((c.gastado * 100 / c.entra).rounded())) % de lo que entra. Toca una banda para ver sus movimientos."
        }
        return "Toca una banda para ver sus movimientos."
    }

    private func anima() {
        if reducir { avance = 1; return }
        avance = 0
        withAnimation(.spring(response: 1.0, dampingFraction: 0.9).delay(0.1)) { avance = 1 }
    }

    // MARK: dibujo

    private struct Geometria {
        var alturas: [CGFloat]
        var huecos: [CGFloat]
        var total: CGFloat
        var separacion: CGFloat
    }

    private func geometria(_ c: Cuentas) -> Geometria {
        let sep: CGFloat = 8, n = CGFloat(c.nodos.count)
        let base = max(200, n * (hueco + 8))
        let k = (base - sep * (n - 1)) / CGFloat(max(c.izquierda, 0.01))
        let alturas = c.nodos.map { max(2, CGFloat($0.valor) * k) }
        let huecos = alturas.map { max($0, hueco) }
        return Geometria(alturas: alturas, huecos: huecos, total: huecos.reduce(0, +) + sep * (n - 1), separacion: sep)
    }

    private func grafica(_ c: Cuentas) -> some View {
        let g = geometria(c)
        let resaltada = activa(c.nodos)
        return GeometryReader { geo in
            let ancho = geo.size.width
            let bx: CGFloat = 10, x1 = max(120, ancho * 0.42)
            let izqH = g.alturas.reduce(0, +), izq0 = (g.total - izqH) / 2
            // dónde empieza cada banda a la izquierda (apiladas) y dónde cae a la derecha (centrada en su hueco)
            let posiciones: [(yIzq: CGFloat, yDer: CGFloat, centro: CGFloat)] = {
                var salida: [(yIzq: CGFloat, yDer: CGFloat, centro: CGFloat)] = []
                var yIzq = izq0, ySlot: CGFloat = 0
                for i in c.nodos.indices {
                    salida.append((yIzq: yIzq, yDer: ySlot + (g.huecos[i] - g.alturas[i]) / 2, centro: ySlot + g.huecos[i] / 2))
                    yIzq += g.alturas[i]
                    ySlot += g.huecos[i] + g.separacion
                }
                return salida
            }()
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(c.nodos.enumerated()), id: \.element.id) { i, n in
                        let p = posiciones[i], h = g.alturas[i]
                        let forma = BandaFlujo(x0: bx, y0: p.yIzq, x1: x1, y1: p.yDer, h: h)
                        forma
                            .fill(n.color.opacity(resaltada == nil ? 0.32 : resaltada == n.id ? 0.6 : 0.08))
                            .contentShape(forma)
                            .onTapGesture { toca(n) }
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(n.color)
                            .frame(width: 8, height: h)
                            .offset(x: x1, y: p.yDer)
                            .opacity(resaltada == nil || resaltada == n.id ? 1 : 0.35)
                            .onTapGesture { toca(n) }
                    }
                }
                .mask(alignment: .leading) {
                    Rectangle().frame(width: max(bx, (x1 + 8) * avance))
                }
                .accessibilityHidden(true)

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Tema.texto.opacity(0.8))
                    .frame(width: bx, height: izqH)
                    .offset(y: izq0)
                    .accessibilityHidden(true)

                ForEach(Array(c.nodos.enumerated()), id: \.element.id) { i, n in
                    etiqueta(n, c: c, elegida: resaltada == n.id, apagada: resaltada != nil && resaltada != n.id)
                        .frame(width: max(60, ancho - x1 - 16), alignment: .leading)
                        .position(x: x1 + 16 + max(60, ancho - x1 - 16) / 2, y: posiciones[i].centro)
                        .opacity(Double(avance))
                }
            }
        }
        .frame(height: g.total)
        .animation(Tema.Muelle.pantalla, value: resaltada)
        .animation(Tema.Muelle.pantalla, value: c.nodos.map(\.valor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Flujo del ciclo")
    }

    private func etiqueta(_ n: Nodo, c: Cuentas, elegida: Bool, apagada: Bool) -> some View {
        let pct = Int((n.valor * 100 / max(c.izquierda, 0.01)).rounded())
        return Button { toca(n) } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(n.nombre)
                    .font(Tema.fuente(.pequeno, peso: elegida ? .semibold : .regular))
                    .foregroundStyle(Tema.texto).lineLimit(1)
                Text("\(Eur.texto(n.valor)) · \(pct) %")
                    .font(Tema.fuente(.etiqueta)).monospacedDigit()
                    .foregroundStyle(Tema.suave).lineLimit(1)
                    .contentTransition(.numericText(value: n.valor))
            }
            .minimumScaleFactor(0.8)
            .opacity(apagada ? 0.4 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(n.nombre): \(Eur.texto(n.valor)), el \(pct) %")
        .accessibilityHint(n.cats.count == 1 ? "Filtra los movimientos por esta categoría" : "Resalta esta banda")
        .accessibilityAddTraits(elegida ? .isSelected : [])
    }

    private func toca(_ n: Nodo) {
        Haptica.shared.toca(.marcar)
        withAnimation(Tema.Muelle.pantalla) {
            let ya = activa(cuentas.nodos) == n.id
            if ya {
                elegida = nil
                filtro = nil
            } else {
                elegida = n.id
                filtro = n.cats.count == 1 ? n.cats[0] : nil
            }
        }
    }
}

/// Una banda: de (x0, y0) a la izquierda a (x1, y1) a la derecha, de grosor h, con los bordes en curva bezier.
struct BandaFlujo: Shape {
    var x0: CGFloat
    var y0: CGFloat
    var x1: CGFloat
    var y1: CGFloat
    var h: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(y0, y1), h) }
        set { y0 = newValue.first.first; y1 = newValue.first.second; h = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let xm = (x0 + x1) / 2
        p.move(to: CGPoint(x: x0, y: y0))
        p.addCurve(to: CGPoint(x: x1, y: y1), control1: CGPoint(x: xm, y: y0), control2: CGPoint(x: xm, y: y1))
        p.addLine(to: CGPoint(x: x1, y: y1 + h))
        p.addCurve(to: CGPoint(x: x0, y: y0 + h), control1: CGPoint(x: xm, y: y1 + h), control2: CGPoint(x: xm, y: y0 + h))
        p.closeSubpath()
        return p
    }
}
