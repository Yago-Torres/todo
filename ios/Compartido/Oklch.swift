import Foundation

/// La fórmula de los temas: dos colores (base y acento) → todos los tokens de claro y oscuro. Es la misma que
/// genera() de ~/estilo/calma.js, cifra a cifra (OKLCH con las matrices de Björn Ottosson, recorte por canal 0…1,
/// hex en mayúsculas), para que Tom y la web pinten exactamente lo mismo.
/// Comprobación: #F2F2F2 + #4E7A62 → claro fondo #F2F2F2, acento #4E7A62; oscuro fondo #131313, carta #1D1D1D,
/// acento #87B098; gota #99C3AB.
enum Oklch {
    struct Lado {
        var fondo, carta, cartaLuz, carta2, texto, suave, tenue, linea, dock, dockTexto, ascii: String
        var acento, acentoTexto, acentoSuave: String

        var tokens: [String: String] {
            ["fondo": fondo, "carta": carta, "carta_luz": cartaLuz, "carta2": carta2, "texto": texto, "suave": suave,
             "tenue": tenue, "linea": linea, "dock": dock, "dock_texto": dockTexto, "ascii": ascii,
             "acento": acento, "acento_texto": acentoTexto, "acento_suave": acentoSuave]
        }
    }

    struct Generado {
        var claro: Lado
        var oscuro: Lado
        var gota: String
        var gotaTexto: String
    }

    private static func lin(_ c: Double) -> Double {
        let x = c / 255
        return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
    }

    private static func gam(_ v: Double) -> Int {
        let x = max(0, min(1, v))
        let y = x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
        return Int((y * 255).rounded())   // como Math.round para positivos
    }

    /// (L en 0…100, C, H en grados)
    static func aOklch(_ hex: String) -> (Double, Double, Double) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let n = Int(s, radix: 16) ?? 0
        let r = lin(Double(n >> 16)), g = lin(Double((n >> 8) & 255)), b = lin(Double(n & 255))
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let sv = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let L = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * sv
        let A = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * sv
        let B = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * sv
        let h = (atan2(B, A) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        return (L * 100, (A * A + B * B).squareRoot(), h)
    }

    /// Hex en mayúsculas, o "rgba(r, g, b, a)" si hay alfa.
    static func deOklch(_ L: Double, _ C: Double, _ H: Double, alfa: Double? = nil) -> String {
        let h = H * .pi / 180, A = C * cos(h), B = C * sin(h), l0 = L / 100
        let l = pow(l0 + 0.3963377774 * A + 0.2158037573 * B, 3)
        let m = pow(l0 - 0.1055613458 * A - 0.0638541728 * B, 3)
        let s = pow(l0 - 0.0894841775 * A - 1.291485548 * B, 3)
        let rgb = [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                   -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                   -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s].map(gam)
        if let alfa { return "rgba(\(rgb[0]), \(rgb[1]), \(rgb[2]), \(alfa))" }
        return "#" + rgb.map { String(format: "%02X", $0) }.joined()
    }

    /// pow() de un negativo da NaN; en JS ** 3 de un negativo da negativo: se respeta el signo.
    private static func pow(_ x: Double, _ y: Double) -> Double {
        x < 0 && y == 3 ? -Foundation.pow(-x, 3) : Foundation.pow(x, y)
    }

    private static func entre(_ x: Double, _ a: Double, _ b: Double) -> Double { max(a, min(b, x)) }

    static func esHex(_ s: String) -> Bool {
        s.count == 7 && s.hasPrefix("#") && Int(s.dropFirst(), radix: 16) != nil
    }

    static func genera(base: String, acento: String) -> Generado {
        let (Lb, Cb0, Hb) = aOklch(base)
        let cn = Cb0 < 0.004 ? 0 : min(Cb0, 0.045)
        let fc = Lb >= 90 ? min(Lb, 99) : 96.8
        let fo = Lb <= 25 ? max(Lb, 7) : 18.5
        func N(_ L: Double, _ k: Double, _ a: Double? = nil) -> String { deOklch(L, cn * k, Hb, alfa: a) }
        let (La, Ca0, Ha) = aOklch(acento)
        let ca = min(Ca0, 0.25)
        func A(_ L: Double, _ k: Double) -> String { deOklch(L, ca * k, Ha) }
        let claro = Lado(fondo: N(fc, 0.45), carta: N(min(fc + 2.8, 100), 0.12), cartaLuz: "#FFFFFF", carta2: N(fc - 3.2, 0.6),
                         texto: N(22, 0.7), suave: N(52, 0.6), tenue: N(70, 0.5), linea: N(fc - 6.3, 0.55), dock: N(30, 0.8),
                         dockTexto: N(78, 0.5), ascii: N(30, 1, 0.2),
                         acento: A(entre(La, 38, 58), 1), acentoTexto: "#FFFFFF", acentoSuave: A(95, 0.25))
        let oscuro = Lado(fondo: N(fo, 0.6), carta: N(fo + 4.5, 0.7), cartaLuz: N(fo + 7, 0.7), carta2: N(fo + 8.5, 0.75),
                          texto: N(95, 0.3), suave: N(72, 0.55), tenue: N(52, 0.5), linea: N(fo + 13.5, 0.75),
                          dock: N(max(fo + 11.5, 26), 0.8), dockTexto: N(78, 0.5), ascii: N(90, 1.4, 0.15),
                          acento: A(entre(La, 72, 88), 0.9), acentoTexto: A(22, 0.6), acentoSuave: A(31, 0.35))
        return Generado(claro: claro, oscuro: oscuro, gota: A(entre(La, 78, 90), 0.9), gotaTexto: A(24, 0.7))
    }
}
