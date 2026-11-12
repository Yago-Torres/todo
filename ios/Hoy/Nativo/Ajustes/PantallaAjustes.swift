import SwiftUI

/// Ajustes en nativo (/ajustes.html): lo mismo que la página web, con la apariencia, las pantallas, el freno y las claves
/// de Configurar. Una lista nativa con secciones, con el fondo y las cartas del tema.
struct PantallaAjustes: View {
    var body: some View {
        NavigationStack {
            List {
                SeccionAjustesTom()
                SeccionApariencia()
                SeccionPantallas()
                SeccionFreno()
                Section {
                    Button {
                        Haptica.shared.toca(.marcar)
                        Navegador.shared.configurar = true
                    } label: {
                        Label("Claves, Salud, avisos y Face ID", systemImage: "key")
                    }
                } footer: {
                    Text("Las claves de conexión y lo que depende de este iPhone.")
                }
            }
            .listRowBackground(Tema.carta)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 96) }   // el hueco de la barra
        }
    }
}
