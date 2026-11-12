import SwiftUI
import WidgetKit

// Los widgets del entreno y de la semana de hábitos necesitan el plan y el registro de varios días, que /api/hoy no
// trae: salen de /api/state (con la copia de Local si no hay red, como Siri).

struct SesionPlan: Hashable {
    var dia: String
    var habito: String
    var nombre: String      // «Pull A · Espalda bíceps»
    var tipo: String        // pesas|carrera|movilidad|otro
    var hecho: Bool
}

struct HabitoSemana: Identifiable, Hashable {
    var id: String
    var n: String
    var c: String
    var goal: Int
    var plan: Set<String>   // días planificados de la semana
    var hechos: Set<String> // días hechos de la semana
}

struct DatosEstado {
    var hoy: String
    var semana: [String]
    var habitos: [HabitoSemana]
    /// Las sesiones de entreno de hoy a 7 días, en orden (las de hoy ya hechas incluidas).
    var sesiones: [SesionPlan]
    var copia: Date?

    /// La próxima sesión sin hacer.
    var proxima: SesionPlan? { sesiones.first { !$0.hecho } }

    static var muestra: DatosEstado {
        let hoy = Fecha.hoy()
        let semana = DiasSemana.semana(de: hoy)
        let tres = Array(semana.prefix(3))
        return DatosEstado(
            hoy: hoy, semana: semana,
            habitos: [
                HabitoSemana(id: "a", n: "Gimnasio", c: "#1baf7a", goal: 4, plan: Set(semana.prefix(4)), hechos: Set(tres.prefix(2))),
                HabitoSemana(id: "b", n: "Correr", c: "#eb6834", goal: 3, plan: Set(semana.dropFirst(1).prefix(3)), hechos: Set(tres.dropFirst())),
                HabitoSemana(id: "c", n: "Leer", c: "#3987e5", goal: 7, plan: Set(semana), hechos: Set(tres)),
            ],
            sesiones: [SesionPlan(dia: hoy, habito: "a", nombre: "Pull A · Espalda bíceps", tipo: "pesas", hecho: false),
                       SesionPlan(dia: semana.last ?? hoy, habito: "b", nombre: "Rodaje suave · 35 min", tipo: "carrera", hecho: false)],
            copia: nil)
    }

    /// Lee el JSON de /api/state (clean() del servidor: habits, log, plan, rutinas, sesion).
    init?(_ crudo: Data, copia: Date?) {
        guard let e = (try? JSONSerialization.jsonObject(with: crudo)) as? [String: Any] else { return nil }
        let hoy = Fecha.hoy()
        self.hoy = hoy
        self.copia = copia
        let sem = DiasSemana.semana(de: hoy)
        semana = sem

        func conjuntos(_ v: Any?) -> [String: Set<String>] {
            var out: [String: Set<String>] = [:]
            for (dia, ids) in (v as? [String: Any]) ?? [:] { out[dia] = Set((ids as? [String]) ?? []) }
            return out
        }
        let log = conjuntos(e["log"]), plan = conjuntos(e["plan"])
        let lista = (e["habits"] as? [[String: Any]]) ?? []
        habitos = lista.compactMap { h in
            guard let id = h["id"] as? String else { return nil }
            return HabitoSemana(id: id, n: (h["n"] as? String) ?? id, c: (h["c"] as? String) ?? "#888888",
                                goal: (h["goal"] as? NSNumber)?.intValue ?? 7,
                                plan: Set(sem.filter { plan[$0]?.contains(id) ?? false }),
                                hechos: Set(sem.filter { log[$0]?.contains(id) ?? false }))
        }

        // sesiones de entreno: hábitos con alguna rutina que no sea de movilidad (igual que es_entreno() del servidor)
        let rutinas = (e["rutinas"] as? [[String: Any]]) ?? []
        let nombreRutina = rutinas.reduce(into: [String: String]()) { acc, r in
            if let id = r["id"] as? String, let n = r["n"] as? String { acc[id] = n }
        }
        let tipoDeHabito = rutinas.reduce(into: [String: String]()) { acc, r in
            guard let hab = r["hab"] as? String, let tipo = r["tipo"] as? String, tipo != "movilidad" else { return }
            acc[hab] = tipo
        }
        let nombreHabito = lista.reduce(into: [String: String]()) { acc, h in
            if let id = h["id"] as? String, let n = h["n"] as? String { acc[id] = n }
        }
        let sesion = (e["sesion"] as? [String: [String: String]]) ?? [:]
        var sesiones: [SesionPlan] = []
        let cal = Calendar(identifier: .gregorian)
        for i in 0..<7 {
            guard let d = cal.date(byAdding: .day, value: i, to: DiasSemana.fecha(hoy) ?? Date()) else { continue }
            let dia = Fecha.dia(d)
            for hid in (e["plan"] as? [String: [String]])?[dia] ?? [] {
                guard let tipo = tipoDeHabito[hid] else { continue }
                let nombre = sesion[dia]?[hid].flatMap { nombreRutina[$0] } ?? nombreHabito[hid] ?? "Entreno"
                sesiones.append(SesionPlan(dia: dia, habito: hid, nombre: nombre, tipo: tipo, hecho: log[dia]?.contains(hid) ?? false))
            }
        }
        self.sesiones = sesiones
    }

    init(hoy: String, semana: [String], habitos: [HabitoSemana], sesiones: [SesionPlan], copia: Date?) {
        self.hoy = hoy
        self.semana = semana
        self.habitos = habitos
        self.sesiones = sesiones
        self.copia = copia
    }
}

enum EstadoDatos {
    case sinClaves
    case datos(DatosEstado)
    case sinDatos(String)
}

struct EntradaEstado: TimelineEntry {
    let date: Date
    let estado: EstadoDatos
}

struct ProveedorEstado: TimelineProvider {
    func placeholder(in context: Context) -> EntradaEstado {
        EntradaEstado(date: Date(), estado: .datos(.muestra))
    }

    func getSnapshot(in context: Context, completion: @escaping (EntradaEstado) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task { completion(EntradaEstado(date: Date(), estado: await Self.carga())) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EntradaEstado>) -> Void) {
        Task {
            let ahora = Date()
            let entrada = EntradaEstado(date: ahora, estado: await Self.carga())
            completion(Timeline(entries: [entrada], policy: .after(ahora.addingTimeInterval(30 * 60))))
        }
    }

    static func carga() async -> EstadoDatos {
        guard Almacen.claves != nil else { return .sinClaves }
        do {
            let (crudo, copia) = try await API.leeOCopia("/api/state")
            guard let datos = DatosEstado(crudo, copia: copia) else { return .sinDatos("No entiendo lo que devuelve el servidor") }
            return .datos(datos)
        } catch {
            return .sinDatos(error.localizedDescription)
        }
    }
}
