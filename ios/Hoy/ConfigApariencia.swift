import SwiftUI

// Configurar → Apariencia y Pantallas. Todo cambia al momento (Aspecto es @Observable) y se guarda en el servidor,
// así que la web lo coge también.

/// Configurar → Apariencia: vista previa, modo, paleta, acento, letra, esquinas y fondo.
struct SeccionApariencia: View {
    private var aspecto: Aspecto { Aspecto.shared }

    private func enlace(_ clave: WritableKeyPath<Eleccion, String>) -> Binding<String> {
        Binding(get: { Aspecto.shared.eleccion[keyPath: clave] },
                set: { v in Aspecto.shared.cambia { $0[keyPath: clave] = v } })
    }

    var body: some View {
        let cat = aspecto.catalogo
        let e = aspecto.eleccion
        Section {
            MuestraApariencia()
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            Picker("Modo", selection: enlace(\.modo)) {
                Text("Sistema").tag("sistema")
                Text("Claro").tag("claro")
                Text("Oscuro").tag("oscuro")
            }
            .pickerStyle(.segmented)
            if let cat {
                NavigationLink {
                    ElegirPaleta()
                } label: {
                    LabeledContent("Paleta", value: cat.paleta(e.paleta)?.nombre ?? e.paleta)
                }
                NavigationLink {
                    ElegirAcento()
                } label: {
                    LabeledContent("Acento", value: e.acento.isEmpty ? "El de la paleta" : (cat.acento(e.acento)?.nombre ?? e.acento))
                }
                NavigationLink {
                    ElegirFuente()
                } label: {
                    LabeledContent("Letra", value: cat.fuentes.first { $0.id == e.fuente }?.nombre ?? e.fuente)
                }
                Picker("Esquinas", selection: enlace(\.esquinas)) {
                    ForEach(cat.esquinas) { Text($0.nombre).tag($0.id) }
                }
                Picker("Fondo de caracteres", selection: enlace(\.fondo)) {
                    ForEach(cat.fondos) { Text($0.nombre).tag($0.id) }
                }
            } else {
                Text("Sin catálogo todavía: se baja la próxima vez que haya conexión.")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            }
            Button("Restablecer", role: .destructive) { Aspecto.shared.restablece() }
        } header: {
            Text("Apariencia")
        } footer: {
            Text("Se guarda en el servidor: la web cambia igual.")
        }
    }
}

/// Una carta de muestra: un hábito marcado, una cifra y un botón, con el tema actual.
struct MuestraApariencia: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            HStack(spacing: Tema.Espacio.m) {
                ZStack {
                    Circle().fill(Tema.acento)
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Tema.acentoTexto)
                }
                .frame(width: 24, height: 24)
                Text("Leer 20 min").font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                    .strikethrough(true, color: Tema.tenue)
                Spacer()
                Text("plan").estiloEtiqueta().foregroundStyle(Tema.acento)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Tema.acentoSuave, in: Capsule())
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pasos ayer").estiloEtiqueta().foregroundStyle(Tema.suave)
                    Text("8.430").font(Tema.fuente(.cifra)).monospacedDigit().foregroundStyle(Tema.texto)
                }
                Spacer()
                Text("Guardar")
                    .font(Tema.fuente(.destacado))
                    .foregroundStyle(Tema.acentoTexto)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Tema.acento, in: RoundedRectangle(cornerRadius: Tema.Radio.boton, style: .continuous))
            }
        }
        .carta(relleno: Tema.Espacio.m)
        .padding(Tema.Espacio.s)
        .background(Tema.fondo, in: RoundedRectangle(cornerRadius: Tema.Radio.carta + 6, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Vista previa de la apariencia")
    }
}

/// Las paletas en rejilla: cada muestra, mitad claro y mitad oscuro, con el punto de su acento.
struct ElegirPaleta: View {
    @State private var familia = "Todas"

    var body: some View {
        let aspecto = Aspecto.shared
        let cat = aspecto.catalogo
        let familias = ["Todas"] + Array(Set(cat?.paletas.map(\.familia) ?? [])).sorted()
        let paletas = (cat?.paletas ?? []).filter { familia == "Todas" || $0.familia == familia }
        let elegida = cat?.paleta(aspecto.eleccion.paleta)
        ScrollView {
            VStack(alignment: .leading, spacing: Tema.Espacio.l) {
                if let elegida {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(elegida.nombre).font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
                        if let d = elegida.descripcion { Text(d).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave) }
                    }
                    .contentTransition(.interpolate)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Tema.Espacio.s) {
                        ForEach(familias, id: \.self) { f in
                            Button(f) { withAnimation(Tema.Muelle.toque) { familia = f } }
                                .font(Tema.fuente(.pequeno, peso: .medium))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .foregroundStyle(familia == f ? Tema.acentoTexto : Tema.texto)
                                .background(familia == f ? Tema.acento : Tema.carta, in: Capsule())
                        }
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: Tema.Espacio.m)], spacing: Tema.Espacio.m) {
                    ForEach(paletas) { p in
                        Button {
                            Haptica.shared.toca(.marcar)
                            aspecto.cambia { $0.paleta = p.id }
                        } label: {
                            MuestraPaleta(paleta: p, acento: cat?.acento(p.acento), elegida: p.id == aspecto.eleccion.paleta)
                        }
                        .buttonStyle(EstiloHundir())
                    }
                }
            }
            .padding(Tema.Espacio.l)
        }
        .background(Tema.fondo.ignoresSafeArea())
        .navigationTitle("Paleta")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MuestraPaleta: View {
    let paleta: Catalogo.PaletaCat
    let acento: Catalogo.AcentoCat?
    let elegida: Bool

    private func c(_ s: String) -> Color { Color(uiColor: UIColor(css: s)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                mitad(paleta.claro, acento?.claro.acento)
                mitad(paleta.oscuro, acento?.oscuro.acento)
            }
            .frame(height: 64)
            .clipShape(RoundedRectangle(cornerRadius: Tema.Radio.boton, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Tema.Radio.boton, style: .continuous)
                .strokeBorder(elegida ? Tema.acento : Tema.linea, lineWidth: elegida ? 2.5 : 1))
            Text(paleta.nombre)
                .font(Tema.fuente(.pequeno, peso: elegida ? .semibold : .regular))
                .foregroundStyle(Tema.texto)
                .lineLimit(1)
        }
        .accessibilityLabel("\(paleta.nombre)\(elegida ? ", elegida" : "")")
    }

    private func mitad(_ t: Catalogo.Tonos, _ ac: String?) -> some View {
        ZStack(alignment: .bottomLeading) {
            c(t.fondo)
            RoundedRectangle(cornerRadius: 4).fill(c(t.carta)).frame(height: 22).padding(6).offset(y: -14)
            Circle().fill(c(ac ?? t.texto)).frame(width: 10, height: 10).padding(8)
        }
    }
}

/// Acento: «El de la paleta» o uno de la lista.
struct ElegirAcento: View {
    var body: some View {
        let aspecto = Aspecto.shared
        let cat = aspecto.catalogo
        List {
            Section {
                fila(nombre: "El de la paleta", claro: nil, oscuro: nil, elegido: aspecto.eleccion.acento.isEmpty) {
                    aspecto.cambia { $0.acento = "" }
                }
            }
            Section {
                ForEach(cat?.acentos ?? []) { a in
                    fila(nombre: a.nombre, claro: a.claro.acento, oscuro: a.oscuro.acento, elegido: aspecto.eleccion.acento == a.id) {
                        aspecto.cambia { $0.acento = a.id }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Tema.fondo.ignoresSafeArea())
        .navigationTitle("Acento")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func fila(nombre: String, claro: String?, oscuro: String?, elegido: Bool, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            HStack(spacing: Tema.Espacio.m) {
                if let claro, let oscuro {
                    HStack(spacing: -6) {
                        Circle().fill(Color(uiColor: UIColor(css: claro))).frame(width: 22, height: 22)
                        Circle().fill(Color(uiColor: UIColor(css: oscuro))).frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(Tema.carta, lineWidth: 2))
                    }
                } else {
                    Image(systemName: "paintpalette").foregroundStyle(Tema.acento).frame(width: 38)
                }
                Text(nombre).foregroundStyle(Tema.texto)
                Spacer()
                if elegido { Image(systemName: "checkmark").foregroundStyle(Tema.acento) }
            }
        }
        .listRowBackground(Tema.carta)
    }
}

/// Letra: cada nombre escrito en su propia fuente.
struct ElegirFuente: View {
    var body: some View {
        let aspecto = Aspecto.shared
        List {
            ForEach(aspecto.catalogo?.fuentes ?? []) { f in
                Button {
                    aspecto.cambia { $0.fuente = f.id }
                } label: {
                    HStack {
                        let familia = f.familia_ios ?? ""
                        Text(f.nombre)
                            .font(familia.isEmpty ? Font.system(size: 20) : Font.custom(familia, size: 20))
                            .foregroundStyle(Tema.texto)
                        Spacer()
                        if aspecto.eleccion.fuente == f.id { Image(systemName: "checkmark").foregroundStyle(Tema.acento) }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Tema.carta)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Tema.fondo.ignoresSafeArea())
        .navigationTitle("Letra")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Configurar → Pantallas: el orden de la barra de abajo y de los bloques de Hoy.
struct SeccionPantallas: View {
    var body: some View {
        Section {
            NavigationLink("Barra de abajo") {
                EditorBloques(pantalla: "app-dock", todos: Dock.entradas.map { ($0.clave, $0.nombre) }, fijos: ["hoy"])
                    .navigationTitle("Barra de abajo")
                    .navigationBarTitleDisplayMode(.inline)
            }
            NavigationLink("Hoy (app)") {
                EditorBloques(pantalla: "app-hoy", todos: PantallaHoy.bloques, fijos: [])
                    .navigationTitle("Hoy")
                    .navigationBarTitleDisplayMode(.inline)
            }
        } header: {
            Text("Pantallas")
        } footer: {
            Text("Arrastra para ordenar y apaga lo que no quieras ver. Se guarda en el servidor.")
        }
    }
}

/// Lista reordenable con interruptor para mostrar u ocultar cada elemento. Guarda en Aspecto a cada cambio.
struct EditorBloques: View {
    let pantalla: String
    let todos: [(String, String)]
    let fijos: Set<String>
    @State private var orden: [String] = []
    @State private var ocultos: Set<String> = []

    private func nombre(_ id: String) -> String { todos.first { $0.0 == id }?.1 ?? id }

    var body: some View {
        List {
            ForEach(orden, id: \.self) { id in
                Toggle(isOn: Binding(
                    get: { !ocultos.contains(id) },
                    set: { visible in
                        if visible { ocultos.remove(id) } else { ocultos.insert(id) }
                        guarda()
                    })) {
                    Text(nombre(id)).foregroundStyle(ocultos.contains(id) ? Tema.suave : Tema.texto)
                }
                .disabled(fijos.contains(id))
                .listRowBackground(Tema.carta)
            }
            .onMove { origen, destino in
                orden.move(fromOffsets: origen, toOffset: destino)
                guarda()
            }
        }
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
        .background(Tema.fondo.ignoresSafeArea())
        .onAppear {
            let b = Aspecto.shared.bloques(pantalla)
            orden = b.aplica(todos.map { $0.0 }, visibles: false)
            ocultos = Set(b.ocultos).subtracting(fijos)
        }
    }

    private func guarda() {
        Haptica.shared.toca(.marcar)
        Aspecto.shared.ponBloques(pantalla, Bloques(orden: orden, ocultos: orden.filter { ocultos.contains($0) }))
    }
}
