import AppIntents
import WidgetKit

// Compila en la app y en el widget, como Intents.swift: solo Compartido, AppIntents y WidgetKit.

// MARK: categoría de gasto para Siri

struct CategoriaGastoEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Categoría de gasto")
    static var defaultQuery = CategoriaGastoConsulta()

    var id: String
    var nombre: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(nombre)") }
}

struct CategoriaGastoConsulta: EntityStringQuery {
    /// Las del servidor; sin red, las últimas que se bajaron.
    private func todas() async -> [CategoriaGastoEntity] {
        let cats: [CategoriaGasto]
        if let bajadas = try? await API.categoriasGasto(), !bajadas.isEmpty {
            cats = bajadas
        } else {
            cats = CategoriaGasto.guardadas
        }
        return cats.map { CategoriaGastoEntity(id: $0.id, nombre: $0.n) }
    }

    func entities(for identifiers: [String]) async throws -> [CategoriaGastoEntity] {
        let lista = await todas()
        // sin red ni caché, el id vale igual: gastos acepta el id o el nombre
        return identifiers.map { id in lista.first(where: { $0.id == id }) ?? CategoriaGastoEntity(id: id, nombre: id) }
    }

    func entities(matching string: String) async throws -> [CategoriaGastoEntity] {
        let q = string.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return await todas().filter {
            $0.nombre.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).contains(q)
        }
    }

    func suggestedEntities() async throws -> [CategoriaGastoEntity] { await todas() }
}

// MARK: apuntar gasto

/// Siri y Atajos: «Apunta un gasto en Hoy». Va al ciclo de cobro de gastos.yagotg.dev por el proxy de todo y
/// contesta con el texto que compone gastos (lo apuntado, cómo va el ciclo y los avisos de presupuesto).
struct ApuntaGastoIntent: AppIntent {
    static var title: LocalizedStringResource = "Apuntar un gasto"
    static var description = IntentDescription("Apunta un gasto en el ciclo de cobro de Gastos.")

    @Parameter(title: "Importe", description: "En euros", requestValueDialog: "¿Cuánto?") var importe: Double
    @Parameter(title: "Nota", description: "En qué: «cena con Alberto». Si no hay categoría, se adivina por aquí.")
    var nota: String?
    @Parameter(title: "Categoría") var categoria: CategoriaGastoEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Apunta \(\.$importe) € en \(\.$categoria)") {
            \.$nota
        }
    }

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let texto = try await API.apuntaGasto(importe: importe, nota: nota, cat: categoria?.id, src: "siri")
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "\(texto)")
    }
}
