import UIKit

/// Los accesos que salen al mantener pulsado el icono.
enum Accesos {
    private static let secciones: [(tipo: String, titulo: String, simbolo: String, ruta: String)] = [
        ("entreno", "Entreno", "figure.run", "/entreno.html"),
        ("escalada-vivo", "Escalada en vivo", "figure.climbing", "/entreno.html"),
        ("pendientes", "Pendientes", "checklist", "/pendientes.html"),
        ("habitos", "Hábitos", "checkmark.circle", "/habitos.html"),
        ("salud", "Salud", "heart.fill", "/salud.html"),
    ]

    static func instala() {
        Task { @MainActor in
            UIApplication.shared.shortcutItems = secciones.map {
                UIApplicationShortcutItem(type: $0.tipo, localizedTitle: $0.titulo, localizedSubtitle: nil,
                                          icon: UIApplicationShortcutIcon(systemImageName: $0.simbolo), userInfo: nil)
            } + [UIApplicationShortcutItem(type: "configurar", localizedTitle: "Ajustes de Tom", localizedSubtitle: nil,
                                           icon: UIApplicationShortcutIcon(systemImageName: "gearshape"), userInfo: nil)]
        }
    }

    static func maneja(_ tipo: String) {
        // Configurar, sin pasar por Ajustes
        if tipo == "configurar" {
            Task { @MainActor in Navegador.shared.configurar = true }
            return
        }
        // la cámara con el esqueleto en vivo, encima de Entreno
        if tipo == "escalada-vivo" {
            Task { @MainActor in VivoEscalada.shared.abre() }
            return
        }
        guard let s = secciones.first(where: { $0.tipo == tipo }) else { return }
        Task { @MainActor in Navegador.shared.abre(s.ruta) }
    }
}
