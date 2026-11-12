import Foundation
import SwiftUI
import Observation

private extension KeyedDecodingContainer {
    /// Una clave que falta o viene rara no tumba la pantalla entera: se queda el valor por defecto.
    func v<T: Decodable>(_ clave: Key, _ por: T) -> T { (try? decodeIfPresent(T.self, forKey: clave)) ?? por }
}

/// Lo que devuelve GET /api/comida/estado (el proxy de todo). Solo lo del menú: recetas con sus ingredientes y macros,
/// el menú por días y el objetivo diario. La lista de la compra y las cuentas no se leen ni se enseñan (Yago, 12/11).
struct EstadoComida: Decodable {
    var recetas: [Receta] = []
    var ingredientes: [Ingrediente] = []
    var menu: [String: [String: String]] = [:]
    var objetivo: Objetivo?

    enum CodingKeys: String, CodingKey { case recetas, ingredientes, menu, objetivo }

    struct Receta: Decodable, Identifiable, Hashable {
        var id = ""
        var n = ""
        var tipo = ""
        var kcal = 0.0
        var prot = 0.0
        var pasos: [String] = []
        var ing: [Linea] = []
        var nut: Nutricion?

        enum CodingKeys: String, CodingKey { case id, n, tipo, kcal, prot, pasos, ing, nut }

        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            id = c.v(.id, ""); n = c.v(.n, ""); tipo = c.v(.tipo, ""); kcal = c.v(.kcal, 0); prot = c.v(.prot, 0)
            pasos = c.v(.pasos, []); ing = c.v(.ing, [])
            nut = try? c.decodeIfPresent(Nutricion.self, forKey: .nut)
        }

        /// kcal y proteína salen de sumar los ingredientes (calculada) o son la estimación de Claude (la web pone «~»).
        var calculada: Bool { nut?.calculada ?? false }
        var hc: Double? { calculada ? nut?.hc : nil }
        var grasa: Double? { calculada ? nut?.grasa : nil }
    }

    struct Linea: Decodable, Hashable {
        var i = ""
        var c = 0.0
        var v = ""

        enum CodingKeys: String, CodingKey { case i, c, v }

        init(from d: Decoder) throws {
            let k = try d.container(keyedBy: CodingKeys.self)
            i = k.v(.i, ""); c = k.v(.c, 0); v = k.v(.v, "")
        }
    }

    struct Nutricion: Decodable, Hashable {
        var calculada = false
        var hc: Double?
        var grasa: Double?

        enum CodingKeys: String, CodingKey { case calculada, hc, grasa }

        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            calculada = c.v(.calculada, false)
            hc = try? c.decodeIfPresent(Double.self, forKey: .hc)
            grasa = try? c.decodeIfPresent(Double.self, forKey: .grasa)
        }
    }

    struct Ingrediente: Decodable, Hashable {
        var id = ""
        var n = ""
        var unidad = "kg"
        var vn = ""
        var variantes: [Variante] = []

        enum CodingKeys: String, CodingKey { case id, n, unidad, vn, variantes }

        struct Variante: Decodable, Hashable {
            var id = ""
            var n = ""

            enum CodingKeys: String, CodingKey { case id, n }

            init(from d: Decoder) throws {
                let c = try d.container(keyedBy: CodingKeys.self)
                id = c.v(.id, ""); n = c.v(.n, "")
            }
        }

        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            id = c.v(.id, ""); n = c.v(.n, ""); unidad = c.v(.unidad, "kg"); vn = c.v(.vn, "")
            variantes = c.v(.variantes, [])
        }
    }

    struct Objetivo: Decodable, Hashable {
        var kcal = 0.0
        var proteina = 0.0

        enum CodingKeys: String, CodingKey { case kcal, proteina }

        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            kcal = c.v(.kcal, 0); proteina = c.v(.proteina, 0)
        }
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        recetas = c.v(.recetas, []); ingredientes = c.v(.ingredientes, []); menu = c.v(.menu, [:])
        objetivo = try? c.decodeIfPresent(Objetivo.self, forKey: .objetivo)
    }

    func receta(_ id: String) -> Receta? { recetas.first { $0.id == id } }
    func ingrediente(_ id: String) -> Ingrediente? { ingredientes.first { $0.id == id } }

    /// «50 g», «3 ud», «1,5 kg»: las cantidades llegan en g, ml o unidades según el ingrediente.
    func cantidad(_ l: Linea) -> String {
        let unidad = ingrediente(l.i)?.unidad ?? "kg"
        func num(_ x: Double, _ dec: Int) -> String {
            var t = String(format: "%.\(dec)f", x).replacingOccurrences(of: ".", with: ",")
            if t.contains(",") {
                while t.hasSuffix("0") { t.removeLast() }
                if t.hasSuffix(",") { t.removeLast() }
            }
            return t
        }
        if unidad == "ud" { return "\(num(l.c, 1)) ud" }
        if l.c < 1000 { return "\(num(l.c, 0)) \(unidad == "l" ? "ml" : "g")" }
        return "\(num(l.c / 1000, 2)) \(unidad == "l" ? "l" : "kg")"
    }

    /// «Avena», o «Lentejas (cocidas)» si la receta usa otra forma del ingrediente.
    func nombre(_ l: Linea) -> String {
        guard let ing = ingrediente(l.i) else { return l.i }
        if !l.v.isEmpty, let v = ing.variantes.first(where: { $0.id == l.v }) { return "\(ing.n) (\(v.n))" }
        return ing.n
    }
}

/// El menú de la semana en nativo. Lee /api/comida/estado (sin red, la copia de Local) y puede regenerarlo con
/// POST /api/comida/menu (Claude tarda minutos: Cloudflare corta a los ~100 s, así que si la respuesta no llega se
/// sigue mirando el estado hasta que el menú cambie).
@MainActor @Observable
final class DatosComida {
    static let shared = DatosComida()

    private(set) var estado: EstadoComida?
    /// La fecha de la copia si lo que se ve no viene fresco del servidor (sin red).
    private(set) var copia: Date?
    private(set) var error: String?
    private(set) var cargando = false
    private(set) var generando = false
    /// Lo que sale bajo el botón de generar (cómo va, o qué falló).
    private(set) var mensaje: String?
    private(set) var mensajeEsError = false

    private let ruta = "/api/comida/estado"

    init() {
        if let r = Local.lee(Local.clave("GET", ruta)), let e = try? JSONDecoder().decode(EstadoComida.self, from: r.cuerpo) {
            estado = e
            copia = r.fecha
        }
    }

    /// Los 7 días desde hoy, como el menú de la web.
    var dias: [String] {
        (0..<7).map { Self.dia(desplazado: $0) }
    }

    static func dia(desplazado n: Int) -> String {
        Fecha.dia(Calendar.current.date(byAdding: .day, value: n, to: Date()) ?? Date())
    }

    func carga() async {
        guard !cargando else { return }
        cargando = true
        defer { cargando = false }
        do {
            let (crudo, fecha) = try await API.leeOCopia(ruta)
            let nuevo = try JSONDecoder().decode(EstadoComida.self, from: crudo)
            withAnimation(Tema.Muelle.pantalla) { estado = nuevo }
            copia = fecha
            error = nil
        } catch {
            if estado == nil {
                self.error = (error as? APIError)?.mensaje ?? "No entiendo lo que devuelve el servidor de comida."
            }
        }
    }

    // MARK: regenerar

    /// «Generar menú» con una instrucción opcional. Devuelve cuando el menú ya es otro (o falla).
    func genera(instruccion: String) async {
        guard !generando else { return }
        generando = true
        mensajeEsError = false
        mensaje = "Claude está montando el menú. Tarda unos minutos: puedes seguir usando la app."
        defer { generando = false }
        let antes = huella(estado)
        do {
            try await manda(instruccion)
            await carga()
            mensaje = "Menú nuevo listo."
        } catch let e as APIError where e.sinRed || e.mensaje.hasPrefix("Ya está") {
            // la respuesta se perdió (Cloudflare corta a los ~100 s) pero el servidor sigue: se espera a que cambie
            if await espera(cambioDesde: antes) {
                mensaje = "Menú nuevo listo."
            } else {
                mensajeEsError = true
                mensaje = "No he visto que el menú cambiara. Tira para recargar dentro de un rato, o vuelve a pulsar Generar."
            }
        } catch {
            mensajeEsError = true
            mensaje = (error as? APIError)?.mensaje ?? error.localizedDescription
        }
    }

    private func huella(_ e: EstadoComida?) -> String {
        guard let e else { return "" }
        return e.menu.keys.sorted().map { d in
            d + ":" + (e.menu[d] ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        }.joined(separator: "|")
    }

    /// Cada 10 s, hasta 12 minutos, mira si el menú es otro.
    private func espera(cambioDesde antes: String) async -> Bool {
        for _ in 0..<72 {
            try? await Task.sleep(for: .seconds(10))
            if Task.isCancelled { return false }
            if let crudo = try? await API.datos(ruta),
               let nuevo = try? JSONDecoder().decode(EstadoComida.self, from: crudo), huella(nuevo) != antes {
                estado = nuevo
                copia = nil
                return true
            }
        }
        return false
    }

    /// POST /api/comida/menu con un plazo largo (el de API.datos es de 20 s).
    private func manda(_ instruccion: String) async throws {
        var json: [String: Any] = [:]
        let limpia = instruccion.trimmingCharacters(in: .whitespacesAndNewlines)
        if !limpia.isEmpty { json["instruccion"] = String(limpia.prefix(500)) }
        var p = try API.peticion("/api/comida/menu", metodo: "POST", json: json)
        p.timeoutInterval = 900
        let resultado: (Data, URLResponse)
        do {
            resultado = try await URLSession.shared.data(for: p)
        } catch {
            throw APIError(mensaje: "Sin conexión con el servidor: \(error.localizedDescription)", sinRed: true)
        }
        guard let http = resultado.1 as? HTTPURLResponse else { throw APIError(mensaje: "Respuesta rara del servidor") }
        if (200..<300).contains(http.statusCode) { return }
        let tipo = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        if API.esCaida(http.statusCode, tipo: tipo) {
            throw APIError(mensaje: "El servidor tarda en contestar", sinRed: true)
        }
        let objeto = try? JSONSerialization.jsonObject(with: resultado.0) as? [String: Any]
        let detalle = (objeto?["detail"] as? String) ?? "Error \(http.statusCode) del servidor"
        throw APIError(mensaje: detalle)
    }
}
