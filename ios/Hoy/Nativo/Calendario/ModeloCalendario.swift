import SwiftUI

// El calendario de todo (GET /api/calendario): eventos propios (el servidor los copia a Google y a iCloud) y las
// tareas del vault con fecha. Aquí solo la forma de los datos y las cuentas de fechas; nada de EventKit.

/// Un calendario de destino («day-to-day», «Deporte»…) con su color.
struct CalendarioTom: Codable, Identifiable, Hashable {
    var id: String
    var n: String
    var color: String

    var tinta: Color { Color(hex: color) }
}

/// Cómo va la copia de un evento en cada sitio: "ok", "pendiente" o "error: …".
struct SincroCal: Codable, Hashable {
    var google: String?
    var icloud: String?

    var falla: Bool { [google, icloud].contains { ($0 ?? "").hasPrefix("error") } }
    var pendiente: Bool { [google, icloud].contains { $0 == "pendiente" } }
    var detalle: String {
        [("Google", google), ("iCloud", icloud)].compactMap { n, v in v.map { "\(n): \($0)" } }.joined(separator: " · ")
    }
}

/// Una ocurrencia de un evento en el rango pedido. Los de una serie comparten `id` (la serie) y cambian `dia`.
struct EventoCal: Codable, Identifiable, Hashable {
    var id: String
    var t: String
    var dia: String
    var origen: String
    var finDia: String
    var inicio: String
    var fin: String
    var cal: String
    var nota: String
    var lugar: String
    var aviso: Int
    var repite: String
    var hasta: String
    var sincro: SincroCal?
    /// "dia:idHabito" si sale del plan de Entreno: lo cuadra el servidor y aquí no se edita.
    var entreno: String = ""

    /// Para ForEach: una serie repite id en cada día.
    var clave: String { "\(id)|\(dia)" }
    var todoElDia: Bool { inicio.isEmpty }
    var provisional: Bool { id.hasPrefix("tmp:") }

    /// ¿Ocupa ese día? (los de varios días, de `dia` a `finDia`)
    func cubre(_ d: String) -> Bool { dia <= d && d <= max(dia, finDia) }

    enum CodingKeys: String, CodingKey {
        case id, t, dia, origen, finDia = "fin_dia", inicio, fin, cal, nota, lugar, aviso, repite, hasta, sincro, entreno
    }

    init(id: String, t: String, dia: String, origen: String = "", finDia: String = "", inicio: String = "", fin: String = "",
         cal: String = "", nota: String = "", lugar: String = "", aviso: Int = -1, repite: String = "", hasta: String = "",
         sincro: SincroCal? = nil) {
        self.id = id; self.t = t; self.dia = dia; self.origen = origen.isEmpty ? dia : origen
        self.finDia = finDia.isEmpty ? dia : finDia; self.inicio = inicio; self.fin = fin; self.cal = cal
        self.nota = nota; self.lugar = lugar; self.aviso = aviso; self.repite = repite; self.hasta = hasta; self.sincro = sincro
    }

    // tolerante: lo que falte, vacío (el servidor es nuevo y puede omitir claves)
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys) -> String { (try? c.decodeIfPresent(String.self, forKey: k)) ?? "" }
        id = s(.id); t = s(.t); dia = s(.dia)
        origen = s(.origen).isEmpty ? dia : s(.origen)
        finDia = s(.finDia).isEmpty ? dia : s(.finDia)
        inicio = s(.inicio); fin = s(.fin); cal = s(.cal); nota = s(.nota); lugar = s(.lugar)
        aviso = (try? c.decodeIfPresent(Int.self, forKey: .aviso)) ?? -1
        repite = s(.repite); hasta = s(.hasta)
        sincro = try? c.decodeIfPresent(SincroCal.self, forKey: .sincro)
        entreno = s(.entreno)
    }
}

/// Una tarea del vault con fecha (Pendientes). Con hora es un recordatorio: el bot avisa por Telegram.
struct TareaCal: Codable, Identifiable, Hashable {
    var id: String
    var t: String
    var due: String
    var hora: String
    var hecha: Bool
    var estado: String
    var nota: String

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys) -> String { (try? c.decodeIfPresent(String.self, forKey: k)) ?? "" }
        id = s(.id); t = s(.t); due = s(.due); hora = s(.hora); estado = s(.estado); nota = s(.nota)
        hecha = (try? c.decodeIfPresent(Bool.self, forKey: .hecha)) ?? false
    }

    init(id: String, t: String, due: String, hora: String = "", hecha: Bool = false, estado: String = "nueva", nota: String = "") {
        self.id = id; self.t = t; self.due = due; self.hora = hora; self.hecha = hecha; self.estado = estado; self.nota = nota
    }

    var provisional: Bool { id.hasPrefix("tmp:") }
}

struct RespuestaCal: Codable {
    var hoy: String?
    var calendarios: [CalendarioTom]?
    var eventos: [EventoCal]?
    var tareas: [TareaCal]?
}

/// Lo que sale en un día: un evento o una tarea, para pintarlos juntos y en orden.
enum ElementoDiaCal: Identifiable, Hashable {
    case evento(EventoCal)
    case tarea(TareaCal)

    var id: String {
        switch self {
        case .evento(let e): return "e|" + e.clave
        case .tarea(let t): return "t|" + t.id
        }
    }

    /// Para ordenar: lo de todo el día primero, luego por hora.
    var orden: String {
        switch self {
        case .evento(let e): return e.todoElDia ? "0" : "1" + e.inicio
        case .tarea(let t): return t.hora.isEmpty ? "0~" : "1" + t.hora
        }
    }
}

/// Qué se crea con el «+»: un evento (al calendario), una tarea con fecha o un recordatorio (tarea con hora).
enum TipoElementoCal: String, CaseIterable, Identifiable {
    case evento, tarea, recordatorio
    var id: String { rawValue }
    var nombre: String {
        switch self {
        case .evento: return "Evento"
        case .tarea: return "Tarea"
        case .recordatorio: return "Recordatorio"
        }
    }
}

enum VistaCal: String, CaseIterable, Identifiable {
    case mes, semana, dia, agenda
    var id: String { rawValue }
    var nombre: String {
        switch self {
        case .mes: return "Mes"
        case .semana: return "Semana"
        case .dia: return "Día"
        case .agenda: return "Agenda"
        }
    }
}

/// Fechas como las manda el servidor («yyyy-MM-dd», «HH:mm») y la rejilla del mes (lunes primero).
enum UtilCal {
    static var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = FechasES.locale
        c.firstWeekday = 2
        c.timeZone = .current
        return c
    }

    static func dia(_ d: Date) -> String { FechasES.texto(d, "yyyy-MM-dd") }
    static func fecha(_ s: String) -> Date { FechasES.fecha(s) ?? Date() }
    static func hoy() -> String { dia(Date()) }

    static func suma(_ s: String, dias n: Int) -> String {
        dia(cal.date(byAdding: .day, value: n, to: fecha(s)) ?? fecha(s))
    }

    static func suma(_ s: String, meses n: Int) -> String {
        dia(cal.date(byAdding: .month, value: n, to: fecha(s)) ?? fecha(s))
    }

    /// El primer día del mes de `s`.
    static func inicioMes(_ s: String) -> String { String(s.prefix(8)) + "01" }

    /// El lunes de la semana de `s`.
    static func lunes(_ s: String) -> String {
        let d = fecha(s)
        let wd = cal.component(.weekday, from: d)   // 1 domingo … 7 sábado
        return suma(s, dias: -((wd + 5) % 7))
    }

    /// Las 6 semanas que pinta la vista Mes (de lunes a domingo).
    static func rejillaMes(_ s: String) -> [String] {
        let primero = lunes(inicioMes(s))
        return (0..<42).map { suma(primero, dias: $0) }
    }

    static func dias(desde: String, _ n: Int) -> [String] { (0..<n).map { suma(desde, dias: $0) } }

    static func minutos(_ hhmm: String) -> Int? {
        let p = hhmm.split(separator: ":")
        guard p.count == 2, let h = Int(p[0]), let m = Int(p[1]) else { return nil }
        return h * 60 + m
    }

    static func hhmm(_ minutos: Int) -> String {
        let m = max(0, min(23 * 60 + 59, minutos))
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    /// Fecha y hora juntas (para los DatePicker).
    static func fechaHora(_ dia: String, _ hora: String) -> Date {
        let base = cal.startOfDay(for: fecha(dia))
        return cal.date(byAdding: .minute, value: minutos(hora) ?? 9 * 60, to: base) ?? base
    }

    static func hora(_ d: Date) -> String { FechasES.texto(d, "HH:mm") }

    static func titulo(_ s: String, _ formato: String) -> String {
        let t = FechasES.texto(fecha(s), formato)
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    /// «hoy», «mañana», «ayer» o «jueves 20 nov».
    static func cercano(_ s: String, hoy: String) -> String {
        if s == hoy { return "Hoy" }
        if s == suma(hoy, dias: 1) { return "Mañana" }
        if s == suma(hoy, dias: -1) { return "Ayer" }
        return titulo(s, "EEEE d MMM")
    }

    static let avisos: [(minutos: Int, nombre: String)] = [
        (-1, "Sin aviso"), (0, "A la hora"), (5, "5 min antes"), (10, "10 min antes"), (15, "15 min antes"),
        (30, "30 min antes"), (60, "1 hora antes"), (120, "2 horas antes"), (1440, "1 día antes"),
    ]

    static let repeticiones: [(valor: String, nombre: String)] = [
        ("", "No se repite"), ("diario", "Cada día"), ("semanal", "Cada semana"), ("mensual", "Cada mes"), ("anual", "Cada año"),
    ]
}
