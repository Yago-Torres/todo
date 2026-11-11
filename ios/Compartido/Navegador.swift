import Foundation
import Combine

/// Lo que pide abrir el widget, los accesos del icono, Siri o un aviso: la web navega a `ruta` («/entreno.html»,
/// «/habitos.html?hecho=id») y la deja en nil. Si la web aún no está, se queda pendiente hasta que cargue.
@MainActor
final class Navegador: ObservableObject {
    static let shared = Navegador()

    @Published var ruta: String?

    func abre(_ ruta: String) {
        self.ruta = ruta.hasPrefix("/") ? ruta : "/" + ruta
    }
}
