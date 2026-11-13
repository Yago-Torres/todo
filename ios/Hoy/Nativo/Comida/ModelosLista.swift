import Foundation

// La lista de Comida: lo que hay en casa o se quiere comprar, cada cosa con sus macros. Los modelos usan las mismas
// claves que GET/POST /api/comida/cesta (comida.yagotg.dev, cesta.json) para poder guardar la copia local tal cual.

private extension KeyedDecodingContainer {
    func v<T: Decodable>(_ clave: Key, _ por: T) -> T { (try? decodeIfPresent(T.self, forKey: clave)) ?? por }
}

/// Valores por 100 g (o 100 ml).
struct Por100: Codable, Hashable {
    var kcal = 0.0
    var prot = 0.0
    var hc = 0.0
    var grasa = 0.0

    enum CodingKeys: String, CodingKey { case kcal, prot, hc, grasa }

    init(kcal: Double = 0, prot: Double = 0, hc: Double = 0, grasa: Double = 0) {
        self.kcal = kcal; self.prot = prot; self.hc = hc; self.grasa = grasa
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        kcal = c.v(.kcal, 0); prot = c.v(.prot, 0); hc = c.v(.hc, 0); grasa = c.v(.grasa, 0)
    }

    /// Los macros de `gramos` de esto.
    func por(_ gramos: Double) -> Macros {
        Macros(kcal: kcal * gramos / 100, prot: prot * gramos / 100, hc: hc * gramos / 100, grasa: grasa * gramos / 100)
    }
}

/// kcal y gramos de proteína, hidratos y grasa de una cantidad concreta.
struct Macros: Codable, Hashable {
    var kcal = 0.0
    var prot = 0.0
    var hc = 0.0
    var grasa = 0.0

    enum CodingKeys: String, CodingKey { case kcal, prot, hc, grasa }

    init(kcal: Double = 0, prot: Double = 0, hc: Double = 0, grasa: Double = 0) {
        self.kcal = kcal; self.prot = prot; self.hc = hc; self.grasa = grasa
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        kcal = c.v(.kcal, 0); prot = c.v(.prot, 0); hc = c.v(.hc, 0); grasa = c.v(.grasa, 0)
    }

    static func + (a: Macros, b: Macros) -> Macros {
        Macros(kcal: a.kcal + b.kcal, prot: a.prot + b.prot, hc: a.hc + b.hc, grasa: a.grasa + b.grasa)
    }

    /// Reparto de las kcal entre los tres macros (4, 4 y 9 kcal por gramo), de 0 a 1.
    var reparto: (prot: Double, hc: Double, grasa: Double) {
        let p = prot * 4, h = hc * 4, g = grasa * 9
        let t = p + h + g
        guard t > 0 else { return (0, 0, 0) }
        return (p / t, h / t, g / t)
    }
}

/// Una unidad de la lista: gramos, mililitros o unidades (un huevo, un plátano).
enum UnidadLista: String, Codable, CaseIterable, Identifiable {
    case g, ml, ud
    var id: String { rawValue }
    var nombre: String { self == .ud ? "ud" : rawValue }
    var largo: String {
        switch self {
        case .g: return "gramos"
        case .ml: return "mililitros"
        case .ud: return "unidades"
        }
    }
    var porDefecto: Double { self == .ud ? 1 : 100 }
}

/// Un alimento del catálogo (despensa de comida, tabla base o estimado por Claude).
struct Alimento: Codable, Hashable, Identifiable {
    var id = ""
    var n = ""
    var n100 = Por100()
    var u = UnidadLista.g
    var g_ud: Double?
    var fuente = ""
    var alias = ""
    var origen = ""

    enum CodingKeys: String, CodingKey { case id, n, n100, u, g_ud, fuente, alias, origen }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.v(.id, ""); n = c.v(.n, ""); n100 = c.v(.n100, Por100()); u = c.v(.u, .g)
        g_ud = try? c.decodeIfPresent(Double.self, forKey: .g_ud)
        fuente = c.v(.fuente, ""); alias = c.v(.alias, ""); origen = c.v(.origen, "")
    }
}

/// Una línea de la lista. El id lo pone la app (sin red no hay servidor que lo dé); `t` es la última edición en ms
/// (el servidor se queda con la más reciente), `t0` cuándo se añadió (el orden).
struct ItemLista: Codable, Hashable, Identifiable {
    var id = UUID().uuidString
    var a = ""
    var n = ""
    var c = 100.0
    var u = UnidadLista.g
    var hecho = false
    var t = 0.0
    var t0 = 0.0
    var n100: Por100?
    var g_ud: Double?

    enum CodingKeys: String, CodingKey { case id, a, n, c, u, hecho, t, t0, n100, g_ud }

    init(alimento: Alimento?, nombre: String, cantidad: Double?, unidad: UnidadLista?) {
        let ahora = Date().timeIntervalSince1970 * 1000
        a = alimento?.id ?? ""
        n = nombre
        u = unidad ?? alimento?.u ?? .g
        c = cantidad ?? u.porDefecto
        t = ahora
        t0 = ahora
        n100 = alimento?.n100
        g_ud = alimento?.g_ud
    }

    init(from d: Decoder) throws {
        let k = try d.container(keyedBy: CodingKeys.self)
        id = k.v(.id, ""); a = k.v(.a, ""); n = k.v(.n, ""); c = k.v(.c, 0); u = k.v(.u, .g)
        hecho = k.v(.hecho, false); t = k.v(.t, 0); t0 = k.v(.t0, 0)
        n100 = try? k.decodeIfPresent(Por100.self, forKey: .n100)
        g_ud = try? k.decodeIfPresent(Double.self, forKey: .g_ud)
    }

    /// Gramos (ml ≈ g); las unidades pasan por el peso de una. nil si no se sabe.
    var gramos: Double? {
        if u != .ud { return c }
        guard let g_ud, g_ud > 0 else { return nil }
        return c * g_ud
    }

    var macros: Macros? {
        guard let n100, let g = gramos else { return nil }
        return n100.por(g)
    }

    /// «150 g», «2 ud», «1,5 l».
    var cantidadTexto: String { Formato.cantidad(c, u) }
}

/// Una receta hecha con lo de la lista (POST /api/comida/receta), o una favorita.
struct RecetaLista: Codable, Hashable, Identifiable {
    var id = ""
    var n = ""
    var raciones = 1
    var tiempo = 0
    var ing: [Linea] = []
    var pasos: [String] = []
    var nota = ""
    var instruccion = ""
    var total = Macros()
    var racion = Macros()
    var completa = true
    var t = 0.0

    enum CodingKeys: String, CodingKey { case id, n, raciones, tiempo, ing, pasos, nota, instruccion, total, racion, completa, t }

    struct Linea: Codable, Hashable {
        var n = ""
        var c = 0.0
        var u = UnidadLista.g
        var extra = false
        var completa = true
        var kcal = 0.0
        var prot = 0.0
        var hc = 0.0
        var grasa = 0.0

        enum CodingKeys: String, CodingKey { case n, c, u, extra, completa, kcal, prot, hc, grasa }

        init(from d: Decoder) throws {
            let k = try d.container(keyedBy: CodingKeys.self)
            n = k.v(.n, ""); c = k.v(.c, 0); u = k.v(.u, .g); extra = k.v(.extra, false); completa = k.v(.completa, true)
            kcal = k.v(.kcal, 0); prot = k.v(.prot, 0); hc = k.v(.hc, 0); grasa = k.v(.grasa, 0)
        }
    }

    init(from d: Decoder) throws {
        let k = try d.container(keyedBy: CodingKeys.self)
        id = k.v(.id, ""); n = k.v(.n, ""); raciones = max(1, k.v(.raciones, 1)); tiempo = k.v(.tiempo, 0)
        ing = k.v(.ing, []); pasos = k.v(.pasos, []); nota = k.v(.nota, ""); instruccion = k.v(.instruccion, "")
        total = k.v(.total, Macros()); racion = k.v(.racion, Macros()); completa = k.v(.completa, true); t = k.v(.t, 0)
    }
}

/// Lo que devuelve /api/comida/cesta. El total se calcula aquí (sin red también).
struct CestaComida: Codable {
    var items: [ItemLista] = []
    var favoritas: [RecetaLista] = []
    var ultima: RecetaLista?
    var objetivo: Objetivo?

    enum CodingKeys: String, CodingKey { case items, favoritas, ultima, objetivo }

    struct Objetivo: Codable, Hashable {
        var kcal = 0.0
        var proteina = 0.0

        enum CodingKeys: String, CodingKey { case kcal, proteina }

        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            kcal = c.v(.kcal, 0); proteina = c.v(.proteina, 0)
        }
    }

    init() {}

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        items = c.v(.items, []); favoritas = c.v(.favoritas, [])
        ultima = try? c.decodeIfPresent(RecetaLista.self, forKey: .ultima)
        objetivo = try? c.decodeIfPresent(Objetivo.self, forKey: .objetivo)
    }
}

/// Un cambio suelto de la lista (lo que se manda en POST /api/comida/cesta {ops}). Idempotentes: la cola puede
/// mandar uno dos veces sin que pase nada.
enum OpLista {
    case pon(ItemLista)
    case quita(String)
    case fav(RecetaLista)
    case desfav(String)

    var json: [String: Any] {
        switch self {
        case .pon(let i): return ["op": "pon", "item": Self.objeto(i)]
        case .quita(let id): return ["op": "quita", "id": id]
        case .fav(let r): return ["op": "fav", "receta": Self.objeto(r)]
        case .desfav(let id): return ["op": "desfav", "id": id]
        }
    }

    private static func objeto<T: Encodable>(_ x: T) -> Any {
        guard let d = try? JSONEncoder().encode(x), let o = try? JSONSerialization.jsonObject(with: d) else { return [:] }
        return o
    }

    /// Para rehacer encima de lo del servidor los cambios que siguen en la cola.
    static func desde(_ o: [String: Any]) -> OpLista? {
        func decodifica<T: Decodable>(_ x: Any?) -> T? {
            guard let x, let d = try? JSONSerialization.data(withJSONObject: x) else { return nil }
            return try? JSONDecoder().decode(T.self, from: d)
        }
        switch o["op"] as? String {
        case "pon": return (decodifica(o["item"]) as ItemLista?).map { .pon($0) }
        case "quita": return (o["id"] as? String).map { .quita($0) }
        case "fav": return (decodifica(o["receta"]) as RecetaLista?).map { .fav($0) }
        case "desfav": return (o["id"] as? String).map { .desfav($0) }
        default: return nil
        }
    }

    /// Lo mismo que aplica_ops() del servidor.
    func aplica(_ c: inout CestaComida) {
        switch self {
        case .pon(var i):
            if let k = c.items.firstIndex(where: { $0.id == i.id }) {
                guard c.items[k].t <= i.t else { return }
                if c.items[k].t0 > 0 { i.t0 = c.items[k].t0 }
                if i.n100 == nil { i.n100 = c.items[k].n100; i.g_ud = i.g_ud ?? c.items[k].g_ud }
                c.items[k] = i
            } else {
                c.items.append(i)
            }
        case .quita(let id):
            c.items.removeAll { $0.id == id }
        case .fav(let r):
            if let k = c.favoritas.firstIndex(where: { $0.id == r.id }) { c.favoritas[k] = r } else { c.favoritas.append(r) }
        case .desfav(let id):
            c.favoritas.removeAll { $0.id == id }
        }
    }
}

enum Formato {
    private static func numero(_ x: Double, _ decimales: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.numberStyle = .decimal
        f.maximumFractionDigits = decimales
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: x)) ?? String(x)
    }

    /// «1.234» (sin decimales, con punto de miles).
    static func entero(_ x: Double) -> String { numero(x.rounded(), 0) }

    /// «12,5».
    static func decimal(_ x: Double, _ d: Int = 1) -> String { numero(x, d) }

    static func cantidad(_ c: Double, _ u: UnidadLista) -> String {
        switch u {
        case .ud: return "\(numero(c, 1)) ud"
        case .g: return c >= 1000 ? "\(numero(c / 1000, 2)) kg" : "\(numero(c, 0)) g"
        case .ml: return c >= 1000 ? "\(numero(c / 1000, 2)) l" : "\(numero(c, 0)) ml"
        }
    }

    /// Lee «1,5» o «1.5».
    static func lee(_ texto: String) -> Double? {
        Double(texto.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
}

/// Buscar en el catálogo como el servidor (busca_alimentos): igual, por el principio, por una palabra, por dentro, por alias.
enum BuscaAlimentos {
    static func clave(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func busca(_ q: String, en catalogo: [Alimento], limite: Int = 6) -> [Alimento] {
        let q = clave(q)
        guard !q.isEmpty else { return [] }
        var puntos: [(Int, Int, Alimento)] = []
        for a in catalogo {
            let n = clave(a.n)
            let p: Int
            if n == q { p = 0 }
            else if n.hasPrefix(q) { p = 1 }
            else if n.split(separator: " ").contains(where: { $0.hasPrefix(q) }) { p = 2 }
            else if n.contains(q) { p = 3 }
            else if clave(a.alias).contains(q) { p = 4 }
            else { continue }
            puntos.append((p, n.count, a))
        }
        return puntos.sorted { ($0.0, $0.1) < ($1.0, $1.1) }.prefix(limite).map { $0.2 }
    }

    /// «200 g pollo», «2 huevos», «1,5 l leche» → (200, g, «pollo»). Sin número delante, solo el nombre.
    static func separa(_ texto: String) -> (cantidad: Double?, unidad: UnidadLista?, nombre: String) {
        let limpio = texto.trimmingCharacters(in: .whitespaces)
        let patron = #"^(\d+(?:[.,]\d+)?)\s*(kg|g|gr|gramos|l|ml|ud|uds|unidad|unidades)?\.?\s+(?:de\s+)?(.+)$"#
        guard let re = try? NSRegularExpression(pattern: patron, options: [.caseInsensitive]),
              let m = re.firstMatch(in: limpio, range: NSRange(limpio.startIndex..., in: limpio)),
              let rNum = Range(m.range(at: 1), in: limpio), let rNom = Range(m.range(at: 3), in: limpio),
              var c = Formato.lee(String(limpio[rNum])) else { return (nil, nil, limpio) }
        var u: UnidadLista?
        if let rU = Range(m.range(at: 2), in: limpio) {
            switch limpio[rU].lowercased() {
            case "kg": u = .g; c *= 1000
            case "l": u = .ml; c *= 1000
            case "ml": u = .ml
            case "ud", "uds", "unidad", "unidades": u = .ud
            default: u = .g
            }
        }
        return (c, u, String(limpio[rNom]))
    }
}

extension String {
    /// «Pechuga de pollo» (solo la primera letra; capitalized pondría «Pechuga De Pollo»).
    var capitalizadoComida: String { prefix(1).uppercased() + String(dropFirst()) }
}
