import SwiftUI
import Charts

// Las gráficas de Salud con Swift Charts. Ejes y rejilla con los colores del tema; las fases del sueño llevan los
// suyos (los de la web), para que profundo, básico, REM y despierto signifiquen lo mismo en todas partes.

// MARK: ejes

/// Las marcas del eje vertical: rejilla del tema y la etiqueta que diga `formato`.
private func marcasY(_ valores: AxisMarkValues = .automatic(desiredCount: 4),
                     formato: @escaping (Double) -> String) -> some AxisContent {
    AxisMarks(position: .leading, values: valores) { v in
        AxisGridLine().foregroundStyle(Tema.linea)
        AxisValueLabel {
            if let x = v.as(Double.self) {
                Text(formato(x)).font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.tenue)
            }
        }
    }
}

/// Un día de cada tantos, según cuántos se enseñen (la semana, con la inicial del día).
private func marcasDias(_ n: Int) -> some AxisContent {
    AxisMarks(values: .stride(by: .day, count: n <= 7 ? 1 : n <= 14 ? 2 : 5)) { v in
        AxisValueLabel {
            if let d = v.as(Date.self) {
                Text(FechasES.texto(d, n <= 7 ? "EEEEE" : "d MMM")).font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.tenue)
            }
        }
    }
}

private func nocheCercana(_ sel: Date?, _ noches: [NocheSueno]) -> NocheSueno? {
    guard let sel else { return nil }
    return noches.first { Calendar.current.isDate($0.fecha, inSameDayAs: sel) }
}

private struct Leyenda: View {
    let items: [(String, Color)]

    var body: some View {
        HStack(spacing: Tema.Espacio.m) {
            ForEach(items.indices, id: \.self) { i in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3).fill(items[i].1).frame(width: 12, height: 10)
                    Text(items[i].0).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// La línea de abajo de cada gráfica: lo que hay bajo el dedo, o una pista.
private struct Lectura: View {
    let texto: String

    var body: some View {
        Text(texto)
            .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentTransition(.interpolate)
            .animation(Tema.Muelle.toque, value: texto)
    }
}

// MARK: la noche, hora a hora

private struct TramoFase: Identifiable {
    let id: Date
    let fase: FaseSueno
    let inicio: Date
    let fin: Date
    let minutos: Double
}

struct CartaNoche: View {
    let dia: String
    let tramos: [TramoSueno]
    @State private var sel: Date?

    private var validos: [TramoFase] {
        tramos.compactMap { t in
            FaseSueno(rawValue: t.fase).map { TramoFase(id: t.inicio, fase: $0, inicio: t.inicio, fin: t.fin, minutos: t.minutos) }
        }
    }

    private var rango: ClosedRange<Date> {
        let cal = Calendar.current
        let ini = validos.map(\.inicio).min() ?? Date()
        let fin = validos.map(\.fin).max() ?? ini.addingTimeInterval(3600)
        let a = cal.dateInterval(of: .hour, for: ini)?.start ?? ini
        let b = cal.dateInterval(of: .hour, for: fin)?.end ?? fin
        return a...max(b, a.addingTimeInterval(3600))
    }

    private func hora(_ d: Date) -> String { FechasES.texto(d, "HH:mm") }

    var body: some View {
        let datos = validos
        let nombres = FaseSueno.deArribaAbajo.map(\.nombre)
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            TituloCarta(titulo: "La noche", detalle: FechasES.corta(dia))
            Leyenda(items: FaseSueno.deArribaAbajo.map { ($0.nombre, $0.color) })
            Chart(datos) { t in
                RectangleMark(xStart: .value("Desde", t.inicio), xEnd: .value("Hasta", t.fin),
                              y: .value("Fase", t.fase.nombre), height: .ratio(0.8))
                    .foregroundStyle(by: .value("Fase", t.fase.nombre))
                    .cornerRadius(3)
            }
            .chartForegroundStyleScale(domain: nombres, range: FaseSueno.deArribaAbajo.map(\.color))
            .chartLegend(.hidden)
            .chartYScale(domain: nombres)
            .chartXScale(domain: rango)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 2)) { v in
                    AxisGridLine().foregroundStyle(Tema.linea)
                    AxisValueLabel {
                        if let d = v.as(Date.self) {
                            Text(FechasES.texto(d, "HH")).font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.tenue)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { v in
                    AxisValueLabel {
                        if let s = v.as(String.self) {
                            Text(s).font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.suave)
                        }
                    }
                }
            }
            .chartXSelection(value: $sel)
            .frame(height: 190)
            .accessibilityLabel("Fases de la última noche, hora a hora")
            if let s = sel, let t = datos.first(where: { s >= $0.inicio && s < $0.fin }) {
                Lectura(texto: "\(t.fase.nombre) · \(hora(t.inicio))–\(hora(t.fin)) · \(Int(t.minutos.rounded())) min")
            } else {
                Lectura(texto: "Toca la gráfica para ver cada tramo.")
            }
        }
        .carta()
    }
}

// MARK: fases por noche

private struct FilaFase: Identifiable {
    let id: String
    let fecha: Date
    let fase: FaseSueno
    let minutos: Double
}

struct CartaFases: View {
    let noches: [NocheSueno]
    let periodo: PeriodoSalud
    @State private var sel: Date?

    private var filas: [FilaFase] {
        noches.flatMap { n -> [FilaFase] in
            guard let f = n.fases else { return [] }
            return FaseSueno.apilado.map { FilaFase(id: "\(n.dia)-\($0.rawValue)", fecha: n.fecha, fase: $0, minutos: f[$0.rawValue] ?? 0) }
        }
    }

    private func lectura() -> String {
        guard let n = nocheCercana(sel, noches) else { return "Toca una barra para ver la noche." }
        var t = FechasES.corta(n.dia)
        if let nota = n.nota { t += " · puntuación \(nota.total)" }
        if let s = n.sueno, s > 0 { t += " · dormido \(FechasES.hm(s))" }
        if let f = n.fases {
            t += " · " + FaseSueno.apilado.reversed().map { "\($0.nombre) \(FechasES.hm(f[$0.rawValue] ?? 0))" }.joined(separator: ", ")
        }
        return t
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            TituloCarta(titulo: "Fases por noche", detalle: "últimas \(periodo.noches) noches")
            if filas.isEmpty {
                Text("Sin fases todavía en este periodo.").font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            } else {
                Leyenda(items: FaseSueno.apilado.reversed().map { ($0.nombre, $0.color) })
                let elegida = nocheCercana(sel, noches)?.dia
                Chart(filas) { f in
                    BarMark(x: .value("Noche", f.fecha, unit: .day), y: .value("Minutos", f.minutos))
                        .foregroundStyle(by: .value("Fase", f.fase.nombre))
                        .opacity(elegida == nil || f.id.hasPrefix(elegida ?? "") ? 1 : 0.45)
                }
                .chartForegroundStyleScale(domain: FaseSueno.apilado.map(\.nombre), range: FaseSueno.apilado.map(\.color))
                .chartLegend(.hidden)
                .chartXAxis { marcasDias(periodo.noches) }
                .chartYAxis { marcasY(.stride(by: 120.0)) { "\(Int($0 / 60)) h" } }
                .chartXSelection(value: $sel)
                .frame(height: 220)
                .accessibilityLabel("Minutos de cada fase del sueño por noche")
                Lectura(texto: lectura())
            }
        }
        .carta()
    }
}

// MARK: puntuación

private struct PuntoNota: Identifiable {
    let id: String
    let fecha: Date
    let total: Int
}

struct CartaPuntuacion: View {
    let noches: [NocheSueno]
    let periodo: PeriodoSalud
    @State private var sel: Date?

    private var puntos: [PuntoNota] {
        noches.compactMap { n in n.nota.map { PuntoNota(id: n.dia, fecha: n.fecha, total: $0.total) } }
    }

    private func lectura() -> String {
        guard let n = nocheCercana(sel, noches) else { return "Toca la gráfica para ver cada noche." }
        guard let x = n.nota else { return "\(FechasES.corta(n.dia)) · sin puntuación" }
        return "\(FechasES.corta(n.dia)) · \(x.total), \(x.nivel.lowercased()) · duración \(x.duracion)/50, hora \(x.hora)/30, interrupciones \(x.interrupciones)/20"
    }

    var body: some View {
        let p = puntos
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            TituloCarta(titulo: "Puntuación", detalle: "últimas \(periodo.noches) noches")
            if p.count < 2 {
                Text("Hace falta más de una noche con puntuación para dibujarla.")
                    .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            } else {
                Chart {
                    ForEach(p) { x in
                        AreaMark(x: .value("Noche", x.fecha, unit: .day), y: .value("Puntuación", x.total))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(LinearGradient(colors: [Tema.acento.opacity(0.28), Tema.acento.opacity(0)],
                                                            startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Noche", x.fecha, unit: .day), y: .value("Puntuación", x.total))
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                            .foregroundStyle(Tema.acento)
                        PointMark(x: .value("Noche", x.fecha, unit: .day), y: .value("Puntuación", x.total))
                            .symbolSize(36)
                            .foregroundStyle(Tema.acento)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXAxis { marcasDias(periodo.noches) }
                .chartYAxis { marcasY(.stride(by: 25.0)) { "\(Int($0))" } }
                .chartXSelection(value: $sel)
                .frame(height: 190)
                .accessibilityLabel("Puntuación del sueño por noche")
                Lectura(texto: lectura())
            }
        }
        .carta()
    }
}

// MARK: peso

private struct CambioCifra {
    /// Bajar es lo bueno en peso, grasa e IMC; en masa magra, subir.
    static func texto(_ x: Double, unidad: String, decimales: Int = 1) -> String {
        if abs(x) < 0.05 { return "sin cambios" }
        return (x > 0 ? "+" : "−") + FechasES.coma(abs(x), decimales) + unidad
    }

    static func color(_ x: Double, bajaEsBueno: Bool) -> Color {
        if abs(x) < 0.05 { return Tema.suave }
        return (x < 0) == bajaEsBueno ? Tema.acento : Tema.peligro
    }
}

struct CartaPeso: View {
    let datos: DatosSalud
    let periodo: PeriodoSalud
    @State private var sel: Date?

    var body: some View {
        let puntos = datos.pesos(periodo)
        let ultimo = datos.informe?.cuerpo.peso.last
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            Text("Peso").estiloEtiqueta().foregroundStyle(Tema.suave)
            if let u = ultimo {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(FechasES.coma(u.kg)).font(Tema.fuente(.gigante)).foregroundStyle(Tema.texto)
                        .monospacedDigit().contentTransition(.numericText())
                    Text("kg").font(Tema.fuente(.destacado)).foregroundStyle(Tema.suave)
                }
                Text(subtitulo(u.dia)).font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                if let c = datos.cambioPeso30 {
                    Text("\(CambioCifra.texto(c, unidad: " kg")) en 30 días")
                        .font(Tema.fuente(.pequeno, peso: .medium)).foregroundStyle(CambioCifra.color(c, bajaEsBueno: true))
                }
            } else {
                Text("—").font(Tema.fuente(.gigante)).foregroundStyle(Tema.tenue)
                Text("Sin pesajes. Llegan con Salud (la báscula los deja allí).")
                    .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            }
            if puntos.count > 1 { grafica(puntos) }
        }
        .carta()
    }

    private func subtitulo(_ dia: String) -> String {
        let media = datos.pesos(.trimestre).last?.media
        return FechasES.corta(dia) + (media.map { " · media 7 días \(FechasES.coma($0)) kg" } ?? "")
    }

    private func grafica(_ puntos: [PuntoPeso]) -> some View {
        let valores = puntos.flatMap { [$0.kg, $0.media ?? $0.kg] }
        let lo = (valores.min() ?? 0).rounded(.down) - 0.5
        let hi = (valores.max() ?? 1).rounded(.up) + 0.5
        let conMedia = puntos.filter { $0.media != nil }
        return VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            Chart {
                ForEach(conMedia) { p in
                    LineMark(x: .value("Día", p.fecha, unit: .day), y: .value("Media 7 días", p.media ?? p.kg))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .foregroundStyle(Tema.acento)
                }
                ForEach(puntos) { p in
                    PointMark(x: .value("Día", p.fecha, unit: .day), y: .value("Pesaje", p.kg))
                        .symbolSize(26)
                        .foregroundStyle(Tema.suave)
                }
                if let s = sel, let p = puntos.min(by: { abs($0.fecha.timeIntervalSince(s)) < abs($1.fecha.timeIntervalSince(s)) }) {
                    RuleMark(x: .value("Día", p.fecha, unit: .day))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(Tema.tenue)
                }
            }
            .chartYScale(domain: lo...hi)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { v in
                    AxisValueLabel {
                        if let d = v.as(Date.self) {
                            Text(FechasES.texto(d, "d MMM")).font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.tenue)
                        }
                    }
                }
            }
            .chartYAxis { marcasY { FechasES.coma($0, $0 == $0.rounded() ? 0 : 1) } }
            .chartXSelection(value: $sel)
            .frame(height: 190)
            .accessibilityLabel("Peso por día y su media de 7 días")
            if let s = sel, let p = puntos.min(by: { abs($0.fecha.timeIntervalSince(s)) < abs($1.fecha.timeIntervalSince(s)) }) {
                Lectura(texto: "\(FechasES.corta(p.dia)) · \(FechasES.coma(p.kg)) kg" + (p.media.map { " · media \(FechasES.coma($0)) kg" } ?? ""))
            } else {
                Leyenda(items: [("Media 7 días", Tema.acento), ("Pesaje", Tema.suave)])
            }
        }
    }
}

// MARK: composición

struct CartaComposicion: View {
    let datos: DatosSalud
    let periodo: PeriodoSalud

    private struct Ficha: Identifiable {
        let id: String
        let nombre: String
        let valor: KeyPath<CompCuerpo, Double?>
        let unidad: String
        let bajaEsBueno: Bool
    }

    private let fichas = [
        Ficha(id: "grasa", nombre: "Grasa", valor: \.grasa, unidad: " %", bajaEsBueno: true),
        Ficha(id: "magra", nombre: "Masa magra", valor: \.magra, unidad: " kg", bajaEsBueno: false),
        Ficha(id: "imc", nombre: "IMC", valor: \.imc, unidad: "", bajaEsBueno: true),
    ]

    var body: some View {
        let filas = datos.informe?.cuerpo.comp ?? []
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            TituloCarta(titulo: "Composición", detalle: filas.last.map { FechasES.corta($0.dia) })
            if filas.isEmpty {
                Text("Grasa, masa magra e IMC: llegan con Salud cuando la app de la báscula los escribe allí.")
                    .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            } else {
                HStack(spacing: Tema.Espacio.s) {
                    ForEach(fichas) { f in ficha(f) }
                }
                grasa(datos.comp(periodo).filter { $0.grasa != nil })
            }
        }
        .carta()
    }

    private func ficha(_ f: Ficha) -> some View {
        let u = datos.ultimaComp(f.valor)
        return VStack(alignment: .leading, spacing: 2) {
            Text(f.nombre).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).lineLimit(1)
            Text(u.map { FechasES.coma($0.actual) + f.unidad } ?? "—")
                .font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            if let c = u?.cambio {
                Text(CambioCifra.texto(c, unidad: f.unidad))
                    .font(Tema.fuente(.pequeno)).foregroundStyle(CambioCifra.color(c, bajaEsBueno: f.bajaEsBueno))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .padding(Tema.Espacio.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.carta2, in: RoundedRectangle(cornerRadius: Tema.Radio.boton, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func grasa(_ g: [CompCuerpo]) -> some View {
        if g.count > 1 {
            VStack(alignment: .leading, spacing: Tema.Espacio.s) {
                Text("Grasa por pesaje").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                Chart(g, id: \.dia) { f in
                    LineMark(x: .value("Día", FechasES.fecha(f.dia) ?? Date(), unit: .day), y: .value("Grasa", f.grasa ?? 0))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .foregroundStyle(Tema.acento)
                    PointMark(x: .value("Día", FechasES.fecha(f.dia) ?? Date(), unit: .day), y: .value("Grasa", f.grasa ?? 0))
                        .symbolSize(24)
                        .foregroundStyle(Tema.acento)
                }
                .chartYScale(domain: ((g.compactMap(\.grasa).min() ?? 0).rounded(.down) - 1)...((g.compactMap(\.grasa).max() ?? 1).rounded(.up) + 1))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { v in
                        AxisValueLabel {
                            if let d = v.as(Date.self) {
                                Text(FechasES.texto(d, "d MMM")).font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.tenue)
                            }
                        }
                    }
                }
                .chartYAxis { marcasY { "\(Int($0)) %" } }
                .frame(height: 150)
                .accessibilityLabel("Porcentaje de grasa por pesaje")
            }
        }
    }
}

// MARK: pasos

struct CartaPasos: View {
    let noches: [NocheSueno]
    let periodo: PeriodoSalud
    @State private var sel: Date?

    var body: some View {
        let con = noches.filter { ($0.pasos ?? 0) > 0 }
        let media = con.isEmpty ? nil : con.reduce(0.0) { $0 + ($1.pasos ?? 0) } / Double(con.count)
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            TituloCarta(titulo: "Pasos", detalle: media.map { "media \(FechasES.miles($0))" })
            if con.isEmpty {
                Text("Sin pasos todavía en este periodo.").font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            } else {
                let elegida = nocheCercana(sel, con)?.dia
                Chart {
                    ForEach(con) { n in
                        BarMark(x: .value("Día", n.fecha, unit: .day), y: .value("Pasos", n.pasos ?? 0))
                            .cornerRadius(4)
                            .foregroundStyle(Tema.acento)
                            .opacity(elegida == nil || elegida == n.dia ? 1 : 0.45)
                    }
                    if let media {
                        RuleMark(y: .value("Media", media))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(Tema.suave)
                    }
                }
                .chartXAxis { marcasDias(periodo.noches) }
                .chartYAxis { marcasY { $0 >= 1000 ? "\(Int($0 / 1000)) k" : "\(Int($0))" } }
                .chartXSelection(value: $sel)
                .frame(height: 190)
                .accessibilityLabel("Pasos por día")
                if let n = nocheCercana(sel, con), let p = n.pasos {
                    Lectura(texto: "\(FechasES.corta(n.dia)) · \(FechasES.miles(p)) pasos")
                } else {
                    Lectura(texto: "Toca una barra para ver el día. La línea es la media.")
                }
            }
        }
        .carta()
    }
}
