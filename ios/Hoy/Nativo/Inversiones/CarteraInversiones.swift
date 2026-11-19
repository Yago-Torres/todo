import SwiftUI
import Charts

/// La pestaña Cartera: cifras, evolución frente a la referencia, posiciones (tocar una abre su ficha) y reparto.
struct CarteraInversiones: View {
    let inf: InformeInv
    @State private var datos = DatosInversiones.shared
    @State private var abierta: PosicionInv?
    @State private var actualizando = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.l) {
            CifrasInv(inf: inf)
            if let l = inf.leccion { LeccionInvCarta(leccion: l) }
            GraficaEvolucionInv(inf: inf)
            posiciones
            if !inf.abiertas.isEmpty { GraficaRepartoInv(inf: inf) }
        }
        .sheet(item: $abierta) { p in
            HojaPosicionInv(posicion: p)
        }
    }

    private var posiciones: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            Text("Posiciones").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
            if inf.abiertas.isEmpty {
                Text(inf.activos.isEmpty ? "Aún no hay nada. Ve a Operaciones y apunta tu primera compra."
                                         : "Ahora mismo no tienes nada abierto.")
                    .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            }
            ForEach(Array(inf.abiertas.enumerated()), id: \.element.id) { i, p in
                Button {
                    Haptica.shared.toca(.dia)
                    abierta = p
                } label: {
                    FilaPosicionInv(p: p, color: ColoresInv.de(i))
                }
                .buttonStyle(.plain)
                if i < inf.abiertas.count - 1 { Divider().overlay(Tema.linea) }
            }
            HStack(spacing: Tema.Espacio.m) {
                Button {
                    actualizando = true
                    Task {
                        await datos.actualizaPrecios()
                        actualizando = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        if actualizando { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                        Text(actualizando ? "Actualizando…" : "Actualizar precios")
                    }
                    .font(Tema.fuente(.pequeno, peso: .medium))
                    .foregroundStyle(Tema.acento)
                }
                .disabled(actualizando)
                Spacer()
                if let hora = inf.posiciones.compactMap(\.precioHora).max() {
                    Text("Precios \(FechasES.cuando(hora)) \(hora.count >= 16 ? String(hora.suffix(5)) : "")")
                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.tenue)
                }
            }
            .padding(.top, Tema.Espacio.xs)
        }
        .carta()
    }
}

// MARK: cifras

private struct CifrasInv: View {
    let inf: InformeInv

    var body: some View {
        let t = inf.total
        let metido = inf.serie.last?.metido ?? 0
        let n = inf.abiertas.count
        let extra = [t.realizado != 0 ? "vendido \(DineroES.signo(t.realizado))" : "",
                     t.dividendos != 0 ? "dividendos \(DineroES.eur(t.dividendos))" : "",
                     t.comisiones != 0 ? "comisiones \(DineroES.eur(t.comisiones))" : ""].filter { !$0.isEmpty }
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Tema.Espacio.m), GridItem(.flexible())], spacing: Tema.Espacio.m) {
            cifra("Valor", DineroES.eur(t.valor), n == 0 ? "Sin posiciones" : n == 1 ? "1 posición" : "\(n) posiciones", Tema.texto)
            cifra("Ganancia sin vender", DineroES.signo(t.latente), DineroES.pct(t.rent), DineroES.color(t.latente))
            cifra("Hoy", DineroES.signo(t.dia), t.valor - t.dia != 0 ? DineroES.pct(t.dia / (t.valor - t.dia) * 100) : "",
                  DineroES.color(t.dia))
            cifra("Metido (neto)", DineroES.eur(metido), extra.first ?? "coste de lo que tienes", Tema.texto)
        }
    }

    private func cifra(_ titulo: String, _ valor: String, _ pie: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titulo).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            Text(valor)
                .font(Tema.fuente(.seccion)).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(pie).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .carta(relleno: Tema.Espacio.m)
        .accessibilityElement(children: .combine)
    }
}

// MARK: evolución

private struct PuntoGrafInv: Identifiable {
    let id: String
    let fecha: Date
    let serie: String
    let valor: Double
}

private struct GraficaEvolucionInv: View {
    let inf: InformeInv
    @State private var rango = 0
    @State private var sel: Date?

    private static let valor = "Valor"
    private static let metido = "Lo metido"

    private var referencia: String { "Todo en \(inf.referencia.simbolo)" }

    private var tramo: [PuntoSerieInv] {
        guard rango > 0 else { return inf.serie }
        let desde = FechasES.masDias(Fecha.hoy(), -rango)
        return inf.serie.filter { $0.dia >= desde }
    }

    private var puntos: [PuntoGrafInv] {
        var out: [PuntoGrafInv] = []
        for s in tramo {
            guard let f = FechasES.fecha(s.dia) else { continue }
            out.append(PuntoGrafInv(id: "v\(s.dia)", fecha: f, serie: Self.valor, valor: s.valor))
            out.append(PuntoGrafInv(id: "m\(s.dia)", fecha: f, serie: Self.metido, valor: s.metido))
            if let r = s.referencia { out.append(PuntoGrafInv(id: "r\(s.dia)", fecha: f, serie: referencia, valor: r)) }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            HStack {
                Text("Evolución").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
                Spacer()
                Picker("Periodo", selection: $rango) {
                    Text("1M").tag(30)
                    Text("6M").tag(182)
                    Text("1A").tag(365)
                    Text("Todo").tag(0)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }
            if tramo.isEmpty {
                Text("Cuando apuntes tu primera compra, aquí verás cómo evoluciona.")
                    .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            } else {
                grafica
                if let s = sel, let p = cercano(s) {
                    Text(lectura(p)).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.texto)
                } else {
                    LeyendaInv(items: [(Self.valor, Tema.acento, false), (Self.metido, Tema.suave, true),
                                       ("Si todo hubiera ido a \(inf.referencia.simbolo)", ColoresInv.de(0), false)])
                }
                if let u = inf.serie.last, let r = u.referencia {
                    Text("Con las mismas compras en \(inf.referencia.nombre ?? inf.referencia.simbolo) tendrías \(DineroES.eur(r)) (\(DineroES.signo(u.valor - r)) para ti). Es la forma honesta de saber si elegir valores te está saliendo a cuenta.")
                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .carta()
    }

    private var grafica: some View {
        let ps = puntos
        return Chart {
            ForEach(ps) { p in
                LineMark(x: .value("Día", p.fecha, unit: .day), y: .value("Euros", p.valor), series: .value("Serie", p.serie))
                    .foregroundStyle(by: .value("Serie", p.serie))
                    .lineStyle(estilo(p.serie))
                    .interpolationMethod(p.serie == Self.metido ? .stepEnd : .monotone)
            }
            if let s = sel, let p = cercano(s), let f = FechasES.fecha(p.dia) {
                RuleMark(x: .value("Día", f, unit: .day))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Tema.tenue)
            }
        }
        .chartForegroundStyleScale(domain: [Self.valor, Self.metido, referencia],
                                   range: [Tema.acento, Tema.suave, ColoresInv.de(0)])
        .chartLegend(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { v in
                AxisValueLabel {
                    if let d = v.as(Date.self) {
                        Text(FechasES.texto(d, rango > 0 && rango <= 31 ? "d MMM" : "MMM yy"))
                            .font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.tenue)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                AxisGridLine().foregroundStyle(Tema.linea)
                AxisValueLabel {
                    if let x = v.as(Double.self) {
                        Text(DineroES.corto(x)).font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.tenue)
                    }
                }
            }
        }
        .chartXSelection(value: $sel)
        .frame(height: 220)
        .accessibilityLabel("Valor de la cartera frente a lo metido y a la referencia")
    }

    private func estilo(_ serie: String) -> StrokeStyle {
        serie == Self.metido ? StrokeStyle(lineWidth: 1.5, dash: [4, 4]) : StrokeStyle(lineWidth: serie == Self.valor ? 2.2 : 1.6, lineCap: .round)
    }

    private func cercano(_ d: Date) -> PuntoSerieInv? {
        tramo.min { a, b in
            abs((FechasES.fecha(a.dia) ?? .distantPast).timeIntervalSince(d)) < abs((FechasES.fecha(b.dia) ?? .distantPast).timeIntervalSince(d))
        }
    }

    private func lectura(_ p: PuntoSerieInv) -> String {
        var s = "\(FechasES.larga(p.dia)) · valor \(DineroES.eur(p.valor)) · metido \(DineroES.eur(p.metido))"
        if let r = p.referencia { s += " · \(inf.referencia.simbolo) \(DineroES.eur(r))" }
        return s
    }
}

// MARK: reparto

private struct GraficaRepartoInv: View {
    let inf: InformeInv

    var body: some View {
        let lista = inf.abiertas.filter { ($0.valor ?? 0) > 0 }
        let tipos = ColoresInv.ordenTipos.compactMap { k in inf.reparto[k].map { "\(ColoresInv.tipos[k] ?? k) \(FechasES.coma($0, 1)) %" } }
        return VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            Text("Reparto").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
            Chart {
                ForEach(Array(lista.enumerated()), id: \.element.id) { i, p in
                    SectorMark(angle: .value("Valor", p.valor ?? 0), innerRadius: .ratio(0.62), angularInset: 1.5)
                        .cornerRadius(3)
                        .foregroundStyle(ColoresInv.de(i))
                }
            }
            .frame(height: 190)
            .accessibilityLabel("Peso de cada posición")
            LeyendaInv(items: lista.enumerated().map { i, p in ("\(p.nombre) \(FechasES.coma(p.peso, 1)) %", ColoresInv.de(i), false) })
            Text(tipos.joined(separator: " · ")).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            Text("Por la etiqueta de cada producto. Lo que hay dentro de los ETFs (países, sectores, empresas) lo mira la review del domingo.")
                .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.tenue)
                .fixedSize(horizontal: false, vertical: true)
        }
        .carta()
    }
}

// MARK: fila y leyenda

struct FilaPosicionInv: View {
    let p: PosicionInv
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(p.nombre).font(Tema.fuente(.texto, peso: .medium)).foregroundStyle(Tema.texto).lineLimit(1)
                Spacer(minLength: Tema.Espacio.s)
                Text(DineroES.eur(p.valor)).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto).monospacedDigit()
            }
            HStack(alignment: .firstTextBaseline) {
                Text("\(p.simbolo) · \(DineroES.campo(p.cantidad)) part. · \(FechasES.coma(p.peso, 1)) %")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).lineLimit(1)
                Spacer(minLength: Tema.Espacio.s)
                Text(DineroES.pct(p.rent)).font(Tema.fuente(.pequeno)).foregroundStyle(DineroES.color(p.rent))
                if let d = p.dia {
                    Text("· hoy \(DineroES.pct(d))").font(Tema.fuente(.pequeno)).foregroundStyle(DineroES.color(d))
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Tema.carta2)
                    Capsule().fill(color).frame(width: geo.size.width * min(1, max(0, p.peso / 100)))
                }
            }
            .frame(height: 4)
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Abre su ficha")
    }
}

/// Una leyenda: muestra de color (discontinua si es una raya) y texto.
struct LeyendaInv: View {
    let items: [(String, Color, Bool)]

    var body: some View {
        FlujoEnt(espacio: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, x in
                HStack(spacing: 6) {
                    if x.2 {
                        Rectangle().fill(x.1).frame(width: 14, height: 1.5).opacity(0.8)
                    } else {
                        RoundedRectangle(cornerRadius: 2).fill(x.1).frame(width: 10, height: 10)
                    }
                    Text(x.0).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                }
            }
        }
    }
}
