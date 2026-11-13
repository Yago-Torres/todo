import Foundation
import SwiftUI
import Observation

/// La lista de Comida en el iPhone. Lee /api/comida/cesta (sin red, la copia de Local con los cambios de la cola
/// encima) y cada cambio sale como una operación suelta a POST /api/comida/cesta: si no hay red se queda en la cola de
/// Local y Sincro la manda al volver. El catálogo de alimentos (/api/comida/alimentos) también se guarda, para buscar
/// y calcular macros sin red.
@MainActor @Observable
final class DatosLista {
    static let shared = DatosLista()

    private(set) var cesta = CestaComida()
    private(set) var catalogo: [Alimento] = []
    private(set) var cargado = false
    private(set) var copia: Date?
    private(set) var error: String?
    var aviso: AvisoTom?

    /// «Hazme una receta»: cómo va y lo que salió.
    private(set) var cocinando = false
    private(set) var errorReceta: String?
    var recetaNueva: RecetaLista?

    /// Estimando un alimento nuevo con Claude (el nombre).
    private(set) var estimando: String?

    static let ruta = "/api/comida/cesta"
    static let rutaCatalogo = "/api/comida/alimentos"
    private var enVuelo = 0

    init() {
        if let r = Local.lee(Local.clave("GET", Self.ruta)), let c = try? JSONDecoder().decode(CestaComida.self, from: r.cuerpo) {
            cesta = c
            cargado = true
        }
        if let r = Local.lee(Local.clave("GET", Self.rutaCatalogo)),
           let c = try? JSONDecoder().decode(RespuestaCatalogo.self, from: r.cuerpo) {
            catalogo = c.alimentos
        }
    }

    private struct RespuestaCatalogo: Decodable { var alimentos: [Alimento] }

    // MARK: lo que se ve

    /// Primero lo pendiente, lo marcado al final; dentro de cada grupo, por cuándo se añadió.
    var items: [ItemLista] {
        cesta.items.sorted { ($0.hecho ? 1 : 0, $0.t0) < ($1.hecho ? 1 : 0, $1.t0) }
    }

    /// La suma de lo que no está marcado.
    var total: Macros { cesta.items.filter { !$0.hecho }.compactMap(\.macros).reduce(Macros(), +) }

    var sinDatos: Int { cesta.items.filter { !$0.hecho && $0.macros == nil }.count }

    func alimento(_ id: String) -> Alimento? { id.isEmpty ? nil : catalogo.first { $0.id == id } }

    // MARK: cargar

    func carga() async {
        async let cat: Void = cargaCatalogo()
        do {
            let (crudo, fecha) = try await API.leeOCopia(Self.ruta)
            var c = try JSONDecoder().decode(CestaComida.self, from: crudo)
            // lo que sigue en la cola todavía no está en el servidor: se rehace encima para no verlo desaparecer
            let pendientes = Self.opsPendientes()
            for op in pendientes { op.aplica(&c) }
            if enVuelo == 0 {
                withAnimation(Tema.Muelle.pantalla) { cesta = c }
                completaDatos()
                if !pendientes.isEmpty { guardaCopia() }
            }
            copia = fecha
            error = nil
            cargado = true
        } catch {
            if !cargado { self.error = (error as? APIError)?.mensaje ?? "No entiendo lo que devuelve el servidor de comida." }
        }
        await cat
    }

    private func cargaCatalogo() async {
        guard let (crudo, _) = try? await API.leeOCopia(Self.rutaCatalogo),
              let c = try? JSONDecoder().decode(RespuestaCatalogo.self, from: crudo) else { return }
        catalogo = c.alimentos
        completaDatos()
    }

    /// Las líneas añadidas sin red no traen los datos del servidor: se sacan del catálogo.
    private func completaDatos() {
        for k in cesta.items.indices where cesta.items[k].n100 == nil {
            if let a = alimento(cesta.items[k].a) {
                cesta.items[k].n100 = a.n100
                cesta.items[k].g_ud = a.g_ud
            }
        }
    }

    private static func opsPendientes() -> [OpLista] {
        Local.cambios()
            .filter { $0.rutaSinQuery == ruta && $0.estado == .pendiente }
            .flatMap { c -> [OpLista] in
                guard let cuerpo = c.cuerpo,
                      let o = (try? JSONSerialization.jsonObject(with: cuerpo)) as? [String: Any],
                      let ops = o["ops"] as? [[String: Any]] else { return [] }
                return ops.compactMap(OpLista.desde)
            }
    }

    private func guardaCopia() {
        guard let d = try? JSONEncoder().encode(cesta) else { return }
        Local.guarda(Local.clave("GET", Self.ruta), cuerpo: d, tipo: "application/json", version: nil, fecha: Date(),
                     local: true, forzar: true)
    }

    // MARK: cambiar

    /// Aplica aquí al momento y lo manda (o lo deja en la cola).
    private func manda(_ ops: [OpLista], animado: Bool = true) {
        var c = cesta
        for op in ops { op.aplica(&c) }
        if animado { withAnimation(Tema.Muelle.pantalla) { cesta = c } } else { cesta = c }
        guardaCopia()
        enVuelo += 1
        Task {
            defer { enVuelo -= 1 }
            do {
                let json: [String: Any] = ["ops": ops.map(\.json)]
                guard let crudo = try await API.escribeOEncola(Self.ruta, json: json) else {
                    copia = copia ?? Date()
                    return
                }
                // lo del servidor manda solo si no queda nada más por el camino (si no, parpadearía lo de después)
                if enVuelo == 1, Self.opsPendientes().isEmpty,
                   let nueva = try? JSONDecoder().decode(CestaComida.self, from: crudo) {
                    cesta = nueva
                    completaDatos()
                    Local.guarda(Local.clave("GET", Self.ruta), cuerpo: crudo, tipo: "application/json", version: nil,
                                 fecha: Date(), forzar: true)
                    copia = nil
                }
            } catch {
                Haptica.shared.toca(.error)
                aviso = AvisoTom(texto: "No se ha guardado: \((error as? APIError)?.mensaje ?? error.localizedDescription)",
                                 error: true)
                await carga()
            }
        }
    }

    private var ahora: Double { Date().timeIntervalSince1970 * 1000 }

    /// Añade lo escrito: con alimento del catálogo (y sus macros) o sin datos.
    func anade(_ alimento: Alimento?, nombre: String, cantidad: Double?, unidad: UnidadLista?) {
        let n = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        // si ya está en la lista, se suma la cantidad en vez de repetir la línea
        if let a = alimento, let k = cesta.items.firstIndex(where: { $0.a == a.id && !$0.hecho }),
           cesta.items[k].u == (unidad ?? cesta.items[k].u) {
            var i = cesta.items[k]
            i.c += cantidad ?? i.u.porDefecto
            i.t = ahora
            Haptica.shared.toca(.marcar)
            manda([.pon(i)])
            aviso = AvisoTom(texto: "\(i.n): ahora \(i.cantidadTexto)")
            return
        }
        let i = ItemLista(alimento: alimento, nombre: alimento?.n ?? n, cantidad: cantidad, unidad: unidad)
        Haptica.shared.toca(.marcar)
        manda([.pon(i)])
    }

    func cambia(_ item: ItemLista) {
        var i = item
        i.t = ahora
        manda([.pon(i)], animado: false)
    }

    func marca(_ item: ItemLista) {
        var i = item
        i.hecho.toggle()
        i.t = ahora
        Haptica.shared.toca(i.hecho ? .marcar : .desmarcar)
        manda([.pon(i)])
    }

    func quita(_ item: ItemLista) {
        Haptica.shared.toca(.desmarcar)
        manda([.quita(item.id)])
        aviso = AvisoTom(texto: "Quitado: \(item.n)") { [weak self] in
            guard let self else { return }
            var i = item
            i.t = self.ahora
            self.manda([.pon(i)])
        }
    }

    func quitaMarcados() {
        let hechos = cesta.items.filter(\.hecho)
        guard !hechos.isEmpty else { return }
        Haptica.shared.toca(.desmarcar)
        manda(hechos.map { .quita($0.id) })
        aviso = AvisoTom(texto: hechos.count == 1 ? "Quitado 1 marcado" : "Quitados \(hechos.count) marcados") { [weak self] in
            guard let self else { return }
            let t = self.ahora
            self.manda(hechos.map { h -> OpLista in
                var i = h
                i.t = t
                return OpLista.pon(i)
            })
        }
    }

    func esFavorita(_ r: RecetaLista) -> Bool { cesta.favoritas.contains { $0.id == r.id } }

    func alternaFavorita(_ r: RecetaLista) {
        let era = esFavorita(r)
        Haptica.shared.toca(era ? .desmarcar : .record)
        manda([era ? .desfav(r.id) : .fav(r)])
    }

    // MARK: alimentos nuevos

    /// Pide a Claude los macros de algo que no está en el catálogo, lo guarda y lo añade a la lista.
    func estimaYAnade(_ nombre: String, cantidad: Double?, unidad: UnidadLista?) async {
        let n = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, estimando == nil else { return }
        estimando = n
        defer { estimando = nil }
        do {
            let crudo = try await API.datos("/api/comida/alimentos/estima", metodo: "POST", json: ["n": n])
            let a = try JSONDecoder().decode(Alimento.self, from: crudo)
            if !catalogo.contains(where: { $0.id == a.id }) { catalogo.append(a) }
            anade(a, nombre: a.n, cantidad: cantidad, unidad: unidad)
            aviso = AvisoTom(texto: "\(a.n): \(Formato.entero(a.n100.kcal)) kcal por 100 g (estimado por Claude)")
            Task { await cargaCatalogo() }
        } catch let e as APIError where e.sinRed {
            // sin red se apunta igual, sin datos: se puede estimar más tarde desde la propia línea
            anade(nil, nombre: n, cantidad: cantidad, unidad: unidad)
            aviso = AvisoTom(texto: "Sin conexión: apuntado sin macros. Tócalo luego para calcularlos.")
        } catch {
            Haptica.shared.toca(.error)
            aviso = AvisoTom(texto: (error as? APIError)?.mensaje ?? error.localizedDescription, error: true)
        }
    }

    /// Para una línea sin datos: estima su alimento y la engancha.
    func estima(_ item: ItemLista) async {
        guard estimando == nil else { return }
        estimando = item.n
        defer { estimando = nil }
        do {
            let crudo = try await API.datos("/api/comida/alimentos/estima", metodo: "POST", json: ["n": item.n])
            let a = try JSONDecoder().decode(Alimento.self, from: crudo)
            if !catalogo.contains(where: { $0.id == a.id }) { catalogo.append(a) }
            engancha(item, a)
        } catch {
            Haptica.shared.toca(.error)
            aviso = AvisoTom(texto: (error as? APIError)?.mensaje ?? error.localizedDescription, error: true)
        }
    }

    /// Le pone a una línea los datos de un alimento del catálogo (y su unidad si la que tenía no le vale).
    func engancha(_ item: ItemLista, _ a: Alimento) {
        var i = item
        i.a = a.id
        i.n100 = a.n100
        i.g_ud = a.g_ud
        if i.u == .ud && a.g_ud == nil { i.u = a.u; i.c = a.u.porDefecto }
        i.t = ahora
        Haptica.shared.toca(.marcar)
        manda([.pon(i)])
    }

    // MARK: recetas

    /// POST /api/comida/receta. Claude tarda unos 20 s; si la respuesta se pierde, se recoge la última de la cesta.
    func hazReceta(con ids: [String], instruccion: String, raciones: Int) async -> Bool {
        guard !cocinando, !ids.isEmpty else { return false }
        cocinando = true
        errorReceta = nil
        defer { cocinando = false }
        let desde = ahora
        var json: [String: Any] = ["ids": ids, "raciones": raciones]
        let limpia = instruccion.trimmingCharacters(in: .whitespacesAndNewlines)
        if !limpia.isEmpty { json["instruccion"] = String(limpia.prefix(200)) }
        do {
            let crudo = try await pideLargo("/api/comida/receta", json: json)
            let r = try JSONDecoder().decode(RecetaLista.self, from: crudo)
            cesta.ultima = r
            recetaNueva = r
            Haptica.shared.toca(.record)
            return true
        } catch let e as APIError where e.sinRed {
            if !Red.shared.hayRed {
                errorReceta = "Sin conexión: para hacer una receta hace falta internet (la piensa Claude en el servidor)."
                return false
            }
            // Cloudflare corta a los 100 s pero el servidor sigue: se espera a que aparezca la receta nueva
            for _ in 0..<12 {
                try? await Task.sleep(for: .seconds(10))
                if let crudo = try? await API.datos(Self.ruta),
                   let c = try? JSONDecoder().decode(CestaComida.self, from: crudo), let r = c.ultima, r.t >= desde {
                    cesta.ultima = r
                    recetaNueva = r
                    Haptica.shared.toca(.record)
                    return true
                }
            }
            errorReceta = "La receta no ha llegado. Vuelve a probar en un momento."
            return false
        } catch {
            Haptica.shared.toca(.error)
            errorReceta = (error as? APIError)?.mensaje ?? error.localizedDescription
            return false
        }
    }

    /// Como API.datos, con un plazo largo (el de API.datos es de 20 s).
    private func pideLargo(_ ruta: String, json: [String: Any]) async throws -> Data {
        var p = try API.peticion(ruta, metodo: "POST", json: json)
        p.timeoutInterval = 150
        let resultado: (Data, URLResponse)
        do {
            resultado = try await URLSession.shared.data(for: p)
        } catch {
            throw APIError(mensaje: "Sin conexión con el servidor: \(error.localizedDescription)", sinRed: true)
        }
        guard let http = resultado.1 as? HTTPURLResponse else { throw APIError(mensaje: "Respuesta rara del servidor") }
        if (200..<300).contains(http.statusCode) { return resultado.0 }
        let tipo = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        if API.esCaida(http.statusCode, tipo: tipo) { throw APIError(mensaje: "El servidor tarda en contestar", sinRed: true) }
        let objeto = try? JSONSerialization.jsonObject(with: resultado.0) as? [String: Any]
        throw APIError(mensaje: (objeto?["detail"] as? String) ?? "Error \(http.statusCode) del servidor")
    }
}
