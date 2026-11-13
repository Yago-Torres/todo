import Foundation
import SwiftUI

// Lo que la web de gastos cambia con el PUT del estado entero (viajes y su hucha, cuánto cobras y qué día, los ingresos)
// y Tom manda como operaciones de la cola (Compartido/OperacionesGastos.swift): se ven al momento, funcionan sin red y
// Sincro las aplica sobre el estado fresco del servidor. Siempre en la instancia que se mira: Yago y Aitana, aparte.

/// Las monedas que entiende el servidor (MONEDAS de main.py), con su símbolo.
enum MonedaViaje {
    static let todas: [(codigo: String, simbolo: String)] = [
        ("EUR", "€"), ("GBP", "£"), ("USD", "$"), ("CHF", "CHF"), ("SEK", "kr"), ("NOK", "kr"), ("DKK", "kr"),
        ("CZK", "Kč"), ("PLN", "zł"), ("HUF", "Ft"), ("JPY", "¥"), ("MAD", "DH"),
    ]

    static func simbolo(_ codigo: String) -> String { todas.first { $0.codigo == codigo }?.simbolo ?? codigo }

    /// «12,50 £».
    static func texto(_ x: Double, _ codigo: String) -> String {
        Eur.texto(x).replacingOccurrences(of: "€", with: simbolo(codigo))
    }
}

/// Cómo se reparte un gasto de un viaje compartido (REPARTOS de la web).
enum RepartoViaje {
    static func opciones(_ pareja: String) -> [(id: String, n: String)] {
        [("medias", "A medias"), ("mio", "Solo mío"), ("suyo", "Todo de \(pareja)"),
         ("pago", "Le pago a \(pareja) (saldar)"), ("cobro", "\(pareja) me paga (saldar)")]
    }
}

extension DatosGastos {
    var ajustes: EstadoGastos.Ajustes { estado?.ajustes ?? EstadoGastos.Ajustes() }
    var viajes: [EstadoGastos.Viaje] { estado?.viajes ?? [] }

    func viaje(_ id: String) -> EstadoGastos.Viaje? { viajes.first { $0.id == id } }

    /// El viaje en curso hoy en otra moneda: lo que se apunta va en esa por defecto (como la web).
    var viajeEnOtraMoneda: EstadoGastos.Viaje? {
        let hoy = Fecha.hoy()
        return viajes.first { $0.desde <= hoy && hoy <= $0.hasta && $0.moneda != "EUR" }
    }

    /// Los ingresos del ciclo que se ve, de la copia del estado (así lo editado sin red se ve ya).
    func ingresosDelCiclo(_ r: ResumenGastos) -> [ResumenGastos.IngresoCiclo] {
        guard let e = estado else { return r.ingresos }
        return e.ingresos.filter { $0.dia >= r.inicio && $0.dia <= r.fin }
            .sorted { $0.dia != $1.dia ? $0.dia > $1.dia : $0.id > $1.id }
    }

    // MARK: ajustes (ingreso, día de cobro, hucha)

    /// Devuelve true si el cambio se ha quedado en la cola (sin red): las cuentas del ciclo se recalculan al llegar.
    @discardableResult
    func ponAjustes(_ cambios: [String: Any], resumen: String) async throws -> Bool {
        let inst = instancia
        let enCola = try await opera(inst, ["op": "ajustes.pon", "cambios": cambios, "resumen": resumen])
        if cambios["dia_cobro"] != nil, inst == instancia {
            // otro día de cobro = otros ciclos: se vuelve al de hoy
            withAnimation(Tema.Muelle.pantalla) { ref = Fecha.hoy() }
        }
        await refresca(inst)
        return enCola
    }

    // MARK: viajes

    /// Un id como los del servidor («v» + 9 cifras).
    static func idViaje() -> String { "v" + String(Int.random(in: 100_000_000...999_999_999)) }

    /// Crea o cambia un viaje. Al crearlo se lleva los gastos que ya eran suyos (reservas, los que lo nombran, los de
    /// esos días) y devuelve cuáles, para poder devolverlos al ciclo.
    @discardableResult
    func ponViaje(_ v: EstadoGastos.Viaje, nuevo: Bool) async throws -> [Movimiento] {
        let inst = instancia
        var op: [String: Any] = ["op": "viaje.pon", "viaje": v.crudo,
                                 "resumen": nuevo ? "Crear el viaje \(v.n)" : "Cambiar el viaje \(v.n)"]
        if nuevo { op["lleva"] = true }
        try await opera(inst, op)
        await refresca(inst)
        guard nuevo else { return [] }
        let llevados = (estadoDe(inst)?.gastos ?? []).filter { $0.viaje == v.id }
        if !llevados.isEmpty {
            ofreceDeshacer(inst, "\(v.n) se lleva \(llevados.count) gasto\(llevados.count == 1 ? "" : "s")",
                           ["op": "viaje.asigna", "ids": llevados.map(\.id), "viaje": "",
                            "resumen": "Devolver al ciclo los gastos de \(v.n)"])
        }
        return llevados
    }

    /// Borra el viaje: sus gastos vuelven al ciclo. Se puede deshacer unos segundos.
    func borraViaje(_ v: EstadoGastos.Viaje) async throws {
        let inst = instancia
        let suyos = movimientos.filter { $0.viaje == v.id }.map(\.id)
        try await opera(inst, ["op": "viaje.borra", "id": v.id, "resumen": "Borrar el viaje \(v.n)"])
        ofreceDeshacer(inst, "Borrado \(v.n): sus gastos vuelven al ciclo",
                       ["op": "viaje.pon", "viaje": v.crudo, "asigna": suyos, "resumen": "Recuperar el viaje \(v.n)"])
        await refresca(inst)
    }

    /// El cambio de hoy (euros por unidad) del BCE, por el servidor. nil sin red o si no responde.
    func cambioDeHoy(_ moneda: String) async -> Double? {
        guard moneda != "EUR",
              let d = try? await API.datos("\(instancia.base)/cambio?moneda=\(moneda)"),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let c = (o["cambio"] as? NSNumber)?.doubleValue, c > 0 else { return nil }
        return c
    }

    /// Un Bizum para quedar en paz en un viaje compartido: pago si debías, cobro si te debían.
    func salda(_ v: EstadoGastos.Viaje, meDebe: Double, pareja: String) async throws -> String {
        try await apunta(tipo: .gasto, importe: abs(meDebe), nota: meDebe < 0 ? "Pago a \(pareja)" : "\(pareja) me paga",
                         cat: "otros", extra: ["moneda": "EUR", "viaje": v.id, "reparto": meDebe < 0 ? "pago" : "cobro"])
    }

    private func estadoDe(_ inst: InstanciaGastos) -> EstadoGastos? { inst == instancia ? estado : nil }

    // MARK: ingresos

    func editaIngreso(_ i: ResumenGastos.IngresoCiclo, importe: Double, dia: String, tipo: String, cat: String,
                      nota: String) async throws {
        let inst = instancia
        let x = (importe * 100).rounded() / 100
        let limpia = nota.trimmingCharacters(in: .whitespaces)
        let cambios: [String: Any] = ["importe": x, "dia": dia, "tipo": tipo, "cat": tipo == "devuelve" ? cat : "",
                                      "nota": limpia, "comercio": limpia.isEmpty ? i.comercio : ""]
        try await opera(inst, ["op": "ingreso.edita", "id": i.id, "cambios": cambios,
                               "resumen": "Cambiar el ingreso de \(Eur.texto(x))"])
        await refresca(inst)
    }

    func borraIngreso(_ i: ResumenGastos.IngresoCiclo) async throws {
        let inst = instancia
        let crudo: [String: Any] = ["id": i.id, "dia": i.dia, "importe": i.importe, "tipo": i.tipo, "cat": i.cat,
                                    "nota": i.nota, "comercio": i.comercio, "src": i.src]
        try await opera(inst, ["op": "ingreso.borra", "id": i.id, "resumen": "Borrar el ingreso de \(Eur.texto(i.importe))"])
        ofreceDeshacer(inst, "Borrado: +\(Eur.texto(i.importe))",
                       ["op": "ingreso.restaura", "ingreso": crudo, "resumen": "Recuperar un ingreso borrado"])
        await refresca(inst)
    }
}
