import AppIntents

/// Frases de Siri y Atajos. Solo en la app (el widget no las necesita). Como mucho 10 AppShortcut, y cada frase
/// con el nombre de la app: sin Apple Intelligence, Siri solo reconoce estas frases tal cual (con sus huecos).
struct AtajosHoy: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: DileATomIntent(),
                    phrases: ["Dile a \(.applicationName)",
                              "Pregunta a \(.applicationName)",
                              "Pregúntale a \(.applicationName)"],
                    shortTitle: "Dile a Tom",
                    systemImageName: "bubble.left.and.text.bubble.right")
        AppShortcut(intent: HablaConTomIntent(),
                    phrases: ["Habla con \(.applicationName)",
                              "Hablar con \(.applicationName)",
                              "Modo voz en \(.applicationName)"],
                    shortTitle: "Habla con Tom",
                    systemImageName: "waveform")
        AppShortcut(intent: MueveEntrenoIntent(),
                    phrases: ["Mueve el entreno a \(\.$dia) en \(.applicationName)",
                              "Mueve el entreno al \(\.$dia) en \(.applicationName)",
                              "Pasa el entreno a \(\.$dia) en \(.applicationName)",
                              "Pasa el entreno al \(\.$dia) en \(.applicationName)",
                              "Mueve el entreno en \(.applicationName)"],
                    shortTitle: "Mover entreno",
                    systemImageName: "calendar.badge.clock")
        AppShortcut(intent: QueTocaIntent(),
                    phrases: ["Qué toca \(\.$dia) en \(.applicationName)",
                              "Qué toca el \(\.$dia) en \(.applicationName)",
                              "Qué me toca \(\.$dia) en \(.applicationName)",
                              "Qué tengo \(\.$dia) en \(.applicationName)",
                              "Qué toca en \(.applicationName)"],
                    shortTitle: "Qué toca",
                    systemImageName: "list.bullet.clipboard")
        AppShortcut(intent: MarcaHabitoSiriIntent(),
                    phrases: ["Marca \(\.$habito) en \(.applicationName)",
                              "He hecho \(\.$habito) en \(.applicationName)",
                              "Marca un hábito en \(.applicationName)",
                              "Marca hábito en \(.applicationName)"],
                    shortTitle: "Marcar hábito",
                    systemImageName: "checkmark.circle")
        AppShortcut(intent: ApuntaTareaIntent(),
                    phrases: ["Apunta una tarea en \(.applicationName)",
                              "Apunta tarea en \(.applicationName)",
                              "Añade una tarea en \(.applicationName)"],
                    shortTitle: "Apuntar tarea",
                    systemImageName: "plus.circle")
        AppShortcut(intent: ApuntaGastoIntent(),
                    phrases: ["Apunta un gasto en \(.applicationName)",
                              "Apunta gasto en \(.applicationName)",
                              "He gastado en \(.applicationName)"],
                    shortTitle: "Apuntar gasto",
                    systemImageName: "eurosign.circle")
        AppShortcut(intent: PresupuestoIntent(),
                    phrases: ["Cuánto me queda en \(.applicationName)",
                              "Cuánto queda de presupuesto en \(.applicationName)",
                              "Cómo voy de dinero en \(.applicationName)",
                              "Presupuesto en \(.applicationName)"],
                    shortTitle: "Presupuesto",
                    systemImageName: "banknote")
        AppShortcut(intent: ApuntaPesoIntent(),
                    phrases: ["Apunta el peso en \(.applicationName)",
                              "Apunta mi peso en \(.applicationName)",
                              "Registra el peso en \(.applicationName)"],
                    shortTitle: "Apuntar peso",
                    systemImageName: "scalemass")
        AppShortcut(intent: AbreSeccionIntent(),
                    phrases: ["Abre \(\.$seccion) en \(.applicationName)",
                              "Empieza el entreno en \(.applicationName)",
                              "Empezar entreno en \(.applicationName)",
                              "Abre el entreno en \(.applicationName)"],
                    shortTitle: "Abrir sección",
                    systemImageName: "figure.run")
    }
}
