import Foundation

/// Fechas en hora local con el formato del servidor. Un formateador por llamada: se usan desde el widget,
/// Salud y las tareas de fondo a la vez, y así la zona horaria es siempre la de ahora (viajes).
enum Fecha {
    private static func texto(_ d: Date, _ formato: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = formato
        return f.string(from: d)
    }

    static func hoy() -> String { dia(Date()) }

    static func dia(_ d: Date) -> String { texto(d, "yyyy-MM-dd") }

    static func minuto(_ d: Date) -> String { texto(d, "yyyy-MM-dd'T'HH:mm") }
}
