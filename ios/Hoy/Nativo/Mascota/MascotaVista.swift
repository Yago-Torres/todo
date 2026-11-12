import SwiftUI

/// La mascota nativa (el fantasma de píxeles o la flor de boli de static/mascota.js), con sus animaciones: flota y
/// respira, parpadea, cambia de cara con un parpadeo, hace cosas por su cuenta, reacciona y, si `pasea`, sale a dar
/// una vuelta por la pantalla. Tocarla le hace hacer algo. Reutilizable: Hoy la pone en su cabecera (MascotaHoy) y
/// Ajustes → Tu mascota, como vista previa. Con «reducir movimiento» se queda quieta, solo cambia de cara.
struct MascotaVista: View {
    let ajustes: MascotaAjustes
    var estado: MascotaEstado = .reposo
    /// Lo presente que está (0,25…1): se desvanece si llevas días sin venir.
    var presencia: Double = 1
    /// Cada vez que cambia, se alegra un momento (al marcar un hábito).
    var reaccion: Int = 0
    /// Puede salir de su sitio a dar un paseo por la pantalla (como en la web).
    var pasea = false

    @Environment(\.accessibilityReduceMotion) private var quieto
    @Environment(\.scenePhase) private var fase
    @State private var motor = MascotaMotor()
    @State private var cache = CacheMascota()

    /// Lo que puede salirse de la caja (notas, saltos, la voltereta) sin cambiar lo que ocupa.
    private static let margen: CGFloat = 34

    var body: some View {
        let flor = ajustes.tipo == "flor"
        let caja = flor ? DibujoMascota.cajaFlor : DibujoMascota.cajaFantasma
        let texto = Tema.texto, fondo = Tema.fondo
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: quieto || fase != .active)) { contexto in
            let t = quieto ? Date().timeIntervalSinceReferenceDate : contexto.date.timeIntervalSinceReferenceDate
            let f = motor.paso(t, movimiento: !quieto)
            Canvas { ctx, tam in
                pinta(ctx, tam, f, caja: caja, flor: flor, texto: texto, fondo: fondo)
            }
            .padding(-Self.margen)
            .offset(f.desplazamiento)
        }
        .aspectRatio(caja.width / caja.height, contentMode: .fit)
        .contentShape(Rectangle())
        .onTapGesture { motor.toca() }
        .accessibilityElement()
        .accessibilityLabel(flor ? "Tu flor" : "Tu fantasma")
        .accessibilityValue(Self.descripcion(estado))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { motor.toca() }
        .onAppear {
            motor.ajustes = ajustes
            motor.pasea = pasea
            if let pantalla = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.screen }).first {
                motor.limites = CGSize(width: pantalla.bounds.width - 140, height: pantalla.bounds.height * 0.55)
            }
            motor.pon(estado, presencia: presencia, movimiento: false)
        }
        .onChange(of: ajustes) { _, nuevos in
            let otroTipo = nuevos.tipo != motor.ajustes.tipo
            motor.ajustes = nuevos
            if otroTipo { motor.pon(motor.actual, presencia: presencia, movimiento: false) }
        }
        .onChange(of: estado) { _, e in motor.pon(e, presencia: presencia, movimiento: !quieto) }
        .onChange(of: presencia) { _, p in motor.pon(estado, presencia: p, movimiento: !quieto) }
        .onChange(of: reaccion) { _, _ in motor.reacciona(movimiento: !quieto) }
    }

    private static func descripcion(_ e: MascotaEstado) -> String {
        switch e {
        case .reposo: return "Tranquila"
        case .contento: return "Contenta: has hecho todo lo de hoy"
        case .feliz: return "Feliz"
        case .animo: return "Te anima: aún quedan hábitos"
        case .enfadado: return "Enfadada: ayer se te pasó algo"
        case .dormido: return "Dormida"
        case .ausente: return "Te echa de menos"
        }
    }

    // MARK: pintar

    private func pinta(_ ctx: GraphicsContext, _ tam: CGSize, _ f: FotogramaMascota, caja: CGRect, flor: Bool,
                       texto: Color, fondo: Color) {
        let dentro = CGRect(origin: .zero, size: tam).insetBy(dx: Self.margen, dy: Self.margen)
        guard dentro.width > 0, dentro.height > 0 else { return }
        let s = min(dentro.width / caja.width, dentro.height / caja.height)
        var g = ctx
        g.translateBy(x: dentro.midX - caja.midX * s, y: dentro.midY - caja.midY * s)
        g.scaleBy(x: s, y: s)
        if f.izquierda {
            g.translateBy(x: caja.midX, y: 0)
            g.scaleBy(x: -1, y: 1)
            g.translateBy(x: -caja.midX, y: 0)
        }
        let A = ajustes
        let m = f.forma
        // la sombra, que encoge cuando sube
        let fs = 1 + 0.2 * f.flota / 5
        let sombra = flor ? CGRect(x: 82 - 46 * fs, y: 97 - 2 * fs, width: 92 * fs, height: 4 * fs)
            : {
                let rx = A.ancho * m.a * (1 + A.pera * 0.3) * 0.8 * fs
                return CGRect(x: 80 + A.cola * 0.5 - rx, y: 148 - 3.5 * fs, width: 2 * rx, height: 7 * fs)
            }()
        g.fill(Path(ellipseIn: sombra), with: .color(.black.opacity(0.2 * f.presencia)))

        g.translateBy(x: 0, y: f.flota)
        let aire = g
        // el vaivén, colgado de arriba
        var v = g
        v.opacity = f.props[.opacidad] ?? 1
        let colgado = flor ? CGPoint(x: 104, y: -1) : CGPoint(x: 80 + A.cola * 0.2, y: 122 - A.alto)
        gira(&v, f.vaiven, en: colgado)
        // el cuerpo con el gesto, apoyado abajo
        var c = v
        c.opacity = f.presencia
        c.translateBy(x: f.props[.x] ?? 0, y: f.props[.y] ?? 0)
        let pie = flor ? CGPoint(x: 104, y: 92) : CGPoint(x: 80 + A.cola * 0.2, y: 132)
        c.translateBy(x: pie.x, y: pie.y)
        c.rotate(by: .degrees(f.props[.giro] ?? 0))
        c.scaleBy(x: f.props[.escalaX] ?? 1, y: f.props[.escalaY] ?? 1)
        c.translateBy(x: -pie.x, y: -pie.y)

        if flor {
            pintaFlor(c, f, texto: texto, fondo: fondo)
        } else {
            pintaFantasma(c, f)
        }

        // lo que flota por el aire
        for (p, u) in f.particulas {
            let e = 1 - (1 - u) * (1 - u)
            var a = aire
            a.opacity = 1 - u
            let punto = CGPoint(x: p.origen.x + p.dx * e, y: p.origen.y + p.dy * e)
            switch p.tipo {
            case .letra(let l, let color, let tamano):
                a.draw(Text(l).font(.system(size: tamano, weight: .bold)).foregroundColor(color), at: punto, anchor: .bottomLeading)
            case .humo:
                a.fill(Path(ellipseIn: CGRect(x: punto.x - 3.5, y: punto.y - 3.5, width: 7, height: 7)), with: .color(DibujoMascota.humo))
            case .petalo:
                a.stroke(Path(ellipseIn: CGRect(x: punto.x, y: punto.y - 2, width: 9, height: 4)), with: .color(texto), lineWidth: 0.7)
            }
        }
    }

    private func gira(_ g: inout GraphicsContext, _ grados: Double, en p: CGPoint) {
        guard grados != 0 else { return }
        g.translateBy(x: p.x, y: p.y)
        g.rotate(by: .degrees(grados))
        g.translateBy(x: -p.x, y: -p.y)
    }

    private func escala(_ g: inout GraphicsContext, _ x: Double, _ y: Double, en p: CGPoint) {
        g.translateBy(x: p.x, y: p.y)
        g.scaleBy(x: x, y: y)
        g.translateBy(x: -p.x, y: -p.y)
    }

    private func pintaFantasma(_ c: GraphicsContext, _ f: FotogramaMascota) {
        let A = ajustes, m = f.forma, s = 5.0
        func sn(_ v: Double) -> Double { (v / s).rounded() * s }
        let color = DibujoMascota.mezcla(A.color, DibujoMascota.rojo, max(0, min(1, m.ro)) * 0.55)
        c.fill(cache.cuerpo(A, m, fase: f.fase), with: .color(color))
        if let adorno = cache.adorno(A) {
            var a = c
            a.translateBy(x: 0, y: sn(A.alto * (1 - m.h)))
            a.fill(adorno.camino, with: .color(adorno.color ?? DibujoMascota.tinta))
        }
        var cara = c
        cara.translateBy(x: 0, y: sn(A.alto * (1 - m.h) * (1 - A.ojosY)))
        let centro = CGPoint(x: 80 + A.cola * 0.2, y: 122 - A.alto + A.alto * A.ojosY + 4)
        escala(&cara, 1, f.caraEscalaY, en: centro)
        pintaCara(cara, cache.cara(f.cara, A), f, tinta: DibujoMascota.tinta, rojo: 0)
    }

    private func pintaFlor(_ c: GraphicsContext, _ f: FotogramaMascota, texto: Color, fondo: Color) {
        let m = f.forma
        let partes = cache.flor(ajustes.semilla, fotograma: f.fase)
        let rojo = max(0, min(1, m.ro)) * 0.62
        c.fill(Path(ellipseIn: CGRect(x: 104 - 48, y: 34 - 35, width: 96, height: 70)), with: .color(fondo.opacity(0.82)))
        func trazo(_ g: GraphicsContext, _ p: Path, _ grosor: CGFloat = 0.72) {
            let estilo = StrokeStyle(lineWidth: grosor, lineCap: .round, lineJoin: .round)
            g.stroke(p, with: .color(texto), style: estilo)
            if rojo > 0 { g.stroke(p, with: .color(Color(hex: DibujoMascota.rojo).opacity(rojo)), style: estilo) }
        }
        func nudo(_ x0: Double, _ x1: Double, _ y: Double) -> Path {
            var p = Path(); p.move(to: CGPoint(x: x0, y: y)); p.addLine(to: CGPoint(x: x1, y: y)); return p
        }
        var pi = c
        gira(&pi, m.pi + (f.props[.pi] ?? 0), en: CGPoint(x: 90, y: 59))
        trazo(pi, partes.pi); trazo(pi, nudo(54, 62, 82.5), 2.2)
        var pd = c
        gira(&pd, m.pd + (f.props[.pd] ?? 0), en: CGPoint(x: 109, y: 56))
        trazo(pd, partes.pd); trazo(pd, nudo(93, 97, 91.5), 2.2)
        var pe = c
        let k = m.p * (f.props[.petalos] ?? 1)
        escala(&pe, k, k, en: DibujoMascota.centroFlor)
        trazo(pe, partes.petalos)
        let mano = f.props[.mano] ?? 0
        var bi = c
        gira(&bi, m.bi + (f.props[.bi] ?? 0), en: CGPoint(x: 85, y: 37.5))
        trazo(bi, partes.bi)
        gira(&bi, mano, en: CGPoint(x: 25, y: 45))
        trazo(bi, partes.mi)
        var bd = c
        gira(&bd, m.bd + (f.props[.bd] ?? 0), en: CGPoint(x: 115.5, y: 42))
        trazo(bd, partes.bd)
        gira(&bd, mano, en: CGPoint(x: 175, y: 36.5))
        trazo(bd, partes.md)
        var cara = c
        escala(&cara, 1, f.caraEscalaY, en: CGPoint(x: 104, y: 37))
        pintaCara(cara, cache.cara(f.cara, ajustes), f, tinta: texto, rojo: rojo)
    }

    private func pintaCara(_ c: GraphicsContext, _ trazos: [TrazoMascota], _ f: FotogramaMascota, tinta: Color, rojo: Double) {
        let ojosX = f.props[.ojosX] ?? 0
        for tr in trazos {
            var g = c
            g.opacity = tr.opacidad
            if tr.ojo {
                g.translateBy(x: ojosX, y: 0)
                if f.parpadeo < 1 {
                    let r = tr.camino.boundingRect
                    escala(&g, 1, f.parpadeo, en: CGPoint(x: r.midX, y: r.midY))
                }
            }
            let color = tr.color ?? tinta
            if tr.relleno { g.fill(tr.camino, with: .color(color)) }
            if !tr.relleno || tr.color == nil {
                let estilo = StrokeStyle(lineWidth: tr.grosor, lineCap: .round, lineJoin: .round)
                g.stroke(tr.camino, with: .color(color), style: estilo)
                if rojo > 0, tr.color == nil { g.stroke(tr.camino, with: .color(Color(hex: DibujoMascota.rojo).opacity(rojo)), style: estilo) }
            }
        }
    }
}

/// Lo caro de dibujar, calculado una vez: los píxeles del cuerpo (por deformación y fase), la flor (por semilla y
/// fotograma) y cada cara.
final class CacheMascota {
    private var cuerpos: [String: Path] = [:]
    private var flores: [Int: DibujoMascota.PartesFlor] = [:]
    private var caras: [String: [TrazoMascota]] = [:]
    private var adornos: [String: TrazoMascota?] = [:]
    private var firma = ""

    private func revisa(_ A: MascotaAjustes) {
        let f = "\(A.tipo)|\(A.semilla)|\(A.grumos)|\(A.pera)|\(A.cola)|\(A.flecos)|\(A.fleco)|\(A.ancho)|\(A.alto)|\(A.ojoI)|\(A.ojoD)|\(A.sep)|\(A.ojosY)|\(A.extra)|\(A.rubor)"
        if f != firma {
            firma = f
            cuerpos = [:]
            caras = [:]
            adornos = [:]
        }
    }

    func cuerpo(_ A: MascotaAjustes, _ m: FormaMascota, fase: Int) -> Path {
        revisa(A)
        // redondeado: durante el rebote del cambio de estado se repite mucho la misma forma
        let a = (m.a * 200).rounded() / 200, h = (m.h * 200).rounded() / 200, fl = (m.fl * 100).rounded() / 100
        let clave = "\(a)|\(h)|\(fl)|\(fase)"
        if let p = cuerpos[clave] { return p }
        if cuerpos.count > 80 { cuerpos = [:] }
        let puntos = DibujoMascota.contorno(A, ancho: A.ancho * a, alto: A.alto * h, fleco: min(18, A.fleco * fl), fase: Double(fase))
        let p = DibujoMascota.pixeles(puntos, 5)
        cuerpos[clave] = p
        return p
    }

    func flor(_ semilla: Int, fotograma: Int) -> DibujoMascota.PartesFlor {
        let clave = semilla * 2 + fotograma
        if let f = flores[clave] { return f }
        if flores.count > 6 { flores = [:] }
        let f = DibujoMascota.partesFlor(semilla, fotograma: fotograma)
        flores[clave] = f
        return f
    }

    func cara(_ e: String, _ A: MascotaAjustes) -> [TrazoMascota] {
        revisa(A)
        if let c = caras[e] { return c }
        let c = A.tipo == "flor" ? DibujoMascota.rostroFlor(e, semilla: A.semilla) : DibujoMascota.rostroFantasma(e, A)
        caras[e] = c
        return c
    }

    func adorno(_ A: MascotaAjustes) -> TrazoMascota? {
        revisa(A)
        if let a = adornos[A.extra] { return a }
        let a = DibujoMascota.adorno(A)
        adornos[A.extra] = a
        return a
    }
}

/// La mascota de la cabecera de Hoy: su estado sale de los hábitos, la hora y los días sin venir (como `lee()` en
/// mascota.js) y se alegra cada vez que hay un hábito más hecho. También mantiene al día el ajuste «sonidos».
struct MascotaHoy: View {
    @State private var datos = DatosNativos.shared
    @State private var modelo = ModeloAjustes.shared
    @State private var sinVenir = 0
    @State private var reaccion = 0

    private var hechos: Int { datos.hoy?.habitos.filter(\.hecho).count ?? 0 }

    var body: some View {
        let (estado, presencia) = calcula()
        MascotaVista(ajustes: modelo.ajustes?.mascota ?? MascotaAjustes(), estado: estado, presencia: presencia,
                     reaccion: reaccion, pasea: modelo.ajustes?.mascota.paseo ?? true)
            .frame(height: 56)
            .task {
                leeSinVenir()
                await modelo.carga()
                if let s = modelo.ajustes?.sonidos { Sonidos.shared.activos = s }
            }
            .onChange(of: modelo.ajustes?.sonidos) { _, s in if let s { Sonidos.shared.activos = s } }
            .onChange(of: hechos) { antes, ahora in
                leeSinVenir()
                if ahora > antes { reaccion += 1 }
            }
    }

    /// d: hábitos de hoy, lo de ayer sin hacer y los días sin venir → estado y presencia.
    private func calcula() -> (MascotaEstado, Double) {
        guard let hoy = datos.hoy else { return (.reposo, 1) }
        let hs = hoy.habitos
        let hora = Calendar.current.component(.hour, from: Date())
        let noche = hora >= 23 || hora < 6
        let ayer = (hoy.ayer ?? []).filter { a in !(hs.first { $0.id == a.id }?.hecho ?? false) }
        let faltan = hs.filter { $0.plan && !$0.hecho }
        let dias = hs.contains(where: \.hecho) ? 0 : sinVenir
        let estado: MascotaEstado = noche ? .dormido : dias >= 3 ? .ausente : !ayer.isEmpty ? .enfadado
            : faltan.isEmpty && hs.contains(where: { $0.plan || $0.hecho }) ? .contento
            : hora >= 18 && !faltan.isEmpty ? .animo : .reposo
        return (estado, dias >= 3 ? max(0.25, 1 - Double(dias) * 0.13) : 1)
    }

    /// `sin_venir` viene en /api/hoy pero no está en el modelo Hoy: se lee de la copia local.
    private func leeSinVenir() {
        guard let r = Local.lee(Local.clave("GET", "/api/hoy")),
              let o = (try? JSONSerialization.jsonObject(with: r.cuerpo)) as? [String: Any] else { return }
        sinVenir = (o["sin_venir"] as? NSNumber)?.intValue ?? 0
    }
}
