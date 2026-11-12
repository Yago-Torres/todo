import SwiftUI

/// Cómo está la mascota (lo decide Hoy con los hábitos, la hora y los días sin venir, como `lee()` en mascota.js).
enum MascotaEstado: String, CaseIterable {
    case reposo, contento, feliz, animo, enfadado, dormido, ausente
}

/// La deformación de cada estado. Fantasma: a ancho, h alto, fl flecos. Flor: p pétalos, bi/bd brazos, pi/pd piernas.
/// ro: cuánto enrojece.
struct FormaMascota {
    var a = 1.0, h = 1.0, fl = 1.0, ro = 0.0
    var p = 1.0, bi = 0.0, bd = 0.0, pi = 0.0, pd = 0.0

    static func de(_ e: MascotaEstado, flor: Bool) -> FormaMascota {
        if flor {
            switch e {
            case .reposo: return FormaMascota()
            case .contento: return FormaMascota(p: 1.05, bi: 11, bd: -11)
            case .feliz: return FormaMascota(p: 1.1, bi: 30, bd: -30, pi: 12, pd: -8)
            case .animo: return FormaMascota(p: 0.98, bd: -34)
            case .enfadado: return FormaMascota(ro: 1, p: 1.06, bi: -24, bd: 24, pi: -6, pd: 6)
            case .dormido: return FormaMascota(p: 0.88, bi: -38, bd: 38, pi: 8, pd: -8)
            case .ausente: return FormaMascota(p: 0.8, bi: -52, bd: 52, pi: 4, pd: -4)
            }
        }
        switch e {
        case .reposo: return FormaMascota()
        case .contento: return FormaMascota(a: 1.06, h: 0.95, fl: 0.8)
        case .feliz: return FormaMascota(a: 1.1, h: 0.9, fl: 0.7)
        case .animo: return FormaMascota(a: 0.96, h: 1.05)
        case .enfadado: return FormaMascota(a: 1.12, h: 0.94, fl: 0.85, ro: 1)
        case .dormido: return FormaMascota(a: 1.14, h: 0.72, fl: 0.45)
        case .ausente: return FormaMascota(a: 0.82, h: 1.12, fl: 1.5)
        }
    }

    static func mezcla(_ x: FormaMascota, _ y: FormaMascota, _ k: Double) -> FormaMascota {
        func m(_ a: Double, _ b: Double) -> Double { a + (b - a) * k }
        return FormaMascota(a: m(x.a, y.a), h: m(x.h, y.h), fl: m(x.fl, y.fl), ro: m(x.ro, y.ro),
                            p: m(x.p, y.p), bi: m(x.bi, y.bi), bd: m(x.bd, y.bd), pi: m(x.pi, y.pi), pd: m(x.pd, y.pd))
    }
}

/// Lo que se puede animar con una pista de fotogramas clave.
enum PropMascota: Hashable {
    case x, y, giro, escalaX, escalaY      // todo el cuerpo (absolutas)
    case bi, bd, pi, pd, mano, petalos      // partes de la flor (se suman al estado; petalos multiplica)
    case ojosX, opacidad
}

/// Una pista: valores por los que pasa (el primero, el de partida) en tramos iguales con inOutSine.
struct PistaMascota {
    var prop: PropMascota
    var inicio: Double
    var duracion: Double
    var valores: [Double]

    func valor(_ t: Double) -> Double? {
        let u = (t - inicio) / duracion
        guard u >= 0, u < 1, valores.count > 1 else { return nil }
        let tramos = Double(valores.count - 1)
        let i = min(valores.count - 2, Int(u * tramos))
        let f = u * tramos - Double(i)
        let e = -(cos(.pi * f) - 1) / 2
        return valores[i] + (valores[i + 1] - valores[i]) * e
    }
}

/// Lo que flota por el aire y se va: una nota, un corazón, humo, una zeta, un pétalo.
struct ParticulaMascota {
    enum Tipo { case letra(String, Color, CGFloat), humo, petalo }
    var tipo: Tipo
    var origen: CGPoint
    var dx: Double
    var dy: Double
    var inicio: Double
    var duracion: Double
}

/// Lo que se pinta en un fotograma, ya calculado.
struct FotogramaMascota {
    var forma = FormaMascota()
    var cara = "reposo"
    var caraEscalaY = 1.0
    var parpadeo = 1.0
    var flota = 0.0
    var vaiven = 0.0
    var props: [PropMascota: Double] = [:]
    var particulas: [(ParticulaMascota, Double)] = []
    var fase = 0
    var presencia = 1.0
    var desplazamiento = CGSize.zero
    var izquierda = false
    var t = 0.0
}

/// El cerebro de la mascota: estados, gestos, parpadeo, lo que hace por su cuenta y el paseo. Lo mueve la vista a
/// cada fotograma con `paso(t)` (no es observable: solo lo lee la TimelineView).
final class MascotaMotor {
    var ajustes = MascotaAjustes()
    var vivo = true          // hace cosas solo (en la vista previa de Ajustes, también, pero sin pasear)
    var pasea = false        // puede salir de su sitio a dar una vuelta
    var limites = CGSize(width: 300, height: 400)

    private(set) var actual: MascotaEstado = .reposo
    private var base: MascotaEstado = .reposo
    private(set) var presencia = 1.0
    private var formaDesde = FormaMascota(), formaHasta = FormaMascota(), formaInicio = -10.0, formaAnimada = true
    private var vista = "reposo", ratoCara: (String, Double)?, caraCambio = -10.0
    private var pistas: [PistaMascota] = []
    private var particulas: [ParticulaMascota] = []
    private var libre = 0.0
    private var vuelta: Double?
    private var proximoSolo = 0.0, proximoPulso = 0.0, proximoParpadeo = 0.0, parpadeoInicio = -10.0, parpadeoDoble = false
    private var proximoPaseo = 0.0
    private var repetido = ""
    // el paseo: tramos de desplazamiento
    private var tramos: [(desde: CGSize, hasta: CGSize, inicio: Double, dur: Double, luego: Double)] = []
    private var desplazamiento = CGSize.zero
    private var izquierda = false
    private var arrancado = false

    var esFlor: Bool { ajustes.tipo == "flor" }

    private static func ahora() -> Double { Date().timeIntervalSinceReferenceDate }

    // MARK: estados

    /// El estado de fondo (el que toca por los datos) y lo presente que está (si lleva días sin venir).
    func pon(_ e: MascotaEstado, presencia p: Double = 1, movimiento: Bool = true) {
        base = e
        presencia = p
        if vuelta == nil, e != actual { cambia(e, movimiento: movimiento) }
    }

    private func cambia(_ e: MascotaEstado, movimiento: Bool = true) {
        let t = Self.ahora()
        formaDesde = formaActual(t)
        formaHasta = FormaMascota.de(e, flor: esFlor)
        formaInicio = t
        formaAnimada = movimiento
        actual = e
        expresion(e.rawValue, t, movimiento: movimiento)
    }

    /// Cambia un momento (al marcar un hábito: «feliz» con una fiesta) y vuelve a lo de antes.
    func reacciona(_ e: MascotaEstado = .feliz, ms: Double = 1.6, movimiento: Bool = true) {
        cambia(e, movimiento: movimiento)
        let t = Self.ahora()
        if e == .feliz, movimiento {
            gesto(["doble", "voltereta", "baile", "salto", "estira"].randomElement()!, t)
            suelta(.letra("✦", Color(hex: ajustes.color), 14), arribaDe: t, dx: 14, dy: -22, ms: 1.1)
        }
        vuelta = t + ms
    }

    /// Al tocarla: pone buena cara y hace algo (si no está ya en medio de otra cosa).
    func toca() {
        let t = Self.ahora()
        guard t >= libre else { return }
        rato(actual == .enfadado ? "enfadado" : "feliz", 0.9, t)
        emote(["salto", "voltereta", "giro", "baile", "estornudo", "saltito"].randomElement()!, t)
    }

    private func formaActual(_ t: Double) -> FormaMascota {
        guard formaAnimada else { return formaHasta }
        let u = (t - formaInicio) / 0.7
        if u >= 1 { return formaHasta }
        if u <= 0 { return formaDesde }
        // outElastic(1, .65) de anime.js
        let p = 0.65, s = p / 4
        let k = 1 - pow(2, -10 * u) * sin((u + s) * 2 * .pi / p)
        return FormaMascota.mezcla(formaDesde, formaHasta, k)
    }

    // MARK: la cara

    private func expresion(_ e: String, _ t: Double, movimiento: Bool = true) {
        guard e != vista else { return }
        vista = e
        caraCambio = movimiento ? t : -10
    }

    private func rato(_ e: String, _ s: Double, _ t: Double) {
        ratoCara = (e, t + s)
        if e != vista { caraCambio = t }
    }

    private func caraVisible(_ t: Double) -> String {
        if let r = ratoCara, t < r.1 { return r.0 }
        return vista
    }

    // MARK: gestos

    /// [segundos, posturas, vuelta entera] como GESTOS en mascota.js.
    private static let gestos: [String: (Double, [[PropMascota: Double]], Bool)] = [
        "salto": (0.62, [[.escalaX: 1.1, .escalaY: 0.86], [.y: -18, .escalaX: 0.93, .escalaY: 1.1], [.y: 0, .escalaX: 1.1, .escalaY: 0.88]], false),
        "saltito": (0.42, [[.escalaX: 1.05, .escalaY: 0.93], [.y: -8, .escalaX: 0.97, .escalaY: 1.04]], false),
        "doble": (1.0, [[.escalaX: 1.1, .escalaY: 0.86], [.y: -18, .escalaX: 0.93, .escalaY: 1.1], [.y: 0, .escalaX: 1.1, .escalaY: 0.88],
                        [.y: -11, .escalaX: 0.95, .escalaY: 1.06], [.y: 0, .escalaX: 1.06, .escalaY: 0.92]], false),
        "voltereta": (0.86, [[.escalaX: 1.1, .escalaY: 0.84], [.y: -24, .giro: 180, .escalaX: 1, .escalaY: 1], [.y: 0, .giro: 360, .escalaX: 1.1, .escalaY: 0.88]], true),
        "baile": (1.3, [[.giro: -11, .y: -3], [.giro: 11, .y: 0], [.giro: -11, .y: -3], [.giro: 11, .y: 0], [.giro: -6, .y: -2]], false),
        "meneo": (0.9, [[.giro: -7], [.giro: 7], [.giro: -5], [.giro: 4]], false),
        "estira": (0.95, [[.escalaX: 1.06, .escalaY: 0.92], [.y: -4, .escalaX: 0.88, .escalaY: 1.2], [.y: -4, .escalaX: 0.88, .escalaY: 1.2], [.escalaX: 1.04, .escalaY: 0.95]], false),
        "giro": (0.7, [[.escalaX: 0.1], [.escalaX: -1], [.escalaX: 0.1]], false),
        "escondite": (1.5, [[.escalaX: 1.25, .escalaY: 0.14], [.escalaX: 1.25, .escalaY: 0.14], [.escalaX: 1.25, .escalaY: 0.14], [.y: -8, .escalaX: 0.92, .escalaY: 1.14]], false),
        "estornudo": (0.8, [[.giro: -5, .escalaY: 1.1], [.giro: -8, .escalaY: 1.13], [.giro: 11, .x: 5, .escalaY: 0.84]], false),
        "empujon": (0.62, [[.x: -5, .giro: -5], [.x: 8, .giro: 8]], false),
        "pataleta": (0.76, [[.y: -6, .giro: -5], [.y: 0, .escalaX: 1.08, .escalaY: 0.92], [.y: -6, .giro: 5], [.y: 0, .escalaX: 1.08, .escalaY: 0.92]], false),
        "temblor": (0.52, [[.x: -2], [.x: 2], [.x: -2], [.x: 2], [.x: -2], [.x: 2]], false),
        "resopla": (0.76, [[.escalaX: 1.1, .escalaY: 1.06], [.escalaX: 1.1, .escalaY: 1.06], [.escalaX: 0.96, .escalaY: 0.94]], false),
        "ronquido": (2.0, [[.escalaX: 1.06, .escalaY: 0.9], [.escalaX: 0.98, .escalaY: 1.05]], false),
        "vuelta": (1.0, [[.escalaY: 0.85], [.escalaX: -1, .escalaY: 0.85], [.escalaX: 1]], false),
        "suspiro": (1.5, [[.y: -3, .escalaY: 1.05], [.y: 3, .escalaY: 0.92]], false),
    ]

    private static func reposo(_ p: PropMascota) -> Double {
        switch p {
        case .escalaX, .escalaY, .petalos, .opacidad: return 1
        default: return 0
        }
    }

    private func gesto(_ n: String, _ t: Double) {
        guard let g = Self.gestos[n] else { return }
        let (dur, posturas, entera) = g
        libre = t + dur + 0.5
        let props = Set(posturas.flatMap { $0.keys })
        for p in props {
            let r = Self.reposo(p)
            var valores = [r] + posturas.map { $0[p] ?? r }
            if !entera { valores.append(r) }
            anima(p, valores, dur, t)
        }
    }

    private func anima(_ p: PropMascota, _ valores: [Double], _ dur: Double, _ t: Double) {
        pistas.removeAll { $0.prop == p }
        pistas.append(PistaMascota(prop: p, inicio: t, duracion: dur, valores: valores))
        libre = max(libre, t + dur + 0.4)
    }

    // MARK: lo que flota

    private func arriba() -> CGPoint {
        if esFlor { return CGPoint(x: 104, y: 2) }
        let f = formaHasta
        return CGPoint(x: 80 + ajustes.cola * 0.2, y: 122 - ajustes.alto * f.h)
    }

    private func suelta(_ tipo: ParticulaMascota.Tipo, arribaDe t: Double, dx: Double = 10, dy: Double = -28, ms: Double = 1.6) {
        let a = arriba()
        var origen: CGPoint
        switch tipo {
        case .letra: origen = CGPoint(x: a.x + (esFlor ? 40 : ajustes.ancho * 0.7), y: a.y + 8)
        case .humo: origen = CGPoint(x: a.x + (Bool.random() ? -14 : 14), y: a.y - 3)
        case .petalo: origen = CGPoint(x: 62 + Double.random(in: 0..<84), y: 56)
        }
        particulas.append(ParticulaMascota(tipo: tipo, origen: origen, dx: dx, dy: dy, inicio: t, duracion: ms))
    }

    private func humo(_ t: Double) { suelta(.humo, arribaDe: t, dx: Bool.random() ? -8 : 8, dy: -18, ms: 1) }

    // MARK: lo que hace por su cuenta

    private static let porEstado: [MascotaEstado: [String]] = [
        .reposo: ["mira", "mira", "guino", "bostezo", "saltito", "giro", "escondite", "tararea", "estornudo", "estira"],
        .contento: ["corazon", "corazon", "tararea", "baile", "guino", "voltereta", "giro", "mira"],
        .animo: ["mira", "meneo", "empujon", "empujon", "saltito"],
        .enfadado: ["pataleta", "resopla", "temblor", "mira"],
        .dormido: ["ronquido", "ronquido", "vuelta"],
        .ausente: ["suspiro", "difumina", "mira"],
    ]
    private static let deFlor: [MascotaEstado: [String]] = [
        .reposo: ["saluda", "saluda", "molinillo", "aletea", "patadita", "respira"], .contento: ["saluda", "molinillo", "aletea", "respira"],
        .animo: ["saluda", "saluda"], .enfadado: ["patadita", "aletea"], .dormido: ["respira"], .ausente: ["petalo", "petalo", "petalo"],
    ]

    private func emote(_ n: String, _ t: Double) {
        let color = Color(hex: ajustes.color)
        switch n {
        case "mira":
            let d = esFlor ? 2.5 : 5
            anima(.ojosX, [0, -d, -d, d, d, 0], 1.9, t)
            libre = t + 2.2
        case "saluda": anima(.bd, [0, -32, -14, -36, -14, -30, 0], 1.5, t); rato("contento", 1.5, t)
        case "molinillo": anima(.mano, [0, 360], 1.4, t)
        case "aletea": anima(.bi, [0, 26, -8, 24, 0], 1.1, t); anima(.bd, [0, -26, 8, -24, 0], 1.1, t)
        case "patadita": anima(.pi, [0, 32, -4, 24, 0], 0.9, t)
        case "respira": anima(.petalos, [1, 1.1, 1.1, 1], 1.8, t)
        case "petalo": suelta(.petalo, arribaDe: t, dx: Bool.random() ? -14 : 12, dy: 34, ms: 2.4)
        case "guino": rato("guino", 0.7, t); gesto("saltito", t)
        case "bostezo": rato("bostezo", 1.6, t); gesto("estira", t)
        case "voltereta": rato("feliz", 1, t); gesto("voltereta", t)
        case "baile": rato("feliz", 1.4, t); gesto("baile", t); suelta(.letra("♪", color, 14), arribaDe: t)
        case "escondite": rato("sorpresa", 1.5, t); gesto("escondite", t)
        case "tararea":
            gesto("meneo", t)
            suelta(.letra("♪", color, 14), arribaDe: t)
            suelta(.letra("♫", color, 12), arribaDe: t + 0.5, dx: 16)
        case "estornudo":
            rato("bostezo", 0.45, t); gesto("estornudo", t)
            suelta(.letra("!", DibujoMascota.humo, 16), arribaDe: t + 0.5, dx: 14, dy: -10, ms: 0.7)
        case "corazon": rato("contento", 0.9, t); gesto("saltito", t); suelta(.letra("♥", Color(hex: "#E8556F"), 15), arribaDe: t)
        case "empujon": gesto("empujon", t); suelta(.letra("!", color, 16), arribaDe: t, dx: 6, dy: -14, ms: 0.9)
        case "pataleta": gesto("pataleta", t); humo(t)
        case "resopla": gesto("resopla", t); humo(t + 0.3); humo(t + 0.5)
        case "ronquido": gesto("ronquido", t); suelta(.letra("Z", DibujoMascota.humo, 18), arribaDe: t, dx: 14, dy: -26, ms: 2)
        case "difumina": anima(.opacidad, [1, 0.1, 0.1, 1], 2.2, t); libre = t + 2.6
        default: gesto(n, t)   // saltito, salto, giro, estira, meneo, temblor, vuelta, suspiro
        }
    }

    private func solo(_ t: Double) {
        guard t >= libre, vuelta == nil else { return }
        var xs = (Self.porEstado[actual] ?? Self.porEstado[.reposo]!).filter { $0 != repetido && !(esFlor && ["estira", "escondite"].contains($0)) }
        if esFlor { xs += Self.deFlor[actual] ?? [] }
        guard let n = xs.randomElement() else { return }
        repetido = n
        emote(n, t)
    }

    // MARK: el paseo

    private func empiezaPaseo(_ t: Double) {
        guard pasea, ajustes.paseo, tramos.isEmpty, vuelta == nil, [.reposo, .contento, .animo].contains(actual) else { return }
        let w = max(0, limites.width), h = max(0, limites.height)
        func sitio() -> CGSize { CGSize(width: -Double.random(in: 0...w), height: Double.random(in: 30...max(31, h))) }
        var desde = desplazamiento
        var inicio = t
        for destino in [sitio(), sitio(), CGSize.zero] {
            let dur = 0.5 + hypot(destino.width - desde.width, destino.height - desde.height) * 0.007
            let espera = destino == .zero ? 0 : Double.random(in: 1.8...3.5)
            tramos.append((desde, destino, inicio, dur, espera))
            inicio += dur + espera
            desde = destino
        }
    }

    private func avanzaPaseo(_ t: Double) {
        guard let tr = tramos.first else { return }
        let u = (t - tr.inicio) / tr.dur
        if u < 0 { return }
        if u >= 1 {
            desplazamiento = tr.hasta
            if t >= tr.inicio + tr.dur + tr.luego || tr.hasta == .zero {
                tramos.removeFirst()
                if tr.hasta != .zero { solo(t) } else { izquierda = false }
            }
            return
        }
        let e = -(cos(.pi * u) - 1) / 2
        izquierda = tr.hasta.width < tr.desde.width
        desplazamiento = CGSize(width: tr.desde.width + (tr.hasta.width - tr.desde.width) * e,
                                height: tr.desde.height + (tr.hasta.height - tr.desde.height) * e)
    }

    var paseando: Bool { !tramos.isEmpty }

    // MARK: cada fotograma

    func paso(_ t: Double, movimiento: Bool) -> FotogramaMascota {
        var f = FotogramaMascota()
        f.t = t
        if !arrancado {
            arrancado = true
            proximoSolo = t + Double.random(in: 6...20)
            proximoParpadeo = t + Double.random(in: 2.2...6.5)
            proximoPulso = t + 1.7
            proximoPaseo = t + Double.random(in: 70...200)
        }
        if let v = vuelta, t >= v {
            vuelta = nil
            cambia(base, movimiento: movimiento)
        }
        if let r = ratoCara, t >= r.1 {
            ratoCara = nil
            if vista != r.0 { caraCambio = t }
        }
        if movimiento {
            if vivo, t >= proximoSolo {
                solo(t)
                proximoSolo = t + Double.random(in: 11...34)
            }
            if vivo, t >= proximoPulso {
                proximoPulso = t + 1.7
                if actual == .enfadado { humo(t) }
                if actual == .dormido { suelta(.letra("z", DibujoMascota.humo, 14), arribaDe: t, dx: 12, dy: -24, ms: 2.4) }
            }
            if t >= proximoParpadeo {
                parpadeoInicio = t
                parpadeoDoble = Double.random(in: 0...1) < 0.2
                proximoParpadeo = t + Double.random(in: 2.2...6.5)
            }
            if vivo, pasea, t >= proximoPaseo {
                proximoPaseo = t + Double.random(in: 70...200)
                empiezaPaseo(t)
            }
            avanzaPaseo(t)
        }

        f.forma = formaActual(movimiento ? t : formaInicio + 1)
        let cara = caraVisible(t)
        // cambiar de cara es un parpadeo: se cierra (80 ms), se cambia y se abre con rebote (170 ms)
        let dc = t - caraCambio
        if movimiento, dc >= 0, dc < 0.25 {
            if dc < 0.08 {
                f.caraEscalaY = 1 - 0.85 * pow(dc / 0.08, 2)
                f.cara = caraAnterior
            } else {
                let u = (dc - 0.08) / 0.17 - 1
                f.caraEscalaY = 0.15 + 0.85 * (1 + 3 * pow(u, 3) + 2 * pow(u, 2))
                f.cara = cara
            }
        } else {
            f.cara = cara
        }
        if dc >= 0.08 || dc < 0 { caraAnterior = cara }
        // parpadeo
        let dp = t - parpadeoInicio, largo = parpadeoDoble ? 0.34 : 0.17
        if movimiento, dp >= 0, dp < largo {
            let u = dp.truncatingRemainder(dividingBy: 0.17) / 0.17
            f.parpadeo = 1 - 0.9 * sin(u * .pi)
        }
        if movimiento {
            f.flota = -5 * (1 - cos(t / 3.6 * 2 * .pi)) / 2
            if actual == .animo {
                let u = t.truncatingRemainder(dividingBy: 2.6) / 2.6
                // 0 → -4 → 4 → 0 en 2,6 s
                let tercio = 1.0 / 3
                if u < tercio {
                    f.vaiven = -4 * sin(u * 3 * Double.pi / 2)
                } else if u < 2 * tercio {
                    f.vaiven = -4 + 8 * (1 - cos((u - tercio) * 3 * Double.pi)) / 2
                } else {
                    f.vaiven = 4 * cos((u - 2 * tercio) * 3 * Double.pi / 2)
                }
            }
            f.fase = Int(t / (esFlor ? 0.25 : 0.55)) % 2
        }
        pistas.removeAll { t >= $0.inicio + $0.duracion }
        for p in pistas { if let v = p.valor(t) { f.props[p.prop] = v } }
        particulas.removeAll { t >= $0.inicio + $0.duracion }
        f.particulas = particulas.compactMap { p in
            let u = (t - p.inicio) / p.duracion
            return u >= 0 ? (p, u) : nil
        }
        f.presencia = actual == .ausente ? presencia : 1
        f.desplazamiento = desplazamiento
        f.izquierda = izquierda
        return f
    }

    private var caraAnterior = "reposo"
}
