import Foundation
import SwiftUI
import WidgetKit

/// Editar los hábitos y planificar la semana. Cada cambio es una operación con intención (Compartido/Operaciones.swift):
/// se pinta al momento en la copia local, va a la cola de Local y Sincro la aplica sobre el estado FRESCO del servidor
/// (GET → operación → PUT con X-Version; en un 409, otra vuelta). Funciona igual con y sin red: sin red se queda en la
/// cola y sale sola al volver, sin pisar lo que el bot o la web hayan cambiado mientras tanto.
@MainActor
enum GestorHabitos {
    /// Cuántos hábitos admite el servidor (clean() corta en 20).
    static let maximo = Operaciones.maximoHabitos

    /// Colores para elegir al crear un hábito (los de Calma: saturación media, se leen en claro y en oscuro).
    static let colores = ["#A6402F", "#D9822B", "#C9A227", "#7A9A3B", "#3F8F6B", "#2F8F9D", "#3B5C92", "#6B5CA5", "#B24C85", "#6B6B6B"]

    static func idNuevo() -> String {
        String((0..<8).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
    }

    /// Apunta la operación, la pinta y la manda. Con red espera a que llegue y, si el servidor la rechaza, lanza su
    /// motivo (y se queda en «cambios por enviar» para descartarla). Sin red vuelve enseguida: ya está en la cola.
    static func manda(_ op: [String: Any]) async throws {
        guard let id = Operaciones.encola(Operaciones.state, op) else {
            throw APIError(mensaje: "No he podido guardar el cambio en el iPhone. Desbloquéalo y vuelve a probar.")
        }
        DatosNativos.shared.refrescaDesdeLocal()
        await Sincro.vacia()
        DatosNativos.shared.refrescaDesdeLocal()
        WidgetCenter.shared.reloadAllTimelines()
        if let c = Local.cambio(id), c.estado != .pendiente {
            throw APIError(mensaje: c.error ?? "El servidor no ha aceptado el cambio.")
        }
    }

    private static func nombre(_ id: String) -> String {
        DatosNativos.shared.habitos.first { $0.id == id }?.n ?? "un hábito"
    }

    private static var cola: Task<Void, Never>?

    /// Para lo que no sea una operación de las de abajo: lee el estado, aplica `cambio` y lo guarda (con red). Sin red,
    /// el cambio se hace sobre la copia local y el estado entero va a la cola con la copia de partida, y Sincro lo junta a
    /// tres bandas con lo del servidor (Fusion). Mejor usar `edita(_:cambios:)` y compañía.
    static func modifica(_ cambio: @escaping (inout [String: Any]) -> Void) async throws {
        let previa = cola
        let tarea = Task { @MainActor () -> Result<Void, Error> in
            await previa?.value
            do { try await aplica(cambio); return .success(()) } catch { return .failure(error) }
        }
        cola = Task { _ = await tarea.value }
        do {
            try await tarea.value.get()
        } catch let e as APIError where e.sinRed {
            let clave = Local.clave("GET", Operaciones.state)
            guard let r = Local.lee(clave), var estado = (try? JSONSerialization.jsonObject(with: r.cuerpo)) as? [String: Any] else {
                throw APIError(mensaje: "Sin conexión, y aún no hay copia de tus hábitos en el iPhone. Ábrelos una vez con red.")
            }
            cambio(&estado)
            guard let datos = try? JSONSerialization.data(withJSONObject: estado),
                  Local.encola(metodo: "PUT", ruta: Operaciones.state, cuerpo: datos,
                               cabeceras: ["content-type": "application/json", "x-version": r.version ?? ""], base: r.cuerpo) else {
                throw e
            }
            Local.guarda(clave, cuerpo: datos, tipo: r.tipo, version: r.version, fecha: Date(), local: true, forzar: true)
            DatosNativos.shared.leeEstado(datos)
        }
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
            let vista = Operaciones.llega(Operaciones.state, cuerpo, version: http.value(forHTTPHeaderField: "X-Version"))
            DatosNativos.shared.leeEstado(vista)
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
            throw APIError(mensaje: "Sin conexión con el servidor: \(error.localizedDescription)", sinRed: true)
        }
    }

    private static func detalle(_ d: Data) -> String? {
        ((try? JSONSerialization.jsonObject(with: d)) as? [String: Any])?["detail"] as? String
    }

    // MARK: cambios concretos (operaciones de la cola)

    /// Crea un hábito con estos campos (cualquiera: n, c, goal, cada y los que añada el servidor). El id lo pone la app.
    static func crea(campos: [String: Any]) async throws {
        guard DatosNativos.shared.habitos.count < maximo else {
            throw APIError(mensaje: "Ya tienes \(maximo) hábitos, el máximo. Borra uno para crear otro.")
        }
        var c = campos
        let id = (c["id"] as? String) ?? idNuevo()
        c["id"] = id
        try await manda(["op": "habito.crea", "id": id, "campos": c,
                         "resumen": "Crear el hábito «\((c["n"] as? String) ?? "")»"])
    }

    /// Cambia estos campos de un hábito (cualquiera; NSNull lo quita). Lo demás del hábito queda como esté en el servidor.
    static func edita(_ id: String, cambios: [String: Any]) async throws {
        try await manda(["op": "habito.edita", "id": id, "cambios": cambios,
                         "resumen": "Cambiar el hábito «\((cambios["n"] as? String) ?? nombre(id))»"])
    }

    static func crea(nombre: String, color: String, goal: Int, cada: Int) async throws {
        let n = String(nombre.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        try await crea(campos: ["n": n, "c": color, "goal": goal, "cada": cada])
    }

    static func edita(_ id: String, nombre: String, color: String, goal: Int, cada: Int) async throws {
        let n = String(nombre.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        try await edita(id, cambios: ["n": n, "c": color, "goal": goal, "cada": cada])
    }

    /// Borra el hábito y, con él, lo hecho y lo planificado (clean() tira los ids que ya no existen).
    static func borra(_ id: String) async throws {
        try await manda(["op": "habito.borra", "id": id, "resumen": "Borrar el hábito «\(nombre(id))»"])
    }

    /// Deja los hábitos en este orden de ids (los que no estén, al final).
    static func ordena(_ ids: [String]) async throws {
        try await manda(["op": "habito.ordena", "ids": ids, "resumen": "Ordenar los hábitos"])
    }

    /// Pone o quita el hábito del plan de ese día (planear() de la web).
    static func planea(_ id: String, dia: String, si: Bool) async throws {
        try await manda(["op": "plan.pon", "id": id, "dia": dia, "si": si,
                         "resumen": "\(si ? "Planificar" : "Quitar del plan") «\(nombre(id))» (\(dia))"])
    }
}
