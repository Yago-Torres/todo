import AppIntents
import SwiftUI
import WidgetKit

// Un widget, un dato, «como un script»: al añadirlo (o al mantenerlo pulsado > Editar) eliges qué enseña.
// Pensado para la pantalla de bloqueo y para StandBy (el pequeño sin fondo, a pantalla grande, se lee de lejos).
// Todo sale de /api/hoy, con la misma carga y la misma caché que el widget grande (Proveedor.carga()).

// MARK: qué mostrar

enum DatoWidget: String, AppEnum {
    case pasos, sueno, racha, pendientes, gastos, entreno, carrera, peso

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Dato")
    static var caseDisplayRepresentations: [DatoWidget: DisplayRepresentation] = [
        .pasos: "Pasos",
        .sueno: "Sueño",
        .racha: "Racha y hábitos",
        .pendientes: "Pendientes",
        .gastos: "Gastos (queda del ciclo)",
        .entreno: "Entreno de hoy",
        .carrera: "Carrera de hoy (plan de 5k)",
        .peso: "Peso",
    ]
}

struct ConfiguraDato: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Qué mostrar"
    static var description = IntentDescription("Elige el dato que enseña el widget.")

    @Parameter(title: "Dato", default: .pasos) var dato: DatoWidget

    init() {}

    init(dato: DatoWidget) { self.dato = dato }
}

// MARK: línea de tiempo

struct EntradaDato: TimelineEntry {
    let date: Date
    let estado: EstadoWidget
    let dato: DatoWidget
}

struct ProveedorDato: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> EntradaDato {
        EntradaDato(date: Date(), estado: .datos(Hoy.muestraDato), dato: .pasos)
    }

    func snapshot(for configuration: ConfiguraDato, in context: Context) async -> EntradaDato {
        if context.isPreview {
            return EntradaDato(date: Date(), estado: .datos(Hoy.muestraDato), dato: configuration.dato)
        }
        return EntradaDato(date: Date(), estado: await Proveedor.carga(), dato: configuration.dato)
    }

    func timeline(for configuration: ConfiguraDato, in context: Context) async -> Timeline<EntradaDato> {
        let ahora = Date()
        let entrada = EntradaDato(date: ahora, estado: await Proveedor.carga(), dato: configuration.dato)
        return Timeline(entries: [entrada], policy: .after(ahora.addingTimeInterval(15 * 60)))
    }
}

extension Hoy {
    /// La muestra del widget grande con lo que este necesita de más (galería de widgets y placeholder).
    static var muestraDato: Hoy {
        var h = Hoy.muestra
        h.peso = PesoHoy(dia: Fecha.hoy(), kg: 78.3, media: 78.5)
        h.gastos = GastosHoy(total: 935, presu: 1402, ayer: 12, inicio: nil, fin: nil, quedan: 17, al_dia: 27.45)
        h.entreno = [EntrenoHoy(id: "a", n: "Pull A · Espalda bíceps", tipo: "pesas", hecho: false)]
        h.carrera = CarreraHoy(estimacion: 1440, objetivo: 1320, semana: 3, n_semanas: 20, fase: "Base",
                               proxima: SesionCarrera(dia: Fecha.hoy(), n: "Rodaje suave · 35 min", tipo: "suave", hecho: false),
                               hoy_hecho: false)
        return h
    }
}

// MARK: el dato ya compuesto

/// Lo que pinta cada familia para un dato: así las cuatro vistas dicen lo mismo.
struct FichaDato {
    var simbolo: String
    var titulo: String
    var valor: String        // grande: «7.500», «Pull A», «466 €»
    var corto: String        // dentro del círculo: «7,5k», «7:00», «466€»
    var linea: String        // la de encima de la hora: «7.500 pasos»
    var detalle: String
    var progreso: Double?    // 0…1; nil = sin anillo ni barra
    var color: Color
    var ruta: String

    init(_ dato: DatoWidget, _ h: Hoy, ahora: Date) {
        switch dato {
        case .pasos:
            let p = h.salud?.pasos
            let n = p?.ultimo ?? 0
            simbolo = "figure.walk"
            titulo = "Pasos"
            valor = n > 0 ? Resumen.miles(n) : "—"
            corto = FichaDato.kilos(n)
            linea = n > 0 ? "\(Resumen.miles(n)) pasos" : "Sin pasos"
            detalle = ["ayer", p?.media.map { "media \(Resumen.miles($0))" }].compactMap { $0 }.joined(separator: " · ")
            progreso = min(1, Double(n) / Objetivo.pasos)
            color = Paleta.pas
            ruta = "/salud.html"

        case .sueno:
            let s = h.salud?.sueno
            let m = s?.ultimo ?? 0
            simbolo = "bed.double.fill"
            titulo = "Sueño"
            valor = m > 0 ? Resumen.hm(m) : "—"
            corto = m > 0 ? "\(m / 60):" + String(format: "%02d", m % 60) : "—"
            linea = m > 0 ? "\(Resumen.hm(m)) dormido" : "Sin sueño"
            detalle = ["anoche", s?.media.map { "media \(Resumen.hm($0))" }].compactMap { $0 }.joined(separator: " · ")
            progreso = min(1, Double(m) / Objetivo.sueno)
            color = Paleta.sue
            ruta = "/salud.html"

        case .racha:
            let planificados = h.habitos.filter { $0.plan }
            let base = planificados.isEmpty ? h.habitos : planificados
            let hechos = base.filter { $0.hecho }.count
            let mejor = h.habitos.max { $0.racha < $1.racha }
            let hora = Calendar.current.component(.hour, from: ahora)
            let enJuego = hora >= 20 && h.habitos.contains { $0.arriesga }
            let cuenta = "\(hechos)/\(base.count)"
            let dias = mejor?.racha ?? 0
            simbolo = "flame.fill"
            titulo = planificados.isEmpty ? "Hábitos" : "Hábitos de hoy"
            valor = cuenta
            corto = cuenta
            if enJuego {
                detalle = "racha en juego"
            } else if let mejor, mejor.racha > 0 {
                detalle = "racha \(mejor.racha) d · \(mejor.n)"
            } else {
                detalle = "sin racha"
            }
            linea = "\(cuenta) hábitos" + (dias > 0 ? " · racha \(dias) d" : "")
            progreso = base.isEmpty ? 0 : Double(hechos) / Double(base.count)
            color = enJuego ? Paleta.aviso : Paleta.hab
            ruta = "/habitos.html"

        case .pendientes:
            simbolo = "checklist"
            titulo = "Pendientes"
            ruta = "/pendientes.html"
            progreso = nil
            if let tareas = h.tareas {
                valor = "\(tareas.count)"
                corto = "\(tareas.count)"
                linea = tareas.isEmpty ? "Nada pendiente hoy" : "\(tareas.count) pendiente" + (tareas.count == 1 ? "" : "s")
                detalle = tareas.first.map(Resumen.linea) ?? "Nada que venza hoy"
                color = tareas.isEmpty ? Paleta.hab : Paleta.aviso
            } else {
                valor = "—"
                corto = "—"
                linea = "Pendientes sin conexión"
                detalle = "El vault no responde"
                color = Paleta.suave
            }

        case .gastos:
            let g = h.gastos
            simbolo = "eurosign.circle.fill"
            titulo = "Queda del ciclo"
            ruta = "/gastos.html"
            if let g, let queda = g.queda {
                valor = Resumen.euros(queda)
                corto = "\(Int(queda.rounded()))€"
                linea = queda >= 0 ? "Quedan \(Resumen.euros(queda))" : "Ciclo pasado en \(Resumen.euros(-queda))"
                if queda < 0 {
                    detalle = "te has pasado del presupuesto"
                } else {
                    detalle = [g.al_dia.map { "\(Resumen.euros($0))/día" }, g.quedan.map { "\($0) d" }]
                        .compactMap { $0 }.joined(separator: " · ")
                }
                progreso = max(0, min(1, queda / (g.presu ?? 1)))
                color = queda < 0 ? Paleta.aviso : Paleta.hab
            } else {
                valor = "—"
                corto = "—"
                linea = "Gastos sin conexión"
                detalle = "Gastos no responde"
                progreso = nil
                color = Paleta.suave
            }

        case .entreno:
            let sesiones = h.entreno ?? []
            let hechos = sesiones.filter { $0.hecho }.count
            let siguiente = sesiones.first { !$0.hecho }
            titulo = "Entreno de hoy"
            ruta = "/entreno.html"
            color = Paleta.hab
            simbolo = FichaDato.simboloEntreno((siguiente ?? sesiones.first)?.tipo)
            if sesiones.isEmpty {
                valor = "Descanso"
                corto = "—"
                linea = "Hoy descanso"
                detalle = "Hoy no toca entrenar"
                progreso = nil
            } else if let siguiente {
                let partes = FichaDato.partes(siguiente.n)
                let luego = sesiones.filter { !$0.hecho && $0.id != siguiente.id }.map { FichaDato.partes($0.n).0 }
                valor = partes.0
                corto = "\(hechos)/\(sesiones.count)"
                linea = siguiente.n
                detalle = ([partes.1] + (luego.isEmpty ? [] : ["luego " + luego.joined(separator: ", ")]))
                    .filter { !$0.isEmpty }.joined(separator: " · ")
                progreso = Double(hechos) / Double(sesiones.count)
            } else {
                valor = "Hecho"
                corto = "\(hechos)/\(sesiones.count)"
                linea = "Entreno hecho"
                detalle = sesiones.map { FichaDato.partes($0.n).0 }.joined(separator: ", ")
                progreso = 1
            }

        case .carrera:
            let c = h.carrera
            simbolo = "figure.run"
            titulo = "Carrera"
            ruta = "/carrera.html"
            color = Paleta.pas
            let estimado = c?.estimacion.map { "5k en \(FichaDato.mmss($0))" }
            var semana: String?
            if let s = c?.semana, let n = c?.n_semanas { semana = "semana \(s)/\(n)" }
            if let c, let s = c.semana, let n = c.n_semanas, n > 0 {
                progreso = min(1, Double(s) / Double(n))
            } else {
                progreso = nil
            }
            if c?.hoy_hecho == true {
                valor = "Hecha"
                corto = "Hecha"
                linea = "Carrera de hoy hecha"
                detalle = [estimado, semana].compactMap { $0 }.joined(separator: " · ")
            } else if let p = c?.proxima, p.dia == h.hoy {
                let partes = FichaDato.partes(p.n)
                valor = partes.0
                corto = "Hoy"
                linea = "Hoy: \(p.n)"
                detalle = ([partes.1] + [semana, c?.fase].compactMap { $0 }).filter { !$0.isEmpty }.joined(separator: " · ")
            } else if let p = c?.proxima {
                let dia = FichaDato.diaCorto(p.dia)
                valor = "Hoy no"
                corto = dia
                linea = "Carrera el \(dia)"
                detalle = "\(dia): \(FichaDato.partes(p.n).0)"
            } else {
                valor = "—"
                corto = "—"
                linea = c == nil ? "Carrera sin conexión" : "Sin carreras en el plan"
                detalle = estimado ?? "Sin plan"
            }

        case .peso:
            let p = h.peso
            simbolo = "scalemass.fill"
            titulo = "Peso"
            ruta = "/salud.html"
            progreso = nil
            color = Paleta.sue
            if let kg = p?.kg {
                let texto = "\(FichaDato.decimal(kg)) kg"
                valor = texto
                corto = FichaDato.decimal(kg)
                linea = texto
                detalle = [p?.media.map { "media \(FichaDato.decimal($0))" }, p?.dia.map { FichaDato.diaCorto($0) }]
                    .compactMap { $0 }.joined(separator: " · ")
            } else {
                valor = "—"
                corto = "—"
                linea = "Sin peso"
                detalle = "Pésate y se apunta solo"
            }
        }
    }

    /// «Pull A · Espalda bíceps» → («Pull A», «Espalda bíceps»): lo primero va en grande.
    static func partes(_ n: String) -> (String, String) {
        let trozos = n.components(separatedBy: " · ")
        return (trozos.first ?? n, trozos.dropFirst().joined(separator: " · "))
    }

    static func simboloEntreno(_ tipo: String?) -> String {
        switch tipo ?? "" {
        case "pesas": return "dumbbell.fill"
        case "carrera": return "figure.run"
        case "movilidad": return "figure.flexibility"
        case "otro": return "figure.climbing"
        default: return "moon.zzz.fill"
        }
    }

    static func kilos(_ n: Int) -> String {
        if n <= 0 { return "—" }
        if n < 1000 { return "\(n)" }
        let k = Double(n) / 1000
        return (k < 10 ? String(format: "%.1fk", k) : String(format: "%.0fk", k)).replacingOccurrences(of: ".", with: ",")
    }

    static func mmss(_ s: Int) -> String { "\(s / 60):" + String(format: "%02d", s % 60) }

    static func decimal(_ x: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "es_ES")
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 1
        return f.string(from: NSNumber(value: x)) ?? String(format: "%.1f", x)
    }

    /// «2026-11-13» → «jue 13».
    static func diaCorto(_ dia: String) -> String {
        let entrada = DateFormatter()
        entrada.locale = Locale(identifier: "en_US_POSIX")
        entrada.calendar = Calendar(identifier: .gregorian)
        entrada.dateFormat = "yyyy-MM-dd"
        guard let d = entrada.date(from: dia) else { return dia }
        let salida = DateFormatter()
        salida.locale = Locale(identifier: "es_ES")
        salida.dateFormat = "EEE d"
        return salida.string(from: d).replacingOccurrences(of: ".", with: "")
    }
}

// MARK: vistas

struct DatoVista: View {
    @Environment(\.widgetFamily) private var familia
    @Environment(\.widgetRenderingMode) private var modo
    @Environment(\.showsWidgetContainerBackground) private var conFondo
    let entrada: EntradaDato

    private var ruta: String {
        if case .datos(let h) = entrada.estado { return FichaDato(entrada.dato, h, ahora: entrada.date).ruta }
        return "/"
    }

    var body: some View {
        contenido
            .widgetURL(rutaURL(ruta))
            .containerBackground(for: .widget) {
                if familia == .systemSmall { Paleta.fondo } else { Color.clear }
            }
    }

    @ViewBuilder private var contenido: some View {
        switch entrada.estado {
        case .sinClaves:
            aviso("Abre Tom", detalle: "para configurarlo")
        case .sinDatos(let motivo):
            aviso("Sin datos", detalle: motivo)
        case .datos(let h):
            let f = FichaDato(entrada.dato, h, ahora: entrada.date)
            switch familia {
            case .accessoryCircular: DatoCircular(f: f)
            case .accessoryRectangular: DatoRectangular(f: f)
            case .accessoryInline: Label(f.linea, systemImage: f.simbolo)
            default: DatoPequeno(f: f, conFondo: conFondo, aColor: modo == .fullColor)
            }
        }
    }

    @ViewBuilder private func aviso(_ titulo: String, detalle: String) -> some View {
        switch familia {
        case .accessoryInline:
            Text(titulo)
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 20, weight: .semibold))
            }
        default:
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(familia == .systemSmall ? Paleta.texto : Color.primary)
                Text(detalle)
                    .font(.system(size: 11))
                    .foregroundStyle(familia == .systemSmall ? Paleta.suave : Color.secondary)
                    .lineLimit(3)
            }
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

struct DatoCircular: View {
    let f: FichaDato

    var body: some View {
        if let p = f.progreso {
            Gauge(value: min(1, max(0, p))) {
                Image(systemName: f.simbolo)
            } currentValueLabel: {
                Text(f.corto)
                    .minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        } else {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: f.simbolo)
                        .font(.system(size: 13, weight: .semibold))
                        .widgetAccentable()
                    Text(f.corto)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .padding(5)
            }
        }
    }
}

struct DatoRectangular: View {
    let f: FichaDato

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(f.titulo, systemImage: f.simbolo)
                .font(.system(size: 12, weight: .semibold))
                .widgetAccentable()
            Text(f.valor)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
            Text(f.detalle)
                .font(.system(size: 12))
                .foregroundStyle(Color.secondary)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// El pequeño de la pantalla de inicio y de StandBy. En StandBy (sin fondo) el número crece para leerse de lejos.
struct DatoPequeno: View {
    let f: FichaDato
    let conFondo: Bool
    let aColor: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: conFondo ? 4 : 2) {
            Label(f.titulo, systemImage: f.simbolo)
                .font(.system(size: conFondo ? 13 : 16, weight: .semibold))
                .foregroundStyle(aColor ? f.color : Color.secondary)
                .widgetAccentable()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            Text(f.valor)
                .font(.system(size: conFondo ? 40 : 60, weight: .bold, design: .rounded))
                .foregroundStyle(aColor ? Paleta.texto : Color.primary)
                .lineLimit(conFondo ? 2 : 1)
                .minimumScaleFactor(0.3)
            if conFondo || f.progreso == nil {
                Text(f.detalle)
                    .font(.system(size: conFondo ? 12 : 16, weight: .medium))
                    .foregroundStyle(aColor ? Paleta.suave : Color.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            if let p = f.progreso {
                BarraDato(progreso: p, color: aColor ? f.color : Color.primary)
                    .frame(height: conFondo ? 6 : 10)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct BarraDato: View {
    let progreso: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let p = min(1, max(0, progreso))
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.25))
                if p > 0 {
                    Capsule()
                        .fill(color)
                        .frame(width: max(geo.size.height, geo.size.width * p))
                        .widgetAccentable()
                }
            }
        }
    }
}

struct HoyDatoWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "HoyDato", intent: ConfiguraDato.self, provider: ProveedorDato()) { entrada in
            DatoVista(entrada: entrada)
        }
        .configurationDisplayName("Un dato")
        .description("Elige qué enseña: pasos, sueño, hábitos, pendientes, gastos, entreno, carrera o peso.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall])
        .containerBackgroundRemovable(true)
    }
}
