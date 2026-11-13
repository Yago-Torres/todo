import SwiftUI
import WidgetKit

// «Tom según la hora»: el widget de la pantalla de bloqueo que cambia con el momento del día, con la misma lógica y las
// mismas horas que el fondo generado (Compartido/MomentoFondo.swift). Para quien no quiera cambiar el fondo.

struct EntradaMomento: TimelineEntry {
    let date: Date
    let contenido: ContenidoMomento?
}

struct ProveedorMomento: TimelineProvider {
    func placeholder(in context: Context) -> EntradaMomento {
        EntradaMomento(date: Date(), contenido: Self.contenido(Hoy.muestra, nil, Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (EntradaMomento) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task {
            let hoy = Self.hoy(await Proveedor.carga())
            completion(EntradaMomento(date: Date(), contenido: Self.contenido(hoy, InstantaneaFondo.lee(), Date())))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EntradaMomento>) -> Void) {
        Task {
            let ahora = Date()
            let estado = await Proveedor.carga()
            if case .sinClaves = estado {
                completion(Timeline(entries: [EntradaMomento(date: ahora, contenido: nil)], policy: .after(ahora.addingTimeInterval(3600))))
                return
            }
            let hoy = Self.hoy(estado)
            let inst = InstantaneaFondo.lee()
            // una entrada ahora y otra en cada cambio de momento (despertar, entreno, fin del entreno, noche, medianoche)
            let fechas = [ahora] + AjustesFondo.lee().cambios(desde: ahora, horas: 24)
            let entradas = fechas.map { EntradaMomento(date: $0, contenido: Self.contenido(hoy, inst, $0)) }
            completion(Timeline(entries: entradas, policy: .after(ahora.addingTimeInterval(30 * 60))))
        }
    }

    private static func hoy(_ estado: EstadoWidget) -> Hoy? {
        if case .datos(let h) = estado { return h }
        return Almacen.leeHoy()
    }

    static func contenido(_ hoy: Hoy?, _ inst: InstantaneaFondo?, _ fecha: Date) -> ContenidoMomento {
        ContenidoMomento.construye(AjustesFondo.lee(), hoy: hoy, inst: inst, ahora: fecha)
    }
}

struct MomentoVista: View {
    @Environment(\.widgetFamily) private var familia
    let entrada: EntradaMomento

    var body: some View {
        if let c = entrada.contenido {
            contenido(c).marcoWidget(ruta(c.momento))
        } else {
            AvisoWidget(titulo: "Abre Tom", detalle: "para configurarlo").marcoWidget("/")
        }
    }

    private func ruta(_ m: MomentoFondo) -> String {
        switch m {
        case .manana: return "/"
        case .entreno: return "/entreno.html"
        case .noche: return "/habitos.html"
        }
    }

    @ViewBuilder private func contenido(_ c: ContenidoMomento) -> some View {
        if !c.hayDatos {
            AvisoWidget(titulo: "Sin datos de hoy", detalle: "Abre Tom con conexión")
        } else {
            switch familia {
            case .accessoryInline: Text(linea(c))
            case .accessoryCircular: circular(c)
            default: rectangular(c)
            }
        }
    }

    // MARK: textos

    private func entrenoDeHoy(_ c: ContenidoMomento) -> EntrenoFondo? {
        c.entrenoPendiente.first { $0.tipo != "movilidad" } ?? c.entrenoPendiente.first
    }

    private func linea(_ c: ContenidoMomento) -> String {
        switch c.momento {
        case .manana:
            let e = entrenoDeHoy(c).map { "Hoy: \($0.nombre)" } ?? "Hoy"
            return c.faltan.isEmpty ? "\(e) · todo hecho" : "\(e) · \(c.faltan.count) hábitos"
        case .entreno:
            return entrenoDeHoy(c).map { "Toca \($0.nombre)" } ?? "Hora de entrenar"
        case .noche:
            if c.faltan.isEmpty { return "Día completo" }
            return c.rachaEnJuego > 0 ? "Faltan \(c.faltan.count) · racha \(c.rachaEnJuego) d" : "Faltan \(c.faltan.count)"
        }
    }

    private func rectangular(_ c: ContenidoMomento) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: c.momento.simbolo).widgetAccentable()
                Text(cabecera(c)).lineLimit(1)
            }
            .font(.system(size: 14, weight: .bold))
            ForEach(Array(detalle(c).prefix(2).enumerated()), id: \.offset) { _, t in
                Text(t).font(.system(size: 13)).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func cabecera(_ c: ContenidoMomento) -> String {
        switch c.momento {
        case .manana: return entrenoDeHoy(c).map { "Hoy: \($0.nombre)" } ?? "Hoy, sin entreno"
        case .entreno: return entrenoDeHoy(c).map { "Toca \($0.nombre)" } ?? "Hora de entrenar"
        case .noche:
            if c.completo { return "Día completo" }
            return c.faltan.count == 1 ? "Falta uno" : "Faltan \(c.faltan.count)"
        }
    }

    private func detalle(_ c: ContenidoMomento) -> [String] {
        var l: [String] = []
        switch c.momento {
        case .manana:
            if !c.habitos.isEmpty { l.append("\(c.habitos.filter(\.hecho).count)/\(c.habitos.count) hábitos") }
            if let t = c.tareas.first { l.append("\(t.hora) \(t.texto)") }
            if let s = c.suenoMin, s > 0 { l.append("Dormiste \(ContenidoMomento.horas(s))") }
        case .entreno:
            l = entrenoDeHoy(c)?.ejercicios ?? []
            if l.isEmpty, let h = c.inicioEntreno {
                l.append("A las \(h.formatted(date: .omitted, time: .shortened))")
            }
        case .noche:
            if c.completo {
                l.append("Todo hecho. Buen trabajo.")
            } else {
                l.append(c.faltan.map(\.n).joined(separator: ", "))
                if c.rachaEnJuego > 0 { l.append("Racha de \(c.rachaEnJuego) d en juego") }
            }
        }
        return l
    }

    @ViewBuilder private func circular(_ c: ContenidoMomento) -> some View {
        switch c.momento {
        case .entreno:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "dumbbell.fill").font(.system(size: 22, weight: .semibold)).widgetAccentable()
            }
        default:
            let total = max(1, c.habitos.count)
            Gauge(value: Double(c.habitos.count - c.faltan.count), in: 0...Double(total)) {
                Image(systemName: c.momento.simbolo)
            } currentValueLabel: {
                if c.faltan.isEmpty {
                    Image(systemName: "checkmark")
                } else {
                    Text("\(c.faltan.count)")
                }
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
        }
    }
}

struct MomentoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TomMomento", provider: ProveedorMomento()) { entrada in
            MomentoVista(entrada: entrada)
        }
        .configurationDisplayName("Tom según la hora")
        .description("Por la mañana lo que toca hoy, antes de entrenar los ejercicios y por la noche lo que falta. Las horas se cambian en Tom › Ajustes › Pantalla de bloqueo.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}
