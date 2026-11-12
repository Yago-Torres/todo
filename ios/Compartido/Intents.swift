import AppIntents
import WidgetKit

// Compila en la app y en el widget: solo Compartido, AppIntents y WidgetKit (nada de UIKit).

// MARK: hábito para Siri

struct HabitoEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Hábito")
    static var defaultQuery = HabitoConsulta()

    var id: String
    var nombre: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(nombre)") }
}

struct HabitoConsulta: EntityStringQuery {
    /// Los de hoy del servidor; sin red, la caché que guarda la app.
    private func todos() async -> [HabitoEntity] {
        let habitos: [Habito]
        if let hoy = try? await API.hoy() {
            habitos = hoy.habitos
        } else {
            habitos = Almacen.leeHoy()?.habitos ?? []
        }
        return habitos.map { HabitoEntity(id: $0.id, nombre: $0.n) }
    }

    func entities(for identifiers: [String]) async throws -> [HabitoEntity] {
        await todos().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [HabitoEntity] {
        let q = string.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return await todos().filter {
            $0.nombre.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).contains(q)
        }
    }

    func suggestedEntities() async throws -> [HabitoEntity] { await todos() }
}

// MARK: marcar hábito

/// Para el widget interactivo: el hábito va por id y nombre, sin pedir nada.
struct MarcaHabitoIntent: AppIntent {
    static var title: LocalizedStringResource = "Marcar hábito"
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Hábito (id)") var habito: String
    @Parameter(title: "Nombre") var nombre: String
    @Parameter(title: "Hecho", default: true) var hecho: Bool

    init() {}

    init(habito: String, nombre: String, hecho: Bool = true) {
        self.habito = habito
        self.nombre = nombre
        self.hecho = hecho
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        Optimista.marcaHabito(id: habito, hecho: hecho)   // el widget lo enseña ya, también sin red
        let encolado = try await API.marcaOEncola(habito: habito, hecho: hecho)
        WidgetCenter.shared.reloadAllTimelines()
        let texto = "\(nombre) \(hecho ? "hecho" : "sin hacer")" + (encolado ? ". \(API.avisoEncolado)" : "")
        return .result(dialog: "\(texto)")
    }
}

/// Para Siri y Atajos: elige el hábito por su nombre.
struct MarcaHabitoSiriIntent: AppIntent {
    static var title: LocalizedStringResource = "Marcar un hábito"
    static var description = IntentDescription("Marca un hábito de hoy como hecho.")

    @Parameter(title: "Hábito", requestValueDialog: "¿Qué hábito?") var habito: HabitoEntity

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let encolado = try await API.marcaOEncola(habito: habito.id, hecho: true)
        WidgetCenter.shared.reloadAllTimelines()
        let texto = "\(habito.nombre) hecho" + (encolado ? ". \(API.avisoEncolado)" : "")
        return .result(dialog: "\(texto)")
    }
}

// MARK: apuntar tarea

struct ApuntaTareaIntent: AppIntent {
    static var title: LocalizedStringResource = "Apuntar una tarea"
    static var description = IntentDescription("Añade una tarea a tus pendientes.")

    @Parameter(title: "Tarea", requestValueDialog: "¿Qué tarea?") var texto: String

    init() {}

    init(texto: String) { self.texto = texto }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty else { throw APIError(mensaje: "La tarea está vacía") }
        let encolado = try await API.tareaOEncola(limpio)
        WidgetCenter.shared.reloadAllTimelines()
        let texto = encolado ? "Tarea: \(API.avisoEncolado.lowercased())" : "Tarea apuntada"
        return .result(dialog: "\(texto)")
    }
}

// MARK: abrir una sección

enum Seccion: String, AppEnum {
    case entreno, pendientes, habitos, salud

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Sección")
    static var caseDisplayRepresentations: [Seccion: DisplayRepresentation] = [
        .entreno: "Entreno",
        .pendientes: "Pendientes",
        .habitos: "Hábitos",
        .salud: "Salud",
    ]

    var ruta: String { "/\(rawValue).html" }
}

struct AbreSeccionIntent: AppIntent {
    static var title: LocalizedStringResource = "Abrir una sección"
    static var openAppWhenRun = true

    @Parameter(title: "Sección", default: .entreno) var seccion: Seccion

    init() {}

    init(seccion: Seccion) { self.seccion = seccion }

    @MainActor
    func perform() async throws -> some IntentResult {
        Navegador.shared.abre(seccion.ruta)
        return .result()
    }
}
