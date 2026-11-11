import SwiftUI

enum Paleta {
    static let hab = Color(hex: "#1baf7a")
    static let pas = Color(hex: "#eb6834")
    static let sue = Color(hex: "#3987e5")
    static let fondo = Color(hex: "#171A16")
    static let campo = Color(hex: "#2B3028")
    static let texto = Color(hex: "#EEF0E8")
    static let suave = Color(hex: "#A3A892")
    static let aviso = Color(hex: "#E8B04A")
}

enum Objetivo {
    static let pasos = 10000.0
    static let sueno = 480.0
}

/// Los números del día ya calculados, para que todas las vistas pinten lo mismo.
struct Resumen {
    let habitos: [Habito]
    let hechos: Int
    let pasos: Int
    let sueno: Int
    let tareas: [Tarea]
    let enJuego: Bool
    let gastos: GastosHoy?

    init(_ h: Hoy, ahora: Date) {
        habitos = h.habitos
        hechos = h.habitos.filter { $0.hecho }.count
        pasos = h.salud?.pasos?.ultimo ?? 0
        sueno = h.salud?.sueno?.ultimo ?? 0
        tareas = h.tareas ?? []
        gastos = h.gastos
        let hora = Calendar.current.component(.hour, from: ahora)
        enJuego = hora >= 20 && h.habitos.contains { !$0.hecho && $0.racha >= 2 }
    }

    var progresos: [(Double, Color)] {
        [(habitos.isEmpty ? 0 : Double(hechos) / Double(habitos.count), Paleta.hab),
         (Double(pasos) / Objetivo.pasos, Paleta.pas),
         (Double(sueno) / Objetivo.sueno, Paleta.sue)]
    }

    var textoPasos: String { pasos > 0 ? Resumen.miles(pasos) : "—" }
    var textoSueno: String { sueno > 0 ? Resumen.hm(sueno) : "—" }

    /// «Quedan 466 € · 27,45 €/día · 17 d» del ciclo de gastos; nil si no hay presupuesto o gastos no responde.
    var textoGastos: String? {
        guard let g = gastos, let queda = g.queda else { return nil }
        guard queda >= 0 else { return "Ciclo pasado en \(Resumen.euros(-queda))" }
        var t = "Quedan \(Resumen.euros(queda))"
        if let dia = g.al_dia, dia > 0 { t += " · \(Resumen.euros(dia))/día" }
        if let d = g.quedan, d > 0 { t += " · \(d) d" }
        return t
    }

    var gastosPasados: Bool { (gastos?.queda ?? 0) < 0 }

    /// Euros a la española: «1.402 €», «27,45 €» (los céntimos solo por debajo de 100).
    static func euros(_ x: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "es_ES")
        f.usesGroupingSeparator = true
        f.groupingSize = 3
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = abs(x) >= 100 ? 0 : 2
        return (f.string(from: NSNumber(value: x)) ?? String(Int(x.rounded()))) + " €"
    }

    static func hm(_ m: Int) -> String {
        "\(m / 60) h " + String(format: "%02d", m % 60)
    }

    static func miles(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "es_ES")
        f.usesGroupingSeparator = true
        f.groupingSize = 3
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }

    static func linea(_ t: Tarea) -> String {
        if let hora = t.hora, !hora.isEmpty { return "\(t.t) · \(hora)" }
        return t.t
    }
}

struct Anillos: View {
    let valores: [(Double, Color)]
    let grosor: CGFloat
    var separacion: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            let lado = min(geo.size.width, geo.size.height)
            ZStack {
                ForEach(0..<valores.count, id: \.self) { i in
                    let margen = grosor / 2 + CGFloat(i) * (grosor + separacion)
                    let p = min(1, max(0, valores[i].0))
                    ZStack {
                        Circle().stroke(valores[i].1.opacity(0.2), lineWidth: grosor)
                        if p > 0 {
                            Circle()
                                .trim(from: 0, to: p)
                                .stroke(valores[i].1, style: StrokeStyle(lineWidth: grosor, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                    }
                    .padding(margen)
                }
            }
            .frame(width: lado, height: lado)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
