import SwiftUI

/// Hábitos en nativo: la semana de cada hábito (lunes a domingo), lo que lleva contra su objetivo y la racha.
/// Tocar un día lo marca o desmarca (hoy y días pasados); el resto de la página web (editar hábitos, planificar)
/// sigue en /habitos.html, a un toque desde «Editar».
struct PantallaHabitos: View {
    @State private var datos = DatosNativos.shared
    @State private var semanaAtras = 0

    private let letras = ["L", "M", "X", "J", "V", "S", "D"]

    private var diaBase: String {
        let d = Calendar.current.date(byAdding: .day, value: -7 * semanaAtras, to: Date()) ?? Date()
        return Fecha.dia(d)
    }

    var body: some View {
        let dias = datos.semana(de: diaBase)
        let hoy = Fecha.hoy()
        ScrollView {
            VStack(alignment: .leading, spacing: Tema.Espacio.l) {
                cabecera(dias)
                if let copia = datos.copia {
                    Label(API.notaCopia(copia), systemImage: "wifi.slash")
                        .font(Tema.fuente(.pie)).foregroundStyle(Tema.aviso)
                }
                HStack(spacing: 0) {
                    ForEach(Array(dias.enumerated()), id: \.offset) { i, dia in
                        Text(letras[i])
                            .font(Tema.fuente(.etiqueta))
                            .foregroundStyle(dia == hoy ? Tema.acento : Tema.suave)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, Tema.Espacio.m)
                if datos.habitos.isEmpty {
                    Text(datos.cargando ? "Cargando…" : "Sin hábitos todavía. Créalos desde «Editar».")
                        .font(Tema.fuente(.cuerpo)).foregroundStyle(Tema.suave)
                        .carta()
                }
                ForEach(datos.habitos) { h in
                    TarjetaHabito(habito: h, dias: dias, hoy: hoy, racha: racha(h.id))
                }
            }
            .padding(.horizontal, Tema.Espacio.l)
            .padding(.top, Tema.Espacio.s)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .refreshable { await datos.recarga() }
        .task { await datos.carga() }
        .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { g in
            guard abs(g.translation.width) > abs(g.translation.height) * 1.5 else { return }
            withAnimation(Tema.Muelle.pantalla) {
                semanaAtras = max(0, semanaAtras + (g.translation.width > 0 ? 1 : -1))
            }
        })
    }

    private func cabecera(_ dias: [String]) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(semanaAtras == 0 ? "Esta semana" : semanaAtras == 1 ? "La semana pasada" : "Hace \(semanaAtras) semanas")
                    .font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.suave).textCase(.uppercase)
                    .contentTransition(.interpolate)
                Text("Hábitos").font(Tema.fuente(.saludo)).foregroundStyle(Tema.texto)
            }
            Spacer()
            HStack(spacing: Tema.Espacio.s) {
                Button { withAnimation(Tema.Muelle.pantalla) { semanaAtras += 1 } } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Semana anterior")
                Button { withAnimation(Tema.Muelle.pantalla) { semanaAtras = max(0, semanaAtras - 1) } } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(semanaAtras == 0)
                .accessibilityLabel("Semana siguiente")
                Button("Editar") {
                    // la página web de siempre, con la edición y la planificación
                    Navegador.shared.abre("/habitos.html?web=1")
                }
                .font(Tema.fuente(.pie, peso: .medium))
            }
            .foregroundStyle(Tema.acento)
            .font(.system(size: 15, weight: .semibold))
        }
        .padding(.top, Tema.Espacio.s)
    }

    private func racha(_ id: String) -> Int {
        datos.hoy?.habitos.first(where: { $0.id == id })?.racha ?? 0
    }
}

struct TarjetaHabito: View {
    let habito: DatosNativos.HabitoEstado
    let dias: [String]
    let hoy: String
    let racha: Int
    @State private var datos = DatosNativos.shared

    var body: some View {
        let color = Color(hex: habito.c)
        let hechos = dias.filter { datos.log[$0]?.contains(habito.id) ?? false }.count
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            HStack(alignment: .firstTextBaseline, spacing: Tema.Espacio.s) {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(habito.n).font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto).lineLimit(2)
                Spacer()
                if racha > 1 {
                    Label("\(racha)", systemImage: "flame.fill")
                        .font(Tema.fuente(.pie, peso: .semibold)).monospacedDigit()
                        .foregroundStyle(Tema.aviso)
                        .contentTransition(.numericText())
                }
                Text(habito.cada > 1 ? "\(hechos)/\(habito.goal) · cada \(habito.cada) sem." : "\(hechos)/\(habito.goal)")
                    .font(Tema.fuente(.pie)).monospacedDigit()
                    .foregroundStyle(hechos >= habito.goal ? Tema.acento : Tema.suave)
                    .contentTransition(.numericText())
            }
            HStack(spacing: 0) {
                ForEach(dias, id: \.self) { dia in
                    Dia(hecho: datos.log[dia]?.contains(habito.id) ?? false,
                        plan: datos.plan[dia]?.contains(habito.id) ?? false,
                        esHoy: dia == hoy, futuro: dia > hoy, color: color) {
                        let nuevo = !(datos.log[dia]?.contains(habito.id) ?? false)
                        Haptica.shared.toca(nuevo ? .marcar : .desmarcar)
                        Task { await datos.marca(habito.id, hecho: nuevo, dia: dia) }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Barra(valor: Double(hechos) / Double(max(habito.goal, 1)), color: color)
                .frame(height: 4)
                .animation(Tema.Muelle.toque, value: hechos)
        }
        .carta(relleno: Tema.Espacio.m)
    }

    struct Dia: View {
        let hecho: Bool
        let plan: Bool
        let esHoy: Bool
        let futuro: Bool
        let color: Color
        let toca: () -> Void

        var body: some View {
            Button(action: toca) {
                ZStack {
                    Circle()
                        .fill(hecho ? color : Tema.carta2)
                    if plan && !hecho {
                        Circle().strokeBorder(color, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    }
                    if esHoy && !hecho {
                        Circle().strokeBorder(Tema.acento, lineWidth: 2)
                    }
                    if hecho {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 32, height: 32)
                .scaleEffect(hecho ? 1 : 0.9)
                .opacity(futuro ? 0.35 : 1)
                .animation(Tema.Muelle.toque, value: hecho)
            }
            .buttonStyle(.plain)
            .disabled(futuro)
            .accessibilityLabel(hecho ? "Hecho" : plan ? "Planificado" : "Sin hacer")
        }
    }
}
