import Foundation

// /api/hoy. Cada tarjeta del servidor puede llegar como {"error": "..."} si su app no responde (trozo() en main.py):
// esos campos quedan en nil y el resto se lee igual. La decodificación tolerante va en extensiones para conservar
// los init memberwise (el widget los usa en su muestra).

struct Hoy: Codable {
    var hoy: String
    var habitos: [Habito]
    var salud: SaludHoy?
    var tareas: [Tarea]?
    var carrera: CarreraHoy?
    var ayer: [HabitoAyer]?
    // para el widget configurable y la línea de gastos (al final y opcionales: el init memberwise no cambia)
    var peso: PesoHoy?
    var gastos: GastosHoy?
    var entreno: [EntrenoHoy]?
    var leer: Int?
}

struct Habito: Codable, Identifiable, Hashable {
    var id: String
    var n: String
    var c: String
    var plan: Bool
    var hecho: Bool
    var racha: Int
    // de /api/hoy desde las rachas con descansos (al final y opcionales: el init memberwise no cambia)
    /// Hoy se exige y hay racha (si no se hace, se rompe o gasta un comodín).
    var juego: Bool? = nil
    /// Hoy descansa: "descanso", "vacaciones", "enfermedad" o "comodin". La racha está congelada.
    var libre: String? = nil

    /// La racha está en juego hoy (sin los campos nuevos, como antes: 2 días o más sin hacer).
    var arriesga: Bool { !hecho && libre == nil && (juego ?? true) && racha >= 2 }
}

struct HabitoAyer: Codable, Hashable {
    var id: String
    var n: String
}

struct SaludHoy: Codable {
    var sueno: DatoSalud?
    var pasos: DatoSalud?
}

struct DatoSalud: Codable {
    var ultimo: Int?
    var media: Int?
    var serie: [Int?]?
}

struct Tarea: Codable, Hashable {
    var t: String
    var due: String?
    var hora: String?
    var id: String?
}

struct CarreraHoy: Codable {
    var estimacion: Int?
    var objetivo: Int?
    var semana: Int?
    var n_semanas: Int?
    var fase: String?
    var proxima: SesionCarrera?
    var hoy_hecho: Bool?
}

/// La próxima sesión del plan de 5k que falta por hacer (puede ser hoy).
struct SesionCarrera: Codable, Hashable {
    var dia: String
    var n: String
    var tipo: String?
    var hecho: Bool
}

/// El último peso apuntado y la media de 7 días.
struct PesoHoy: Codable {
    var dia: String?
    var kg: Double?
    var media: Double?
}

/// El ciclo de cobro de gastos (hoy_gastos() en main.py). `quedan` son días; `al_dia`, euros por día.
struct GastosHoy: Codable {
    var total: Double?
    var presu: Double?
    var ayer: Double?
    var inicio: String?
    var fin: String?
    var quedan: Int?
    var al_dia: Double?

    /// Lo que queda del presupuesto del ciclo (negativo si te has pasado); nil sin presupuesto.
    var queda: Double? {
        guard let presu, presu > 0, let total else { return nil }
        return presu - total
    }
}

/// Lo que toca entrenar hoy: la rutina de cada hábito planificado. tipo: pesas|carrera|movilidad|otro.
struct EntrenoHoy: Codable, Hashable {
    var id: String
    var n: String
    var tipo: String
    var hecho: Bool
}

// MARK: decodificación tolerante

private struct Clave: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

private extension KeyedDecodingContainer where K == Clave {
    /// nil si falta, es null o tiene otra forma (p. ej. {"error": ...}).
    func tolera<T: Decodable>(_ tipo: T.Type, _ clave: String) -> T? {
        (try? decodeIfPresent(T.self, forKey: Clave(clave))) ?? nil
    }

    /// Los números de Python pueden llegar como 420 o 420.0.
    func entero(_ clave: String) -> Int? {
        if let i = tolera(Int.self, clave) { return i }
        if let d = tolera(Double.self, clave), d.isFinite { return Int(d.rounded()) }
        return nil
    }

    func texto(_ clave: String) -> String? {
        if let s = tolera(String.self, clave) { return s }
        return entero(clave).map(String.init)
    }

    func booleano(_ clave: String) -> Bool? {
        if let b = tolera(Bool.self, clave) { return b }
        return entero(clave).map { $0 != 0 }
    }
}

/// Un elemento que no se entiende se salta en vez de tirar la lista entera.
private struct Quizas<T: Decodable>: Decodable {
    let valor: T?
    init(from decoder: Decoder) throws { valor = try? T(from: decoder) }
}

private extension KeyedDecodingContainer where K == Clave {
    func lista<T: Decodable>(_ tipo: T.Type, _ clave: String) -> [T]? {
        tolera([Quizas<T>].self, clave).map { $0.compactMap(\.valor) }
    }
}

extension Hoy {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Clave.self)
        self.init(hoy: c.texto("hoy") ?? Fecha.hoy(),
                  habitos: c.lista(Habito.self, "habitos") ?? [],
                  salud: c.tolera(SaludHoy.self, "salud"),
                  tareas: c.lista(Tarea.self, "tareas"),
                  carrera: c.tolera(CarreraHoy.self, "carrera"),
                  ayer: c.lista(HabitoAyer.self, "ayer"),
                  peso: c.tolera(PesoHoy.self, "peso"),
                  gastos: c.tolera(GastosHoy.self, "gastos"),
                  entreno: c.lista(EntrenoHoy.self, "entreno"),
                  leer: c.entero("leer"))
    }
}

extension Habito {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Clave.self)
        guard let id = c.texto("id") else {
            throw DecodingError.dataCorruptedError(forKey: Clave("id"), in: c, debugDescription: "hábito sin id")
        }
        self.init(id: id, n: c.texto("n") ?? id, c: c.texto("c") ?? "#1baf7a",
                  plan: c.booleano("plan") ?? false, hecho: c.booleano("hecho") ?? false,
                  racha: c.entero("racha") ?? 0, juego: c.booleano("juego"), libre: c.texto("libre"))
    }
}

extension HabitoAyer {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Clave.self)
        guard let id = c.texto("id") else {
            throw DecodingError.dataCorruptedError(forKey: Clave("id"), in: c, debugDescription: "hábito sin id")
        }
        self.init(id: id, n: c.texto("n") ?? id)
    }
}

extension SaludHoy {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Clave.self)
        self.init(sueno: c.tolera(DatoSalud.self, "sueno"), pasos: c.tolera(DatoSalud.self, "pasos"))
    }
}

extension DatoSalud {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Clave.self)
        let serie = c.tolera([Double?].self, "serie")?.map { d in d.flatMap { $0.isFinite ? Int($0.rounded()) : nil } }
        self.init(ultimo: c.entero("ultimo"), media: c.entero("media"), serie: serie)
    }
}

extension Tarea {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Clave.self)
        guard let t = c.texto("t") else {
            throw DecodingError.dataCorruptedError(forKey: Clave("t"), in: c, debugDescription: "tarea sin texto")
        }
        self.init(t: t, due: c.texto("due"), hora: c.texto("hora"), id: c.texto("id"))
    }
}

extension CarreraHoy {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Clave.self)
        self.init(estimacion: c.entero("estimacion"), objetivo: c.entero("objetivo"),
                  semana: c.entero("semana"), n_semanas: c.entero("n_semanas"),
                  fase: c.texto("fase"), proxima: c.tolera(SesionCarrera.self, "proxima"),
                  hoy_hecho: c.booleano("hoy_hecho"))
    }
}

extension SesionCarrera {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Clave.self)
        guard let dia = c.texto("dia"), let n = c.texto("n") else {
            throw DecodingError.dataCorruptedError(forKey: Clave("dia"), in: c, debugDescription: "sesión sin día")
        }
        self.init(dia: dia, n: n, tipo: c.texto("tipo"), hecho: c.booleano("hecho") ?? false)
    }
}

extension PesoHoy {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Clave.self)
        self.init(dia: c.texto("dia"), kg: c.tolera(Double.self, "kg"), media: c.tolera(Double.self, "media"))
    }
}

extension GastosHoy {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Clave.self)
        // {"error": ...} si gastos no responde: mejor nil que un ciclo con todo vacío
        guard !c.contains(Clave("error")) else {
            throw DecodingError.dataCorruptedError(forKey: Clave("error"), in: c, debugDescription: "gastos no responde")
        }
        self.init(total: c.tolera(Double.self, "total"), presu: c.tolera(Double.self, "presu"),
                  ayer: c.tolera(Double.self, "ayer"), inicio: c.texto("inicio"), fin: c.texto("fin"),
                  quedan: c.entero("quedan"), al_dia: c.tolera(Double.self, "al_dia"))
    }
}

extension EntrenoHoy {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Clave.self)
        guard let id = c.texto("id") else {
            throw DecodingError.dataCorruptedError(forKey: Clave("id"), in: c, debugDescription: "entreno sin id")
        }
        self.init(id: id, n: c.texto("n") ?? id, tipo: c.texto("tipo") ?? "otro", hecho: c.booleano("hecho") ?? false)
    }
}
