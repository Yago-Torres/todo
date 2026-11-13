import SwiftUI
import UIKit
import WidgetKit

/// Lo que hace la app al arrancar y al volver a primer plano, ordenado para que lo primero sea pintar: la última
/// copia de cada pantalla sale de Local al momento y nada de esto la retrasa. Lo que no se ve (sesión de audio,
/// Live Activities, subidas, atajos, Salud, avisos, widgets) espera a que ya se haya pintado el primer fotograma, y
/// la red siempre va por detrás: cuando contesta, cada pantalla cambia a lo nuevo con su muelle.
@MainActor
enum Arranque {
    private static var arrancada = false

    /// Un margen para que el primer fotograma salga antes que el trabajo de fondo.
    private static func trasPintar(_ ms: Int = 250) async {
        try? await Task.sleep(for: .milliseconds(ms))
    }

    /// Una vez por arranque, con la app delante (no cuando iOS la despierta en segundo plano para un intent o Salud).
    static func primeraVez() {
        guard !arrancada else { return }
        arrancada = true
        Task { @MainActor in
            await trasPintar()
            // la sesión de audio .ambient (los sonidos de la app respetan el silencio y se mezclan con la música)
            Sonido.ambiente()
            // la Live Activity del entreno y la sesión que iOS cerró a medias (vuelve a Entreno y se reabre)
            _ = Entreno.shared
            // las subidas de escalada que acabaron con la app cerrada avisan en cuanto existe su sesión
            Subidas.shared.arranca()
            // las demás secciones de la barra, ya en memoria con su copia local
            await Precarga.secciones()
        }
    }

    /// Cada vez que la app pasa a primer plano (también la primera).
    static func alActivar(conClaves: Bool) {
        Navegador.shared.recogeVoz()
        primeraVez()
        Task { @MainActor in
            await trasPintar(conClaves ? 400 : 0)
            Accesos.instala()
            guard conClaves else { return }
            Isla.limpia()
            // los hábitos de hoy como valores de «Marca … en Tom»
            AtajosHoy.updateAppShortcutParameters()
            DatosFondo.alActivar()   // el entreno de hoy para el fondo de bloqueo (Hoy/Nativo/Bloqueo/)
            Task { await Aspecto.shared.sincroniza() }
            // lo apuntado sin red sale ya, y se baja lo principal para tenerlo sin conexión
            Task { await Sincro.alActivar() }
            _ = await Salud.sincroniza()
            await Avisos.programa()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
