import Foundation

// El entreno tal como está en /api/state (ver «Esquema de data.json» en CLAUDE.md de todo): hábitos, rutinas, plan,
// sesión de cada día y las sesiones de gimnasio serie a serie. Solo lo que usa Entreno; el resto del estado se guarda
// tal cual (DatosEntreno parte del JSON crudo y solo reescribe sus claves).

struct HabitoGym: Identifiable, Hashable, Decodable {
    var id: String
    var n: String
    var c: String

    init(id: String, n: String, c: String) {
        self.id = id
        self.n = n
        self.c = c
    }

    init(from decoder: Decoder) throws {
        let k = try decoder.container(keyedBy: CodingKeys.self)
        id = try k.decode(String.self, forKey: .id)
        n = (try? k.decode(String.self, forKey: .n)) ?? id
        c = (try? k.decode(String.self, forKey: .c)) ?? "#888888"
    }

    private enum CodingKeys: String, CodingKey { case id, n, c }
}

struct BloqueGym: Codable, Hashable {
    var ej: String
    var series: Int
    var repes: String
    var kg: Double
    var seg: Int
    var nota: String

    init(ej: String, series: Int = 3, repes: String = "", kg: Double = 0, seg: Int = 0, nota: String = "") {
        self.ej = ej
        self.series = series
        self.repes = repes
        self.kg = kg
        self.seg = seg
        self.nota = nota
    }

    init(from decoder: Decoder) throws {
        let k = try decoder.container(keyedBy: CodingKeys.self)
        ej = (try? k.decode(String.self, forKey: .ej)) ?? ""
        series = (try? k.decode(Int.self, forKey: .series)) ?? 1
        repes = (try? k.decode(String.self, forKey: .repes)) ?? ""
        kg = (try? k.decode(Double.self, forKey: .kg)) ?? 0
        seg = (try? k.decode(Int.self, forKey: .seg)) ?? 0
        nota = (try? k.decode(String.self, forKey: .nota)) ?? ""
    }

    /// Va por tiempo (la plancha): segundos y no repeticiones.
    var porTiempo: Bool { seg > 0 && repes.isEmpty }
}

struct RutinaGym: Codable, Identifiable, Hashable {
    var id: String
    var n: String
    var tipo: String          // pesas | carrera | movilidad | otro
    var hab: String
    var bloques: [BloqueGym]
    /// Segundos para colocarse entre paso y paso de una rutina guiada (solo si la hay).
    var pausa: Int?

    init(from decoder: Decoder) throws {
        let k = try decoder.container(keyedBy: CodingKeys.self)
        id = try k.decode(String.self, forKey: .id)
        n = (try? k.decode(String.self, forKey: .n)) ?? id
        tipo = (try? k.decode(String.self, forKey: .tipo)) ?? "pesas"
        hab = (try? k.decode(String.self, forKey: .hab)) ?? ""
        bloques = (try? k.decode([BloqueGym].self, forKey: .bloques)) ?? []
        pausa = try? k.decode(Int.self, forKey: .pausa)
    }

    func encode(to encoder: Encoder) throws {
        var k = encoder.container(keyedBy: CodingKeys.self)
        try k.encode(id, forKey: .id)
        try k.encode(n, forKey: .n)
        try k.encode(tipo, forKey: .tipo)
        try k.encode(hab, forKey: .hab)
        try k.encode(bloques, forKey: .bloques)
        // como clean(): solo si la hay, para que las rutinas de carrera.py sigan siendo iguales
        if let pausa, pausa > 0 { try k.encode(pausa, forKey: .pausa) }
    }

    private enum CodingKeys: String, CodingKey { case id, n, tipo, hab, bloques, pausa }

    /// Lo que dura una rutina guiada, en segundos.
    var duracion: Int {
        bloques.reduce(0) { $0 + $1.seg } + (pausa ?? 0) * max(0, bloques.count - 1)
    }
}

/// Una serie hecha: [kilos, repeticiones] (o segundos, en la plancha), como la guarda el servidor.
struct SerieGym: Codable, Hashable {
    var kg: Double
    var n: Int

    init(kg: Double, n: Int) {
        self.kg = kg
        self.n = n
    }

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        kg = (try? c.decode(Double.self)) ?? 0
        n = Int((try? c.decode(Double.self)) ?? 0)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(kg)
        try c.encode(n)
    }

    /// Epley: la fuerza de la serie en una sola cifra.
    var e1rm: Double { kg * (1 + Double(n) / 30) }
}

struct EjercicioGym: Codable, Hashable {
    var ej: String
    var series: [SerieGym]

    init(ej: String, series: [SerieGym] = []) {
        self.ej = ej
        self.series = series
    }

    init(from decoder: Decoder) throws {
        let k = try decoder.container(keyedBy: CodingKeys.self)
        ej = (try? k.decode(String.self, forKey: .ej)) ?? ""
        series = (try? k.decode([SerieGym].self, forKey: .series)) ?? []
    }

    private enum CodingKeys: String, CodingKey { case ej, series }
}

struct SesionGym: Codable, Identifiable, Hashable {
    var id: String
    var rutina: String
    var n: String
    /// Empezó y última serie, en milisegundos desde 1970.
    var t0: Int64
    var t1: Int64
    var min: Int
    var fin: Bool
    /// Ejercicios de la rutina que hoy no se hacen; los añadidos van en `ej` sin más.
    var quita: [String]
    var ej: [EjercicioGym]

    init(id: String, rutina: String, n: String) {
        self.id = id
        self.rutina = rutina
        self.n = n
        t0 = Int64(Date().timeIntervalSince1970 * 1000)
        t1 = 0
        min = 0
        fin = false
        quita = []
        ej = []
    }

    init(from decoder: Decoder) throws {
        let k = try decoder.container(keyedBy: CodingKeys.self)
        id = try k.decode(String.self, forKey: .id)
        rutina = (try? k.decode(String.self, forKey: .rutina)) ?? ""
        n = (try? k.decode(String.self, forKey: .n)) ?? ""
        t0 = Int64((try? k.decode(Double.self, forKey: .t0)) ?? 0)
        t1 = Int64((try? k.decode(Double.self, forKey: .t1)) ?? 0)
        min = (try? k.decode(Int.self, forKey: .min)) ?? 0
        fin = (try? k.decode(Bool.self, forKey: .fin)) ?? false
        quita = (try? k.decode([String].self, forKey: .quita)) ?? []
        ej = (try? k.decode([EjercicioGym].self, forKey: .ej)) ?? []
    }

    private enum CodingKeys: String, CodingKey { case id, rutina, n, t0, t1, min, fin, quita, ej }

    var numeroSeries: Int { ej.reduce(0) { $0 + $1.series.count } }
    var kgMovidos: Double { ej.reduce(0) { a, e in a + e.series.reduce(0) { $0 + $1.kg * Double($1.n) } } }
    var inicio: Date { Date(timeIntervalSince1970: Double(t0) / 1000) }

    /// «52 min · 18 series · 4.310 kg movidos».
    var resumen: String {
        var partes: [String] = []
        if min > 0 { partes.append("\(min) min") }
        partes.append("\(numeroSeries) \(numeroSeries == 1 ? "serie" : "series")")
        if kgMovidos > 0 { partes.append("\(FormatoEnt.miles(Int(kgMovidos.rounded()))) kg movidos") }
        return partes.joined(separator: " · ")
    }
}

struct ActividadGym: Decodable, Hashable {
    var id: String
    var t: String
    var n: String
    var km: Double
    var min: Int
    var seg: Int
    var ritmo: String

    init(from decoder: Decoder) throws {
        let k = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? k.decode(String.self, forKey: .id)) ?? ""
        t = (try? k.decode(String.self, forKey: .t)) ?? ""
        n = (try? k.decode(String.self, forKey: .n)) ?? ""
        km = (try? k.decode(Double.self, forKey: .km)) ?? 0
        min = (try? k.decode(Int.self, forKey: .min)) ?? 0
        seg = (try? k.decode(Int.self, forKey: .seg)) ?? 0
        ritmo = (try? k.decode(String.self, forKey: .ritmo)) ?? ""
    }

    private enum CodingKeys: String, CodingKey { case id, t, n, km, min, seg, ritmo }
}

/// Lo del estado que toca Entreno, ya con tipos.
struct EstadoEntreno {
    var habitos: [HabitoGym] = []
    var rutinas: [RutinaGym] = []
    var log: [String: [String]] = [:]
    var plan: [String: [String]] = [:]
    var sesion: [String: [String: String]] = [:]
    var gym: [String: [SesionGym]] = [:]
    var peso: [String: Double] = [:]
    var actividad: [String: [ActividadGym]] = [:]

    init() {}

    init(crudo: [String: Any]) {
        habitos = Self.lee(crudo["habits"]) ?? []
        rutinas = Self.lee(crudo["rutinas"]) ?? []
        log = Self.lee(crudo["log"]) ?? [:]
        plan = Self.lee(crudo["plan"]) ?? [:]
        sesion = Self.lee(crudo["sesion"]) ?? [:]
        gym = Self.lee(crudo["gym"]) ?? [:]
        peso = Self.lee(crudo["peso"]) ?? [:]
        actividad = Self.lee(crudo["actividad"]) ?? [:]
    }

    private static func lee<T: Decodable>(_ valor: Any?) -> T? {
        guard let valor, JSONSerialization.isValidJSONObject(valor),
              let datos = try? JSONSerialization.data(withJSONObject: valor) else { return nil }
        return try? JSONDecoder().decode(T.self, from: datos)
    }

    private static func objeto<T: Encodable>(_ valor: T) -> Any? {
        guard let datos = try? JSONEncoder().encode(valor) else { return nil }
        return try? JSONSerialization.jsonObject(with: datos)
    }

    /// El estado crudo con lo de aquí puesto encima (lo demás, tal cual vino).
    func escribe(en crudo: [String: Any]) -> [String: Any] {
        var c = crudo
        // los días vacíos fuera, como clean()
        let logLimpio = log.filter { !$0.value.isEmpty }
        let planLimpio = plan.filter { !$0.value.isEmpty }
        let sesionLimpia = sesion.filter { !$0.value.isEmpty }
        let gymLimpio = gym.filter { !$0.value.isEmpty }
        if let v = Self.objeto(rutinas) { c["rutinas"] = v }
        if let v = Self.objeto(logLimpio) { c["log"] = v }
        if let v = Self.objeto(planLimpio) { c["plan"] = v }
        if let v = Self.objeto(sesionLimpia) { c["sesion"] = v }
        if let v = Self.objeto(gymLimpio) { c["gym"] = v }
        if let v = Self.objeto(peso) { c["peso"] = v }
        return c
    }

    // MARK: lo que se lee

    func habito(_ id: String) -> HabitoGym? { habitos.first { $0.id == id } }
    func rutina(_ id: String) -> RutinaGym? { rutinas.first { $0.id == id } }
    func hecho(_ dia: String, _ h: String) -> Bool { log[dia]?.contains(h) ?? false }

    /// Los hábitos que son entrenar: los que tienen alguna rutina que los marca.
    var habitosDeEntreno: [HabitoGym] {
        let con = Set(rutinas.map(\.hab).filter { !$0.isEmpty })
        return habitos.filter { con.contains($0.id) }
    }

    /// Lo que toca entrenar ese día: lo asignado y lo planificado que sea entrenar.
    func entrenoDe(_ dia: String) -> [String] {
        let asignadas = sesion[dia] ?? [:]
        var ids: [String] = []
        for id in asignadas.keys.sorted() + (plan[dia] ?? []) where !ids.contains(id) {
            guard habito(id) != nil else { continue }
            if asignadas[id] != nil || rutinas.contains(where: { $0.hab == id }) { ids.append(id) }
        }
        return ids
    }

    /// La rutina asignada a ese hábito ese día.
    func rutinaDe(_ dia: String, _ h: String) -> RutinaGym? {
        if let r = sesion[dia]?[h] { return rutina(r) }
        return nil
    }

    /// Todas las sesiones con alguna serie, de la más vieja a la más nueva.
    var sesiones: [(dia: String, s: SesionGym)] {
        gym.keys.sorted().flatMap { d in (gym[d] ?? []).map { (dia: d, s: $0) } }
            .filter { $0.s.ej.contains { !$0.series.isEmpty } }
    }

    /// La última vez que se hizo ese ejercicio, sin contar la sesión `menos`.
    func ultima(_ ej: String, menos: String?) -> [SerieGym]? {
        for x in sesiones.reversed() where x.s.id != menos {
            if let e = x.s.ej.first(where: { $0.ej == ej && !$0.series.isEmpty }) { return e.series }
        }
        return nil
    }

    /// Doble progresión: si la última vez todas las series llegaron al tope del rango con el mismo peso, toca subir.
    func sugerencia(_ b: BloqueGym, menos: String?) -> (kg: Double, sube: Bool, ultima: [SerieGym]?) {
        guard let u = ultima(b.ej, menos: menos) else { return (b.kg, false, nil) }
        let top = u.map(\.kg).max() ?? 0
        let r = FormatoEnt.rango(b.repes)
        let sube = r != nil && top > 0 && u.count >= b.series && u.allSatisfy { $0.kg >= top && $0.n >= (r?.1 ?? 0) }
        return (sube ? top + (top < 20 ? 1 : 2.5) : top, sube, u)
    }

    /// La serie supera a todas las de antes de ese ejercicio (fuerza estimada; sin peso, repes). La primera vez no.
    func esRecord(_ ej: String, _ s: SerieGym, sesion actual: String) -> Bool {
        let de = sesiones.flatMap { x in x.s.ej.filter { $0.ej == ej }.map { (id: x.s.id, series: $0.series) } }
        guard de.contains(where: { $0.id != actual }) else { return false }
        let antes = de.flatMap(\.series)
        return s.kg > 0 ? antes.allSatisfy { s.e1rm > $0.e1rm } : antes.allSatisfy { s.n > $0.n }
    }

    /// Todos los ejercicios conocidos (rutinas e historial), en orden alfabético.
    var ejercicios: [String] {
        var vistos = Set<String>()
        var out: [String] = []
        for n in rutinas.flatMap({ $0.bloques.map(\.ej) }) + sesiones.flatMap({ $0.s.ej.map(\.ej) }) where vistos.insert(n).inserted {
            out.append(n)
        }
        return out.sorted { $0.localizedCompare($1) == .orderedAscending }
    }

    /// Cómo se hizo un ejercicio en alguna rutina: series y repes de partida para uno añadido.
    func molde(_ ej: String) -> BloqueGym {
        rutinas.flatMap(\.bloques).first { $0.ej == ej } ?? BloqueGym(ej: ej)
    }

    /// Lo que tocaba en los últimos 6 días y no se hizo (lo más reciente de cada hábito), si hoy no toca ya lo mismo.
    func atrasados(hoy: String) -> [(dia: String, h: String)] {
        let entrena = Set(rutinas.filter { $0.tipo != "movilidad" && !$0.hab.isEmpty }.map(\.hab))
        var ultimo: [String: String] = [:]
        for i in stride(from: 6, through: 1, by: -1) {
            let d = FormatoEnt.mas(hoy, -i)
            let ids = Set((plan[d] ?? []) + Array((sesion[d] ?? [:]).keys))
            for h in ids where entrena.contains(h) && habito(h) != nil && !hecho(d, h) { ultimo[h] = d }
            for h in log[d] ?? [] where (ultimo[h] ?? "9999") < d { ultimo[h] = nil }
        }
        return ultimo.filter { par in
            !hecho(hoy, par.key) && !(plan[hoy] ?? []).contains(par.key) && sesion[hoy]?[par.key] == nil
        }
        .map { (dia: $0.value, h: $0.key) }
        .sorted { $0.dia < $1.dia }
    }

    // MARK: cambiar

    mutating func marca(_ h: String, dia: String, _ on: Bool) {
        var l = log[dia] ?? []
        if on { if !l.contains(h) { l.append(h) } } else { l.removeAll { $0 == h } }
        log[dia] = l.isEmpty ? nil : l
    }

    /// Mueve el hábito `h` del día `de` al día `a`, con su sesión. Si el destino ya lo tenía, se cambian las dos
    /// sesiones (como mueve_entreno() del servidor): nunca se pierde una.
    mutating func mueve(_ h: String, de: String, a: String) {
        guard de != a else { return }
        let rDe = sesion[de]?[h]
        let rA = sesion[a]?[h]
        let estabaEnA = (plan[a] ?? []).contains(h) || rA != nil
        var pDe = plan[de] ?? []
        pDe.removeAll { $0 == h }
        if estabaEnA { pDe.append(h) }
        plan[de] = pDe.isEmpty ? nil : pDe
        var pA = plan[a] ?? []
        if !pA.contains(h) { pA.append(h) }
        plan[a] = pA
        var sDe = sesion[de] ?? [:]
        var sA = sesion[a] ?? [:]
        sDe[h] = estabaEnA ? rA : nil
        sA[h] = rDe ?? rA
        sesion[de] = sDe.isEmpty ? nil : sDe
        sesion[a] = sA.isEmpty ? nil : sA
    }

    mutating func planifica(_ h: String, dia: String, rutina r: String?) {
        var p = plan[dia] ?? []
        if !p.contains(h) { p.append(h) }
        plan[dia] = p
        if let r {
            var s = sesion[dia] ?? [:]
            s[h] = r
            sesion[dia] = s
        }
    }

    mutating func quitaDelPlan(_ h: String, dia: String) {
        var p = plan[dia] ?? []
        p.removeAll { $0 == h }
        plan[dia] = p.isEmpty ? nil : p
        var s = sesion[dia] ?? [:]
        s[h] = nil
        sesion[dia] = s.isEmpty ? nil : s
    }

    mutating func asigna(_ h: String, dia: String, rutina r: String) {
        var s = sesion[dia] ?? [:]
        s[h] = r
        sesion[dia] = s
    }

    /// La sesión con ese id de ese día, para cambiarla.
    mutating func conSesion(_ dia: String, _ id: String, _ cambio: (inout SesionGym) -> Void) {
        guard var lista = gym[dia], let i = lista.firstIndex(where: { $0.id == id }) else { return }
        cambio(&lista[i])
        gym[dia] = lista
    }

    func sesionGym(_ dia: String, _ id: String) -> SesionGym? { gym[dia]?.first { $0.id == id } }
}

// MARK: músculos

enum Musculos {
    static let lista: [(id: String, n: String)] = [
        ("pecho", "Pecho"), ("hombro", "Hombros"), ("espalda", "Espalda"), ("trapecio", "Trapecio"), ("biceps", "Bíceps"),
        ("triceps", "Tríceps"), ("antebrazo", "Antebrazo"), ("core", "Abdomen"), ("lumbar", "Lumbar"), ("gluteo", "Glúteo"),
        ("cuadriceps", "Cuádriceps"), ("femoral", "Femoral"), ("gemelo", "Gemelos"),
    ]

    /// La primera regla que encaja manda; 1 = músculo principal, 0,5 = ayuda (las mismas de entreno.html).
    private static let reglas: [(String, [String: Double])] = [
        ("triceps|frances|press cerrado", ["triceps": 1]),
        ("fondos", ["pecho": 1, "triceps": 1, "hombro": 0.5]),
        ("face pull", ["hombro": 1, "trapecio": 1]),
        ("press militar|press hombro|arnold", ["hombro": 1, "triceps": 0.5]),
        ("laterales|pajaro|posterior", ["hombro": 1]),
        ("press banca|press inclinado|press pecho|flies|aperturas|cruce", ["pecho": 1, "triceps": 0.5, "hombro": 0.5]),
        ("curl femoral|femoral", ["femoral": 1]),
        ("curl|preacher|biceps|martillo", ["biceps": 1, "antebrazo": 0.5]),
        ("dominada|pulldown|jalon|pull al pecho|pullover", ["espalda": 1, "biceps": 0.5]),
        ("remo", ["espalda": 1, "trapecio": 0.5, "biceps": 0.5]),
        ("encogimiento", ["trapecio": 1]),
        ("rumano|buenos dias", ["femoral": 1, "gluteo": 1, "lumbar": 0.5]),
        ("peso muerto", ["gluteo": 1, "femoral": 1, "lumbar": 1, "espalda": 0.5]),
        ("extension de cuadriceps|extension de pierna", ["cuadriceps": 1]),
        ("prensa|sentadilla|squat|hack|zancada|lunge|bulgara", ["cuadriceps": 1, "gluteo": 1]),
        ("gemelo|talon", ["gemelo": 1]),
        ("hip thrust|puente|gluteo|abductor", ["gluteo": 1]),
        ("core|plancha|abdominal|crunch|rueda", ["core": 1]),
    ]

    static func de(_ ej: String) -> [String: Double] {
        let plano = ej.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES")).lowercased()
        for (patron, m) in reglas where patron.split(separator: "|").contains(where: { plano.contains($0) }) {
            return m
        }
        return [:]
    }

    /// Series por músculo en los últimos 7 días.
    static func porMusculo(_ e: EstadoEntreno, hoy: String) -> [String: Double] {
        var n = Dictionary(uniqueKeysWithValues: lista.map { ($0.id, 0.0) })
        let desde = FormatoEnt.mas(hoy, -6)
        for x in e.sesiones where x.dia >= desde {
            for ej in x.s.ej {
                for (m, f) in de(ej.ej) { n[m, default: 0] += f * Double(ej.series.count) }
            }
        }
        return n
    }

    static func nivel(_ n: Double) -> Int { n <= 0 ? 0 : n < 4 ? 1 : n < 10 ? 2 : 3 }
}

// MARK: formatos

enum FormatoEnt {
    /// 72.5 → «72,5», como se escribe aquí (hasta dos decimales, sin ceros de más).
    static func num(_ x: Double) -> String {
        let r = (x * 100).rounded() / 100
        if r == r.rounded() { return String(Int(r)) }
        var s = String(format: "%.2f", r)
        while s.hasSuffix("0") { s.removeLast() }
        return s.replacingOccurrences(of: ".", with: ",")
    }

    /// «72,5» o «72.5» → 72.5.
    static func lee(_ texto: String) -> Double? {
        Double(texto.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    static func mmss(_ s: Int) -> String {
        let s = max(0, s)
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    static func hmmss(_ s: Int) -> String {
        s >= 3600 ? "\(s / 3600):\(String(format: "%02d", (s % 3600) / 60)):\(String(format: "%02d", s % 60))" : mmss(s)
    }

    static func miles(_ n: Int) -> String {
        let cifras = String(abs(n))
        var out = ""
        for (i, c) in cifras.enumerated() {
            if i > 0 && (cifras.count - i) % 3 == 0 { out += "." }
            out.append(c)
        }
        return (n < 0 ? "-" : "") + out
    }

    /// «8-10» → (8, 10); «12» → (12, 12).
    static func rango(_ texto: String) -> (Int, Int)? {
        let partes = texto.split(whereSeparator: { $0 == "-" || $0 == "–" }).map { $0.trimmingCharacters(in: .whitespaces) }
        if partes.count == 2, let a = Int(partes[0]), let b = Int(partes[1]) { return (a, b) }
        if partes.count == 1, let a = Int(partes[0]) { return (a, a) }
        return nil
    }

    private static func analiza(_ dia: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: dia).map { $0.addingTimeInterval(12 * 3600) }
    }

    static func fecha(_ dia: String) -> Date { analiza(dia) ?? Date() }

    static func mas(_ dia: String, _ n: Int) -> String {
        Fecha.dia(Calendar(identifier: .gregorian).date(byAdding: .day, value: n, to: fecha(dia)) ?? Date())
    }

    static func dias(de: String, a: String) -> Int {
        Int((fecha(a).timeIntervalSince(fecha(de)) / 86400).rounded())
    }

    private static func texto(_ dia: String, _ formato: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = formato
        return f.string(from: fecha(dia)).replacingOccurrences(of: ".", with: "")
    }

    /// «5 nov».
    static func corta(_ dia: String) -> String { texto(dia, "d MMM") }
    /// «lun 5».
    static func diaSemana(_ dia: String) -> String { texto(dia, "EEE d") }
    /// «lunes 5 de noviembre».
    static func larga(_ dia: String) -> String { texto(dia, "EEEE d 'de' MMMM") }
    /// «L», «M», «X»…
    static func letra(_ dia: String) -> String {
        let i = (Calendar(identifier: .gregorian).component(.weekday, from: fecha(dia)) + 5) % 7
        return ["L", "M", "X", "J", "V", "S", "D"][i]
    }

    /// El lunes de la semana de ese día.
    static func lunes(_ dia: String) -> String {
        let i = (Calendar(identifier: .gregorian).component(.weekday, from: fecha(dia)) + 5) % 7
        return mas(dia, -i)
    }

    static func uid() -> String {
        let letras = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<8).map { _ in letras.randomElement() ?? "a" })
    }

    static func ahoraMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}
