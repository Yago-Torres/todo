import SwiftUI

/// Qué pantallas nativas se pueden editar (orden y ocultos de sus bloques) y con qué ids. Configurar → Pantallas lee de
/// aquí. Una pantalla nueva que use `PantallaEditable` añade su línea en `bloques` (clave «app-<seccion>»); las que no
/// estén salen en Configurar desactivadas, con «pronto».
enum PantallasEditables {
    /// clave de la disposición («app-entreno») → [(id estable del bloque, nombre que se ve)].
    static var bloques: [String: [(String, String)]] = [
        "app-hoy": PantallaHoy.bloques,
        // ← cada pantalla nueva con PantallaEditable, aquí
    ]

    /// Lo registra la propia pantalla al aparecer, por si se olvidó la línea de arriba (sirve a partir de entonces).
    static func registra(_ pantalla: String, _ lista: [(String, String)]) {
        if bloques[pantalla] == nil { bloques[pantalla] = lista }
    }

    /// Las pantallas nativas del registro, con su clave de disposición y su nombre (el de la barra de abajo).
    static func registradas() -> [(clave: String, nombre: String, ruta: String)] {
        RegistroNativo.pantallas.compactMap { p in
            guard let e = Dock.entradas.first(where: { $0.href == p.ruta }) else { return nil }
            return ("app-" + e.clave, e.nombre, p.ruta)
        }
    }
}

private struct EditarPantallaClave: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    /// Entra en el modo edición de la `PantallaEditable` que contiene esta vista (para un botón propio dentro de un bloque).
    var editarPantalla: () -> Void {
        get { self[EditarPantallaClave.self] }
        set { self[EditarPantallaClave.self] = newValue }
    }
}

/// El contenedor de una pantalla nativa con bloques que se ordenan y se esconden (Configurar → Pantallas, o «Editar»
/// en la propia pantalla, o mantener pulsado un bloque). Pinta la cabecera, los bloques en el orden guardado en la
/// disposición `pantalla` («app-<seccion>») y, al editar, la lista con asas e interruptores. Ver ios/README.md.
///
///     PantallaEditable(pantalla: "app-entreno", titulo: "Entreno", bloques: [("plan", "Plan"), ("serie", "Series")],
///                      recarga: { await datos.recarga() }) { editar in
///         Cabecera(editar: editar)
///     } bloque: { id in
///         switch id { case "plan": Plan(); case "serie": Series(); default: EmptyView() }
///     }
struct PantallaEditable<Cabecera: View, Bloque: View, Pie: View>: View {
    let pantalla: String
    let titulo: String
    /// (id estable, nombre). Los ids no cambian nunca: son lo que se guarda en el servidor.
    let bloques: [(String, String)]
    var recarga: (() async -> Void)?
    /// Hueco al final para que la barra de abajo no tape el último bloque.
    var huecoBarra: CGFloat = 120
    let cabecera: (_ editar: @escaping () -> Void) -> Cabecera
    let bloque: (String) -> Bloque
    let pie: () -> Pie

    @State private var editando = false

    init(pantalla: String, titulo: String, bloques: [(String, String)], recarga: (() async -> Void)? = nil,
         huecoBarra: CGFloat = 120,
         @ViewBuilder cabecera: @escaping (_ editar: @escaping () -> Void) -> Cabecera,
         @ViewBuilder bloque: @escaping (String) -> Bloque,
         @ViewBuilder pie: @escaping () -> Pie) {
        self.pantalla = pantalla
        self.titulo = titulo
        self.bloques = bloques
        self.recarga = recarga
        self.huecoBarra = huecoBarra
        self.cabecera = cabecera
        self.bloque = bloque
        self.pie = pie
    }

    private var ids: [String] { bloques.map { $0.0 } }

    private func edita() {
        withAnimation(Tema.Muelle.pantalla) { editando = true }
    }

    var body: some View {
        Group {
            if editando {
                edicion.transition(.opacity)
            } else {
                contenido.transition(.opacity)
            }
        }
        .onAppear { PantallasEditables.registra(pantalla, bloques) }
    }

    /// Modo edición en la propia pantalla: asa para ordenar e interruptor para ocultar; «Listo» vuelve.
    private var edicion: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Editar \(titulo)").font(Tema.fuente(.titulo)).foregroundStyle(Tema.texto)
                Spacer()
                Button("Listo") { withAnimation(Tema.Muelle.pantalla) { editando = false } }
                    .font(Tema.fuente(.destacado))
                    .foregroundStyle(Tema.acento)
            }
            .padding(.horizontal, Tema.Espacio.l)
            .padding(.top, Tema.Espacio.m)
            EditorBloques(pantalla: pantalla, todos: bloques, fijos: [])
                .padding(.bottom, 90)
        }
    }

    private var contenido: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Tema.Espacio.l) {
                cabecera(edita)
                ForEach(Aspecto.shared.bloques(pantalla).aplica(ids), id: \.self) { id in
                    bloque(id)
                        .contextMenu {
                            Button("Editar \(titulo)", systemImage: "square.and.pencil") { edita() }
                            Button("Ocultar este bloque", systemImage: "eye.slash") { oculta(id) }
                        }
                }
                pie()
            }
            .padding(.horizontal, Tema.Espacio.l)
            .padding(.top, Tema.Espacio.s)
            .padding(.bottom, huecoBarra)
        }
        .scrollIndicators(.hidden)
        .modifier(Refresco(recarga: recarga))
        .environment(\.editarPantalla, edita)
    }

    private func oculta(_ id: String) {
        var b = Aspecto.shared.bloques(pantalla)
        if b.orden.isEmpty { b.orden = ids }
        if !b.ocultos.contains(id) { b.ocultos.append(id) }
        Aspecto.shared.ponBloques(pantalla, b)
    }
}

extension PantallaEditable where Pie == EmptyView {
    init(pantalla: String, titulo: String, bloques: [(String, String)], recarga: (() async -> Void)? = nil,
         huecoBarra: CGFloat = 120,
         @ViewBuilder cabecera: @escaping (_ editar: @escaping () -> Void) -> Cabecera,
         @ViewBuilder bloque: @escaping (String) -> Bloque) {
        self.init(pantalla: pantalla, titulo: titulo, bloques: bloques, recarga: recarga, huecoBarra: huecoBarra,
                  cabecera: cabecera, bloque: bloque, pie: { EmptyView() })
    }
}

/// Tirar para recargar, solo si la pantalla pasó una `recarga`.
private struct Refresco: ViewModifier {
    let recarga: (() async -> Void)?

    func body(content: Content) -> some View {
        if let recarga {
            content.refreshable { await recarga() }
        } else {
            content
        }
    }
}
