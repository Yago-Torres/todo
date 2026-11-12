import ActivityKit
import SwiftUI
import WidgetKit

/// La isla para el descanso suelto, el pase del freno, la subida de escalada y «Día en la isla».
/// Compacta: icono + mm:ss (o % o anillo); expandida: título, detalle y la barra o la cuenta atrás.
struct AvisoLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AvisoActividad.self) { contexto in
            AvisoVista.bloqueo(contexto.state, caducada: contexto.isStale)
                .padding(16)
                .activityBackgroundTint(Tono2.fondo)
                .activitySystemActionForegroundColor(Tono2.acento)
        } dynamicIsland: { contexto in
            let e = contexto.state
            let caducada = contexto.isStale
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(e.titulo).lineLimit(1)
                    } icon: {
                        Image(systemName: e.icono).foregroundStyle(Tono2.acento)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Tono2.texto)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    AvisoVista.derecha(e, caducada: caducada)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Tono2.acento)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        if !e.detalle.isEmpty {
                            Text(e.detalle).font(.callout).foregroundStyle(Tono2.suave).lineLimit(2)
                        }
                        AvisoVista.barra(e, caducada: caducada)
                    }
                }
            } compactLeading: {
                if !e.anillos.isEmpty {
                    AvisoVista.anillos(e.anillos).frame(width: 20, height: 20)
                } else {
                    Image(systemName: e.icono).foregroundStyle(Tono2.acento)
                }
            } compactTrailing: {
                AvisoVista.derecha(e, caducada: caducada)
                    .font(.body.weight(.semibold).monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 48)
                    .foregroundStyle(Tono2.acento)
            } minimal: {
                if !e.anillos.isEmpty {
                    AvisoVista.anillos(e.anillos)
                } else {
                    Image(systemName: e.icono).foregroundStyle(Tono2.acento)
                }
            }
            .keylineTint(Tono2.acento)
        }
    }
}

/// Los colores elegidos en Tom, en oscuro (la isla siempre es negra).
private enum Tono2 {
    static var fondo: Color { ColoresGuardados.oscuro("fondo", "#111111") }
    static var acento: Color { ColoresGuardados.oscuro("acento", "#9FD3B4") }
    static var texto: Color { ColoresGuardados.oscuro("texto", "#EDEDED") }
    static var suave: Color { ColoresGuardados.oscuro("suave", "#9A9A9A") }
    static var campo: Color { ColoresGuardados.oscuro("carta2", "#252525") }
}

enum AvisoVista {
    /// Lo de la derecha: la cuenta atrás, el porcentaje, un check o los hábitos.
    @ViewBuilder static func derecha(_ e: AvisoActividad.ContentState, caducada: Bool) -> some View {
        if e.listo || caducada {
            Image(systemName: "checkmark")
        } else if let inicio = e.inicio, let fin = e.fin, fin > inicio {
            Text(timerInterval: inicio...fin, countsDown: true)
        } else if let p = e.progreso {
            Text("\(Int((p * 100).rounded()))%")
        } else if let h = e.anillos.first {
            Text("\(Int((h * 100).rounded()))%")
        } else {
            EmptyView()
        }
    }

    @ViewBuilder static func barra(_ e: AvisoActividad.ContentState, caducada: Bool) -> some View {
        if let inicio = e.inicio, let fin = e.fin, fin > inicio, !caducada, !e.listo {
            ProgressView(timerInterval: inicio...fin, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                .tint(Tono2.acento)
        } else if let p = e.progreso, !e.listo {
            ProgressView(value: min(max(p, 0), 1)).tint(Tono2.acento)
        } else if !e.anillos.isEmpty {
            HStack(spacing: 14) {
                ForEach(Array(e.anillos.prefix(3).enumerated()), id: \.offset) { i, v in
                    HStack(spacing: 6) {
                        anillo(v, color(i)).frame(width: 22, height: 22)
                        Text(["Hábitos", "Pasos", "Sueño"][i]).font(.caption).foregroundStyle(Tono2.suave)
                    }
                }
            }
        }
    }

    static func bloqueo(_ e: AvisoActividad.ContentState, caducada: Bool) -> some View {
        HStack(spacing: 14) {
            if e.anillos.isEmpty {
                Image(systemName: e.icono)
                    .font(.title2)
                    .foregroundStyle(Tono2.acento)
                    .frame(width: 36)
            } else {
                anillos(e.anillos).frame(width: 40, height: 40)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(e.titulo).font(.headline).foregroundStyle(Tono2.texto).lineLimit(1)
                if !e.detalle.isEmpty {
                    Text(e.detalle).font(.subheadline).foregroundStyle(Tono2.suave).lineLimit(2)
                }
                barra(e, caducada: caducada)
            }
            Spacer(minLength: 0)
            derecha(e, caducada: caducada)
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(Tono2.acento)
                .frame(maxWidth: 90, alignment: .trailing)
        }
    }

    static func anillos(_ valores: [Double]) -> some View {
        ZStack {
            ForEach(Array(valores.prefix(3).enumerated()), id: \.offset) { i, v in
                anillo(v, color(i)).padding(CGFloat(i) * 4.5)
            }
        }
    }

    static func anillo(_ v: Double, _ c: Color) -> some View {
        ZStack {
            Circle().stroke(c.opacity(0.25), lineWidth: 3)
            Circle().trim(from: 0, to: max(0.001, min(v, 1)))
                .stroke(c, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }

    private static func color(_ i: Int) -> Color {
        [Tono2.acento, Color(hex: "#E8B04A"), Color(hex: "#5E81AC")][min(i, 2)]
    }
}
