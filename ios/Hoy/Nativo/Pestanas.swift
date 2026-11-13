import SwiftUI

/// Lo que hay debajo de todo con las claves puestas: la pantalla nativa de la sección (Hoy/Nativo/Registro.swift) con
/// el fondo del tema y la barra nativa encima. Las pantallas entran y salen con el muelle del tema, sin cargar nada:
/// cada una pinta al momento su copia local (ya en memoria, ver Precarga) y se refresca por detrás.
struct Pestanas: View {
    let claves: Claves
    @ObservedObject private var navegador = Navegador.shared
    @Environment(\.scenePhase) private var fase
    /// La sección de antes, para saber hacia qué lado pasa la página.
    @State private var anterior = "/"
    /// Lo que se ha arrastrado de lado: la pantalla sigue al dedo antes de pasar de página.
    @State private var arrastre: CGFloat = 0

    var body: some View {
        let haciaDelante = Self.indice(navegador.pestana) >= Self.indice(anterior)
        ZStack(alignment: .bottom) {
            ZStack {
                Tema.fondo.ignoresSafeArea()
                FondoTema().ignoresSafeArea()   // el fondo de cada tema (Decoracion/)
                pantalla
                    .id(navegador.pestana)
                    // como pasar páginas: la nueva entra por un lado y la vieja sale por el otro
                    .transition(.push(from: haciaDelante ? .trailing : .leading))
            }
            .offset(x: arrastre)
            // deslizar a los lados: la página sigue al dedo y, pasado un tercio (o rápido), pasa a la de al lado
            .simultaneousGesture(DragGesture(minimumDistance: 24)
                .onChanged { g in
                    guard puedeArrastrar(g) else { return }
                    arrastre = g.translation.width * 0.6
                }
                .onEnded { g in
                    let dx = g.translation.width, rapido = abs(g.predictedEndTranslation.width) > 260
                    defer { withAnimation(Tema.Muelle.pantalla) { arrastre = 0 } }
                    guard puedeArrastrar(g), abs(dx) > 80 || rapido else { return }
                    paso(dx < 0 ? 1 : -1)
                })
            VStack(spacing: Tema.Espacio.s) {
                IndicadorCola()   // «N cambios por enviar» (Cola/), solo si hay algo en la cola
                Dock(actual: Navegador.seccion(navegador.pestana)) { navegador.toca($0) }
            }
                .padding(.bottom, 2)
                .ignoresSafeArea(.keyboard)
        }
        .animation(Tema.Muelle.pantalla, value: navegador.pestana)
        .onChange(of: navegador.pestana) { viejo, _ in anterior = viejo }
        // «?hecho=id» de un aviso o del widget: se marca aquí
        .onChange(of: navegador.marcaPendiente, initial: true) { _, id in
            guard let id else { return }
            navegador.marcaPendiente = nil
            Haptica.shared.toca(.marcar)
            Task { await DatosNativos.shared.marca(id, hecho: true) }
        }
        .onChange(of: fase) { _, nueva in
            if nueva == .active { Task { await DatosNativos.shared.carga(margen: 60) } }
        }
    }

    /// Solo arrastres claramente horizontales; en las listas con filas que se deslizan (completar, borrar…),
    /// solo desde los bordes.
    private func puedeArrastrar(_ g: DragGesture.Value) -> Bool {
        let dx = g.translation.width, dy = g.translation.height
        guard abs(dx) > abs(dy) * 2 else { return false }
        if Self.conFilasDeslizables.contains(navegador.pestana) {
            let x = g.startLocation.x, ancho = UIScreen.main.bounds.width
            return x < 28 || x > ancho - 28
        }
        return true
    }

    private static let conFilasDeslizables: Set<String> = ["/pendientes.html", "/documentos.html", "/gastos.html"]

    private static func indice(_ pestana: String) -> Int {
        Dock.visibles().firstIndex { $0.href == Navegador.seccion(pestana) } ?? 0
    }

    /// A la sección de al lado según el orden de la barra (dir: 1 siguiente, -1 anterior).
    private func paso(_ dir: Int) {
        let lista = Dock.visibles()
        let i = Self.indice(navegador.pestana) + dir
        guard lista.indices.contains(i) else {
            Haptica.shared.toca(.error)
            return
        }
        Haptica.shared.toca(.marcar)
        navegador.toca(lista[i].href)
    }

    private var pantalla: some View { RegistroNativo.vista(navegador.pestana) }
}
