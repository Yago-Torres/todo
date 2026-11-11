import SwiftUI
import Foundation

/// El orbe del modo voz: un shader de Metal (Hoy/Orbe.metal) dentro de un TimelineView. Respira lento mientras
/// espera, se agita con el nivel real del micrófono al escuchar y late con la voz cuando habla Tom.
/// Con Reducir movimiento queda quieto: solo cambia de color y de tamaño según el estado.
struct Orbe: View {
    let charla: Conversacion
    let sinMovimiento: Bool

    @Environment(\.colorScheme) private var esquema
    @State private var motor = MotorOrbe()

    private let lado: CGFloat = 220

    var body: some View {
        let fase = charla.fase
        Group {
            if sinMovimiento {
                let quieto = MotorOrbe.metas(fase)
                lienzo(MotorOrbe.Estado(t: 0, amp: 0, azul: quieto.azul, ambar: quieto.ambar))
                    .scaleEffect(MotorOrbe.escala(fase))
                    .animation(.easeInOut(duration: 0.3), value: fase)
            } else {
                TimelineView(.animation) { contexto in
                    lienzo(motor.paso(contexto.date, fase: fase, nivel: charla.nivel, pulso: charla.ultimoPulso))
                }
            }
        }
        .frame(width: lado, height: lado)
        .overlay {
            if case .parada = fase {
                Image(systemName: "mic.slash")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Color("Fondo"))
            }
        }
        .accessibilityHidden(true)
    }

    private func lienzo(_ e: MotorOrbe.Estado) -> some View {
        Rectangle()
            .fill(Color.white)
            .colorEffect(ShaderLibrary.orbeTom(
                .float2(Float(lado), Float(lado)),
                .float(Float(e.t)),
                .float(Float(e.amp)),
                .float(Float(e.azul)),
                .float(Float(e.ambar)),
                .color(acento),
                .color(Self.azul),
                .color(Self.ambar)
            ))
    }

    /// Acento Calma: oliva en claro, lima en oscuro.
    private var acento: Color { esquema == .dark ? Color(hex: "#CDE77F") : Color(hex: "#5E7A1E") }
    private static let azul = Color(hex: "#2a78d6")
    private static let ambar = Color(hex: "#E7B04A")
}

/// Integra el tiempo y suaviza la amplitud y los colores fotograma a fotograma. No es observable: lo lee el
/// TimelineView en cada fotograma y no debe invalidar nada al cambiar.
final class MotorOrbe {
    struct Estado {
        var t: Double
        var amp: Double
        var azul: Double
        var ambar: Double
    }

    private var t: Double = 0
    private var amp: Double = 0.25
    private var azul: Double = 0.25
    private var ambar: Double = 0
    private var antes: Date?

    /// Hacia qué colores tira la veta en cada estado.
    static func metas(_ fase: Conversacion.Fase) -> (azul: Double, ambar: Double) {
        switch fase {
        case .escuchando: return (1, 0)
        case .hablando: return (0, 1)
        case .pensando: return (0.5, 0.3)
        case .preparando, .parada: return (0.25, 0)
        }
    }

    /// Solo para Reducir movimiento: el estado se nota en el tamaño.
    static func escala(_ fase: Conversacion.Fase) -> CGFloat {
        switch fase {
        case .escuchando: return 1.06
        case .hablando: return 1.0
        case .pensando: return 0.97
        case .preparando, .parada: return 0.92
        }
    }

    /// nivel: 0…1 del micrófono. pulso: instante (timeIntervalSinceReferenceDate) de la última palabra de Tom.
    func paso(_ ahora: Date, fase: Conversacion.Fase, nivel: Double, pulso: TimeInterval) -> Estado {
        let dt = min(max(ahora.timeIntervalSince(antes ?? ahora), 0), 0.1)
        antes = ahora

        let vel: Double
        let meta: Double
        switch fase {
        case .escuchando:
            vel = 1.4 + 0.8 * nivel
            meta = 0.3 + 0.75 * nivel
        case .hablando:
            // envolvente suave mientras habla + un golpe que decae en cada palabra
            let golpe = exp(-max(ahora.timeIntervalSinceReferenceDate - pulso, 0) * 7)
            let envolvente = abs(sin(t * 4.2)) * (0.6 + 0.4 * sin(t * 1.3))
            vel = 1.3
            meta = 0.35 + 0.3 * envolvente + 0.4 * golpe
        case .pensando:
            vel = 1.2
            meta = 0.3
        case .preparando, .parada:
            vel = 1
            meta = 0.25
        }
        let colores = Self.metas(fase)

        t += dt * vel
        amp += (meta - amp) * min(1, dt * 6)
        azul += (colores.azul - azul) * min(1, dt * 4)
        ambar += (colores.ambar - ambar) * min(1, dt * 4)
        return Estado(t: t, amp: amp, azul: azul, ambar: ambar)
    }
}
