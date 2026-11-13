import SwiftUI

/// Hábitos en nativo: la semana de cada hábito (lunes a domingo), lo que lleva contra su objetivo y la racha.
/// Tocar un día lo marca o desmarca (hoy y días pasados); las flechas cambian de semana (deslizar es cambiar de sección).
/// «Editar» crea, cambia, ordena y borra hábitos y planifica la semana (Habitos/EditorHabitos.swift).
struct PantallaHabitos: View {
    @State private var datos = DatosNativos.shared
    @State private var semanaAtras = 0
    @State private var editando = false
    @State private var planificando = false
    @State private var calendario = false
    @State private var nuevo: BorradorHabito?
    @State private var descansos = false
    @State private var rachas = DatosRachas.shared

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
                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.aviso)
                }
                HStack(spacing: 0) {
                    ForEach(Array(dias.enumerated()), id: \.offset) { i, dia in
                        Text(letras[i])
                            .estiloEtiqueta()
                            .foregroundStyle(dia == hoy ? Tema.acento : Tema.suave)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, Tema.Espacio.m)
                if datos.habitos.isEmpty {
                    Text(datos.cargando ? "Cargando…" : "Sin hábitos todavía. Crea el primero desde «Editar».")
                        .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                        .carta()
                }
                ForEach(datos.habitos) { h in
                    TarjetaHabito(habito: h, dias: dias, hoy: hoy, racha: racha(h.id))
                }
                TiraRachas(racha: { racha($0) })   // Habitos/TiraRachas.swift
            }
            .padding(.horizontal, Tema.Espacio.l)
            .padding(.top, Tema.Espacio.s)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await datos.recarga()
            await rachas.recarga()
        }
        .task { await datos.carga() }
        .task { await rachas.carga() }
        .onChange(of: datos.log) { _, _ in Task { await rachas.recarga() } }   // marcar un día pasado cambia la cuenta
        .celebraHitos()
        .sheet(isPresented: $descansos) { HojaDescansos() }
        .sheet(isPresented: $editando) { EditorHabitos() }
        .sheet(isPresented: $planificando) { PlanificarSemana() }
        .sheet(isPresented: $calendario) { CalendarioHabitos() }
        .sheet(item: $nuevo) { FichaHabito(borrador: $0) }
    }

    private func cabecera(_ dias: [String]) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(semanaAtras == 0 ? "Esta semana" : semanaAtras == 1 ? "La semana pasada" : "Hace \(semanaAtras) semanas")
                    .estiloEtiqueta().foregroundStyle(Tema.suave).textCase(.uppercase)
                    .contentTransition(.interpolate)
                Text("Hábitos").font(Tema.fuente(.titulo)).foregroundStyle(Tema.texto)
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
                Menu {
                    Button("Nuevo hábito", systemImage: "plus") { nuevo = BorradorHabito() }
                    Button("Planificar la semana", systemImage: "calendar") { planificando = true }
                    Button("Calendario del mes", systemImage: "calendar.day.timeline.left") { calendario = true }
                    Button("Editar y ordenar", systemImage: "pencil") { editando = true }
                    Divider()
                    Button("Descansar hoy, vacaciones y comodines", systemImage: "leaf") { descansos = true }
                } label: {
                    Text("Editar").font(Tema.fuente(.pequeno, peso: .medium))
                }
                .accessibilityLabel("Editar hábitos")
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
    @State private var rachas = DatosRachas.shared

    var body: some View {
        let color = Color(hex: habito.c)
        let hechos = dias.filter { datos.log[$0]?.contains(habito.id) ?? false }.count
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            HStack(alignment: .firstTextBaseline, spacing: Tema.Espacio.s) {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(habito.n).font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto).lineLimit(2)
                Spacer()
                if racha > 1 {
                    let congelada = rachas.estado(habito.id, hoy).map { $0 != "hecho" && $0 != "pendiente" && $0 != "fallo" } ?? false
                    Label("\(racha)", systemImage: congelada ? "snowflake" : "flame.fill")
                        .font(Tema.fuente(.pequeno, peso: .semibold)).monospacedDigit()
                        .foregroundStyle(congelada ? Tema.suave : Tema.aviso)
                        .contentTransition(.numericText())
                        .accessibilityLabel(congelada ? "Racha de \(racha) días, congelada hoy" : "Racha de \(racha) días")
                }
                Text(habito.cada > 1 ? "\(hechos)/\(habito.goal) · cada \(habito.cada) sem." : "\(hechos)/\(habito.goal)")
                    .font(Tema.fuente(.pequeno)).monospacedDigit()
                    .foregroundStyle(hechos >= habito.goal ? Tema.acento : Tema.suave)
                    .contentTransition(.numericText())
            }
            HStack(spacing: 0) {
                ForEach(dias, id: \.self) { dia in
                    Dia(hecho: datos.log[dia]?.contains(habito.id) ?? false,
                        plan: datos.plan[dia]?.contains(habito.id) ?? false,
                        esHoy: dia == hoy, futuro: dia > hoy, color: color, estado: rachas.estado(habito.id, dia)) {
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
        /// Lo que dice la racha de ese día (DatosRachas.estado): descanso, vacaciones, enfermedad, comodin, fallo…
        var estado: String? = nil
        let toca: () -> Void

        private var libre: String? {
            guard !hecho, let estado, ["descanso", "vacaciones", "enfermedad", "comodin"].contains(estado) else { return nil }
            return estado
        }

        var body: some View {
            Button(action: toca) {
                ZStack {
                    Circle()
                        .fill(hecho ? color : libre != nil ? color.opacity(0.14) : Tema.carta2)
                    if let libre {
                        // día que no cuenta: su icono, y la racha ni sube ni se rompe
                        Image(systemName: DatosRachas.icono(libre))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(libre == "comodin" ? Tema.acento : Tema.suave)
                    }
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
            .accessibilityLabel(hecho ? "Hecho" : libre.map { DatosRachas.nombre($0) + ": no cuenta para la racha" }
                                ?? (estado == "fallo" ? "Sin hacer, se rompió la racha" : plan ? "Planificado" : "Sin hacer"))
        }
    }
}
