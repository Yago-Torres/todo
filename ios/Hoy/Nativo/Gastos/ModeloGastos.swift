import SwiftUI
import UIKit

/// De quién son los gastos. Son dos instancias distintas del servidor, con datos aparte: nunca se suman ni se mezclan
/// (regla de ~/gastos/CLAUDE.md). Cada llamada, cada copia local y cada vista lleva la suya.
enum InstanciaGastos: String, CaseIterable, Identifiable {
    case yago, aitana

    var id: String { rawValue }

    /// El prefijo del proxy de todo (/api/gastos/* y /api/gastos-aitana/*).
    var base: String { self == .yago ? "/api/gastos" : "/api/gastos-aitana" }
    var nombre: String { self == .yago ? "Yago" : "Aitana" }
}

// MARK: lo que devuelve /api/<gastos>/resumen

private extension KeyedDecodingContainer {
    /// Una clave que falta o viene rara no tumba la pantalla entera: se queda el valor por defecto.
    func v<T: Decodable>(_ clave: Key, _ por: T) -> T { (try? decodeIfPresent(T.self, forKey: clave)) ?? por }
}

struct ResumenGastos: Decodable {
    var inicio = ""
    var fin = ""
    var dias = 1
    var hechos = 0
    var actual = false
    var total = 0.0
    var aparte = 0.0
    var presu = 0.0
    var ingreso = 0.0
    var extra = 0.0
    var diaCobro = 1
    var proyeccion = 0.0
    var n = 0
    var cats: [Categoria] = []
    var serie: [Double] = []
    var seriePrevia: [Double] = []
    var historico: [Ciclo] = []
    var insights: [Insight] = []
    var suscripciones: [Suscripcion] = []
    /// Lo que se repite (semana, mes, año), también lo ignorado: el bloque Recurrentes (ReglasGastos.swift).
    var recurrentes: [Recurrente] = []
    var ingresos: [IngresoCiclo] = []
    var sugeridoTotal = 0.0
    var pareja = ""
    var hucha: Hucha?

    enum CodingKeys: String, CodingKey {
        case inicio, fin, dias, hechos, actual, total, aparte, presu, ingreso, extra, proyeccion, n, cats, serie, historico, insights, suscripciones, ingresos, pareja, hucha, recurrentes
        case diaCobro = "dia_cobro"
        case seriePrevia = "serie_previa"
        case sugeridoTotal = "sugerido_total"
    }

    struct Categoria: Decodable, Identifiable, Hashable {
        var id = ""
        var n = ""
        var presu = 0.0
        var gastado = 0.0
        var proyeccion = 0.0
        var estado = "ok"
        var devuelto = 0.0
        var anterior = 0.0
        var sugerido = 0.0
        var por = ""

        enum CodingKeys: String, CodingKey {
            case id, n, presu, gastado, proyeccion, estado, devuelto, anterior, sugerido, por
        }

        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            id = c.v(.id, ""); n = c.v(.n, ""); presu = c.v(.presu, 0); gastado = c.v(.gastado, 0)
            proyeccion = c.v(.proyeccion, 0); estado = c.v(.estado, "ok"); devuelto = c.v(.devuelto, 0)
            anterior = c.v(.anterior, 0); sugerido = c.v(.sugerido, 0); por = c.v(.por, "")
        }
    }

    struct Ciclo: Decodable, Hashable {
        var inicio = ""
        var fin = ""
        var total = 0.0

        enum CodingKeys: String, CodingKey {
            case inicio, fin, total
        }

        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            inicio = c.v(.inicio, ""); fin = c.v(.fin, ""); total = c.v(.total, 0)
        }
    }

    struct Insight: Decodable, Hashable {
        var nivel = "info"
        var texto = ""

        enum CodingKeys: String, CodingKey {
            case nivel, texto
        }

        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            nivel = c.v(.nivel, "info"); texto = c.v(.texto, "")
        }
    }

    struct Suscripcion: Decodable, Hashable {
        var n = ""
        var importe = 0.0
        var cada = "mes"
        var cat = ""
        var proximo = ""
        var alMes = 0.0

        enum CodingKeys: String, CodingKey {
            case n, importe, cada, cat, proximo
            case alMes = "al_mes"
        }

        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            n = c.v(.n, ""); importe = c.v(.importe, 0); cada = c.v(.cada, "mes"); cat = c.v(.cat, "")
            proximo = c.v(.proximo, ""); alMes = c.v(.alMes, 0)
        }
    }

    struct IngresoCiclo: Decodable, Identifiable, Hashable {
        var id = ""
        var dia = ""
        var importe = 0.0
        var tipo = "extra"
        var cat = ""
        var nota = ""
        var comercio = ""

        enum CodingKeys: String, CodingKey {
            case id, dia, importe, tipo, cat, nota, comercio
        }

        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            id = c.v(.id, ""); dia = c.v(.dia, ""); importe = c.v(.importe, 0); tipo = c.v(.tipo, "extra")
            cat = c.v(.cat, ""); nota = c.v(.nota, ""); comercio = c.v(.comercio, "")
        }
    }

    struct Hucha: Decodable, Hashable {
        var aporte = 0.0
        var aportado = 0.0
        var gastado = 0.0
        var saldo = 0.0

        enum CodingKeys: String, CodingKey {
            case aporte, aportado, gastado, saldo
        }

        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            aporte = c.v(.aporte, 0); aportado = c.v(.aportado, 0); gastado = c.v(.gastado, 0); saldo = c.v(.saldo, 0)
        }
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        inicio = c.v(.inicio, ""); fin = c.v(.fin, ""); dias = max(1, c.v(.dias, 1)); hechos = c.v(.hechos, 0)
        actual = c.v(.actual, false); total = c.v(.total, 0); aparte = c.v(.aparte, 0); presu = c.v(.presu, 0)
        ingreso = c.v(.ingreso, 0); extra = c.v(.extra, 0); diaCobro = c.v(.diaCobro, 1)
        proyeccion = c.v(.proyeccion, 0); n = c.v(.n, 0); cats = c.v(.cats, [])
        serie = c.v(.serie, []); seriePrevia = c.v(.seriePrevia, []); historico = c.v(.historico, [])
        insights = c.v(.insights, []); suscripciones = c.v(.suscripciones, []); ingresos = c.v(.ingresos, [])
        recurrentes = c.v(.recurrentes, [])
        sugeridoTotal = c.v(.sugeridoTotal, 0)
        pareja = (try? c.decodeIfPresent(String.self, forKey: .pareja)) ?? ""
        hucha = try? c.decodeIfPresent(Hucha.self, forKey: .hucha)
    }

    // MARK: cuentas que hace la web al pintar la cabecera

    /// Días que quedan del ciclo contando hoy (0 si el ciclo ya está cerrado).
    var quedan: Int { actual ? max(1, dias - hechos + 1) : 0 }
    /// Dónde deberías ir hoy si gastaras al ritmo del presupuesto (0...1), nil si el ciclo no está en curso.
    var ritmo: Double? { actual ? Double(hechos) / Double(dias) : nil }
    var pasado: Bool { presu > 0 && total > presu }
    var alDia: Double { quedan > 0 ? max(0, (presu - total) / Double(quedan)) : 0 }
    var cierre: Double { actual ? proyeccion : total }
    var ahorro: Double { ingreso + extra - cierre }
}

// MARK: lo que devuelve /api/<gastos>/estado (los movimientos)

struct Movimiento: Decodable, Identifiable, Hashable {
    var id = ""
    var dia = ""
    var importe = 0.0
    var cat = ""
    var nota = ""
    var comercio = ""
    var src = "web"
    var viaje = ""
    var orig = 0.0
    var moneda = ""
    var lineas: [Linea] = []
    /// Apuntado sin red: espera en la cola de Local a que vuelva la conexión.
    var pendiente = false

    enum CodingKeys: String, CodingKey {
        case id, dia, importe, cat, nota, comercio, src, viaje, orig, moneda, lineas
    }

    struct Linea: Decodable, Hashable {
        var t = ""
        var imp = 0.0

        enum CodingKeys: String, CodingKey {
            case t, imp
        }

        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            t = c.v(.t, ""); imp = c.v(.imp, 0)
        }
    }

    init(id: String, dia: String, importe: Double, cat: String, nota: String, pendiente: Bool = false) {
        self.id = id; self.dia = dia; self.importe = importe; self.cat = cat; self.nota = nota
        self.pendiente = pendiente
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.v(.id, ""); dia = c.v(.dia, ""); importe = c.v(.importe, 0); cat = c.v(.cat, "")
        nota = c.v(.nota, ""); comercio = c.v(.comercio, ""); src = c.v(.src, "web"); viaje = c.v(.viaje, "")
        orig = c.v(.orig, 0); moneda = c.v(.moneda, ""); lineas = c.v(.lineas, [])
    }

    /// El título de la fila: lo que dice el comercio o la nota; si no, la categoría.
    func titulo(_ nombreCat: String) -> String {
        if !comercio.isEmpty { return comercio }
        if !nota.isEmpty { return nota }
        return nombreCat
    }

    /// De dónde vino el apunte (lo que la web llama ORIGEN).
    var origen: String {
        ["atajo": "atajo", "applepay": "Apple Pay", "bot": "Telegram", "ticket": "ticket", "banco": "banco",
         "siri": "Siri"][src] ?? ""
    }
}

struct EstadoGastos: Decodable {
    var cats: [CategoriaBase] = []
    var gastos: [Movimiento] = []
    var viajes: [Viaje] = []
    /// Reglas de categoría (el orden es la prioridad), palabras rechazadas y recurrentes confirmados/ignorados.
    var reglas: [ReglaGasto] = []
    var rechazadas: [String] = []
    var recurrentes: [String: String] = [:]

    enum CodingKeys: String, CodingKey {
        case cats, gastos, viajes, reglas, rechazadas, recurrentes
    }

    struct CategoriaBase: Decodable, Identifiable, Hashable {
        var id = ""
        var n = ""
        var presu = 0.0

        enum CodingKeys: String, CodingKey {
            case id, n, presu
        }

        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            id = c.v(.id, ""); n = c.v(.n, ""); presu = c.v(.presu, 0)
        }
    }

    struct Viaje: Decodable, Identifiable, Hashable {
        var id = ""
        var n = ""
        var desde = ""
        var hasta = ""
        var presu = 0.0
        var moneda = "EUR"

        enum CodingKeys: String, CodingKey {
            case id, n, desde, hasta, presu, moneda
        }

        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            id = c.v(.id, ""); n = c.v(.n, ""); desde = c.v(.desde, ""); hasta = c.v(.hasta, "")
            presu = c.v(.presu, 0); moneda = c.v(.moneda, "EUR")
        }
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        cats = c.v(.cats, []); gastos = c.v(.gastos, []); viajes = c.v(.viajes, [])
        reglas = c.v(.reglas, []); rechazadas = c.v(.rechazadas, []); recurrentes = c.v(.recurrentes, [:])
    }
}

// MARK: formatos

/// Euros a la española: «1.234,56 €». Los formateadores se crean una vez.
enum Eur {
    private static func formateador(_ decimales: Int) -> NumberFormatter {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = decimales
        f.maximumFractionDigits = decimales
        return f
    }

    private static let dos = formateador(2)
    private static let cero = formateador(0)

    static func texto(_ x: Double) -> String {
        (dos.string(from: NSNumber(value: x)) ?? String(format: "%.2f", x)) + "\u{00A0}€"
    }

    static func entero(_ x: Double) -> String {
        (cero.string(from: NSNumber(value: x)) ?? String(format: "%.0f", x)) + "\u{00A0}€"
    }

    /// «12,50», «12.5», «1.234,56», «12 €»… a número. nil si no se entiende.
    static func lee(_ texto: String) -> Double? {
        var s = texto.replacingOccurrences(of: "€", with: "").replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
        if s.contains(",") {
            s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        }
        guard let x = Double(s), x.isFinite else { return nil }
        return x
    }

    /// Para rellenar un campo editable: «12,50».
    static func campo(_ x: Double) -> String {
        String(format: "%.2f", x).replacingOccurrences(of: ".", with: ",")
    }
}

/// Fechas «yyyy-MM-dd» del servidor, a la española.
enum FechaGasto {
    private static let iso: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func formato(_ patron: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = patron
        return f
    }

    private static let corto = formato("d MMM")
    private static let diaSemana = formato("EEEE d")

    static func fecha(_ dia: String) -> Date? { iso.date(from: dia) }
    static func dia(_ fecha: Date) -> String { iso.string(from: fecha) }

    /// «28 oct».
    static func corta(_ dia: String) -> String {
        guard let d = fecha(dia) else { return dia }
        return corto.string(from: d).replacingOccurrences(of: ".", with: "")
    }

    /// «Hoy», «Ayer» o «Lunes 3».
    static func titulo(_ dia: String) -> String {
        if dia == Fecha.hoy() { return "Hoy" }
        if let ayer = Calendar.current.date(byAdding: .day, value: -1, to: Date()), dia == Fecha.dia(ayer) { return "Ayer" }
        guard let d = fecha(dia) else { return dia }
        let t = diaSemana.string(from: d)
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    /// El día `n` días antes o después de `dia`.
    static func desplaza(_ dia: String, _ n: Int) -> String {
        guard let d = fecha(dia), let r = Calendar(identifier: .gregorian).date(byAdding: .day, value: n, to: d) else { return dia }
        return Self.dia(r)
    }
}

/// Los 8 colores de categoría (--serie-1…8 de calma.css, validados para daltonismo). Siguen a la categoría por su
/// posición en la lista, no a su gasto: filtrar o ordenar no los repinta.
enum SerieGastos {
    private static let colores: [Color] = [
        ("#2a78d6", "#3987e5"), ("#eb6834", "#d95926"), ("#1baf7a", "#199e70"), ("#eda100", "#c98500"),
        ("#e87ba4", "#d55181"), ("#008300", "#008300"), ("#6250d6", "#9085e9"), ("#e34948", "#e66767"),
    ].map { Color(uiColor: .dinamico(claro: $0.0, oscuro: $0.1)) }

    static func color(_ indice: Int) -> Color { colores[((indice % 8) + 8) % 8] }
}
