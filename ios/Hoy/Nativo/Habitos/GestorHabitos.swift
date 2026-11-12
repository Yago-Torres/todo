import Foundation
import SwiftUI
import WidgetKit

/// Editar los hábitos y planificar la semana, como hace static/index.html: el servidor guarda el estado entero
/// (PUT /api/state), así que se lee la última versión, se cambia lo que toca y se devuelve con su X-Version. Si
/// alguien escribió entre medias (409), se repite sobre lo nuevo. Pide conexión: reescribir el estado entero desde una
/// copia vieja pisaría cambios hechos en otro sitio, por eso no va a la cola de «sin conexión».
@MainActor
enum GestorHabitos {
    /// Cuántos hábitos admite el servidor (clean() corta en 20).
    static let maximo = 20

    /// Colores para elegir al crear un hábito (los de Calma: saturación media, se leen en claro y en oscuro).
    static let colores = ["#A6402F", "#D9822B", "#C9A227", "#7A9A3B", "#3F8F6B", "#2F8F9D", "#3B5C92", "#6B5CA5", "#B24C85", "#6B6B6B"]

    static func idNuevo() -> String {
        String((0..<8).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
    }

    private static var cola: Task<Void, Never>?

    /// Lee el estado, aplica `cambio` y lo guarda. Al terminar, las pantallas nativas ya lo ven. Los cambios van uno
    /// detrás de otro (varios toques seguidos en el planificador no se pisan).
    static func modifica(_ cambio: @escaping (inout [String: Any]) -> Void) async throws {
        let previa = cola
        let tarea = Task { @MainActor () -> Result<Void, Error> in
            await previa?.value
            do { try await aplica(cambio); return .success(()) } catch { return .failure(error) }
        }
        cola = Task { _ = await tarea.value }
        try await tarea.value.get()
    }

    private static func aplica(_ cambio: (inout [String: Any]) -> Void) async throws {
        var ultimo: APIError?
        for _ in 0..<3 {
            let (crudo, version) = try await lee()
            guard var estado = (try? JSONSerialization.jsonObject(with: crudo)) as? [String: Any] else {
                throw APIError(mensaje: "No entiendo lo que devuelve el servidor. Vuelve a probar en un momento.")
            }
            cambio(&estado)
            var p = try API.peticion("/api/state", metodo: "PUT", json: estado)
            if let version { p.setValue(version, forHTTPHeaderField: "X-Version") }
            let (cuerpo, http) = try await manda(p)
            if http.statusCode == 409 {
                ultimo = APIError(mensaje: "Se cambió en otro sitio mientras guardabas. Vuelve a probar.")
                continue
            }
            guard (200..<300).contains(http.statusCode) else {
                throw APIError(mensaje: detalle(cuerpo) ?? "El servidor no ha guardado el cambio (error \(http.statusCode)).")
            }
            Local.guarda(Local.clave("GET", "/api/state"), cuerpo: cuerpo, tipo: "application/json",
                         version: http.value(forHTTPHeaderField: "X-Version"), fecha: Date(), forzar: true)
            DatosNativos.shared.leeEstado(cuerpo)
            WidgetCenter.shared.reloadAllTimelines()
            Task { await DatosNativos.shared.recarga() }   // la lista de Hoy (plan, rachas) sale de /api/hoy
            return
        }
        throw ultimo ?? APIError(mensaje: "No se pudo guardar.")
    }

    private static func lee() async throws -> (Data, String?) {
        let (cuerpo, http) = try await manda(try API.peticion("/api/state"))
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(mensaje: detalle(cuerpo) ?? "El servidor no contesta bien (error \(http.statusCode)).")
        }
        return (cuerpo, http.value(forHTTPHeaderField: "X-Version"))
    }

    private static func manda(_ p: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (d, r) = try await URLSession.shared.data(for: p)
            guard let http = r as? HTTPURLResponse else { throw APIError(mensaje: "Respuesta rara del servidor") }
            return (d, http)
        } catch let e as APIError {
            throw e
        } catch {
            throw APIError(mensaje: "Sin conexión. Editar hábitos necesita red: vuelve a probar cuando la tengas.", sinRed: true)
        }
    }

    private static func detalle(_ d: Data) -> String? {
        ((try? JSONSerialization.jsonObject(with: d)) as? [String: Any])?["detail"] as? String
    }

    // MARK: cambios concretos

    private static func habitos(_ e: [String: Any]) -> [[String: Any]] { (e["habits"] as? [[String: Any]]) ?? [] }

    static func crea(nombre: String, color: String, goal: Int, cada: Int) async throws {
        let n = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        try await modifica { e in
            var hs = habitos(e)
            guard hs.count < maximo else { return }
            hs.append(["id": idNuevo(), "n": String(n.prefix(60)), "c": color, "goal": goal, "cada": cada])
            e["habits"] = hs
        }
    }

    static func edita(_ id: String, nombre: String, color: String, goal: Int, cada: Int) async throws {
        let n = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        try await modifica { e in
            e["habits"] = habitos(e).map { h in
                guard (h["id"] as? String) == id else { return h }
                var h = h
                h["n"] = String(n.prefix(60)); h["c"] = color; h["goal"] = goal; h["cada"] = cada
                return h
            }
        }
    }

    /// Borra el hábito y, con él, lo hecho y lo planificado (clean() tira los ids que ya no existen).
    static func borra(_ id: String) async throws {
        try await modifica { e in e["habits"] = habitos(e).filter { ($0["id"] as? String) != id } }
    }

    /// Deja los hábitos en este orden de ids (los que no estén, al final).
    static func ordena(_ ids: [String]) async throws {
        try await modifica { e in
            let hs = habitos(e)
            let primero = ids.compactMap { id in hs.first { ($0["id"] as? String) == id } }
            let resto = hs.filter { h in !ids.contains((h["id"] as? String) ?? "") }
            e["habits"] = primero + resto
        }
    }

    /// Pone o quita el hábito del plan de ese día (planear() de la web).
    static func planea(_ id: String, dia: String, si: Bool) async throws {
        try await modifica { e in
            var plan = (e["plan"] as? [String: [String]]) ?? [:]
            var l = plan[dia] ?? []
            if si { if !l.contains(id) { l.append(id) } } else { l.removeAll { $0 == id } }
            plan[dia] = l.isEmpty ? nil : l
            e["plan"] = plan
        }
    }
}
