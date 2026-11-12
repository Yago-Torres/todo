import Foundation
import Combine

/// Lo que pide abrir el widget, los accesos del icono, Siri o un aviso: la web navega a `ruta` («/entreno.html»,
/// «/habitos.html?hecho=id») y la deja en nil. Si la web aún no está, se queda pendiente hasta que cargue.
@MainActor
final class Navegador: ObservableObject {
    static let shared = Navegador()

    @Published var ruta: String?
    /// La sección de la barra de abajo (su href en la web: "/", "/habitos.html", "/entreno.html"…). Hoy y Hábitos son
    /// pantallas nativas; las demás, la web en esa ruta.
    @Published var pestana: String = "/"
    /// La página que tiene cargada la web ahora (su ruta), para no recargarla al volver a su pestaña.
    @Published var paginaWeb: String?
    /// «/habitos.html?hecho=id» (un aviso o el widget): el hábito que la pantalla nativa tiene que marcar.
    @Published var marcaPendiente: String?

    /// Lo rellena la app al arrancar con RegistroNativo.rutas (Compartido también compila en el widget, que no las tiene).
    static var nativas: Set<String> = ["/", "/habitos.html"]

    /// Hoy y Hábitos van a su pantalla nativa, salvo con «web=1» (la página de siempre, para editar y planificar).
    static func esNativa(_ ruta: String) -> Bool {
        nativas.contains(seccion(ruta)) && !ruta.contains("web=1")
    }

    /// La entrada de la barra a la que pertenece una ruta (las mismas equivalencias que menu() de calma.js).
    static func seccion(_ ruta: String) -> String {
        let camino = ruta.components(separatedBy: CharacterSet(charactersIn: "?#")).first ?? ruta
        let equivalentes = ["/hoy.html": "/", "/index.html": "/habitos.html", "/carrera.html": "/entreno.html",
                            "/sueno.html": "/salud.html", "": "/"]
        return equivalentes[camino] ?? camino
    }
    /// El modo voz de Tom (Hoy/Voz.swift) a pantalla completa.
    @Published var voz = false
    /// Abrir Configurar desde el acceso del icono (también en frío, antes de que exista la vista).
    @Published var configurar = false

    private static let claveVoz = "abreVoz"

    func abre(_ ruta: String) {
        let r = ruta.hasPrefix("/") ? ruta : "/" + ruta
        let s = Self.seccion(r)
        if Self.esNativa(r) {
            if let id = URLComponents(string: r)?.queryItems?.first(where: { $0.name == "hecho" })?.value, !id.isEmpty {
                marcaPendiente = id
            }
            pestana = s
            return
        }
        // la web de una sección nativa (Hábitos con web=1) se queda con su ruta entera, para no confundirla con la nativa
        pestana = Self.nativas.contains(s) ? r : s
        self.ruta = r
    }

    /// Un toque en la barra: si la web ya está en esa sección, se enseña tal cual (sin recargar).
    func toca(_ seccion: String) {
        if Self.nativas.contains(seccion) || (paginaWeb.map(Self.seccion) == seccion && paginaWeb.map(Self.esNativa) == false) {
            pestana = seccion
        } else {
            abre(seccion)
        }
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
