import AppIntents
import WidgetKit

// Compila en la app y en el widget, como Intents.swift: solo Compartido, AppIntents y WidgetKit.
// Siri sin Apple Intelligence solo entiende frases declaradas (Hoy/Atajos.swift): las de aquí con huecos van a
// endpoints que no pasan por Claude y contestan ya con el texto para leerlo; «Dile a Tom» va al bot, con Claude.

// MARK: día para Siri

enum Dia: String, AppEnum {
    case hoy, manana, pasado, lunes, martes, miercoles, jueves, viernes, sabado, domingo

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Día")
    static var caseDisplayRepresentations: [Dia: DisplayRepresentation] = [
        .hoy: "hoy",
        .manana: "mañana",
        .pasado: "pasado mañana",
        .lunes: "lunes",
        .martes: "martes",
        .miercoles: "miércoles",
        .jueves: "jueves",
        .viernes: "viernes",
        .sabado: "sábado",
        .domingo: "domingo",
    ]

    /// El weekday de Calendar (1 = domingo); nil para hoy, mañana y pasado.
    private var diaSemana: Int? {
        switch self {
        case .domingo: return 1
        case .lunes: return 2
        case .martes: return 3
        case .miercoles: return 4
        case .jueves: return 5
        case .viernes: return 6
        case .sabado: return 7
        case .hoy, .manana, .pasado: return nil
        }
    }

    /// "yyyy-MM-dd". «El lunes» es el próximo lunes; si hoy es lunes, hoy solo con `incluyendoHoy`
    /// («qué toca el lunes» sí, «mueve el entreno al lunes» no: eso es el de la semana que viene).
    func fecha(incluyendoHoy: Bool, desde ahora: Date = Date()) -> String {
        let calendario = Calendar.current
        var salto: Int
        switch self {
        case .hoy: salto = 0
        case .manana: salto = 1
        case .pasado: salto = 2
        default:
            let actual = calendario.component(.weekday, from: ahora)
            salto = ((diaSemana ?? actual) - actual + 7) % 7
            if salto == 0 && !incluyendoHoy { salto = 7 }
        }
        return Fecha.dia(calendario.date(byAdding: .day, value: salto, to: ahora) ?? ahora)
    }
}

// MARK: mover el entreno

struct MueveEntrenoIntent: AppIntent {
    static var title: LocalizedStringResource = "Mover el entreno"
    static var description = IntentDescription("Pasa el entreno de hoy que falta por hacer a otro día, con su sesión.")

    @Parameter(title: "Día", requestValueDialog: "¿A qué día?") var dia: Dia

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let texto = try await API.mueveEntreno(a: dia.fecha(incluyendoHoy: false))
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "\(texto)")
    }
}

// MARK: qué toca

struct QueTocaIntent: AppIntent {
    static var title: LocalizedStringResource = "Qué toca"
    static var description = IntentDescription("El entreno, los hábitos que faltan y lo que vence ese día.")

    @Parameter(title: "Día", default: .hoy) var dia: Dia

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let texto = try await API.tocaOCopia(dia: dia.fecha(incluyendoHoy: true))
        return .result(dialog: "\(texto)")
    }
}

// MARK: presupuesto

struct PresupuestoIntent: AppIntent {
    static var title: LocalizedStringResource = "Cuánto queda de presupuesto"
    static var description = IntentDescription("Lo que te queda del ciclo de cobro de Gastos y a cuánto sale al día.")

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let texto = try await API.presupuestoOCopia()
        return .result(dialog: "\(texto)")
    }
}

// MARK: peso

struct ApuntaPesoIntent: AppIntent {
    static var title: LocalizedStringResource = "Apuntar el peso"
    static var description = IntentDescription("Apunta el peso de hoy.")

    @Parameter(title: "Peso", description: "En kilos", requestValueDialog: "¿Cuánto pesas?") var kilos: Double

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let texto = try await API.pesoOEncola(kilos)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "\(texto)")
    }
}

// MARK: dile a Tom (texto libre, con Claude)

struct DileATomIntent: AppIntent {
    static var title: LocalizedStringResource = "Decirle algo a Tom"
    static var description = IntentDescription("Lo que le dirías al bot de Telegram: mover entrenos, apuntar, preguntar…")

    @Parameter(title: "Qué le dices", requestValueDialog: "¿Qué le digo a Tom?") var texto: String

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var dicho = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dicho.isEmpty else { throw APIError(mensaje: "No te he oído") }
        do {
            var respuesta = try await API.tom(dicho)
            // lo que reorganiza la semana se confirma de viva voz, como el «vale» de Telegram
            var vueltas = 0
            while respuesta.confirmar && vueltas < 2 {
                vueltas += 1
                dicho = try await $texto.requestValue("\(respuesta.texto)")
                respuesta = try await API.tom(dicho)
            }
            WidgetCenter.shared.reloadAllTimelines()
            return .result(dialog: "\(respuesta.texto)")
        } catch let error as APIError where error.sinRed {
            // lo entiende Claude en la Pi: sin red no hay nada que guardar para luego
            return .result(dialog: "Para eso Tom necesita conexión. Prueba otra vez cuando vuelva la red.")
        }
    }
}

// MARK: habla con Tom (el modo voz de la app)

/// Abre la app en el modo voz. Lo usan Siri y el botón del centro de control (HoyWidget/ControlTom.swift).
struct HablaConTomIntent: AppIntent {
    static var title: LocalizedStringResource = "Hablar con Tom"
    static var description = IntentDescription("Abre Tom en modo voz: le hablas, te contesta y sigue escuchando.")
    static var openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        Navegador.shared.abreVoz()
        return .result()
    }
}
