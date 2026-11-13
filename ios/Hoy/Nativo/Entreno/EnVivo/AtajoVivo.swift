import AppIntents

/// «Escalada en vivo» como acción de Atajos (para el botón de acción, el toque posterior o la pantalla de inicio).
/// No es un AppShortcut: ya hay 10, el máximo; sale en Atajos buscando «Tom».
struct EscaladaEnVivoIntent: AppIntent {
    static var title: LocalizedStringResource = "Escalada en vivo"
    static var description = IntentDescription("Abre la cámara con el esqueleto en tiempo real para grabar un intento.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        VivoEscalada.shared.abre()
        return .result()
    }
}
