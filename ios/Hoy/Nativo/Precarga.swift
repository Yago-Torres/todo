import Foundation

/// Las copias locales de las secciones de la barra, ya en memoria antes de abrirlas: cada modelo lee la suya de Local
/// al crearse (y la decodifica), así que se crean aquí, una a una y en el orden de la barra, poco después del primer
/// fotograma. Al tocar una pestaña la pantalla pinta lo último que hubo, sin «Cargando…», y se refresca por detrás.
@MainActor
enum Precarga {
    private static var hecha = false

    static func secciones() async {
        guard !hecha else { return }
        hecha = true
        var rutas = Dock.visibles().map(\.href)
        if !rutas.contains("/carrera.html") { rutas.append("/carrera.html") }
        for ruta in rutas {
            calienta(ruta)
            // entre una y otra, que pinte lo que tenga que pintar (cada una decodifica en el hilo principal)
            try? await Task.sleep(for: .milliseconds(40))
        }
    }

    /// El modelo de una sección, creado (y con su copia leída) si aún no lo estaba.
    static func calienta(_ ruta: String) {
        switch Navegador.pantalla(ruta) {
        case "/", "/habitos.html": _ = DatosNativos.shared
        case "/entreno.html":
            _ = DatosEntreno.shared
            _ = EscaladaDatos.shared
        case "/carrera.html": _ = CarreraDatos.shared
        case "/salud.html": _ = DatosSalud.shared
        case "/pendientes.html": _ = DatosPendientes.shared
        case "/comida.html": _ = DatosComida.shared
        case "/gastos.html": DatosGastos.shared.precarga()
        case "/documentos.html": _ = DatosDocumentos.shared
        case "/ajustes.html": _ = ModeloAjustes.shared
        default: break
        }
    }
}
