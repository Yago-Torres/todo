import SwiftUI

/// Lo que hay debajo de todo con las claves puestas: las pantallas nativas (Hoy, Hábitos), la web para el resto de
/// secciones y la barra nativa encima. La web vive siempre debajo (no se recarga al ir y volver); las pantallas
/// nativas entran y salen con el muelle del tema, sin cargar nada.
struct Pestanas: View {
    let claves: Claves
    @ObservedObject private var navegador = Navegador.shared
    @Environment(\.scenePhase) private var fase

    private var nativa: Bool { Navegador.nativas.contains(navegador.pestana) }

    var body: some View {
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
                            insertion: .opacity.combined(with: .scale(scale: 0.985, anchor: .top)),
                            removal: .opacity))
                }
                .transition(.opacity)
            }
            Dock(actual: Navegador.seccion(navegador.pestana)) { navegador.toca($0) }
                .padding(.bottom, 2)
                .ignoresSafeArea(.keyboard)
        }
        .animation(Tema.Muelle.pantalla, value: navegador.pestana)
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

    @ViewBuilder private var pantalla: some View {
        if navegador.pestana == "/habitos.html" {
            PantallaHabitos()
        } else {
            PantallaHoy()
        }
    }
}
