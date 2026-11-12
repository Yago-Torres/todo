import AppIntents
import UniformTypeIdentifiers

// Las acciones de Atajos del fondo de bloqueo. Solo en la app (no en el widget): corren en el proceso de la app, que
// iOS lanza en segundo plano sin abrirla (openAppWhenRun = false), con más memoria que una extensión. Sin red usan lo
// guardado (DatosFondo). Atajos pasa la imagen a «Establecer fondo de pantalla».

struct FondoAhoraIntent: AppIntent {
    static var title: LocalizedStringResource = "Fondo de Tom ahora"
    static var description = IntentDescription(
        "La imagen de la pantalla de bloqueo con lo que toca ahora: por la mañana el día, antes de entrenar los ejercicios y por la noche lo que falta. Pásala a «Establecer fondo de pantalla».")
    static var openAppWhenRun = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let r = try await GeneradorFondo.genera()
        return .result(value: IntentFile(data: r.datos, filename: "Tom-\(r.momento.rawValue).jpg", type: .jpeg))
    }
}

struct FondoMomentoIntent: AppIntent {
    static var title: LocalizedStringResource = "Fondo de Tom de un momento"
    static var description = IntentDescription(
        "La imagen de la pantalla de bloqueo de un momento concreto (mañana, antes de entrenar o noche), sea la hora que sea.")
    static var openAppWhenRun = false

    @Parameter(title: "Momento", default: .manana) var momento: MomentoFondo

    static var parameterSummary: some ParameterSummary {
        Summary("Fondo de Tom de \(\.$momento)")
    }

    init() {}

    init(momento: MomentoFondo) { self.momento = momento }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let r = try await GeneradorFondo.genera(momento: momento)
        return .result(value: IntentFile(data: r.datos, filename: "Tom-\(r.momento.rawValue).jpg", type: .jpeg))
    }
}
