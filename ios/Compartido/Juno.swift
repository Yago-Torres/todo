import SwiftUI

// El aparato juno1980 (id "hardware" en el catálogo): la carcasa de la web (~/estilo/hardware.css) en SwiftUI.
// Lo comparten la app y el widget: el widget no tiene el catálogo, así que la app le deja el aparato en el app group.
// Calma no pasa por aquí: sin aparato guardado, todo se pinta como siempre.

/// El aparato elegido, guardado para el widget y la Live Activity.
enum AparatoGuardado {
    static let clave = "apariencia.aparato"

    static func guarda(_ aparato: String) { Almacen.defaults.set(aparato, forKey: clave) }

    static var actual: String { Almacen.defaults.string(forKey: clave) ?? "calma" }
    static var juno: Bool { actual == "hardware" }
}

/// Los materiales fijos del aparato (los --hw-* de la web): LCD, cristal ámbar, teclas y papel.
enum Juno {
    static let ambarFondo = Color(hex: "#140D06")
    static let ambar = Color(hex: "#FFB54A")
    static let ambarSuave = Color(hex: "#D29444")
    static let rojo = Color(hex: "#E2412F")
    static let aguja = Color(hex: "#FF3D2A")
    static let led = Color(hex: "#3FAE49")
    static let bisel = Color(hex: "#2B2723")
    static let papel = Color(hex: "#FBFAF5")
    static let papelTexto = Color(hex: "#24221D")

    /// La pantalla LCD verde (claro) o de fósforo (oscuro).
    static let lcd = Color(uiColor: .dinamico(claro: "#B8C2A3", oscuro: "#0F2420"))
    static let lcdTexto = Color(uiColor: .dinamico(claro: "#1B2213", oscuro: "#8FF0CF"))
    static let lcdSuave = Color(uiColor: .dinamico(claro: "#3C4632", oscuro: "#63BC9F"))
    /// Tecla clara (beige) y su sombra; en oscuro, gris de plástico.
    static let tecla = Color(uiColor: .dinamico(claro: "#F4EFE2", oscuro: "#5A5650"))
    static let tecla2 = Color(uiColor: .dinamico(claro: "#D9D1BD", oscuro: "#45423D"))
    static let teclaBorde = Color(uiColor: .dinamico(claro: "#9B927D", oscuro: "#1A1917"))
    static let teclaTexto = Color(uiColor: .dinamico(claro: "#2A261F", oscuro: "#F4EFE2"))
    static let relieve = Color(uiColor: .dinamico(claro: "rgba(255, 255, 255, .55)", oscuro: "rgba(255, 255, 255, .06)"))
    static let hundido = Color(uiColor: .dinamico(claro: "rgba(0, 0, 0, .10)", oscuro: "rgba(0, 0, 0, .45)"))

    /// La letra de las pantallas: Share Tech Mono (LCD) y VT323 (ámbar) si están registradas; si no, la mono del sistema.
    static func lcdFuente(_ tam: CGFloat, registrada: Bool) -> Font {
        registrada ? .custom("Share Tech Mono", size: tam) : .system(size: tam, weight: .medium, design: .monospaced)
    }

    static func ambarFuente(_ tam: CGFloat, registrada: Bool) -> Font {
        registrada ? .custom("VT323", size: tam * 1.25) : .system(size: tam, weight: .regular, design: .monospaced)
    }
}

/// Un tornillo de cabeza ranurada (el de la esquina de cada panel).
struct Tornillo: View {
    var lado: CGFloat = 8

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [.white, Color(hex: "#B4AD9C"), Color(hex: "#5C5649")],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: lado * 0.8))
            Circle().strokeBorder(Color(hex: "#332E26").opacity(0.55), lineWidth: 0.6)
            Capsule().fill(Color(hex: "#332E26")).frame(width: lado * 0.62, height: max(0.9, lado * 0.11))
                .rotationEffect(.degrees(45))
        }
        .frame(width: lado, height: lado)
        .accessibilityHidden(true)
    }
}

/// El panel de la carcasa: plástico con relieve arriba, sombra abajo y dos tornillos.
struct PanelJuno: View {
    let color: Color
    var radio: CGFloat = 6
    var tornillos = true

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: radio, style: .continuous)
        forma.fill(color)
            .overlay(forma.fill(LinearGradient(colors: [Color.white.opacity(0.10), .clear, Color.black.opacity(0.06)],
                                               startPoint: .top, endPoint: .bottom)))
            .overlay(forma.strokeBorder(LinearGradient(colors: [Juno.relieve, Juno.hundido],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .overlay(alignment: .top) {
                if tornillos {
                    HStack { Tornillo(); Spacer(); Tornillo() }.padding(.horizontal, 7).padding(.top, 7)
                }
            }
            .shadow(color: .black.opacity(0.22), radius: 0, x: 0, y: 1.5)
            .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 4)
    }
}

/// El cristal ámbar de los vúmetros y las cifras de dinero.
struct CristalAmbar: View {
    var radio: CGFloat = 6

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: radio, style: .continuous)
        forma.fill(Juno.ambarFondo)
            .overlay(forma.fill(LinearGradient(colors: [Color.white.opacity(0.07), .clear],
                                               startPoint: .top, endPoint: .center)))
            .overlay(forma.strokeBorder(Juno.bisel, lineWidth: 2))
    }
}

/// La aguja: animable (el ángulo, en grados desde la vertical).
private struct Aguja: Shape {
    var angulo: Double
    var animatableData: Double {
        get { angulo }
        set { angulo = newValue }
    }

    func path(in r: CGRect) -> Path {
        let centro = CGPoint(x: r.midX, y: r.maxY - r.height * 0.05)
        let largo = r.height * 0.78
        let a = CGFloat(angulo - 90) * .pi / 180
        var p = Path()
        p.move(to: centro)
        p.addLine(to: CGPoint(x: centro.x + cos(a) * largo, y: centro.y + sin(a) * largo))
        return p
    }
}

/// Vúmetro de aguja, como calma.vu() en la web: `valor` 0…1 es el objetivo (de -50° a +30°) y lo que pase, la zona
/// roja (hasta 1,25). Con «reducir movimiento» la aguja va directa.
struct Vumetro: View {
    let valor: Double
    var etiqueta: String = "VU"
    var registrada = false
    var animar = true
    @Environment(\.accessibilityReduceMotion) private var reducir
    @State private var visto = 0.0

    private static func angulo(_ v: Double) -> Double { -50 + max(0, min(1.25, v.isFinite ? v : 0)) * 80 }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                Canvas { ctx, size in
                    let cx = size.width / 2, cy = size.height * 0.95
                    let r = min(size.height * 0.72, size.width * 0.46)
                    func punto(_ grados: Double, _ radio: CGFloat) -> CGPoint {
                        let a = CGFloat(grados) * .pi / 180
                        return CGPoint(x: cx + radio * sin(a), y: cy - radio * cos(a))
                    }
                    var arco = Path()
                    arco.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: .degrees(-140),
                                endAngle: .degrees(-60), clockwise: false)
                    ctx.stroke(arco, with: .color(Juno.ambar.opacity(0.5)), lineWidth: 1)
                    var rojo = Path()
                    rojo.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: .degrees(-60),
                                endAngle: .degrees(-40), clockwise: false)
                    ctx.stroke(rojo, with: .color(Juno.rojo), lineWidth: 3)
                    for i in 0...10 {
                        let gr = -50 + Double(i) * 10
                        var m = Path()
                        m.move(to: punto(gr, r))
                        m.addLine(to: punto(gr, r * (i % 5 == 0 ? 0.84 : 0.9)))
                        ctx.stroke(m, with: .color(gr > 30 ? Juno.rojo : Juno.ambar), lineWidth: i % 5 == 0 ? 2 : 1)
                    }
                }
                Text(etiqueta)
                    .font(Juno.ambarFuente(max(9, h * 0.16), registrada: registrada))
                    .foregroundStyle(Juno.ambar.opacity(0.7))
                    .position(x: w / 2, y: h * 0.52)
                Aguja(angulo: Self.angulo(animar ? visto : valor))
                    .stroke(Juno.aguja, style: StrokeStyle(lineWidth: max(1.2, h * 0.025), lineCap: .round))
                Circle().fill(Color(hex: "#222222"))
                    .overlay(Circle().strokeBorder(Juno.ambar.opacity(0.4), lineWidth: 0.6))
                    .frame(width: max(6, h * 0.12), height: max(6, h * 0.12))
                    .position(x: w / 2, y: h * 0.95)
            }
        }
        .aspectRatio(160 / 86, contentMode: .fit)
        .padding(6)
        .background(CristalAmbar())
        .onAppear {
            guard animar else { return }
            if reducir { visto = valor } else {
                withAnimation(.spring(response: 0.9, dampingFraction: 0.55).delay(0.1)) { visto = valor }
            }
        }
        .onChange(of: valor) { _, nuevo in
            if reducir { visto = nuevo } else { withAnimation(.spring(response: 0.7, dampingFraction: 0.6)) { visto = nuevo } }
        }
        .accessibilityHidden(true)
    }
}

/// Una cifra en la pantalla LCD (o en ámbar): el valor grande y qué es en pequeño.
struct CifraLCD: View {
    let valor: String
    let que: String
    var ambar = false
    var registrada = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(valor)
                .font(ambar ? Juno.ambarFuente(17, registrada: registrada) : Juno.lcdFuente(17, registrada: registrada))
                .foregroundStyle(ambar ? Juno.ambar : Juno.lcdTexto)
                .lineLimit(1).minimumScaleFactor(0.6)
                .monospacedDigit()
            Text(que.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(ambar ? Juno.ambarSuave : Juno.lcdSuave)
                .lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if ambar { CristalAmbar(radio: 4) } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Juno.lcd)
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Juno.bisel, lineWidth: 2))
            }
        }
        .accessibilityElement(children: .combine)
    }
}
