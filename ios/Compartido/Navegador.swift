import Foundation
import Combine

/// Lo que pide abrir el widget, los accesos del icono, Siri o un aviso: la web navega a `ruta` («/entreno.html»,
/// «/habitos.html?hecho=id») y la deja en nil. Si la web aún no está, se queda pendiente hasta que cargue.
@MainActor
final class Navegador: ObservableObject {
    static let shared = Navegador()

    @Published var ruta: String?
    /// El modo voz de Tom (Hoy/Voz.swift) a pantalla completa.
    @Published var voz = false
    /// Abrir Configurar desde el acceso del icono (también en frío, antes de que exista la vista).
    @Published var configurar = false

    private static let claveVoz = "abreVoz"

    func abre(_ ruta: String) {
        self.ruta = ruta.hasPrefix("/") ? ruta : "/" + ruta
    }

    /// «Habla con Tom» puede correr en el proceso del widget (el botón del centro de control), donde este Navegador
    /// no es el de la app: además se deja una marca en el app group, y la app la recoge al activarse.
    func abreVoz() {
        voz = true
        Almacen.defaults.set(Date().timeIntervalSince1970, forKey: Self.claveVoz)
    }

    /// Al pasar a primer plano: si la marca es de hace menos de un minuto, abre el modo voz.
    func recogeVoz() {
        let marca = Almacen.defaults.double(forKey: Self.claveVoz)
        guard marca > 0 else { return }
        Almacen.defaults.removeObject(forKey: Self.claveVoz)
        if Date().timeIntervalSince1970 - marca < 60 { voz = true }
    }

    /// Con el modo voz ya abierto, la marca sobra: que no lo vuelva a abrir la próxima vez que se active la app.
    func olvidaVoz() {
        Almacen.defaults.removeObject(forKey: Self.claveVoz)
    }
}
