import SwiftUI

// Las carcasas Solarpunk, Plano y Conserje (ids "solar", "plano", "conserje"): las de la web (~/estilo/solar.css,
// plano.css y conserje.css) en SwiftUI. juno1980 vive en Compartido/Juno.swift porque la usa también el widget.
// Calma no pasa por aquí.

extension Tema {
    /// Solarpunk: portada con foto en Hoy, cartas blancas muy redondas y arcos de sol.
    static var solar: Bool { actual.aparato == "solar" }
    /// Plano: plano de ingeniería (tinta azul sobre papel; de noche, cianotipo), cotas y marcas de registro.
    static var plano: Bool { actual.aparato == "plano" }
    /// Conserje: gran hotel de los años 30, marcos dobles granate y oro, medallones.
    static var conserje: Bool { actual.aparato == "conserje" }
}

/// Plano y Conserje mandan sobre los colores del tema (en la web, sus tokens van con !important).
enum PaletaAparato {
    static func aplica(_ p: inout Paleta, aparato: String) {
        switch aparato {
        case "plano":
            p.fondo = .init(claro: "#F6F9FD", oscuro: "#123B70")
            p.carta = .init(claro: "#F6F9FD", oscuro: "#123B70")
            p.cartaLuz = p.carta
            p.carta2 = .init(claro: "rgba(27, 79, 156, .06)", oscuro: "rgba(234, 242, 255, .07)")
            p.texto = .init(claro: "#12305E", oscuro: "#EAF2FF")
            p.suave = .init(claro: "#4F6A93", oscuro: "#B5CBEA")
            p.tenue = .init(claro: "#8299BB", oscuro: "#7F9CC6")
            p.linea = .init(claro: "rgba(27, 79, 156, .3)", oscuro: "rgba(234, 242, 255, .3)")
            p.acento = .init(claro: "#1B4F9C", oscuro: "#EAF2FF")
            p.acentoTexto = .init(claro: "#F6F9FD", oscuro: "#123B70")
            p.acentoSuave = .init(claro: "rgba(27, 79, 156, .1)", oscuro: "rgba(234, 242, 255, .12)")
            p.dock = .init(claro: "#F6F9FD", oscuro: "#123B70")
            p.dockTexto = .init(claro: "#1B4F9C", oscuro: "#EAF2FF")
        case "conserje":
            p.fondo = .init(claro: "#F3DCDA", oscuro: "#22111A")
            p.carta = .init(claro: "#FFF8EF", oscuro: "#301A25")
            p.cartaLuz = p.carta
            p.carta2 = .init(claro: "#F7E9E2", oscuro: "#3A2130")
            p.texto = .init(claro: "#3A1B26", oscuro: "#F6E6EA")
            p.suave = .init(claro: "#7B5560", oscuro: "#CDAAB5")
            p.tenue = .init(claro: "#A88C93", oscuro: "#92717C")
            p.linea = .init(claro: "rgba(126, 36, 64, .2)", oscuro: "rgba(229, 138, 164, .22)")
            p.acento = .init(claro: "#7E2440", oscuro: "#E58AA4")
            p.acentoTexto = .init(claro: "#FFF4E2", oscuro: "#2A0F1B")
            p.acentoSuave = .init(claro: "#F4D8DC", oscuro: "#48223A")
            p.dock = .init(claro: "#6B1E37", oscuro: "#4A1A2C")
            p.dockTexto = .init(claro: "#F6E2B8", oscuro: "#F2D69A")
        default:
            break
        }
    }
}

enum Conserje {
    static let oro = Color(hex: "#B88A3E")
    static let oroClaro = Color(hex: "#E2C27E")
}

// MARK: cartas

/// Plano: la pieza sin relleno, con su contorno y las marcas de registro en las esquinas.
struct PanelPlano: View {
    var body: some View {
        Rectangle().fill(Tema.carta.opacity(0.82))
            .overlay(Rectangle().strokeBorder(Tema.acento, lineWidth: 1.5))
            .overlay(MarcasRegistro().stroke(Tema.acento, lineWidth: 1).padding(-7))
    }
}

/// Las cruces de las cuatro esquinas de un plano.
struct MarcasRegistro: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let l: CGFloat = 12, m: CGFloat = 6
        for (x, y) in [(r.minX, r.minY), (r.maxX, r.minY), (r.minX, r.maxY), (r.maxX, r.maxY)] {
            let cx = x == r.minX ? x + m : x - m, cy = y == r.minY ? y + m : y - m
            p.move(to: CGPoint(x: cx - l / 2, y: cy)); p.addLine(to: CGPoint(x: cx + l / 2, y: cy))
            p.move(to: CGPoint(x: cx, y: cy - l / 2)); p.addLine(to: CGPoint(x: cx, y: cy + l / 2))
        }
        return p
    }
}

/// Conserje: crema con marco doble, granate por fuera y oro por dentro.
struct MarcoConserje: View {
    var body: some View {
        Rectangle().fill(Tema.carta)
            .overlay(Rectangle().strokeBorder(Tema.acento, lineWidth: 1.5))
            .overlay(Rectangle().strokeBorder(Conserje.oro, lineWidth: 1).padding(5))
            .shadow(color: Tema.acento.opacity(0.18), radius: 0, x: 0, y: 4)
    }
}

/// Solarpunk: carta blanca, sin borde, muy redonda y con una sombra suave.
struct CartaSolar: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Tema.carta)
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
    }
}

// MARK: medidores de Hoy

/// Solarpunk: medio círculo que se llena hasta el objetivo (como calma.arco en la web).
struct ArcoSol: View {
    let valor: Double
    let cifra: String
    let que: String
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reducir
    @State private var visto = 0.0

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                MedioArco().stroke(Tema.carta2, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                MedioArco().trim(from: 0, to: max(0.001, min(visto, 1)))
                    .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
            }
            .aspectRatio(100 / 56, contentMode: .fit)
            .frame(maxWidth: 120)
            Text(cifra).font(.custom("Fraunces", size: 19, relativeTo: .headline).weight(.semibold))
                .foregroundStyle(Tema.texto).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(que).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .onAppear { if reducir { visto = valor } else { withAnimation(.spring(response: 0.9, dampingFraction: 0.8).delay(0.1)) { visto = valor } } }
        .onChange(of: valor) { _, nuevo in withAnimation(reducir ? nil : Tema.Muelle.toque) { visto = nuevo } }
    }
}

private struct MedioArco: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let radio = min(r.width / 2, r.height) - 5
        p.addArc(center: CGPoint(x: r.midX, y: r.maxY - 5), radius: radio, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        return p
    }
}

/// Plano: una cota con el rayado hasta el valor y la cifra encima (como calma.cota).
struct CotaPlano: View {
    let valor: Double
    let cifra: String
    let que: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(que.uppercased()).font(.custom("JetBrains Mono", size: 10.5)).tracking(0.6).foregroundStyle(Tema.suave)
                Spacer()
                Text(cifra).font(.custom("JetBrains Mono", size: 15).weight(.bold)).foregroundStyle(Tema.acento).monospacedDigit()
            }
            GeometryReader { g in
                let w = g.size.width, f = max(0, min(1, valor.isFinite ? valor : 0))
                ZStack(alignment: .leading) {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 0, y: 22))
                        p.move(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: 22))
                        p.move(to: CGPoint(x: 0, y: 11)); p.addLine(to: CGPoint(x: w, y: 11))
                        for i in 1..<10 { let x = w * CGFloat(i) / 10; p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: 5)) }
                    }
                    .stroke(Tema.acento.opacity(0.7), lineWidth: 1)
                    Rayado().stroke(valor > 1 ? Tema.peligro : Tema.acento, lineWidth: 1.5)
                        .frame(width: w * f, height: 14).clipped()
                        .overlay(alignment: .trailing) { Rectangle().fill(Tema.acento).frame(width: 2) }
                        .offset(y: 0)
                }
            }
            .frame(height: 22)
        }
    }
}

/// El rayado a 45° de un plano.
struct Rayado: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        var x = r.minX - r.height
        while x < r.maxX {
            p.move(to: CGPoint(x: x, y: r.maxY)); p.addLine(to: CGPoint(x: x + r.height, y: r.minY))
            x += 5
        }
        return p
    }
}

/// Conserje: medallón con un aro dorado que se cierra y la cifra dentro (como calma.medalla).
struct MedallaConserje: View {
    let valor: Double
    let cifra: String
    let que: String
    @Environment(\.accessibilityReduceMotion) private var reducir
    @State private var visto = 0.0

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Tema.acento, lineWidth: 1.2)
                Circle().stroke(Conserje.oro.opacity(0.25), lineWidth: 6).padding(7)
                Circle().trim(from: 0, to: max(0.001, min(visto, 1))).stroke(Conserje.oro, lineWidth: 6)
                    .rotationEffect(.degrees(-90)).padding(7)
                Circle().stroke(Tema.acento, style: StrokeStyle(lineWidth: 0.8, dash: [1.5, 2.5])).padding(14)
                Text(cifra).font(.custom("Fraunces", size: 17, relativeTo: .headline)).foregroundStyle(Tema.texto)
                    .lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal, 18)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 100)
            Text(que.uppercased()).font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(Tema.suave).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .onAppear { if reducir { visto = valor } else { withAnimation(.spring(response: 1, dampingFraction: 0.8).delay(0.1)) { visto = valor } } }
        .onChange(of: valor) { _, nuevo in withAnimation(reducir ? nil : Tema.Muelle.toque) { visto = nuevo } }
    }
}

// MARK: portada de Solarpunk

/// La cabecera de Hoy sobre una foto de arquitectura con plantas (de día el bosque de niebla, de noche los
/// superárboles), con el velo oscuro abajo y el crédito que pide la licencia.
struct PortadaSolar: ViewModifier {
    @Environment(\.colorScheme) private var esquema

    @ViewBuilder func body(content: Content) -> some View {
        if Tema.solar {
            let foto = esquema == .dark ? "estanque" : "nube"
            content
                .padding(.top, 170)
                .padding(.bottom, 30)
                .environment(\.colorScheme, .dark)
                .background(alignment: .bottom) {
                    ZStack(alignment: .bottomTrailing) {
                        if let img = UIImage(named: "\(foto).webp") ?? UIImage(named: foto) {
                            Image(uiImage: img).resizable().scaledToFill()
                        } else {
                            LinearGradient(colors: [Color(hex: "#3D6B47"), Color(hex: "#1C3324")], startPoint: .top, endPoint: .bottom)
                        }
                        LinearGradient(colors: [.black.opacity(0.25), .clear, Color(hex: "#04120A").opacity(0.75)], startPoint: .top, endPoint: .bottom)
                        Text(foto == "nube" ? "Cloud Forest, Singapur · Basile Morin, CC BY-SA 4.0" : "Gardens by the Bay · Dietmar Rabich, CC BY-SA 4.0")
                            .font(.system(size: 9)).foregroundStyle(.white.opacity(0.75)).padding(.trailing, 20).padding(.bottom, 8)
                    }
                    .frame(height: 520)
                    .padding(.horizontal, -24)
                    .clipped()
                    .accessibilityHidden(true)
                }
        } else {
            content
        }
    }
}
