import SwiftUI
import LocalAuthentication

/// Tapa la web hasta que pasas Face ID (o el código del iPhone, si Face ID falla).
struct Bloqueo: View {
    let alDesbloquear: () -> Void

    @Environment(\.scenePhase) private var fase
    @State private var error: String?
    @State private var pidiendo = false

    init(alDesbloquear: @escaping () -> Void) {
        self.alDesbloquear = alDesbloquear
    }

    var body: some View {
        ZStack {
            Tema.fondo.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "faceid")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Tom está bloqueado")
                    .font(.title2.bold())
                if let error {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button("Desbloquear", systemImage: "faceid") {
                    Task { await pide() }
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(Tema.acentoTexto)
                .disabled(pidiendo)
            }
            .padding(32)
        }
        // Face ID solo se puede pedir con la app delante; el bloqueo se pone al irse a segundo plano
        .task {
            if fase == .active { await pide() }
        }
        .onChange(of: fase) { _, nueva in
            if nueva == .active { Task { await pide() } }
        }
    }

    private func pide() async {
        guard !pidiendo else { return }
        pidiendo = true
        defer { pidiendo = false }

        let contexto = LAContext()
        contexto.localizedCancelTitle = "Cancelar"
        var fallo: NSError?
        guard contexto.canEvaluatePolicy(.deviceOwnerAuthentication, error: &fallo) else {
            // sin código ni Face ID en el iPhone no hay con qué bloquear: dejarla cerrada sería perder la app
            error = fallo?.localizedDescription
            alDesbloquear()
            return
        }
        do {
            if try await contexto.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Desbloquea Tom") {
                error = nil
                alDesbloquear()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
