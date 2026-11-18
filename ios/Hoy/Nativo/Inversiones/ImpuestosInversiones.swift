import SwiftUI

/// La pestaña Impuestos: lo que te quedaría si vendieras hoy, lo que toca en la renta de este año por lo ya vendido,
/// consejos para pagar menos y la lista de ventas con las cifras que pide la declaración. Las cuentas son del servidor
/// (inversiones.py, fiscal()): IRPF, base del ahorro, FIFO, compensaciones y la regla de los 2 meses.
struct ImpuestosInversiones: View {
    let inf: InformeInv

    var body: some View {
        if let f = inf.fiscal {
            VStack(alignment: .leading, spacing: Tema.Espacio.l) {
                cifras(f)
                if !f.consejos.isEmpty { consejos(f.consejos) }
                posiciones(f.siVendes)
                ventas(f)
                Text(explicacion(f))
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .carta()
            }
        } else {
            Text("El servidor aún no manda los impuestos. Tira hacia abajo para recargar.")
                .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                .frame(maxWidth: .infinity, alignment: .leading)
                .carta()
        }
    }

    // MARK: cifras

    private func cifras(_ f: FiscalInv) -> some View {
        let s = f.siVendes, r = f.renta
        let pieImpuesto = s.latente > 0 ? "\(FechasES.coma(s.tipo, 2)) % de lo ganado" : s.latente < 0 ? "vas en pérdidas" : " "
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: Tema.Espacio.m), GridItem(.flexible())], spacing: Tema.Espacio.m) {
            cifra("Si vendes todo hoy", DineroES.eur(s.neto), "de \(DineroES.eur(s.valor))", Tema.texto)
            cifra("Impuesto al vender", DineroES.eur(s.impuesto), pieImpuesto, Tema.texto)
            cifra("Renta \(String(f.anio))", DineroES.eur(r.cuota),
                  r.base > 0 ? "base \(DineroES.eur(r.base, 0)) · \(Int(r.marginal)) %" : "nada vendido aún", Tema.texto)
            cifra("Ganancia limpia", DineroES.signo(s.gananciaNeta), "\(DineroES.signo(s.latente)) antes", DineroES.color(s.gananciaNeta))
        }
    }

    private func cifra(_ titulo: String, _ valor: String, _ pie: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titulo).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).lineLimit(1).minimumScaleFactor(0.8)
            Text(valor)
                .font(Tema.fuente(.seccion)).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(pie).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .carta(relleno: Tema.Espacio.m)
        .accessibilityElement(children: .combine)
    }

    // MARK: consejos

    private func consejos(_ cs: [String]) -> some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            Text("Para pagar menos").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
            ForEach(cs, id: \.self) { c in
                Label {
                    Text(c).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lightbulb").foregroundStyle(Tema.acento)
                }
                .font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .carta()
    }

    // MARK: posiciones

    private func posiciones(_ s: SiVendesInv) -> some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            Text("Si vendieras cada una").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
            if s.posiciones.isEmpty {
                Text("Sin posiciones abiertas.").font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            }
            ForEach(Array(s.posiciones.enumerated()), id: \.element.id) { i, p in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(p.nombre).font(Tema.fuente(.texto, peso: .semibold)).foregroundStyle(Tema.texto).lineLimit(1)
                        Spacer(minLength: Tema.Espacio.s)
                        Text(DineroES.eur(p.neto)).font(Tema.fuente(.texto, peso: .semibold)).foregroundStyle(Tema.texto).monospacedDigit()
                    }
                    HStack {
                        Text("vale \(DineroES.eur(p.valor)) · \(DineroES.signo(p.latente))")
                        Spacer(minLength: Tema.Espacio.s)
                        Text(p.impuesto < 0 ? "ahorras \(DineroES.eur(-p.impuesto))" : "impuesto \(DineroES.eur(p.impuesto))")
                    }
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).monospacedDigit()
                    if p.reciente && p.latente < 0 {
                        Text("Comprado hace menos de 2 meses: si vendes y recompras pronto, la pérdida se aplaza.")
                            .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.aviso)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                if i < s.posiciones.count - 1 { Divider().overlay(Tema.linea) }
            }
            Text("Cada fila es vender solo esa posición, sobre lo que ya llevas este año. La cifra grande es lo que te quedaría.")
                .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.tenue)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .carta()
    }

    // MARK: ventas

    private func ventas(_ f: FiscalInv) -> some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            Text("Ventas de \(String(f.anio)) para la renta").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
            if f.ventas.isEmpty {
                Text("Ninguna venta este año: cuando vendas algo, aquí tendrás las cifras que pide la renta.")
                    .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(f.ventas.enumerated()), id: \.offset) { i, v in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(v.nombre).font(Tema.fuente(.texto, peso: .semibold)).foregroundStyle(Tema.texto).lineLimit(1)
                        Spacer(minLength: Tema.Espacio.s)
                        Text(DineroES.signo(v.resultado)).font(Tema.fuente(.texto, peso: .semibold))
                            .foregroundStyle(DineroES.color(v.resultado)).monospacedDigit()
                    }
                    Text("Vendido \(FechasES.larga(v.fecha)) · comprado \(comprado(v))")
                    Text("Adquisición \(DineroES.eur(v.adquisicion)) · transmisión \(DineroES.eur(v.transmision))").monospacedDigit()
                    if !v.isin.isEmpty { Text(v.isin).textSelection(.enabled) }
                    if v.diferida {
                        Text("Pérdida aplazada: compraste lo mismo a menos de 2 meses.").foregroundStyle(Tema.aviso)
                    }
                }
                .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                if i < f.ventas.count - 1 { Divider().overlay(Tema.linea) }
            }
            if f.dividendos != 0 {
                Text("Dividendos cobrados en \(String(f.anio)): \(DineroES.eur(f.dividendos)) (rendimientos del capital mobiliario).")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            }
            if !f.ventas.isEmpty {
                Text("Compáralo con el informe fiscal de Trade Republic. Va en «ganancias y pérdidas por transmisión de acciones admitidas a negociación»; las comisiones ya están dentro.")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.tenue)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .carta()
    }

    private func comprado(_ v: VentaFiscalInv) -> String {
        guard let a = v.compra else { return "—" }
        guard let b = v.compraHasta, b != a else { return FechasES.larga(a) }
        return "\(FechasES.larga(a)) – \(FechasES.larga(b))"
    }

    private func explicacion(_ f: FiscalInv) -> String {
        var t = "Base del ahorro del IRPF: 19 % hasta 6.000 €, 21 % hasta 50.000 €, 23 % hasta 200.000 €, 27 % hasta 300.000 € y 30 % por encima. "
            + "Solo pagas al vender (FIFO: lo primero que compraste es lo primero que vendes) y por dividendos e intereses cada año. "
            + "Las pérdidas compensan ganancias del mismo año y hasta el 25 % de los dividendos; lo que sobra vale 4 años (apúntalo en Perfil). "
            + "Si recompras lo mismo en menos de 2 meses, la pérdida se aplaza. No cuenta los intereses de la cuenta ni las retenciones de dividendos extranjeros. "
        if f.regimen == "foral" { t += "Tributas en Navarra o País Vasco: sus tramos son otros y esta cifra es orientativa. " }
        return t + "Es una estimación para decidir, no tu declaración."
    }
}
