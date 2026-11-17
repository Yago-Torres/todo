import SwiftUI
import WidgetKit
import AppIntents

// «Apuntar»: dos botones, Nota y Pendiente, que abren Tom con la caja de apuntar (Hoy/Nativo/Notas/HojaApuntar.swift).
// Un widget no puede pedir texto: el botón corre AbreApuntarIntent (abre la app y deja la marca en el app group) y,
// fuera de los botones, el toque va a hoy://apuntar?tipo=nota. No lee datos: su línea de tiempo es una sola entrada.

func apuntarURL(_ tipo: TipoCaptura) -> URL {
    URL(string: "hoy://apuntar?tipo=\(tipo.rawValue)") ?? URL(string: "hoy://apuntar")!
}

struct EntradaApuntar: TimelineEntry {
    let date: Date
}

struct ProveedorApuntar: TimelineProvider {
    func placeholder(in context: Context) -> EntradaApuntar { EntradaApuntar(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (EntradaApuntar) -> Void) {
        completion(EntradaApuntar(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EntradaApuntar>) -> Void) {
        completion(Timeline(entries: [EntradaApuntar(date: Date())], policy: .never))
    }
}

struct ApuntarVista: View {
    @Environment(\.widgetFamily) private var familia
    @Environment(\.widgetRenderingMode) private var modo

    var body: some View {
        contenido
            .widgetURL(apuntarURL(.nota))
            .containerBackground(for: .widget) {
                if esAccesorio(familia) { AccessoryWidgetBackground() } else { FondoWidget() }
            }
    }

    @ViewBuilder private var contenido: some View {
        let t = Tinta(modo)
        switch familia {
        case .accessoryCircular:
            Image(systemName: "square.and.pencil")
                .font(.system(size: 22, weight: .semibold))
                .widgetAccentable()
                .accessibilityLabel("Apuntar una nota")
        case .accessoryRectangular:
            HStack(spacing: 6) {
                botonAccesorio(.nota, "Nota", "lightbulb")
                botonAccesorio(.tarea, "Pendiente", "checklist")
            }
        case .systemMedium:
            HStack(spacing: 10) {
                boton(.nota, "Nota rápida", "lightbulb.fill", detalle: "Una idea suelta", t: t)
                boton(.tarea, "Pendiente", "checklist", detalle: "A Pendientes", t: t)
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                Text("Apuntar").font(.system(size: 13, weight: .bold)).foregroundStyle(t.suave)
                boton(.nota, "Nota", "lightbulb.fill", detalle: nil, t: t)
                boton(.tarea, "Pendiente", "checklist", detalle: nil, t: t)
            }
        }
    }

    private func boton(_ tipo: TipoCaptura, _ titulo: String, _ simbolo: String, detalle: String?, t: Tinta) -> some View {
        Button(intent: AbreApuntarIntent(tipo: tipo)) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: simbolo)
                    .font(.system(size: detalle == nil ? 15 : 20, weight: .semibold))
                    .foregroundStyle(t.habitos)
                Text(titulo)
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(t.texto)
                    .lineLimit(1).minimumScaleFactor(0.8)
                if let detalle {
                    Text(detalle).font(.system(size: 12)).foregroundStyle(t.suave).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(10)
            .background(t.campo, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tipo == .nota ? "Apuntar una nota rápida" : "Apuntar un pendiente")
    }

    private func botonAccesorio(_ tipo: TipoCaptura, _ titulo: String, _ simbolo: String) -> some View {
        Button(intent: AbreApuntarIntent(tipo: tipo)) {
            VStack(spacing: 2) {
                Image(systemName: simbolo).font(.system(size: 15, weight: .semibold)).widgetAccentable()
                Text(titulo).font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tipo == .nota ? "Apuntar una nota rápida" : "Apuntar un pendiente")
    }
}

struct ApuntarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HoyApuntar", provider: ProveedorApuntar()) { _ in
            ApuntarVista()
        }
        .configurationDisplayName("Apuntar")
        .description("Una nota rápida o un pendiente: abre Tom con la caja de apuntar y el teclado ya fuera.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}
