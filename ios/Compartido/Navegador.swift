import Foundation
import Combine

/// Lo que pide abrir el widget, los accesos del icono, Siri o un aviso: una ruta («/entreno.html»,
/// «/habitos.html?hecho=id») que acaba siempre en su pantalla nativa; una que no se conoce, en Hoy.
@MainActor
final class Navegador: ObservableObject {
    static let shared = Navegador()

    /// La pantalla que se ve: la ruta de su sección en el registro ("/", "/habitos.html", "/entreno.html"…). Carrera
    /// tiene la suya ("/carrera.html") aunque en la barra se marque Entreno (ver `seccion`).
    @Published var pestana: String = "/" {
        // la de antes, guardada ANTES de pintar: Pestanas decide con ella hacia qué lado pasa la página
        willSet { if newValue != pestana { anterior = pestana } }
    }
    /// La sección de la que venimos (para el sentido de la transición: siempre de lado, nunca desde abajo).
    private(set) var anterior: String = "/"
    /// «?hecho=id» (un aviso o el widget, en Hoy o en Hábitos): el hábito que hay que marcar.
    @Published var marcaPendiente: String?
    /// «/pendientes.html?nueva=1» (el control «Apuntar una tarea»): Pendientes enfoca el campo de apuntar.
    @Published var apuntarTarea = false

    /// Lo rellena la app al arrancar con RegistroNativo.rutas (Compartido también compila en el widget, que no las tiene).
    static var nativas: Set<String> = ["/"]

    /// La entrada de la barra a la que pertenece una ruta (las mismas equivalencias que menu() de calma.js).
    static func seccion(_ ruta: String) -> String {
        let camino = ruta.components(separatedBy: CharacterSet(charactersIn: "?#")).first ?? ruta
        let equivalentes = ["/hoy.html": "/", "/index.html": "/habitos.html", "/carrera.html": "/entreno.html",
                            "/sueno.html": "/salud.html", "": "/"]
        return equivalentes[camino] ?? camino
    }

    /// La pantalla nativa de una ruta: la suya si está en el registro (Carrera), si no la de su sección, y Hoy si
    /// no hay ninguna.
    static func pantalla(_ ruta: String) -> String {
        let camino = ruta.components(separatedBy: CharacterSet(charactersIn: "?#")).first ?? ruta
        if nativas.contains(camino) { return camino }
        let s = seccion(camino)
        return nativas.contains(s) ? s : "/"
    }

    /// El modo voz de Tom (Hoy/Voz.swift) a pantalla completa.
    @Published var voz = false
    /// Abrir Configurar desde el acceso del icono (también en frío, antes de que exista la vista).
    @Published var configurar = false

    private static let claveVoz = "abreVoz"

    func abre(_ ruta: String) {
        let r = ruta.hasPrefix("/") ? ruta : "/" + ruta
        let destino = Self.pantalla(r)
        let datos = URLComponents(string: r)?.queryItems ?? []
        if let id = datos.first(where: { $0.name == "hecho" })?.value, !id.isEmpty {
            marcaPendiente = id
        }
        if destino == "/pendientes.html", datos.contains(where: { $0.name == "nueva" && $0.value == "1" }) {
            apuntarTarea = true
        }
        pestana = destino
    }

    /// Un toque en la barra.
    func toca(_ seccion: String) {
        pestana = Self.pantalla(seccion)
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
