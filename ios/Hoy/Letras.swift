import CoreText
import Foundation
import UIKit

/// Las letras empaquetadas en Hoy/ (.ttf), registradas solo cuando hacen falta. Ya no van en UIAppFonts: iOS las
/// registraba todas (unos 3 MB) antes de pintar nada. Al arrancar se registran solo las del tema elegido (Aspecto) y
/// el resto al verlas en Configurar → Apariencia. Una letra nueva: su .ttf en Hoy/ y su línea aquí (nombre de
/// familia → ficheros sin extensión).
enum Letras {
    private static let archivos: [String: [String]] = [
        "Instrument Sans": ["InstrumentSans"],
        "Inter": ["Inter"],
        "Manrope": ["Manrope"],
        "Geist": ["Geist"],
        "IBM Plex Sans": ["IBMPlexSans"],
        "DM Sans": ["DMSans"],
        "Space Grotesk": ["SpaceGrotesk"],
        "JetBrains Mono": ["JetBrainsMono"],
        "Fraunces": ["Fraunces"],
        "Shippori Mincho": ["ShipporiMincho-Regular", "ShipporiMincho-Bold"],
        "Zen Kaku Gothic New": ["ZenKakuGothicNew-Regular", "ZenKakuGothicNew-Bold"],
    ]

    private static let cerrojo = NSLock()
    /// Familia → si se puede usar (registrada, o del sistema).
    nonisolated(unsafe) private static var vistas: [String: Bool] = [:]

    /// Registra la familia si es una de las nuestras y dice si se puede usar con Font.custom.
    @discardableResult
    static func lista(_ familia: String) -> Bool {
        cerrojo.lock()
        defer { cerrojo.unlock() }
        if let ya = vistas[familia] { return ya }
        if let nombres = archivos[familia] {
            for n in nombres {
                guard let url = Bundle.main.url(forResource: n, withExtension: "ttf") else { continue }
                var error: Unmanaged<CFError>?
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            }
        }
        let ok = !UIFont.fontNames(forFamilyName: familia).isEmpty
        vistas[familia] = ok
        return ok
    }

    /// Todas (Configurar → Apariencia escribe cada nombre en su letra).
    static func todas() {
        for familia in archivos.keys { lista(familia) }
    }
}
