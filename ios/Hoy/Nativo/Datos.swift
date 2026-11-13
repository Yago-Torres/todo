import Foundation
import SwiftUI
import Observation
import WidgetKit

/// Lo que enseñan Hoy y Hábitos en nativo. Lee /api/hoy y /api/state (sin red, la copia de Local) y marca al momento:
/// la pantalla cambia antes de que conteste el servidor y, si no hay red, el cambio va a la cola de Local (SinRed.swift).
@MainActor @Observable
final class DatosNativos {
    static let shared = DatosNativos()

    struct HabitoEstado: Identifiable, Hashable {
        var id: String
        var n: String
        var c: String
        var goal: Int
        var cada: Int
    }

    private(set) var hoy: Hoy?
    /// Los hábitos y el log del estado entero (/api/state), para la pantalla de Hábitos.
    private(set) var habitos: [HabitoEstado] = []
    private(set) var log: [String: Set<String>] = [:]
    private(set) var plan: [String: Set<String>] = [:]
    /// La fecha de la copia si lo que se ve no viene fresco del servidor (sin red).
    private(set) var copia: Date?
    private(set) var cargando = false
    private(set) var error: String?
    /// Tareas marcadas como hechas en esta sesión: desaparecen de la lista sin esperar a recargar.
    private(set) var tareasHechas: Set<String> = []

    private var ultimaCarga: Date?

    init() {
        // lo último que se vio, para pintar al instante al abrir la app
        if let r = Local.lee(Local.clave("GET", "/api/hoy")), let h = try? JSONDecoder().decode(Hoy.self, from: r.cuerpo) {
            hoy = h
        } else {
            hoy = Almacen.leeHoy()
        }
        // el estado entero (solo lo usa Hábitos, y pesa) justo después del primer fotograma de Hoy
        Task { @MainActor [weak self] in
            guard let self, self.habitos.isEmpty, let r = Local.lee(Local.clave("GET", "/api/state")) else { return }
            self.leeEstado(r.cuerpo)
        }
    }

    /// Recarga si hace más de `margen` segundos de la última vez (al volver a la pestaña no se pide cada vez).
    func carga(margen: TimeInterval = 20) async {
        if let ultimaCarga, Date().timeIntervalSince(ultimaCarga) < margen { return }
        guard !cargando else { return }
        cargando = true
        defer { cargando = false }
        do {
            let (crudo, fecha) = try await API.leeOCopia("/api/hoy")
            let nuevo = try JSONDecoder().decode(Hoy.self, from: crudo)
            if fecha == nil { Almacen.guardaHoy(crudo) }
            // lo que ya se veía (la copia de Local) cambia a lo nuevo con el muelle, sin parpadeos
            withAnimation(Tema.Muelle.pantalla) { hoy = nuevo }
            copia = fecha
            error = nil
            ultimaCarga = Date()
            tareasHechas = []
            actualizaIsla()
        } catch {
            self.error = error.localizedDescription
        }
        if let r = try? await API.leeOCopia("/api/state") {
            withAnimation(Tema.Muelle.pantalla) { leeEstado(r.datos) }
        }
    }

    func recarga() async {
        ultimaCarga = nil
        await carga()
    }

    /// Vuelve a pintar lo que hay en la copia local (tras apuntar un cambio en la cola o al salir de ella).
    func refrescaDesdeLocal() {
        if let r = Local.lee(Local.clave("GET", "/api/state")) { leeEstado(r.cuerpo) }
        if let r = Local.lee(Local.clave("GET", "/api/hoy")), let h = try? JSONDecoder().decode(Hoy.self, from: r.cuerpo) {
            withAnimation(Tema.Muelle.toque) { hoy = h }
            actualizaIsla()
        }
    }

    func leeEstado(_ crudo: Data) {
        guard let e = (try? JSONSerialization.jsonObject(with: crudo)) as? [String: Any] else { return }
        habitos = ((e["habits"] as? [[String: Any]]) ?? []).compactMap { h in
            guard let id = h["id"] as? String else { return nil }
            return HabitoEstado(id: id, n: (h["n"] as? String) ?? id, c: (h["c"] as? String) ?? "#888888",
                                goal: (h["goal"] as? NSNumber)?.intValue ?? 7, cada: (h["cada"] as? NSNumber)?.intValue ?? 1)
        }
        log = Self.conjuntos(e["log"])
        plan = Self.conjuntos(e["plan"])
    }

    private static func conjuntos(_ valor: Any?) -> [String: Set<String>] {
        var out: [String: Set<String>] = [:]
        for (dia, ids) in (valor as? [String: Any]) ?? [:] { out[dia] = Set((ids as? [String]) ?? []) }
        return out
    }

    // MARK: marcar

    func hecho(_ id: String, dia: String = Fecha.hoy()) -> Bool {
        if dia == hoy?.hoy, let h = hoy?.habitos.first(where: { $0.id == id }) { return h.hecho }
        return log[dia]?.contains(id) ?? false
    }

    /// Marca o desmarca, primero en pantalla. Devuelve false si el servidor lo rechazó (y lo deja como estaba).
    @discardableResult
    func marca(_ id: String, hecho nuevo: Bool, dia: String = Fecha.hoy()) async -> Bool {
        let antes = hecho(id, dia: dia)
        withAnimation(Tema.Muelle.toque) { aplica(id, nuevo, dia) }
        actualizaIsla()
        do {
            try await API.marcaOEncola(habito: id, hecho: nuevo, dia: dia)
            WidgetCenter.shared.reloadAllTimelines()
            return true
        } catch {
            withAnimation(Tema.Muelle.toque) { aplica(id, antes, dia) }
            self.error = error.localizedDescription
            return false
        }
    }

    private func aplica(_ id: String, _ valor: Bool, _ dia: String) {
        var dias = log[dia] ?? []
        if valor { dias.insert(id) } else { dias.remove(id) }
        log[dia] = dias
        guard var h = hoy, h.hoy == dia, let i = h.habitos.firstIndex(where: { $0.id == id }) else { return }
        if h.habitos[i].hecho != valor {
            h.habitos[i].hecho = valor
            h.habitos[i].racha = max(0, h.habitos[i].racha + (valor ? 1 : -1))
        }
        hoy = h
    }

    /// Una tarea de «Para hoy» hecha (POST /api/tarea/hecha, a la cola si no hay red).
    func tareaHecha(_ tarea: Tarea) async {
        guard let id = tarea.id else { return }
        _ = withAnimation(Tema.Muelle.toque) { tareasHechas.insert(id) }
        do {
            _ = try await API.escribeOEncola("/api/tarea/hecha", json: ["id": id, "hecha": true])
        } catch {
            _ = withAnimation(Tema.Muelle.toque) { tareasHechas.remove(id) }
            self.error = error.localizedDescription
        }
    }

    /// «Día en la isla» (si está activado): los anillos de hoy.
    func actualizaIsla() {
        let hs = habitosDeHoy
        let hechos = hs.filter(\.hecho).count
        let pasos = Double(hoy?.salud?.pasos?.ultimo ?? 0) / 10_000
        let sueno = Double(hoy?.salud?.sueno?.ultimo ?? 0) / 480
        Isla.dia(habitos: hs.isEmpty ? 0 : Double(hechos) / Double(hs.count), pasos: pasos, sueno: sueno,
                 texto: hs.isEmpty ? "Nada planificado" : "\(hechos) de \(hs.count) hábitos")
    }

    // MARK: lo que se pinta

    /// Lo de hoy: lo planificado o ya hecho (como la portada web); el resto va aparte.
    var habitosDeHoy: [Habito] { (hoy?.habitos ?? []).filter { $0.plan || $0.hecho } }
    var otrosHabitos: [Habito] { (hoy?.habitos ?? []).filter { !$0.plan && !$0.hecho } }

    var tareasDeHoy: [Tarea] {
        (hoy?.tareas ?? []).filter { t in t.id.map { !tareasHechas.contains($0) } ?? true }
    }

    /// Lunes a domingo de la semana de `dia`.
    func semana(de dia: String = Fecha.hoy()) -> [String] {
        let cal = Calendar(identifier: .iso8601)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: dia),
              let lunes = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)) else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: lunes) }.map(Fecha.dia)
    }

    func hechosEnSemana(_ id: String, dia: String = Fecha.hoy()) -> Int {
        semana(de: dia).filter { log[$0]?.contains(id) ?? false }.count
    }
}
