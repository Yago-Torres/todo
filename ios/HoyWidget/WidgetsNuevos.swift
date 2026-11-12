import SwiftUI
import WidgetKit
import AppIntents

// Widgets de un solo asunto, con leyenda donde hay gráficos: Pendientes de hoy (se completan desde el widget), Próximo
// entreno, Presupuesto del ciclo, Sueño de anoche, Racha (los hábitos se marcan desde el widget) y la Semana de hábitos.
// Los cuatro primeros leen /api/hoy (Proveedor, HoyWidget.swift); Entreno y Semana, /api/state (EstadoServidor.swift).

private let bloquesPequenos: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline]

// MARK: pendientes de hoy

struct PendientesVista: View {
    @Environment(\.widgetFamily) private var familia
    @Environment(\.widgetRenderingMode) private var modo
    let entrada: Entrada

    var body: some View {
        contenido.marcoWidget("/pendientes.html")
    }

    @ViewBuilder private var contenido: some View {
        switch entrada.estado {
        case .sinClaves: AvisoWidget(titulo: "Abre Tom", detalle: "para configurarlo")
        case .sinDatos(let motivo): AvisoWidget(titulo: "Sin datos", detalle: motivo)
        case .datos(let h): lista(h)
        }
    }

    @ViewBuilder private func lista(_ h: Hoy) -> some View {
        let tareas = h.tareas ?? []
        switch familia {
        case .accessoryInline:
            Label(tareas.isEmpty ? "Nada pendiente hoy" : "\(tareas.count) pendientes · \(tareas.first?.t ?? "")",
                  systemImage: "checklist")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "checklist").font(.system(size: 13, weight: .semibold)).widgetAccentable()
                    Text("\(tareas.count)").font(.system(size: 20, weight: .bold, design: .rounded))
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label(tareas.isEmpty ? "Nada pendiente" : "Pendientes · \(tareas.count)", systemImage: "checklist")
                    .font(.system(size: 12, weight: .semibold)).widgetAccentable()
                ForEach(Array(tareas.prefix(2).enumerated()), id: \.offset) { _, t in
                    Text(Resumen.linea(t)).font(.system(size: 12)).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            sistema(tareas, hoy: h.hoy)
        }
    }

    private func sistema(_ tareas: [Tarea], hoy: String) -> some View {
        let t = Tinta(modo)
        let cuantas = familia == .systemLarge ? 8 : familia == .systemMedium ? 4 : 3
        return VStack(alignment: .leading, spacing: 6) {
            CabeceraWidget(titulo: "Para hoy", simbolo: "checklist", cuenta: tareas.isEmpty ? nil : "\(tareas.count)")
            if tareas.isEmpty {
                Spacer(minLength: 0)
                Label("Nada pendiente hoy", systemImage: "checkmark.circle")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(t.texto)
                Spacer(minLength: 0)
            } else {
                ForEach(Array(tareas.prefix(cuantas).enumerated()), id: \.offset) { _, tarea in
                    FilaTareaWidget(tarea: tarea, hoy: hoy)
                }
                if tareas.count > cuantas {
                    Text("y \(tareas.count - cuantas) más").font(.system(size: 11)).foregroundStyle(t.suave)
                }
                Spacer(minLength: 0)
                if familia != .systemSmall {
                    HStack(spacing: 10) {
                        PuntoLeyenda(color: t.habitos, texto: "toca el círculo para completar")
                        if tareas.contains(where: { ($0.due ?? hoy) < hoy }) { PuntoLeyenda(color: t.aviso, texto: "vencida") }
                    }
                    .foregroundStyle(t.suave)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct FilaTareaWidget: View {
    @Environment(\.widgetRenderingMode) private var modo
    let tarea: Tarea
    let hoy: String

    private var vencida: Bool { (tarea.due ?? hoy) < hoy }

    private var etiqueta: some View {
        let t = Tinta(modo)
        return HStack(spacing: 4) {
            Text(tarea.t).font(.system(size: 13)).foregroundStyle(t.texto).lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: 2)
            if let hora = tarea.hora, !hora.isEmpty {
                Text(hora).font(.system(size: 11)).monospacedDigit().foregroundStyle(t.suave)
            }
        }
    }

    var body: some View {
        let t = Tinta(modo)
        if let id = tarea.id {
            Toggle(isOn: false, intent: CompletaTareaIntent(tarea: id, texto: tarea.t)) { etiqueta }
                .toggleStyle(CasillaStyle(color: vencida ? t.aviso : t.habitos))
        } else {
            etiqueta
        }
    }
}

struct PendientesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HoyPendientes", provider: Proveedor()) { entrada in
            PendientesVista(entrada: entrada)
        }
        .configurationDisplayName("Pendientes de hoy")
        .description("Lo que vence hoy. Toca el círculo para completarlo sin abrir Tom.")
        .supportedFamilies(bloquesPequenos + [.accessoryCircular])
    }
}

// MARK: próximo entreno

struct ProximoEntrenoVista: View {
    @Environment(\.widgetFamily) private var familia
    @Environment(\.widgetRenderingMode) private var modo
    let entrada: EntradaEstado

    var body: some View {
        contenido.marcoWidget("/entreno.html")
    }

    @ViewBuilder private var contenido: some View {
        switch entrada.estado {
        case .sinClaves: AvisoWidget(titulo: "Abre Tom", detalle: "para configurarlo")
        case .sinDatos(let motivo): AvisoWidget(titulo: "Sin datos", detalle: motivo)
        case .datos(let d): vista(d)
        }
    }

    @ViewBuilder private func vista(_ d: DatosEstado) -> some View {
        let t = Tinta(modo)
        let proxima = d.proxima
        switch familia {
        case .accessoryInline:
            Label(proxima.map { "\(DiasSemana.etiqueta($0.dia, hoy: d.hoy)): \(FichaDato.partes($0.nombre).0)" } ?? "Sin entreno esta semana",
                  systemImage: FichaDato.simboloEntreno(proxima?.tipo))
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label(proxima.map { DiasSemana.etiqueta($0.dia, hoy: d.hoy) } ?? "Entreno", systemImage: FichaDato.simboloEntreno(proxima?.tipo))
                    .font(.system(size: 12, weight: .semibold)).widgetAccentable()
                Text(proxima.map { FichaDato.partes($0.nombre).0 } ?? "Sin entreno en 7 días")
                    .font(.system(size: 18, weight: .bold, design: .rounded)).minimumScaleFactor(0.6)
                Text(proxima.map { FichaDato.partes($0.nombre).1 } ?? "").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium, .systemLarge:
            let filas = Array(d.sesiones.prefix(familia == .systemLarge ? 7 : 3))
            VStack(alignment: .leading, spacing: 7) {
                CabeceraWidget(titulo: "Entreno", simbolo: "dumbbell.fill",
                               cuenta: d.sesiones.isEmpty ? nil : "\(d.sesiones.filter(\.hecho).count)/\(d.sesiones.count) esta semana")
                if filas.isEmpty {
                    Spacer(minLength: 0)
                    Label("Sin entrenos en los próximos 7 días", systemImage: "moon.zzz.fill")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(t.texto)
                }
                ForEach(Array(filas.enumerated()), id: \.offset) { _, s in FilaEntreno(sesion: s, hoy: d.hoy) }
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    PuntoLeyenda(color: t.habitos, texto: "hecho")
                    PuntoLeyenda(color: t.suave, texto: "por hacer")
                    if d.sesiones.contains(where: { $0.dia == d.hoy && !$0.hecho }) { PuntoLeyenda(color: t.aviso, texto: "toca el círculo de hoy") }
                }
                .foregroundStyle(t.suave)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        default:
            VStack(alignment: .leading, spacing: 4) {
                Label(proxima.map { DiasSemana.etiqueta($0.dia, hoy: d.hoy) } ?? "Entreno", systemImage: FichaDato.simboloEntreno(proxima?.tipo))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(t.habitos).widgetAccentable().lineLimit(1)
                Spacer(minLength: 0)
                Text(proxima.map { FichaDato.partes($0.nombre).0 } ?? "Descanso")
                    .font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(t.texto)
                    .lineLimit(2).minimumScaleFactor(0.5)
                Text(proxima.map { FichaDato.partes($0.nombre).1 } ?? "Nada planificado en 7 días")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(t.suave).lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

struct FilaEntreno: View {
    @Environment(\.widgetRenderingMode) private var modo
    let sesion: SesionPlan
    let hoy: String

    private var texto: some View {
        let t = Tinta(modo)
        let partes = FichaDato.partes(sesion.nombre)
        return HStack(spacing: 6) {
            Image(systemName: FichaDato.simboloEntreno(sesion.tipo)).font(.system(size: 12)).foregroundStyle(t.suave).frame(width: 16)
            Text(partes.0).font(.system(size: 13, weight: .semibold)).foregroundStyle(t.texto).lineLimit(1)
            Spacer(minLength: 2)
            Text(DiasSemana.etiqueta(sesion.dia, hoy: hoy)).font(.system(size: 11)).foregroundStyle(t.suave).lineLimit(1)
        }
    }

    var body: some View {
        let t = Tinta(modo)
        if sesion.dia == hoy {
            Toggle(isOn: sesion.hecho, intent: MarcaHabitoIntent(habito: sesion.habito, nombre: FichaDato.partes(sesion.nombre).0,
                                                                  hecho: !sesion.hecho)) { texto }
                .toggleStyle(CasillaStyle(color: sesion.hecho ? t.habitos : t.aviso))
        } else {
            HStack(spacing: 6) {
                Image(systemName: sesion.hecho ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(sesion.hecho ? t.habitos : t.suave)
                texto
            }
        }
    }
}

struct EntrenoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HoyEntreno", provider: ProveedorEstado()) { entrada in
            ProximoEntrenoVista(entrada: entrada)
        }
        .configurationDisplayName("Próximo entreno")
        .description("La sesión que toca, hoy o el próximo día con entreno. Marca la de hoy desde el widget.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: presupuesto del ciclo

struct PresupuestoVista: View {
    @Environment(\.widgetFamily) private var familia
    @Environment(\.widgetRenderingMode) private var modo
    let entrada: Entrada

    var body: some View {
        contenido.marcoWidget("/gastos.html")
    }

    @ViewBuilder private var contenido: some View {
        switch entrada.estado {
        case .sinClaves: AvisoWidget(titulo: "Abre Tom", detalle: "para configurarlo")
        case .sinDatos(let motivo): AvisoWidget(titulo: "Sin datos", detalle: motivo)
        case .datos(let h):
            if let g = h.gastos, let presu = g.presu, presu > 0, let total = g.total { vista(g, presu: presu, total: total) }
            else { AvisoWidget(titulo: "Gastos sin conexión", detalle: "Gastos no responde o no hay presupuesto") }
        }
    }

    @ViewBuilder private func vista(_ g: GastosHoy, presu: Double, total: Double) -> some View {
        let t = Tinta(modo)
        let queda = presu - total
        let gastado = max(0, min(1, total / presu))
        let color = queda < 0 ? t.aviso : t.habitos
        let diario = g.al_dia.map { "\(Resumen.euros($0))/día" }
        let dias = g.quedan.map { "\($0) d" }
        let extra = [diario, dias].compactMap { $0 }.joined(separator: " · ")
        let quedaTexto = queda >= 0 ? Resumen.euros(queda) : "-" + Resumen.euros(-queda)
        switch familia {
        case .accessoryInline:
            Label(queda >= 0 ? "Quedan \(Resumen.euros(queda))" : "Pasado en \(Resumen.euros(-queda))", systemImage: "eurosign.circle")
        case .accessoryCircular:
            Gauge(value: gastado) {
                Image(systemName: "eurosign")
            } currentValueLabel: {
                Text("\(Int(queda.rounded()))").minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Ciclo", systemImage: "eurosign.circle").font(.system(size: 12, weight: .semibold)).widgetAccentable()
                Text(quedaTexto).font(.system(size: 20, weight: .bold, design: .rounded))
                Text(extra).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemSmall:
            ZStack {
                Anillos(valores: [(gastado, color)], grosor: 12)
                VStack(spacing: 0) {
                    Text(quedaTexto)
                        .font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(t.texto)
                        .minimumScaleFactor(0.5).lineLimit(1)
                    Text(queda >= 0 ? "quedan" : "pasado").font(.system(size: 11)).foregroundStyle(t.suave)
                }
                .padding(.horizontal, 22)
            }
        default:
            HStack(spacing: 16) {
                Anillos(valores: [(gastado, color)], grosor: 12).frame(width: 104, height: 104)
                VStack(alignment: .leading, spacing: 4) {
                    CabeceraWidget(titulo: "Ciclo de gastos", simbolo: "eurosign.circle")
                    Text(quedaTexto)
                        .font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(t.texto)
                        .minimumScaleFactor(0.5).lineLimit(1)
                    Text((queda >= 0 ? "quedan" : "pasado") + " de " + Resumen.euros(presu) + (extra.isEmpty ? "" : " · " + extra))
                        .font(.system(size: 12)).foregroundStyle(t.suave).lineLimit(2)
                    Spacer(minLength: 0)
                    HStack(spacing: 10) {
                        PuntoLeyenda(color: color, texto: "gastado \(Resumen.euros(total))")
                        PuntoLeyenda(color: t.campo, texto: "libre")
                    }
                    .foregroundStyle(t.suave)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

struct PresupuestoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HoyPresupuesto", provider: Proveedor()) { entrada in
            PresupuestoVista(entrada: entrada)
        }
        .configurationDisplayName("Presupuesto del ciclo")
        .description("Lo que te queda del ciclo de cobro de Gastos y a cuánto sale al día.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: sueño de anoche

struct BarrasSueno: View {
    @Environment(\.widgetRenderingMode) private var modo
    let serie: [Int?]
    let hoy: String

    private func inicial(_ i: Int) -> String {
        guard let h = DiasSemana.fecha(hoy),
              let d = Calendar(identifier: .gregorian).date(byAdding: .day, value: i - (serie.count - 1), to: h) else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEEEE"
        return f.string(from: d).uppercased()
    }

    var body: some View {
        let t = Tinta(modo)
        let tope = Double(max(serie.compactMap { $0 }.max() ?? 0, 540))
        GeometryReader { geo in
            let alto = max(10, geo.size.height - 14)
            ZStack(alignment: .topLeading) {
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array(serie.enumerated()), id: \.offset) { i, v in
                        VStack(spacing: 2) {
                            ZStack(alignment: .bottom) {
                                Capsule().fill(t.campo).frame(height: alto)
                                if let v, v > 0 {
                                    Capsule()
                                        .fill(i == serie.count - 1 ? t.sueno : t.sueno.opacity(0.55))
                                        .frame(height: max(4, alto * Double(v) / tope))
                                        .widgetAccentable(i == serie.count - 1)
                                }
                            }
                            Text(inicial(i)).font(.system(size: 9)).foregroundStyle(t.suave)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                // el objetivo de 8 h
                Rectangle()
                    .fill(t.texto.opacity(0.55))
                    .frame(height: 1)
                    .offset(y: alto * (1 - Objetivo.sueno / tope))
            }
        }
    }
}

struct SuenoVista: View {
    @Environment(\.widgetFamily) private var familia
    @Environment(\.widgetRenderingMode) private var modo
    let entrada: Entrada

    var body: some View {
        contenido.marcoWidget("/salud.html")
    }

    @ViewBuilder private var contenido: some View {
        switch entrada.estado {
        case .sinClaves: AvisoWidget(titulo: "Abre Tom", detalle: "para configurarlo")
        case .sinDatos(let motivo): AvisoWidget(titulo: "Sin datos", detalle: motivo)
        case .datos(let h): vista(h)
        }
    }

    @ViewBuilder private func vista(_ h: Hoy) -> some View {
        let t = Tinta(modo)
        let s = h.salud?.sueno
        let minutos = s?.ultimo ?? 0
        let valor = minutos > 0 ? Resumen.hm(minutos) : "—"
        let media = s?.media.map { "media \(Resumen.hm($0))" } ?? ""
        switch familia {
        case .accessoryInline:
            Label(minutos > 0 ? "\(valor) dormido" : "Sin sueño", systemImage: "bed.double.fill")
        case .accessoryCircular:
            Gauge(value: min(1, Double(minutos) / Objetivo.sueno)) {
                Image(systemName: "bed.double.fill")
            } currentValueLabel: {
                Text(minutos > 0 ? "\(minutos / 60):" + String(format: "%02d", minutos % 60) : "—").minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Anoche", systemImage: "bed.double.fill").font(.system(size: 12, weight: .semibold)).widgetAccentable()
                Text(valor).font(.system(size: 22, weight: .bold, design: .rounded))
                Text(media).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemSmall:
            VStack(alignment: .leading, spacing: 4) {
                Label("Anoche", systemImage: "bed.double.fill").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.sueno).widgetAccentable()
                Spacer(minLength: 0)
                Text(valor).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(t.texto)
                    .lineLimit(1).minimumScaleFactor(0.5)
                BarraDato(progreso: Double(minutos) / Objetivo.sueno, color: t.sueno).frame(height: 7)
                Text(media.isEmpty ? "objetivo 8 h" : "\(media) · meta 8 h").font(.system(size: 10)).foregroundStyle(t.suave).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        default:
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    CabeceraWidget(titulo: "Anoche", simbolo: "bed.double.fill", color: t.sueno)
                    Text(valor).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(t.texto)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text(media).font(.system(size: 12)).foregroundStyle(t.suave).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    PuntoLeyenda(color: t.sueno, texto: "noche (la de anoche, más fuerte)").foregroundStyle(t.suave)
                    HStack(spacing: 4) {
                        Rectangle().fill(t.texto.opacity(0.55)).frame(width: 10, height: 1)
                        Text("meta 8 h").font(.system(size: 10)).lineLimit(1)
                    }
                    .foregroundStyle(t.suave)
                }
                .frame(width: 130, alignment: .leading)
                BarrasSueno(serie: s?.serie ?? [], hoy: h.hoy)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

struct SuenoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HoySueno", provider: Proveedor()) { entrada in
            SuenoVista(entrada: entrada)
        }
        .configurationDisplayName("Sueño de anoche")
        .description("Lo que dormiste y las últimas siete noches frente a tu meta de 8 horas.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: racha

struct RachaVista: View {
    @Environment(\.widgetFamily) private var familia
    @Environment(\.widgetRenderingMode) private var modo
    let entrada: Entrada

    var body: some View {
        contenido.marcoWidget("/habitos.html")
    }

    @ViewBuilder private var contenido: some View {
        switch entrada.estado {
        case .sinClaves: AvisoWidget(titulo: "Abre Tom", detalle: "para configurarlo")
        case .sinDatos(let motivo): AvisoWidget(titulo: "Sin datos", detalle: motivo)
        case .datos(let h): vista(h)
        }
    }

    @ViewBuilder private func vista(_ h: Hoy) -> some View {
        let t = Tinta(modo)
        let r = Resumen(h, ahora: entrada.date)
        let orden = h.habitos.sorted { ($0.racha, !$0.hecho ? 1 : 0) > ($1.racha, !$1.hecho ? 1 : 0) }
        let mejor = orden.first
        switch familia {
        case .accessoryInline:
            Label(mejor.map { "Racha \($0.racha) d · \($0.n)" } ?? "Sin racha", systemImage: "flame.fill")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "flame.fill").font(.system(size: 13)).widgetAccentable()
                    Text("\(mejor?.racha ?? 0)").font(.system(size: 20, weight: .bold, design: .rounded))
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Racha", systemImage: "flame.fill").font(.system(size: 12, weight: .semibold)).widgetAccentable()
                Text("\(mejor?.racha ?? 0) días").font(.system(size: 20, weight: .bold, design: .rounded))
                Text(mejor?.n ?? "Sin hábitos").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemSmall:
            VStack(alignment: .leading, spacing: 2) {
                Label(r.enJuego ? "Racha en juego" : "Racha", systemImage: "flame.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(r.enJuego ? t.aviso : t.habitos)
                    .widgetAccentable().lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Text("\(mejor?.racha ?? 0)").font(.system(size: 54, weight: .bold, design: .rounded)).foregroundStyle(t.texto)
                Text("días · \(mejor?.n ?? "sin hábitos")").font(.system(size: 12, weight: .medium)).foregroundStyle(t.suave)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        default:
            let filas = Array(orden.prefix(familia == .systemLarge ? 8 : 4))
            VStack(alignment: .leading, spacing: 6) {
                CabeceraWidget(titulo: "Rachas", simbolo: "flame.fill", cuenta: "\(r.hechos)/\(r.habitos.count) hoy")
                ForEach(filas) { hab in FilaRacha(habito: hab, enJuego: r.enJuego) }
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    PuntoLeyenda(color: t.habitos, texto: "días seguidos")
                    PuntoLeyenda(color: t.aviso, texto: "en juego esta noche")
                }
                .foregroundStyle(t.suave)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct FilaRacha: View {
    @Environment(\.widgetRenderingMode) private var modo
    let habito: Habito
    let enJuego: Bool

    var body: some View {
        let t = Tinta(modo)
        let peligro = enJuego && !habito.hecho && habito.racha >= 2
        Toggle(isOn: habito.hecho, intent: MarcaHabitoIntent(habito: habito.id, nombre: habito.n, hecho: !habito.hecho)) {
            HStack(spacing: 4) {
                Text(habito.n).font(.system(size: 13, weight: habito.hecho ? .regular : .semibold))
                    .foregroundStyle(habito.hecho ? t.suave : t.texto).lineLimit(1).minimumScaleFactor(0.75)
                Spacer(minLength: 2)
                if habito.racha > 0 {
                    Label("\(habito.racha)", systemImage: "flame.fill").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(peligro ? t.aviso : t.suave)
                }
            }
        }
        .toggleStyle(CasillaStyle(color: habito.hecho ? t.habitos : t.suave))
    }
}

struct RachaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HoyRacha", provider: Proveedor()) { entrada in
            RachaVista(entrada: entrada)
        }
        .configurationDisplayName("Racha")
        .description("Tus rachas de hábitos, y marca el de hoy desde el widget para no romperla.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: la semana de hábitos

struct SemanaVista: View {
    @Environment(\.widgetFamily) private var familia
    @Environment(\.widgetRenderingMode) private var modo
    let entrada: EntradaEstado

    var body: some View {
        contenido.marcoWidget("/habitos.html")
    }

    @ViewBuilder private var contenido: some View {
        switch entrada.estado {
        case .sinClaves: AvisoWidget(titulo: "Abre Tom", detalle: "para configurarlo")
        case .sinDatos(let motivo): AvisoWidget(titulo: "Sin datos", detalle: motivo)
        case .datos(let d): tabla(d)
        }
    }

    private func tabla(_ d: DatosEstado) -> some View {
        let t = Tinta(modo)
        let activos = d.habitos.filter { !$0.plan.isEmpty || !$0.hechos.isEmpty }
        let filas = Array(activos.prefix(familia == .systemLarge ? 9 : 4))
        let hechos = activos.reduce(0) { $0 + $1.hechos.count }
        let previstos = activos.reduce(0) { $0 + max($1.plan.count, $1.hechos.count) }
        return VStack(alignment: .leading, spacing: 5) {
            CabeceraWidget(titulo: "Semana de hábitos", simbolo: "calendar", cuenta: previstos > 0 ? "\(hechos)/\(previstos)" : nil)
            HStack(spacing: 0) {
                Spacer().frame(width: 92)
                ForEach(Array(d.semana.enumerated()), id: \.offset) { i, dia in
                    Text(DiasSemana.iniciales[i % 7])
                        .font(.system(size: 10, weight: dia == d.hoy ? .bold : .regular))
                        .foregroundStyle(dia == d.hoy ? t.texto : t.suave)
                        .frame(maxWidth: .infinity)
                }
            }
            if filas.isEmpty {
                Spacer(minLength: 0)
                Text("Sin plan esta semana").font(.system(size: 13, weight: .semibold)).foregroundStyle(t.texto)
            }
            ForEach(filas) { h in FilaSemana(habito: h, semana: d.semana, hoy: d.hoy) }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                PuntoLeyenda(color: t.habitos, texto: "hecho")
                PuntoLeyenda(color: t.suave, texto: "previsto")
                PuntoLeyenda(color: t.aviso, texto: "sin hacer")
            }
            .foregroundStyle(t.suave)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct FilaSemana: View {
    @Environment(\.widgetRenderingMode) private var modo
    let habito: HabitoSemana
    let semana: [String]
    let hoy: String

    private func punto(_ dia: String) -> some View {
        let t = Tinta(modo)
        let hecho = habito.hechos.contains(dia)
        let previsto = habito.plan.contains(dia)
        let color = t.completo ? Color(hex: habito.c) : Color.primary
        return ZStack {
            if hecho {
                Circle().fill(color)
            } else if previsto {
                Circle().strokeBorder(dia < hoy ? t.aviso : t.suave, lineWidth: 1.6)
            } else {
                Circle().fill(t.campo).frame(width: 5, height: 5)
            }
        }
        .frame(width: 15, height: 15)
        .widgetAccentable(hecho)
        .frame(maxWidth: .infinity)
    }

    var body: some View {
        let t = Tinta(modo)
        HStack(spacing: 0) {
            Text(habito.n).font(.system(size: 12, weight: .medium)).foregroundStyle(t.texto)
                .lineLimit(1).minimumScaleFactor(0.7).frame(width: 92, alignment: .leading)
            ForEach(Array(semana.enumerated()), id: \.offset) { _, dia in
                if dia == hoy && (habito.plan.contains(dia) || habito.hechos.contains(dia)) {
                    Button(intent: MarcaHabitoIntent(habito: habito.id, nombre: habito.n, hecho: !habito.hechos.contains(dia))) {
                        punto(dia)
                    }
                    .buttonStyle(.plain)
                } else {
                    punto(dia)
                }
            }
        }
    }
}

struct SemanaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HoySemana", provider: ProveedorEstado()) { entrada in
            SemanaVista(entrada: entrada)
        }
        .configurationDisplayName("Semana de hábitos")
        .description("Cada hábito, de lunes a domingo: lo hecho, lo previsto y lo que se quedó sin hacer. Marca el de hoy con un toque.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
