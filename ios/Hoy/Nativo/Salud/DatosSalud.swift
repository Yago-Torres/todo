import Foundation
import SwiftUI
import Observation

// Lo que devuelve GET /api/sueno (el mismo que pinta salud.html): las últimas 30 noches con sus pasos, la última noche
// hora a hora y el cuerpo (peso y composición, 120 días).

struct NotaSueno: Codable, Hashable {
    var total: Int
    var duracion: Int
    var hora: Int
    var interrupciones: Int

    /// Los mismos tramos que la web: 96 o más muy alta, 80 alta, 70 aceptable, 40 baja.
    var nivel: String {
        total >= 96 ? "Muy alta" : total >= 80 ? "Alta" : total >= 70 ? "Aceptable" : total >= 40 ? "Baja" : "Muy baja"
    }
}

struct NocheSueno: Codable, Identifiable, Hashable {
    var dia: String
    var sueno: Double?
    var pasos: Double?
    var fases: [String: Double]?
    var nota: NotaSueno?
    var acostarse: String?
    var levantarse: String?

    var id: String { dia }
    var fecha: Date { FechasES.fecha(dia) ?? Date() }
}

/// Un tramo de la noche: [fase, inicio ISO, minutos].
struct TramoSueno: Codable, Identifiable, Hashable {
    var fase: String
    var inicio: Date
    var minutos: Double

    var id: Date { inicio }
    var fin: Date { inicio.addingTimeInterval(minutos * 60) }

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        fase = try c.decode(String.self)
        let texto = try c.decode(String.self)
        minutos = try c.decode(Double.self)
        guard let d = Self.lee(texto) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Hora no válida: \(texto)"))
        }
        inicio = d
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(fase)
        try c.encode(Self.escribe(inicio))
        try c.encode(minutos)
    }

    private static func formateador(_ formato: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = formato
        return f
    }

    private static func lee(_ s: String) -> Date? {
        let limpio = String(s.prefix(19))
        return formateador("yyyy-MM-dd'T'HH:mm:ss").date(from: limpio)
            ?? formateador("yyyy-MM-dd'T'HH:mm").date(from: String(s.prefix(16)))
    }

    private static func escribe(_ d: Date) -> String { formateador("yyyy-MM-dd'T'HH:mm:ss").string(from: d) }
}

struct AnocheSueno: Codable, Hashable {
    var dia: String
    var nota: NotaSueno?
    var acostarse: String?
    var levantarse: String?
    var sueno: Double?
    var tramos: [TramoSueno]?
}

/// [día, kg]
struct PesajeCuerpo: Codable, Hashable {
    var dia: String
    var kg: Double

    init(dia: String, kg: Double) {
        self.dia = dia
        self.kg = kg
    }

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        dia = try c.decode(String.self)
        kg = try c.decode(Double.self)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(dia)
        try c.encode(kg)
    }
}

/// [día, grasa %, masa magra kg, IMC]; no llegan siempre los tres.
struct CompCuerpo: Codable, Hashable {
    var dia: String
    var grasa: Double?
    var magra: Double?
    var imc: Double?

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        dia = try c.decode(String.self)
        grasa = Self.opcional(&c)
        magra = Self.opcional(&c)
        imc = Self.opcional(&c)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(dia)
        for v in [grasa, magra, imc] {
            if let v { try c.encode(v) } else { try c.encodeNil() }
        }
    }

    private static func opcional(_ c: inout UnkeyedDecodingContainer) -> Double? {
        if c.isAtEnd { return nil }
        if (try? c.decodeNil()) == true { return nil }
        return try? c.decode(Double.self)
    }
}

struct CuerpoSalud: Decodable, Hashable {
    var peso: [PesajeCuerpo]
    var comp: [CompCuerpo]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Claves.self)
        peso = (try? c.decode([PesajeCuerpo].self, forKey: .peso)) ?? []
        comp = (try? c.decode([CompCuerpo].self, forKey: .comp)) ?? []
    }

    init(peso: [PesajeCuerpo] = [], comp: [CompCuerpo] = []) {
        self.peso = peso
        self.comp = comp
    }

    private enum Claves: String, CodingKey { case peso, comp }
}

struct InformeSueno: Decodable {
    var noches: [NocheSueno]
    var anoche: AnocheSueno?
    var cuerpo: CuerpoSalud

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Claves.self)
        noches = (try? c.decode([NocheSueno].self, forKey: .noches)) ?? []
        anoche = try? c.decode(AnocheSueno.self, forKey: .anoche)
        cuerpo = (try? c.decode(CuerpoSalud.self, forKey: .cuerpo)) ?? CuerpoSalud()
    }

    private enum Claves: String, CodingKey { case noches, anoche, cuerpo }
}

/// Un pesaje con la media de los 7 días que acaban en él (el peso diario rebota con el agua, la media no).
struct PuntoPeso: Identifiable, Hashable {
    var dia: String
    var kg: Double
    var media: Double?
    var id: String { dia }
    var fecha: Date { FechasES.fecha(dia) ?? Date() }
}

enum FaseSueno: String, CaseIterable, Identifiable {
    case deep, core, rem, awake

    var id: String { rawValue }

    var nombre: String {
        switch self {
        case .deep: return "Profundo"
        case .core: return "Básico"
        case .rem: return "REM"
        case .awake: return "Despierto"
        }
    }

    /// Los colores de la web (validados para daltonismo): son de la fase, no del tema, para que signifiquen lo mismo.
    var color: Color {
        switch self {
        case .deep: return Color(uiColor: .dinamico(claro: "#2a78d6", oscuro: "#3987e5"))
        case .core: return Color(uiColor: .dinamico(claro: "#1baf7a", oscuro: "#199e70"))
        case .rem: return Color(uiColor: .dinamico(claro: "#eda100", oscuro: "#c98500"))
        case .awake: return Color(uiColor: .dinamico(claro: "#e34948", oscuro: "#e85580"))
        }
    }

    /// De arriba abajo en la noche (despierto arriba, profundo abajo).
    static let deArribaAbajo: [FaseSueno] = [.awake, .rem, .core, .deep]
    /// En el orden en que se apilan las barras (profundo abajo).
    static let apilado: [FaseSueno] = [.deep, .core, .rem, .awake]
}

enum PeriodoSalud: Int, CaseIterable, Identifiable {
    case semana = 7, quincena = 14, mes = 30, trimestre = 90

    var id: Int { rawValue }
    var titulo: String { "\(rawValue) días" }
    /// El servidor manda las últimas 30 noches (el peso, 120 días).
    var noches: Int { min(rawValue, 30) }
}

@MainActor @Observable
final class DatosSalud {
    static let shared = DatosSalud()

    private(set) var informe: InformeSueno?
    /// La fecha de la copia si lo que se ve no viene fresco del servidor (sin red).
    private(set) var copia: Date?
    private(set) var cargando = false
    private(set) var error: String?
    private var ultimaCarga: Date?

    init() {
        if let r = Local.lee(Local.clave("GET", "/api/sueno")),
           let i = try? JSONDecoder().decode(InformeSueno.self, from: r.cuerpo) {
            informe = i
        }
    }

    func carga(margen: TimeInterval = 20) async {
        if let ultimaCarga, Date().timeIntervalSince(ultimaCarga) < margen { return }
        guard !cargando else { return }
        cargando = true
        defer { cargando = false }
        do {
            let (crudo, fecha) = try await API.leeOCopia("/api/sueno")
            let nuevo = try JSONDecoder().decode(InformeSueno.self, from: crudo)
            informe = nuevo
            copia = fecha
            error = nil
            ultimaCarga = Date()
        } catch let e as DecodingError {
            error = "No entiendo lo que devuelve /api/sueno (\(e.localizedDescription))"
        } catch {
            self.error = error.localizedDescription
        }
    }

    func recarga() async {
        ultimaCarga = nil
        await carga()
    }

    // MARK: lo que se pinta

    func noches(_ periodo: PeriodoSalud) -> [NocheSueno] {
        Array((informe?.noches ?? []).suffix(periodo.noches))
    }

    /// Todos los pesajes con su media de 7 días, calculada sobre la serie entera.
    private var todosLosPesos: [PuntoPeso] {
        let p = informe?.cuerpo.peso ?? []
        return p.map { x in
            let desde = FechasES.masDias(x.dia, -6)
            let v = p.filter { $0.dia >= desde && $0.dia <= x.dia }.map(\.kg)
            return PuntoPeso(dia: x.dia, kg: x.kg, media: v.isEmpty ? nil : v.reduce(0, +) / Double(v.count))
        }
    }

    func pesos(_ periodo: PeriodoSalud) -> [PuntoPeso] {
        let desde = FechasES.masDias(Fecha.hoy(), -(periodo.rawValue - 1))
        return todosLosPesos.filter { $0.dia >= desde }
    }

    /// Cuánto ha cambiado la media en los últimos 30 días (nil si no hay pesaje de entonces).
    var cambioPeso30: Double? {
        guard let ultimo = todosLosPesos.last, let m = ultimo.media else { return nil }
        let limite = FechasES.masDias(ultimo.dia, -30)
        guard let antes = todosLosPesos.last(where: { $0.dia <= limite }), let ma = antes.media else { return nil }
        return m - ma
    }

    func comp(_ periodo: PeriodoSalud) -> [CompCuerpo] {
        let desde = FechasES.masDias(Fecha.hoy(), -(periodo.rawValue - 1))
        return (informe?.cuerpo.comp ?? []).filter { $0.dia >= desde }
    }

    /// El último valor de la composición que haya llegado (no vienen siempre juntos) y su cambio en 30 días.
    func ultimaComp(_ valor: KeyPath<CompCuerpo, Double?>) -> (actual: Double, cambio: Double?)? {
        let filas = informe?.cuerpo.comp ?? []
        guard let ultima = filas.last(where: { $0[keyPath: valor] != nil }), let actual = ultima[keyPath: valor] else { return nil }
        let limite = FechasES.masDias(ultima.dia, -30)
        let antes = filas.last(where: { $0.dia <= limite && $0[keyPath: valor] != nil })?[keyPath: valor]
        return (actual, antes.map { actual - $0 })
    }
}
