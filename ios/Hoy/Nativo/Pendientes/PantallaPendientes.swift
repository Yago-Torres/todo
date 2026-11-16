import SwiftUI
import UIKit

/// Pendientes en nativo (lo de static/pendientes.html): las tareas del vault con su día y su hora, «Leer luego», lo que
/// toca revisar y las notas recientes. Apuntar arriba, completar con un toque (o deslizando), posponer, cambiar y
/// borrar con «Deshacer». Sin red, los cambios van a la cola y se mandan al volver.
struct PantallaPendientes: View {
    enum Seccion: Hashable { case board, tareas, leer, vault }

    @State private var datos = DatosPendientes.shared
    @State private var seccion = Seccion.board
    @State private var columna = EstadoBoard.nueva
    @State private var proyecto = ""
    @State private var nuevaHistoria = false
    @State private var ficha: TareaVault?
    @State private var viendoHistorial = false
    @State private var busca = ""
    @State private var nueva = ""
    @State private var nuevaDia: String? = Fecha.hoy()
    @State private var nuevaHora: String?
    @State private var eligiendoCuando = false
    @State private var enviando = false
    @State private var editando: TareaVault?
    @State private var abiertos: Set<String> = []
    @FocusState private var escribiendo: Bool
    @ObservedObject private var navegador = Navegador.shared
    @Environment(\.openURL) private var abre

    var body: some View {
        VStack(spacing: Tema.Espacio.m) {
            cabecera
            apuntar
            CampoBusqueda(texto: $busca, pista: "Buscar en \(seccion == .board || seccion == .tareas ? "tareas" : seccion == .leer ? "Leer luego" : "el vault")")
                .padding(.horizontal, Tema.Espacio.l)
            SelectorPildoras(opciones: [(Seccion.board, "Board"),
                                        (Seccion.tareas, "Por fecha · \(datos.cuentaTareas)"),
                                        (Seccion.leer, "Leer luego · \(datos.bandeja?.leer.count ?? 0)"),
                                        (Seccion.vault, "Vault")],
                             seleccion: $seccion)
            if seccion == .board { controlesBoard }
            lista
        }
        .padding(.top, Tema.Espacio.s)
        .tostada(datos.aviso) { datos.quitaAviso() }
        .task { await datos.carga() }
        // «/pendientes.html?nueva=1» (el control «Apuntar una tarea»): directo al campo, tras entrar la pantalla
        .onChange(of: navegador.apuntarTarea, initial: true) { _, pedido in
            guard pedido else { return }
            navegador.apuntarTarea = false
            seccion = .tareas
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                escribiendo = true
            }
        }
        .environment(\.locale, FechasES.locale)
        .sheet(item: $editando) { t in
            HojaTarea(titulo: "Cambiar tarea", texto: t.t, dia: t.dia, hora: t.horaTexto,
                      alGuardar: { texto, dia, hora in await datos.edita(t, texto: texto, due: dia, hora: hora) },
                      alBorrar: { await datos.borra(t) })
        }
        .sheet(item: $ficha) { t in FichaBoard(tarea: t, datos: datos) }
        .sheet(isPresented: $viendoHistorial) { HistorialBoard() }
        .sheet(isPresented: $eligiendoCuando) {
            HojaTarea(titulo: "Cuándo", dia: nuevaDia, hora: nuevaHora, conTexto: false,
                      alGuardar: { _, dia, hora in
                          nuevaDia = dia
                          nuevaHora = hora
                      })
        }
    }

    // MARK: cabecera y apuntar

    private var cabecera: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.xs) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(datos.cuentaTareas == 0 ? "Todo al día" : datos.cuentaTareas == 1 ? "1 tarea" : "\(datos.cuentaTareas) tareas")
                        .estiloEtiqueta().foregroundStyle(Tema.suave)
                        .contentTransition(.numericText())
                    Text("Pendientes").font(Tema.fuente(.titulo)).foregroundStyle(Tema.texto)
                }
                Spacer()
                if datos.cargando && datos.bandeja == nil {
                    ProgressView().tint(Tema.suave)
                }
                if seccion == .board {
                    Button { viendoHistorial = true } label: {
                        Label("Historial", systemImage: "clock.arrow.circlepath")
                            .font(Tema.fuente(.pequeno, peso: .medium)).foregroundStyle(Tema.texto)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Tema.carta2, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            if let copia = datos.copia {
                Label(API.notaCopia(copia), systemImage: "wifi.slash")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.aviso)
            }
        }
        .padding(.horizontal, Tema.Espacio.l)
    }

    private var apuntar: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            TextField("Apuntar una tarea…", text: $nueva)
                .font(Tema.fuente(.destacado))
                .foregroundStyle(Tema.texto)
                .focused($escribiendo)
                .submitLabel(.done)
                .onSubmit { envia() }
                .accessibilityLabel("Qué tienes que hacer")
            HStack(spacing: Tema.Espacio.s) {
                Button {
                    escribiendo = false
                    eligiendoCuando = true
                } label: {
                    Label(Self.etiqueta(nuevaDia, nuevaHora), systemImage: "calendar")
                        .font(Tema.fuente(.pequeno, peso: .medium))
                        .foregroundStyle(Tema.texto)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Tema.carta2, in: Capsule())
                        .contentTransition(.interpolate)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cuándo: \(Self.etiqueta(nuevaDia, nuevaHora))")
                if seccion == .board {
                    Button {
                        Haptica.shared.toca(.marcar)
                        nuevaHistoria.toggle()
                    } label: {
                        Label("Historia", systemImage: nuevaHistoria ? "checkmark.circle.fill" : "circle")
                            .font(Tema.fuente(.pequeno, peso: .medium))
                            .foregroundStyle(nuevaHistoria ? Tema.acentoTexto : Tema.texto)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(nuevaHistoria ? Tema.acento : Tema.carta2, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(nuevaHistoria ? .isSelected : [])
                }
                Spacer()
                Button(action: envia) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Tema.acentoTexto)
                        .frame(width: 34, height: 34)
                        .background(nueva.trimmingCharacters(in: .whitespaces).isEmpty ? Tema.tenue : Tema.acento, in: Circle())
                }
                .disabled(nueva.trimmingCharacters(in: .whitespaces).isEmpty || enviando)
                .accessibilityLabel("Añadir tarea")
            }
        }
        .carta(relleno: Tema.Espacio.m)
        .padding(.horizontal, Tema.Espacio.l)
        .animation(Tema.Muelle.toque, value: nuevaDia)
    }

    private func envia() {
        guard !enviando, !nueva.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        enviando = true
        Haptica.shared.toca(.marcar)
        // en el board, con el proyecto filtrado (si hay) y en «Por hacer», que es donde aparece
        let enBoard = seccion == .board
        Task {
            if await datos.apunta(nueva, due: nuevaDia, hora: nuevaHora, tags: enBoard && !proyecto.isEmpty ? [proyecto] : [],
                                  historia: enBoard && nuevaHistoria) {
                nueva = ""
                nuevaDia = Fecha.hoy()
                nuevaHora = nil
                nuevaHistoria = false
                if enBoard { columna = .nueva }
            }
            enviando = false
        }
    }

    /// «Hoy · 10:00», «Mañana», «vie 14», «Sin fecha»
    static func etiqueta(_ dia: String?, _ hora: String?) -> String {
        guard let dia else { return "Sin fecha" }
        let n = FechasES.entre(Fecha.hoy(), dia)
        let d = n == 0 ? "Hoy" : n == 1 ? "Mañana" : FechasES.diaSemana(dia)
        return d + (hora.map { " · \($0)" } ?? "")
    }

    // MARK: la lista

    private var lista: some View {
        List {
            switch seccion {
            case .board: seccionBoard
            case .tareas: seccionTareas
            case .leer: seccionLeer
            case .vault: seccionVault
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .listSectionSpacing(Tema.Espacio.m)
        .contentMargins(.bottom, 110, for: .scrollContent)   // el hueco de la barra
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await datos.recarga() }
        .overlay { vacio }
        .animation(Tema.Muelle.pantalla, value: seccion)
    }

    @ViewBuilder private var vacio: some View {
        if !hayContenido && datos.bandeja != nil {
            VStack(spacing: Tema.Espacio.s) {
                Image(systemName: busca.isEmpty ? "checkmark.circle" : "magnifyingglass")
                    .font(.system(size: 34)).foregroundStyle(Tema.tenue)
                Text(busca.isEmpty ? textoVacio : "Nada con «\(busca)»")
                    .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                    .multilineTextAlignment(.center)
            }
            .padding(Tema.Espacio.xl)
            .allowsHitTesting(false)
        } else if datos.bandeja == nil, let error = datos.error {
            Text(error).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro).padding(Tema.Espacio.xl)
        }
    }

    private var hayContenido: Bool {
        switch seccion {
        case .board: return !tarjetas.isEmpty
        case .tareas: return !datos.grupos(buscando: busca).isEmpty || !datos.deProyectos(buscando: busca).isEmpty
        case .leer: return !lecturas.isEmpty
        case .vault: return !revisar.isEmpty || !notas.isEmpty
        }
    }

    private var textoVacio: String {
        switch seccion {
        case .board: return columna == .hecha ? "Lo que acabes este ciclo sale aquí." : "Nada en «\(columna.nombre)»."
        case .tareas: return "Nada pendiente. Apunta algo arriba o díselo a Tom."
        case .leer: return "Comparte un enlace desde Safari con «Leer luego» y aparece aquí, resumido."
        case .vault: return "Nada que revisar ni nada nuevo en las dos últimas semanas."
        }
    }

    // MARK: board

    @ViewBuilder private var controlesBoard: some View {
        SelectorPildoras(opciones: EstadoBoard.allCases.map { e in
                             (valor: e, titulo: "\(e.nombre) · \(datos.columna(e, proyecto: proyecto).count)") },
                         seleccion: $columna)
        if !datos.proyectos.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chipProyecto("", "Todos")
                    ForEach(datos.proyectos, id: \.self) { x in chipProyecto(x, BoardTexto.bonito(x)) }
                }
                .padding(.horizontal, Tema.Espacio.l)
            }
        }
        if let c = datos.bandeja?.ciclo {
            let quedan = FechasES.entre(Fecha.hoy(), c.hasta) + 1
            Text("Ciclo \(FechasES.corta(c.desde)) – \(FechasES.corta(c.hasta)) · \(quedan <= 1 ? "último día" : "quedan \(quedan) días")")
                .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Tema.Espacio.l)
        }
    }

    private func chipProyecto(_ valor: String, _ titulo: String) -> some View {
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

    private var tarjetas: [TareaVault] {
        datos.columna(columna, proyecto: proyecto).filter { $0.t.contieneBusqueda(busca) || ($0.nota ?? "").contieneBusqueda(busca) }
    }

    @ViewBuilder private var seccionBoard: some View {
        let ts = tarjetas
        if !ts.isEmpty {
            Section {
                ForEach(ts) { t in filaBoard(t) }
            } header: {
                Text("\(columna.nombre) · \(ts.count)").estiloEtiqueta()
                    .foregroundStyle(columna == .bloqueada ? Tema.peligro : Tema.suave)
            }
        }
    }

    private func filaBoard(_ t: TareaVault) -> some View {
        let fija = t.fija == true
        let padre = t.padre.flatMap { p in datos.todasBoard.first { $0.id == p }?.t }
        return FilaBoard(tarea: t, padre: padre, filtro: proyecto)
            .contentShape(Rectangle())
            .onTapGesture { ficha = t }
            .listRowBackground(Tema.carta)
            .listRowSeparatorTint(Tema.linea)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if let s = t.estadoBoard.siguiente(fija: fija) {
                    Button { Task { await datos.mueve(t, a: s) } } label: { Label(s.nombre, systemImage: s.icono) }
                        .tint(Tema.acento)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if !fija && t.estadoBoard != .bloqueada {
                    Button { Task { await datos.mueve(t, a: .bloqueada) } } label: { Label("Bloquear", systemImage: "hand.raised") }
                        .tint(Tema.peligro)
                }
            }
            .contextMenu {
                ForEach(EstadoBoard.allCases.filter { $0 != t.estadoBoard && !(fija && ($0 == .activa || $0 == .bloqueada)) }, id: \.self) { e in
                    Button { Task { await datos.mueve(t, a: e) } } label: { Label("Mover a \(e.nombre)", systemImage: e.icono) }
                }
                Button { ficha = t } label: { Label("Abrir", systemImage: "square.and.pencil") }
            }
    }

    // MARK: tareas

    @ViewBuilder private var seccionTareas: some View {
        ForEach(datos.grupos(buscando: busca)) { g in
            Section {
                ForEach(g.tareas) { t in fila(t) }
            } header: {
                Text("\(g.titulo) · \(g.tareas.count)")
                    .estiloEtiqueta().foregroundStyle(g.vencidas ? Tema.peligro : Tema.suave)
            }
        }
        ForEach(datos.deProyectos(buscando: busca)) { g in
            let abierto = abiertos.contains(g.id) || !busca.isEmpty
            Section {
                Button {
                    Haptica.shared.toca(.marcar)
                    withAnimation(Tema.Muelle.pantalla) {
                        if abiertos.contains(g.id) { abiertos.remove(g.id) } else { abiertos.insert(g.id) }
                    }
                } label: {
                    HStack {
                        Text(g.grupo == "Curro" ? "Del curro" : "De tus proyectos")
                            .font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
                        Text("· \(g.total)").font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.tenue)
                            .rotationEffect(.degrees(abierto ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Tema.carta)
                .accessibilityLabel("\(g.grupo == "Curro" ? "Del curro" : "De tus proyectos"), \(g.total) tareas")
                .accessibilityValue(abierto ? "Abierto" : "Plegado")
                if abierto {
                    ForEach(g.notas) { n in
                        Button {
                            if let url = n.abrir.flatMap(URL.init(string:)) { abre(url) }
                        } label: {
                            Label(n.nota, systemImage: "doc.text")
                                .font(Tema.fuente(.pequeno, peso: .semibold)).foregroundStyle(Tema.acento)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Tema.carta)
                        ForEach(n.tareas) { t in fila(t, conNota: false) }
                    }
                }
            }
        }
    }

    private func fila(_ t: TareaVault, conNota: Bool = true) -> some View {
        let fija = t.fija == true
        return FilaTarea(tarea: t, marcada: datos.marcadas.contains(t.id), conNota: conNota) {
            Task { await datos.hecha(t) }
        }
        .contentShape(Rectangle())
        .onTapGesture { if !fija { editando = t } }
        .listRowBackground(Tema.carta)
        .listRowSeparatorTint(Tema.linea)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { Task { await datos.hecha(t) } } label: { Label("Hecha", systemImage: "checkmark") }
                .tint(Tema.acento)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !fija {
                Button(role: .destructive) { Task { await datos.borra(t) } } label: { Label("Borrar", systemImage: "trash") }
                Button { Task { await datos.pospon(t, a: datos.manana(de: t)) } } label: {
                    Label("Mañana", systemImage: "arrow.turn.up.right")
                }
                .tint(Tema.aviso)
            }
        }
        .contextMenu {
            Button { Task { await datos.hecha(t) } } label: { Label("Marcar hecha", systemImage: "checkmark.circle") }
            if !fija {
                Button { editando = t } label: { Label("Cambiar", systemImage: "pencil") }
                Menu {
                    Button("Mañana") { Task { await datos.pospon(t, a: datos.manana(de: t)) } }
                    Button("Pasado mañana") { Task { await datos.pospon(t, a: FechasES.masDias(Fecha.hoy(), 2)) } }
                    Button("El lunes") { Task { await datos.pospon(t, a: HojaTarea.proximoLunes()) } }
                    Button("En una semana") { Task { await datos.pospon(t, a: FechasES.masDias(Fecha.hoy(), 7)) } }
                    if t.dia != nil {
                        Button("Quitar la fecha") { Task { await datos.pospon(t, a: nil) } }
                    }
                } label: {
                    Label("Posponer", systemImage: "calendar.badge.clock")
                }
                Button(role: .destructive) { Task { await datos.borra(t) } } label: { Label("Borrar", systemImage: "trash") }
            }
        }
    }

    // MARK: Leer luego

    private var lecturas: [LecturaVault] {
        (datos.bandeja?.leer ?? []).filter { $0.titulo.contieneBusqueda(busca) || ($0.resumen ?? "").contieneBusqueda(busca) }
    }

    @ViewBuilder private var seccionLeer: some View {
        if !lecturas.isEmpty {
            Section {
                ForEach(lecturas) { l in
                    FilaLectura(lectura: l)
                        .contentShape(Rectangle())
                        .onTapGesture { abreLectura(l) }
                        .listRowBackground(Tema.carta)
                        .listRowSeparatorTint(Tema.linea)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button { Task { await datos.leido(l) } } label: { Label("Leído", systemImage: "checkmark") }
                                .tint(Tema.acento)
                        }
                        .contextMenu {
                            if let url = l.url.flatMap(URL.init(string:)), !(l.url ?? "").isEmpty {
                                Button { abre(url) } label: { Label("Abrir el enlace", systemImage: "safari") }
                                ShareLink(item: url) { Label("Compartir", systemImage: "square.and.arrow.up") }
                            }
                            if let nota = l.abrir.flatMap(URL.init(string:)) {
                                Button { abre(nota) } label: { Label("Abrir la nota", systemImage: "doc.text") }
                            }
                            Button { Task { await datos.leido(l) } } label: { Label("Marcar leído", systemImage: "checkmark.circle") }
                        }
                }
            } header: {
                Text("Sin leer · \(lecturas.count)").estiloEtiqueta().foregroundStyle(Tema.suave)
            }
        }
    }

    private func abreLectura(_ l: LecturaVault) {
        Haptica.shared.toca(.marcar)
        if let u = l.url, !u.isEmpty, let url = URL(string: u) { abre(url) }
        else if let url = l.abrir.flatMap(URL.init(string:)) { abre(url) }
    }

    // MARK: vault

    private var revisar: [RevisarVault] {
        (datos.bandeja?.revisar ?? []).filter { !$0.ruta.hasPrefix("Recursos/Leer luego/") && $0.titulo.contieneBusqueda(busca) }
    }

    private var notas: [NotaVault] {
        (datos.bandeja?.notas ?? []).filter { $0.titulo.contieneBusqueda(busca) || ($0.extracto ?? "").contieneBusqueda(busca) }
    }

    @ViewBuilder private var seccionVault: some View {
        if !revisar.isEmpty {
            Section {
                ForEach(revisar) { r in
                    Button {
                        if let url = r.abrir.flatMap(URL.init(string:)) { abre(url) }
                    } label: {
                        HStack {
                            Text(r.titulo).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto).lineLimit(2)
                            Spacer(minLength: Tema.Espacio.s)
                            if let rv = r.review, !rv.isEmpty {
                                Text("desde \(FechasES.corta(rv))").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.aviso)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Tema.carta)
                    .listRowSeparatorTint(Tema.linea)
                }
            } header: {
                Text("Para revisar · \(revisar.count)").estiloEtiqueta().foregroundStyle(Tema.aviso)
            }
        }
        if !notas.isEmpty {
            Section {
                ForEach(notas) { n in
                    Button {
                        if let url = n.abrir.flatMap(URL.init(string:)) { abre(url) }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(n.titulo).font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto).lineLimit(2)
                            HStack(spacing: Tema.Espacio.s) {
                                if let tipo = n.tipo, !tipo.isEmpty {
                                    Text(tipo).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.acento)
                                        .padding(.horizontal, 8).padding(.vertical, 2)
                                        .background(Tema.acentoSuave, in: Capsule())
                                }
                                if let c = n.cambio, !c.isEmpty {
                                    Text(FechasES.hace(c)).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                                }
                            }
                            if let e = n.extracto, !e.isEmpty {
                                Text(e).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).lineLimit(3)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Tema.carta)
                    .listRowSeparatorTint(Tema.linea)
                }
            } header: {
                Text("Lo último en tu vault").estiloEtiqueta().foregroundStyle(Tema.suave)
            }
        }
    }
}

// MARK: filas

private struct FilaTarea: View {
    let tarea: TareaVault
    let marcada: Bool
    let conNota: Bool
    let alMarcar: () -> Void

    private var dias: Int? { tarea.dia.map { FechasES.entre(Fecha.hoy(), $0) } }

    var body: some View {
        HStack(alignment: .top, spacing: Tema.Espacio.m) {
            Button(action: alMarcar) {
                Image(systemName: marcada ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(marcada ? Tema.acento : Tema.tenue)
                    .symbolEffect(.bounce, value: marcada)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Marcar hecha: \(tarea.t)")
            VStack(alignment: .leading, spacing: 2) {
                Text(tarea.t)
                    .font(Tema.fuente(.texto))
                    .foregroundStyle(marcada ? Tema.suave : Tema.texto)
                    .strikethrough(marcada, color: Tema.suave)
                    .multilineTextAlignment(.leading)
                if conNota, tarea.grupo != "Pendientes", let nota = tarea.nota, !nota.isEmpty {
                    Text(nota).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).lineLimit(1)
                }
            }
            Spacer(minLength: Tema.Espacio.s)
            if let dia = tarea.dia {
                let color = (dias ?? 0) < 0 ? Tema.peligro : (dias ?? 0) == 0 ? Tema.acento : Tema.suave
                Text(FechasES.cuando(dia) + (tarea.horaTexto.map { " \($0)" } ?? ""))
                    .font(Tema.fuente(.pequeno, peso: .medium))
                    .foregroundStyle(color)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(color.opacity(0.12), in: Capsule())
                    .fixedSize()
            }
        }
        .padding(.vertical, 2)
        .animation(Tema.Muelle.toque, value: marcada)
    }
}

private struct FilaLectura: View {
    let lectura: LecturaVault

    private var tocaHoy: Bool {
        if let r = lectura.review, !r.isEmpty { return r <= Fecha.hoy() }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(lectura.titulo).font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto).lineLimit(2)
            HStack(spacing: 6) {
                if let m = lectura.minutos, m > 0 { Text("\(m) min"); Text("·") }
                if let g = lectura.guardado, !g.isEmpty { Text("guardado \(FechasES.hace(g))") }
                if tocaHoy {
                    Text("toca hoy").foregroundStyle(Tema.aviso)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Tema.aviso.opacity(0.14), in: Capsule())
                }
            }
            .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            if let r = lectura.resumen, !r.isEmpty {
                Text(r).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}
