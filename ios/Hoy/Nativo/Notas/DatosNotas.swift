import Foundation
import SwiftUI
import Observation
import UIKit

// Las notas rápidas (Notas rápidas.md del vault, GET /api/notas): ideas que no son tareas hasta que tú lo dices.
// Apuntar va por la cola si no hay red. Borrar y «→ Pendiente» también, pero solo se pueden deshacer con red: el
// deshacer necesita lo que contesta el servidor (dónde estaba la línea, el id de la tarea nueva).

struct NotaRapida: Codable, Identifiable, Hashable {
    var id: String
    var t: String
    /// «2026-11-17 10:32», o «» si se escribió a mano en Obsidian.
    var cuando: String

    /// Apuntada sin red: aún no tiene id del vault, así que no se puede borrar ni pasar a tarea hasta que salga.
    var provisional: Bool { id.hasPrefix("tmp:") }
}

private struct ListaNotas: Codable {
    var notas: [NotaRapida]
}

@MainActor @Observable
final class DatosNotas {
    static let shared = DatosNotas()

    private(set) var notas: [NotaRapida] = []
    private(set) var copia: Date?
    private(set) var cargando = false
    private(set) var error: String?
    var aviso: AvisoTom?

    private static let ruta = "/api/notas"

    init() {
        if let r = Local.lee(Local.clave("GET", Self.ruta)),
           let l = try? JSONDecoder().decode(ListaNotas.self, from: r.cuerpo) {
            notas = l.notas
        }
    }

    func carga() async {
        guard !cargando else { return }
        cargando = true
        defer { cargando = false }
        do {
            let (crudo, fecha) = try await API.leeOCopia(Self.ruta)
            let l = try JSONDecoder().decode(ListaNotas.self, from: crudo)
            // sin red, las apuntadas que aún esperan en la cola siguen arriba hasta que salgan
            let esperando = fecha == nil ? [] : notas.filter(\.provisional)
            withAnimation(Tema.Muelle.pantalla) { notas = esperando + l.notas }
            copia = fecha
            error = nil
        } catch let e as DecodingError {
            error = "No entiendo lo que devuelve /api/notas (\(e.localizedDescription))"
        } catch {
            self.error = error.localizedDescription
        }
    }

    func avisa(_ texto: String, error: Bool = false, deshacer: (@MainActor () async -> Void)? = nil) {
        aviso = AvisoTom(texto: texto, error: error, deshacer: deshacer)
        AccessibilityNotification.Announcement(texto).post()
        if error { Haptica.shared.toca(.error) }
    }

    func quitaAviso() { aviso = nil }

    private static func objeto(_ datos: Data?) -> [String: Any]? {
        datos.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    private static func ahora() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: Date())
    }

    // MARK: apuntar

    /// `encolada`: sin red, se ha quedado en la cola. `error`: lo que hay que enseñar si no se ha apuntado.
    @discardableResult
    func apunta(_ texto: String) async -> (ok: Bool, encolada: Bool, error: String?) {
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty else { return (false, false, "La nota está vacía") }
        do {
            let r = try await API.escribeOEncola("/api/nota", json: ["t": limpio])
            guard let r else {
                let provisional = NotaRapida(id: "tmp:\(UUID().uuidString)", t: limpio, cuando: Self.ahora())
                withAnimation(Tema.Muelle.pantalla) { notas.insert(provisional, at: 0) }
                return (true, true, nil)
            }
            if let nueva = try? JSONDecoder().decode(NotaRapida.self, from: r) {
                withAnimation(Tema.Muelle.pantalla) { notas.insert(nueva, at: 0) }
            } else {
                await carga()
            }
            return (true, false, nil)
        } catch {
            return (false, false, error.localizedDescription)
        }
    }

    // MARK: borrar

    func borra(_ n: NotaRapida) async {
        guard !n.provisional else { return }
        let antes = notas
        withAnimation(Tema.Muelle.pantalla) { notas.removeAll { $0.id == n.id } }
        do {
            let r = try await API.escribeOEncola("/api/nota/borra", json: ["id": n.id])
            guard let borrada = Self.objeto(r) else {
                avisa("Borrada. Se enviará en cuanto haya conexión")
                return
            }
            avisa("Nota borrada", deshacer: { [weak self] in await self?.restaura(borrada) })
        } catch {
            withAnimation(Tema.Muelle.pantalla) { notas = antes }
            avisa("No se ha borrado: \(error.localizedDescription)", error: true)
        }
    }

    private func restaura(_ borrada: [String: Any]) async {
        do {
            _ = try await API.datos("/api/nota/restaura", metodo: "POST", json: borrada)
            await carga()
        } catch {
            avisa("No se ha podido deshacer: \(error.localizedDescription)", error: true)
        }
    }

    // MARK: a pendiente

    /// La nota se va de aquí y aparece en Pendientes como tarea sin fecha.
    func aTarea(_ n: NotaRapida) async {
        guard !n.provisional else { return }
        let antes = notas
        withAnimation(Tema.Muelle.pantalla) { notas.removeAll { $0.id == n.id } }
        do {
            let r = try await API.escribeOEncola("/api/nota/tarea", json: ["id": n.id])
            guard let o = Self.objeto(r), let tarea = o["tarea"] as? [String: Any], let id = tarea["id"] as? String,
                  let nota = o["nota"] as? [String: Any] else {
                avisa("Pasará a Pendientes en cuanto haya conexión")
                return
            }
            await DatosPendientes.shared.recarga()
            avisa("Ya es una tarea de Pendientes", deshacer: { [weak self] in
                do {
                    _ = try await API.datos("/api/tarea/borra", metodo: "POST", json: ["id": id])
                    _ = try await API.datos("/api/nota/restaura", metodo: "POST", json: nota)
                    await DatosPendientes.shared.recarga()
                    await self?.carga()
                } catch {
                    self?.avisa("No se ha podido deshacer: \(error.localizedDescription)", error: true)
                }
            })
        } catch {
            withAnimation(Tema.Muelle.pantalla) { notas = antes }
            avisa("No se ha podido: \(error.localizedDescription)", error: true)
        }
    }
}
