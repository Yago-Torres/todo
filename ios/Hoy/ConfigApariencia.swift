import SwiftUI

// Configurar → Apariencia y Pantallas. Todo cambia al momento (Aspecto es @Observable) y se guarda en el servidor,
// así que la web lo coge también.

/// "#RRGGBB" de un Color (lo que devuelve el ColorPicker).
private func hexDe(_ c: Color) -> String {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
    func canal(_ x: CGFloat) -> Int { Int((max(0, min(1, x)) * 255).rounded()) }
    return String(format: "#%02X%02X%02X", canal(r), canal(g), canal(b))
}

private func colorDe(_ css: String) -> Color { Color(uiColor: UIColor(css: css)) }

/// Configurar → Apariencia: vista previa y la rejilla de temas (al estilo monkeytype).
struct SeccionApariencia: View {
    var body: some View {
        let aspecto = Aspecto.shared
        let temas = aspecto.catalogo?.temas ?? []
        Section {
            MuestraApariencia()
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            if temas.isEmpty {
                Text("Sin catálogo de temas todavía: se baja la próxima vez que haya conexión.")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(temas) { t in
                        Button {
                            Haptica.shared.toca(.marcar)
                            aspecto.eligeTema(t)
                        } label: {
                            TarjetaTema(tema: t, elegido: aspecto.eleccion.tema == t.id)
                        }
                        .buttonStyle(EstiloHundir())
                    }
                }
                .padding(.vertical, 6)
            }
        } header: {
            Text("Apariencia")
        } footer: {
            Text(aspecto.eleccion.tema == "propio" ? "Tema propio: lo has personalizado abajo." : "Se guarda en el servidor: la web cambia igual.")
        }
        SeccionPersonalizar()
    }
}

/// Un tema: su nombre en su letra de títulos, sus colores en claro y oscuro y su vibra.
struct TarjetaTema: View {
    let tema: Catalogo.TemaCat
    let elegido: Bool

    var body: some View {
        let g = Oklch.genera(base: tema.base, acento: tema.acento)
        let familia = Aspecto.shared.familia(tema.titulos ?? tema.fuente)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                mitad(g.claro)
                mitad(g.oscuro)
            }
            .frame(height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(tema.nombre)
                .font(familia.map { Font.custom($0, size: 17).weight(.bold) } ?? Font.system(size: 17, weight: .bold))
                .foregroundStyle(Tema.texto)
                .lineLimit(1)
            if let v = tema.vibra {
                Text(v).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Tema.fondo, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(elegido ? Tema.acento : Tema.linea, lineWidth: elegido ? 2.5 : 1))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(elegido ? .isSelected : [])
    }

    private func mitad(_ l: Oklch.Lado) -> some View {
        ZStack(alignment: .bottomLeading) {
            colorDe(l.fondo)
            RoundedRectangle(cornerRadius: 3).fill(colorDe(l.carta)).frame(height: 14).padding(5).offset(y: -12)
            Circle().fill(colorDe(l.acento)).frame(width: 10, height: 10).padding(6)
        }
    }
}

/// «Personalizar»: fondo y acento libres (con sugerencias), letras, esquinas, fondo de caracteres y modo.
struct SeccionPersonalizar: View {
    private func enlace(_ clave: WritableKeyPath<Eleccion, String>) -> Binding<String> {
        Binding(get: { Aspecto.shared.eleccion[keyPath: clave] },
                set: { v in Aspecto.shared.cambia { $0[keyPath: clave] = v } })
    }

    private func color(_ clave: WritableKeyPath<Eleccion, String>) -> Binding<Color> {
        Binding(get: { colorDe(Aspecto.shared.eleccion[keyPath: clave]) },
                set: { c in
                    let h = hexDe(c)
                    Aspecto.shared.cambia { $0[keyPath: clave] = h }
                })
    }

    var body: some View {
        let aspecto = Aspecto.shared
        let cat = aspecto.catalogo
        let e = aspecto.eleccion
        Section {
            ColorPicker("Fondo", selection: color(\.base), supportsOpacity: false)
            if let s = cat?.sugerencias?.base { sugerencias(s, elegido: e.base, clave: \.base) }
            ColorPicker("Acento", selection: color(\.acento), supportsOpacity: false)
            if let s = cat?.sugerencias?.acento { sugerencias(s, elegido: e.acento, clave: \.acento) }
            NavigationLink {
                ElegirFuente(clave: \.fuente, titulo: "Letra")
            } label: {
                LabeledContent("Letra", value: cat?.fuente(e.fuente)?.nombre ?? e.fuente)
            }
            NavigationLink {
                ElegirFuente(clave: \.titulos, titulo: "Títulos")
            } label: {
                LabeledContent("Títulos", value: cat?.fuente(e.titulos)?.nombre ?? e.titulos)
            }
            if let cat {
                Picker("Esquinas", selection: enlace(\.esquinas)) {
                    ForEach(cat.esquinas) { Text($0.nombre).tag($0.id) }
                }
                Picker("Fondo de caracteres", selection: enlace(\.fondo)) {
                    ForEach(cat.fondos) { Text($0.nombre).tag($0.id) }
                }
            }
            Picker("Modo", selection: enlace(\.modo)) {
                Text("Sistema").tag("sistema")
                Text("Claro").tag("claro")
                Text("Oscuro").tag("oscuro")
            }
            .pickerStyle(.segmented)
            Button("Restablecer", role: .destructive) { Aspecto.shared.restablece() }
        } header: {
            Text("Personalizar")
        } footer: {
            Text("Con el fondo y el acento se calculan todos los colores de claro y oscuro, igual que en la web.")
        }
    }

    private func sugerencias(_ lista: [String], elegido: String, clave: WritableKeyPath<Eleccion, String>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(lista, id: \.self) { hex in
                    Button {
                        Haptica.shared.toca(.marcar)
                        Aspecto.shared.cambia { $0[keyPath: clave] = hex }
                    } label: {
                        Circle().fill(colorDe(hex))
                            .frame(width: 28, height: 28)
                            .overlay(Circle().strokeBorder(Tema.linea, lineWidth: 1))
                            .overlay(Circle().strokeBorder(Tema.acento, lineWidth: hex.uppercased() == elegido.uppercased() ? 2.5 : 0).padding(-4))
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(hex)
                }
            }
        }
    }
}

/// Una carta de muestra: un hábito marcado, una cifra y un botón, con el tema actual.
struct MuestraApariencia: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            Text("Hoy").font(Tema.fuente(.titulo)).foregroundStyle(Tema.texto)
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
            .carta(relleno: Tema.Espacio.m)
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
            .carta(relleno: Tema.Espacio.m)
        }
        .padding(Tema.Espacio.m)
        .background(Tema.fondo, in: RoundedRectangle(cornerRadius: Tema.Radio.carta + 6, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Vista previa de la apariencia")
    }
}

/// Letra o títulos: cada nombre escrito en su propia fuente.
struct ElegirFuente: View {
    let clave: WritableKeyPath<Eleccion, String>
    let titulo: String

    var body: some View {
        let aspecto = Aspecto.shared
        List {
            ForEach(aspecto.catalogo?.fuentes ?? []) { f in
                Button {
                    aspecto.cambia { $0[keyPath: clave] = f.id }
                } label: {
                    HStack {
                        let familia = f.familia_ios ?? ""
                        Text(f.nombre)
                            .font(familia.isEmpty ? Font.system(size: 20) : Font.custom(familia, size: 20))
                            .foregroundStyle(Tema.texto)
                        Spacer()
                        if aspecto.eleccion[keyPath: clave] == f.id { Image(systemName: "checkmark").foregroundStyle(Tema.acento) }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Tema.carta)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Tema.fondo.ignoresSafeArea())
        .navigationTitle(titulo)
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
