import SwiftUI

/// El fondo de caracteres de calma.js (el plasma), en nativo: una rejilla de símbolos cuya densidad sigue un campo
/// de ondas que se mueve despacio. Canvas + TimelineView a ~15 fps; quieto con «reducir movimiento». La intensidad es
/// la de la apariencia elegida (Tema.actual.fondo: 0 apagado, 0,5 sutil, 1 normal, 1,6 más presente).
struct FondoCalma: View {
    @Environment(\.accessibilityReduceMotion) private var quieto

    private static let rampa: [Character] = [" ", " ", "·", ".", ":", "-", "=", "+", "*"]
    private static let celda = CGSize(width: 11, height: 18)

    var body: some View {
        let intensidad = Tema.actual.fondo
        if intensidad > 0 {
            TimelineView(.animation(minimumInterval: 1.0 / 15, paused: quieto)) { contexto in
                Canvas(rendersAsynchronously: true) { ctx, tam in
                    let t = quieto ? 0 : contexto.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000)
                    pinta(ctx, tam, t, intensidad)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func pinta(_ ctx: GraphicsContext, _ tam: CGSize, _ t: Double, _ intensidad: Double) {
        // un glifo resuelto por nivel: resolverlo una vez por fotograma, no por celda
        let glifos: [GraphicsContext.ResolvedText] = Self.rampa.enumerated().map { i, c in
            let vivo = i >= Self.rampa.count - 2
            return ctx.resolve(Text(String(c))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(vivo ? Tema.acento.opacity(min(1, 0.45 * intensidad)) : Tema.ascii.opacity(min(1, intensidad))))
        }
        let cols = Int(tam.width / Self.celda.width) + 1
        let filas = Int(tam.height / Self.celda.height) + 1
        let lento = t * 0.35
        for f in 0..<filas {
            let y = Double(f) * 0.16
            for c in 0..<cols {
                let x = Double(c) * 0.12
                var v = sin(x + lento) + sin(y * 1.3 - lento * 0.8)
                v += sin((x + y) * 0.7 + lento * 0.6) + sin(sqrt(x * x + y * y) * 0.9 - lento)
                let n = (v + 4) / 8   // 0…1
                let i = min(Self.rampa.count - 1, max(0, Int(n * n * Double(Self.rampa.count))))
                guard i > (intensidad > 1 ? 0 : 1) else { continue }
                ctx.draw(glifos[i], at: CGPoint(x: CGFloat(c) * Self.celda.width, y: CGFloat(f) * Self.celda.height), anchor: .topLeading)
            }
        }
    }
}
