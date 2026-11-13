import SwiftUI

/// «Rachas · últimos 28 días» de la web (index.html): por hábito, una tira con los 28 días (hecho, día libre o comodín),
/// o 4 semanas si es de una vez por semana (un hábito semanal con 27 huecos vacíos parece un fracaso aunque vaya
/// perfecto), la racha, la constancia de los últimos 30 días y el total de veces.
struct TiraRachas: View {
    let racha: (String) -> Int
    @State private var datos = DatosNativos.shared
    @State private var rachas = DatosRachas.shared

    private var dias: [String] {
        (0..<28).map { i in Fecha.dia(Calendar.current.date(byAdding: .day, value: i - 27, to: Date()) ?? Date()) }
    }

    var body: some View {
        if !datos.habitos.isEmpty {
            let dias = self.dias
            VStack(alignment: .leading, spacing: Tema.Espacio.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Rachas").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
                    Spacer()
                    Text("últimos 28 días").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                }
                HStack {
                    Text("hace 4 semanas")
                    Spacer()
                    Text("hoy")
                    Text("racha · 30 d").frame(width: 76, alignment: .trailing)
                }
                .font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.tenue)
                ForEach(datos.habitos) { h in fila(h, dias) }
            }
            .carta()
        }
    }

    private func fila(_ h: DatosNativos.HabitoEstado, _ dias: [String]) -> some View {
        let color = Color(hex: h.c)
        let r = racha(h.id)
        let pct = constancia(h.id)
        let total = datos.log.values.filter { $0.contains(h.id) }.count
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(h.n).font(Tema.fuente(.pequeno, peso: .medium)).foregroundStyle(Tema.texto).lineLimit(1)
            }
            HStack(spacing: Tema.Espacio.s) {
                tira(h, dias, color)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(r)").font(Tema.fuente(.texto, peso: .bold)).monospacedDigit()
                        .foregroundStyle(r >= 3 ? Tema.aviso : Tema.texto)
                        .contentTransition(.numericText())
                    Text("\(pct) %").font(Tema.fuente(.pequeno)).monospacedDigit().foregroundStyle(Tema.suave)
                }
                .frame(width: 76, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(h.n): \(r) días seguidos, \(pct) % de los últimos 30 días, \(total) en total")
    }

    @ViewBuilder private func tira(_ h: DatosNativos.HabitoEstado, _ dias: [String], _ color: Color) -> some View {
        if h.goal > 1 {
            HStack(spacing: 2) {
                ForEach(dias, id: \.self) { d in
                    let hecho = datos.log[d]?.contains(h.id) ?? false
                    let libre = rachas.estado(h.id, d).flatMap { ["descanso", "vacaciones", "enfermedad", "comodin"].contains($0) ? $0 : nil }
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(hecho ? color : libre == "comodin" ? Tema.acento.opacity(0.45) : libre != nil ? color.opacity(0.2) : Tema.carta2)
                        .frame(height: 14)
                }
            }
        } else {
            // por semanas: lleno si hubo al menos una marca esa semana
            HStack(spacing: 3) {
                ForEach(0..<4, id: \.self) { k in
                    let semana = Array(dias[(k * 7)..<(k * 7 + 7)])
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(semana.contains { datos.log[$0]?.contains(h.id) ?? false } ? color : Tema.carta2)
                        .frame(height: 14)
                }
            }
        }
    }

    /// La parte de los últimos 30 días con el hábito hecho, en %.
    private func constancia(_ id: String) -> Int {
        let n = (0..<30).filter { i in
            let d = Fecha.dia(Calendar.current.date(byAdding: .day, value: -i, to: Date()) ?? Date())
            return datos.log[d]?.contains(id) ?? false
        }.count
        return Int((Double(n) * 100 / 30).rounded())
    }
}
