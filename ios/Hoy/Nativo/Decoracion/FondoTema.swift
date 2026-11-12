import SwiftUI

/// El fondo de cada tema (sustituye a FondoCalma, que sigue siendo el de Hormigón, Calma y Grafito). Sale de la clave
/// `decoracion` del catálogo: papel washi con olas (Shibuya), laca con kintsugi (Kioto), pétalos (Sakura), barrido
/// de terminal, papel de periódico, rejilla neón (Miami), formas Bauhaus, curvas de nivel (Bosque, Fiordo), manchas
/// (Matcha, Lavanda, Arena, Café), estrellas (Medianoche) y rejilla de aparato (Braun).
/// Canvas + TimelineView: los que se mueven solos, a 8–24 fps; los quietos solo se repintan mientras el dedo o la
/// inclinación los mueven. Con «reducir movimiento», todo quieto. La intensidad es la del fondo elegido en
/// Configurar → Apariencia (0 apagado, 0,5 sutil, 1 normal, 1,6 más presente).
struct FondoTema: View {
    @Environment(\.accessibilityReduceMotion) private var quieto
    @Environment(\.scenePhase) private var fase
    @State private var movimiento = MovimientoFondo.shared

    var body: some View {
        let intensidad = Tema.actual.fondo
        let id = Aspecto.shared.decoracion
        Group {
            if intensidad <= 0 {
                Color.clear
            } else if let deco = Decoracion(rawValue: id) {
                let colores = ColoresFondo()
                let dormido = quieto || fase != .active || (deco.fps == 0 && !movimiento.activo)
                TimelineView(.animation(minimumInterval: 1.0 / (deco.fps > 0 ? deco.fps : 20), paused: dormido)) { contexto in
                    // lo que cambia a cada momento se lee aquí (en el hilo principal) y entra en el Canvas como valores
                    let ahora = contexto.date
                    let t = quieto ? 0 : ahora.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 100_000)
                    let inclinacion = quieto ? CGPoint(x: 0, y: 0.7) : movimiento.inclinacion
                    let toque = movimiento.toque
                    let fuerza = quieto ? 0 : movimiento.fuerzaToque(ahora)
                    Canvas { ctx, tam in
                        deco.pinta(ctx, Escena(t: t, tam: tam, k: intensidad, inclinacion: inclinacion,
                                               toque: toque, fuerza: fuerza, c: colores))
                    }
                }
            } else {
                // ascii (y cualquier id que esta versión no conozca): el plasma de siempre, que flota con la inclinación
                FondoCalmaInclinado()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            movimiento.engancha()
            VigiaTema.shared.arranca()
        }
        .onDisappear { movimiento.suelta() }
    }
}

/// FondoCalma con un poco de paralaje: se desplaza unos puntos hacia donde se inclina el iPhone.
private struct FondoCalmaInclinado: View {
    @Environment(\.accessibilityReduceMotion) private var quieto
    @State private var movimiento = MovimientoFondo.shared

    var body: some View {
        // `activo` es lo único observado: mientras se mueve, se recoloca con un muelle suave
        let _ = movimiento.activo
        let g = quieto ? .zero : movimiento.inclinacion
        FondoCalma()
            .padding(-12)
            .offset(x: g.x * 8, y: (g.y - 0.7) * 8)
            .animation(.interpolatingSpring(stiffness: 40, damping: 12), value: g)
    }
}

/// Los colores del tema ya resueltos, para pintarlos dentro del Canvas.
struct ColoresFondo {
    var texto = Tema.texto
    var acento = Tema.acento
    var acentoSuave = Tema.acentoSuave
    var ascii = Tema.ascii
    var aviso = Tema.aviso
    var gota = Tema.gota
    var fondo = Tema.fondo
}

/// Todo lo que necesita un fotograma.
struct Escena {
    var t: Double
    var tam: CGSize
    var k: Double
    var inclinacion: CGPoint
    var toque: CGPoint?
    var fuerza: Double
    var c: ColoresFondo

    var w: CGFloat { tam.width }
    var h: CGFloat { tam.height }
    /// Desplazamiento de paralaje para una capa a `profundidad` (0 lejos, 1 cerca).
    func paralaje(_ profundidad: CGFloat) -> CGSize {
        CGSize(width: inclinacion.x * 14 * profundidad, height: (inclinacion.y - 0.7) * 14 * profundidad)
    }
    /// Cuánto afecta el dedo a un punto (1 encima, 0 a `radio` o más, o sin dedo).
    func cercaDelDedo(_ p: CGPoint, radio: CGFloat) -> Double {
        guard fuerza > 0, let toque else { return 0 }
        let d = hypot(p.x - toque.x, p.y - toque.y)
        return d >= radio ? 0 : (1 - d / radio) * fuerza
    }
}

/// Un número entre 0 y 1 fijo para cada n: el «azar» de los fondos, que no cambia de un fotograma a otro.
func azarFijo(_ n: Int) -> Double {
    var x = UInt64(bitPattern: Int64(n)) &+ 0x9E37_79B9_7F4A_7C15
    x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
    x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
    x ^= x >> 31
    return Double(x % 1_000_003) / 1_000_003
}

enum Decoracion: String {
    case washi, kintsugi, petalos, barrido, papel, rejillaNeon = "rejilla-neon", formas, curvas, manchas, estrellas
    case rejillaFina = "rejilla-fina"

    /// Fotogramas por segundo de su propio movimiento (0 = quieto: solo se repinta con el dedo o la inclinación).
    var fps: Double {
        switch self {
        case .petalos: return 24
        case .rejillaNeon: return 20
        case .kintsugi, .barrido, .estrellas: return 15
        case .washi, .manchas: return 10
        case .papel, .formas, .curvas, .rejillaFina: return 0
        }
    }

    func pinta(_ ctx: GraphicsContext, _ e: Escena) {
        switch self {
        case .washi: Self.washi(ctx, e)
        case .kintsugi: Self.kintsugi(ctx, e)
        case .petalos: Self.petalos(ctx, e)
        case .barrido: Self.barrido(ctx, e)
        case .papel: Self.papel(ctx, e)
        case .rejillaNeon: Self.rejillaNeon(ctx, e)
        case .formas: Self.formas(ctx, e)
        case .curvas: Self.curvas(ctx, e)
        case .manchas: Self.manchas(ctx, e)
        case .estrellas: Self.estrellas(ctx, e)
        case .rejillaFina: Self.rejillaFina(ctx, e)
        }
    }

    // MARK: Shibuya: papel washi con fibras y olas seigaiha abajo

    private static func washi(_ ctx: GraphicsContext, _ e: Escena) {
        var c = ctx
        let p = e.paralaje(0.3)
        c.translateBy(x: p.width, y: p.height)
        // fibras: trazos cortos y curvos repartidos por todo el papel
        var fibras = Path()
        let n = Int(e.w * e.h / 2200)
        for i in 0..<n {
            let x = azarFijo(i * 5) * e.w, y = azarFijo(i * 5 + 1) * e.h
            let largo = 6 + azarFijo(i * 5 + 2) * 20, ang = azarFijo(i * 5 + 3) * .pi
            let curva = (azarFijo(i * 5 + 4) - 0.5) * 8
            let dx = cos(ang) * largo / 2, dy = sin(ang) * largo / 2
            fibras.move(to: CGPoint(x: x - dx, y: y - dy))
            fibras.addQuadCurve(to: CGPoint(x: x + dx, y: y + dy), control: CGPoint(x: x - dy / largo * curva * 2, y: y + dx / largo * curva * 2))
        }
        c.stroke(fibras, with: .color(e.c.texto.opacity(0.07 * e.k)), lineWidth: 0.5)

        // olas: filas de escamas (tres arcos), cada fila tapa a la de detrás, y cada vez más presentes hacia abajo
        let r: CGFloat = 24
        let filas = 7
        let arriba = e.h - CGFloat(filas) * r / 2 - r
        for fila in 0..<filas {
            let y = arriba + CGFloat(fila) * r / 2 + r
            let vaiven: Double = sin(e.t * 0.25 + Double(fila) * 0.7) * 5 + Double(e.inclinacion.x) * 10
            let desfase: CGFloat = fila % 2 == 0 ? 0 : r
            let alfa = 0.05 + 0.16 * Double(fila) / Double(filas - 1)
            var x: CGFloat = -2 * r + desfase + CGFloat(vaiven.truncatingRemainder(dividingBy: Double(2 * r)))
            while x < e.w + 2 * r {
                let centro = CGPoint(x: x, y: y)
                let escama = Path { q in
                    q.addArc(center: centro, radius: r, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                    q.closeSubpath()
                }
                c.fill(escama, with: .color(e.c.fondo))
                var arcos = Path()
                for f in [1.0, 0.7, 0.4] {
                    arcos.addArc(center: centro, radius: r * f, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                }
                c.stroke(arcos, with: .color(e.c.acento.opacity(alfa * e.k)), lineWidth: 1)
                x += 2 * r
            }
        }
    }

    // MARK: Kioto: laca con vetas de oro que brillan un poco

    nonisolated(unsafe) private static var vetasCache: (CGSize, Path)?

    private static func vetas(_ tam: CGSize) -> Path {
        if let c = vetasCache, c.0 == tam { return c.1 }
        var p = Path()
        var semilla = 11
        func azar() -> Double { semilla += 1; return azarFijo(semilla * 13) }
        for grieta in 0..<6 {
            // empieza en un borde y avanza hacia dentro con quiebros, a veces se ramifica
            var punto: CGPoint
            var ang: Double
            switch grieta % 4 {
            case 0: punto = CGPoint(x: 0, y: azar() * tam.height); ang = 0
            case 1: punto = CGPoint(x: tam.width, y: azar() * tam.height); ang = .pi
            case 2: punto = CGPoint(x: azar() * tam.width, y: 0); ang = .pi / 2
            default: punto = CGPoint(x: azar() * tam.width, y: tam.height); ang = -.pi / 2
            }
            p.move(to: punto)
            for paso in 0..<16 {
                ang += (azar() - 0.5) * 0.9
                let largo = 18 + azar() * 40
                let siguiente = CGPoint(x: punto.x + cos(ang) * largo, y: punto.y + sin(ang) * largo)
                p.addLine(to: siguiente)
                if paso % 5 == 3, azar() < 0.7 {
                    // rama corta
                    var q = siguiente, a = ang + (azar() < 0.5 ? -1 : 1) * (0.6 + azar() * 0.6)
                    var rama = Path()
                    rama.move(to: q)
                    for _ in 0..<4 {
                        a += (azar() - 0.5) * 0.8
                        q = CGPoint(x: q.x + cos(a) * (10 + azar() * 22), y: q.y + sin(a) * (10 + azar() * 22))
                        rama.addLine(to: q)
                    }
                    p.addPath(rama)
                    p.move(to: siguiente)
                }
                punto = siguiente
            }
        }
        vetasCache = (tam, p)
        return p
    }

    private static func kintsugi(_ ctx: GraphicsContext, _ e: Escena) {
        var c = ctx
        // el brillo de la laca: una mancha de luz que sigue a la inclinación
        let luz = CGPoint(x: e.w * (0.5 + e.inclinacion.x * 0.35), y: e.h * (0.3 + (e.inclinacion.y - 0.7) * 0.4))
        c.fill(Path(CGRect(origin: .zero, size: e.tam)),
               with: .radialGradient(Gradient(colors: [e.c.acento.opacity(0.07 * e.k), .clear]),
                                     center: luz, startRadius: 0, endRadius: max(e.w, e.h) * 0.8))
        let p = e.paralaje(0.4)
        c.translateBy(x: p.width, y: p.height)
        let v = vetas(e.tam)
        let estilo = StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round)
        c.stroke(v, with: .color(e.c.acento.opacity(0.22 * e.k)), style: estilo)
        // el destello que recorre el oro en diagonal, empujado por la inclinación
        let pos = (e.t * 0.06 + Double(e.inclinacion.x) * 0.25).truncatingRemainder(dividingBy: 1.6) - 0.3
        let a = CGPoint(x: e.w * (pos - 0.12), y: e.h * (pos - 0.12))
        let b = CGPoint(x: e.w * (pos + 0.12), y: e.h * (pos + 0.12))
        c.stroke(v, with: .linearGradient(Gradient(colors: [.clear, e.c.acento.opacity(min(1, 0.8 * e.k)), .clear]),
                                          startPoint: a, endPoint: b),
                 style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        // donde toca el dedo, el oro se enciende
        if e.fuerza > 0, let t = e.toque {
            c.stroke(v, with: .radialGradient(Gradient(colors: [e.c.acento.opacity(min(1, 0.9 * e.k * e.fuerza)), .clear]),
                                              center: CGPoint(x: t.x - p.width, y: t.y - p.height), startRadius: 0, endRadius: 130),
                     style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: Sakura: pétalos que caen despacio

    private static let petalo: Path = Path { q in
        q.move(to: CGPoint(x: 0, y: 1))
        q.addQuadCurve(to: CGPoint(x: -0.28, y: -1), control: CGPoint(x: -0.95, y: 0))
        q.addLine(to: CGPoint(x: 0, y: -0.72))
        q.addLine(to: CGPoint(x: 0.28, y: -1))
        q.addQuadCurve(to: CGPoint(x: 0, y: 1), control: CGPoint(x: 0.95, y: 0))
        q.closeSubpath()
    }

    private static func petalos(_ ctx: GraphicsContext, _ e: Escena) {
        let n = 18
        let alto = e.h + 60
        for i in 0..<n {
            let velocidad = 16 + azarFijo(i * 7 + 1) * 22
            let y = (e.t * velocidad + azarFijo(i * 7 + 2) * alto).truncatingRemainder(dividingBy: alto) - 30
            let viento = Double(e.inclinacion.x) * 50 * (0.6 + azarFijo(i * 7 + 3))
            var x = azarFijo(i * 7) * e.w + sin(e.t * (0.4 + azarFijo(i * 7 + 4) * 0.4) + Double(i)) * 24 + viento
            var punto = CGPoint(x: x, y: y)
            // el dedo los aparta
            if let t = e.toque {
                let f = e.cercaDelDedo(punto, radio: 100)
                if f > 0 {
                    let d = max(1, hypot(punto.x - t.x, punto.y - t.y))
                    punto.x += (punto.x - t.x) / d * 40 * f
                    punto.y += (punto.y - t.y) / d * 40 * f
                }
            }
            x = punto.x.truncatingRemainder(dividingBy: e.w + 40)
            if x < -20 { x += e.w + 40 }
            punto.x = x
            let tam = 6 + azarFijo(i * 7 + 5) * 6
            let giro = e.t * (0.3 + azarFijo(i * 7 + 6) * 0.6) + Double(i)
            var c = ctx
            c.translateBy(x: punto.x, y: punto.y)
            c.rotate(by: .radians(giro))
            c.scaleBy(x: tam * max(0.15, abs(cos(giro * 1.3))), y: tam)
            let alfa = (0.22 + 0.18 * azarFijo(i * 3 + 9)) * e.k
            c.fill(petalo, with: .color((i % 3 == 0 ? e.c.gota : e.c.acento).opacity(min(1, alfa))))
        }
    }

    // MARK: Terminal: líneas de barrido y caracteres

    private static let simbolos = Array("01<>/\\{}[]=+*#$%&ABCDEF")

    private static func barrido(_ ctx: GraphicsContext, _ e: Escena) {
        var lineas = Path()
        var y: CGFloat = 0
        while y < e.h {
            lineas.addRect(CGRect(x: 0, y: y, width: e.w, height: 1))
            y += 4
        }
        ctx.fill(lineas, with: .color(e.c.texto.opacity(0.025 * e.k)))
        // la franja que baja
        let banda = CGFloat((e.t * 55).truncatingRemainder(dividingBy: Double(e.h + 240))) - 120
        ctx.fill(Path(CGRect(x: 0, y: banda - 70, width: e.w, height: 140)),
                 with: .linearGradient(Gradient(colors: [.clear, e.c.acento.opacity(0.06 * e.k), .clear]),
                                       startPoint: CGPoint(x: 0, y: banda - 70), endPoint: CGPoint(x: 0, y: banda + 70)))
        // caracteres sueltos que cambian a ratos; más vivos al pasar la franja o el dedo
        let glifos = simbolos.map { ctx.resolve(Text(String($0)).font(.system(size: 12, design: .monospaced)).foregroundColor(e.c.acento)) }
        let celda = CGSize(width: 14, height: 20)
        let cols = Int(e.w / celda.width) + 1, filas = Int(e.h / celda.height) + 1
        let p = e.paralaje(0.5)
        for f in 0..<filas {
            for col in 0..<cols {
                let id = f * 977 + col
                guard azarFijo(id) < 0.07 else { continue }
                let paso = Int(e.t * 1.3 + azarFijo(id + 1) * 10)
                let g = glifos[Int(azarFijo(id * 31 + paso) * Double(glifos.count)) % glifos.count]
                let punto = CGPoint(x: CGFloat(col) * celda.width + p.width, y: CGFloat(f) * celda.height + p.height)
                let cerca = max(0, 1 - abs(punto.y - banda) / 80)
                var c = ctx
                c.opacity = min(1, (0.12 + 0.3 * cerca + 0.6 * e.cercaDelDedo(punto, radio: 90)) * e.k)
                c.draw(g, at: punto, anchor: .topLeading)
            }
        }
    }

    // MARK: Prensa: grano de papel y columnas tenues

    private static func papel(_ ctx: GraphicsContext, _ e: Escena) {
        var c = ctx
        let p = e.paralaje(0.25)
        var grano = Path()
        let n = Int(e.w * e.h / 260)
        for i in 0..<n {
            let x = azarFijo(i * 3) * e.w, y = azarFijo(i * 3 + 1) * e.h
            let r = 0.3 + azarFijo(i * 3 + 2) * 0.6
            grano.addEllipse(in: CGRect(x: x, y: y, width: r, height: r))
        }
        c.fill(grano, with: .color(e.c.texto.opacity(0.09 * e.k)))
        c.translateBy(x: p.width, y: p.height)
        // tres columnas con su filete y líneas de «texto» grises
        let margen: CGFloat = 18, hueco: CGFloat = 14
        let ancho = (e.w - 2 * margen - 2 * hueco) / 3
        var filetes = Path(), texto = Path(), titulares = Path()
        for col in 0..<3 {
            let x = margen + CGFloat(col) * (ancho + hueco)
            if col > 0 {
                filetes.move(to: CGPoint(x: x - hueco / 2, y: 90))
                filetes.addLine(to: CGPoint(x: x - hueco / 2, y: e.h - 40))
            }
            var y: CGFloat = 96
            var linea = 0
            while y < e.h - 40 {
                let id = col * 1000 + linea
                if azarFijo(id) < 0.06 {
                    // un titular
                    titulares.addRect(CGRect(x: x, y: y, width: ancho * (0.6 + azarFijo(id + 1) * 0.4), height: 7))
                    y += 18
                } else {
                    let fin = azarFijo(id + 2) < 0.15 ? 0.35 + azarFijo(id + 3) * 0.4 : 1
                    texto.addRect(CGRect(x: x, y: y, width: ancho * fin, height: 2.5))
                    y += 9
                }
                linea += 1
            }
        }
        filetes.move(to: CGPoint(x: margen, y: 80))
        filetes.addLine(to: CGPoint(x: e.w - margen, y: 80))
        c.stroke(filetes, with: .color(e.c.texto.opacity(0.07 * e.k)), lineWidth: 0.6)
        c.fill(texto, with: .color(e.c.texto.opacity(0.035 * e.k)))
        c.fill(titulares, with: .color(e.c.texto.opacity(0.05 * e.k)))
    }

    // MARK: Miami: rejilla en perspectiva de neón

    private static func rejillaNeon(_ ctx: GraphicsContext, _ e: Escena) {
        var c = ctx
        let horizonte = e.h * 0.6 + (e.inclinacion.y - 0.7) * 20
        var fuga = e.w / 2 + e.inclinacion.x * 70
        if let t = e.toque { fuga += (t.x - e.w / 2) * 0.35 * e.fuerza }
        // el sol, con sus franjas
        let radio = e.w * 0.24
        let sol = CGRect(x: fuga - radio, y: horizonte - radio * 1.2, width: radio * 2, height: radio * 2)
        c.drawLayer { capa in
            capa.clip(to: Path(CGRect(x: 0, y: 0, width: e.w, height: horizonte)))
            var franjas = Path(CGRect(x: sol.minX, y: sol.minY, width: sol.width, height: sol.height * 0.55))
            var yy = sol.minY + sol.height * 0.55
            var alto: CGFloat = 7
            while yy < sol.maxY {
                franjas.addRect(CGRect(x: sol.minX, y: yy, width: sol.width, height: alto))
                yy += alto + 4
                alto = max(2, alto - 1.2)
            }
            capa.clip(to: Path(ellipseIn: sol))
            capa.fill(franjas, with: .linearGradient(Gradient(colors: [e.c.aviso.opacity(0.14 * e.k), e.c.acento.opacity(0.14 * e.k)]),
                                                     startPoint: CGPoint(x: 0, y: sol.minY), endPoint: CGPoint(x: 0, y: sol.maxY)))
        }
        var rejilla = Path()
        for i in -14...14 {
            let abajo = e.w / 2 + CGFloat(i) * e.w / 5
            rejilla.move(to: CGPoint(x: fuga, y: horizonte))
            rejilla.addLine(to: CGPoint(x: fuga + (abajo - fuga) * 1.6, y: e.h + (e.h - horizonte) * 0.6))
        }
        let avance = (e.t * 0.55).truncatingRemainder(dividingBy: 1)
        for n in 0..<16 {
            let z = (Double(n) + avance) / 16
            let y = horizonte + (e.h - horizonte) * CGFloat(pow(z, 2.2))
            rejilla.move(to: CGPoint(x: 0, y: y))
            rejilla.addLine(to: CGPoint(x: e.w, y: y))
        }
        rejilla.move(to: CGPoint(x: 0, y: horizonte))
        rejilla.addLine(to: CGPoint(x: e.w, y: horizonte))
        c.clip(to: Path(CGRect(x: 0, y: horizonte, width: e.w, height: e.h - horizonte)))
        c.stroke(rejilla, with: .color(e.c.acento.opacity(0.07 * e.k)), lineWidth: 5)
        c.stroke(rejilla, with: .color(e.c.acento.opacity(0.28 * e.k)), lineWidth: 1)
        // niebla en el horizonte: el fondo se come las líneas lejanas
        c.fill(Path(CGRect(x: 0, y: horizonte, width: e.w, height: 90)),
               with: .linearGradient(Gradient(colors: [e.c.fondo, e.c.fondo.opacity(0)]),
                                     startPoint: CGPoint(x: 0, y: horizonte), endPoint: CGPoint(x: 0, y: horizonte + 90)))
    }

    // MARK: Bauhaus: círculo, triángulo y cuadrado planos

    private static func formas(_ ctx: GraphicsContext, _ e: Escena) {
        func sitio(_ x: CGFloat, _ y: CGFloat, _ profundidad: CGFloat) -> CGPoint {
            let p = e.paralaje(profundidad * 1.6)
            var punto = CGPoint(x: x + p.width, y: y + p.height)
            if let t = e.toque, e.fuerza > 0 {
                punto.x += (t.x - punto.x) * 0.04 * profundidad * e.fuerza
                punto.y += (t.y - punto.y) * 0.04 * profundidad * e.fuerza
            }
            return punto
        }
        let circulo = sitio(e.w * 0.8, e.h * 0.2, 0.5)
        let r = e.w * 0.3
        ctx.fill(Path(ellipseIn: CGRect(x: circulo.x - r, y: circulo.y - r, width: 2 * r, height: 2 * r)),
                 with: .color(e.c.acento.opacity(0.11 * e.k)))
        let tri = sitio(e.w * 0.05, e.h * 0.58, 0.9)
        let lado = e.w * 0.46
        ctx.fill(Path { q in
            q.move(to: CGPoint(x: tri.x, y: tri.y + lado))
            q.addLine(to: CGPoint(x: tri.x + lado / 2, y: tri.y + lado * 0.13))
            q.addLine(to: CGPoint(x: tri.x + lado, y: tri.y + lado))
            q.closeSubpath()
        }, with: .color(e.c.aviso.opacity(0.12 * e.k)))
        let cua = sitio(e.w * 0.58, e.h * 0.74, 0.3)
        ctx.fill(Path(CGRect(x: cua.x, y: cua.y, width: e.w * 0.3, height: e.w * 0.3)),
                 with: .color(e.c.texto.opacity(0.07 * e.k)))
        let raya = sitio(0, e.h * 0.47, 0.2)
        ctx.fill(Path(CGRect(x: 0, y: raya.y, width: e.w, height: 3)), with: .color(e.c.texto.opacity(0.08 * e.k)))
        let palo = sitio(e.w * 0.3, 0, 0.7)
        ctx.fill(Path(CGRect(x: palo.x, y: 0, width: 3, height: e.h * 0.47)), with: .color(e.c.texto.opacity(0.06 * e.k)))
    }

    // MARK: Bosque y Fiordo: curvas de nivel

    nonisolated(unsafe) private static var curvasCache: (CGSize, Path, Path)?

    /// Las curvas de nivel de un relieve inventado, con marching squares en una rejilla de 12 pt. Se calculan una
    /// vez por tamaño de pantalla.
    private static func curvasDeNivel(_ tam: CGSize) -> (Path, Path) {
        if let c = curvasCache, c.0 == tam { return (c.1, c.2) }
        let paso: CGFloat = 12
        let cols = Int(tam.width / paso) + 3, filas = Int(tam.height / paso) + 3
        func altura(_ x: CGFloat, _ y: CGFloat) -> Double {
            let u = Double(x / tam.width), v = Double(y / tam.height)
            var z = 0.0
            z += exp(-(pow(u - 0.25, 2) + pow(v - 0.22, 2)) / 0.05) * 0.9
            z += exp(-(pow(u - 0.8, 2) + pow(v - 0.55, 2)) / 0.07) * 1.0
            z += exp(-(pow(u - 0.3, 2) + pow(v - 0.85, 2)) / 0.04) * 0.7
            z += 0.08 * sin(u * 9 + v * 4) + 0.06 * sin(v * 13 - u * 3)
            return z
        }
        var valores = [[Double]](repeating: [Double](repeating: 0, count: cols), count: filas)
        for f in 0..<filas { for c in 0..<cols { valores[f][c] = altura(CGFloat(c - 1) * paso, CGFloat(f - 1) * paso) } }
        var normal = Path(), maestra = Path()
        for nivel in 1...16 {
            let l = Double(nivel) * 0.065
            var p = Path()
            for f in 0..<(filas - 1) {
                for c in 0..<(cols - 1) {
                    let a = valores[f][c], b = valores[f][c + 1], d = valores[f + 1][c + 1], e = valores[f + 1][c]
                    let x = CGFloat(c - 1) * paso, y = CGFloat(f - 1) * paso
                    func corte(_ v0: Double, _ v1: Double) -> CGFloat { CGFloat((l - v0) / (v1 - v0)) }
                    var puntos: [CGPoint] = []
                    if (a < l) != (b < l) { puntos.append(CGPoint(x: x + corte(a, b) * paso, y: y)) }
                    if (b < l) != (d < l) { puntos.append(CGPoint(x: x + paso, y: y + corte(b, d) * paso)) }
                    if (e < l) != (d < l) { puntos.append(CGPoint(x: x + corte(e, d) * paso, y: y + paso)) }
                    if (a < l) != (e < l) { puntos.append(CGPoint(x: x, y: y + corte(a, e) * paso)) }
                    var i = 0
                    while i + 1 < puntos.count {
                        p.move(to: puntos[i])
                        p.addLine(to: puntos[i + 1])
                        i += 2
                    }
                }
            }
            if nivel % 5 == 0 { maestra.addPath(p) } else { normal.addPath(p) }
        }
        curvasCache = (tam, normal, maestra)
        return (normal, maestra)
    }

    private static func curvas(_ ctx: GraphicsContext, _ e: Escena) {
        var c = ctx
        let p = e.paralaje(0.6)
        c.translateBy(x: p.width, y: p.height)
        let (normal, maestra) = curvasDeNivel(e.tam)
        c.stroke(normal, with: .color(e.c.texto.opacity(0.07 * e.k)), lineWidth: 0.7)
        c.stroke(maestra, with: .color(e.c.acento.opacity(0.18 * e.k)), lineWidth: 1.1)
        if e.fuerza > 0, let t = e.toque {
            let centro = CGPoint(x: t.x - p.width, y: t.y - p.height)
            let brillo = GraphicsContext.Shading.radialGradient(
                Gradient(colors: [e.c.acento.opacity(min(1, 0.55 * e.k * e.fuerza)), .clear]),
                center: centro, startRadius: 0, endRadius: 110)
            c.stroke(normal, with: brillo, lineWidth: 1)
            c.stroke(maestra, with: brillo, lineWidth: 1.4)
        }
    }

    // MARK: Matcha, Lavanda, Arena y Café: manchas orgánicas suaves

    private static func manchas(_ ctx: GraphicsContext, _ e: Escena) {
        let colores = [e.c.acento, e.c.gota, e.c.acento, e.c.aviso]
        let base: [(CGFloat, CGFloat, CGFloat)] = [(0.15, 0.12, 0.55), (0.9, 0.38, 0.5), (0.2, 0.7, 0.45), (0.75, 0.92, 0.5)]
        for (i, b) in base.enumerated() {
            let fi = Double(i)
            let p = e.paralaje(0.4 + CGFloat(i) * 0.25)
            var centro = CGPoint(x: e.w * b.0 + sin(e.t * 0.05 * (fi + 1) + fi) * e.w * 0.12 + p.width * 2,
                                 y: e.h * b.1 + cos(e.t * 0.04 * (fi + 2) + fi) * e.h * 0.06 + p.height * 2)
            if let t = e.toque, e.fuerza > 0 {
                centro.x += (t.x - centro.x) * 0.08 * e.fuerza
                centro.y += (t.y - centro.y) * 0.08 * e.fuerza
            }
            let r = e.w * b.2
            var mancha = Path()
            let n = 40
            for j in 0...n {
                let a = Double(j) / Double(n) * 2 * .pi
                let rr = r * (1 + 0.12 * sin(3 * a + e.t * 0.2 + fi) + 0.07 * sin(5 * a - e.t * 0.15 + fi * 2))
                let q = CGPoint(x: centro.x + cos(a) * rr, y: centro.y + sin(a) * rr)
                if j == 0 { mancha.move(to: q) } else { mancha.addLine(to: q) }
            }
            mancha.closeSubpath()
            ctx.fill(mancha, with: .radialGradient(Gradient(colors: [colores[i].opacity(min(1, 0.13 * e.k)), colores[i].opacity(0)]),
                                                   center: centro, startRadius: 0, endRadius: r * 1.15))
        }
    }

    // MARK: Medianoche: estrellas tenues

    private static func estrellas(_ ctx: GraphicsContext, _ e: Escena) {
        let n = 120
        for i in 0..<n {
            let profundidad = 0.2 + azarFijo(i * 6 + 3) * 0.8
            let p = e.paralaje(CGFloat(profundidad) * 1.4)
            let punto = CGPoint(x: azarFijo(i * 6) * e.w + p.width, y: azarFijo(i * 6 + 1) * e.h + p.height)
            let tam = 0.6 + azarFijo(i * 6 + 2) * 1.5 * profundidad
            let titila = 0.35 + 0.65 * (0.5 + 0.5 * sin(e.t * (0.4 + azarFijo(i * 6 + 4) * 1.6) + azarFijo(i * 6 + 5) * 6.3))
            let alfa = min(1, (0.45 * titila + 0.5 * e.cercaDelDedo(punto, radio: 110)) * e.k)
            ctx.fill(Path(ellipseIn: CGRect(x: punto.x - tam / 2, y: punto.y - tam / 2, width: tam, height: tam)),
                     with: .color((i % 9 == 0 ? e.c.acento : e.c.texto).opacity(alfa)))
        }
        // una estrella fugaz de vez en cuando
        let ciclo = 19.0
        let fase = e.t.truncatingRemainder(dividingBy: ciclo)
        if fase < 0.9 {
            let vez = Int(e.t / ciclo)
            let x0 = azarFijo(vez * 3) * e.w * 0.8, y0 = azarFijo(vez * 3 + 1) * e.h * 0.4
            let avance = fase / 0.9
            let cabeza = CGPoint(x: x0 + 220 * avance, y: y0 + 90 * avance)
            let cola = CGPoint(x: cabeza.x - 70, y: cabeza.y - 29)
            var raya = Path()
            raya.move(to: cola)
            raya.addLine(to: cabeza)
            ctx.stroke(raya, with: .linearGradient(Gradient(colors: [.clear, e.c.texto.opacity(0.5 * e.k * (1 - avance))]),
                                                   startPoint: cola, endPoint: cabeza), lineWidth: 1.2)
        }
    }

    // MARK: Braun: rejilla fina de aparato

    private static func rejillaFina(_ ctx: GraphicsContext, _ e: Escena) {
        var c = ctx
        let p = e.paralaje(0.2)
        c.translateBy(x: p.width, y: p.height)
        let paso: CGFloat = 10
        var fina = Path(), gruesa = Path()
        var i = 0
        var x: CGFloat = 0
        while x <= e.w {
            var l = Path(); l.move(to: CGPoint(x: x, y: -20)); l.addLine(to: CGPoint(x: x, y: e.h + 20))
            if i % 5 == 0 { gruesa.addPath(l) } else { fina.addPath(l) }
            x += paso; i += 1
        }
        i = 0
        var y: CGFloat = 0
        while y <= e.h {
            var l = Path(); l.move(to: CGPoint(x: -20, y: y)); l.addLine(to: CGPoint(x: e.w + 20, y: y))
            if i % 5 == 0 { gruesa.addPath(l) } else { fina.addPath(l) }
            y += paso; i += 1
        }
        c.stroke(fina, with: .color(e.c.texto.opacity(0.025 * e.k)), lineWidth: 0.5)
        c.stroke(gruesa, with: .color(e.c.texto.opacity(0.05 * e.k)), lineWidth: 0.6)
        // la rejilla del altavoz, abajo a la derecha: puntos dentro de un círculo
        let centro = CGPoint(x: e.w * 0.82, y: e.h * 0.84)
        let radio = e.w * 0.3
        var puntos = Path(), vivos = Path()
        var py = centro.y - radio
        while py <= centro.y + radio {
            var px = centro.x - radio
            while px <= centro.x + radio {
                if hypot(px - centro.x, py - centro.y) <= radio {
                    let punto = CGRect(x: px - 1.6, y: py - 1.6, width: 3.2, height: 3.2)
                    if e.cercaDelDedo(CGPoint(x: px + p.width, y: py + p.height), radio: 70) > 0.2 {
                        vivos.addEllipse(in: punto)
                    } else {
                        puntos.addEllipse(in: punto)
                    }
                }
                px += 9
            }
            py += 9
        }
        c.fill(puntos, with: .color(e.c.texto.opacity(0.09 * e.k)))
        c.fill(vivos, with: .color(e.c.acento.opacity(min(1, 0.6 * e.k))))
        // el piloto naranja
        c.fill(Path(ellipseIn: CGRect(x: e.w - 34, y: 64, width: 8, height: 8)), with: .color(e.c.acento.opacity(min(1, 0.45 * e.k))))
    }
}
