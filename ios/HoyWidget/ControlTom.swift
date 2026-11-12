import AppIntents
import SwiftUI
import WidgetKit

/// «Habla con Tom» en el centro de control (y en el botón de acción o la pantalla de bloqueo): abre el modo voz.
@available(iOS 18.0, *)
struct HablaConTomControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "dev.yagotg.hoy.voz") {
            ControlWidgetButton(action: HablaConTomIntent()) {
                Label("Habla con Tom", systemImage: "waveform")
            }
        }
        .displayName("Habla con Tom")
        .description("Abre Tom en modo voz.")
    }
}

// MARK: más controles del centro de control (iOS 18)

/// Abre una ruta de la app con su enlace hoy://ruta?r=… (el control corre en el proceso del widget, no en el de la app).
@available(iOS 18.0, *)
struct AbreRutaIntent: AppIntent {
    static var title: LocalizedStringResource = "Abrir en Tom"
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Ruta") var ruta: String

    init() {}

    init(ruta: String) { self.ruta = ruta }

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(rutaURL(ruta)))
    }
}

/// «Apuntar tarea»: un control no puede pedir texto, así que abre Pendientes.
@available(iOS 18.0, *)
struct ApuntaTareaControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "dev.yagotg.hoy.tarea") {
            ControlWidgetButton(action: AbreRutaIntent(ruta: "/pendientes.html?nueva=1")) {
                Label("Apuntar tarea", systemImage: "plus.circle")
            }
        }
        .displayName("Apuntar tarea")
        .description("Abre Pendientes para apuntar una tarea.")
    }
}

// MARK: marcar un hábito

@available(iOS 18.0, *)
struct ConfiguraHabitoControl: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "Hábito"

    @Parameter(title: "Hábito") var habito: HabitoEntity?

    init() {}
}

/// El interruptor del control: marca o desmarca el hábito elegido (con la cola si no hay red).
@available(iOS 18.0, *)
struct MarcaHabitoControlIntent: SetValueIntent {
    static var title: LocalizedStringResource = "Marcar hábito"
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Hábito (id)") var habito: String
    @Parameter(title: "Nombre") var nombre: String
    @Parameter(title: "Hecho") var value: Bool

    init() {}

    init(habito: String, nombre: String) {
        self.habito = habito
        self.nombre = nombre
    }

    func perform() async throws -> some IntentResult {
        guard !habito.isEmpty else { return .result() }
        Optimista.marcaHabito(id: habito, hecho: value)
        try await API.marcaOEncola(habito: habito, hecho: value)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

@available(iOS 18.0, *)
struct EstadoHabitoControl: Sendable {
    var id: String
    var nombre: String
    var hecho: Bool
}

@available(iOS 18.0, *)
struct ProveedorHabitoControl: AppIntentControlValueProvider {
    func previewValue(configuration: ConfiguraHabitoControl) -> EstadoHabitoControl {
        EstadoHabitoControl(id: "", nombre: configuration.habito?.nombre ?? "Hábito", hecho: false)
    }

    func currentValue(configuration: ConfiguraHabitoControl) async throws -> EstadoHabitoControl {
        guard let e = configuration.habito else { return EstadoHabitoControl(id: "", nombre: "Elige un hábito", hecho: false) }
        let hoy = (try? await API.hoy()) ?? Almacen.leeHoy()
        return EstadoHabitoControl(id: e.id, nombre: e.nombre, hecho: hoy?.habitos.first { $0.id == e.id }?.hecho ?? false)
    }
}

@available(iOS 18.0, *)
struct MarcaHabitoControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "dev.yagotg.hoy.habito", provider: ProveedorHabitoControl()) { estado in
            ControlWidgetToggle(isOn: estado.hecho, action: MarcaHabitoControlIntent(habito: estado.id, nombre: estado.nombre)) {
                Label(estado.nombre, systemImage: estado.hecho ? "checkmark.circle.fill" : "circle")
            } valueLabel: { hecho in
                Text(hecho ? "Hecho" : "Sin hacer")
            }
        }
        .displayName("Marcar hábito")
        .description("Marca o desmarca un hábito de hoy.")
        .promptsForUserConfiguration()
    }
}

// MARK: abrir una sección

@available(iOS 18.0, *)
struct ConfiguraSeccionControl: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "Sección"

    @Parameter(title: "Sección", default: .entreno) var seccion: Seccion

    init() {}
}

extension Seccion {
    var nombre: String {
        switch self {
        case .entreno: return "Entreno"
        case .pendientes: return "Pendientes"
        case .habitos: return "Hábitos"
        case .salud: return "Salud"
        }
    }

    var simbolo: String {
        switch self {
        case .entreno: return "dumbbell.fill"
        case .pendientes: return "checklist"
        case .habitos: return "flame.fill"
        case .salud: return "heart.fill"
        }
    }
}

@available(iOS 18.0, *)
struct ProveedorSeccionControl: AppIntentControlValueProvider {
    func previewValue(configuration: ConfiguraSeccionControl) -> Seccion { configuration.seccion }

    func currentValue(configuration: ConfiguraSeccionControl) async throws -> Seccion { configuration.seccion }
}

@available(iOS 18.0, *)
struct AbreSeccionControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "dev.yagotg.hoy.seccion", provider: ProveedorSeccionControl()) { seccion in
            ControlWidgetButton(action: AbreRutaIntent(ruta: seccion.ruta)) {
                Label("Abrir \(seccion.nombre)", systemImage: seccion.simbolo)
            }
        }
        .displayName("Abrir una sección")
        .description("Abre Tom en Entreno, Pendientes, Hábitos o Salud.")
        .promptsForUserConfiguration()
    }
}
