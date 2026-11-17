import SwiftUI
import Charts

/// La ficha de una posición: sus cifras, el precio de los últimos tres años con tu coste medio y tus operaciones
/// marcadas, y atajos para apuntar otra o cambiar el activo.
struct HojaPosicionInv: View {
    let posicion: PosicionInv
    @State private var datos = DatosInversiones.shared
    @State private var sel: Date?
    @State private var apuntando = false
    @State private var editando: ActivoInv?
    @Environment(\.dismiss) private var cierra

    private struct Cierre: Identifiable { let id: String; let fecha: Date; let precio: Double }
    private struct Marca: Identifiable { let id: String; let fecha: Date; let precio: Double; let venta: Bool }

    /// La posición con los datos de ahora (cambia si se apunta algo con la hoja abierta).
    private var p: PosicionInv { datos.inf?.posiciones.first { $0.id == posicion.id } ?? posicion }

    private var color: Color {
        let i = datos.inf?.abiertas.firstIndex { $0.id == posicion.id } ?? 0
        return ColoresInv.de(i)
    }

    private var cierres: [Cierre] {
        let desde = FechasES.masDias(Fecha.hoy(), -3 * 365)
        let serie = datos.inf?.historicos[p.simbolo] ?? [:]
        return serie.keys.sorted().filter { $0 >= desde }.compactMap { dia in
            guard let f = FechasES.fecha(dia), let v = serie[dia] else { return nil }
            return Cierre(id: dia, fecha: f, precio: v)
        }
    }

    private var marcas: [Marca] {
        (datos.inf?.operaciones ?? []).filter { $0.activo == p.id && $0.tipo != "dividendo" }.compactMap { o in
            guard let f = FechasES.fecha(o.fecha) else { return nil }
            return Marca(id: o.id, fecha: f, precio: o.precio, venta: o.tipo == "venta")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tema.Espacio.l) {
                    resumen
                    if cierres.count > 1 { grafica }
                    detalles
                }
                .padding(Tema.Espacio.l)
            }
            .background(Tema.fondo.ignoresSafeArea())
            .navigationTitle(p.nombre)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { cierra() } }
            }
            .sheet(isPresented: $apuntando) {
                HojaOperacionInv(operacion: nil, activoInicial: p.id)
            }
            .sheet(item: $editando) { a in
                HojaActivoInv(activo: a, alGuardar: { _ in })
            }
            .tostada(datos.aviso) { datos.quitaAviso() }
        }
        .tint(Tema.acento)
        .environment(\.locale, FechasES.locale)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Tema.fondo)
    }

    private var resumen: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.xs) {
            Text("\(p.simbolo) · \(DineroES.campo(p.cantidad)) participaciones")
                .estiloEtiqueta().foregroundStyle(Tema.suave)
            Text(DineroES.eur(p.valor)).font(Tema.fuente(.cifra)).foregroundStyle(Tema.texto)
            HStack(spacing: Tema.Espacio.s) {
                Text("\(DineroES.signo(p.latente)) (\(DineroES.pct(p.rent)))").foregroundStyle(DineroES.color(p.latente))
                if let d = p.dia { Text("· hoy \(DineroES.pct(d))").foregroundStyle(DineroES.color(d)) }
            }
            .font(Tema.fuente(.texto))
            HStack(spacing: Tema.Espacio.m) {
                Button { apuntando = true } label: {
                    Label("Apuntar operación", systemImage: "plus")
                        .font(Tema.fuente(.pequeno, peso: .semibold))
                        .foregroundStyle(Tema.acentoTexto)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Tema.acento, in: Capsule())
                }
                Button {
                    editando = datos.inf?.activo(p.id)
                } label: {
                    Label("Editar activo", systemImage: "pencil")
                        .font(Tema.fuente(.pequeno, peso: .medium))
                        .foregroundStyle(Tema.texto)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Tema.carta, in: Capsule())
                }
            }
            .buttonStyle(.plain)
            .padding(.top, Tema.Espacio.s)
        }
    }

    private var grafica: some View {
        let cs = cierres, ms = marcas
        return VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            Text("Precio").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
            Chart {
                ForEach(cs) { c in
                    LineMark(x: .value("Día", c.fecha, unit: .day), y: .value("Precio", c.precio))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round))
                        .foregroundStyle(color)
                }
                if let medio = p.costeMedio {
                    RuleMark(y: .value("Coste medio", medio))
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                        .foregroundStyle(Tema.suave)
                }
                ForEach(ms) { m in
                    PointMark(x: .value("Día", m.fecha, unit: .day), y: .value("Precio", m.precio))
                        .symbol(m.venta ? BasicChartSymbolShape.diamond : BasicChartSymbolShape.circle)
                        .symbolSize(48)
                        .foregroundStyle(Tema.texto)
                }
                if let s = sel, let c = cercano(s, cs) {
                    RuleMark(x: .value("Día", c.fecha, unit: .day))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(Tema.tenue)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { v in
                    AxisValueLabel {
                        if let d = v.as(Date.self) {
                            Text(FechasES.texto(d, "MMM yy")).font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.tenue)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                    AxisGridLine().foregroundStyle(Tema.linea)
                    AxisValueLabel {
                        if let x = v.as(Double.self) {
                            Text(DineroES.eur(x, x < 10 ? 2 : 0)).font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.tenue)
                        }
                    }
                }
            }
            .chartXSelection(value: $sel)
            .frame(height: 210)
            .accessibilityLabel("Precio de \(p.nombre) con tu coste medio y tus operaciones")
            if let s = sel, let c = cercano(s, cs) {
                Text("\(FechasES.larga(c.id)) · \(DineroES.precio(c.precio))").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.texto)
            } else {
                LeyendaInv(items: [("Precio", color, false), ("Tu coste medio", Tema.suave, true), ("Tus compras y ventas", Tema.texto, false)])
            }
        }
        .carta()
    }

    private func cercano(_ d: Date, _ cs: [Cierre]) -> Cierre? {
        cs.min { abs($0.fecha.timeIntervalSince(d)) < abs($1.fecha.timeIntervalSince(d)) }
    }

    private var detalles: some View {
        var filas: [(String, String)] = [
            ("Precio", DineroES.precio(p.precio)),
            ("Coste medio (FIFO)", DineroES.eur(p.costeMedio)),
            ("Invertido", DineroES.eur(p.coste)),
            ("Peso en la cartera", "\(FechasES.coma(p.peso, 1)) %"),
            ("TER", p.ter.map { "\(FechasES.coma($0, 2)) %" } ?? "sin apuntar"),
            ("ISIN", p.isin.isEmpty ? "—" : p.isin),
            ("Tipo", ColoresInv.tipos[p.tipo] ?? p.tipo),
        ]
        if p.realizado != 0 { filas.append(("Ya vendido", DineroES.signo(p.realizado))) }
        if p.dividendos != 0 { filas.append(("Dividendos", DineroES.eur(p.dividendos))) }
        if p.comisiones != 0 { filas.append(("Comisiones", DineroES.eur(p.comisiones))) }
        if !p.papel.isEmpty { filas.append(("Papel en tu cartera", p.papel)) }
        return VStack(spacing: 0) {
            ForEach(Array(filas.enumerated()), id: \.offset) { i, f in
                HStack(alignment: .firstTextBaseline) {
                    Text(f.0).foregroundStyle(Tema.suave)
                    Spacer(minLength: Tema.Espacio.m)
                    Text(f.1).foregroundStyle(Tema.texto).multilineTextAlignment(.trailing).monospacedDigit()
                }
                .font(Tema.fuente(.texto))
                .padding(.vertical, 9)
                if i < filas.count - 1 { Divider().overlay(Tema.linea) }
            }
        }
        .carta()
    }
}
