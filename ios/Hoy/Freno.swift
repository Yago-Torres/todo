import SwiftUI
import AppIntents
import UIKit

/// Freno de apps. Sin cuenta de pago no hay API de Tiempo de uso (FamilyControls), así que va con Atajos:
/// una automatización «Al abrir Instagram» → acción «Frenar app» de Tom (nombre libre; si no la conozco, su esquema) → «Abrir URL» con lo que devuelve.
/// Con pase (o aperturas libres que quedan) devuelve instagram://, que con Instagram ya delante no hace nada; sin pase,
/// hoy://freno?app=instagram, que abre Tom con la pantalla de freno. Entrar da un pase de unos minutos y abre la app;
/// esa apertura vuelve a disparar la automatización, pero ya con pase, así que no hay bucle.
/// Todo se queda en el iPhone (app group): lo que haces con tus apps no sale de aquí.
struct AppFrenada: Codable, Hashable, Identifiable {
    let rawValue: String   // nombre normalizado: «Brawl Stars» → brawlstars
    let nombre: String
    let esquema: String

    var id: String { rawValue }
    var enlace: URL { URL(string: esquema) ?? URL(string: "hoy://")! }
    var freno: URL { URL(string: "hoy://freno?app=\(rawValue)")! }

    /// Esquemas conocidos; abrirlos no necesita LSApplicationQueriesSchemes (solo canOpenURL lo pediría).
    static let conocidas: [String: (String, String)] = [
        "instagram": ("Instagram", "instagram://"), "tiktok": ("TikTok", "snssdk1233://"),
        "youtube": ("YouTube", "youtube://"), "x": ("X", "twitter://"), "twitter": ("X", "twitter://"),
        "facebook": ("Facebook", "fb://"), "reddit": ("Reddit", "reddit://"), "whatsapp": ("WhatsApp", "whatsapp://"),
        "twitch": ("Twitch", "twitch://"), "threads": ("Threads", "barcelona://"), "bereal": ("BeReal", "bereal://"),
        "telegram": ("Telegram", "tg://"), "snapchat": ("Snapchat", "snapchat://"), "pinterest": ("Pinterest", "pinterest://"),
        "discord": ("Discord", "discord://"), "linkedin": ("LinkedIn", "linkedin://"), "netflix": ("Netflix", "nflx://"),
        "spotify": ("Spotify", "spotify://"), "tinder": ("Tinder", "tinder://"),
        "brawlstars": ("Brawl Stars", "brawlstars://"), "clashroyale": ("Clash Royale", "clashroyale://"),
        "clashofclans": ("Clash of Clans", "clashofclans://"),
    ]

    static func normaliza(_ texto: String) -> String {
        texto.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// La que ya pasó por la acción de Atajos (se guarda al ejecutarla).
    init?(rawValue: String) {
        guard let a = Freno.apps()[rawValue] else { return nil }
        self = a
    }

    init(rawValue: String, nombre: String, esquema: String) {
        self.rawValue = rawValue; self.nombre = nombre; self.esquema = esquema
    }

    /// Lo que escribes en Atajos: nombre libre y, si no la conozco, su enlace (brawlstars://…).
    static func resuelve(nombre: String, esquema: String?) -> AppFrenada? {
        let clave = normaliza(nombre)
        guard !clave.isEmpty else { return nil }
        var e = esquema?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !e.isEmpty, !e.contains(":") { e += "://" }
        if let c = conocidas[clave] {
            return AppFrenada(rawValue: clave, nombre: c.0, esquema: e.isEmpty ? c.1 : e)
        }
        if e.isEmpty { e = Freno.apps()[clave]?.esquema ?? "" }
        guard !e.isEmpty else { return nil }
        return AppFrenada(rawValue: clave, nombre: nombre.trimmingCharacters(in: .whitespaces), esquema: e)
    }
}

/// Lo de un día con una app.
struct ContadorFreno: Codable, Equatable {
    var aperturas = 0   // veces que saltó la automatización sin pase
    var entradas = 0    // veces que dijiste «Entrar»
    var renuncias = 0   // veces que dijiste «Mejor no»
    var minutos = 0     // minutos de pase concedidos
    var segundos = 0    // uso real: de abrirla a cerrarla (automatización «Al cerrar» → «App cerrada»)

    var minutosReales: Int { (segundos + 30) / 60 }

    init() {}

    // los registros de antes no traen «segundos»
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        aperturas = try c.decodeIfPresent(Int.self, forKey: .aperturas) ?? 0
        entradas = try c.decodeIfPresent(Int.self, forKey: .entradas) ?? 0
        renuncias = try c.decodeIfPresent(Int.self, forKey: .renuncias) ?? 0
        minutos = try c.decodeIfPresent(Int.self, forKey: .minutos) ?? 0
        segundos = try c.decodeIfPresent(Int.self, forKey: .segundos) ?? 0
    }
}

enum Freno {
    private static let claveRegistro = "freno.registro"
    private static func clavePase(_ app: AppFrenada) -> String { "freno.pase.\(app.rawValue)" }

    static var minutosPase: Int { max(1, Almacen.defaults.object(forKey: "freno.minutos") as? Int ?? 5) }
    static var esperaBase: Int { max(3, Almacen.defaults.object(forKey: "freno.espera") as? Int ?? 8) }
    static var libresAlDia: Int { max(0, Almacen.defaults.object(forKey: "freno.libres") as? Int ?? 0) }
    /// Minutos de uso real al día por app (0: sin límite). Pasado, la espera es la máxima y no hay aperturas libres.
    static var limiteDiario: Int { max(0, Almacen.defaults.object(forKey: "freno.limite") as? Int ?? 0) }

    static func pasadoDeLimite(_ app: AppFrenada) -> Bool {
        limiteDiario > 0 && deHoy(app).segundos >= limiteDiario * 60
    }

    private static func claveAbierta(_ app: AppFrenada) -> String { "freno.abierta.\(app.rawValue)" }

    /// La app ha pasado a primer plano (con pase): desde aquí cuenta el uso real.
    private static func marcaAbierta(_ app: AppFrenada) {
        if Almacen.defaults.double(forKey: claveAbierta(app)) == 0 {
            Almacen.defaults.set(Date().timeIntervalSince1970, forKey: claveAbierta(app))
        }
    }

    /// Lo que hace «App cerrada»: suma el rato desde que se abrió (si es creíble: menos de 4 h) al día en que se abrió.
    static func alCerrar(_ app: AppFrenada) {
        let desde = Almacen.defaults.double(forKey: claveAbierta(app))
        Almacen.defaults.removeObject(forKey: claveAbierta(app))
        guard desde > 0 else { return }
        let segundos = Int(Date().timeIntervalSince1970 - desde)
        guard segundos > 0, segundos < 4 * 3600 else { return }
        recuerda(app)
        apunta(app) { $0.segundos += segundos }
    }

    private static var hoy: String { Fecha.dia(Date()) }

    /// Las apps que han pasado por la acción, para que la pantalla de freno sepa su nombre y su enlace.
    static func apps() -> [String: AppFrenada] {
        guard let datos = Almacen.defaults.data(forKey: "freno.apps"),
              let r = try? JSONDecoder().decode([String: AppFrenada].self, from: datos) else { return [:] }
        return r
    }

    static func recuerda(_ app: AppFrenada) {
        var r = apps()
        guard r[app.rawValue] != app else { return }
        r[app.rawValue] = app
        if let datos = try? JSONEncoder().encode(r) { Almacen.defaults.set(datos, forKey: "freno.apps") }
    }

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
        recuerda(app)
        if pase(app) != nil { marcaAbierta(app); return app.enlace }
        apunta(app) { $0.aperturas += 1 }
        if deHoy(app).aperturas <= libresAlDia, !pasadoDeLimite(app) {
            daPase(app, minutos: minutosPase)
            apunta(app) { $0.minutos += minutosPase }
            marcaAbierta(app)
            return app.enlace
        }
        return app.freno
    }

    /// Cada entrada de más hoy alarga la espera 4 s, hasta 30; pasado el límite diario, 30 directamente.
    static func espera(_ app: AppFrenada) -> Int {
        pasadoDeLimite(app) ? 30 : min(30, esperaBase + 4 * deHoy(app).entradas)
    }

    static func entra(_ app: AppFrenada, minutos: Int) {
        daPase(app, minutos: minutos)
        apunta(app) { $0.entradas += 1; $0.minutos += minutos }
        Task { @MainActor in
            Isla.pase(app.nombre, minutos: minutos)   // «Instagram · 4:59» en la isla hasta que caduque
            _ = await UIApplication.shared.open(app.enlace)
        }
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

    @Parameter(title: "App", description: "El nombre de la app, tal cual: Instagram, TikTok, Brawl Stars…")
    var app: String

    @Parameter(title: "Enlace", description: "Solo si Tom no conoce la app: su esquema de URL, como brawlstars://")
    var enlace: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Frenar \(\.$app)") { \.$enlace }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<URL> {
        guard let frenada = AppFrenada.resuelve(nombre: app, esquema: enlace) else {
            throw FrenoError.sinEnlace(app)
        }
        return .result(value: Freno.alAbrir(frenada))
    }
}

enum FrenoError: Error, CustomLocalizedStringResourceConvertible {
    case sinEnlace(String)
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .sinEnlace(let app):
            "No sé cómo abrir «\(app)». Pon su esquema de URL en «Enlace» (por ejemplo, brawlstars://)."
        }
    }
}

/// La segunda automatización, «Al cerrar la app»: con ella Tom mide el uso real (de abrir a cerrar).
struct FrenoCerradaIntent: AppIntent {
    static var title: LocalizedStringResource = "App cerrada"
    static var description = IntentDescription("Para la automatización «Al cerrar una app»: Tom suma el rato que la has tenido abierta. Pon el mismo nombre que en «Frenar app».")
    static var openAppWhenRun = false

    @Parameter(title: "App", description: "El mismo nombre que en «Frenar app»")
    var app: String

    static var parameterSummary: some ParameterSummary { Summary("Cerrada \(\.$app)") }

    func perform() async throws -> some IntentResult {
        let clave = AppFrenada.normaliza(app)
        let frenada = Freno.apps()[clave] ?? AppFrenada.resuelve(nombre: app, esquema: nil)
            ?? AppFrenada(rawValue: clave, nombre: app, esquema: "")
        Freno.alCerrar(frenada)
        return .result()
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
                    .fill(Tema.acento.opacity(0.18))
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
                .foregroundStyle(Tema.acentoTexto)
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
        .background(Tema.fondo.ignoresSafeArea())
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
        var texto = partes.joined(separator: ", ") + "."
        if contador.segundos > 0 {
            texto += "\nUso real hoy: \(contador.minutosReales) min"
            if Freno.limiteDiario > 0 {
                texto += contador.segundos >= Freno.limiteDiario * 60
                    ? " (te has pasado de los \(Freno.limiteDiario) que te pusiste)."
                    : " de \(Freno.limiteDiario)."
            } else {
                texto += "."
            }
        }
        return texto
    }
}

/// En Configurar: los ajustes del freno, lo de hoy y cómo se monta la automatización.
struct SeccionFreno: View {
    @AppStorage("freno.minutos", store: Almacen.defaults) private var minutos = 5
    @AppStorage("freno.espera", store: Almacen.defaults) private var espera = 8
    @AppStorage("freno.libres", store: Almacen.defaults) private var libres = 0
    @AppStorage("freno.limite", store: Almacen.defaults) private var limite = 0
    @State private var ayuda = false

    var body: some View {
        Section {
            Stepper("Pase al entrar: \(minutos) min", value: $minutos, in: 1...60)
            Stepper("Espera: \(espera) s", value: $espera, in: 3...30)
            Stepper("Aperturas libres al día: \(libres)", value: $libres, in: 0...20)
            Stepper(limite == 0 ? "Límite diario: sin límite" : "Límite diario: \(limite) min",
                    value: $limite, in: 0...240, step: 5)
            let hoy = Freno.apps().values.sorted { $0.nombre < $1.nombre }.map { ($0, Freno.deHoy($0)) }.filter { $0.1.aperturas > 0 }
            ForEach(hoy, id: \.0) { app, c in
                LabeledContent(app.nombre, value: c.segundos > 0
                               ? "\(c.minutosReales) min de uso · \(c.aperturas) aperturas · \(c.entradas) entradas"
                               : "\(c.aperturas) aperturas · \(c.entradas) entradas · \(c.minutos) min de pase")
                    .font(.callout)
            }
            DisclosureGroup("Cómo se activa", isExpanded: $ayuda) {
                Text("""
                Una vez por app, en Atajos → Automatización → Nueva → App:
                1. Elige la app (Instagram…), marca «Se abre» y «Ejecutar inmediatamente».
                2. Añade la acción «Frenar app» de Tom (búscala: no está entre los recuadros) y escribe el nombre de la app. Si Tom no la conoce, te pedirá su enlace en «Enlace» (p. ej. brawlstars://).
                3. Añade «Abrir URL» (la de Atajos): coge sola el resultado de la anterior.
                Sin pase, se abre Tom y te pregunta. Cada vez que entras hoy, la espera crece 4 s.

                Para medir el uso real (y el límite diario), otra automatización por app:
                App → la misma, marca solo «Se cierra» y «Ejecutar inmediatamente» → acción «App cerrada» de Tom con el mismo nombre.
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
