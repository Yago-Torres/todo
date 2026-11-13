import SwiftUI
import UIKit

/// La ruta del intento, al estilo de una actividad de Strava: el trazo del centro de gravedad coloreado por velocidad,
/// los apoyos (manos o pies quietos más de 0,4 s), las pausas, el perfil de «elevación» y las cifras. Sale de las
/// poses que ya calculan Presumir o el modo en vivo (que las guarda en un JSON junto al vídeo).
struct RutaEsc {
    struct Punto {
        var t: Double
        var p: CGPoint      // píxeles de la imagen derecha
        var v: Double       // m/s
        var altura: Double  // m sobre la salida
    }

    var puntos: [Punto]
    var apoyos: [(t: Double, p: CGPoint)]
    var pausas: [(Double, Double)]
    var tam: CGSize
    var tiempo: Double
    var alturaMax: Double
    var vMax: Double
    var tramo: (inicio: Double, metros: Double)?

    var t0: Double { puntos.first?.t ?? 0 }
    var subidaPorMinuto: Double { tiempo > 1 ? alturaMax / (tiempo / 60) : 0 }

    /// nil si no hay bastante cuerpo visto para dibujar nada.
    init?(_ muestras: [(Double, PoseEsc?)], tam: CGSize) {
        guard tam.width > 0, tam.height > 0 else { return nil }
        var crudos: [(Double, CGPoint)] = []
        var troncos: [CGFloat] = []
        for (t, pose) in muestras {
            guard let pose, let c = pose.centro(tam) else { continue }
            crudos.append((t, c))
            if let l = pose.largoTronco(tam) { troncos.append(l) }
        }
        guard crudos.count >= 4, !troncos.isEmpty else { return nil }
        troncos.sort()
        let tronco = max(troncos[troncos.count / 2], 1)
        let mpp = 0.5 / Double(tronco)   // metros por píxel: el tronco mide ~0,5 m

        // suavizado: media móvil de 5 muestras
        var suaves: [(Double, CGPoint)] = []
        for i in crudos.indices {
            let a = max(0, i - 2), b = min(crudos.count - 1, i + 2)
            var x: CGFloat = 0, y: CGFloat = 0
            for j in a...b {
                x += crudos[j].1.x
                y += crudos[j].1.y
            }
            let n = CGFloat(b - a + 1)
            suaves.append((crudos[i].0, CGPoint(x: x / n, y: y / n)))
        }
        let y0 = suaves[0].1.y
        var ps: [Punto] = []
        for i in suaves.indices {
            let (t, p) = suaves[i]
            var v = 0.0
            if i > 0 {
                let (ta, pa) = suaves[i - 1]
                if t > ta { v = Double(hypot(p.x - pa.x, p.y - pa.y)) * mpp / (t - ta) }
            }
            ps.append(Punto(t: t, p: p, v: min(v, 3), altura: Double(y0 - p.y) * mpp))
        }
        // la velocidad, también suavizada (si no, el degradado parpadea)
        let vs = ps.map(\.v)
        for i in ps.indices {
            let a = max(0, i - 3), b = min(ps.count - 1, i + 3)
            ps[i].v = vs[a...b].reduce(0, +) / Double(b - a + 1)
        }

        // pausas: más de 1 s casi sin moverse
        var pausas: [(Double, Double)] = []
        var desde: Double?
        for q in ps {
            if q.v < 0.08 {
                if desde == nil { desde = q.t }
            } else if let d = desde {
                if q.t - d >= 1 { pausas.append((d, q.t)) }
                desde = nil
            }
        }
        if let d = desde, let fin = ps.last?.t, fin - d >= 1 { pausas.append((d, fin)) }

        // apoyos: una mano o un pie quieto (menos de 0,12 troncos) durante 0,4 s o más
        var apoyos: [(t: Double, p: CGPoint)] = []
        for extremo in [10, 11, 17, 18] {
            var ancla: (t: Double, p: CGPoint, suma: CGPoint, n: CGFloat, ultimo: Double)?
            func cierra() {
                if let a = ancla, a.ultimo - a.t >= 0.4, a.n > 0 {
                    apoyos.append((a.t, CGPoint(x: a.suma.x / a.n, y: a.suma.y / a.n)))
                }
                ancla = nil
            }
            for (t, pose) in muestras {
                guard let pose, pose.ve(extremo) else {
                    cierra()
                    continue
                }
                let q = CGPoint(x: pose.p[extremo].x * tam.width, y: pose.p[extremo].y * tam.height)
                if var a = ancla, hypot(q.x - a.p.x, q.y - a.p.y) < 0.12 * tronco {
                    a.suma = CGPoint(x: a.suma.x + q.x, y: a.suma.y + q.y)
                    a.n += 1
                    a.ultimo = t
                    ancla = a
                } else {
                    cierra()
                    ancla = (t, q, q, 1, t)
                }
            }
            cierra()
        }
        apoyos.sort { $0.t < $1.t }

        // el tramo más rápido: lo que más se sube en 2 s
        var tramo: (inicio: Double, metros: Double)?
        var j = 0
        for i in ps.indices {
            if j < i { j = i }
            while j + 1 < ps.count && ps[j + 1].t - ps[i].t <= 2 { j += 1 }
            let sube = ps[j].altura - ps[i].altura
            if sube > (tramo?.metros ?? 0.05) { tramo = (ps[i].t, sube) }
        }

        puntos = ps
        self.apoyos = apoyos
        self.pausas = pausas
        self.tam = tam
        tiempo = max(0, (ps.last?.t ?? 0) - (ps.first?.t ?? 0))
        alturaMax = max(0, ps.map(\.altura).max() ?? 0)
        vMax = max(0.2, ps.map(\.v).max() ?? 0.2)
        self.tramo = tramo
    }

    // MARK: cifras

    static func metros(_ m: Double) -> String {
        String(format: "%.1f", m).replacingOccurrences(of: ".", with: ",")
    }

    var cifras: [(String, String)] {
        let s = Int(tiempo.rounded())
        return [
            ("Tiempo", String(format: "%ld:%02ld", s / 60, s % 60)),
            ("Altura", "≈ \(Self.metros(alturaMax)) m"),
            ("Movimientos", "\(apoyos.count)"),
            ("Pausas", "\(pausas.count)"),
            ("Subida", "\(Self.metros(subidaPorMinuto)) m/min"),
            ("Tramo más rápido", tramo.map { "\(Self.metros($0.metros)) m en 2 s" } ?? "–"),
        ]
    }
}

// MARK: - guardar la serie de poses (modo en vivo)

/// Las poses de una grabación en vivo, en un JSON junto al .mov: así la tarjeta de la ruta no recalcula nada.
struct SerieGuardada: Codable {
    var ancho: Double
    var alto: Double
    var t: [Double]
    /// 19 × (x, y, confianza) por muestra; nil si no se veía a nadie.
    var poses: [[Double]?]

    static func guarda(_ serie: [(Double, PoseEsc?)], tam: CGSize, en url: URL) -> Bool {
        guard !serie.isEmpty else { return false }
        let t0 = serie[0].0
        var tiempos: [Double] = []
        var poses: [[Double]?] = []
        for (t, pose) in serie {
            tiempos.append(t - t0)
            if let pose {
                var plano: [Double] = []
                plano.reserveCapacity(PoseEsc.n * 3)
                for i in 0..<PoseEsc.n {
                    plano.append(Double(pose.p[i].x))
                    plano.append(Double(pose.p[i].y))
                    plano.append(Double(pose.c[i]))
                }
                poses.append(plano)
            } else {
                poses.append(nil)
            }
        }
        let s = SerieGuardada(ancho: Double(tam.width), alto: Double(tam.height), t: tiempos, poses: poses)
        guard let datos = try? JSONEncoder().encode(s) else { return false }
        return (try? datos.write(to: url, options: .atomic)) != nil
    }

    static func lee(_ url: URL) -> ([(Double, PoseEsc?)], CGSize)? {
        guard let datos = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(SerieGuardada.self, from: datos), s.t.count == s.poses.count else { return nil }
        var r: [(Double, PoseEsc?)] = []
        for (t, plano) in zip(s.t, s.poses) {
            guard let plano, plano.count == PoseEsc.n * 3 else {
                r.append((t, nil))
                continue
            }
            var p = [CGPoint](repeating: .zero, count: PoseEsc.n)
            var c = [Float](repeating: 0, count: PoseEsc.n)
            for i in 0..<PoseEsc.n {
                p[i] = CGPoint(x: plano[i * 3], y: plano[i * 3 + 1])
                c[i] = Float(plano[i * 3 + 2])
            }
            r.append((t, PoseEsc(p: p, c: c)))
        }
        return (r, CGSize(width: s.ancho, height: s.alto))
    }
}

// MARK: - pintar la ruta (CGContext con la y hacia abajo)

enum PintorRuta {
    /// Lleva un punto de la imagen al rectángulo, encajando toda la ruta (y los apoyos) sin deformarla.
    static func encaje(_ r: RutaEsc, en rect: CGRect) -> (CGPoint) -> CGPoint {
        let todos = r.puntos.map(\.p) + r.apoyos.map(\.p)
        guard let minX = todos.map(\.x).min(), let maxX = todos.map(\.x).max(),
              let minY = todos.map(\.y).min(), let maxY = todos.map(\.y).max() else { return { _ in CGPoint(x: rect.midX, y: rect.midY) } }
        let lado = max(maxX - minX, maxY - minY, r.tam.height * 0.15)
        let escala = min(rect.width, rect.height) / lado
        let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
        return { p in CGPoint(x: rect.midX + (p.x - cx) * escala, y: rect.midY + (p.y - cy) * escala) }
    }

    /// Lento (acento) → medio (aviso) → rápido (peligro), como el ritmo de Strava.
    static func color(_ v: Double, _ vMax: Double, _ c: ColoresEsq) -> UIColor {
        let f = max(0, min(1, v / vMax))
        return f < 0.5 ? mezcla(c.hueso, c.centro, f * 2) : mezcla(c.centro, c.rapido, (f - 0.5) * 2)
    }

    static func mezcla(_ a: UIColor, _ b: UIColor, _ w: Double) -> UIColor {
        var ra: CGFloat = 0, ga: CGFloat = 0, ba: CGFloat = 0, aa: CGFloat = 0
        var rb: CGFloat = 0, gb: CGFloat = 0, bb: CGFloat = 0, ab: CGFloat = 0
        a.getRed(&ra, green: &ga, blue: &ba, alpha: &aa)
        b.getRed(&rb, green: &gb, blue: &bb, alpha: &ab)
        let f = CGFloat(max(0, min(1, w)))
        return UIColor(red: ra + (rb - ra) * f, green: ga + (gb - ga) * f, blue: ba + (bb - ba) * f, alpha: 1)
    }

    static func cuadricula(_ ctx: CGContext, _ rect: CGRect, _ c: ColoresEsq, paso: CGFloat = 54) {
        ctx.saveGState()
        ctx.setStrokeColor(c.punto.withAlphaComponent(0.06).cgColor)
        ctx.setLineWidth(1)
        var x = rect.minX
        while x <= rect.maxX {
            ctx.move(to: CGPoint(x: x, y: rect.minY))
            ctx.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += paso
        }
        var y = rect.minY
        while y <= rect.maxY {
            ctx.move(to: CGPoint(x: rect.minX, y: y))
            ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += paso
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// El trazo hasta `hasta` (tiempo del vídeo; nil = entero), con salida, top, apoyos y el punto actual.
    static func trazo(_ ctx: CGContext, _ r: RutaEsc, en rect: CGRect, hasta: Double? = nil, colores c: ColoresEsq,
                      grosor g: CGFloat = 8, marcas: Bool = true) {
        let a = encaje(r, en: rect)
        let ps = hasta.map { h in r.puntos.filter { $0.t <= h } } ?? r.puntos
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        // la ruta entera, tenue, por debajo (en el mini-mapa se ve lo que queda)
        if hasta != nil, r.puntos.count > 1 {
            ctx.setStrokeColor(c.punto.withAlphaComponent(0.18).cgColor)
            ctx.setLineWidth(g * 0.6)
            ctx.move(to: a(r.puntos[0].p))
            for q in r.puntos.dropFirst() { ctx.addLine(to: a(q.p)) }
            ctx.strokePath()
        }
        if ps.count > 1 {
            ctx.setStrokeColor(c.borde.withAlphaComponent(0.7).cgColor)
            ctx.setLineWidth(g + 5)
            ctx.move(to: a(ps[0].p))
            for q in ps.dropFirst() { ctx.addLine(to: a(q.p)) }
            ctx.strokePath()
            ctx.setLineWidth(g)
            for k in 1..<ps.count {
                ctx.setStrokeColor(color(ps[k].v, r.vMax, c).cgColor)
                ctx.move(to: a(ps[k - 1].p))
                ctx.addLine(to: a(ps[k].p))
                ctx.strokePath()
            }
        }
        // los apoyos
        let ra = max(3, g * 0.7)
        for ap in r.apoyos where hasta == nil || ap.t <= (hasta ?? 0) {
            let q = a(ap.p)
            ctx.setFillColor(c.borde.cgColor)
            ctx.fillEllipse(in: CGRect(x: q.x - ra - 2, y: q.y - ra - 2, width: (ra + 2) * 2, height: (ra + 2) * 2))
            ctx.setFillColor(c.punto.withAlphaComponent(0.9).cgColor)
            ctx.fillEllipse(in: CGRect(x: q.x - ra, y: q.y - ra, width: ra * 2, height: ra * 2))
        }
        guard marcas, let primero = r.puntos.first else { return }
        // salida
        punto(ctx, a(primero.p), g * 1.6, relleno: c.hueso, borde: c.punto)
        // top: lo más alto
        if hasta == nil, let top = r.puntos.max(by: { $0.altura < $1.altura }) {
            punto(ctx, a(top.p), g * 1.6, relleno: c.rapido, borde: c.punto)
        }
        // dónde va ahora
        if hasta != nil, let ultimo = ps.last {
            punto(ctx, a(ultimo.p), g * 1.3, relleno: c.centro, borde: c.punto)
        }
    }

    private static func punto(_ ctx: CGContext, _ q: CGPoint, _ r: CGFloat, relleno: UIColor, borde: UIColor) {
        ctx.setFillColor(borde.cgColor)
        ctx.fillEllipse(in: CGRect(x: q.x - r - 3, y: q.y - r - 3, width: (r + 3) * 2, height: (r + 3) * 2))
        ctx.setFillColor(relleno.cgColor)
        ctx.fillEllipse(in: CGRect(x: q.x - r, y: q.y - r, width: r * 2, height: r * 2))
    }

    /// El perfil de «elevación»: la altura en el tiempo, con las pausas sombreadas.
    static func perfil(_ ctx: CGContext, _ r: RutaEsc, en rect: CGRect, colores c: ColoresEsq) {
        guard r.puntos.count > 1, r.tiempo > 0 else { return }
        let t0 = r.t0
        let tope = max(r.alturaMax, 0.5)
        func pt(_ q: RutaEsc.Punto) -> CGPoint {
            CGPoint(x: rect.minX + CGFloat((q.t - t0) / r.tiempo) * rect.width,
                    y: rect.maxY - CGFloat(max(0, q.altura) / tope) * rect.height)
        }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setFillColor(c.punto.withAlphaComponent(0.08).cgColor)
        for (a, b) in r.pausas {
            let x0 = rect.minX + CGFloat((a - t0) / r.tiempo) * rect.width
            let x1 = rect.minX + CGFloat((b - t0) / r.tiempo) * rect.width
            ctx.fill(CGRect(x: x0, y: rect.minY, width: max(2, x1 - x0), height: rect.height))
        }
        let area = CGMutablePath()
        area.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for q in r.puntos { area.addLine(to: pt(q)) }
        area.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        area.closeSubpath()
        ctx.addPath(area)
        ctx.setFillColor(c.hueso.withAlphaComponent(0.3).cgColor)
        ctx.fillPath()
        let linea = CGMutablePath()
        linea.move(to: pt(r.puntos[0]))
        for q in r.puntos.dropFirst() { linea.addLine(to: pt(q)) }
        ctx.addPath(linea)
        ctx.setStrokeColor(c.hueso.cgColor)
        ctx.setLineWidth(4)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        ctx.setStrokeColor(c.punto.withAlphaComponent(0.25).cgColor)
        ctx.setLineWidth(1.5)
        ctx.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        ctx.strokePath()
    }

    // MARK: la tarjeta entera

    static func letra(_ tam: CGFloat, _ peso: UIFont.Weight, _ familia: String?) -> UIFont {
        if let familia {
            let d = UIFontDescriptor(fontAttributes: [.family: familia, .traits: [UIFontDescriptor.TraitKey.weight: peso.rawValue]])
            return UIFont(descriptor: d, size: tam)
        }
        return .systemFont(ofSize: tam, weight: peso)
    }

    private static func escribe(_ s: String, en p: CGPoint, _ tam: CGFloat, _ peso: UIFont.Weight, _ color: UIColor,
                                _ familia: String?, ancho: CGFloat = 1000, kern: CGFloat = 0) {
        let a = NSAttributedString(string: s, attributes: [.font: letra(tam, peso, familia), .foregroundColor: color, .kern: kern])
        a.draw(with: CGRect(x: p.x, y: p.y, width: ancho, height: tam * 1.4),
               options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
    }

    /// «Ruta del intento»: 1080×1920 (historia) o 1080×1080 (cuadrada).
    static func tarjeta(_ r: RutaEsc, tam: CGSize, colores c: ColoresEsq, titulo: String, fecha: String) -> UIImage {
        let formato = UIGraphicsImageRendererFormat()
        formato.scale = 1
        formato.opaque = true
        return UIGraphicsImageRenderer(size: tam, format: formato).image { contexto in
            let ctx = contexto.cgContext
            let w = tam.width, h = tam.height
            let cuadrada = h < w * 1.3
            ctx.setFillColor(c.borde.cgColor)
            ctx.fill(CGRect(origin: .zero, size: tam))
            cuadricula(ctx, CGRect(origin: .zero, size: tam), c)
            let m: CGFloat = 64
            let arriba: CGFloat = cuadrada ? 56 : 130
            escribe("RUTA DEL INTENTO", en: CGPoint(x: m, y: arriba), 28, .semibold, c.hueso, c.familia, kern: 3)
            escribe(titulo, en: CGPoint(x: m, y: arriba + 40), cuadrada ? 60 : 76, .bold, c.punto, c.familia, ancho: w - m * 2)
            escribe(fecha, en: CGPoint(x: m, y: arriba + (cuadrada ? 116 : 140)), 30, .regular, c.suave, c.familia)

            let cifras = r.cifras
            if cuadrada {
                let mapa = CGRect(x: m, y: 250, width: 470, height: 470)
                tarjetaMapa(ctx, r, mapa, c)
                let perfilR = CGRect(x: m, y: 760, width: w - m * 2, height: 120)
                perfil(ctx, r, en: perfilR, colores: c)
                // cifras a la derecha del mapa (4) y debajo del perfil (2)
                for (i, (k, v)) in cifras.prefix(4).enumerated() {
                    cifra(k, v, en: CGPoint(x: 580, y: 260 + CGFloat(i) * 112), c, grande: 50)
                }
                for (i, (k, v)) in cifras.dropFirst(4).enumerated() {
                    cifra(k, v, en: CGPoint(x: m + CGFloat(i) * 480, y: 910), c, grande: 44)
                }
            } else {
                let mapa = CGRect(x: m, y: 380, width: w - m * 2, height: 860)
                tarjetaMapa(ctx, r, mapa, c)
                escribe("Altura en el tiempo", en: CGPoint(x: m, y: 1270), 28, .semibold, c.suave, c.familia)
                perfil(ctx, r, en: CGRect(x: m, y: 1320, width: w - m * 2, height: 170), colores: c)
                for (i, (k, v)) in cifras.enumerated() {
                    let col = CGFloat(i % 3), fila = CGFloat(i / 3)
                    cifra(k, v, en: CGPoint(x: m + col * 330, y: 1540 + fila * 150), c, grande: i == 5 ? 40 : 56)
                }
            }
            escribe("Tom", en: CGPoint(x: w - m - 90, y: h - (cuadrada ? 60 : 90)), 34, .bold, c.suave, c.familia)
        }
    }

    private static func tarjetaMapa(_ ctx: CGContext, _ r: RutaEsc, _ mapa: CGRect, _ c: ColoresEsq) {
        let fondo = UIBezierPath(roundedRect: mapa, cornerRadius: 28)
        ctx.addPath(fondo.cgPath)
        ctx.setFillColor(c.carta.cgColor)
        ctx.fillPath()
        ctx.saveGState()
        ctx.addPath(fondo.cgPath)
        ctx.clip()
        cuadricula(ctx, mapa, c, paso: 40)
        ctx.restoreGState()
        trazo(ctx, r, en: mapa.insetBy(dx: 50, dy: 50), colores: c, grosor: 10)
    }

    private static func cifra(_ k: String, _ v: String, en p: CGPoint, _ c: ColoresEsq, grande: CGFloat) {
        escribe(k.uppercased(), en: p, 22, .semibold, c.suave, c.familia, ancho: 440, kern: 1.5)
        escribe(v, en: CGPoint(x: p.x, y: p.y + 30), grande, .bold, c.punto, c.familia, ancho: 440)
    }

    /// El mini-mapa del vídeo: la ruta dibujándose a la vez que el vídeo.
    static func miniMapa(_ ctx: CGContext, _ r: RutaEsc, en rect: CGRect, hasta: Double, colores c: ColoresEsq) {
        ctx.saveGState()
        let fondo = UIBezierPath(roundedRect: rect, cornerRadius: 28).cgPath
        ctx.addPath(fondo)
        ctx.setFillColor(c.borde.withAlphaComponent(0.6).cgColor)
        ctx.fillPath()
        ctx.restoreGState()
        trazo(ctx, r, en: rect.insetBy(dx: 30, dy: 30), hasta: hasta, colores: c, grosor: 6)
    }
}

// MARK: - la hoja de la tarjeta

struct RutaParaHoja: Identifiable {
    let id = UUID()
    let ruta: RutaEsc
    let titulo: String
}

struct HojaTarjetaRuta: View {
    let ruta: RutaEsc
    let titulo: String
    @Environment(\.dismiss) private var cerrar
    @State private var cuadrada = false
    @State private var imagen: UIImage?
    @State private var compartir = false
    @State private var guardando = false
    @State private var aviso: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Tema.Espacio.l) {
                    Picker("Formato", selection: $cuadrada) {
                        Text("Historia 9:16").tag(false)
                        Text("Cuadrada").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Group {
                        if let imagen {
                            Image(uiImage: imagen).resizable().scaledToFit()
                        } else {
                            Rectangle().fill(Tema.carta2).aspectRatio(cuadrada ? 1 : 9.0 / 16.0, contentMode: .fit)
                        }
                    }
                    .frame(maxHeight: 520)
                    .clipShape(RoundedRectangle(cornerRadius: Tema.Radio.carta))
                    .accessibilityLabel("Tarjeta de la ruta: \(ruta.cifras.map { "\($0.0) \($0.1)" }.joined(separator: ", "))")
                    Button {
                        compartir = imagen != nil
                    } label: {
                        Label("Compartir", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(BotonEnt(principal: true))
                    Button {
                        guarda()
                    } label: {
                        Label(guardando ? "Guardando…" : "Guardar en Fotos", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(BotonEnt())
                    .disabled(guardando || imagen == nil)
                    if let aviso {
                        Text(aviso).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                    }
                }
                .padding(Tema.Espacio.l)
            }
            .background(Tema.fondo)
            .navigationTitle("Tarjeta de la ruta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { cerrar() }
                }
            }
            .task(id: cuadrada) {
                let tam = cuadrada ? CGSize(width: 1080, height: 1080) : CGSize(width: 1080, height: 1920)
                imagen = PintorRuta.tarjeta(ruta, tam: tam, colores: ColoresEsq.delTema(), titulo: titulo,
                                            fecha: Self.fecha())
            }
            .sheet(isPresented: $compartir) {
                if let imagen {
                    HojaCompartir(cosas: [imagen]).presentationDetents([.medium, .large])
                }
            }
        }
    }

    static func fecha() -> String {
        let t = Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "es_ES")))
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    private func guarda() {
        guard let imagen else { return }
        guardando = true
        Task {
            do {
                try await Fototeca.guarda(imagen: imagen)
                aviso = "Guardada en Fotos."
                Haptica.shared.toca(.marcar)
            } catch {
                aviso = error.localizedDescription
                Haptica.shared.toca(.error)
            }
            guardando = false
        }
    }
}
