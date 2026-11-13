import SwiftUI

/// La sección «Sin conexión» de Configurar.
struct SeccionSinConexion: View {
    @State private var cambios: [Local.Cambio] = []
    @State private var ultima: Date?
    @State private var sincronizando = false
    @State private var borrando = false
    @State private var preguntaBorrar = false
    @State private var mensaje: String?

    private var pendientes: Int { cambios.filter { $0.estado == .pendiente }.count }

    var body: some View {
        Section {
            LabeledContent("Última sincronización",
                           value: ultima.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Nunca")
                .onAppear(perform: recarga)
            LabeledContent("Cambios pendientes", value: "\(pendientes)")
            ForEach(cambios.prefix(50)) { c in
                fila(c)
            }
            Button {
                Task { await sincroniza() }
            } label: {
                HStack {
                    Text("Sincronizar ahora")
                    if sincronizando {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(sincronizando)
            Button("Borrar datos locales", role: .destructive) { preguntaBorrar = true }
                .disabled(borrando)
                .confirmationDialog("¿Borrar los datos guardados en este iPhone?", isPresented: $preguntaBorrar,
                                    titleVisibility: .visible) {
                    Button("Borrar", role: .destructive) { Task { await borra() } }
                } message: {
                    Text("Se vuelven a bajar en cuanto haya conexión. Los cambios sin enviar no se tocan.")
                }
        } header: {
            Text("Sin conexión")
        } footer: {
            Text(mensaje ?? "Tom guarda en este iPhone (y solo aquí) una copia de tus datos para usarlos sin red. Lo que cambies sin conexión se envía al volver.")
        }
    }

    private func fila(_ c: Local.Cambio) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(c.resumen)
            Text(detalle(c))
                .font(.caption)
                .foregroundStyle(c.estado == .pendiente ? Color.secondary : Color.orange)
        }
        .swipeActions {
            Button("Descartar", role: .destructive) { descarta(c) }
            if c.estado != .pendiente {
                Button("Reintentar") { reintenta(c) }
                    .tint(.blue)
            }
        }
    }

    private func detalle(_ c: Local.Cambio) -> String {
        let cuando = c.fecha.formatted(date: .abbreviated, time: .shortened)
        switch c.estado {
        case .pendiente:
            guard c.intentos > 0 else { return cuando }
            return "\(cuando) · \(c.intentos) intentos · \(c.error ?? "")"
        case .conflicto:
            return "Conflicto: \(c.error ?? ""). Desliza para reintentar o descartar."
        case .error:
            return "Error: \(c.error ?? ""). Desliza para reintentar o descartar."
        }
    }

    private func recarga() {
        cambios = Local.cambios()
        ultima = Local.ultimaSincronizacion
    }

    private func descarta(_ c: Local.Cambio) {
        Local.descarta(c.id)
        Operaciones.recalcula(para: c)
        recarga()
    }

    private func reintenta(_ c: Local.Cambio) {
        Local.reintenta(c.id)
        recarga()
        Task {
            await Sincro.vacia(forzar: true)
            recarga()
        }
    }

    private func sincroniza() async {
        sincronizando = true
        mensaje = nil
        let enviados = await Sincro.vacia(forzar: true)
        await Sincro.precarga(forzar: true)
        sincronizando = false
        recarga()
        mensaje = Red.shared.hayRed
            ? "Hecho: \(enviados) \(enviados == 1 ? "cambio enviado" : "cambios enviados") y datos al día."
            : "Sin conexión: se enviará solo al volver la red."
    }

    private func borra() async {
        borrando = true
        Local.borraRespuestas()
        borrando = false
        recarga()
        mensaje = "Datos locales borrados. Se vuelven a bajar con conexión."
    }
}
