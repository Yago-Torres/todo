import Charts
import SwiftUI

/// Salud → Móvil (como en la web): lo que llevas en las apps que frenas (Freno manda los ratos a /api/pantalla/dias):
/// hoy, ayer y la media de la semana frente a la pasada; los últimos 30 días con el límite del hábito del móvil (en rojo
/// los días que te pasaste); y cada app con su rato al día, aperturas, «no entré» y días sobre su límite.

struct RespuestaPantalla: Decodable {
    struct App: Decodable, Hashable { var app: String; var s: Int; var n: Int; var no: Int }
    struct Periodo: Decodable { var s: Int; var n: Int; var no: Int; var apps: [App] }
    struct Dia: Decodable, Identifiable { var dia: String; var s: Int?; var id: String { dia } }
    var hoy: Periodo
    var ayer: Periodo
    var semana: Periodo
    var pasada: Periodo
    var limites: [String: Int]
    var excesos: [String: Int]
    var dias30: [Dia]?
    var limiteHabito: Double?

    enum CodingKeys: String, CodingKey {
        case hoy, ayer, semana, pasada, limites, excesos, dias30
        case limiteHabito = "limite_habito"
    }
}

struct CartaMovil: View {
    @State private var r: RespuestaPantalla?
    @State private var sel: Date?

    private func hm(_ segundos: Double) -> String {
        let m = Int((segundos / 60).rounded())
        return String(m / 60) + " h " + (m % 60 < 10 ? "0" : "") + String(m % 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            let lim = r?.limiteHabito
            TituloCarta(titulo: "Móvil", detalle: lim.map { "límite " + hm($0) + " al día" })
            if let r {
                cifras(r, lim)
                grafica(r, lim)
                apps(r)
                Text("Las apps que frenas en Tom (Freno). «No entré» son las veces que te lo pensaste y saliste.")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.tenue)
            } else {
                Text("Cargando…").font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            }
        }
        .carta()
        .task { await carga() }
    }

    private func cifras(_ r: RespuestaPantalla, _ lim: Double?) -> some View {
        let sem = Double(r.semana.s) / 7, pas = Double(r.pasada.s) / 7
        let dif = pas > 0 ? Int(((sem - pas) / pas * 100).rounded()) : nil
        let semTexto = dif.map { "al día esta semana (" + ($0 > 0 ? "+" : "") + String($0) + " %)" } ?? "al día esta semana"
        return HStack(alignment: .top, spacing: Tema.Espacio.m) {
            cifra(hm(Double(r.hoy.s)), "hoy", mal: lim.map { Double(r.hoy.s) > $0 } ?? false)
            cifra(hm(Double(r.ayer.s)), "ayer", mal: lim.map { Double(r.ayer.s) > $0 } ?? false)
            cifra(hm(sem), semTexto, mal: lim.map { sem > $0 } ?? false)
        }
    }

    private func cifra(_ valor: String, _ etiqueta: String, mal: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(valor).font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(mal ? Tema.peligro : Tema.texto)
            Text(etiqueta).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func grafica(_ r: RespuestaPantalla, _ lim: Double?) -> some View {
        let dias = (r.dias30 ?? []).compactMap { d -> (Date, String, Double)? in
            guard let s = d.s, let f = FechasES.fecha(d.dia) else { return nil }
            return (f, d.dia, Double(s) / 60)
        }
        if !dias.isEmpty {
            Chart {
                ForEach(dias, id: \.1) { d in
                    BarMark(x: .value("Día", d.0, unit: .day), y: .value("Minutos", d.2))
                        .cornerRadius(3)
                        .foregroundStyle(lim.map { d.2 * 60 > $0 } ?? false ? Tema.peligro : Tema.acento)
                }
                if let lim {
                    RuleMark(y: .value("Límite", lim / 60))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Tema.suave)
                }
            }
            .chartYAxis {
                AxisMarks(values: .stride(by: 60)) { v in
                    AxisGridLine()
                    AxisValueLabel { Text(String(Int((v.as(Double.self) ?? 0) / 60)) + " h") }
                }
            }
            .chartXSelection(value: $sel)
            .frame(height: 170)
            .accessibilityLabel("Minutos al día en las apps que vigilas, últimos 30 días")
            if let sel, let d = dias.min(by: { abs($0.0.timeIntervalSince(sel)) < abs($1.0.timeIntervalSince(sel)) }) {
                Lectura(texto: FechasES.corta(d.1) + " · " + hm(d.2 * 60))
            }
        }
    }

    private func apps(_ r: RespuestaPantalla) -> some View {
        let lista = r.semana.apps.filter { $0.s > 0 || $0.n > 0 }
        let top = Double(max(1, lista.map(\.s).max() ?? 1))
        return VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            ForEach(lista, id: \.self) { a in
                let limite = r.limites[a.app]
                let excesos = r.excesos[a.app] ?? 0
                let veces = a.n == 1 ? "vez" : "veces"
                let extra = limite.map { " · límite " + String($0) + " min, pasado " + String(excesos) + " de 7 días" } ?? ""
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(a.app).font(Tema.fuente(.pequeno, peso: .semibold)).foregroundStyle(Tema.texto)
                        Spacer()
                        Text(hm(Double(a.s) / 7) + "/día").font(Tema.fuente(.pequeno)).monospacedDigit().foregroundStyle(Tema.suave)
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Tema.linea)
                            Capsule().fill(Tema.acento).frame(width: g.size.width * Double(a.s) / top)
                        }
                    }
                    .frame(height: 7)
                    Text("Esta semana: " + String(a.n) + " " + veces + " · no entré " + String(a.no) + extra)
                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                }
            }
        }
    }

    private func carga() async {
        guard let d = try? await API.datos("/api/pantalla") else { return }
        if let x = try? JSONDecoder().decode(RespuestaPantalla.self, from: d) {
            withAnimation(Tema.Muelle.pantalla) { r = x }
        }
    }
}
