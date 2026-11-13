import Foundation
import SwiftUI
import Observation
import WidgetKit

/// Una racha tal como la cuenta el servidor (GET /api/rachas, `rachas()` en main.py: la ÚNICA regla, la misma que la web).
/// Aquí no se cuenta nada: solo se suma el «hecho» de hoy a `base` para que marcar se vea al momento.
struct RachaHabito: Identifiable, Hashable {
    var id: String
    var n: String
    var c: String
    var racha: Int
    /// La racha hasta ayer: marcar hoy suma uno.
    var base: Int
    var hecho: Bool
    /// Hoy la pide (planificado, diario o se acaba su ventana).
    var exigido: Bool
    var enJuego: Bool
    /// Hoy descansa (descanso, vacaciones, enfermedad, comodin): la racha está congelada.
    var libre: String?
    var siguiente: Int?
    /// Mañana la pide (para los avisos de mañana).
    var manana: Bool
    /// Día → hecho | descanso | vacaciones | enfermedad | comodin | fallo | pendiente (últimas 6 semanas).
    var dias: [String: String]
}

/// Unas vacaciones, una enfermedad o un descanso de varios días: no se exige nada y las rachas se congelan.
struct PeriodoLibre: Identifiable, Hashable {
    var id: String
    var desde: String
    var hasta: String
    /// Vacío = todos los hábitos.
    var habitos: [String]
    var motivo: String
}

/// Lo de las rachas en nativo: lee /api/rachas (sin red, la copia de Local) y manda descansos, comodines y vacaciones
/// por la cola (POST /api/descanso, /api/comodin, /api/vacaciones: idempotentes, como /api/marca).
@MainActor @Observable
final class DatosRachas {
    static let shared = DatosRachas()
    static let ruta = "/api/rachas"

    private(set) var dia: String = ""
    private(set) var habitos: [RachaHabito] = []
    private(set) var hitos: [Int] = [7, 14, 30, 50, 100, 200, 365, 500, 1000]
    private(set) var alMes = 2
    private(set) var usados: [String] = []
    private(set) var quedan = 0
    private(set) var comodinHoy = false
    private(set) var vacaciones: [PeriodoLibre] = []
    /// Los hábitos que descansan hoy ("*" = todos).
    private(set) var descansos: Set<String> = []
    private(set) var copia: Date?
    var error: String?
    private var ultimaCarga: Date?

    init() {
        if let r = Local.lee(Local.clave("GET", Self.ruta)) { lee(r.cuerpo) }
    }

    func carga(margen: TimeInterval = 20) async {
        if let ultimaCarga, Date().timeIntervalSince(ultimaCarga) < margen, dia == Fecha.hoy() { return }
        do {
            let (crudo, fecha) = try await API.leeOCopia(Self.ruta)
            lee(crudo)
            copia = fecha
            ultimaCarga = fecha == nil ? Date() : nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func recarga() async {
        ultimaCarga = nil
        await carga()
    }

    /// Lo que devuelve /api/rachas (y cada POST de rachas, que contesta lo mismo ya cambiado).
    func lee(_ crudo: Data) {
        guard let o = (try? JSONSerialization.jsonObject(with: crudo)) as? [String: Any] else { return }
        func entero(_ v: Any?) -> Int? { (v as? NSNumber)?.intValue }
        dia = (o["hoy"] as? String) ?? Fecha.hoy()
        hitos = ((o["hitos"] as? [Any]) ?? []).compactMap(entero)
        if hitos.isEmpty { hitos = [7, 14, 30, 50, 100, 200, 365, 500, 1000] }
        habitos = ((o["habitos"] as? [[String: Any]]) ?? []).compactMap { h in
            guard let id = h["id"] as? String else { return nil }
            return RachaHabito(id: id, n: (h["n"] as? String) ?? id, c: (h["c"] as? String) ?? "#888888",
                               racha: entero(h["racha"]) ?? 0, base: entero(h["base"]) ?? 0,
                               hecho: (h["hecho"] as? Bool) ?? false, exigido: (h["exigido"] as? Bool) ?? false,
                               enJuego: (h["en_juego"] as? Bool) ?? false, libre: h["libre"] as? String,
                               siguiente: entero(h["siguiente"]), manana: (h["manana"] as? Bool) ?? false,
                               dias: (h["dias"] as? [String: String]) ?? [:])
        }
        let c = (o["comodines"] as? [String: Any]) ?? [:]
        alMes = entero(c["al_mes"]) ?? 2
        usados = (c["usados"] as? [String]) ?? []
        quedan = entero(c["quedan"]) ?? 0
        comodinHoy = (c["hoy"] as? Bool) ?? false
        vacaciones = ((o["vacaciones"] as? [[String: Any]]) ?? []).compactMap { p in
            guard let id = p["id"] as? String, let de = p["desde"] as? String, let a = p["hasta"] as? String else { return nil }
            return PeriodoLibre(id: id, desde: de, hasta: a, habitos: (p["habitos"] as? [String]) ?? [],
                                motivo: (p["motivo"] as? String) ?? "vacaciones")
        }
        descansos = Set((o["descansos"] as? [String]) ?? [])
    }

    // MARK: lo que se pinta (con lo marcado ahora mismo en Hoy, que cambia antes que el servidor)

    /// ¿Está hecho hoy? Lo de DatosNativos manda: se marca allí al momento (y sin red).
    func hechoAhora(_ r: RachaHabito) -> Bool {
        guard dia == Fecha.hoy() else { return false }
        return DatosNativos.shared.hoy?.habitos.first(where: { $0.id == r.id })?.hecho ?? r.hecho
    }

    /// La racha que se ve: hasta ayer + hoy si está hecho.
    func racha(_ r: RachaHabito) -> Int { dia == Fecha.hoy() ? r.base + (hechoAhora(r) ? 1 : 0) : r.racha }

    /// Por qué descansa hoy, en el mismo orden que `libre()` del servidor: descanso, periodo, comodín.
    func libreHoy(_ r: RachaHabito) -> String? {
        if hechoAhora(r) { return nil }
        if descansos.contains(r.id) || descansos.contains("*") { return "descanso" }
        if let p = vacaciones.first(where: { $0.desde <= dia && dia <= $0.hasta && ($0.habitos.isEmpty || $0.habitos.contains(r.id)) }) {
            return p.motivo
        }
        return comodinHoy ? "comodin" : nil
    }

    /// En juego ahora: el servidor dice que hoy la pide y aún no se ha marcado ni puesto a descansar.
    func enJuego(_ r: RachaHabito) -> Bool { dia == Fecha.hoy() && r.enJuego && !hechoAhora(r) && libreHoy(r) == nil }

    var enJuegoHoy: [RachaHabito] { habitos.filter { enJuego($0) }.sorted { $0.base > $1.base } }

    /// Las rachas que hay que enseñar: vivas o en juego, de la más larga a la más corta.
    var vivas: [RachaHabito] {
        habitos.filter { racha($0) > 0 || enJuego($0) }.sorted { (racha($0), $0.n) > (racha($1), $1.n) }
    }

    /// El siguiente hito para una racha de n días (7, 14, 30…).
    func siguienteHito(_ n: Int) -> Int? { hitos.first { $0 > n } }

    /// El hito anterior (o 0), para pintar la barra de lo que falta.
    func hitoAnterior(_ n: Int) -> Int { hitos.last { $0 <= n } ?? 0 }

    /// «Mantén tu racha de 12 días: Gimnasio y Core», con lo que queda en juego ahora mismo.
    var llamada: (dias: Int, habitos: [RachaHabito])? {
        let j = enJuegoHoy
        guard let mayor = j.first else { return nil }
        return (mayor.base, j)
    }

    /// Cómo está un día de un hábito en el calendario. Los días por venir salen de las vacaciones ya puestas.
    func estado(_ id: String, _ dia: String) -> String? {
        if dia > self.dia {
            return vacaciones.first { $0.desde <= dia && dia <= $0.hasta && ($0.habitos.isEmpty || $0.habitos.contains(id)) }?.motivo
        }
        if dia == self.dia, let r = habitos.first(where: { $0.id == id }) {
            return hechoAhora(r) ? "hecho" : libreHoy(r) ?? (enJuego(r) ? "pendiente" : nil)
        }
        return habitos.first { $0.id == id }?.dias[dia]
    }

    static func icono(_ libre: String) -> String {
        switch libre {
        case "comodin": return "snowflake"
        case "vacaciones": return "beach.umbrella"
        case "enfermedad": return "bed.double.fill"
        default: return "leaf.fill"
        }
    }

    static func nombre(_ libre: String) -> String {
        switch libre {
        case "comodin": return "Comodín"
        case "vacaciones": return "Vacaciones"
        case "enfermedad": return "Enfermedad"
        default: return "Descanso"
        }
    }

    static func nombres(_ xs: [String]) -> String {
        guard let ultimo = xs.last else { return "" }
        return xs.count == 1 ? ultimo : xs.dropLast().joined(separator: ", ") + " y " + ultimo
    }

    static func dias(_ n: Int) -> String { n == 1 ? "1 día" : "\(n) días" }

    // MARK: escribir (primero en pantalla; sin red, a la cola)

    /// Descansar hoy (o un día) un hábito; nil = todos. `quita` lo deshace.
    func descansa(_ id: String?, dia: String = Fecha.hoy(), quita: Bool = false) async {
        let clave = id ?? "*"
        let antes = descansos
        if dia == self.dia {
            withAnimation(Tema.Muelle.toque) {
                if quita { descansos.remove(clave) } else { descansos.insert(clave) }
            }
        }
        var json: [String: Any] = ["dia": dia, "id": clave]
        if quita { json["quita"] = true }
        await manda("/api/descanso", json) { self.descansos = antes }
    }

    /// Gasta un comodín hoy (congela todas las rachas), o lo devuelve.
    func usaComodin(quita: Bool = false) async {
        guard quita || quedan > 0 || comodinHoy else {
            error = "No te quedan comodines este mes. Puedes poner «Descansar hoy» a los hábitos que no vayas a hacer."
            return
        }
        let (antesHoy, antesQuedan) = (comodinHoy, quedan)
        withAnimation(Tema.Muelle.toque) {
            if quita, comodinHoy { comodinHoy = false; quedan += 1 } else if !quita, !comodinHoy { comodinHoy = true; quedan -= 1 }
        }
        var json: [String: Any] = ["dia": Fecha.hoy()]
        if quita { json["quita"] = true }
        await manda("/api/comodin", json) { self.comodinHoy = antesHoy; self.quedan = antesQuedan }
    }

    func ponAlMes(_ n: Int) async {
        let antes = alMes
        let usadosMes = alMes - quedan
        alMes = n
        quedan = max(0, n - usadosMes)
        await manda("/api/comodin", ["al_mes": n]) { self.alMes = antes; self.quedan = max(0, antes - usadosMes) }
    }

    /// Crea o cambia un periodo. El id lo pone el iPhone: si sale dos veces desde la cola, no se duplica.
    func guarda(_ p: PeriodoLibre) async {
        let antes = vacaciones
        withAnimation(Tema.Muelle.pantalla) {
            vacaciones = (vacaciones.filter { $0.id != p.id } + [p]).sorted { $0.desde < $1.desde }
        }
        await manda("/api/vacaciones", ["id": p.id, "desde": p.desde, "hasta": p.hasta, "habitos": p.habitos, "motivo": p.motivo]) {
            self.vacaciones = antes
        }
    }

    func borra(_ p: PeriodoLibre) async {
        let antes = vacaciones
        withAnimation(Tema.Muelle.pantalla) { vacaciones.removeAll { $0.id == p.id } }
        await manda("/api/vacaciones", ["id": p.id, "quita": true]) { self.vacaciones = antes }
    }

    private func manda(_ ruta: String, _ json: [String: Any], deshaz: @escaping () -> Void) async {
        do {
            if let respuesta = try await API.escribeOEncola(ruta, json: json) {
                lee(respuesta)   // contesta con las rachas ya recalculadas
                copia = nil
            }
            error = nil
            await DatosNativos.shared.recarga()   // Hoy y los widgets: «libre» y «juego» de cada hábito
            WidgetCenter.shared.reloadAllTimelines()
            await Avisos.programa()   // lo que ya no está en juego no avisa
        } catch {
            withAnimation(Tema.Muelle.toque) { deshaz() }
            self.error = error.localizedDescription
            Haptica.shared.toca(.error)
        }
    }
}
