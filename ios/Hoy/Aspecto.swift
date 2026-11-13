import SwiftUI
import UIKit
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
        /// El tema ya resuelto de la última vez: para pintar el primer fotograma sin decodificar el catálogo.
        static let instantanea = "apariencia.instantanea"
    }

    private(set) var catalogo: Catalogo?
    private(set) var eleccion = Eleccion()
    private(set) var disposicion: [String: Bloques] = [:]
    /// El tema ya construido (colores resueltos una vez, no en cada acceso), con el filtro del modo noche si toca.
    private(set) var tema = Tema()
    /// Modo noche ahora mismo (Noche.swift): oscuro y con el filtro cálido.
    private(set) var noche = false
    /// Lo que se pintó la última vez, mientras el catálogo aún no está (el primer momento tras arrancar).
    private(set) var instantanea: TemaGuardado?

    /// El tema sin el filtro de noche.
    @ObservationIgnored private var base = Tema()
    @ObservationIgnored private var envio: Task<Void, Never>?

    init() {
        let d = Almacen.defaults
        let elegida = d.data(forKey: Clave.eleccion).flatMap { try? JSONDecoder().decode(Eleccion.self, from: $0) }
        disposicion = d.data(forKey: Clave.disposicion)
            .flatMap { try? JSONDecoder().decode([String: Bloques].self, from: $0) } ?? [:]
        noche = Noche.activa()
        if let elegida, let inst = d.data(forKey: Clave.instantanea).flatMap({ try? JSONDecoder().decode(TemaGuardado.self, from: $0) }),
           inst.eleccion == elegida {
            // arranque rápido: el tema de la última vez tal cual, y el catálogo (60 KB de JSON) después de pintar
            eleccion = elegida
            instantanea = inst
            base = inst.tema
            tema = conNoche(base)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                self?.cargaCatalogo()
            }
        } else {
            catalogo = Self.leeCatalogo()
            if let elegida { eleccion = elegida } else if let def = catalogo?.defecto { eleccion = def }
            base = construye()
            tema = conNoche(base)
            guardaInstantanea()
        }
        vigilaNoche()
    }

    /// El guardado si ya es v2 (con temas); si no, la copia del bundle.
    private static func leeCatalogo() -> Catalogo? {
        let guardado = Almacen.defaults.data(forKey: Clave.catalogo).flatMap { try? JSONDecoder().decode(Catalogo.self, from: $0) }
        return guardado?.temas != nil ? guardado
            : Bundle.main.url(forResource: "apariencia", withExtension: "json")
                .flatMap { try? Data(contentsOf: $0) }
                .flatMap { try? JSONDecoder().decode(Catalogo.self, from: $0) } ?? guardado
    }

    /// Tras el arranque rápido: el catálogo de verdad. Si el tema sale igual que el guardado, no se repinta nada.
    private func cargaCatalogo() {
        guard catalogo == nil else { return }
        catalogo = Self.leeCatalogo()
        let antes = instantanea
        base = construye()
        if !TemaGuardado(base, eleccion: eleccion, decoracion: nil, sonido: nil).mismoAspecto(antes) {
            withAnimation(.easeInOut(duration: 0.35)) { tema = conNoche(base) }
        }
        instantanea = nil
        guardaInstantanea()
    }

    // MARK: lo que se lee

    var esquema: ColorScheme? {
        if noche { return .dark }
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
            base = construye()
            tema = conNoche(base)
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
                self.instantanea = nil
                self.base = self.construye()
                self.tema = self.conNoche(self.base)
                self.guardaInstantanea()
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
            base = construye()
            tema = conNoche(base)
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
        guardaInstantanea()
        guardaParaWidget()
    }

    /// El tema resuelto, para el próximo arranque (solo con el catálogo ya cargado: si no, lo de ahora es lo guardado).
    private func guardaInstantanea() {
        guard catalogo != nil else { return }
        let t = TemaGuardado(base, eleccion: eleccion, decoracion: decoracion, sonido: juegoSonidos)
        if let x = try? JSONEncoder().encode(t) { Almacen.defaults.set(x, forKey: Clave.instantanea) }
    }

    // MARK: modo noche

    private func conNoche(_ t: Tema) -> Tema {
        guard noche else { return t }
        var x = t
        x.paleta = t.paleta.nocturna()
        return x
    }

    /// Mira cada medio minuto y al volver a la app si entra o sale la noche.
    private func vigilaNoche() {
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil,
                                               queue: .main) { _ in
            Task { @MainActor in Aspecto.shared.revisaNoche() }
        }
        Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.revisaNoche()
            }
        }
    }

    @MainActor
    func revisaNoche() {
        let ahora = Noche.activa()
        guard ahora != noche else { return }
        // un fundido de un segundo: los colores (y el claro/oscuro del sistema) pasan sin saltos
        TransicionFundido.cambia {
            self.noche = ahora
            self.tema = self.conNoche(self.base)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Configurar → Apariencia → Modo noche.
    @MainActor
    func ponNoche(_ a: AjustesNoche) {
        guard a != Noche.ajustes else { return }
        Noche.ajustes = a
        revisaNoche()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: construir el tema

    private func construye() -> Tema {
        // tras el arranque rápido aún puede faltar el catálogo: sin él saldrían la letra y las esquinas por defecto
        if catalogo == nil {
            catalogo = Self.leeCatalogo()
            instantanea = nil
        }
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

    /// La familia de iOS de una letra del catálogo (nil = SF Pro, o si no se ha podido registrar). La registra la
    /// primera vez (Letras): al arrancar, solo las del tema elegido.
    func familia(_ id: String) -> String? {
        guard let f = catalogo?.fuente(id), let n = f.familia_ios, !n.isEmpty, Letras.lista(n) else { return nil }
        return n
    }

    /// El widget y la Live Activity no tienen el catálogo: se les dejan los colores ya elegidos.
    private func guardaParaWidget() {
        let g = Oklch.genera(base: eleccion.base, acento: eleccion.acento)
        ColoresGuardados.guarda(claro: g.claro.tokens, oscuro: g.oscuro.tokens)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// El tema resuelto tal como se pintó (colores, letras, esquinas, fondo, decoración y sonidos), para el próximo arranque.
struct TemaGuardado: Codable, Equatable {
    var eleccion: Eleccion
    /// token → [claro, oscuro]
    var colores: [String: [String]]
    var texto: String?
    var titulo: String?
    var cifras: String?
    var radios: [Double]
    var fondo: Double
    var decoracion: String?
    var sonido: String?

    init(_ t: Tema, eleccion: Eleccion, decoracion: String?, sonido: String?) {
        self.eleccion = eleccion
        var c: [String: [String]] = [:]
        for (nombre, campo) in Paleta.campos { c[nombre] = [t.paleta[keyPath: campo].claro, t.paleta[keyPath: campo].oscuro] }
        colores = c
        texto = t.fuentes.texto
        titulo = t.fuentes.titulo
        cifras = t.fuentes.cifras
        radios = [t.radios.carta, t.radios.boton, t.radios.celda]
        fondo = t.fondo
        self.decoracion = decoracion
        self.sonido = sonido
    }

    var tema: Tema {
        var t = Tema()
        for (nombre, campo) in Paleta.campos {
            if let par = colores[nombre], par.count == 2 { t.paleta[keyPath: campo] = .init(claro: par[0], oscuro: par[1]) }
        }
        t.fuentes = Fuentes(texto: texto, titulo: titulo, cifras: cifras)
        if radios.count == 3 { t.radios = Radios(carta: radios[0], boton: radios[1], celda: radios[2]) }
        t.fondo = fondo
        return t
    }

    /// Lo mismo de ver (sin mirar decoración ni sonidos).
    func mismoAspecto(_ otro: TemaGuardado?) -> Bool {
        guard let otro else { return false }
        return colores == otro.colores && texto == otro.texto && titulo == otro.titulo && cifras == otro.cifras
            && radios == otro.radios && fondo == otro.fondo
    }
}

extension Paleta {
    /// Todos los tokens con su nombre (el de calma.css), para guardarlos y para el filtro de noche.
    static let campos: [(String, WritableKeyPath<Paleta, Paleta.Token>)] = [
        ("fondo", \.fondo), ("carta", \.carta), ("carta_luz", \.cartaLuz), ("carta2", \.carta2), ("texto", \.texto),
        ("suave", \.suave), ("tenue", \.tenue), ("linea", \.linea), ("acento", \.acento),
        ("acento_texto", \.acentoTexto), ("acento_suave", \.acentoSuave), ("peligro", \.peligro), ("aviso", \.aviso),
        ("dock", \.dock), ("dock_texto", \.dockTexto), ("gota", \.gota), ("gota_texto", \.gotaTexto), ("ascii", \.ascii),
    ]

    /// La paleta del modo noche: el lado oscuro de cada token pasado por el filtro cálido (Noche.filtra), igual en
    /// claro y en oscuro (de noche siempre se pinta oscuro, pero así no salta nada mientras cambia el sistema).
    func nocturna() -> Paleta {
        var p = self
        for (nombre, campo) in Self.campos {
            let o = Noche.filtra(self[keyPath: campo].oscuro, acento: Noche.tokensAcento.contains(nombre))
            p[keyPath: campo] = .init(claro: o, oscuro: o)
        }
        return p
    }
}
