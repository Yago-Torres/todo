import Foundation
import AppIntents

// La pantalla de bloqueo inteligente: qué momento del día es (mañana, antes de entrenar, noche), qué se enseña en cada
// uno y cómo. Compila en la app (el generador del fondo, Hoy/Nativo/Bloqueo/) y en el widget («Tom según la hora»):
// los dos usan la misma lógica y los mismos ajustes, guardados en el app group. Solo Foundation y AppIntents.

// MARK: el momento

enum MomentoFondo: String, Codable, CaseIterable, Identifiable, AppEnum {
    case manana, entreno, noche

    var id: String { rawValue }

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Momento")
    static var caseDisplayRepresentations: [MomentoFondo: DisplayRepresentation] = [
        .manana: "mañana",
        .entreno: "antes de entrenar",
        .noche: "noche",
    ]

    var nombre: String {
        switch self {
        case .manana: return "Mañana"
        case .entreno: return "Entreno"
        case .noche: return "Noche"
        }
    }

    var simbolo: String {
        switch self {
        case .manana: return "sunrise"
        case .entreno: return "dumbbell"
        case .noche: return "moon.stars"
        }
    }
}

/// Lo que puede salir en la capa de información. Los ids se guardan: no cambiarlos nunca.
enum ElementoFondo: String, Codable, CaseIterable, Identifiable {
    case titulo, entreno, ejercicios, habitos, faltan, racha, tareas, sueno, pasos

    var id: String { rawValue }

    var nombre: String {
        switch self {
        case .titulo: return "Saludo"
        case .entreno: return "Entreno de hoy"
        case .ejercicios: return "Ejercicios principales"
        case .habitos: return "Hábitos del día"
        case .faltan: return "Hábitos que faltan"
        case .racha: return "Racha en juego"
        case .tareas: return "Tareas con hora"
        case .sueno: return "Sueño de anoche"
        case .pasos: return "Pasos de ayer"
        }
    }

    var simbolo: String {
        switch self {
        case .titulo: return "textformat"
        case .entreno: return "figure.strengthtraining.traditional"
        case .ejercicios: return "list.number"
        case .habitos: return "checklist"
        case .faltan: return "circle.dashed"
        case .racha: return "flame"
        case .tareas: return "clock"
        case .sueno: return "bed.double"
        case .pasos: return "figure.walk"
        }
    }
}

struct ElementoVisible: Codable, Hashable, Identifiable {
    var elemento: ElementoFondo
    var visible: Bool

    var id: String { elemento.rawValue }
}

// MARK: los ajustes

enum EstiloCapa: String, Codable, CaseIterable, Identifiable {
    case cristal, sombra, banda
    var id: String { rawValue }
    var nombre: String {
        switch self {
        case .cristal: return "Cristal"
        case .sombra: return "Texto"
        case .banda: return "Banda"
        }
    }
}

enum PosicionCapa: String, Codable, CaseIterable, Identifiable {
    case arriba, centro, abajo
    var id: String { rawValue }
    var nombre: String {
        switch self {
        case .arriba: return "Arriba"
        case .centro: return "Centro"
        case .abajo: return "Abajo"
        }
    }
}

/// Los colores de la capa: los del tema (en su versión oscura, texto claro; o en la clara, texto oscuro) o propios.
enum ColoresCapa: String, Codable, CaseIterable, Identifiable {
    case temaOscuro, temaClaro, propios
    var id: String { rawValue }
    var nombre: String {
        switch self {
        case .temaOscuro: return "Tema, texto claro"
        case .temaClaro: return "Tema, texto oscuro"
        case .propios: return "Propios"
        }
    }
}

/// Encuadre y retoque de una foto. `x`, `y` mueven el centro en fracciones del lienzo; `zoom` ≥ 1 sobre «rellenar».
struct AjusteFoto: Codable, Hashable {
    var zoom: Double = 1
    var x: Double = 0
    var y: Double = 0
    /// 0…0,85: un velo negro encima.
    var oscurecer: Double = 0.25
    /// 0…1: hasta 24 pt de desenfoque.
    var desenfoque: Double = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        zoom = (try? c.decodeIfPresent(Double.self, forKey: .zoom)) ?? 1
        x = (try? c.decodeIfPresent(Double.self, forKey: .x)) ?? 0
        y = (try? c.decodeIfPresent(Double.self, forKey: .y)) ?? 0
        oscurecer = (try? c.decodeIfPresent(Double.self, forKey: .oscurecer)) ?? 0.25
        desenfoque = (try? c.decodeIfPresent(Double.self, forKey: .desenfoque)) ?? 0
    }

    private enum CodingKeys: String, CodingKey { case zoom, x, y, oscurecer, desenfoque }
}

struct AjustesFondo: Codable, Equatable {
    static let clave = "fondo.ajustes"
    /// La foto común cuando todos los momentos usan la misma.
    static let comun = "comun"

    // horas, en minutos desde las 00:00
    var despertar = 6 * 60 + 30
    var noche = 21 * 60 + 30
    /// Con hora fija de entreno, el momento empieza `antes` minutos antes y dura hasta `duracion` después de la hora.
    var horaFija = true
    var horaLaborable = 17 * 60 + 45   // lunes a jueves
    var horaViernes = 15 * 60 + 15
    var horaFinde = 11 * 60 + 30
    var antes = 30
    var duracion = 90
    /// Sin hora fija: la franja del momento entreno.
    var franjaInicio = 17 * 60
    var franjaFin = 19 * 60

    // la foto
    var mismaFoto = true
    /// Por momento ("manana"…) o "comun".
    var fotos: [String: AjusteFoto] = [:]

    // la capa
    var estilo: EstiloCapa = .cristal
    var posicion: PosicionCapa = .centro
    /// Deja libre la fila de widgets de debajo de la hora.
    var huecoWidgets = true
    /// "tema" o el id de una letra del catálogo de apariencia.
    var letra = "tema"
    var colores: ColoresCapa = .temaOscuro
    var textoPropio = "#FFFFFF"
    var acentoPropio = "#A8D5BA"
    /// 0,8…1,4
    var tamano = 1.0
    var elementos: [String: [ElementoVisible]] = [:]

    init() {}

    // tolerante: un ajuste nuevo que falte en lo guardado toma su valor por defecto
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AjustesFondo()
        func v<T: Decodable>(_ k: CodingKeys, _ def: T) -> T { ((try? c.decodeIfPresent(T.self, forKey: k)) ?? nil) ?? def }
        despertar = v(.despertar, d.despertar)
        noche = v(.noche, d.noche)
        horaFija = v(.horaFija, d.horaFija)
        horaLaborable = v(.horaLaborable, d.horaLaborable)
        horaViernes = v(.horaViernes, d.horaViernes)
        horaFinde = v(.horaFinde, d.horaFinde)
        antes = v(.antes, d.antes)
        duracion = v(.duracion, d.duracion)
        franjaInicio = v(.franjaInicio, d.franjaInicio)
        franjaFin = v(.franjaFin, d.franjaFin)
        mismaFoto = v(.mismaFoto, d.mismaFoto)
        fotos = v(.fotos, d.fotos)
        estilo = v(.estilo, d.estilo)
        posicion = v(.posicion, d.posicion)
        huecoWidgets = v(.huecoWidgets, d.huecoWidgets)
        letra = v(.letra, d.letra)
        colores = v(.colores, d.colores)
        textoPropio = v(.textoPropio, d.textoPropio)
        acentoPropio = v(.acentoPropio, d.acentoPropio)
        tamano = v(.tamano, d.tamano)
        elementos = v(.elementos, d.elementos)
    }

    private enum CodingKeys: String, CodingKey {
        case despertar, noche, horaFija, horaLaborable, horaViernes, horaFinde, antes, duracion, franjaInicio, franjaFin
        case mismaFoto, fotos, estilo, posicion, huecoWidgets, letra, colores, textoPropio, acentoPropio, tamano, elementos
    }

    static func lee() -> AjustesFondo {
        guard let d = Almacen.defaults.data(forKey: clave),
              let a = try? JSONDecoder().decode(AjustesFondo.self, from: d) else { return AjustesFondo() }
        return a
    }

    func guarda() {
        if let d = try? JSONEncoder().encode(self) { Almacen.defaults.set(d, forKey: Self.clave) }
    }

    // MARK: fotos y elementos

    /// La clave de la foto de un momento: la común si todos usan la misma.
    func claveFoto(_ m: MomentoFondo) -> String { mismaFoto ? Self.comun : m.rawValue }

    func ajusteFoto(_ m: MomentoFondo) -> AjusteFoto { fotos[claveFoto(m)] ?? AjusteFoto() }

    static func porDefecto(_ m: MomentoFondo) -> [ElementoVisible] {
        let orden: [ElementoFondo]
        let visibles: Set<ElementoFondo>
        switch m {
        case .manana:
            orden = [.titulo, .entreno, .habitos, .tareas, .sueno, .pasos, .ejercicios, .faltan, .racha]
            visibles = [.titulo, .entreno, .habitos, .tareas, .sueno]
        case .entreno:
            orden = [.titulo, .ejercicios, .entreno, .habitos, .tareas, .sueno, .pasos, .faltan, .racha]
            visibles = [.titulo, .ejercicios]
        case .noche:
            orden = [.titulo, .faltan, .racha, .habitos, .tareas, .entreno, .ejercicios, .sueno, .pasos]
            visibles = [.titulo, .faltan, .racha]
        }
        return orden.map { ElementoVisible(elemento: $0, visible: visibles.contains($0)) }
    }

    /// Los de ese momento en su orden; los que se añadan en versiones nuevas, al final y ocultos.
    func elementos(_ m: MomentoFondo) -> [ElementoVisible] {
        guard var lista = elementos[m.rawValue], !lista.isEmpty else { return Self.porDefecto(m) }
        for e in ElementoFondo.allCases where !lista.contains(where: { $0.elemento == e }) {
            lista.append(ElementoVisible(elemento: e, visible: false))
        }
        return lista
    }

    // MARK: horas

    private static var calendario: Calendar { Calendar.current }

    private static func minutos(_ d: Date) -> Int {
        let c = calendario.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private static func en(_ dia: Date, _ minutos: Int) -> Date {
        let cero = calendario.startOfDay(for: dia)
        return cero.addingTimeInterval(TimeInterval(minutos) * 60)
    }

    /// La hora del entreno de ese día (L-J, V o fin de semana), en minutos.
    func horaEntreno(_ dia: Date) -> Int {
        switch Self.calendario.component(.weekday, from: dia) {   // 1 = domingo
        case 2...5: return horaLaborable
        case 6: return horaViernes
        default: return horaFinde
        }
    }

    /// Cuándo es el momento entreno ese día.
    func ventanaEntreno(_ dia: Date) -> (inicio: Date, fin: Date) {
        if horaFija {
            let h = horaEntreno(dia)
            return (Self.en(dia, h - antes), Self.en(dia, h + max(15, duracion)))
        }
        let fin = franjaFin > franjaInicio ? franjaFin : franjaInicio + 60
        return (Self.en(dia, franjaInicio), Self.en(dia, fin))
    }

    /// Antes de despertar sigue siendo la mañana (lo que toca el día que empieza); el entreno, solo si falta alguno.
    func momento(_ ahora: Date, hayEntreno: Bool) -> MomentoFondo {
        let m = Self.minutos(ahora)
        if hayEntreno {
            let v = ventanaEntreno(ahora)
            if ahora >= v.inicio && ahora < v.fin { return .entreno }
        }
        if m >= noche && m >= despertar { return .noche }
        return .manana
    }

    /// Las horas en que cambia el momento, desde `desde` y durante `horas` (para el timeline del widget).
    func cambios(desde: Date, horas: Double = 26) -> [Date] {
        let fin = desde.addingTimeInterval(horas * 3600)
        var lista: [Date] = []
        var dia = Self.calendario.startOfDay(for: desde)
        while dia < fin {
            let v = ventanaEntreno(dia)
            for d in [Self.en(dia, despertar), v.inicio, v.fin, Self.en(dia, noche), Self.en(dia, 0)] where d > desde && d <= fin {
                lista.append(d)
            }
            guard let siguiente = Self.calendario.date(byAdding: .day, value: 1, to: dia) else { break }
            dia = siguiente
        }
        return Array(Set(lista)).sorted()
    }

    static func texto(_ minutos: Int) -> String {
        let m = ((minutos % 1440) + 1440) % 1440
        return String(format: "%d:%02d", m / 60, m % 60)
    }
}

// MARK: la copia del entreno con sus ejercicios

/// El entreno de hoy y mañana con sus ejercicios principales. La app lo saca de /api/state (Hoy/Nativo/Bloqueo/) y lo
/// deja en el app group legible con el iPhone bloqueado: la base local no se abre bloqueada y las automatizaciones
/// de Atajos de la mañana corren así.
struct EntrenoFondo: Codable, Hashable {
    var hab: String
    var nombre: String
    var tipo: String
    var hecho: Bool
    var ejercicios: [String]
}

struct InstantaneaFondo: Codable {
    var fecha: Date
    /// "yyyy-MM-dd" → lo que toca ese día.
    var dias: [String: [EntrenoFondo]]

    private static var fichero: URL {
        let carpeta = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Config.grupo)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return carpeta.appendingPathComponent("fondo-entreno.json")
    }

    static func lee() -> InstantaneaFondo? {
        guard let d = try? Data(contentsOf: fichero) else { return nil }
        return try? JSONDecoder().decode(InstantaneaFondo.self, from: d)
    }

    func guarda() {
        guard let d = try? JSONEncoder().encode(self) else { return }
        try? FileManager.default.createDirectory(at: Self.fichero.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? d.write(to: Self.fichero, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

// MARK: lo que se enseña

/// Lo que dice la capa en un momento, ya decidido. Lo pintan el fondo generado y el widget.
struct ContenidoMomento {
    struct Tarea: Hashable {
        var hora: String
        var texto: String
    }

    var momento: MomentoFondo
    var fecha: Date
    var hayDatos: Bool
    var titulo: String
    var entrenos: [EntrenoFondo]
    var habitos: [Habito]
    var faltan: [Habito]
    /// La racha más larga de lo que falta hoy (lo que se pierde si no se hace).
    var rachaEnJuego: Int
    var nombreRacha: String?
    var tareas: [Tarea]
    var suenoMin: Int?
    var pasosAyer: Int?
    var inicioEntreno: Date?

    var completo: Bool { hayDatos && !habitos.isEmpty && faltan.isEmpty }
    var entrenoPendiente: [EntrenoFondo] { entrenos.filter { !$0.hecho } }

    /// Hay entreno de verdad pendiente hoy (la movilidad de la mañana no cuenta para el momento entreno).
    static func hayEntreno(_ hoy: Hoy?, _ inst: InstantaneaFondo?, dia: String) -> Bool {
        lista(hoy, inst, dia: dia).contains { !$0.hecho && $0.tipo != "movilidad" }
    }

    private static func lista(_ hoy: Hoy?, _ inst: InstantaneaFondo?, dia: String) -> [EntrenoFondo] {
        let copia = inst?.dias[dia] ?? []
        guard let hoy, hoy.hoy == dia, let entreno = hoy.entreno else { return copia }
        // lo de /api/hoy manda (lo hecho está al día); los ejercicios, de la copia
        return entreno.map { e in
            let c = copia.first { $0.hab == e.id }
            return EntrenoFondo(hab: e.id, nombre: c?.nombre ?? e.n, tipo: e.tipo, hecho: e.hecho, ejercicios: c?.ejercicios ?? [])
        }
    }

    static func construye(_ ajustes: AjustesFondo, hoy: Hoy?, inst: InstantaneaFondo?, ahora: Date,
                          momento forzado: MomentoFondo? = nil, nombre: String? = nil) -> ContenidoMomento {
        let dia = Fecha.dia(ahora)
        let deHoy = hoy?.hoy == dia ? hoy : nil
        let entrenos = lista(deHoy, inst, dia: dia)
        let hay = entrenos.contains { !$0.hecho && $0.tipo != "movilidad" }
        let m = forzado ?? ajustes.momento(ahora, hayEntreno: hay)

        let todos = deHoy?.habitos ?? []
        let delDia = todos.filter { $0.plan || $0.hecho }
        let habitos = delDia.isEmpty ? todos : delDia
        let faltan = habitos.filter { !$0.hecho }
        let enJuego = faltan.max { $0.racha < $1.racha }

        let tareas: [Tarea] = (deHoy?.tareas ?? [])
            .filter { ($0.due == nil || $0.due == dia) && ($0.hora ?? "").count == 5 }
            .map { Tarea(hora: $0.hora ?? "", texto: $0.t) }
            .sorted { $0.hora < $1.hora }

        let saludo: String
        switch m {
        case .manana:
            let h = Calendar.current.component(.hour, from: ahora)
            let base = h < 13 ? "Buenos días" : (h < 21 ? "Buenas tardes" : "Mañana toca")
            saludo = nombre.map { h < 21 ? "\(base), \($0)" : base } ?? base
        case .entreno:
            saludo = entrenos.first { !$0.hecho && $0.tipo != "movilidad" }.map { "Toca \($0.nombre)" } ?? "Hora de entrenar"
        case .noche:
            saludo = faltan.isEmpty && !habitos.isEmpty ? "Día completo" : "Cierra el día"
        }

        return ContenidoMomento(
            momento: m, fecha: ahora, hayDatos: deHoy != nil, titulo: saludo, entrenos: entrenos, habitos: habitos,
            faltan: faltan, rachaEnJuego: enJuego?.racha ?? 0, nombreRacha: enJuego?.n, tareas: tareas,
            suenoMin: deHoy?.salud?.sueno?.ultimo, pasosAyer: deHoy?.salud?.pasos?.ultimo,
            inicioEntreno: ajustes.horaFija ? Calendar.current.startOfDay(for: ahora)
                .addingTimeInterval(TimeInterval(ajustes.horaEntreno(ahora)) * 60) : nil)
    }

    static func horas(_ minutos: Int) -> String {
        let h = minutos / 60, m = minutos % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// 8430 → "8.430" (es_ES no agrupa las cifras de cuatro).
    static func miles(_ n: Int) -> String {
        var cifras = String(abs(n))
        var partes: [String] = []
        while cifras.count > 3 {
            partes.insert(String(cifras.suffix(3)), at: 0)
            cifras = String(cifras.dropLast(3))
        }
        partes.insert(cifras, at: 0)
        return (n < 0 ? "-" : "") + partes.joined(separator: ".")
    }
}
