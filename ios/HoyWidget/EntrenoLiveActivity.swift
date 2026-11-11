import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// El entreno en la isla dinámica y en la pantalla de bloqueo: ejercicio, serie y, en el descanso, la cuenta atrás
/// (Text(timerInterval:) la pinta el sistema, sin actualizaciones). Estilo Calma oscuro.
struct EntrenoLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EntrenoActividad.self) { contexto in
            EntrenoBloqueo(contexto: contexto)
                .activityBackgroundTint(Tono.fondo)
                .activitySystemActionForegroundColor(Tono.acento)
        } dynamicIsland: { contexto in
            let e = contexto.state
            let enDescanso = EntrenoVista.enDescanso(contexto)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(contexto.attributes.nombre).lineLimit(1)
                    } icon: {
                        Image(systemName: "dumbbell.fill").foregroundStyle(Tono.acento)
                    }
                    .font(.caption)
                    .foregroundStyle(Tono.suave)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if enDescanso, let fin = e.finDescanso {
                        EntrenoVista.cuenta(fin)
                            .font(.title2.weight(.semibold).monospacedDigit())
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(Tono.acento)
                    } else if !e.hecho {
                        EntrenoVista.serie(e)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Tono.texto)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.ejercicio)
                                .font(.headline)
                                .foregroundStyle(Tono.texto)
                                .lineLimit(1)
                            EntrenoVista.linea(e, conSerie: enDescanso)
                                .font(.subheadline)
                                .foregroundStyle(Tono.suave)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        EntrenoVista.boton(e)
                    }
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(Tono.acento)
            } compactTrailing: {
                if enDescanso, let fin = e.finDescanso {
                    EntrenoVista.cuenta(fin)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 44)
                        .foregroundStyle(Tono.acento)
                } else if e.hecho {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Tono.acento)
                } else {
                    EntrenoVista.serie(e)
                        .foregroundStyle(Tono.texto)
                }
            } minimal: {
                if enDescanso, let fin = e.finDescanso {
                    EntrenoVista.cuenta(fin)
                        .font(.caption2.monospacedDigit())
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(Tono.acento)
                } else {
                    Image(systemName: "dumbbell.fill")
                        .foregroundStyle(Tono.acento)
                }
            }
            .keylineTint(Tono.acento)
        }
    }
}

private enum Tono {
    static let fondo = Color(hex: "#171A16")
    static let acento = Color(hex: "#2E8B57")
    static let texto = Color(hex: "#EEF0E8")
    static let suave = Color(hex: "#A3A892")
}

private struct EntrenoBloqueo: View {
    let contexto: ActivityViewContext<EntrenoActividad>

    var body: some View {
        let e = contexto.state
        let enDescanso = EntrenoVista.enDescanso(contexto)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "dumbbell.fill").foregroundStyle(Tono.acento)
                Text(contexto.attributes.nombre).lineLimit(1)
                Spacer(minLength: 0)
                if enDescanso {
                    Text("Descanso")
                } else if e.finDescanso != nil && !e.hecho {
                    Text("A por ella")
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Tono.suave)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.ejercicio)
                        .font(.headline)
                        .foregroundStyle(Tono.texto)
                        .lineLimit(1)
                    EntrenoVista.linea(e, conSerie: true)
                        .font(.subheadline)
                        .foregroundStyle(Tono.suave)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if enDescanso, let fin = e.finDescanso {
                    EntrenoVista.cuenta(fin)
                        .font(.system(size: 36, weight: .semibold, design: .rounded).monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(Tono.acento)
                        .frame(maxWidth: 110, alignment: .trailing)
                }
            }

            if !e.hecho {
                HStack {
                    Spacer(minLength: 0)
                    EntrenoVista.boton(e)
                }
            }
        }
        .padding(16)
    }
}

private enum EntrenoVista {
    /// Descanso en marcha según el sistema: pasada la staleDate (el fin), deja de contar aunque no llegue otra actualización.
    static func enDescanso(_ c: ActivityViewContext<EntrenoActividad>) -> Bool {
        guard let fin = c.state.finDescanso else { return false }
        return !c.isStale && fin > Date()
    }

    /// El rango nunca al revés: Date()...fin con fin ya pasado rompería la vista.
    static func cuenta(_ fin: Date) -> Text {
        Text(timerInterval: min(Date(), fin)...fin, countsDown: true)
            .monospacedDigit()
    }

    static func serie(_ e: EntrenoActividad.ContentState) -> some View {
        Text("\(e.serie)/\(e.total)")
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(e.serie)))
    }

    /// «Serie 3/4 · 70 kg · 8-10 rep», o «Hecho» si no queda serie conocida.
    static func linea(_ e: EntrenoActividad.ContentState, conSerie: Bool) -> some View {
        var partes: [String] = []
        if e.hecho {
            partes.append("Hecho")
        } else if conSerie {
            partes.append("Serie \(e.serie)/\(e.total)")
        }
        if !e.hecho && !e.detalle.isEmpty { partes.append(e.detalle) }
        return Text(partes.joined(separator: " · "))
            .contentTransition(.numericText(value: Double(e.serie)))
    }

    @ViewBuilder static func boton(_ e: EntrenoActividad.ContentState) -> some View {
        if !e.hecho {
            Button(intent: SerieHechaIntent()) {
                Label("Serie hecha", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(Tono.acento)
        }
    }
}
