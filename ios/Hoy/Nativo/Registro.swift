import SwiftUI

/// Las pantallas nativas, una línea cada una: la ruta de su sección (la misma que en la barra y en la web) y su vista.
/// Lo que no esté aquí se abre en la web. Para pasar una sección a nativo: su vista en Hoy/Nativo/<Seccion>/ y una
/// línea en `pantallas`. Navegador.nativas y Pestanas leen de aquí; no hace falta tocar nada más.
enum RegistroNativo {
    static let pantallas: [(ruta: String, vista: () -> AnyView)] = [
        ("/", { AnyView(PantallaHoy()) }),
        ("/habitos.html", { AnyView(PantallaHabitos()) }),
        ("/comida.html", { AnyView(PantallaComida()) }),
        ("/gastos.html", { AnyView(PantallaGastos()) }),
        ("/pendientes.html", { AnyView(PantallaPendientes()) }),
        ("/entreno.html", { AnyView(PantallaEntreno()) }),
        ("/carrera.html", { AnyView(PantallaCarrera()) }),
        ("/salud.html", { AnyView(PantallaSalud()) }),
        ("/documentos.html", { AnyView(PantallaDocumentos()) }),
        ("/ajustes.html", { AnyView(PantallaAjustes()) }),
        // ← cada sección nueva, aquí (una línea, en el orden de la barra)
    ]

    static var rutas: Set<String> { Set(pantallas.map(\.ruta)) }

    static func vista(_ ruta: String) -> AnyView {
        pantallas.first { $0.ruta == ruta }?.vista() ?? AnyView(PantallaHoy())
    }
}
