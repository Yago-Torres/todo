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

    /// Un trozo de racha dentro de la semana (índices de `dias`). `entra`: viene de la semana anterior; `sale`: sigue
    /// en la siguiente. Los dos extremos se pintan pegados al borde.
    struct Tramo: Hashable {
        var desde: Int
        var hasta: Int
        var entra = false
        var sale = false
    }

    private func hecho(_ d: String) -> Bool { datos.log[d]?.contains(habito.id) ?? false }

    private func mueve(_ d: String, _ n: Int) -> String {
        guard let f = Fecha.fecha(d), let g = Calendar(identifier: .gregorian).date(byAdding: .day, value: n, to: f) else { return d }
        return Fecha.dia(g)
    }

    /// ¿Rompe la racha este día? Con lo que cuenta el servidor (/api/rachas: las últimas 6 semanas), solo un fallo; los
    /// días que no se exigían o eran libres no. Sin esos datos (más atrás o sin red) corta cualquier día sin hacer.
    private func corta(_ d: String) -> Bool {
        if hecho(d) { return false }
        let conDatos = rachas.habitos.contains { $0.id == habito.id } && d >= mueve(hoy, -41)
        return conDatos ? rachas.estado(habito.id, d) == "fallo" : true
    }

    /// Antes de `d`, ¿lo último que cuenta es un día hecho (la racha entra en la semana) o un fallo?
    private func vieneDeAntes(_ d: String) -> Bool {
        var x = mueve(d, -1)
        for _ in 0..<60 {
            if hecho(x) { return true }
            if corta(x) { return false }
            x = mueve(x, -1)
        }
        return false
    }

    /// Después de `d` (una semana pasada), ¿sigue la racha? Hasta el siguiente hecho o fallo; si llega a hoy, la de hoy.
    private func sigueDespues(_ d: String) -> Bool {
        var x = mueve(d, 1)
        while x < hoy {
            if hecho(x) { return true }
            if corta(x) { return false }
            x = mueve(x, 1)
        }
        return racha > 0
    }

    /// La cadena de la semana con la regla de rachas del servidor, como el widget de la semana (FilaSemana): solo la
    /// rompe un día exigido sin hacer. Lo de entre medias (Correr 3/sem, o una semana sin tocar de un hábito quincenal)
    /// queda dentro de la cápsula; si la racha sigue viva, la cápsula llega hasta hoy.
    private var tramos: [Tramo] {
        guard let primero = dias.first, primero <= hoy else { return [] }
        var out: [Tramo] = []
        var desde: Int? = nil, ultimo: Int? = nil
        var entra = vieneDeAntes(primero)
        if entra { desde = 0 }
        func cierra() {
            // se rompió: del principio al último hecho (sin hechos esta semana, la que entraba ya no llega)
            if let a = desde, let u = ultimo, u > a || entra { out.append(Tramo(desde: a, hasta: u, entra: entra)) }
        }
        for (i, d) in dias.enumerated() where d <= hoy {
            if hecho(d) {
                if desde == nil { desde = i }
                ultimo = i
            } else if d < hoy && corta(d) {   // hoy sin hacer todavía no rompe
                cierra()
                desde = nil; ultimo = nil; entra = false
            }
        }
        if let a = desde {
            if let iHoy = dias.firstIndex(of: hoy) {
                if racha > 0 { out.append(Tramo(desde: a, hasta: iHoy, entra: entra)) } else { cierra() }
            } else if sigueDespues(dias[dias.count - 1]) {
                out.append(Tramo(desde: a, hasta: dias.count - 1, entra: entra, sale: true))
            } else {
                cierra()
            }
        }
        return out.filter { $0.hasta > $0.desde || $0.entra || $0.sale }
    }

    /// Los días que cuentan para el objetivo: la semana, o las `cada` semanas que acaban en ella (quincenal: esta y la
    /// anterior). Así «1 vez cada 2 semanas» hecho la semana pasada sale 1/1 y no 0/1 en gris.
    private var diasPeriodo: [String] {
        guard habito.cada > 1, let lunes = dias.first else { return dias }
        return (-(habito.cada - 1) * 7 ..< 7).map { mueve(lunes, $0) }
    }

    var body: some View {
        let color = Color(hex: habito.c)
        let hechos = diasPeriodo.filter { hecho($0) }.count
        let cadena = tramos
        let enRacha = Set(cadena.flatMap { Array($0.desde...$0.hasta) })
        // esta semana: hecho, cubierto o al día según el servidor (lo mismo que el círculo de Hoy) cuenta como cumplido
        let alDia = dias.contains(hoy) && (datos.hoy?.habitos.first { $0.id == habito.id }?.listo ?? false)
        let cumple = hechos >= habito.goal || alDia
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
                Text(habito.cada > 1 ? "\(hechos)/\(habito.goal) en \(habito.cada) sem." : "\(hechos)/\(habito.goal)")
                    .font(Tema.fuente(.pequeno)).monospacedDigit()
                    .foregroundStyle(cumple ? Tema.acento : Tema.suave)
                    .contentTransition(.numericText())
            }
            HStack(spacing: 0) {
                ForEach(Array(dias.enumerated()), id: \.element) { i, dia in
                    Dia(hecho: hecho(dia),
                        plan: datos.plan[dia]?.contains(habito.id) ?? false,
                        esHoy: dia == hoy, futuro: dia > hoy, color: color, estado: rachas.estado(habito.id, dia),
                        enRacha: enRacha.contains(i)) {
                        let nuevo = !hecho(dia)
                        Haptica.shared.toca(nuevo ? .marcar : .desmarcar)
                        Task { await datos.marca(habito.id, hecho: nuevo, dia: dia) }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .background {
                // la cápsula de cada racha, por debajo de los círculos
                GeometryReader { g in
                    let ancho = g.size.width / CGFloat(max(dias.count, 1))
                    let alto: CGFloat = 38
                    ZStack(alignment: .topLeading) {
                        ForEach(cadena, id: \.desde) { t in
                            let x0 = t.entra ? 0 : CGFloat(t.desde) * ancho + (ancho - alto) / 2
                            let x1 = t.sale ? g.size.width : CGFloat(t.hasta) * ancho + (ancho + alto) / 2
                            Capsule()
                                .fill(color.opacity(0.08))
                                .overlay(Capsule().strokeBorder(color.opacity(0.5), lineWidth: 1.5))
                                .frame(width: max(x1 - x0, alto), height: alto)
                                .offset(x: x0, y: (g.size.height - alto) / 2)
                                .animation(Tema.Muelle.toque, value: t.hasta)
                        }
                    }
                    .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
                }
                .accessibilityHidden(true)
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
        /// Dentro de una racha viva o cerrada (la cápsula de TarjetaHabito): sin hacer, pero no se exigía.
        var enRacha = false
        let toca: () -> Void

        private var libre: String? {
            guard !hecho, let estado, ["descanso", "vacaciones", "enfermedad", "comodin"].contains(estado) else { return nil }
            return estado
        }

        var body: some View {
            Button(action: toca) {
                ZStack {
                    Circle()
                        .fill(hecho ? color : libre != nil ? color.opacity(0.14) : enRacha ? Color.clear : Tema.carta2)
                    if enRacha && !hecho && libre == nil && !esHoy {
                        // no tocaba: un punto del color, la cápsula de detrás dice que la racha sigue
                        Circle().fill(color.opacity(0.5)).frame(width: 5, height: 5)
                    }
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
                                ?? (estado == "fallo" ? "Sin hacer, se rompió la racha" : plan ? "Planificado"
                                    : enRacha ? "No tocaba, la racha sigue" : "Sin hacer"))
        }
    }
}
