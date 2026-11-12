import SwiftUI
import Charts

/// Las gráficas de Gastos (Swift Charts): en qué se va el ciclo, el ritmo contra el presupuesto y los últimos ciclos.
/// Los colores salen de Tema (acento, suave, aviso…) y, en el reparto, de la paleta de categorías. Cada gráfica trae
/// su tabla en «Ver los datos» (también es lo que lee VoiceOver).
struct GraficasGastos: View {
    let r: ResumenGastos

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.l) {
            if r.cats.contains(where: { $0.gastado > 0 }) { RepartoGastos(r: r) }
            if !r.serie.isEmpty { RitmoGastos(r: r) }
            if r.historico.contains(where: { $0.total > 0 }) { HistoricoGastos(r: r) }
        }
    }
}

// MARK: en qué se va

private struct RepartoGastos: View {
    let r: ResumenGastos
    @State private var datos = DatosGastos.shared

    private struct Parte: Identifiable {
        var id: String
        var nombre: String
        var valor: Double
        var color: Color
    }

    private var partes: [Parte] {
        r.cats.filter { $0.gastado > 0 }.sorted { $0.gastado > $1.gastado }
            .map { Parte(id: $0.id, nombre: $0.n, valor: $0.gastado, color: datos.color($0.id)) }
    }

    var body: some View {
        let p = partes
        let suma = p.reduce(0) { $0 + $1.valor }
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            Text("En qué se va").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
            Chart(p) { x in
                SectorMark(angle: .value("Gastado", x.valor), innerRadius: .ratio(0.64), angularInset: 1.5)
                    .cornerRadius(4)
                    .foregroundStyle(x.color)
            }
            .frame(height: 190)
            .chartBackground { _ in
                VStack(spacing: 2) {
                    Text("Categorías").estiloEtiqueta().foregroundStyle(Tema.suave)
                    Text(Eur.entero(suma)).font(Tema.fuente(.seccion)).monospacedDigit().foregroundStyle(Tema.texto)
                }
            }
            .accessibilityHidden(true)
            ForEach(p) { x in
                HStack(spacing: Tema.Espacio.s) {
                    Circle().fill(x.color).frame(width: 8, height: 8)
                    Text(x.nombre).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.texto)
                    Spacer()
                    Text(Eur.texto(x.valor)).font(Tema.fuente(.pequeno)).monospacedDigit().foregroundStyle(Tema.texto)
                    Text("\(Int((x.valor / max(suma, 1) * 100).rounded())) %")
                        .font(Tema.fuente(.pequeno)).monospacedDigit().foregroundStyle(Tema.suave)
                        .frame(width: 46, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .carta()
    }
}

// MARK: ritmo del ciclo

private struct RitmoGastos: View {
    let r: ResumenGastos
    @State private var verDatos = false

    private static let este = "Este ciclo"
    private static let anterior = "Ciclo anterior"
    private static let ritmo = "Ritmo del presupuesto"
    private static let proyeccion = "Proyección"

    private struct Punto: Identifiable {
        let id = UUID()
        var serie: String
        var dia: Int
        var valor: Double
    }

    private var puntos: [Punto] {
        var l: [Punto] = []
        for (i, v) in r.serie.enumerated() { l.append(Punto(serie: Self.este, dia: i + 1, valor: v)) }
        for (i, v) in r.seriePrevia.enumerated() { l.append(Punto(serie: Self.anterior, dia: i + 1, valor: v)) }
        if r.presu > 0 {
            l.append(Punto(serie: Self.ritmo, dia: 1, valor: r.presu / Double(r.dias)))
            l.append(Punto(serie: Self.ritmo, dia: r.dias, valor: r.presu))
        }
        if r.actual, let ultimo = r.serie.last, r.hechos > 0, r.hechos < r.dias {
            l.append(Punto(serie: Self.proyeccion, dia: r.hechos, valor: ultimo))
            l.append(Punto(serie: Self.proyeccion, dia: r.dias, valor: r.proyeccion))
        }
        return l
    }

    private struct Serie: Identifiable {
        var id: String { nombre }
        var nombre: String
        var color: Color
        var rayas: Bool
    }

    private var series: [Serie] {
        [Serie(nombre: Self.este, color: Tema.acento, rayas: false), Serie(nombre: Self.anterior, color: Tema.tenue, rayas: false),
         Serie(nombre: Self.ritmo, color: Tema.suave, rayas: true), Serie(nombre: Self.proyeccion, color: Tema.aviso, rayas: true)]
    }

    var body: some View {
        let l = puntos
        let presentes = series.filter { s in l.contains { $0.serie == s.nombre } }
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            Text("Ritmo del ciclo").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
            HStack(spacing: Tema.Espacio.m) {
                ForEach(presentes) { s in
                    HStack(spacing: 5) {
                        Capsule().fill(s.color).frame(width: 14, height: s.rayas ? 2 : 3)
                        Text(s.nombre).font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.suave)
                    }
                }
            }
            Chart(l) { p in
                LineMark(x: .value("Día", p.dia), y: .value("Gastado", p.valor), series: .value("Serie", p.serie))
                    .foregroundStyle(by: .value("Serie", p.serie))
                    .lineStyle(StrokeStyle(lineWidth: p.serie == Self.este ? 2.5 : 1.5,
                                           lineCap: .round,
                                           dash: (p.serie == Self.ritmo || p.serie == Self.proyeccion) ? [4, 3] : []))
                    .interpolationMethod(.monotone)
            }
            .chartForegroundStyleScale(domain: series.map { $0.nombre }, range: series.map { $0.color })
            .chartLegend(.hidden)
            .chartXScale(domain: 1...max(r.dias, 2))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisValueLabel().foregroundStyle(Tema.suave)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                    AxisGridLine().foregroundStyle(Tema.linea)
                    AxisValueLabel {
                        if let d = v.as(Double.self) { Text("\(Int(d))").foregroundStyle(Tema.suave) }
                    }
                }
            }
            .frame(height: 190)
            .accessibilityHidden(true)
            DisclosureGroup("Ver los datos", isExpanded: $verDatos) {
                VStack(spacing: 6) {
                    fila("Gastado hasta hoy", Eur.texto(r.total))
                    if r.presu > 0 { fila("Presupuesto", Eur.texto(r.presu)) }
                    if r.actual { fila("Proyección al cierre", Eur.texto(r.proyeccion)) }
                    if let previo = r.seriePrevia.last { fila("Ciclo anterior (completo)", Eur.texto(previo)) }
                }
                .padding(.top, Tema.Espacio.s)
            }
            .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            .tint(Tema.acento)
        }
        .carta()
    }

    private func fila(_ t: String, _ v: String) -> some View {
        HStack {
            Text(t).foregroundStyle(Tema.suave)
            Spacer()
            Text(v).monospacedDigit().foregroundStyle(Tema.texto)
        }
        .font(Tema.fuente(.pequeno))
    }
}

// MARK: últimos ciclos

private struct HistoricoGastos: View {
    let r: ResumenGastos
    @State private var verDatos = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            Text("Últimos ciclos").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
            Chart(r.historico, id: \.inicio) { c in
                BarMark(x: .value("Ciclo", c.inicio), y: .value("Total", c.total))
                    .foregroundStyle(c.inicio == r.inicio ? Tema.acento : Tema.tenue)
                    .cornerRadius(5)
                    .annotation(position: .top, spacing: 3) {
                        Text(Eur.entero(c.total))
                            .font(Tema.fuente(.etiqueta)).monospacedDigit()
                            .foregroundStyle(c.inicio == r.inicio ? Tema.texto : Tema.suave)
                    }
                if r.presu > 0 {
                    RuleMark(y: .value("Presupuesto", r.presu))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(Tema.suave.opacity(0.7))
                }
            }
            .chartXAxis {
                AxisMarks { v in
                    AxisValueLabel {
                        if let s = v.as(String.self) { Text(FechaGasto.corta(s)).foregroundStyle(Tema.suave) }
                    }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 190)
            .accessibilityHidden(true)
            DisclosureGroup("Ver los datos", isExpanded: $verDatos) {
                VStack(spacing: 6) {
                    ForEach(r.historico, id: \.inicio) { c in
                        HStack {
                            Text("\(FechaGasto.corta(c.inicio)) – \(FechaGasto.corta(c.fin))").foregroundStyle(Tema.suave)
                            Spacer()
                            Text(Eur.texto(c.total)).monospacedDigit().foregroundStyle(Tema.texto)
                        }
                        .font(Tema.fuente(.pequeno))
                    }
                }
                .padding(.top, Tema.Espacio.s)
            }
            .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            .tint(Tema.acento)
        }
        .carta()
    }
}
