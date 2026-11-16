import SwiftUI
import UIKit

// El board de Pendientes (lo de static/pendientes.html): las tareas del vault por estado (por hacer, activa, bloqueada,
// hecha), con su proyecto (#etiqueta, o la nota de Proyectos/ de donde salen) y sus historias (una tarea con subtareas).
// En el iPhone cada columna es una píldora; deslizar una tarjeta la pasa a la siguiente. Cada 3 semanas la columna
// «Hecha» se vacía en el servidor y lo suyo queda en el historial.

enum EstadoBoard: String, CaseIterable, Hashable {
    case nueva, activa, bloqueada, hecha

    var nombre: String {
        switch self {
        case .nueva: return "Por hacer"
        case .activa: return "Activa"
        case .bloqueada: return "Bloqueada"
        case .hecha: return "Hecha"
        }
    }

    var icono: String {
        switch self {
        case .nueva: return "circle"
        case .activa: return "play.circle"
        case .bloqueada: return "hand.raised"
        case .hecha: return "checkmark.circle"
        }
    }

    /// A dónde va al deslizar. Lo del curro no se activa ni se bloquea: solo se tacha.
    func siguiente(fija: Bool) -> EstadoBoard? {
        switch self {
        case .nueva: return fija ? .hecha : .activa
        case .activa, .bloqueada: return fija ? .hecha : (self == .activa ? .hecha : .activa)
        case .hecha: return nil
        }
    }
}

extension TareaVault {
    var estadoBoard: EstadoBoard { EstadoBoard(rawValue: estado ?? "") ?? .nueva }
    var etiquetas: [String] { tags ?? [] }
    var esHistoria: Bool { historia == true }
}

enum BoardTexto {
    /// «Raspberry-Pi» → «Raspberry Pi»: en Obsidian una etiqueta no lleva espacios.
    static func bonito(_ x: String) -> String {
        x.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
    }

    static func partes(_ s: String) -> [String] {
        s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

struct CicloBoard: Codable, Hashable {
    var desde: String
    var hasta: String
}

struct CicloHistorial: Codable, Identifiable, Hashable {
    var desde: String
    var hasta: String
    var tareas: [TareaVault]

    var id: String { desde }
}

// MARK: la tarjeta

struct FilaBoard: View {
    let tarea: TareaVault
    /// El título de su historia, si es una subtarea.
    let padre: String?
    /// El proyecto filtrado: no se repite en cada tarjeta.
    let filtro: String

    private var hecha: Bool { tarea.estadoBoard == .hecha }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if tarea.esHistoria {
                HStack(spacing: 6) {
                    Text("Historia").foregroundStyle(Tema.acento)
                    if let p = tarea.progreso, p.count == 2, p[1] > 0 {
                        Text("\(p[0])/\(p[1])").foregroundStyle(Tema.suave).monospacedDigit()
                    }
                }
                .font(Tema.fuente(.pequeno, peso: .semibold))
            } else if let padre {
                Text("↳ \(padre)").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).lineLimit(1)
            }
            Text(tarea.t)
                .font(Tema.fuente(.texto))
                .foregroundStyle(hecha ? Tema.suave : Tema.texto)
                .strikethrough(hecha, color: Tema.suave)
                .multilineTextAlignment(.leading)
            if tarea.esHistoria, let p = tarea.progreso, p.count == 2, p[1] > 0 {
                ProgressView(value: Double(p[0]), total: Double(p[1])).tint(Tema.acento)
            }
            let tags = tarea.etiquetas.filter { $0 != filtro }
            if !tags.isEmpty || tarea.dia != nil || tarea.grupo == "Curro" {
                HStack(spacing: 6) {
                    ForEach(Array(tags.prefix(3)), id: \.self) { x in
                        Text(BoardTexto.bonito(x))
                            .font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.suave)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Tema.carta2, in: Capsule())
                    }
                    if tarea.grupo == "Curro" {
                        Text("curro").font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.suave)
                    }
                    Spacer(minLength: 0)
                    if let dia = tarea.dia, !hecha {
                        let n = FechasES.entre(Fecha.hoy(), dia)
                        Text(FechasES.cuando(dia) + (tarea.horaTexto.map { " \($0)" } ?? ""))
                            .font(Tema.fuente(.pequeno, peso: .medium))
                            .foregroundStyle(n < 0 ? Tema.peligro : n == 0 ? Tema.acento : Tema.suave)
                    }
                }
                .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint("\(tarea.estadoBoard.nombre). Toca para abrirla, desliza para moverla")
    }
}

// MARK: la ficha

struct FichaBoard: View {
    let tarea: TareaVault
    let datos: DatosPendientes

    @Environment(\.dismiss) private var cierra
    @Environment(\.openURL) private var abre
    @State private var texto: String
    @State private var proyectos: String
    @State private var conFecha: Bool
    @State private var fecha: Date
    @State private var nuevaSub = ""
    @State private var confirmaBorrar = false

    init(tarea: TareaVault, datos: DatosPendientes) {
        self.tarea = tarea
        self.datos = datos
        _texto = State(initialValue: tarea.t)
        _proyectos = State(initialValue: tarea.etiquetas.map(BoardTexto.bonito).joined(separator: ", "))
        _conFecha = State(initialValue: tarea.dia != nil)
        _fecha = State(initialValue: tarea.dia.flatMap(FechasES.fecha) ?? Date())
    }

    private var fija: Bool { tarea.fija == true }
    private var hijas: [TareaVault] { datos.todasBoard.filter { $0.padre == tarea.id } }
    private var padre: TareaVault? { tarea.padre.flatMap { p in datos.todasBoard.first { $0.id == p } } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Título", text: $texto, axis: .vertical)
                        .font(Tema.fuente(.destacado))
                        .disabled(fija)
                    Picker("Estado", selection: Binding(get: { tarea.estadoBoard }, set: { e in
                        cierra()
                        Task { await datos.mueve(tarea, a: e) }
                    })) {
                        ForEach(EstadoBoard.allCases, id: \.self) { e in
                            Text(e.nombre).tag(e)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    if let padre { Text("Tarea de «\(padre.t)»") }
                }
                if !fija {
                    Section("Proyectos") {
                        TextField("todo, casa…", text: $proyectos)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Section {
                        Toggle("Con fecha", isOn: $conFecha.animation())
                        if conFecha {
                            DatePicker("Día", selection: $fecha, displayedComponents: .date)
                        }
                    }
                }
                if tarea.esHistoria || !hijas.isEmpty {
                    Section("Tareas · \(hijas.filter { $0.estadoBoard == .hecha }.count)/\(hijas.count)") {
                        ForEach(hijas) { h in
                            HStack {
                                Text(h.t)
                                    .strikethrough(h.estadoBoard == .hecha)
                                    .foregroundStyle(h.estadoBoard == .hecha ? Tema.suave : Tema.texto)
                                Spacer()
                                Text(h.estadoBoard.nombre).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                            }
                        }
                        if !fija && tarea.estadoBoard != .hecha {
                            HStack {
                                TextField("Nueva tarea de esta historia", text: $nuevaSub)
                                    .submitLabel(.done)
                                    .onSubmit(anadeSub)
                                Button("Añadir", action: anadeSub)
                                    .disabled(nuevaSub.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                    }
                }
                Section {
                    if let url = tarea.abrir.flatMap(URL.init(string:)) {
                        Button { abre(url) } label: {
                            Label("Abrir «\(tarea.nota ?? "la nota")» en Obsidian", systemImage: "doc.text")
                        }
                    }
                    if !fija {
                        Button(role: .destructive) { confirmaBorrar = true } label: { Label("Borrar", systemImage: "trash") }
                    }
                } footer: {
                    if fija { Text("Del curro: aquí solo se tacha.") }
                }
            }
            .navigationTitle(tarea.esHistoria ? "Historia" : "Tarea")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { cierra() }
                }
                if !fija {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Guardar", action: guarda)
                            .disabled(texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .confirmationDialog("¿Borrar «\(tarea.t)»?", isPresented: $confirmaBorrar, titleVisibility: .visible) {
                Button("Borrar", role: .destructive) {
                    cierra()
                    Task { await datos.borra(tarea) }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func guarda() {
        let antes = tarea.etiquetas.map(BoardTexto.bonito).joined(separator: ", ")
        // si no toca los proyectos, no se mandan: el servidor deja los que tenía
        let tags: [String]? = proyectos == antes ? nil : BoardTexto.partes(proyectos)
        let dia = conFecha ? Fecha.dia(fecha) : nil
        cierra()
        Task { await datos.edita(tarea, texto: texto, due: dia, hora: conFecha ? tarea.horaTexto : nil, tags: tags) }
    }

    private func anadeSub() {
        let x = nuevaSub.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !x.isEmpty else { return }
        nuevaSub = ""
        cierra()
        Task {
            if await datos.apunta(x, due: nil, hora: nil, padre: tarea.id) { await datos.recarga() }
        }
    }
}

// MARK: el historial

struct HistorialBoard: View {
    @Environment(\.dismiss) private var cierra
    @State private var ciclos: [CicloHistorial]?
    @State private var error: String?

    private struct Respuesta: Decodable { var ciclos: [CicloHistorial] }

    var body: some View {
        NavigationStack {
            List {
                if let ciclos {
                    if ciclos.isEmpty {
                        Text("Todavía no ha acabado ningún ciclo.").foregroundStyle(Tema.suave)
                    }
                    ForEach(ciclos) { c in
                        Section {
                            ForEach(c.tareas) { t in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.t).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                                    Text(([t.hecha_el.map { FechasES.corta($0) } ?? ""] + t.etiquetas.map(BoardTexto.bonito))
                                            .filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                                }
                            }
                        } header: {
                            Text("\(FechasES.corta(c.desde)) – \(FechasES.corta(c.hasta)) · \(c.tareas.count) hechas")
                        }
                    }
                } else if let error {
                    Text(error).foregroundStyle(Tema.peligro)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Historial")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { cierra() }
                }
            }
            .task { await carga() }
        }
    }

    private func carga() async {
        do {
            let (crudo, _) = try await API.leeOCopia("/api/tablero/historial")
            ciclos = try JSONDecoder().decode(Respuesta.self, from: crudo).ciclos
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: el board en horizontal

/// Pide a iOS otra orientación (con AppDelegate.giro) y gira ya, sin esperar a que se mueva el móvil.
@MainActor enum Giro {
    static func pon(_ m: UIInterfaceOrientationMask) {
        AppDelegate.giro = m
        guard let escena = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        var vc = escena.keyWindow?.rootViewController
        while let v = vc {
            v.setNeedsUpdateOfSupportedInterfaceOrientations()
            vc = v.presentedViewController
        }
        escena.requestGeometryUpdate(.iOS(interfaceOrientations: m)) { _ in }
    }
}

/// Mover a otra columna, para los menús de la lista y del board. Lo del curro no se activa ni se bloquea.
struct MenuMover: View {
    let tarea: TareaVault
    let datos: DatosPendientes

    var body: some View {
        let fija = tarea.fija == true
        ForEach(EstadoBoard.allCases.filter { $0 != tarea.estadoBoard && !(fija && ($0 == .activa || $0 == .bloqueada)) },
                id: \.self) { e in
            Button { Task { await datos.mueve(tarea, a: e) } } label: { Label("Mover a \(e.nombre)", systemImage: e.icono) }
        }
    }
}

/// El board entero, a pantalla completa y en horizontal: las cuatro columnas a la vez, arrastrar una tarjeta de
/// una a otra (o mantenerla pulsada → «Mover a»), tocarla para su ficha. Al cerrar, la app vuelve a vertical.
struct BoardHorizontal: View {
    let datos: DatosPendientes
    @Environment(\.dismiss) private var cierra
    @State private var proyecto = ""
    @State private var ficha: TareaVault?
    @State private var viendoHistorial = false
    @State private var encima: EstadoBoard?

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            HStack(spacing: Tema.Espacio.s) {
                Button { cierra() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(Tema.texto)
                        .frame(width: 34, height: 34)
                        .background(Tema.carta2, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cerrar el board")
                VStack(alignment: .leading, spacing: 0) {
                    Text("Board").font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
                    if let c = datos.bandeja?.ciclo {
                        Text("Ciclo \(FechasES.corta(c.desde)) – \(FechasES.corta(c.hasta))")
                            .font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.suave)
                    }
                }
                .fixedSize()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip("", "Todos")
                        ForEach(datos.proyectos, id: \.self) { x in chip(x, BoardTexto.bonito(x)) }
                    }
                }
                Button { viendoHistorial = true } label: {
                    Label("Historial", systemImage: "clock.arrow.circlepath")
                        .font(Tema.fuente(.pequeno, peso: .medium)).foregroundStyle(Tema.texto)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Tema.carta2, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            HStack(alignment: .top, spacing: Tema.Espacio.s) {
                ForEach(EstadoBoard.allCases, id: \.self) { e in columna(e) }
            }
        }
        .padding(.horizontal, Tema.Espacio.m)
        .padding(.top, Tema.Espacio.s)
        .background(Tema.fondo.ignoresSafeArea())
        .environment(\.locale, FechasES.locale)
        .sheet(item: $ficha) { t in FichaBoard(tarea: t, datos: datos) }
        .sheet(isPresented: $viendoHistorial) { HistorialBoard() }
        .onAppear { Giro.pon(.landscape) }
        .onDisappear { Giro.pon(.portrait) }
    }

    private func chip(_ valor: String, _ titulo: String) -> some View {
        let activo = proyecto == valor
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(Tema.Muelle.pantalla) { proyecto = valor }
        } label: {
            Text(titulo)
                .font(Tema.fuente(.pequeno, peso: .medium))
                .foregroundStyle(activo ? Tema.acentoTexto : Tema.texto)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(activo ? Tema.acento : Tema.carta, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(activo ? .isSelected : [])
    }

    private func columna(_ e: EstadoBoard) -> some View {
        let ts = datos.columna(e, proyecto: proyecto)
        let forma = RoundedRectangle(cornerRadius: Tema.Radio.carta, style: .continuous)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: e.icono)
                Text(e.nombre)
                Spacer()
                Text("\(ts.count)").monospacedDigit()
            }
            .font(Tema.fuente(.pequeno, peso: .semibold))
            .foregroundStyle(e == .bloqueada ? Tema.peligro : Tema.suave)
            .padding(.horizontal, 4)
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(ts) { t in tarjeta(t) }
                    if ts.isEmpty {
                        Text(e == .hecha ? "Lo que acabes este ciclo." : "Nada.")
                            .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.tenue)
                            .frame(maxWidth: .infinity).padding(.vertical, Tema.Espacio.m)
                    }
                }
                .padding(.bottom, Tema.Espacio.m)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Tema.carta2, in: forma)
        .overlay { if encima == e { forma.stroke(Tema.acento, lineWidth: 2) } }
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first, let t = datos.todasBoard.first(where: { $0.id == id }), t.estadoBoard != e,
                  !(t.fija == true && (e == .activa || e == .bloqueada)) else { return false }
            Haptica.shared.toca(.marcar)
            Task { await datos.mueve(t, a: e) }
            return true
        } isTargeted: { dentro in
            if dentro { encima = e } else if encima == e { encima = nil }
        }
    }

    private func tarjeta(_ t: TareaVault) -> some View {
        let padre = t.padre.flatMap { p in datos.todasBoard.first { $0.id == p }?.t }
        return FilaBoard(tarea: t, padre: padre, filtro: proyecto)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tema.carta, in: RoundedRectangle(cornerRadius: Tema.Radio.celda, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { ficha = t }
            .draggable(t.id)
            .contextMenu {
                MenuMover(tarea: t, datos: datos)
                Button { ficha = t } label: { Label("Abrir", systemImage: "square.and.pencil") }
            }
    }
}
