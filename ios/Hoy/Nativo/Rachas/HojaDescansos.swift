import SwiftUI

/// Descansos que no rompen rachas: descansar hoy (por hábito o todos), comodines del mes y periodos de vacaciones o
/// enfermedad. Se abre desde el bloque Rachas de Hoy, desde Hábitos y desde el editor de hábitos.
struct HojaDescansos: View {
    @Environment(\.dismiss) private var cerrar
    @State private var rachas = DatosRachas.shared
    @State private var datos = DatosNativos.shared
    @State private var periodo: PeriodoLibre?

    var body: some View {
        NavigationStack {
            List {
                if let error = rachas.error {
                    Text(error).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro)
                        .listRowBackground(Tema.carta)
                }
                seccionHoy
                seccionComodines
                seccionPeriodos
            }
            .scrollContentBackground(.hidden)
            .background(Tema.fondo.ignoresSafeArea())
            .navigationTitle("Descansos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { cerrar() } }
            }
            .sheet(item: $periodo) { FichaPeriodo(periodo: $0) }
            .task { await rachas.recarga() }
        }
    }

    // MARK: hoy

    private var seccionHoy: some View {
        Section {
            Toggle(isOn: Binding(get: { rachas.descansos.contains("*") },
                                 set: { v in Task { await rachas.descansa(nil, quita: !v) } })) {
                Label("Todos los hábitos", systemImage: "leaf.fill")
            }
            ForEach(datos.habitos) { h in
                Toggle(isOn: Binding(get: { rachas.descansos.contains(h.id) || rachas.descansos.contains("*") },
                                     set: { v in Task { await rachas.descansa(h.id, quita: !v) } })) {
                    HStack(spacing: Tema.Espacio.s) {
                        Circle().fill(Color(hex: h.c)).frame(width: 10, height: 10)
                        Text(h.n).lineLimit(1)
                    }
                }
                .disabled(rachas.descansos.contains("*"))
            }
        } header: {
            Text("Descansar hoy")
        } footer: {
            Text("Un hábito que descansa no cuenta hoy: su racha se congela, ni sube ni se rompe.")
        }
        .tint(Tema.acento)
        .listRowBackground(Tema.carta)
    }

    // MARK: comodines

    private var seccionComodines: some View {
        Section {
            HStack {
                Label("Te quedan", systemImage: "snowflake")
                Spacer()
                Text("\(rachas.quedan) de \(rachas.alMes)")
                    .monospacedDigit().foregroundStyle(Tema.suave)
                    .contentTransition(.numericText())
            }
            Stepper(value: Binding(get: { rachas.alMes }, set: { n in Task { await rachas.ponAlMes(n) } }), in: 0...10) {
                Text(rachas.alMes == 1 ? "1 comodín al mes" : "\(rachas.alMes) comodines al mes")
            }
            if rachas.comodinHoy {
                Button("Devolver el comodín de hoy", systemImage: "arrow.uturn.backward") {
                    Task { await rachas.usaComodin(quita: true) }
                }
            } else {
                Button("Usar uno hoy", systemImage: "snowflake") {
                    Haptica.shared.toca(.marcar)
                    Task { await rachas.usaComodin() }
                }
                .disabled(rachas.quedan == 0)
            }
            if !rachas.usados.isEmpty {
                Text("Gastados este mes: " + rachas.usados.map(Self.diaCorto).joined(separator: ", "))
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            }
        } header: {
            Text("Comodines")
        } footer: {
            Text("Si un día se te pasa un hábito que te toca, se gasta uno solo y la racha sigue. Uno cubre el día entero. Vuelven el día 1.")
        }
        .listRowBackground(Tema.carta)
    }

    // MARK: vacaciones y enfermedad

    private var seccionPeriodos: some View {
        Section {
            ForEach(rachas.vacaciones) { p in
                Button { periodo = p } label: { fila(p) }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button("Borrar", systemImage: "trash", role: .destructive) { Task { await rachas.borra(p) } }
                    }
            }
            Button("Añadir vacaciones o enfermedad", systemImage: "plus") {
                periodo = PeriodoLibre(id: "v\(Int(Date().timeIntervalSince1970 * 1000) % 10_000_000_000)",
                                       desde: Fecha.hoy(), hasta: Fecha.hoy(), habitos: [], motivo: "vacaciones")
            }
        } header: {
            Text("Vacaciones y enfermedad")
        } footer: {
            Text("En esas fechas no se exige nada y las rachas se congelan. Para todos los hábitos o solo para algunos.")
        }
        .listRowBackground(Tema.carta)
    }

    private func fila(_ p: PeriodoLibre) -> some View {
        HStack(spacing: Tema.Espacio.m) {
            Image(systemName: DatosRachas.icono(p.motivo))
                .foregroundStyle(Tema.acento)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(DatosRachas.nombre(p.motivo)).font(Tema.fuente(.texto, peso: .medium)).foregroundStyle(Tema.texto)
                Text(p.desde == p.hasta ? Self.diaCorto(p.desde) : "Del \(Self.diaCorto(p.desde)) al \(Self.diaCorto(p.hasta))")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                Text(p.habitos.isEmpty ? "Todos los hábitos"
                     : DatosRachas.nombres(p.habitos.compactMap { id in datos.habitos.first { $0.id == id }?.n }))
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Tema.tenue)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    static func diaCorto(_ dia: String) -> String {
        guard let d = Fecha.fecha(dia) else { return dia }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "d MMM"
        return f.string(from: d)
    }
}

/// Crear o cambiar un periodo: motivo, desde-hasta y a qué hábitos afecta.
private struct FichaPeriodo: View {
    @Environment(\.dismiss) private var cerrar
    @State private var p: PeriodoLibre
    @State private var desde: Date
    @State private var hasta: Date
    @State private var todos: Bool
    @State private var datos = DatosNativos.shared
    private let nuevo: Bool

    init(periodo: PeriodoLibre) {
        _p = State(initialValue: periodo)
        _desde = State(initialValue: Fecha.fecha(periodo.desde) ?? Date())
        _hasta = State(initialValue: Fecha.fecha(periodo.hasta) ?? Date())
        _todos = State(initialValue: periodo.habitos.isEmpty)
        nuevo = !DatosRachas.shared.vacaciones.contains { $0.id == periodo.id }
    }

    private var valido: Bool {
        let dias = Calendar.current.dateComponents([.day], from: desde, to: hasta).day ?? -1
        return dias >= 0 && dias <= 366 && (todos || !p.habitos.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Motivo", selection: $p.motivo) {
                        Label("Vacaciones", systemImage: "beach.umbrella").tag("vacaciones")
                        Label("Enfermedad", systemImage: "bed.double.fill").tag("enfermedad")
                        Label("Descanso", systemImage: "leaf.fill").tag("descanso")
                    }
                    DatePicker("Desde", selection: $desde, displayedComponents: .date)
                    DatePicker("Hasta", selection: $hasta, in: desde..., displayedComponents: .date)
                }
                .listRowBackground(Tema.carta)
                Section {
                    Toggle("Todos los hábitos", isOn: $todos.animation(Tema.Muelle.pantalla))
                    if !todos {
                        ForEach(datos.habitos) { h in
                            Toggle(isOn: Binding(get: { p.habitos.contains(h.id) },
                                                 set: { v in
                                                     if v { p.habitos.append(h.id) } else { p.habitos.removeAll { $0 == h.id } }
                                                 })) {
                                HStack(spacing: Tema.Espacio.s) {
                                    Circle().fill(Color(hex: h.c)).frame(width: 10, height: 10)
                                    Text(h.n).lineLimit(1)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Hábitos")
                } footer: {
                    Text(valido ? "Como mucho un año." : todos ? "La fecha de fin no puede ir antes que la de inicio, ni pasar de un año."
                         : "Elige al menos un hábito, o «Todos».")
                }
                .tint(Tema.acento)
                .listRowBackground(Tema.carta)
            }
            .scrollContentBackground(.hidden)
            .background(Tema.fondo.ignoresSafeArea())
            .navigationTitle(nuevo ? "Nuevo periodo" : DatosRachas.nombre(p.motivo))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        var listo = p
                        listo.desde = Fecha.dia(desde)
                        listo.hasta = Fecha.dia(max(desde, hasta))
                        if todos { listo.habitos = [] }
                        Haptica.shared.toca(.marcar)
                        Task { await DatosRachas.shared.guarda(listo) }
                        cerrar()
                    }
                    .disabled(!valido)
                }
            }
        }
    }
}
