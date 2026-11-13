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
    /// Las cuentas de cada viaje (por id): total, lo pagado por cada uno, mi parte y lo que la pareja me debe.
    var cuentas: [String: CuentaViaje] = [:]

    enum CodingKeys: String, CodingKey {
        case inicio, fin, dias, hechos, actual, total, aparte, presu, ingreso, extra, proyeccion, n, cats, serie, historico, insights, suscripciones, ingresos, pareja, hucha, recurrentes, cuentas
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
        var src = "web"

        enum CodingKeys: String, CodingKey {
            case id, dia, importe, tipo, cat, nota, comercio, src
        }

        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            id = c.v(.id, ""); dia = c.v(.dia, ""); importe = c.v(.importe, 0); tipo = c.v(.tipo, "extra")
            cat = c.v(.cat, ""); nota = c.v(.nota, ""); comercio = c.v(.comercio, ""); src = c.v(.src, "web")
        }

        /// El título de la fila: la nota, el comercio o, sin ellos, qué es.
        var titulo: String {
            !nota.isEmpty ? nota : !comercio.isEmpty ? comercio : (tipo == "devuelve" ? "Te devuelven" : "Ingreso")
        }
    }

    struct Hucha: Decodable, Hashable {
        var aporte = 0.0
        var aportado = 0.0
        var gastado = 0.0
        var saldo = 0.0
        /// Cuántos ciclos más hacen falta para que vuelva a cero (0 si no está en negativo).
        var ciclosACero = 0
        var plan: [Paso] = []

        enum CodingKeys: String, CodingKey {
            case aporte, aportado, gastado, saldo, plan
            case ciclosACero = "ciclos_a_cero"
        }

        /// Un ciclo de la hucha: lo que se aparta, lo que se fue en viajes y cómo queda. Los futuros, hasta volver a cero.
        struct Paso: Decodable, Hashable {
            var inicio = ""
            var fin = ""
            var aparta = 0.0
            var gastado = 0.0
            var saldo = 0.0
            var futuro = false

            enum CodingKeys: String, CodingKey { case inicio, fin, aparta, gastado, saldo, futuro }

            init(from d: Decoder) throws {
                let c = try d.container(keyedBy: CodingKeys.self)
                inicio = c.v(.inicio, ""); fin = c.v(.fin, ""); aparta = c.v(.aparta, 0); gastado = c.v(.gastado, 0)
                saldo = c.v(.saldo, 0); futuro = c.v(.futuro, false)
            }
        }

        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            aporte = c.v(.aporte, 0); aportado = c.v(.aportado, 0); gastado = c.v(.gastado, 0); saldo = c.v(.saldo, 0)
            ciclosACero = c.v(.ciclosACero, 0); plan = c.v(.plan, [])
        }
    }

    /// Las cuentas de un viaje (las calcula el servidor; en uno compartido lee los gastos de la pareja).
    struct CuentaViaje: Decodable, Hashable {
        var total = 0.0
        var pagado = 0.0
        var pagadoPareja = 0.0
        var parte = 0.0
        var meDebe = 0.0
        /// Los gastos de la pareja en ese viaje: solo para verlos (se cambian en su app).
        var suyos: [Movimiento] = []

        enum CodingKeys: String, CodingKey {
            case total, pagado, parte, suyos
            case pagadoPareja = "pagado_pareja"
            case meDebe = "me_debe"
        }

        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            total = c.v(.total, 0); pagado = c.v(.pagado, 0); pagadoPareja = c.v(.pagadoPareja, 0)
            parte = c.v(.parte, 0); meDebe = c.v(.meDebe, 0); suyos = c.v(.suyos, [])
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
        cuentas = c.v(.cuentas, [:])
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
    /// En un viaje compartido, de quién es: medias | mio | suyo | pago | cobro (pago y cobro saldan, no son gasto).
    var reparto = "medias"
    var lineas: [Linea] = []
    /// Apuntado sin red: espera en la cola de Local a que vuelva la conexión.
    var pendiente = false

    enum CodingKeys: String, CodingKey {
        case id, dia, importe, cat, nota, comercio, src, viaje, orig, moneda, lineas, reparto
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
        orig = c.v(.orig, 0); moneda = c.v(.moneda, ""); lineas = c.v(.lineas, []); reparto = c.v(.reparto, "medias")
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
    /// Lo que entra aparte del sueldo (extras y lo que te devuelven): aquí se editan, la copia local lleva lo pendiente.
    var ingresos: [ResumenGastos.IngresoCiclo] = []
    var ajustes = Ajustes()

    enum CodingKeys: String, CodingKey {
        case cats, gastos, viajes, reglas, rechazadas, recurrentes, ingresos, ajustes
    }

    /// Cuánto cobras, qué día y lo que apartas para viajes cada ciclo.
    struct Ajustes: Decodable, Hashable {
        var ingreso = 0.0
        var diaCobro = 1
        var hucha = 0.0

        enum CodingKeys: String, CodingKey {
            case ingreso, hucha
            case diaCobro = "dia_cobro"
        }

        init() {}

        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            ingreso = c.v(.ingreso, 0); diaCobro = c.v(.diaCobro, 1); hucha = c.v(.hucha, 0)
        }
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
        /// Euros por unidad de la moneda del viaje (0 = sin poner).
        var cambio = 0.0
        /// Compartido con la pareja: cada uno apunta lo que paga en su instancia.
        var con = false

        enum CodingKeys: String, CodingKey {
            case id, n, desde, hasta, presu, moneda, cambio, con
        }

        init(id: String, n: String, desde: String, hasta: String, presu: Double, moneda: String, cambio: Double, con: Bool) {
            self.id = id; self.n = n; self.desde = desde; self.hasta = hasta; self.presu = presu
            self.moneda = moneda; self.cambio = cambio; self.con = con
        }

        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            id = c.v(.id, ""); n = c.v(.n, ""); desde = c.v(.desde, ""); hasta = c.v(.hasta, "")
            presu = c.v(.presu, 0); moneda = c.v(.moneda, "EUR"); cambio = c.v(.cambio, 0); con = c.v(.con, false)
        }

        /// Lo que se guarda (la forma de clean() en el servidor).
        var crudo: [String: Any] {
            ["id": id, "n": n, "desde": desde, "hasta": hasta, "presu": presu, "moneda": moneda, "cambio": cambio, "con": con]
        }
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        cats = c.v(.cats, []); gastos = c.v(.gastos, []); viajes = c.v(.viajes, [])
        reglas = c.v(.reglas, []); rechazadas = c.v(.rechazadas, []); recurrentes = c.v(.recurrentes, [:])
        ingresos = c.v(.ingresos, []); ajustes = c.v(.ajustes, Ajustes())
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
