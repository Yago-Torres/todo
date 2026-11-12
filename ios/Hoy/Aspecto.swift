import SwiftUI
import Observation
import WidgetKit

/// La apariencia y la disposición en vivo: de aquí sale `Tema.actual`. Arranca con lo último guardado en el app group
/// (o el catálogo del bundle), se sincroniza con el servidor al arrancar y al volver a primer plano, y manda cada
/// cambio (con un pequeño margen, y a la próxima si no hay red). Como es @Observable y las vistas leen `Tema.*` en su
/// body, cambiar algo repinta todas las pantallas nativas.
@Observable
final class Aspecto {
    static let shared = Aspecto()

    private enum Clave {
        static let catalogo = "apariencia.catalogo"
        static let eleccion = "apariencia.eleccion"
        static let disposicion = "apariencia.disposicion"
        static let pendiente = "apariencia.pendiente"
    }

    private(set) var catalogo: Catalogo?
    private(set) var eleccion = Eleccion()
    private(set) var disposicion: [String: Bloques] = [:]
    /// El tema ya construido (colores resueltos una vez, no en cada acceso).
    private(set) var tema = Tema()

    @ObservationIgnored private var envio: Task<Void, Never>?

    init() {
        let d = Almacen.defaults
        // el guardado si ya es v2 (con temas); si no, la copia del bundle
        let guardado = d.data(forKey: Clave.catalogo).flatMap { try? JSONDecoder().decode(Catalogo.self, from: $0) }
        catalogo = guardado?.temas != nil ? guardado
            : Bundle.main.url(forResource: "apariencia", withExtension: "json")
                .flatMap { try? Data(contentsOf: $0) }
                .flatMap { try? JSONDecoder().decode(Catalogo.self, from: $0) } ?? guardado
        if let e = d.data(forKey: Clave.eleccion).flatMap({ try? JSONDecoder().decode(Eleccion.self, from: $0) }) {
            eleccion = e
        } else if let def = catalogo?.defecto {
            eleccion = def
        }
        disposicion = d.data(forKey: Clave.disposicion)
            .flatMap { try? JSONDecoder().decode([String: Bloques].self, from: $0) } ?? [:]
        tema = construye()
    }

    // MARK: lo que se lee

    var esquema: ColorScheme? {
        switch eleccion.modo {
        case "claro": return .light
        case "oscuro": return .dark
        default: return nil
        }
    }

    func bloques(_ pantalla: String) -> Bloques { disposicion[pantalla] ?? Bloques() }

    // MARK: cambiar

    /// Tocar cualquier valor a mano deja el tema en «propio».
    func cambia(_ cambio: (inout Eleccion) -> Void) {
        var e = eleccion
        cambio(&e)
        guard e != eleccion else { return }
        e.tema = "propio"
        ponEleccion(e)
    }

    /// Elegir un tema copia sus siete valores (el modo, si el tema no trae uno, se queda como estaba).
    func eligeTema(_ t: Catalogo.TemaCat) {
        ponEleccion(Eleccion(tema: t, modo: t.modo ?? eleccion.modo))
    }

    private func ponEleccion(_ e: Eleccion) {
        guard e != eleccion else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            eleccion = e
            tema = construye()
        }
        guardaLocal()
        programaEnvio()
    }

    /// El tema por defecto del catálogo.
    func restablece() {
        if let cat = catalogo, let t = cat.tema(cat.defecto.tema) {
            ponEleccion(Eleccion(tema: t, modo: cat.defecto.modo))
        } else {
            ponEleccion(catalogo?.defecto ?? Eleccion())
        }
    }

    func ponBloques(_ pantalla: String, _ b: Bloques) {
        guard disposicion[pantalla] != b else { return }
        withAnimation(Tema.Muelle.pantalla) { disposicion[pantalla] = b }
        guardaLocal()
        programaEnvio()
    }

    // MARK: servidor

    /// Al arrancar y al volver a primer plano. Si hay cambios sin mandar, primero se mandan (no se pisan con lo viejo).
    func sincroniza() async {
        if let crudo = try? await API.datos("/apariencia.json"),
           let c = try? JSONDecoder().decode(Catalogo.self, from: crudo) {
            Almacen.defaults.set(crudo, forKey: Clave.catalogo)
            await MainActor.run {
                self.catalogo = c
                self.tema = self.construye()
            }
        }
        if Almacen.defaults.bool(forKey: Clave.pendiente) {
            await manda()
            return
        }
        guard let crudo = try? await API.datos("/api/apariencia") else { return }
        await MainActor.run { self.recibe(crudo) }
    }

    private func recibe(_ crudo: Data) {
        struct Respuesta: Decodable {
            var apariencia: Eleccion?
            var disposicion: [String: Bloques]?
        }
        guard let r = try? JSONDecoder().decode(Respuesta.self, from: crudo) else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            if let e = r.apariencia { eleccion = e }
            if let d = r.disposicion { disposicion = d }
            tema = construye()
        }
        guardaLocal()
    }

    private func programaEnvio() {
        Almacen.defaults.set(true, forKey: Clave.pendiente)
        envio?.cancel()
        envio = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await self?.manda()
        }
    }

    private func manda() async {
        guard let eJson = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(eleccion)),
              let dJson = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(disposicion)) else { return }
        do {
            try await API.datos("/api/apariencia", metodo: "POST", json: ["apariencia": eJson, "disposicion": dJson])
            Almacen.defaults.set(false, forKey: Clave.pendiente)
        } catch {
            // sin red: queda marcado y sale en la próxima sincronización
        }
    }

    private func guardaLocal() {
        let d = Almacen.defaults
        if let e = try? JSONEncoder().encode(eleccion) { d.set(e, forKey: Clave.eleccion) }
        if let x = try? JSONEncoder().encode(disposicion) { d.set(x, forKey: Clave.disposicion) }
        guardaParaWidget()
    }

    // MARK: construir el tema

    private func construye() -> Tema {
        var t = Tema()
        let def = catalogo?.defecto ?? Eleccion()
        let g = Oklch.genera(base: Oklch.esHex(eleccion.base) ? eleccion.base : def.base,
                             acento: Oklch.esHex(eleccion.acento) ? eleccion.acento : def.acento)
        var p = Paleta()
        let c = g.claro, o = g.oscuro
        p.fondo = .init(claro: c.fondo, oscuro: o.fondo)
        p.carta = .init(claro: c.carta, oscuro: o.carta)
        p.cartaLuz = .init(claro: c.cartaLuz, oscuro: o.cartaLuz)
        p.carta2 = .init(claro: c.carta2, oscuro: o.carta2)
        p.texto = .init(claro: c.texto, oscuro: o.texto)
        p.suave = .init(claro: c.suave, oscuro: o.suave)
        p.tenue = .init(claro: c.tenue, oscuro: o.tenue)
        p.linea = .init(claro: c.linea, oscuro: o.linea)
        p.dock = .init(claro: c.dock, oscuro: o.dock)
        p.dockTexto = .init(claro: c.dockTexto, oscuro: o.dockTexto)
        p.ascii = .init(claro: c.ascii, oscuro: o.ascii)
        p.acento = .init(claro: c.acento, oscuro: o.acento)
        p.acentoTexto = .init(claro: c.acentoTexto, oscuro: o.acentoTexto)
        p.acentoSuave = .init(claro: c.acentoSuave, oscuro: o.acentoSuave)
        p.gota = .init(claro: g.gota, oscuro: g.gota)
        p.gotaTexto = .init(claro: g.gotaTexto, oscuro: g.gotaTexto)
        if let f = catalogo?.fijos {
            p.peligro = .init(claro: f.claro.peligro, oscuro: f.oscuro.peligro)
            p.aviso = .init(claro: f.claro.aviso, oscuro: f.oscuro.aviso)
        }
        t.paleta = p
        t.fuentes = Fuentes(texto: familia(eleccion.fuente), titulo: familia(eleccion.titulos), cifras: familia(eleccion.fuente))
        if let e = catalogo?.esquinas.first(where: { $0.id == eleccion.esquinas }) {
            t.radios = Radios(carta: e.carta, boton: e.boton, celda: e.celda)
        }
        if let f = catalogo?.fondos.first(where: { $0.id == eleccion.fondo }) { t.fondo = f.intensidad }
        return t
    }

    /// La familia de iOS de una letra del catálogo (nil = SF Pro).
    func familia(_ id: String) -> String? {
        guard let f = catalogo?.fuente(id), let n = f.familia_ios, !n.isEmpty else { return nil }
        return n
    }

    /// El widget y la Live Activity no tienen el catálogo: se les dejan los colores ya elegidos.
    private func guardaParaWidget() {
        let g = Oklch.genera(base: eleccion.base, acento: eleccion.acento)
        ColoresGuardados.guarda(claro: g.claro.tokens, oscuro: g.oscuro.tokens)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
