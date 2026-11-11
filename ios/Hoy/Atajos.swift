import AppIntents

/// Frases de Siri y Atajos. Solo en la app (el widget no las necesita).
struct AtajosHoy: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: MarcaHabitoSiriIntent(),
                    phrases: ["Marca un hábito en \(.applicationName)",
                              "Marca hábito en \(.applicationName)"],
                    shortTitle: "Marcar hábito",
                    systemImageName: "checkmark.circle")
        AppShortcut(intent: ApuntaTareaIntent(),
                    phrases: ["Apunta una tarea en \(.applicationName)",
                              "Apunta tarea en \(.applicationName)"],
                    shortTitle: "Apuntar tarea",
                    systemImageName: "plus.circle")
        AppShortcut(intent: ApuntaGastoIntent(),
                    phrases: ["Apunta un gasto en \(.applicationName)",
                              "Apunta gasto en \(.applicationName)"],
                    shortTitle: "Apuntar gasto",
                    systemImageName: "eurosign.circle")
        AppShortcut(intent: AbreSeccionIntent(seccion: .entreno),
                    phrases: ["Abre entreno en \(.applicationName)",
                              "Abre el entreno en \(.applicationName)"],
                    shortTitle: "Abrir entreno",
                    systemImageName: "figure.run")
    }
}
