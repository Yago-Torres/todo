import SwiftUI

/// Lo que hay debajo de todo con las claves puestas: las pantallas nativas (Hoy, Hábitos), la web para el resto de
/// secciones y la barra nativa encima. La web vive siempre debajo (no se recarga al ir y volver); las pantallas
/// nativas entran y salen con el muelle del tema, sin cargar nada.
struct Pestanas: View {
    let claves: Claves
    @ObservedObject private var navegador = Navegador.shared
    @Environment(\.scenePhase) private var fase
    /// La sección de antes, para saber hacia qué lado pasa la página.
    @State private var anterior = "/"

    private var nativa: Bool { Navegador.nativas.contains(navegador.pestana) }

    var body: some View {
        let haciaDelante = Self.indice(navegador.pestana) >= Self.indice(anterior)
        ZStack(alignment: .bottom) {
            Tema.fondo.ignoresSafeArea()
            Web(claves: claves)
                .ignoresSafeArea()
                .opacity(nativa ? 0 : 1)
                .allowsHitTesting(!nativa)
                .accessibilityHidden(nativa)
            if nativa {
                ZStack {
                    Tema.fondo.ignoresSafeArea()
                    FondoCalma().ignoresSafeArea()
                    pantalla
                        .id(navegador.pestana)
                        .transition(.asymmetric(
                            insertion: .move(edge: haciaDelante ? .trailing : .leading).combined(with: .opacity),
                            removal: .opacity))
                }
                .transition(.asymmetric(insertion: .move(edge: haciaDelante ? .trailing : .leading).combined(with: .opacity),
                                        removal: .opacity))
                // deslizar a los lados: la sección siguiente o la anterior de la barra (sin tocar el scroll vertical)
                .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { g in
                    let dx = g.translation.width, dy = g.translation.height
                    guard abs(dx) > 80, abs(dx) > abs(dy) * 2 else { return }
                    paso(dx < 0 ? 1 : -1)
                })
            }
            Dock(actual: Navegador.seccion(navegador.pestana)) { navegador.toca($0) }
                .padding(.bottom, 2)
                .ignoresSafeArea(.keyboard)
        }
        .animation(Tema.Muelle.pantalla, value: navegador.pestana)
        .onChange(of: navegador.pestana) { viejo, _ in anterior = viejo }
        // en la web, el paso llega desde los bordes de la pantalla (Web.swift)
        .onReceive(NotificationCenter.default.publisher(for: .hoyPaso)) { n in
            if let dir = n.object as? Int { paso(dir) }
        }
        // «/habitos.html?hecho=id» de un aviso o del widget: se marca aquí
        .onChange(of: navegador.marcaPendiente) { _, id in
            guard let id else { return }
            navegador.marcaPendiente = nil
            Haptica.shared.toca(.marcar)
            Task { await DatosNativos.shared.marca(id, hecho: true) }
        }
        .onChange(of: fase) { _, nueva in
            if nueva == .active { Task { await DatosNativos.shared.carga(margen: 60) } }
        }
    }

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

extension Notification.Name {
    /// Deslizar desde un borde con la web delante: object = 1 (siguiente) o -1 (anterior).
    static let hoyPaso = Notification.Name("hoyPaso")
}
