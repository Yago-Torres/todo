import Foundation
import SwiftUI
import Observation

/// Cómo es la mascota (el objeto «mascota» de /api/ajustes). Los rangos son los de MASCOTA en main.py: el servidor
/// recorta lo que se salga, así que aquí se limitan igual para que el deslizador y lo guardado coincidan.
struct MascotaAjustes: Codable, Equatable {
    var tipo = "fantasma"          // fantasma | flor
    var color = "#CDE77F"
    var extra = ""                 // "" | lazo | gorro | gafas
    var rubor = false
    var paseo = true
    var semilla = 14
    var grumos = 0.2, pera = 0.35, cola = -12.0, flecos = 4.0, fleco = 10.0, ancho = 26.0, alto = 73.0
    var ojoI = 4.5, ojoD = 4.5, sep = 14.0, ojosY = 0.38

    /// Un deslizador del fantasma: clave en el JSON, nombre, rango y paso (los de CONTROLES de ajustes.html).
    struct Control: Identifiable {
        let id: String
        let nombre: String
        let rango: ClosedRange<Double>
        let paso: Double
        let valor: WritableKeyPath<MascotaAjustes, Double>
    }

    static let controles: [Control] = [
        Control(id: "ancho", nombre: "Ancho", rango: 20...36, paso: 1, valor: \.ancho),
        Control(id: "alto", nombre: "Alto", rango: 50...90, paso: 1, valor: \.alto),
        Control(id: "pera", nombre: "Forma de pera", rango: 0...1, paso: 0.05, valor: \.pera),
        Control(id: "cola", nombre: "Cola de lado", rango: -24...24, paso: 1, valor: \.cola),
        Control(id: "flecos", nombre: "Flecos", rango: 2...6, paso: 1, valor: \.flecos),
        Control(id: "fleco", nombre: "Largo de flecos", rango: 2...14, paso: 1, valor: \.fleco),
        Control(id: "grumos", nombre: "Grumos", rango: 0...0.5, paso: 0.01, valor: \.grumos),
        Control(id: "ojoI", nombre: "Ojo izquierdo", rango: 2...8, paso: 0.5, valor: \.ojoI),
        Control(id: "ojoD", nombre: "Ojo derecho", rango: 2...8, paso: 0.5, valor: \.ojoD),
        Control(id: "sep", nombre: "Separación de ojos", rango: 8...26, paso: 1, valor: \.sep),
        Control(id: "ojosY", nombre: "Altura de ojos", rango: 0.15...0.6, paso: 0.01, valor: \.ojosY),
    ]

    init() {}

    /// Tolerante: lo que falte o venga raro se queda en el valor por defecto.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Claves.self)
        let d = MascotaAjustes()
        tipo = (try? c.decode(String.self, forKey: .tipo)) == "flor" ? "flor" : "fantasma"
        let col = (try? c.decode(String.self, forKey: .color)) ?? d.color
        color = Oklch.esHex(col) ? col : d.color
        let ex = (try? c.decode(String.self, forKey: .extra)) ?? ""
        extra = ["lazo", "gorro", "gafas"].contains(ex) ? ex : ""
        rubor = (try? c.decode(Bool.self, forKey: .rubor)) ?? d.rubor
        paseo = (try? c.decode(Bool.self, forKey: .paseo)) ?? d.paseo
        semilla = Int((try? c.decode(Double.self, forKey: .semilla)) ?? Double(d.semilla))
        func n(_ k: Claves, _ por: Double) -> Double { (try? c.decode(Double.self, forKey: k)) ?? por }
        grumos = n(.grumos, d.grumos); pera = n(.pera, d.pera); cola = n(.cola, d.cola); flecos = n(.flecos, d.flecos)
        fleco = n(.fleco, d.fleco); ancho = n(.ancho, d.ancho); alto = n(.alto, d.alto)
        ojoI = n(.ojoI, d.ojoI); ojoD = n(.ojoD, d.ojoD); sep = n(.sep, d.sep); ojosY = n(.ojosY, d.ojosY)
    }

    enum Claves: String, CodingKey {
        case tipo, color, extra, rubor, paseo, semilla, grumos, pera, cola, flecos, fleco, ancho, alto, ojoI, ojoD, sep, ojosY
    }
}

struct ModuloAjustes: Codable, Equatable {
    var activo = true
    var barra = true

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activo = (try? c.decode(Bool.self, forKey: .activo)) ?? true
        barra = (try? c.decode(Bool.self, forKey: .barra)) ?? true
    }
    enum CodingKeys: String, CodingKey { case activo, barra }
}

/// /api/ajustes: lo que solo editaba la web. La apariencia y la disposición de pantallas las lleva Aspecto, así que ni se
/// leen ni se mandan: el servidor conserva las suyas cuando faltan.
struct AjustesTom: Codable, Equatable {
    /// Los módulos del servidor, en el orden de la web.
    static let modulosConocidos: [(id: String, nombre: String)] = [
        ("habitos", "Hábitos"), ("pendientes", "Pendientes"), ("entreno", "Entreno"), ("salud", "Salud"),
        ("comida", "Comida"), ("gastos", "Gastos"), ("documentos", "Documentos"),
    ]

    var nombre = ""
    var sonidos = false
    var modulos: [String: ModuloAjustes] = [:]
    var limites: [String: Int] = [:]
    var mascota = MascotaAjustes()
    /// Los módulos que esta instancia no puede alcanzar (sin la clave de su app en el servidor). Solo se lee.
    var sinApp: [String] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nombre = (try? c.decode(String.self, forKey: .nombre)) ?? ""
        sonidos = (try? c.decode(Bool.self, forKey: .sonidos)) ?? false
        modulos = (try? c.decode([String: ModuloAjustes].self, forKey: .modulos)) ?? [:]
        limites = (try? c.decode([String: Int].self, forKey: .limites)) ?? [:]
        mascota = (try? c.decode(MascotaAjustes.self, forKey: .mascota)) ?? MascotaAjustes()
        sinApp = (try? c.decode([String].self, forKey: .sinApp)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(nombre, forKey: .nombre)
        try c.encode(sonidos, forKey: .sonidos)
        try c.encode(modulos, forKey: .modulos)
        try c.encode(limites, forKey: .limites)
        try c.encode(mascota, forKey: .mascota)
    }

    enum CodingKeys: String, CodingKey {
        case nombre, sonidos, modulos, limites, mascota
        case sinApp = "sin_app"
    }

    func modulo(_ id: String) -> ModuloAjustes { modulos[id] ?? ModuloAjustes() }
}

extension MascotaAjustes {
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Claves.self)
        try c.encode(tipo, forKey: .tipo)
        try c.encode(color, forKey: .color)
        try c.encode(extra, forKey: .extra)
        try c.encode(rubor, forKey: .rubor)
        try c.encode(paseo, forKey: .paseo)
        try c.encode(semilla, forKey: .semilla)
        let numeros: [(Claves, Double)] = [(.grumos, grumos), (.pera, pera), (.cola, cola), (.flecos, flecos), (.fleco, fleco),
                                           (.ancho, ancho), (.alto, alto), (.ojoI, ojoI), (.ojoD, ojoD), (.sep, sep), (.ojosY, ojosY)]
        for (k, v) in numeros { try c.encode(v, forKey: k) }
    }
}

/// Lee y guarda /api/ajustes para la parte de Ajustes que antes solo estaba en la web (nombre, sonidos, secciones,
/// límites del móvil y mascota). Cada cambio se manda enseguida (con una pausa corta, para los deslizadores) y, sin
/// red, se queda en la cola de Local hasta que vuelva.
@MainActor @Observable
final class ModeloAjustes {
    static let shared = ModeloAjustes()

    private(set) var ajustes: AjustesTom?
    private(set) var cargando = false
    /// Si lo que se ve es la copia de sin conexión.
    private(set) var copia: Date?
    private(set) var error: String?
    private(set) var estado: Estado = .reposo
    /// Las apps que el atajo de Pantalla ha visto esta semana (para ofrecer poner límite a las que aún no tienen).
    private(set) var appsVistas: [String] = []

    enum Estado: Equatable {
        case reposo, guardando, guardado, encolado, fallo(String)
    }

    private var envio: Task<Void, Never>?
    private var cargado = false

    init() {
        if let r = Local.lee(Local.clave("GET", "/api/ajustes")), let a = try? JSONDecoder().decode(AjustesTom.self, from: r.cuerpo) {
            ajustes = a
        }
    }

    func carga(forzar: Bool = false) async {
        guard !cargando, forzar || !cargado || ajustes == nil else { return }
        cargando = true
        defer { cargando = false }
        do {
            let (crudo, fecha) = try await API.leeOCopia("/api/ajustes")
            // si hay un envío por hacer, lo del servidor es más viejo que lo que se ve
            if envio == nil { ajustes = try JSONDecoder().decode(AjustesTom.self, from: crudo) }
            copia = fecha
            error = nil
            cargado = true
        } catch {
            self.error = ajustes == nil ? "No he podido cargar tus ajustes: \(error.localizedDescription)" : nil
        }
        if let r = try? await API.leeOCopia("/api/pantalla"),
           let o = (try? JSONSerialization.jsonObject(with: r.datos)) as? [String: Any],
           let semana = o["semana"] as? [String: Any], let apps = semana["apps"] as? [[String: Any]] {
            appsVistas = apps.compactMap { $0["app"] as? String }
        }
    }

    /// Cambia algo y lo manda al servidor (con 0,6 s de pausa por si siguen tocando).
    func cambia(_ f: (inout AjustesTom) -> Void) {
        guard var a = ajustes else { return }
        f(&a)
        guard a != ajustes else { return }
        withAnimation(Tema.Muelle.pantalla) { ajustes = a }
        estado = .guardando
        envio?.cancel()
        envio = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            await manda()
        }
    }

    private func manda() async {
        guard let a = ajustes, let datos = try? JSONEncoder().encode(a),
              let json = (try? JSONSerialization.jsonObject(with: datos)) as? [String: Any] else { return }
        defer { envio = nil }
        do {
            if let respuesta = try await API.escribeOEncola("/api/ajustes", json: json) {
                guardaCopia(respuesta, local: false)
                estado = .guardado
            } else {
                guardaCopia(datos, local: true)
                estado = .encolado
            }
        } catch {
            estado = .fallo(error.localizedDescription)
        }
    }

    /// La copia de GET /api/ajustes con lo nuevo encima (lo que no es mío, como la apariencia, se queda como estaba).
    private func guardaCopia(_ nuevo: Data, local: Bool) {
        let clave = Local.clave("GET", "/api/ajustes")
        var base = (Local.lee(clave).flatMap { try? JSONSerialization.jsonObject(with: $0.cuerpo) as? [String: Any] }) ?? [:]
        if let encima = (try? JSONSerialization.jsonObject(with: nuevo)) as? [String: Any] {
            base.merge(encima) { _, n in n }
        }
        guard let cuerpo = try? JSONSerialization.data(withJSONObject: base) else { return }
        Local.guarda(clave, cuerpo: cuerpo, tipo: "application/json", version: nil, fecha: Date(), local: local, forzar: true)
    }
}
