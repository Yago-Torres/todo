import AppIntents
import WidgetKit

// Lo que hacen los botones de los widgets y de los avisos con botones, sin abrir la app. Compila en la app y en el
// widget (como Intents.swift): solo Compartido, AppIntents y WidgetKit. Todo se manda con la cola de SinRed.swift:
// sin red se apunta y sale al volver la conexión.

// MARK: tareas

extension API {
    /// POST /api/tarea/hecha. true = se quedó en la cola.
    @discardableResult
    static func tareaHechaOEncola(id: String) async throws -> Bool {
        try await escribeOEncola("/api/tarea/hecha", json: ["id": id, "hecha": true]) == nil
    }

    /// Cambia el día y la hora de una tarea (POST /api/tarea/edita; el texto se manda tal cual para no tocarlo).
    @discardableResult
    static func mueveTareaOEncola(id: String, texto: String, due: String, hora: String?) async throws -> Bool {
        var json: [String: Any] = ["id": id, "t": texto, "due": due]
        if let hora, !hora.isEmpty { json["hora"] = hora }
        return try await escribeOEncola("/api/tarea/edita", json: json) == nil
    }

    /// Posponer una hora: misma fecha con la hora una más tarde; si pasa de medianoche, cae en el día siguiente.
    @discardableResult
    static func pospone1hOEncola(id: String, texto: String, ahora: Date = Date()) async throws -> Bool {
        let nueva = ahora.addingTimeInterval(3600)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "HH:mm"
        return try await mueveTareaOEncola(id: id, texto: texto, due: Fecha.dia(nueva), hora: f.string(from: nueva))
    }

    /// Dejarla para mañana, con su hora si tenía.
    @discardableResult
    static func tareaAMananaOEncola(id: String, texto: String, hora: String?) async throws -> Bool {
        let manana = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date().addingTimeInterval(86_400)
        return try await mueveTareaOEncola(id: id, texto: texto, due: Fecha.dia(manana), hora: hora)
    }

    /// POST /api/mueve con cola: el entreno sin hacer de `de` pasa a `a`. true = se quedó en la cola.
    @discardableResult
    static func mueveEntrenoOEncola(a: String, de: String) async throws -> Bool {
        try await escribeOEncola("/api/mueve", json: ["a": a, "de": de]) == nil
    }
}

// MARK: lo que se ve ya en el widget (la copia de hoy.json)

/// Cambia la copia que lee el widget antes de que conteste el servidor, y la que usa si no hay red.
enum Optimista {
    static func quitaTarea(id: String) {
        guard var h = Almacen.leeHoy(), let tareas = h.tareas else { return }
        h.tareas = tareas.filter { $0.id != id }
        guarda(h)
    }

    static func marcaHabito(id: String, hecho: Bool) {
        guard var h = Almacen.leeHoy(), let i = h.habitos.firstIndex(where: { $0.id == id }) else { return }
        if h.habitos[i].hecho != hecho {
            h.habitos[i].hecho = hecho
            h.habitos[i].racha = max(0, h.habitos[i].racha + (hecho ? 1 : -1))
        }
        guarda(h)
    }

    private static func guarda(_ h: Hoy) {
        if let d = try? JSONEncoder().encode(h) { Almacen.guardaHoy(d) }
    }
}

// MARK: completar tarea (botón del widget)

struct CompletaTareaIntent: AppIntent {
    static var title: LocalizedStringResource = "Completar tarea"
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Tarea (id)") var tarea: String
    @Parameter(title: "Texto") var texto: String

    init() {}

    init(tarea: String, texto: String) {
        self.tarea = tarea
        self.texto = texto
    }

    func perform() async throws -> some IntentResult {
        Optimista.quitaTarea(id: tarea)   // el widget la quita ya, también sin red
        do {
            try await API.tareaHechaOEncola(id: tarea)
        } catch {
            WidgetCenter.shared.reloadAllTimelines()   // si el servidor la rechaza, el widget vuelve a lo que hay allí
            throw error
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
