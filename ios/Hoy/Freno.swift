import SwiftUI
import AppIntents
import UIKit

/// Freno de apps. Sin cuenta de pago no hay API de Tiempo de uso (FamilyControls), así que va con Atajos:
/// una automatización «Al abrir Instagram» → acción «Frenar Instagram» de Tom → «Abrir URL» con lo que devuelve.
/// Con pase (o aperturas libres que quedan) devuelve instagram://, que con Instagram ya delante no hace nada; sin pase,
/// hoy://freno?app=instagram, que abre Tom con la pantalla de freno. Entrar da un pase de unos minutos y abre la app;
/// esa apertura vuelve a disparar la automatización, pero ya con pase, así que no hay bucle.
/// Todo se queda en el iPhone (app group): lo que haces con tus apps no sale de aquí.
enum AppFrenada: String, AppEnum, CaseIterable, Codable, Identifiable {
    case instagram, tiktok, youtube, x, facebook, reddit, whatsapp, twitch, threads, bereal

    var id: String { rawValue }

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "App"
    static var caseDisplayRepresentations: [AppFrenada: DisplayRepresentation] = [
        .instagram: "Instagram", .tiktok: "TikTok", .youtube: "YouTube", .x: "X (Twitter)", .facebook: "Facebook",
        .reddit: "Reddit", .whatsapp: "WhatsApp", .twitch: "Twitch", .threads: "Threads", .bereal: "BeReal",
    ]

    var nombre: String {
        switch self {
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .youtube: "YouTube"
        case .x: "X"
        case .facebook: "Facebook"
        case .reddit: "Reddit"
        case .whatsapp: "WhatsApp"
        case .twitch: "Twitch"
        case .threads: "Threads"
        case .bereal: "BeReal"
        }
    }

    /// El esquema de URL de cada app (abrirla no necesita LSApplicationQueriesSchemes; solo canOpenURL lo pediría).
    var enlace: URL {
        let esquema = switch self {
        case .instagram: "instagram://"
        case .tiktok: "snssdk1233://"
        case .youtube: "youtube://"
        case .x: "twitter://"
        case .facebook: "fb://"
        case .reddit: "reddit://"
        case .whatsapp: "whatsapp://"
        case .twitch: "twitch://"
        case .threads: "barcelona://"
        case .bereal: "bereal://"
        }
        return URL(string: esquema)!
    }

    var freno: URL { URL(string: "hoy://freno?app=\(rawValue)")! }
}

/// Lo de un día con una app.
struct ContadorFreno: Codable, Equatable {
    var aperturas = 0   // veces que saltó la automatización sin pase
    var entradas = 0    // veces que dijiste «Entrar»
    var renuncias = 0   // veces que dijiste «Mejor no»
    var minutos = 0     // minutos de pase concedidos
}

enum Freno {
    private static let claveRegistro = "freno.registro"
    private static func clavePase(_ app: AppFrenada) -> String { "freno.pase.\(app.rawValue)" }

    static var minutosPase: Int { max(1, Almacen.defaults.object(forKey: "freno.minutos") as? Int ?? 5) }
    static var esperaBase: Int { max(3, Almacen.defaults.object(forKey: "freno.espera") as? Int ?? 8) }
    static var libresAlDia: Int { max(0, Almacen.defaults.object(forKey: "freno.libres") as? Int ?? 0) }

    private static var hoy: String { Fecha.dia(Date()) }

    /// {dia: {app: contador}}, solo los últimos 30 días.
    static func registro() -> [String: [String: ContadorFreno]] {
        guard let datos = Almacen.defaults.data(forKey: claveRegistro),
              let r = try? JSONDecoder().decode([String: [String: ContadorFreno]].self, from: datos) else { return [:] }
        return r
    }

    private static func guarda(_ r: [String: [String: ContadorFreno]]) {
        let limite = Fecha.dia(Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date())
        let recortado = r.filter { $0.key >= limite }
        if let datos = try? JSONEncoder().encode(recortado) { Almacen.defaults.set(datos, forKey: claveRegistro) }
    }

    static func deHoy(_ app: AppFrenada) -> ContadorFreno { registro()[hoy]?[app.rawValue] ?? ContadorFreno() }

    private static func apunta(_ app: AppFrenada, _ cambio: (inout ContadorFreno) -> Void) {
        var r = registro()
        var c = r[hoy]?[app.rawValue] ?? ContadorFreno()
        cambio(&c)
        r[hoy, default: [:]][app.rawValue] = c
        guarda(r)
    }

    static func pase(_ app: AppFrenada) -> Date? {
        let hasta = Almacen.defaults.double(forKey: clavePase(app))
        return hasta > Date().timeIntervalSince1970 ? Date(timeIntervalSince1970: hasta) : nil
    }

    private static func daPase(_ app: AppFrenada, minutos: Int) {
        Almacen.defaults.set(Date().addingTimeInterval(Double(minutos) * 60).timeIntervalSince1970, forKey: clavePase(app))
    }

    /// Lo que hace la acción de Atajos: el enlace que hay que abrir ahora.
    static func alAbrir(_ app: AppFrenada) -> URL {
        if pase(app) != nil { return app.enlace }
        apunta(app) { $0.aperturas += 1 }
        if deHoy(app).aperturas <= libresAlDia {
            daPase(app, minutos: minutosPase)
            apunta(app) { $0.minutos += minutosPase }
            return app.enlace
        }
        return app.freno
    }

    /// Cada entrada de más hoy alarga la espera 4 s, hasta 30.
    static func espera(_ app: AppFrenada) -> Int {
        min(30, esperaBase + 4 * deHoy(app).entradas)
    }

    static func entra(_ app: AppFrenada, minutos: Int) {
        daPase(app, minutos: minutos)
        apunta(app) { $0.entradas += 1; $0.minutos += minutos }
        Task { @MainActor in _ = await UIApplication.shared.open(app.enlace) }
    }

    static func renuncia(_ app: AppFrenada) {
        apunta(app) { $0.renuncias += 1 }
    }
}

/// La acción de Atajos. No abre Tom: devuelve el enlace para la acción «Abrir URL» que va detrás.
struct FrenoIntent: AppIntent {
    static var title: LocalizedStringResource = "Frenar app"
    static var description = IntentDescription("Para la automatización «Al abrir una app»: pon detrás «Abrir URL» con el resultado. Con pase no pasa nada; sin pase, Tom te pregunta si de verdad quieres entrar.")
    static var openAppWhenRun = false

    @Parameter(title: "App")
    var app: AppFrenada

    static var parameterSummary: some ParameterSummary { Summary("Frenar \(\.$app)") }

    func perform() async throws -> some IntentResult & ReturnsValue<URL> {
        .result(value: Freno.alAbrir(app))
    }
}

/// La pantalla que sale con hoy://freno?app=…: respira unos segundos y luego decides.
struct PantallaFreno: View {
    let app: AppFrenada
    let cerrar: () -> Void

    @State private var queda: Int
    @State private var respira = false
    private let contador: ContadorFreno
    private let reloj = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(app: AppFrenada, cerrar: @escaping () -> Void) {
        self.app = app
        self.cerrar = cerrar
        _queda = State(initialValue: Freno.espera(app))
        contador = Freno.deHoy(app)
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Text(app.nombre)
                .font(.largeTitle.bold())
            Text(resumen)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.18))
                    .frame(width: 180, height: 180)
                    .scaleEffect(respira ? 1 : 0.55)
                Text(queda > 0 ? "\(queda)" : "¿Seguro?")
                    .font(queda > 0 ? .system(size: 44, weight: .semibold, design: .monospaced) : .title2.bold())
                    .contentTransition(.numericText())
            }
            .frame(height: 200)
            .accessibilityElement(children: .combine)
            Text(queda > 0 ? (respira ? "Suelta el aire…" : "Coge aire…") : "Respira y decide")
                .foregroundStyle(.secondary)
            Spacer()
            VStack(spacing: 12) {
                Button {
                    Freno.renuncia(app)
                    Haptica.shared.toca("marcar")
                    cerrar()
                } label: {
                    Text("Mejor no").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    Freno.entra(app, minutos: Freno.minutosPase)
                    cerrar()
                } label: {
                    Text("Entrar \(Freno.minutosPase) min").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(queda > 0)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("Fondo").ignoresSafeArea())
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { respira = true }
        }
        .onReceive(reloj) { _ in
            guard queda > 0 else { return }
            withAnimation { queda -= 1 }
        }
    }

    private var resumen: String {
        var partes = ["Hoy la has abierto \(contador.aperturas) \(contador.aperturas == 1 ? "vez" : "veces")"]
        if contador.entradas > 0 { partes.append("has entrado \(contador.entradas) (\(contador.minutos) min)") }
        if contador.renuncias > 0 { partes.append("y lo has dejado \(contador.renuncias)") }
        return partes.joined(separator: ", ") + "."
    }
}

/// En Configurar: los ajustes del freno, lo de hoy y cómo se monta la automatización.
struct SeccionFreno: View {
    @AppStorage("freno.minutos", store: Almacen.defaults) private var minutos = 5
    @AppStorage("freno.espera", store: Almacen.defaults) private var espera = 8
    @AppStorage("freno.libres", store: Almacen.defaults) private var libres = 0
    @State private var ayuda = false

    var body: some View {
        Section {
            Stepper("Pase al entrar: \(minutos) min", value: $minutos, in: 1...60)
            Stepper("Espera: \(espera) s", value: $espera, in: 3...30)
            Stepper("Aperturas libres al día: \(libres)", value: $libres, in: 0...20)
            let hoy = AppFrenada.allCases.map { ($0, Freno.deHoy($0)) }.filter { $0.1.aperturas > 0 }
            ForEach(hoy, id: \.0) { app, c in
                LabeledContent(app.nombre, value: "\(c.aperturas) aperturas · \(c.entradas) entradas · \(c.minutos) min")
                    .font(.callout)
            }
            DisclosureGroup("Cómo se activa", isExpanded: $ayuda) {
                Text("""
                Una vez por app, en Atajos → Automatización → Nueva → App:
                1. Elige la app (Instagram…), marca «Se abre» y «Ejecutar inmediatamente».
                2. Añade la acción «Frenar app» de Tom y elige esa misma app.
                3. Añade «Abrir URL» (la de Atajos): coge sola el resultado de la anterior.
                Sin pase, se abre Tom y te pregunta. Cada vez que entras hoy, la espera crece 4 s.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        } header: {
            Text("Freno de apps")
        } footer: {
            Text("Lo que abres no sale del iPhone. Para un bloqueo que no se pueda saltar, usa además Tiempo de uso → Límites de apps.")
        }
    }
}
