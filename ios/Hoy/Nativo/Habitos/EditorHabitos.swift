import SwiftUI

/// "#RRGGBB" de un Color (lo que devuelve el ColorPicker).
private func hexDelColor(_ c: Color) -> String {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
    func canal(_ x: CGFloat) -> Int { Int((max(0, min(1, x)) * 255).rounded()) }
    return String(format: "#%02X%02X%02X", canal(r), canal(g), canal(b))
}

/// Un hábito mientras se crea o se edita (id nil = nuevo).
struct BorradorHabito: Identifiable, Equatable {
    var id: String?
    var n = ""
    var c = GestorHabitos.colores[0]
    var goal = 7
    var cada = 1
    var clave: String { id ?? "nuevo" }

    init() {}
    init(_ h: DatosNativos.HabitoEstado) {
        id = h.id; n = h.n; c = h.c; goal = h.goal; cada = h.cada
    }
}

/// Hábitos → Editar: la lista para ordenar, crear, tocar uno para cambiarlo y borrar. Lo mismo que «Rachas → Editar»
/// de la web (nombre, días por semana, borrar) más el color, cada cuántas semanas toca y el orden.
struct EditorHabitos: View {
    @Environment(\.dismiss) private var cerrar
    @State private var datos = DatosNativos.shared
    @State private var orden: [DatosNativos.HabitoEstado] = []
    @State private var modo: EditMode = .inactive
    @State private var borrador: BorradorHabito?
    @State private var error: String?
    @State private var descansos = false

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Text(error).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro)
                        .listRowBackground(Tema.carta)
                }
                Section {
                    ForEach(orden) { h in
                        Button { borrador = BorradorHabito(h) } label: { fila(h) }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button("Borrar", systemImage: "trash", role: .destructive) { borra(h) }
                            }
                    }
                    .onMove(perform: mueve)
                    .listRowBackground(Tema.carta)
                    if orden.isEmpty {
                        Text("Aún no tienes hábitos. Crea el primero con «Nuevo».")
                            .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                            .listRowBackground(Tema.carta)
                    }
                } footer: {
                    Text(modo == .active ? "Arrastra por las asas para cambiar el orden."
                         : "Toca un hábito para cambiarlo. Desliza para borrarlo.")
                }
                Section {
                    Button { descansos = true } label: {
                        Label("Descansos, vacaciones y comodines", systemImage: "leaf")
                    }
                    .listRowBackground(Tema.carta)
                } footer: {
                    Text("Días que no rompen las rachas: descansar hoy, vacaciones o enfermedad, y los comodines de cada mes.")
                }
            }
            .environment(\.editMode, $modo)
            .scrollContentBackground(.hidden)
            .background(Tema.fondo.ignoresSafeArea())
            .navigationTitle("Hábitos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(modo == .active ? "Hecho" : "Ordenar") {
                        Haptica.shared.toca(.marcar)
                        withAnimation(Tema.Muelle.pantalla) { modo = modo == .active ? .inactive : .active }
                    }
                    .disabled(orden.count < 2 && modo == .inactive)
                }
                ToolbarItem(placement: .confirmationAction) {
                    HStack {
                        Button("Nuevo", systemImage: "plus") { borrador = BorradorHabito() }
                            .disabled(orden.count >= GestorHabitos.maximo)
                        Button("Listo") { cerrar() }
                    }
                }
            }
            .sheet(item: $borrador) { b in
                FichaHabito(borrador: b)
            }
            .sheet(isPresented: $descansos) { HojaDescansos() }
        }
        .onAppear { orden = datos.habitos }
        .onChange(of: datos.habitos) { _, nuevos in orden = nuevos }
    }

    private func fila(_ h: DatosNativos.HabitoEstado) -> some View {
        HStack(spacing: Tema.Espacio.m) {
            Circle().fill(Color(hex: h.c)).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(h.n).font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto).lineLimit(2)
                Text(h.cada > 1 ? "\(h.goal) días por semana · cada \(h.cada) semanas" : "\(h.goal) días por semana")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Toca para cambiarlo")
    }

    private func mueve(_ origen: IndexSet, _ destino: Int) {
        let antes = orden
        orden.move(fromOffsets: origen, toOffset: destino)
        Haptica.shared.toca(.marcar)
        let ids = orden.map(\.id)
        Task {
            do {
                try await GestorHabitos.ordena(ids)
                error = nil
            } catch {
                withAnimation { orden = antes }
                self.error = error.localizedDescription
            }
        }
    }

    private func borra(_ h: DatosNativos.HabitoEstado) {
        Haptica.shared.toca(.desmarcar)
        Task {
            do {
                try await GestorHabitos.borra(h.id)
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Crear o cambiar un hábito: nombre, color, días por semana y cada cuántas semanas toca. Borrar pide confirmación.
struct FichaHabito: View {
    @State var borrador: BorradorHabito
    @Environment(\.dismiss) private var cerrar
    @State private var guardando = false
    @State private var confirmaBorrar = false
    @State private var fallo: String?
    @FocusState private var enfoque: Bool

    init(borrador: BorradorHabito) {
        _borrador = State(initialValue: borrador)
    }

    private var valido: Bool { !borrador.n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nombre") {
                    TextField("Por ejemplo, Leer 20 minutos", text: $borrador.n)
                        .focused($enfoque)
                        .submitLabel(.done)
                        .onChange(of: borrador.n) { _, v in if v.count > 60 { borrador.n = String(v.prefix(60)) } }
                }
                .listRowBackground(Tema.carta)

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                        ForEach(GestorHabitos.colores, id: \.self) { c in
                            Button {
                                Haptica.shared.toca(.marcar)
                                borrador.c = c
                            } label: {
                                Circle().fill(Color(hex: c)).frame(height: 36)
                                    .overlay(Circle().strokeBorder(Tema.texto, lineWidth: borrador.c.uppercased() == c.uppercased() ? 3 : 0).padding(-4))
                            }
                            .buttonStyle(EstiloHundir())
                            .accessibilityLabel("Color \(c)")
                            .accessibilityAddTraits(borrador.c.uppercased() == c.uppercased() ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 6)
                    ColorPicker("Otro color", selection: Binding(
                        get: { Color(hex: borrador.c) },
                        set: { borrador.c = hexDelColor($0) }), supportsOpacity: false)
                }
                .listRowBackground(Tema.carta)

                Section {
                    Stepper("Días por semana: \(borrador.goal)", value: $borrador.goal, in: 1...7)
                    Stepper(borrador.cada == 1 ? "Toca cada semana" : "Toca cada \(borrador.cada) semanas",
                            value: $borrador.cada, in: 1...8)
                } footer: {
                    Text("Con «cada 2 semanas» las semanas de descanso no cuentan como meta fallida (por ejemplo, escalada).")
                }
                .listRowBackground(Tema.carta)

                if let fallo {
                    Text(fallo).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro)
                        .listRowBackground(Tema.carta)
                }

                if borrador.id != nil {
                    Section {
                        Button("Borrar hábito", role: .destructive) { confirmaBorrar = true }
                    } footer: {
                        Text("Se borra también todo lo que llevas hecho y planificado de este hábito.")
                    }
                    .listRowBackground(Tema.carta)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Tema.fondo.ignoresSafeArea())
            .navigationTitle(borrador.id == nil ? "Nuevo hábito" : "Hábito")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { guarda() }.disabled(!valido || guardando)
                }
            }
            .confirmationDialog("¿Borrar «\(borrador.n)» del todo?", isPresented: $confirmaBorrar, titleVisibility: .visible) {
                Button("Borrar del todo", role: .destructive) { borra() }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("No se puede deshacer.")
            }
            .onAppear { if borrador.id == nil { enfoque = true } }
        }
        .presentationDetents([.large])
    }

    private func guarda() {
        guardando = true
        fallo = nil
        let b = borrador
        Task {
            defer { guardando = false }
            do {
                if let id = b.id {
                    try await GestorHabitos.edita(id, nombre: b.n, color: b.c, goal: b.goal, cada: b.cada)
                } else {
                    try await GestorHabitos.crea(nombre: b.n, color: b.c, goal: b.goal, cada: b.cada)
                }
                Haptica.shared.toca(.marcar)
                cerrar()
            } catch {
                Haptica.shared.toca(.error)
                fallo = error.localizedDescription
            }
        }
    }

    private func borra() {
        guard let id = borrador.id else { return }
        guardando = true
        Task {
            defer { guardando = false }
            do {
                try await GestorHabitos.borra(id)
                Haptica.shared.toca(.desmarcar)
                cerrar()
            } catch {
                Haptica.shared.toca(.error)
                fallo = error.localizedDescription
            }
        }
    }
}

/// Hábitos → Planificar: una semana en cuadrícula (hábito por día); tocar una casilla lo pone o lo quita del plan, como
/// al arrastrar un hábito al calendario en la web.
struct PlanificarSemana: View {
    @Environment(\.dismiss) private var cerrar
    @State private var datos = DatosNativos.shared
    @State private var semana = 0
    /// Lo tocado que el servidor aún no ha confirmado ("dia|id" → valor), para que la casilla cambie al momento.
    @State private var local: [String: Bool] = [:]
    @State private var error: String?

    private let letras = ["L", "M", "X", "J", "V", "S", "D"]

    private var dias: [String] {
        datos.semana(de: Fecha.dia(Calendar.current.date(byAdding: .day, value: 7 * semana, to: Date()) ?? Date()))
    }

    private func planeado(_ dia: String, _ id: String) -> Bool {
        local["\(dia)|\(id)"] ?? (datos.plan[dia]?.contains(id) ?? false)
    }

    var body: some View {
        let dias = self.dias
        let hoy = Fecha.hoy()
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tema.Espacio.l) {
                    HStack {
                        Button { cambia(-1) } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("Semana anterior")
                        Spacer()
                        Text(titulo(dias)).font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
                            .contentTransition(.interpolate)
                        Spacer()
                        Button { cambia(1) } label: { Image(systemName: "chevron.right") }
                            .accessibilityLabel("Semana siguiente")
                    }
                    .foregroundStyle(Tema.acento)
                    .font(.system(size: 15, weight: .semibold))

                    if datos.habitos.isEmpty {
                        Text("Primero crea algún hábito desde «Editar».")
                            .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave).carta()
                    } else {
                        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
                            HStack(spacing: 0) {
                                ForEach(Array(dias.enumerated()), id: \.offset) { i, dia in
                                    Text(letras[i]).estiloEtiqueta()
                                        .foregroundStyle(dia == hoy ? Tema.acento : Tema.suave)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            ForEach(datos.habitos) { h in
                                VStack(alignment: .leading, spacing: Tema.Espacio.xs) {
                                    HStack(spacing: Tema.Espacio.s) {
                                        Circle().fill(Color(hex: h.c)).frame(width: 8, height: 8)
                                        Text(h.n).font(Tema.fuente(.pequeno, peso: .medium)).foregroundStyle(Tema.texto).lineLimit(1)
                                        Spacer()
                                        Text("\(dias.filter { planeado($0, h.id) }.count)/\(h.goal)")
                                            .font(Tema.fuente(.pequeno)).monospacedDigit().foregroundStyle(Tema.suave)
                                            .contentTransition(.numericText())
                                    }
                                    HStack(spacing: 0) {
                                        ForEach(dias, id: \.self) { dia in
                                            casilla(h, dia, hoy: hoy)
                                                .frame(maxWidth: .infinity)
                                        }
                                    }
                                }
                            }
                        }
                        .carta(relleno: Tema.Espacio.m)
                    }
                    if let error {
                        Text(error).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro)
                    }
                    Text("Toca un día para planificar el hábito (aro discontinuo en la pantalla de Hábitos). Los días pasados también se pueden planificar.")
                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                }
                .padding(Tema.Espacio.l)
            }
            .background(Tema.fondo.ignoresSafeArea())
            .navigationTitle("Planificar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { cerrar() } } }
        }
    }

    private func casilla(_ h: DatosNativos.HabitoEstado, _ dia: String, hoy: String) -> some View {
        let si = planeado(dia, h.id)
        let color = Color(hex: h.c)
        return Button {
            toca(h.id, dia, !si)
        } label: {
            ZStack {
                Circle().fill(si ? color : Tema.carta2)
                if dia == hoy && !si { Circle().strokeBorder(Tema.acento, lineWidth: 2) }
                if si {
                    Image(systemName: "calendar").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 34, height: 34)
            .scaleEffect(si ? 1 : 0.9)
            .animation(Tema.Muelle.toque, value: si)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(h.n), \(dia)")
        .accessibilityValue(si ? "Planificado" : "Sin planificar")
        .accessibilityHint("Toca para \(si ? "quitarlo del plan" : "planificarlo")")
    }

    private func toca(_ id: String, _ dia: String, _ nuevo: Bool) {
        Haptica.shared.toca(nuevo ? .marcar : .desmarcar)
        let clave = "\(dia)|\(id)"
        withAnimation(Tema.Muelle.toque) { local[clave] = nuevo }
        Task {
            do {
                try await GestorHabitos.planea(id, dia: dia, si: nuevo)
                error = nil
            } catch {
                Haptica.shared.toca(.error)
                self.error = error.localizedDescription
            }
            withAnimation(Tema.Muelle.toque) { _ = local.removeValue(forKey: clave) }
        }
    }

    private func cambia(_ paso: Int) {
        Haptica.shared.toca(.marcar)
        withAnimation(Tema.Muelle.pantalla) { semana += paso }
    }

    private func titulo(_ dias: [String]) -> String {
        if semana == 0 { return "Esta semana" }
        if semana == 1 { return "La semana que viene" }
        if semana == -1 { return "La semana pasada" }
        guard let a = dias.first, let b = dias.last else { return "" }
        return "\(corto(a)) – \(corto(b))"
    }

    private func corto(_ dia: String) -> String {
        let p = dia.split(separator: "-")
        guard p.count == 3, let d = Int(p[2]), let m = Int(p[1]) else { return dia }
        return "\(d)/\(m)"
    }
}
