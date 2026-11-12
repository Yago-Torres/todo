import Charts
import Observation
import SwiftUI

/// El plan de 5k (GET /api/carrera, carrera.informe en el servidor), como static/carrera.html: el 5k estimado y lo
/// que falta, la semana, los ritmos, cómo se ajusta y tres gráficas (camino al objetivo, minutos por semana y ritmo de
/// cada carrera). Sin red, la última copia.
struct InformeCarrera: Decodable {
    struct Agenda: Decodable, Hashable {
        var dia: String
        var n: String
        var tipo: String
        var hecho: Bool
    }

    struct Objetivo: Decodable {
        var dia: String
        var seg: Double
    }

    struct Estimacion: Decodable {
        var seg: Double
        var dia: String?
        var fuente: String
    }

    struct Hito: Decodable {
        var dia: String
        var seg: Double
    }

    struct Ritmos: Decodable {
        var suave: [Double]
        var tempo: [Double]
        var series: Double
        var objetivo: Double
    }

    struct SesionPlan: Decodable, Hashable {
        var n: String
        var min: Double
        var tipo: String
    }

    struct Semana: Decodable, Identifiable {
        var n: Int
        var lunes: String
        var fase: String
        var descarga: Bool
        var test: Bool
        var sesiones: [SesionPlan]
        var planMin: Double
        var hechoMin: Double
        var hechoKm: Double
        var estado: String
        var camino: Double?
        var est: Double?
        var id: Int { n }
    }

    struct Carrera: Decodable, Identifiable {
        var dia: String
        var km: Double
        var seg: Double
        var n: String?
        var ritmo: Double?
        var tipo: String
        var id: String { "\(dia)-\(km)-\(seg)" }
    }

    struct Proyeccion: Decodable {
        var seg: Double?
        var texto: String
    }

    var agenda: [Agenda]
    var objetivo: Objetivo
    var inicio: String
    var nSemanas: Int
    var semana: Int
    var estimacion: Estimacion
    var historial: [Hito]
    var ritmos: Ritmos
    var semanas: [Semana]
    var carreras: [Carrera]
    var notas: [String]
    var proyeccion: Proyeccion

    static let tipos: [(String, String)] = [("suave", "Rodaje suave"), ("largo", "Rodaje largo"), ("series", "Series"),
                                            ("tempo", "Tempo"), ("test", "Test o carrera"), ("libre", "Otra")]

    static func nombre(_ tipo: String) -> String { tipos.first { $0.0 == tipo }?.1 ?? "Otra" }

    /// Color = el tipo de sesión, siempre el mismo.
    static func color(_ tipo: String) -> Color {
        switch tipo {
        case "suave": return Tema.acento
        case "largo": return Tema.acento.opacity(0.55)
        case "series": return Tema.aviso
        case "tempo": return Tema.peligro
        case "test": return Tema.texto
        default: return Tema.suave
        }
    }
}

@MainActor @Observable
final class CarreraDatos {
    static let shared = CarreraDatos()

    private(set) var informe: InformeCarrera?
    private(set) var copia: Date?
    private(set) var error: String?
    private(set) var cargando = false

    private init() {
        if let r = Local.lee(Local.clave("GET", "/api/carrera")) {
            informe = Self.decodifica(r.cuerpo)
            copia = r.fecha
        }
    }

    private static func decodifica(_ d: Data) -> InformeCarrera? {
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try? dec.decode(InformeCarrera.self, from: d)
    }

    func carga() async {
        guard !cargando else { return }
        cargando = true
        defer { cargando = false }
        do {
            let (crudo, fecha) = try await API.leeOCopia("/api/carrera")
            guard let i = Self.decodifica(crudo) else {
                error = "No entiendo lo que devuelve el plan de carrera."
                return
            }
            withAnimation(Tema.Muelle.pantalla) { informe = i }
            copia = fecha
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// La pantalla (ruta /carrera.html): también se abre en una hoja desde Entreno.
struct PantallaCarrera: View {
    var enHoja = false
    @State private var datos = CarreraDatos.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Tema.Espacio.l) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Plan de 5k").estiloEtiqueta().foregroundStyle(Tema.suave)
                    Text("Carrera").font(Tema.fuente(.titulo)).foregroundStyle(Tema.texto)
                }
                .padding(.top, enHoja ? Tema.Espacio.l : Tema.Espacio.s)
                ContenidoCarrera()
            }
            .padding(.horizontal, Tema.Espacio.l)
            .padding(.bottom, enHoja ? Tema.Espacio.xl : 120)
        }
        .scrollIndicators(.hidden)
        .refreshable { await datos.carga() }
    }
}

struct ContenidoCarrera: View {
    @State private var datos = CarreraDatos.shared

    var body: some View {
        Group {
            if let copia = datos.copia {
                Label(API.notaCopia(copia), systemImage: "wifi.slash")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.aviso)
            }
            if let r = datos.informe {
                CartaEstimacion(r: r)
                CartaSemanaCarrera(r: r)
                CartaRitmos(r: r)
                CartaComoSeAjusta()
                GraficaCamino(r: r)
                GraficaMinutos(r: r)
                GraficaRitmo(r: r)
            } else {
                Text(datos.cargando ? "Cargando el plan…" : datos.error ?? "Sin datos del plan todavía. Tira hacia abajo para cargar.")
                    .font(Tema.fuente(.texto)).foregroundStyle(datos.error == nil ? Tema.suave : Tema.peligro)
                    .carta()
            }
        }
        .task { await datos.carga() }
    }
}

private func mmss(_ s: Double?) -> String {
    guard let s else { return "—" }
    return FormatoEnt.mmss(Int(s.rounded()))
}

private struct CartaEstimacion: View {
    let r: InformeCarrera

    var body: some View {
        let e = r.estimacion
        let obj = r.objetivo.seg
        let ini = r.historial.first?.seg ?? e.seg
        let p = ini > obj ? max(0, min(1, (ini - e.seg) / (ini - obj))) : 1
        let dias = FormatoEnt.dias(de: Fecha.hoy(), a: r.objetivo.dia)
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            Text("Tu 5k ahora").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            Text(mmss(e.seg))
                .font(Tema.fuente(.gigante)).monospacedDigit().foregroundStyle(e.seg <= obj ? Tema.acento : Tema.texto)
                .contentTransition(.numericText(value: e.seg))
            Text("Según \(e.fuente)" + (e.dia.map { " (\(FormatoEnt.corta($0)))" } ?? ""))
                .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            BarraEnt(valor: p).frame(height: 8)
                .accessibilityLabel("Llevas el \(Int(p * 100)) % del camino de \(mmss(ini)) a \(mmss(obj))")
            HStack(spacing: Tema.Espacio.s) {
                tres("Objetivo", mmss(obj))
                tres("Te faltan", e.seg > obj ? "\(Int((e.seg - obj).rounded())) s" : "¡nada!")
                tres("Quedan", dias > 13 ? "\(Int(ceil(Double(dias) / 7))) sem" : "\(max(0, dias)) días")
            }
            .padding(.top, Tema.Espacio.xs)
            if !r.proyeccion.texto.isEmpty {
                Text(r.proyeccion.texto).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto).padding(.top, Tema.Espacio.xs)
            }
        }
        .carta()
    }

    private func tres(_ t: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            Text(v).font(Tema.fuente(.destacado)).monospacedDigit().foregroundStyle(Tema.texto).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Tema.Espacio.s)
        .background(Tema.carta2, in: RoundedRectangle(cornerRadius: Tema.Radio.celda))
    }
}

private struct CartaSemanaCarrera: View {
    let r: InformeCarrera

    var body: some View {
        let w = r.semanas.segura(max(0, r.semana - 1))
        let hoy = Fecha.hoy()
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            HStack(spacing: Tema.Espacio.s) {
                Text(r.semana > 0 ? "Semana \(r.semana) de \(r.nSemanas) · \(w?.fase ?? "")"
                     : "Empieza el \(FormatoEnt.corta(r.inicio)) · \(w?.fase ?? "")")
                    .font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
                Spacer()
                if w?.descarga == true { ChipEnt(texto: "Descarga", color: Tema.aviso, fondo: Tema.carta2) }
                if w?.test == true { ChipEnt(texto: "Test") }
            }
            if r.agenda.isEmpty {
                Text("No hay días de carrera en el calendario estas dos semanas.")
                    .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            }
            ForEach(r.agenda, id: \.self) { a in
                HStack(spacing: Tema.Espacio.m) {
                    Text(FormatoEnt.diaSemana(a.dia)).font(Tema.fuente(.pequeno, peso: .semibold)).foregroundStyle(Tema.suave)
                        .frame(width: 52, alignment: .leading)
                    Circle().fill(InformeCarrera.color(a.tipo)).frame(width: 8, height: 8)
                    Text(a.n).font(Tema.fuente(.texto, peso: .medium))
                        .foregroundStyle(a.hecho ? Tema.suave : Tema.texto).strikethrough(a.hecho, color: Tema.tenue).lineLimit(1)
                    Spacer()
                    if a.hecho { ChipEnt(texto: "Hecho") } else if a.dia < hoy {
                        Text("Pendiente").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.aviso)
                    }
                }
                .padding(Tema.Espacio.s)
                .background(Tema.carta2, in: RoundedRectangle(cornerRadius: Tema.Radio.celda))
                .overlay(RoundedRectangle(cornerRadius: Tema.Radio.celda).strokeBorder(a.dia == hoy ? Tema.acento : .clear, lineWidth: 2))
            }
            ForEach(r.notas, id: \.self) { n in
                HStack(alignment: .firstTextBaseline, spacing: Tema.Espacio.s) {
                    Text("→").font(Tema.fuente(.texto, peso: .bold)).foregroundStyle(Tema.acento)
                    Text(n).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, Tema.Espacio.xs)
        }
        .carta()
    }
}

private struct CartaRitmos: View {
    let r: InformeCarrera

    var body: some View {
        let x = r.ritmos
        let filas: [(String, String, String)] = [
            ("Rodaje suave y largo", "conversación, sin sufrir", "\(mmss(x.suave.first))–\(mmss(x.suave.last))"),
            ("Tempo", "cómodamente duro", "\(mmss(x.tempo.first))–\(mmss(x.tempo.last))"),
            ("Series de 1000 m", "algo más rápido que tu 5k", mmss(x.series)),
            ("Objetivo", "\(mmss(r.objetivo.seg)) son \(mmss(x.objetivo)) cada km", mmss(x.objetivo)),
        ]
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            TituloEnt(titulo: "Tus ritmos") {
                Text("salen de tu 5k estimado").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            }
            ForEach(filas, id: \.0) { f in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(f.0).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                        Text(f.1).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                    }
                    Spacer()
                    Text(f.2 + " /km").font(Tema.fuente(.texto, peso: .semibold)).monospacedDigit().foregroundStyle(Tema.texto)
                }
                .padding(.vertical, 6)
                .overlay(alignment: .bottom) { Rectangle().fill(Tema.linea).frame(height: 0.5) }
            }
        }
        .carta()
    }
}

private struct CartaComoSeAjusta: View {
    @State private var abierto = false

    var body: some View {
        DisclosureGroup(isExpanded: $abierto) {
            VStack(alignment: .leading, spacing: Tema.Espacio.s) {
                Text("Cada madrugada (04:30) se recalcula todo con lo que has hecho de verdad: los días de carrera del calendario de todo, lo que marcas y lo que apuntas con el atajo o el bot.")
                Text("**Volumen.** Si haces todas las carreras de la semana, la siguiente sube un escalón. Si haces una de dos, se mantiene. Si no corres, baja un escalón. Cada tres subidas toca una semana de descarga para asimilar.")
                Text("**Ritmos.** Salen de tu 5k estimado. Los tests (semanas 2, 8 y 14) lo fijan; una carrera normal solo puede bajarlo, nunca subirlo (con la fórmula de Riegel).")
                Text("**Fases.** Base hasta finales de enero: rodaje suave y rodaje largo, compatible con perder grasa. Febrero: series y tempo. La primera semana de marzo, afinar a ritmo de carrera, y la carrera el domingo 14 de marzo (ese día se añade solo al calendario).")
                Text("**Tu semana manda.** El plan solo decide qué sesión toca en tus días de carrera. Si mueves un día en todo o con el bot, la sesión se va con él.")
            }
            .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            .padding(.top, Tema.Espacio.s)
        } label: {
            Text("Cómo se ajusta el plan").font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
        }
        .tint(Tema.suave)
        .carta()
    }
}

/// Una leyenda: muestra de color y texto.
private struct Leyenda: View {
    let items: [(String, Color, Bool)]   // texto, color, discontinua

    var body: some View {
        FlujoEnt(espacio: 12) {
            ForEach(items, id: \.0) { x in
                HStack(spacing: 6) {
                    Rectangle().fill(x.1).frame(width: 14, height: x.2 ? 1.5 : 3).opacity(x.2 ? 0.7 : 1)
                    Text(x.0).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                }
            }
        }
    }
}

private struct VerDatos: View {
    let cabecera: [String]
    let filas: [[String]]
    @State private var abierto = false

    var body: some View {
        DisclosureGroup(isExpanded: $abierto) {
            VStack(spacing: 0) {
                filaTabla(cabecera, cabecera: true)
                ForEach(Array(filas.enumerated()), id: \.offset) { _, f in filaTabla(f) }
            }
        } label: {
            Text("Ver los datos").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
        }
        .tint(Tema.suave)
    }
}

private struct GraficaCamino: View {
    let r: InformeCarrera

    var body: some View {
        let ws = r.semanas
        let actual = max(0, r.semana - 1)
        let proy: [(Int, Double)] = {
            guard let p = r.proyeccion.seg, ws.count > actual + 1 else { return [] }
            let tramos = Double(max(1, ws.count - 1 - actual))
            return (actual..<ws.count).map { i in (ws[i].n, r.estimacion.seg + (p - r.estimacion.seg) * Double(i - actual) / tramos) }
        }()
        let valores = ws.flatMap { [$0.est, $0.camino].compactMap { $0 } } + proy.map(\.1)
        let lo = floor(((valores.min() ?? 1300) - 20) / 60) * 60
        let hi = ceil(((valores.max() ?? 1500) + 20) / 60) * 60
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            TituloEnt(titulo: "Camino a \(mmss(r.objetivo.seg))") {
                Text("más abajo, más rápido").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            }
            Leyenda(items: [("Tu estimación", Tema.acento, false), ("Camino", Tema.suave, true)]
                    + (proy.isEmpty ? [] : [("Proyección", Tema.acento, true)]))
            Chart {
                ForEach(ws) { w in
                    if let c = w.camino {
                        LineMark(x: .value("Semana", w.n), y: .value("Seg", c), series: .value("Serie", "camino"))
                            .foregroundStyle(Tema.suave)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    }
                }
                ForEach(ws) { w in
                    if let est = w.est {
                        LineMark(x: .value("Semana", w.n), y: .value("Seg", est), series: .value("Serie", "est"))
                            .foregroundStyle(Tema.acento)
                            .interpolationMethod(.stepEnd)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        if w.test {
                            PointMark(x: .value("Semana", w.n), y: .value("Seg", est)).foregroundStyle(Tema.acento)
                        }
                    }
                }
                ForEach(proy, id: \.0) { p in
                    LineMark(x: .value("Semana", p.0), y: .value("Seg", p.1), series: .value("Serie", "proy"))
                        .foregroundStyle(Tema.acento)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [2, 4]))
                }
            }
            .chartYScale(domain: lo...max(hi, lo + 60))
            .chartYAxis {
                AxisMarks(position: .leading, values: .stride(by: 60)) { v in
                    AxisGridLine().foregroundStyle(Tema.linea)
                    AxisValueLabel { if let s = v.as(Double.self) { Text(mmss(s)).font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.tenue) } }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { v in
                    AxisValueLabel { if let n = v.as(Int.self) { Text("S\(n)").font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.tenue) } }
                }
            }
            .frame(height: 220)
            .accessibilityLabel("Estimación del 5k por semana frente al camino al objetivo")
            VerDatos(cabecera: ["Semana", "Hasta", "Estimación", "Camino"],
                     filas: ws.map { ["\($0.n)", FormatoEnt.corta(FormatoEnt.mas($0.lunes, 6)), mmss($0.est), mmss($0.camino)] })
        }
        .carta()
    }
}

private struct GraficaMinutos: View {
    let r: InformeCarrera

    var body: some View {
        let ws = r.semanas
        let actual = max(0, r.semana - 1)
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            TituloEnt("Minutos por semana")
            Leyenda(items: [("Planificado", Tema.tenue, false), ("Hecho", Tema.acento, false)])
            Chart {
                ForEach(Array(ws.enumerated()), id: \.offset) { i, w in
                    BarMark(x: .value("Semana", "S\(w.n)"), y: .value("Min", w.planMin), width: .ratio(0.9))
                        .foregroundStyle(i == actual ? Tema.acento.opacity(0.27) : Tema.tenue.opacity(w.estado == "futura" ? 0.2 : 0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    if w.estado != "futura" {
                        BarMark(x: .value("Semana", "S\(w.n)"), y: .value("Min", w.hechoMin), width: .ratio(0.5))
                            .foregroundStyle(Tema.acento)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                    AxisGridLine().foregroundStyle(Tema.linea)
                    AxisValueLabel { if let m = v.as(Double.self) { Text("\(Int(m))′").font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.tenue) } }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisValueLabel().font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.tenue)
                }
            }
            .frame(height: 220)
            .accessibilityLabel("Minutos de carrera planificados y hechos por semana")
            VerDatos(cabecera: ["Semana", "Fase", "Plan", "Hecho", "Km"],
                     filas: ws.map { w in
                         ["\(w.n) (\(FormatoEnt.corta(w.lunes)))", w.fase + (w.descarga ? " · descarga" : ""), "\(Int(w.planMin)) min",
                          w.estado == "futura" ? "—" : "\(Int(w.hechoMin)) min",
                          w.estado == "futura" ? "—" : FormatoEnt.num(w.hechoKm)]
                     })
        }
        .carta()
    }
}

private struct GraficaRitmo: View {
    let r: InformeCarrera

    var body: some View {
        let cs = r.carreras.filter { $0.ritmo != nil }
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            TituloEnt("Ritmo de cada carrera")
            if cs.isEmpty {
                Text("Cuando apuntes carreras con distancia y tiempo (atajo o bot: «he corrido 6 km en 36 min») verás aquí si vas a tus ritmos.")
                    .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            } else {
                let tipos = InformeCarrera.tipos.filter { t in cs.contains { $0.tipo == t.0 } }
                Leyenda(items: tipos.map { ($0.1, InformeCarrera.color($0.0), false) }
                        + [("Banda suave", Tema.suave, true), ("Ritmo objetivo", Tema.suave, true)])
                Chart {
                    ForEach(cs) { c in
                        PointMark(x: .value("Día", FormatoEnt.fecha(c.dia)), y: .value("Ritmo", c.ritmo ?? 0))
                            .foregroundStyle(InformeCarrera.color(c.tipo))
                            .symbolSize(70)
                    }
                    if let a = r.ritmos.suave.first {
                        RuleMark(y: .value("Suave", a)).foregroundStyle(Tema.suave).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    if let b = r.ritmos.suave.last {
                        RuleMark(y: .value("Suave", b)).foregroundStyle(Tema.suave).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    RuleMark(y: .value("Objetivo", r.ritmos.objetivo)).foregroundStyle(Tema.suave)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
                // arriba lo rápido
                .chartYScale(domain: .automatic(includesZero: false, reversed: true))
                .chartYAxis {
                    AxisMarks(position: .leading, values: .stride(by: 30)) { v in
                        AxisGridLine().foregroundStyle(Tema.linea)
                        AxisValueLabel { if let s = v.as(Double.self) { Text(mmss(s)).font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.tenue) } }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { v in
                        AxisValueLabel { if let d = v.as(Date.self) { Text(FormatoEnt.corta(Fecha.dia(d))).font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.tenue) } }
                    }
                }
                .frame(height: 220)
                .accessibilityLabel("Ritmo por kilómetro de cada carrera")
                VerDatos(cabecera: ["Día", "Tipo", "Km", "Tiempo", "Ritmo"],
                         filas: cs.reversed().map { c in
                             [FormatoEnt.corta(c.dia), InformeCarrera.nombre(c.tipo), FormatoEnt.num(c.km), mmss(c.seg), mmss(c.ritmo) + " /km"]
                         })
            }
        }
        .carta()
    }
}
