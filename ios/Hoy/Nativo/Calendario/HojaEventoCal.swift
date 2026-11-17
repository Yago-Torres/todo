import SwiftUI

/// Crear un evento, una tarea con fecha o un recordatorio; o cambiar o borrar un evento. Un evento que se repite se
/// cambia entero (la serie): las fechas de la hoja son las de la primera vez.
struct HojaEventoCal: View {
    enum Modo: Identifiable {
        case nuevo(dia: String, hora: String?, tipo: TipoElementoCal)
        case edita(EventoCal)

        var id: String {
            switch self {
            case .nuevo(let d, let h, let t): return "n|\(d)|\(h ?? "")|\(t.rawValue)"
            case .edita(let e): return "e|\(e.clave)"
            }
        }
    }

    let modo: Modo
    @State private var datos = DatosCalendario.shared
    @Environment(\.dismiss) private var cierra

    @State private var tipo: TipoElementoCal
    @State private var titulo: String
    @State private var todoElDia: Bool
    @State private var inicio: Date
    @State private var fin: Date
    @State private var cal: String
    @State private var repite: String
    @State private var conHasta: Bool
    @State private var hasta: Date
    @State private var aviso: Int
    @State private var lugar: String
    @State private var nota: String
    @State private var guardando = false
    @State private var preguntaBorrar = false
    @FocusState private var enTitulo: Bool

    init(modo: Modo) {
        self.modo = modo
        switch modo {
        case .nuevo(let dia, let hora, let t):
            let ini = UtilCal.fechaHora(dia, hora ?? "09:00")
            _tipo = State(initialValue: t)
            _titulo = State(initialValue: "")
            _todoElDia = State(initialValue: hora == nil && t == .evento)
            _inicio = State(initialValue: ini)
            _fin = State(initialValue: ini.addingTimeInterval(3600))
            _cal = State(initialValue: "")
            _repite = State(initialValue: "")
            _conHasta = State(initialValue: false)
            _hasta = State(initialValue: UtilCal.fecha(UtilCal.suma(dia, meses: 3)))
            _aviso = State(initialValue: hora == nil ? -1 : 10)
            _lugar = State(initialValue: "")
            _nota = State(initialValue: "")
        case .edita(let e):
            // la serie: la primera vez y lo que dura (varios días)
            let largo = Calendar.current.dateComponents([.day], from: UtilCal.fecha(e.dia), to: UtilCal.fecha(e.finDia)).day ?? 0
            let finDia = UtilCal.suma(e.origen, dias: max(0, largo))
            let ini = UtilCal.fechaHora(e.origen, e.inicio.isEmpty ? "09:00" : e.inicio)
            var acaba = UtilCal.fechaHora(finDia, e.fin.isEmpty ? UtilCal.hhmm((UtilCal.minutos(e.inicio) ?? 540) + 60) : e.fin)
            if acaba <= ini { acaba = ini.addingTimeInterval(3600) }
            _tipo = State(initialValue: .evento)
            _titulo = State(initialValue: e.t)
            _todoElDia = State(initialValue: e.todoElDia)
            _inicio = State(initialValue: ini)
            _fin = State(initialValue: e.todoElDia ? UtilCal.fecha(finDia) : acaba)
            _cal = State(initialValue: e.cal)
            _repite = State(initialValue: e.repite)
            _conHasta = State(initialValue: !e.hasta.isEmpty)
            _hasta = State(initialValue: UtilCal.fecha(e.hasta.isEmpty ? UtilCal.suma(e.origen, meses: 3) : e.hasta))
            _aviso = State(initialValue: e.aviso)
            _lugar = State(initialValue: e.lugar)
            _nota = State(initialValue: e.nota)
        }
    }

    private var editando: EventoCal? {
        if case .edita(let e) = modo { return e }
        return nil
    }

    private var componentes: DatePickerComponents { todoElDia ? [.date] : [.date, .hourAndMinute] }

    private var vacio: Bool { titulo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                if editando == nil {
                    Section {
                        Picker("Qué apuntas", selection: $tipo) {
                            ForEach(TipoElementoCal.allCases) { Text($0.nombre).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                    }
                }
                Section {
                    TextField(tipo == .evento ? "Título" : "Qué tienes que hacer", text: $titulo, axis: .vertical)
                        .lineLimit(1...3)
                        .font(Tema.fuente(.destacado))
                        .focused($enTitulo)
                        .accessibilityLabel("Título")
                }
                switch tipo {
                case .evento: camposEvento
                case .tarea:
                    Section {
                        DatePicker("Día", selection: $inicio, displayedComponents: .date)
                    } footer: {
                        Text("Va a Pendientes con esa fecha.")
                    }
                case .recordatorio:
                    Section {
                        DatePicker("Cuándo", selection: $inicio, displayedComponents: [.date, .hourAndMinute])
                    } footer: {
                        Text("Va a Pendientes y te aviso por Telegram a esa hora.")
                    }
                }
                if let e = editando {
                    if let s = e.sincro, s.falla || s.pendiente {
                        Section {
                            Label(s.detalle, systemImage: s.falla ? "exclamationmark.icloud" : "arrow.triangle.2.circlepath")
                                .font(Tema.fuente(.pequeno))
                                .foregroundStyle(s.falla ? Tema.aviso : Tema.suave)
                        } header: {
                            Text("Copia en tus calendarios")
                        }
                    }
                    Section {
                        Button(role: .destructive) {
                            if e.repite.isEmpty { borra(e) } else { preguntaBorrar = true }
                        } label: {
                            Label(e.repite.isEmpty ? "Borrar evento" : "Borrar la serie", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Tema.fondo.ignoresSafeArea())
            .environment(\.locale, FechasES.locale)
            .navigationTitle(editando == nil ? "Nuevo" : "Evento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { cierra() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await guarda() } }
                        .disabled(vacio || guardando)
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog("Es un evento que se repite", isPresented: $preguntaBorrar, titleVisibility: .visible) {
                if let e = editando {
                    Button("Borrar todas las repeticiones", role: .destructive) { borra(e) }
                }
            } message: {
                Text("Se borra la serie entera, también de Google y de iCloud. Podrás deshacerlo un momento.")
            }
            .onAppear {
                if editando == nil { enTitulo = true }
                if cal.isEmpty { cal = datos.calendarios.first?.id ?? "" }
            }
            .onChange(of: inicio) { viejo, nuevo in
                // al mover el principio, el final se mueve lo mismo (como en cualquier calendario)
                fin = fin.addingTimeInterval(nuevo.timeIntervalSince(viejo))
            }
        }
        .tint(Tema.acento)
        .presentationDetents([.large])
    }

    @ViewBuilder private var camposEvento: some View {
        Section {
            Toggle("Todo el día", isOn: $todoElDia.animation(Tema.Muelle.toque))
            DatePicker("Empieza", selection: $inicio, displayedComponents: componentes)
            DatePicker("Acaba", selection: $fin, in: inicio..., displayedComponents: componentes)
        }
        Section {
            Picker("Calendario", selection: $cal) {
                ForEach(datos.calendarios) { c in
                    Label {
                        Text(c.n)
                    } icon: {
                        Image(systemName: "circle.fill").foregroundStyle(c.tinta)
                    }
                    .tag(c.id)
                }
            }
            Picker("Se repite", selection: $repite) {
                ForEach(UtilCal.repeticiones.indices, id: \.self) { i in
                    Text(UtilCal.repeticiones[i].nombre).tag(UtilCal.repeticiones[i].valor)
                }
            }
            if !repite.isEmpty {
                Toggle("Hasta una fecha", isOn: $conHasta.animation(Tema.Muelle.toque))
                if conHasta {
                    DatePicker("Hasta", selection: $hasta, in: inicio..., displayedComponents: .date)
                }
            }
            Picker("Aviso", selection: $aviso) {
                ForEach(UtilCal.avisos.indices, id: \.self) { i in
                    Text(UtilCal.avisos[i].nombre).tag(UtilCal.avisos[i].minutos)
                }
            }
        } footer: {
            if editando != nil && !repite.isEmpty {
                Text("Lo que cambies aquí cambia todas las repeticiones.")
            }
        }
        Section {
            TextField("Lugar", text: $lugar)
            TextField("Nota", text: $nota, axis: .vertical).lineLimit(2...6)
        }
    }

    private func borra(_ e: EventoCal) {
        cierra()
        Task { await datos.borraEvento(e) }
    }

    private func guarda() async {
        guard !vacio else { return }
        guardando = true
        defer { guardando = false }
        let t = titulo.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok: Bool
        switch tipo {
        case .tarea:
            ok = await datos.creaTarea(t, dia: UtilCal.dia(inicio), hora: "")
        case .recordatorio:
            ok = await datos.creaTarea(t, dia: UtilCal.dia(inicio), hora: UtilCal.hora(inicio))
        case .evento:
            var acaba = fin
            if !todoElDia && acaba <= inicio { acaba = inicio.addingTimeInterval(3600) }
            let dia = UtilCal.dia(inicio)
            let finDia = max(dia, UtilCal.dia(acaba))
            let campos: [String: Any] = [
                "t": t, "dia": dia, "fin_dia": finDia,
                "inicio": todoElDia ? "" : UtilCal.hora(inicio),
                "fin": todoElDia ? "" : UtilCal.hora(acaba),
                "cal": cal, "nota": nota.trimmingCharacters(in: .whitespacesAndNewlines),
                "lugar": lugar.trimmingCharacters(in: .whitespacesAndNewlines),
                "aviso": aviso, "repite": repite, "hasta": repite.isEmpty || !conHasta ? "" : UtilCal.dia(hasta),
            ]
            if let e = editando {
                ok = await datos.editaEvento(e.id, campos)
            } else {
                ok = await datos.creaEvento(campos)
            }
        }
        if ok { cierra() }
    }
}
