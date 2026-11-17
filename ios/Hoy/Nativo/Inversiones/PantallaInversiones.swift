import SwiftUI

/// Inversiones en nativo (lo de static/inversiones.html): Cartera, Operaciones, Review y Perfil, con las mismas
/// cuentas que la web porque las hace el servidor. «/inversiones.html?review=fecha» (el aviso del domingo) abre esa review.
struct PantallaInversiones: View {
    enum Vista: Hashable { case cartera, operaciones, review, perfil }

    @State private var datos = DatosInversiones.shared
    @State private var vista: Vista = .cartera
    @ObservedObject private var navegador = Navegador.shared

    private let opciones: [(valor: Vista, titulo: String)] = [
        (.cartera, "Cartera"), (.operaciones, "Operaciones"), (.review, "Review"), (.perfil, "Perfil"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tema.Espacio.l) {
                cabecera
                    .padding(.horizontal, Tema.Espacio.l)
                SelectorPildoras(opciones: opciones, seleccion: $vista)
                Group {
                    if let copia = datos.copia {
                        Label(API.notaCopia(copia), systemImage: "wifi.slash")
                            .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.aviso)
                    }
                    if let inf = datos.inf {
                        switch vista {
                        case .cartera: CarteraInversiones(inf: inf)
                        case .operaciones: OperacionesInversiones(inf: inf)
                        case .review: ReviewInversiones(inf: inf)
                        case .perfil: PerfilInversiones(perfil: inf.perfil)
                        }
                    } else {
                        Text(datos.cargando ? "Cargando la cartera…" : datos.error ?? "Sin datos todavía. Tira hacia abajo para cargar.")
                            .font(Tema.fuente(.texto)).foregroundStyle(datos.error == nil ? Tema.suave : Tema.peligro)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .carta()
                    }
                }
                .padding(.horizontal, Tema.Espacio.l)
            }
            .padding(.top, Tema.Espacio.s)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await datos.carga() }
        .tostada(datos.aviso) { datos.quitaAviso() }
        .task { await datos.carga() }
        .environment(\.locale, FechasES.locale)
        .onChange(of: navegador.reviewInversiones, initial: true) { _, fecha in
            guard let fecha else { return }
            navegador.reviewInversiones = nil
            datos.reviewElegida = fecha
            withAnimation(Tema.Muelle.pantalla) { vista = .review }
            Task { await datos.carga() }   // la review del domingo es nueva: la lista de fechas también
        }
    }

    private var cabecera: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(datos.inf.map { DineroES.eur($0.total.valor) } ?? "Tu cartera")
                    .estiloEtiqueta().foregroundStyle(Tema.suave)
                    .contentTransition(.numericText())
                Text("Inversiones").font(Tema.fuente(.titulo)).foregroundStyle(Tema.texto)
            }
            Spacer()
        }
    }
}
