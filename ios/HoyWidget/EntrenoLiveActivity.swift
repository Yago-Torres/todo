import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// El entreno en la isla dinámica y en la pantalla de bloqueo: ejercicio, serie y, en el descanso, la cuenta atrás.
/// Text(timerInterval:) y ProgressView(timerInterval:) los anima el sistema solos, sin actualizaciones: son lo único
/// que se mueve en una Live Activity. Estilo Calma oscuro (la isla siempre es negra).
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
                    if enDescanso {
                        Text("Descanso")
                            .font(.caption)
                            .foregroundStyle(Tono.suave)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    EntrenoVista.abierta(e, enDescanso: enDescanso)
                }
            } compactLeading: {
                if enDescanso, let fin = e.finDescanso {
                    EntrenoVista.anillo(e, fin: fin)
                } else {
                    Image(systemName: "dumbbell.fill")
                        .foregroundStyle(Tono.acento)
                }
            } compactTrailing: {
                if enDescanso, let fin = e.finDescanso {
                    EntrenoVista.cuenta(fin)
                        .font(.body.weight(.semibold).monospacedDigit())
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
                    EntrenoVista.anillo(e, fin: fin)
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
    static var fondo: Color { ColoresGuardados.oscuro("fondo", "#111111") }
    static var acento: Color { ColoresGuardados.oscuro("acento", "#9FD3B4") }   // el acento elegido, en oscuro
    static var acentoTexto: Color { ColoresGuardados.oscuro("acento_texto", "#14301F") }   // texto sobre el acento
    static var texto: Color { ColoresGuardados.oscuro("texto", "#EDEDED") }
    static var suave: Color { ColoresGuardados.oscuro("suave", "#9A9A9A") }
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
                EntrenoVista.cabecera(e, talla: .title2)
                Spacer(minLength: 0)
                if enDescanso, let fin = e.finDescanso {
                    EntrenoVista.cuenta(fin)
                        .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(Tono.acento)
                        .frame(maxWidth: 120, alignment: .trailing)
                }
            }

            if enDescanso, let fin = e.finDescanso {
                EntrenoVista.barra(e, fin: fin)
            }

            if !e.hecho {
                HStack {
                    Spacer(minLength: 0)
                    EntrenoVista.boton(e)
                }
            }
        }
        .padding(16)
        .animation(.spring(duration: 0.45), value: e.serie)
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

    /// Lo que dura el descanso entero, para que el anillo y la barra empiecen llenos. Si el estado no trae los
    /// segundos (o el fin queda más lejos), cuenta desde ahora. Siempre inicio < fin.
    static func intervalo(_ e: EntrenoActividad.ContentState, fin: Date) -> ClosedRange<Date> {
        let dura = TimeInterval(e.descanso > 0 ? e.descanso : 90)
        var inicio = min(fin.addingTimeInterval(-dura), Date())
        if inicio >= fin { inicio = fin.addingTimeInterval(-1) }
        return inicio...fin
    }

    /// Mini anillo que se vacía con el descanso (lo anima el sistema).
    static func anillo(_ e: EntrenoActividad.ContentState, fin: Date) -> some View {
        ProgressView(timerInterval: intervalo(e, fin: fin), countsDown: true) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.circular)
        .labelsHidden()
        .tint(Tono.acento)
    }

    /// La misma cuenta en barra, para la pantalla de bloqueo.
    static func barra(_ e: EntrenoActividad.ContentState, fin: Date) -> some View {
        ProgressView(timerInterval: intervalo(e, fin: fin), countsDown: true) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.linear)
        .labelsHidden()
        .tint(Tono.acento)
    }

    static func serie(_ e: EntrenoActividad.ContentState) -> some View {
        Text("\(e.serie)/\(e.total)")
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(e.serie)))
    }

    /// «Press banca · 70 kg · 8-10 rep» y, debajo y grande, «Serie 3 de 4» (o «Hecho»).
    static func cabecera(_ e: EntrenoActividad.ContentState, talla: Font) -> some View {
        let ejercicio = e.detalle.isEmpty || e.hecho ? e.ejercicio : "\(e.ejercicio) · \(e.detalle)"
        let serie = e.hecho ? "Hecho" : "Serie \(e.serie) de \(e.total)"
        return VStack(alignment: .leading, spacing: 1) {
            Text(ejercicio)
                .font(.footnote)
                .foregroundStyle(Tono.suave)
                .lineLimit(1)
            Text(serie)
                .font(talla.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Tono.texto)
                .lineLimit(1)
                .contentTransition(.numericText(value: Double(e.serie)))
        }
    }

    /// La isla abierta: cabecera arriba; abajo el reloj grande en acento y «Serie hecha».
    static func abierta(_ e: EntrenoActividad.ContentState, enDescanso: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            cabecera(e, talla: .title3)
            HStack(alignment: .bottom, spacing: 8) {
                if enDescanso, let fin = e.finDescanso {
                    cuenta(fin)
                        .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Tono.acento)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: 150, alignment: .leading)
                }
                Spacer(minLength: 0)
                boton(e)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(duration: 0.45), value: e.serie)
    }

    @ViewBuilder static func boton(_ e: EntrenoActividad.ContentState) -> some View {
        if !e.hecho {
            Button(intent: SerieHechaIntent()) {
                Label("Serie hecha", systemImage: "checkmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Tono.acentoTexto)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Tono.acento, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}
