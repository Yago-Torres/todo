import SwiftUI
import Charts

/// La pestaña Review: la del domingo (y las anteriores) leída en nativo. El Markdown de la review se parte en bloques
/// (encabezados, párrafos, listas, tablas y los ```grafica de la app) y cada uno se pinta con el tema; las tablas se
/// desplazan de lado antes que partir palabras.
struct ReviewInversiones: View {
    let inf: InformeInv
    @State private var datos = DatosInversiones.shared
    @State private var fecha = ""
    @State private var texto: String?
    @State private var cargando = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.l) {
            if inf.reviews.isEmpty {
                VStack(alignment: .leading, spacing: Tema.Espacio.m) {
                    Text("Review semanal").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
                    Text("Cada domingo a las 10:00 Claude analiza tu cartera: qué sobra, qué falta, riesgos, proyecciones y un plan de acción, comparando con las semanas anteriores. Te llega el resumen por Telegram y aquí la tienes entera.")
                        .font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(inf.abiertas.isEmpty ? "Apunta antes tus posiciones y rellena el Perfil."
                                              : "La primera llega el domingo. Rellena antes tu Perfil: con más contexto acierta más.")
                        .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .carta()
            } else {
                SelectorPildoras(opciones: inf.reviews.prefix(12).map { (valor: $0, titulo: FechasES.corta($0)) }, seleccion: $fecha)
                    .padding(.horizontal, -Tema.Espacio.l)
                Group {
                    if let texto {
                        MarkdownInv(texto: texto)
                    } else {
                        Text(cargando ? "Cargando…" : "No se ha podido cargar esta review.")
                            .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .carta()
            }
        }
        .onAppear(perform: eligeFecha)
        .onChange(of: inf.reviews) { _, _ in eligeFecha() }
        .onChange(of: datos.reviewElegida) { _, _ in eligeFecha() }
        .task(id: fecha) {
            guard !fecha.isEmpty else { return }
            cargando = true
            texto = await datos.review(fecha)
            cargando = false
        }
    }

    private func eligeFecha() {
        if let pedida = datos.reviewElegida, inf.reviews.contains(pedida) {
            fecha = pedida
            datos.reviewElegida = nil
        } else if !inf.reviews.contains(fecha) {
            fecha = inf.reviews.first ?? ""
        }
    }
}

// MARK: Markdown

struct GraficaMD: Decodable {
    struct Serie: Decodable {
        var nombre: String?
        var datos: [Double?]
    }
    var tipo: String
    var titulo: String?
    var etiquetas: [String]
    var series: [Serie]
}

private enum BloqueMD {
    case titulo(Int, String)
    case parrafo(String)
    case lista([String], ordenada: Bool)
    case tabla([String], [[String]])
    case grafica(GraficaMD)
    case codigo(String)
    case raya
}

private struct BloqueNum: Identifiable {
    let id: Int
    let bloque: BloqueMD
}

private enum LectorMD {
    static func bloques(_ texto: String) -> [BloqueNum] {
        let L = texto.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n")
        var out: [BloqueMD] = []
        var i = 0
        func esLista(_ s: String) -> Bool { s.range(of: #"^\s*([-*+]|\d+[.)])\s+"#, options: .regularExpression) != nil }
        func esTabla(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespaces).hasPrefix("|") }
        func celdas(_ s: String) -> [String] {
            var t = s.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("|") { t.removeFirst() }
            if t.hasSuffix("|") { t.removeLast() }
            return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        while i < L.count {
            let l = L[i]
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") {
                let lenguaje = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var cuerpo: [String] = []
                i += 1
                while i < L.count && !L[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    cuerpo.append(L[i])
                    i += 1
                }
                i += 1
                if lenguaje == "grafica", let d = cuerpo.joined(separator: " ").data(using: .utf8),
                   let g = try? JSONDecoder().decode(GraficaMD.self, from: d) {
                    out.append(.grafica(g))
                } else {
                    out.append(.codigo(cuerpo.joined(separator: "\n")))
                }
                continue
            }
            if t.isEmpty { i += 1; continue }
            if let r = t.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                let nivel = t[r].filter { $0 == "#" }.count
                out.append(.titulo(nivel, String(t[r.upperBound...])))
                i += 1
                continue
            }
            if t.range(of: #"^(-{3,}|\*{3,})$"#, options: .regularExpression) != nil {
                out.append(.raya)
                i += 1
                continue
            }
            if esTabla(t), i + 1 < L.count, L[i + 1].range(of: #"^\s*\|?\s*:?-{2,}"#, options: .regularExpression) != nil {
                let cab = celdas(t)
                var filas: [[String]] = []
                i += 2
                while i < L.count && esTabla(L[i]) {
                    filas.append(celdas(L[i]))
                    i += 1
                }
                out.append(.tabla(cab, filas))
                continue
            }
            if esLista(l) {
                let ordenada = t.first?.isNumber ?? false
                var items: [String] = []
                while i < L.count && esLista(L[i]) {
                    var item = L[i].replacingOccurrences(of: #"^\s*([-*+]|\d+[.)])\s+"#, with: "", options: .regularExpression)
                    i += 1
                    // las líneas sangradas que siguen son del mismo punto
                    while i < L.count, L[i].hasPrefix("  "), !L[i].trimmingCharacters(in: .whitespaces).isEmpty, !esLista(L[i]) {
                        item += " " + L[i].trimmingCharacters(in: .whitespaces)
                        i += 1
                    }
                    items.append(item)
                }
                out.append(.lista(items, ordenada: ordenada))
                continue
            }
            var parrafo: [String] = []
            while i < L.count {
                let x = L[i].trimmingCharacters(in: .whitespaces)
                if x.isEmpty || x.hasPrefix("#") || x.hasPrefix("```") || esTabla(x) || esLista(L[i]) { break }
                parrafo.append(x)
                i += 1
            }
            if parrafo.isEmpty {   // una línea que no encaja en nada: como párrafo, y adelante
                parrafo.append(t)
                i += 1
            }
            out.append(.parrafo(parrafo.joined(separator: " ")))
        }
        return out.enumerated().map { BloqueNum(id: $0.offset, bloque: $0.element) }
    }

    /// Negrita, cursiva, código y enlaces de una línea.
    static func enLinea(_ s: String) -> AttributedString {
        let opciones = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: s, options: opciones)) ?? AttributedString(s)
    }
}

struct MarkdownInv: View {
    let texto: String

    var body: some View {
        let bloques = LectorMD.bloques(texto)
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            ForEach(bloques) { b in
                vista(b.bloque)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder private func vista(_ b: BloqueMD) -> some View {
        switch b {
        case .titulo(let nivel, let t):
            Text(LectorMD.enLinea(t))
                .font(Tema.fuente(nivel <= 2 ? .seccion : nivel == 3 ? .destacado : .texto, peso: .semibold))
                .foregroundStyle(Tema.texto)
                .padding(.top, nivel <= 2 ? Tema.Espacio.m : Tema.Espacio.xs)
        case .parrafo(let t):
            Text(LectorMD.enLinea(t))
                .font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        case .lista(let items, let ordenada):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ordenada ? "\(i + 1)." : "•").foregroundStyle(Tema.suave).monospacedDigit()
                        Text(LectorMD.enLinea(item)).foregroundStyle(Tema.texto)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(Tema.fuente(.texto))
                }
            }
        case .tabla(let cab, let filas):
            TablaMD(cabecera: cab, filas: filas)
        case .grafica(let g):
            GraficaReviewInv(g: g)
        case .codigo(let t):
            Text(t)
                .font(.system(size: 13, design: .monospaced)).foregroundStyle(Tema.texto)
                .padding(Tema.Espacio.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Tema.carta2, in: RoundedRectangle(cornerRadius: Tema.Radio.celda, style: .continuous))
        case .raya:
            Divider().overlay(Tema.linea)
        }
    }
}

private struct TablaMD: View {
    let cabecera: [String]
    let filas: [[String]]

    var body: some View {
        let n = max(cabecera.count, filas.map(\.count).max() ?? 0)
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    ForEach(0..<n, id: \.self) { j in
                        Text(LectorMD.enLinea(j < cabecera.count ? cabecera[j] : ""))
                            .font(Tema.fuente(.pequeno, peso: .semibold)).foregroundStyle(Tema.suave)
                    }
                }
                Divider().overlay(Tema.linea)
                ForEach(Array(filas.enumerated()), id: \.offset) { _, f in
                    GridRow(alignment: .top) {
                        ForEach(0..<n, id: \.self) { j in
                            Text(LectorMD.enLinea(j < f.count ? f[j] : ""))
                                .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.texto)
                                .monospacedDigit()
                                .frame(minWidth: 70, maxWidth: 220, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.vertical, Tema.Espacio.xs)
        }
        .scrollIndicators(.visible)
    }
}

// MARK: gráficas de la review

private struct DatoGrafInv: Identifiable {
    let id: String
    let etiqueta: String
    let serie: String
    let valor: Double
}

private struct GraficaReviewInv: View {
    let g: GraficaMD

    private var puntos: [DatoGrafInv] {
        var out: [DatoGrafInv] = []
        for (k, s) in g.series.enumerated() {
            let nombre = s.nombre ?? "Serie \(k + 1)"
            for (j, v) in s.datos.enumerated() where j < g.etiquetas.count {
                if let v, v.isFinite { out.append(DatoGrafInv(id: "\(k)-\(j)", etiqueta: g.etiquetas[j], serie: nombre, valor: v)) }
            }
        }
        return out
    }

    private var nombresSeries: [String] { g.series.enumerated().map { $0.element.nombre ?? "Serie \($0.offset + 1)" } }

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            if let t = g.titulo, !t.isEmpty {
                Text(t).font(Tema.fuente(.pequeno, peso: .semibold)).foregroundStyle(Tema.texto)
            }
            switch g.tipo {
            case "tarta": tarta
            case "lineas": lineas
            default: barras
            }
        }
        .padding(Tema.Espacio.m)
        .overlay(RoundedRectangle(cornerRadius: Tema.Radio.celda, style: .continuous).strokeBorder(Tema.linea, lineWidth: 1))
    }

    private var tarta: some View {
        let ps = puntos.filter { $0.serie == nombresSeries.first }
        let etiquetas = ps.map(\.etiqueta)
        return VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            Chart {
                ForEach(ps) { p in
                    SectorMark(angle: .value("Valor", max(0, p.valor)), innerRadius: .ratio(0.58), angularInset: 1.2)
                        .cornerRadius(3)
                        .foregroundStyle(by: .value("Parte", p.etiqueta))
                }
            }
            .chartForegroundStyleScale(domain: etiquetas, range: etiquetas.indices.map { ColoresInv.de($0) })
            .chartLegend(.hidden)
            .frame(height: 180)
            LeyendaInv(items: ps.enumerated().map { i, p in ("\(p.etiqueta) \(FechasES.coma(p.valor, p.valor == p.valor.rounded() ? 0 : 1))", ColoresInv.de(i), false) })
        }
    }

    private var barras: some View {
        let ps = puntos
        let nombres = nombresSeries
        return VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            Chart {
                ForEach(ps) { p in
                    BarMark(x: .value("Categoría", p.etiqueta), y: .value("Valor", p.valor))
                        .foregroundStyle(by: .value("Serie", p.serie))
                        .position(by: .value("Serie", p.serie))
                        .cornerRadius(3)
                }
            }
            .chartForegroundStyleScale(domain: nombres, range: nombres.indices.map { ColoresInv.de($0) })
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks { v in
                    AxisValueLabel {
                        if let s = v.as(String.self) {
                            Text(s).font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.tenue)
                        }
                    }
                }
            }
            .chartYAxis { ejeY }
            .frame(height: 200)
            if nombres.count > 1 {
                LeyendaInv(items: nombres.enumerated().map { i, n in (n, ColoresInv.de(i), false) })
            }
        }
    }

    private var lineas: some View {
        let ps = puntos
        let nombres = nombresSeries
        let colores: [Color] = nombres.enumerated().map { i, n in n == "Lo aportado" ? Tema.suave : ColoresInv.de(i) }
        return VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            Chart {
                ForEach(ps) { p in
                    LineMark(x: .value("Momento", p.etiqueta), y: .value("Valor", p.valor), series: .value("Serie", p.serie))
                        .foregroundStyle(by: .value("Serie", p.serie))
                        .lineStyle(p.serie == "Lo aportado" ? StrokeStyle(lineWidth: 1.5, dash: [4, 4]) : StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
            }
            .chartForegroundStyleScale(domain: nombres, range: colores)
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { v in
                    AxisValueLabel {
                        if let s = v.as(String.self) {
                            Text(s).font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.tenue)
                        }
                    }
                }
            }
            .chartYAxis { ejeY }
            .frame(height: 210)
            LeyendaInv(items: nombres.enumerated().map { i, n in (n, colores[i], n == "Lo aportado") })
        }
    }

    private var ejeY: some AxisContent {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
            AxisGridLine().foregroundStyle(Tema.linea)
            AxisValueLabel {
                if let x = v.as(Double.self) {
                    Text(FechasES.miles(x)).font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.tenue)
                }
            }
        }
    }
}
