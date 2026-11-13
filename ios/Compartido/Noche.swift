import Foundation
import UIKit

/// El modo noche: de una hora a otra (por defecto de 23:00 a 7:00) o de la puesta a la salida del sol, Tom se pone en
/// oscuro y con un filtro cálido encima del tema: menos azul, menos brillo y el acento más apagado. Se guarda en el app
/// group (Configurar → Apariencia → Modo noche) para que el widget y las Live Activities lo apliquen también.
/// Compila en la app y en el widget.
struct AjustesNoche: Codable, Equatable {
    enum Modo: String, Codable, CaseIterable {
        case horas, sol
    }

    var activo = false
    var modo = Modo.horas
    /// Minutos desde medianoche.
    var desde = 23 * 60
    var hasta = 7 * 60

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AjustesNoche()
        activo = (try? c.decodeIfPresent(Bool.self, forKey: .activo)) ?? nil ?? d.activo
        modo = (try? c.decodeIfPresent(Modo.self, forKey: .modo)) ?? nil ?? d.modo
        desde = (try? c.decodeIfPresent(Int.self, forKey: .desde)) ?? nil ?? d.desde
        hasta = (try? c.decodeIfPresent(Int.self, forKey: .hasta)) ?? nil ?? d.hasta
    }
}

enum Noche {
    private static let clave = "noche.ajustes"

    static var ajustes: AjustesNoche {
        get {
            Almacen.defaults.data(forKey: clave).flatMap { try? JSONDecoder().decode(AjustesNoche.self, from: $0) }
                ?? AjustesNoche()
        }
        set {
            if let d = try? JSONEncoder().encode(newValue) { Almacen.defaults.set(d, forKey: clave) }
        }
    }

    /// ¿Toca modo noche a esta hora?
    static func activa(_ fecha: Date = Date(), _ a: AjustesNoche = ajustes) -> Bool {
        guard a.activo else { return false }
        let (desde, hasta) = tramo(fecha, a)
        let cal = Calendar.current
        let c = cal.dateComponents([.hour, .minute], from: fecha)
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        if desde == hasta { return false }
        // 23:00 → 7:00 cruza la medianoche; 13:00 → 15:00 no
        return desde < hasta ? (m >= desde && m < hasta) : (m >= desde || m < hasta)
    }

    /// De qué minuto a qué minuto (desde medianoche) va la noche ese día.
    static func tramo(_ fecha: Date = Date(), _ a: AjustesNoche = ajustes) -> (desde: Int, hasta: Int) {
        guard a.modo == .sol, let s = sol(fecha) else { return (a.desde, a.hasta) }
        return (s.puesta, s.salida)
    }

    /// "23:00"
    static func hora(_ minutos: Int) -> String {
        let m = ((minutos % 1440) + 1440) % 1440
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    // MARK: el sol

    /// Dónde se mira el sol, sin pedir la ubicación: Madrid con la hora de la península, Las Palmas con la de
    /// Canarias y, fuera de España, una longitud sacada del huso horario (a 40° de latitud).
    private static var lugar: (lat: Double, lon: Double) {
        switch TimeZone.current.identifier {
        case "Atlantic/Canary": return (28.1, -15.43)
        case "Europe/Madrid", "Africa/Ceuta": return (40.42, -3.70)
        default:
            let horas = Double(TimeZone.current.secondsFromGMT() - Int(TimeZone.current.daylightSavingTimeOffset())) / 3600
            return (40, horas * 15)
        }
    }

    /// La salida y la puesta del sol de ese día, en minutos desde la medianoche local (la ecuación del amanecer, con
    /// un minuto o dos de margen: suficiente para esto).
    static func sol(_ fecha: Date) -> (salida: Int, puesta: Int)? {
        let (lat, lon) = lugar
        let rad = Double.pi / 180
        // el mediodía local de ese día, en días julianos desde J2000
        let cal = Calendar.current
        guard let mediodia = cal.date(bySettingHour: 12, minute: 0, second: 0, of: fecha) else { return nil }
        let jd = mediodia.timeIntervalSince1970 / 86400 + 2440587.5
        let n = (jd - 2451545.0 + 0.0008).rounded()
        let jEstrella = n - lon / 360
        let m = (357.5291 + 0.98560028 * jEstrella).truncatingRemainder(dividingBy: 360)
        let c = 1.9148 * sin(m * rad) + 0.02 * sin(2 * m * rad) + 0.0003 * sin(3 * m * rad)
        let lambda = (m + c + 180 + 102.9372).truncatingRemainder(dividingBy: 360)
        let transito = 2451545.0 + jEstrella + 0.0053 * sin(m * rad) - 0.0069 * sin(2 * lambda * rad)
        let senoDecl = sin(lambda * rad) * sin(23.4397 * rad)
        let decl = asin(senoDecl)
        let cosW = (sin(-0.833 * rad) - sin(lat * rad) * senoDecl) / (cos(lat * rad) * cos(decl))
        guard cosW > -1, cosW < 1 else { return nil }   // sol de medianoche o noche polar
        let w = acos(cosW) / rad
        func minutos(_ j: Double) -> Int {
            let d = Date(timeIntervalSince1970: (j - 2440587.5) * 86400)
            let k = cal.dateComponents([.hour, .minute], from: d)
            return (k.hour ?? 0) * 60 + (k.minute ?? 0)
        }
        return (minutos(transito - w / 360), minutos(transito + w / 360))
    }

    // MARK: el filtro

    /// Un color del tema (en oscuro) pasado por el filtro: más oscuro, con menos azul y, si es de acento, más
    /// apagado. Acepta y devuelve "#RRGGBB" o "rgba(r, g, b, a)" como el catálogo.
    static func filtra(_ css: String, acento: Bool = false) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        UIColor(css: css).getRed(&r, green: &g, blue: &b, alpha: &a)
        func hex(_ x: CGFloat) -> String { String(format: "%02X", Int((max(0, min(1, x)) * 255).rounded())) }
        let entrada = "#" + hex(r) + hex(g) + hex(b)
        var (L, C, H) = Oklch.aOklch(entrada)
        // menos brillo (los textos claros bajan más que los fondos, que ya son oscuros: menos contraste)
        L = L > 50 ? 50 + (L - 50) * 0.72 : L * 0.86
        if acento {
            C *= 0.55
            L *= 0.88
        }
        let salida = Oklch.deOklch(L, C, H)
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 1
        UIColor(css: salida).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        // el tono cálido: el rojo se queda, el verde baja un poco y el azul bastante
        r2 = r2 * 1.0
        g2 = g2 * 0.86
        b2 = b2 * 0.62
        if a < 0.999 {
            let n = { (x: CGFloat) in Int((max(0, min(1, x)) * 255).rounded()) }
            return "rgba(\(n(r2)), \(n(g2)), \(n(b2)), \(Double(a)))"
        }
        return "#" + hex(r2) + hex(g2) + hex(b2)
    }

    /// Los tokens del widget (los de ColoresGuardados) que son de acento: se apagan más.
    static let tokensAcento: Set<String> = ["acento", "acento_suave", "gota", "peligro", "aviso"]
}
