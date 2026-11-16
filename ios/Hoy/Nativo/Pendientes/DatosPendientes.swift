import Foundation
import SwiftUI
import Observation
import UIKit

// Lo que devuelve GET /api/bandeja (el vault: tareas, Leer luego, notas recientes y para revisar), y las acciones sobre
// las tareas. Todo se ve cambiado al momento; si no hay red, el cambio va a la cola de Local (SinRed.swift) y la copia
// que se enseña sin conexión lleva ya el cambio.

struct TareaVault: Codable, Identifiable, Hashable {
    var id: String
    var t: String
    var due: String?
    var hora: String?
    var ruta: String?
    var nota: String?
    var grupo: String?
    var fija: Bool?
    var abrir: String?
    // el board: estado (nueva, activa, bloqueada, hecha), proyectos, historia y de qué historia cuelga
    var estado: String? = nil
    var tags: [String]? = nil
    var historia: Bool? = nil
    var padre: String? = nil
    /// [hechas, total] de las subtareas de una historia.
    var progreso: [Int]? = nil
    var hecha_el: String? = nil

    /// El día, o nil si no tiene (el servidor a veces manda «»).
    var dia: String? { (due?.isEmpty ?? true) ? nil : due }
    var horaTexto: String? { (hora?.isEmpty ?? true) ? nil : hora }
    /// Recién apuntada sin red: todavía no tiene el id del vault (se puede cambiar igual: la cola le pone el bueno).
    var provisional: Bool { id.hasPrefix("tmp:") }
}

struct LecturaVault: Codable, Identifiable, Hashable {
    var ruta: String
    var titulo: String
    var url: String?
    var resumen: String?
    var minutos: Int?
    var tipo: String?
    var guardado: String?
    var review: String?
    var abrir: String?

    var id: String { ruta }
}

struct NotaVault: Codable, Identifiable, Hashable {
    var ruta: String
    var titulo: String
    var tipo: String?
    var created: String?
    var cambio: String?
    var extracto: String?
    var abrir: String?

    var id: String { ruta }
}

struct RevisarVault: Codable, Identifiable, Hashable {
    var ruta: String
    var titulo: String
    var review: String?
    var tipo: String?
    var abrir: String?

    var id: String { ruta }
}

struct Bandeja: Codable {
    var tareas: [TareaVault]
    /// Las hechas de este ciclo de 3 semanas (la columna «Hecha» del board).
    var hechas: [TareaVault]
    var ciclo: CicloBoard?
    var leer: [LecturaVault]
    var notas: [NotaVault]
    var revisar: [RevisarVault]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Claves.self)
        tareas = (try? c.decode([TareaVault].self, forKey: .tareas)) ?? []
        hechas = (try? c.decode([TareaVault].self, forKey: .hechas)) ?? []
        ciclo = try? c.decode(CicloBoard.self, forKey: .ciclo)
        leer = (try? c.decode([LecturaVault].self, forKey: .leer)) ?? []
        notas = (try? c.decode([NotaVault].self, forKey: .notas)) ?? []
        revisar = (try? c.decode([RevisarVault].self, forKey: .revisar)) ?? []
    }

    private enum Claves: String, CodingKey { case tareas, hechas, ciclo, leer, notas, revisar }
}

@MainActor @Observable
final class DatosPendientes {
    static let shared = DatosPendientes()

    private(set) var bandeja: Bandeja?
    private(set) var copia: Date?
    private(set) var cargando = false
    private(set) var error: String?
    /// Tareas con el círculo marcado que aún se ven (tachadas), un momento antes de irse.
    private(set) var marcadas: Set<String> = []
    var aviso: AvisoTom?

    private var ultimaCarga: Date?
    private static let ruta = "/api/bandeja"

    init() {
        if let r = Local.lee(Local.clave("GET", Self.ruta)),
           let b = try? JSONDecoder().decode(Bandeja.self, from: r.cuerpo) {
            bandeja = b
        }
    }

    func carga(margen: TimeInterval = 20) async {
        if let ultimaCarga, Date().timeIntervalSince(ultimaCarga) < margen { return }
        guard !cargando else { return }
        cargando = true
        defer { cargando = false }
        do {
            let (crudo, fecha) = try await API.leeOCopia(Self.ruta)
            let nueva = try JSONDecoder().decode(Bandeja.self, from: crudo)
            withAnimation(Tema.Muelle.pantalla) {
                bandeja = nueva
                marcadas = []
            }
            copia = fecha
            error = nil
            ultimaCarga = Date()
        } catch let e as DecodingError {
            error = "No entiendo lo que devuelve /api/bandeja (\(e.localizedDescription))"
        } catch {
            self.error = error.localizedDescription
        }
    }

    func recarga() async {
        ultimaCarga = nil
        await carga()
    }

    // MARK: avisos

    func avisa(_ texto: String, error: Bool = false, deshacer: (@MainActor () async -> Void)? = nil) {
        aviso = AvisoTom(texto: texto, error: error, deshacer: deshacer)
        AccessibilityNotification.Announcement(texto).post()
        if error { Haptica.shared.toca(.error) }
    }

    func quitaAviso() { aviso = nil }

    private static func objeto(_ datos: Data?) -> [String: Any]? {
        datos.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    /// Quita de la cola lo que iba sobre una tarea apuntada sin red que aún no ha salido (crearla y sus cambios).
    private func olvidaProvisional(_ id: String) -> Bool {
        let suyos = Local.cambios().filter { c in
            guard c.estado == .pendiente else { return false }
            if c.cabeceras["x-tom-tmp"] == id { return true }
            let cuerpo = c.cuerpo.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            return (cuerpo?["id"] as? String) == id
        }
        guard suyos.contains(where: { $0.cabeceras["x-tom-tmp"] == id }) else { return false }
        for c in suyos { Local.descarta(c.id) }
        Operaciones.recalcula(Self.ruta)
        return true
    }

    // MARK: apuntar

    /// `tags`, `historia` y `padre` (la historia de la que cuelga, si es una subtarea), para el board.
    func apunta(_ texto: String, due: String?, hora: String?, tags: [String] = [], historia: Bool = false,
                padre: String? = nil) async -> Bool {
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty else { return false }
        let provisional = TareaVault(id: "tmp:\(UUID().uuidString)", t: limpio, due: due, hora: due == nil ? nil : hora,
                                     ruta: nil, nota: nil, grupo: "Pendientes", fija: false, abrir: nil,
                                     estado: "nueva", tags: tags, historia: historia, padre: padre)
        withAnimation(Tema.Muelle.pantalla) { bandeja?.tareas.append(provisional) }
        var json: [String: Any] = ["t": limpio]
        if let due { json["due"] = due }
        if let hora, due != nil { json["hora"] = hora }
        if !tags.isEmpty { json["tags"] = tags }
        if historia { json["historia"] = true }
        if let padre { json["padre"] = padre }
        do {
            let r = try await API.escribeOEncola("/api/tarea", json: json, tmp: provisional.id)
            if let r, let real = try? JSONDecoder().decode(TareaVault.self, from: r) {
                withAnimation(Tema.Muelle.pantalla) {
                    if let i = bandeja?.tareas.firstIndex(where: { $0.id == provisional.id }) { bandeja?.tareas[i] = real }
                }
                avisa("Apuntado\(due.map { " para \(FechasES.cuando($0))" } ?? ""): \(limpio)")
            } else if r != nil {
                await recarga()
                avisa("Apuntado: \(limpio)")
            } else {
                avisa("Apuntado. Se enviará en cuanto haya conexión")
            }
            return true
        } catch {
            withAnimation(Tema.Muelle.pantalla) { bandeja?.tareas.removeAll { $0.id == provisional.id } }
            avisa("No se ha apuntado: \(error.localizedDescription)", error: true)
            return false
        }
    }

    // MARK: cambiar

    /// `tags` nil = los proyectos se quedan como estaban.
    func edita(_ t: TareaVault, texto: String, due: String?, hora: String?, tags: [String]? = nil) async {
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty else { return }
        let nuevaHora = due == nil ? nil : hora
        withAnimation(Tema.Muelle.pantalla) {
            if let i = bandeja?.tareas.firstIndex(where: { $0.id == t.id }) {
                bandeja?.tareas[i].t = limpio
                bandeja?.tareas[i].due = due
                bandeja?.tareas[i].hora = nuevaHora
            }
        }
        var json: [String: Any] = ["id": t.id, "t": limpio, "due": due ?? "", "hora": nuevaHora ?? ""]
        if let tags { json["tags"] = tags }
        do {
            let r = try await API.escribeOEncola("/api/tarea/edita", json: json)
            if let r, let real = try? JSONDecoder().decode(TareaVault.self, from: r) {
                coloca(real, en: t.id)
                avisa("Cambiada: \(real.t)")
            } else if r == nil {
                avisa("Cambiada. Se enviará en cuanto haya conexión")
            }
        } catch {
            avisa("No se ha cambiado: \(error.localizedDescription)", error: true)
            await recarga()
        }
    }

    /// Posponer: a `dia` (o sin fecha), con la misma hora.
    func pospon(_ t: TareaVault, a dia: String?) async {
        await edita(t, texto: t.t, due: dia, hora: t.horaTexto)
    }

    /// El día siguiente a lo que tiene (o a hoy, si ya venció o no tiene).
    func manana(de t: TareaVault) -> String {
        FechasES.masDias(max(t.dia ?? Fecha.hoy(), Fecha.hoy()), 1)
    }

    // MARK: el board

    var todasBoard: [TareaVault] { tareas + (bandeja?.hechas ?? []) }

    func columna(_ e: EstadoBoard, proyecto: String) -> [TareaVault] {
        todasBoard.filter { $0.estadoBoard == e && (proyecto.isEmpty || $0.etiquetas.contains(proyecto)) }
    }

    /// Los proyectos con algo abierto, de más a menos tareas.
    var proyectos: [String] {
        var n: [String: Int] = [:]
        for t in tareas { for x in t.etiquetas { n[x, default: 0] += 1 } }
        return n.keys.sorted { (n[$0] ?? 0, $1) > (n[$1] ?? 0, $0) }
    }

    /// Pone `t` en su lista (abiertas o hechas, según su estado) en lugar de la que tenía el id `id`.
    private func coloca(_ t: TareaVault, en id: String) {
        guard var b = bandeja else { return }
        let i = b.tareas.firstIndex { $0.id == id }
        b.tareas.removeAll { $0.id == id }
        b.hechas.removeAll { $0.id == id }
        if t.estadoBoard == .hecha {
            b.hechas.insert(t, at: 0)
        } else if let i, i <= b.tareas.count {
            b.tareas.insert(t, at: i)
        } else {
            b.tareas.append(t)
        }
        bandeja = b
    }

    /// De una columna a otra. Se ve al momento; sin red va a la cola.
    func mueve(_ t: TareaVault, a e: EstadoBoard) async {
        guard t.estadoBoard != e else { return }
        if t.fija == true && (e == .activa || e == .bloqueada) {
            avisa("Lo del curro solo se puede tachar", error: true)
            return
        }
        Haptica.shared.toca(.marcar)
        let antes = t.estadoBoard
        var movida = t
        movida.estado = e.rawValue
        if e == .hecha { movida.hecha_el = Fecha.hoy() }
        withAnimation(Tema.Muelle.pantalla) { coloca(movida, en: t.id) }
        do {
            let r = try await API.escribeOEncola("/api/tarea/estado", json: ["id": t.id, "estado": e.rawValue])
            if let r, let real = try? JSONDecoder().decode(TareaVault.self, from: r) {
                withAnimation(Tema.Muelle.pantalla) { coloca(real, en: t.id) }
                avisa("\(e.nombre): \(real.t)") { [weak self] in await self?.mueve(real, a: antes) }
            } else {
                avisa("\(e.nombre). Se enviará en cuanto haya conexión")
            }
        } catch {
            avisa("No se ha movido: \(error.localizedDescription)", error: true)
            await recarga()
        }
    }

    // MARK: hecha

    func hecha(_ t: TareaVault) async {
        guard !marcadas.contains(t.id) else { return }
        Haptica.shared.toca(.marcar)
        withAnimation(Tema.Muelle.toque) { _ = marcadas.insert(t.id) }
        let envio = Task { try await API.escribeOEncola("/api/tarea/hecha", json: ["id": t.id, "hecha": true]) }
        // el tachado se ve un momento antes de que la fila se vaya
        try? await Task.sleep(nanoseconds: 450_000_000)
        withAnimation(Tema.Muelle.pantalla) { bandeja?.tareas.removeAll { $0.id == t.id } }
        do {
            let r = try await envio.value
            if let nuevo = Self.objeto(r)?["id"] as? String {
                avisa("Hecha: \(t.t)") { [weak self] in await self?.deshazHecha(t, id: nuevo) }
            } else {
                avisa("Hecha. Se enviará en cuanto haya conexión")
            }
        } catch {
            withAnimation(Tema.Muelle.pantalla) {
                marcadas.remove(t.id)
                if bandeja?.tareas.contains(where: { $0.id == t.id }) == false { bandeja?.tareas.append(t) }
            }
            avisa("No se ha podido: \(error.localizedDescription)", error: true)
        }
    }

    private func deshazHecha(_ t: TareaVault, id: String) async {
        do {
            _ = try await API.escribeOEncola("/api/tarea/hecha", json: ["id": id, "hecha": false])
            await recarga()
        } catch {
            avisa("No se ha podido deshacer: \(error.localizedDescription)", error: true)
        }
    }

    // MARK: borrar

    func borra(_ t: TareaVault) async {
        // apuntada sin red y aún en la cola: basta con no mandarla
        if t.provisional, olvidaProvisional(t.id) {
            withAnimation(Tema.Muelle.pantalla) { bandeja?.tareas.removeAll { $0.id == t.id } }
            avisa("Borrada: \(t.t)")
            return
        }
        Haptica.shared.toca(.desmarcar)
        withAnimation(Tema.Muelle.pantalla) { bandeja?.tareas.removeAll { $0.id == t.id } }
        do {
            let r = try await API.escribeOEncola("/api/tarea/borra", json: ["id": t.id])
            if let borrada = Self.objeto(r) {
                avisa("Borrada: \(t.t)") { [weak self] in await self?.restaura(borrada) }
            } else {
                avisa("Borrada. Se enviará en cuanto haya conexión")
            }
        } catch {
            avisa("No se ha borrado: \(error.localizedDescription)", error: true)
            await recarga()
        }
    }

    private func restaura(_ borrada: [String: Any]) async {
        do {
            _ = try await API.escribeOEncola("/api/tarea/restaura", json: borrada)
            await recarga()
        } catch {
            avisa("No se ha podido recuperar: \(error.localizedDescription)", error: true)
        }
    }

    // MARK: Leer luego

    func leido(_ l: LecturaVault) async {
        Haptica.shared.toca(.marcar)
        withAnimation(Tema.Muelle.pantalla) { bandeja?.leer.removeAll { $0.ruta == l.ruta } }
        do {
            let r = try await API.escribeOEncola("/api/leido", json: ["ruta": l.ruta])
            if r == nil {
                avisa("Leído. Se enviará en cuanto haya conexión")
            } else {
                avisa("Leído: \(l.titulo)")
            }
        } catch {
            avisa("No se ha podido: \(error.localizedDescription)", error: true)
            await recarga()
        }
    }

    // MARK: lo que se pinta

    var tareas: [TareaVault] { bandeja?.tareas ?? [] }

    /// Como la web: lo de Proyectos y Curro va plegado, salvo si tiene fecha.
    static func suelta(_ t: TareaVault) -> Bool { !["Proyectos", "Curro"].contains(t.grupo ?? "") }

    struct Grupo: Identifiable {
        let id: String
        let titulo: String
        let vencidas: Bool
        let tareas: [TareaVault]
    }

    func grupos(buscando q: String) -> [Grupo] {
        let hoy = Fecha.hoy()
        let semana = FechasES.masDias(hoy, 7)
        let T = tareas.filter { $0.t.contieneBusqueda(q) || ($0.nota ?? "").contieneBusqueda(q) }
        let todos: [Grupo] = [
            Grupo(id: "vencidas", titulo: "Vencidas", vencidas: true, tareas: T.filter { ($0.dia ?? "9999") < hoy }),
            Grupo(id: "hoy", titulo: "Hoy", vencidas: false, tareas: T.filter { $0.dia == hoy }),
            Grupo(id: "semana", titulo: "Esta semana", vencidas: false, tareas: T.filter { ($0.dia ?? "") > hoy && ($0.dia ?? "") <= semana }),
            Grupo(id: "luego", titulo: "Más adelante", vencidas: false, tareas: T.filter { ($0.dia ?? "") > semana }),
            Grupo(id: "sin", titulo: "Sin fecha", vencidas: false, tareas: T.filter { $0.dia == nil && Self.suelta($0) }),
        ]
        return todos.filter { !$0.tareas.isEmpty }
    }

    struct NotaConTareas: Identifiable {
        let nota: String
        let abrir: String?
        let tareas: [TareaVault]
        var id: String { nota }
    }

    struct GrupoProyecto: Identifiable {
        let grupo: String
        let notas: [NotaConTareas]
        var id: String { grupo }
        var total: Int { notas.reduce(0) { $0 + $1.tareas.count } }
    }

    /// Las de proyectos y curro sin fecha, agrupadas por nota.
    func deProyectos(buscando q: String) -> [GrupoProyecto] {
        var out: [GrupoProyecto] = []
        for g in ["Proyectos", "Curro"] {
            let ts = tareas.filter { $0.grupo == g && $0.dia == nil && ($0.t.contieneBusqueda(q) || ($0.nota ?? "").contieneBusqueda(q)) }
            if ts.isEmpty { continue }
            let porNota = Dictionary(grouping: ts) { $0.nota ?? "" }
            let notas = porNota.keys.sorted().map { NotaConTareas(nota: $0, abrir: porNota[$0]?.first?.abrir, tareas: porNota[$0] ?? []) }
            out.append(GrupoProyecto(grupo: g, notas: notas))
        }
        return out
    }

    /// Cuántas se ven en la pestaña (las de la web: con fecha o sueltas).
    var cuentaTareas: Int { tareas.filter { $0.dia != nil || Self.suelta($0) }.count }
}
