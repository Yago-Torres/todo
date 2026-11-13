import SwiftUI
import Observation

/// Lo que queda en la cola de «sin conexión» (Local), para el indicador común y su hoja. Además, en cuanto entra un
/// cambio y hay red, la vacía (lo apuntado sin red sale en cuanto se puede, en su orden), y al salir algo repinta Hoy y
/// Hábitos desde la copia local.
@MainActor @Observable
final class EstadoCola {
    static let shared = EstadoCola()

    private(set) var cambios: [Local.Cambio] = []
    private(set) var enviando = false

    @ObservationIgnored private var empujon: Task<Void, Never>?
    @ObservationIgnored private var observadores: [NSObjectProtocol] = []

    var pendientes: Int { cambios.filter { $0.estado == .pendiente }.count }
    var conProblema: Int { cambios.count - pendientes }

    init() {
        let centro = NotificationCenter.default
        observadores.append(centro.addObserver(forName: .tomColaCambia, object: nil, queue: .main) { _ in
            Task { @MainActor in EstadoCola.shared.cambia() }
        })
        observadores.append(centro.addObserver(forName: .tomSincronizado, object: nil, queue: .main) { _ in
            Task { @MainActor in DatosNativos.shared.refrescaDesdeLocal() }
        })
        recarga()
    }

    func recarga() {
        let nuevos = Local.cambios()
        guard nuevos != cambios else { return }
        withAnimation(Tema.Muelle.toque) { cambios = nuevos }
    }

    /// Varios avisos seguidos (la cola cambia a ráfagas mientras sale) se juntan en uno.
    private func cambia() {
        empujon?.cancel()
        empujon = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            recarga()
            let ahora = Date()
            let toca = cambios.contains { $0.estado == .pendiente && ($0.proximo ?? .distantPast) <= ahora }
            if toca, Red.shared.hayRed { await Sincro.vacia() }
        }
    }

    func enviaAhora() async {
        guard !enviando else { return }
        enviando = true
        await Sincro.vacia(forzar: true)
        enviando = false
        recarga()
        DatosNativos.shared.refrescaDesdeLocal()
    }

    /// Fuera de la cola: no se manda y deja de verse en la copia local.
    func descarta(_ c: Local.Cambio) {
        Local.descarta(c.id)
        Operaciones.recalcula(para: c)
        recarga()
        Haptica.shared.toca(.desmarcar)
        repinta(c)
    }

    func reintenta(_ c: Local.Cambio) {
        Local.reintenta(c.id)
        Operaciones.recalcula(para: c)
        recarga()
        repinta(c)
        Task { await enviaAhora() }
    }

    /// La pantalla de lo que tocaba el cambio, otra vez desde la copia local.
    private func repinta(_ c: Local.Cambio) {
        for ruta in Operaciones.rutas(Operaciones.pendiente(c)) {
            switch ruta {
            case Operaciones.state, Operaciones.hoy:
                DatosNativos.shared.refrescaDesdeLocal()
            case Operaciones.bandeja:
                Task { await DatosPendientes.shared.recarga() }
            case Operaciones.documentos:
                Task { await DatosDocumentos.shared.recarga() }
            default:
                if ruta.hasSuffix("/estado") { Task { await DatosGastos.shared.recarga() } }
            }
        }
    }
}
