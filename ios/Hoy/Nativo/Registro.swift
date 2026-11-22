import SwiftUI

/// Las pantallas nativas, una línea cada una: la ruta de su sección (la misma que en la barra y en la web del
/// ordenador) y su vista. Una ruta que no esté aquí abre Hoy. Para una sección nueva: su vista en
/// Hoy/Nativo/<Seccion>/ y una línea en `pantallas`. Navegador.nativas y Pestanas leen de aquí.
enum RegistroNativo {
    static let pantallas: [(ruta: String, vista: () -> AnyView)] = [
        ("/", { AnyView(PantallaHoy()) }),
        ("/habitos.html", { AnyView(PantallaHabitos()) }),
        ("/gastos.html", { AnyView(PantallaGastos()) }),
        ("/pendientes.html", { AnyView(PantallaPendientes()) }),
        ("/calendario.html", { AnyView(PantallaCalendario()) }),
        ("/entreno.html", { AnyView(PantallaEntreno()) }),
        ("/carrera.html", { AnyView(PantallaCarrera()) }),
        ("/salud.html", { AnyView(PantallaSalud()) }),
        ("/documentos.html", { AnyView(PantallaDocumentos()) }),
        ("/inversiones.html", { AnyView(PantallaInversiones()) }),
        ("/claude.html", { AnyView(PantallaClaude()) }),
        ("/anio.html", { AnyView(PantallaAnio()) }),   // sin entrada en la barra: se abre tocando «Tu año» en Hoy
        ("/sistema.html", { AnyView(PantallaSistema()) }),   // igual: desde la tarjeta «La Pi» de Hoy
        ("/ajustes.html", { AnyView(PantallaAjustes()) }),
        // ← cada sección nueva, aquí (una línea, en el orden de la barra)
    ]

    static var rutas: Set<String> { Set(pantallas.map(\.ruta)) }

    static func vista(_ ruta: String) -> AnyView {
        pantallas.first { $0.ruta == ruta }?.vista() ?? AnyView(PantallaHoy())
    }
}
