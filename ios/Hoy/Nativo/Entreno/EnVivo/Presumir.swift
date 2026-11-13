import AVFoundation
import CoreImage
import PhotosUI
import SwiftUI
import UIKit
import Vision

/// El vídeo para presumir, hecho entero en el iPhone en unos segundos: vertical 9:16 (1080×1920, listo para
/// historias), con el esqueleto y la estela del centro de gravedad, cámara lenta sola en el tramo en que más se
/// mueven las manos, el rótulo del bloque (nombre, color, nivel, «Intento nº») y «¡Encadenado!» si lo marcas.
/// Dos pasadas: la primera saca la pose con Vision (unas 15 veces por segundo, e interpola), la segunda monta.
struct OpcionesPresumir: @unchecked Sendable {
    var cabecera: CGImage?
    var encadenado: CGImage?
    var lenta: CGImage?
    var marca: CGImage?
    var colores: ColoresEsq
    /// La ruta (gráfico tipo Strava): el mini-mapa en una esquina y el resumen de 2 s al final.
    var miniMapa = true
    var resumen = true
    var titulo = ""
    var fecha = ""
}

/// Lo que sale de montar: el vídeo y la ruta (para la tarjeta compartible).
struct HechoPresumir: @unchecked Sendable {
    var url: URL
    var ruta: RutaEsc?
}

enum MontadorPresumir {
    static let ancho = 1080
    static let alto = 1920
    static let fps: Int32 = 30
    static let lenta = 0.4

    private struct Muestra {
        var t: Double
        var pose: PoseEsc?
        var centro: CGPoint?   // 0-1
    }

    static func monta(_ url: URL, _ o: OpcionesPresumir,
                      progreso: @escaping @Sendable (Double, String) -> Void) async throws -> HechoPresumir {
        let asset = AVURLAsset(url: url)
        guard let pista = try await asset.loadTracks(withMediaType: .video).first else {
            throw APIError(mensaje: "Ese vídeo no tiene imagen")
        }
        let (tamN, giro, fpsN) = try await pista.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        let duracion = try await asset.load(.duration).seconds
        guard duracion.isFinite, duracion > 0.3 else { throw APIError(mensaje: "El vídeo es demasiado corto") }
        let orientacion = Self.orientacion(giro)
        let derecho: CGSize = [.left, .right].contains(orientacion)
            ? CGSize(width: abs(tamN.height), height: abs(tamN.width))
            : CGSize(width: abs(tamN.width), height: abs(tamN.height))

        // 1.ª pasada: la pose
        progreso(0, "Sacando el esqueleto…")
        let muestras = try analiza(asset, pista, orientacion: orientacion, tam: derecho, fps: Double(fpsN),
                                   duracion: duracion, progreso: progreso)
        guard muestras.contains(where: { $0.pose != nil }) else {
            throw APIError(mensaje: "No se ve a nadie en el vídeo. Prueba con uno en el que se te vea entero.")
        }
        let t0 = muestras.first?.t ?? 0, t1 = max(t0 + 0.1, muestras.last?.t ?? duracion)

        // la cámara lenta: el tramo en que más se mueven las manos
        let tramo = tramoRapido(muestras, tam: derecho)
        let ruta = RutaEsc(muestras.map { ($0.t, $0.pose) }, tam: derecho)
        func ritmo(_ t: Double) -> Double {
            guard let tr = tramo else { return 1 }
            let (a, b) = tr
            let rampa = 0.25
            if t < a - rampa || t > b + rampa { return 1 }
            if t >= a && t <= b { return lenta }
            let d = t < a ? (a - t) / rampa : (t - b) / rampa
            return lenta + (1 - lenta) * d
        }
        // tiempo de salida → tiempo del vídeo
        var tabla: [(fuente: Double, salida: Double)] = [(t0, 0)]
        var s = t0, tau = 0.0
        let paso = 1.0 / 240
        while s < t1 {
            tau += paso / ritmo(s)
            s += paso
            tabla.append((s, tau))
        }
        let total = tau
        let n = max(1, Int(total * Double(fps)))
        // el resumen de actividad: 2 s al final con la tarjeta de la ruta
        let tarjeta: CGImage? = o.resumen ? ruta.flatMap {
            PintorRuta.tarjeta($0, tam: CGSize(width: ancho, height: alto), colores: o.colores, titulo: o.titulo,
                               fecha: o.fecha).cgImage
        } : nil
        let extra = tarjeta == nil ? 0 : Int(fps) * 2
        func fuente(_ salida: Double) -> Double {
            var lo = 0, hi = tabla.count - 1
            while hi - lo > 1 {
                let m = (lo + hi) / 2
                if tabla[m].salida <= salida { lo = m } else { hi = m }
            }
            let a = tabla[lo], b = tabla[hi]
            let w = b.salida > a.salida ? (salida - a.salida) / (b.salida - a.salida) : 0
            return a.fuente + (b.fuente - a.fuente) * max(0, min(1, w))
        }

        // 2.ª pasada: montar
        let destino = ArchivosEscalada.carpeta.appendingPathComponent("presumir-\(UUID().uuidString.prefix(8)).mp4")
        try? FileManager.default.removeItem(at: destino)
        let escritor = try AVAssetWriter(outputURL: destino, fileType: .mp4)
        let entrada = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: ancho, AVVideoHeightKey: alto,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 12_000_000,
                                              AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
        ])
        entrada.expectsMediaDataInRealTime = false
        let adaptador = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: entrada, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: ancho, kCVPixelBufferHeightKey as String: alto,
        ])
        guard escritor.canAdd(entrada) else { throw APIError(mensaje: "El iPhone no deja escribir el vídeo") }
        escritor.add(entrada)
        guard escritor.startWriting() else {
            throw escritor.error ?? APIError(mensaje: "El iPhone no deja escribir el vídeo")
        }
        escritor.startSession(atSourceTime: .zero)

        let lector = try AVAssetReader(asset: asset)
        let salida = AVAssetReaderTrackOutput(track: pista, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ])
        salida.alwaysCopiesSampleData = false
        lector.add(salida)
        guard lector.startReading() else { throw lector.error ?? APIError(mensaje: "No se puede leer el vídeo") }
        func lee() -> (Double, CVPixelBuffer)? {
            while let sb = salida.copyNextSampleBuffer() {
                if let pb = CMSampleBufferGetImageBuffer(sb) {
                    return (CMSampleBufferGetPresentationTimeStamp(sb).seconds, pb)
                }
            }
            return nil
        }

        let ci = CIContext(options: [.cacheIntermediates: false])
        let rect = CGRect(x: 0, y: 0, width: ancho, height: alto)
        let negro = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: rect)
        let sombras = Self.sombras(rect)
        let espacio = CGColorSpaceCreateDeviceRGB()
        let sc = max(CGFloat(ancho) / derecho.width, CGFloat(alto) / derecho.height)
        let ws = derecho.width * sc, hs = derecho.height * sc
        var camX: CGFloat?
        var camY: CGFloat?
        var previo: (Double, CVPixelBuffer)?
        var siguiente = lee()
        var ultimoAviso = -1.0

        for k in 0..<n {
            try Task.checkCancellation()
            // el escritor va a su ritmo: se espera fuera del autoreleasepool (no se puede esperar dentro)
            while !entrada.isReadyForMoreMediaData {
                guard escritor.status == .writing else {
                    throw escritor.error ?? APIError(mensaje: "Se ha cortado la escritura del vídeo")
                }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            // cada fotograma suelta su memoria al acabar (CIImage, búferes): si no, un vídeo largo agota la RAM
            let sigue = try autoreleasepool { () throws -> Bool in
                let tSalida = Double(k) / Double(fps)
                let tf = fuente(tSalida)
                while let sig = siguiente, sig.0 <= tf {
                    previo = sig
                    siguiente = lee()
                }
                guard let a = previo ?? siguiente else { return false }
                let r = ritmo(tf)
                var imagen = derecha(a.1, orientacion)
                if r < 0.99, let pr = previo, let sig = siguiente, sig.0 > pr.0 {
                    // a cámara lenta se funden los dos fotogramas vecinos: va suave aunque el vídeo sea de 30 fps
                    let w = max(0, min(1, (tf - pr.0) / (sig.0 - pr.0)))
                    imagen = imagen.applyingFilter("CIDissolveTransition", parameters: [
                        kCIInputTargetImageKey: derecha(sig.1, orientacion), kCIInputTimeKey: w,
                    ])
                }
                // el encuadre sigue al centro de gravedad, sin sacudidas
                let pose = poseEn(tf, muestras)
                let c = pose?.centro(derecho).map { CGPoint(x: $0.x / derecho.width, y: $0.y / derecho.height) }
                let objX = max(0, min(ws - CGFloat(ancho), (c?.x ?? 0.5) * ws - CGFloat(ancho) / 2))
                let objY = max(0, min(hs - CGFloat(alto), (c?.y ?? 0.5) * hs - CGFloat(alto) * 0.55))
                camX = camX.map { $0 + (objX - $0) * 0.08 } ?? objX
                camY = camY.map { $0 + (objY - $0) * 0.08 } ?? objY
                let cx = camX ?? 0, cy = camY ?? 0
                let encuadrada = imagen
                    .transformed(by: CGAffineTransform(scaleX: sc, y: sc))
                    .transformed(by: CGAffineTransform(translationX: -cx, y: -(hs - cy - CGFloat(alto))))
                    .composited(over: negro)
                let compuesta = sombras.composited(over: encuadrada).cropped(to: rect)

                guard let pool = adaptador.pixelBufferPool else { throw APIError(mensaje: "El iPhone no deja escribir el vídeo") }
                var pbSalida: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pbSalida)
                guard let pbSalida else { return true }
                ci.render(compuesta, to: pbSalida, bounds: rect, colorSpace: espacio)

                CVPixelBufferLockBaseAddress(pbSalida, [])
                if let base = CVPixelBufferGetBaseAddress(pbSalida),
                   let ctx = CGContext(data: base, width: ancho, height: alto, bitsPerComponent: 8,
                                       bytesPerRow: CVPixelBufferGetBytesPerRow(pbSalida), space: espacio,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                    ctx.translateBy(x: 0, y: CGFloat(alto))
                    ctx.scaleBy(x: 1, y: -1)
                    let estela = muestras.filter { $0.t <= tf && tf - $0.t <= 1.6 }
                        .compactMap { m in m.centro.map { PuntoEstela(t: m.t, p: $0) } }
                    PintorEsq.pinta(ctx, pose: pose, estela: estela, ahora: tf, duracionEstela: 1.6, tamImagen: derecho,
                                    escala: sc, aPx: { CGPoint(x: $0.x * ws - cx, y: $0.y * hs - cy) }, colores: o.colores)
                    rotulos(ctx, o, tSalida: tSalida, total: total, ritmo: r)
                    if o.miniMapa, let ruta {
                        PintorRuta.miniMapa(ctx, ruta, en: CGRect(x: 48, y: CGFloat(alto) - 300 - 150, width: 300, height: 300),
                                            hasta: tf, colores: o.colores)
                    }
                }
                CVPixelBufferUnlockBaseAddress(pbSalida, [])
                adaptador.append(pbSalida, withPresentationTime: CMTime(value: Int64(k), timescale: fps))
                let p = 0.5 + 0.5 * Double(k + 1) / Double(n + extra)
                if p - ultimoAviso >= 0.01 {
                    ultimoAviso = p
                    progreso(p, "Montando el vídeo…")
                }
                return true
            }
            if !sigue { break }
        }
        lector.cancelReading()
        if let tarjeta {
            for j in 0..<extra {
                try Task.checkCancellation()
                while !entrada.isReadyForMoreMediaData {
                    guard escritor.status == .writing else {
                        throw escritor.error ?? APIError(mensaje: "Se ha cortado la escritura del vídeo")
                    }
                    try await Task.sleep(nanoseconds: 2_000_000)
                }
                autoreleasepool {
                    guard let pool = adaptador.pixelBufferPool else { return }
                    var pb: CVPixelBuffer?
                    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
                    guard let pb else { return }
                    CVPixelBufferLockBaseAddress(pb, [])
                    if let base = CVPixelBufferGetBaseAddress(pb),
                       let ctx = CGContext(data: base, width: ancho, height: alto, bitsPerComponent: 8,
                                           bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: espacio,
                                           bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                        ctx.setFillColor(UIColor.black.cgColor)
                        ctx.fill(rect)
                        ctx.setAlpha(CGFloat(min(1, Double(j + 1) / 9)))
                        // sin girar: la tarjeta es un CGImage y el contexto está con la y hacia arriba
                        ctx.draw(tarjeta, in: rect)
                    }
                    CVPixelBufferUnlockBaseAddress(pb, [])
                    adaptador.append(pb, withPresentationTime: CMTime(value: Int64(n + j), timescale: fps))
                }
                progreso(0.5 + 0.5 * Double(n + j + 1) / Double(n + extra), "Montando el resumen…")
            }
        }
        entrada.markAsFinished()
        await escritor.finishWriting()
        guard escritor.status == .completed else {
            throw escritor.error ?? APIError(mensaje: "No se ha podido terminar el vídeo")
        }
        progreso(1, "Listo")
        return HechoPresumir(url: destino, ruta: ruta)
    }

    // MARK: la 1.ª pasada

    private static func analiza(_ asset: AVAsset, _ pista: AVAssetTrack, orientacion: CGImagePropertyOrientation,
                                tam: CGSize, fps: Double, duracion: Double,
                                progreso: @Sendable (Double, String) -> Void) throws -> [Muestra] {
        let lector = try AVAssetReader(asset: asset)
        let salida = AVAssetReaderTrackOutput(track: pista, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ])
        salida.alwaysCopiesSampleData = false
        lector.add(salida)
        guard lector.startReading() else { throw lector.error ?? APIError(mensaje: "No se puede leer el vídeo") }
        let salto = max(1, Int((max(fps, 15) / 15).rounded()))
        let peticion = VNDetectHumanBodyPoseRequest()
        var suavizador = SuavizadorPose()
        var r: [Muestra] = []
        var i = 0
        var ultimoAviso = -1.0
        var ultimoCentro: (t: Double, p: CGPoint)?
        while true {
            try Task.checkCancellation()
            // cada fotograma suelta su memoria al acabar (búferes, resultados de Vision)
            let sigue = autoreleasepool { () -> Bool in
                guard let sb = salida.copyNextSampleBuffer() else { return false }
                defer { i += 1 }
                guard i % salto == 0, let pb = CMSampleBufferGetImageBuffer(sb) else { return true }
                let t = CMSampleBufferGetPresentationTimeStamp(sb).seconds
                let manejador = VNImageRequestHandler(cvPixelBuffer: pb, orientation: orientacion, options: [:])
                // el escalador: el más cercano al de antes, para no saltar a quien mira de pie
                let cerca = ultimoCentro.flatMap { t - $0.t < 1.5 ? $0.p : nil }
                let cruda: PoseEsc? = (try? manejador.perform([peticion])) != nil
                    ? PoseEsc(peticion.results, cerca: cerca) : nil
                if let c = cruda?.centroTronco { ultimoCentro = (t, c) }
                let pose = suavizador.filtra(cruda, t)
                let vale = pose.hayCuerpo
                let c = vale ? pose.centro(tam).map { CGPoint(x: $0.x / tam.width, y: $0.y / tam.height) } : nil
                r.append(Muestra(t: t, pose: vale ? pose : nil, centro: c))
                let p = 0.5 * min(1, t / duracion)
                if p - ultimoAviso >= 0.01 {
                    ultimoAviso = p
                    progreso(p, "Sacando el esqueleto…")
                }
                return true
            }
            if !sigue { break }
        }
        lector.cancelReading()
        return r
    }

    /// La pose en un instante cualquiera, interpolando entre las dos muestras de Vision que lo rodean.
    private static func poseEn(_ t: Double, _ m: [Muestra]) -> PoseEsc? {
        guard !m.isEmpty else { return nil }
        var lo = 0, hi = m.count - 1
        if t <= m[0].t { return m[0].pose }
        if t >= m[hi].t { return m[hi].pose }
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if m[mid].t <= t { lo = mid } else { hi = mid }
        }
        let a = m[lo], b = m[hi]
        switch (a.pose, b.pose) {
        case let (pa?, pb?):
            let w = b.t > a.t ? (t - a.t) / (b.t - a.t) : 0
            return pa.mezcla(pb, CGFloat(w))
        case let (pa?, nil): return t - a.t < 0.3 ? pa : nil
        case let (nil, pb?): return b.t - t < 0.3 ? pb : nil
        default: return nil
        }
    }

    /// El tramo (inicio, fin) en que las manos van más rápido, en troncos por segundo; nil si es corto o tranquilo.
    private static func tramoRapido(_ m: [Muestra], tam: CGSize) -> (Double, Double)? {
        guard let primero = m.first?.t, let ultimo = m.last?.t, ultimo - primero >= 3 else { return nil }
        var velocidad: [(Double, Double)] = []
        for k in 1..<m.count {
            guard let a = m[k - 1].pose, let b = m[k].pose, let tronco = b.largoTronco(tam), m[k].t > m[k - 1].t else { continue }
            var v = 0.0
            for i in [10, 11] where a.ve(i) && b.ve(i) {
                let d = hypot((b.p[i].x - a.p[i].x) * tam.width, (b.p[i].y - a.p[i].y) * tam.height)
                v = max(v, Double(d / tronco) / (m[k].t - m[k - 1].t))
            }
            velocidad.append((m[k].t, min(v, 12)))
        }
        guard velocidad.count > 4 else { return nil }
        let largo = min(2.0, (ultimo - primero) * 0.35)
        var mejor: (Double, Double, Double)?
        for (k, (ta, _)) in velocidad.enumerated() {
            guard ta + largo <= ultimo else { break }
            var suma = 0.0, cuenta = 0
            for (t, v) in velocidad[k...] {
                if t > ta + largo { break }
                suma += v
                cuenta += 1
            }
            let media = cuenta > 0 ? suma / Double(cuenta) : 0
            if media > (mejor?.2 ?? 0) { mejor = (ta, ta + largo, media) }
        }
        guard let mejor, mejor.2 >= 0.4 else { return nil }
        return (mejor.0, mejor.1)
    }

    // MARK: piezas

    static func orientacion(_ t: CGAffineTransform) -> CGImagePropertyOrientation {
        func cerca(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.01 }
        if cerca(t.a, 0) && cerca(t.b, 1) && cerca(t.c, -1) && cerca(t.d, 0) { return .right }
        if cerca(t.a, 0) && cerca(t.b, -1) && cerca(t.c, 1) && cerca(t.d, 0) { return .left }
        if cerca(t.a, -1) && cerca(t.d, -1) { return .down }
        return .up
    }

    private static func derecha(_ pb: CVPixelBuffer, _ o: CGImagePropertyOrientation) -> CIImage {
        let im = CIImage(cvPixelBuffer: pb).oriented(o)
        return im.transformed(by: CGAffineTransform(translationX: -im.extent.minX, y: -im.extent.minY))
    }

    /// Un velo oscuro arriba y abajo para que se lean los rótulos sobre cualquier pared.
    private static func sombras(_ rect: CGRect) -> CIImage {
        func degradado(_ desde: CGFloat, _ hasta: CGFloat, _ a: CGFloat) -> CIImage {
            let f = CIFilter(name: "CILinearGradient", parameters: [
                "inputPoint0": CIVector(x: 0, y: desde), "inputPoint1": CIVector(x: 0, y: hasta),
                "inputColor0": CIColor(red: 0, green: 0, blue: 0, alpha: a),
                "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0),
            ])
            return (f?.outputImage ?? CIImage.empty()).cropped(to: rect)
        }
        return degradado(rect.height, rect.height - 520, 0.6).composited(over: degradado(0, 380, 0.5))
    }

    private static func rotulos(_ ctx: CGContext, _ o: OpcionesPresumir, tSalida: Double, total: Double, ritmo: Double) {
        func dibuja(_ im: CGImage, _ r: CGRect, alfa: CGFloat = 1) {
            ctx.saveGState()
            ctx.setAlpha(alfa)
            ctx.translateBy(x: 0, y: r.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(im, in: CGRect(x: r.minX, y: 0, width: r.width, height: r.height))
            ctx.restoreGState()
        }
        let w = CGFloat(ancho), h = CGFloat(alto)
        var y: CGFloat = 0
        if let c = o.cabecera {
            let entra = CGFloat(min(1, tSalida / 0.4))
            dibuja(c, CGRect(x: 0, y: -30 * (1 - entra), width: CGFloat(c.width), height: CGFloat(c.height)), alfa: entra)
            y = CGFloat(c.height)
        }
        if ritmo < 0.99, let l = o.lenta {
            let a = CGFloat((1 - ritmo) / (1 - lenta))
            dibuja(l, CGRect(x: w - CGFloat(l.width) - 56, y: y + 20, width: CGFloat(l.width), height: CGFloat(l.height)), alfa: a)
        }
        if let e = o.encadenado, tSalida >= total - 2.2 {
            let d = CGFloat(min(1, (tSalida - (total - 2.2)) / 0.3))
            let escala = 0.75 + 0.25 * d
            let ew = CGFloat(e.width) * escala, eh = CGFloat(e.height) * escala
            dibuja(e, CGRect(x: (w - ew) / 2, y: h * 0.66 - eh / 2, width: ew, height: eh), alfa: d)
        }
        if let m = o.marca {
            dibuja(m, CGRect(x: w - CGFloat(m.width) - 48, y: h - CGFloat(m.height) - 64,
                             width: CGFloat(m.width), height: CGFloat(m.height)), alfa: 0.75)
        }
    }
}

// MARK: - los rótulos (SwiftUI → imagen, en el hilo principal)

@MainActor
enum RotulosPresumir {
    static func letra(_ tam: CGFloat, _ peso: Font.Weight) -> Font {
        let f = Tema.actual.fuentes
        if let familia = f.titulo, Letras.lista(familia) { return Font.custom(familia, fixedSize: tam).weight(peso) }
        return .system(size: tam, weight: peso, design: f.diseno)
    }

    static func haz(nombre: String, color: String, nivel: Int?, intento: Int, encadenado: Bool,
                    miniMapa: Bool = true, resumen: Bool = true) -> OpcionesPresumir {
        let colores = ColoresEsq.delTema()
        let claro = Color(uiColor: colores.punto), oscuro = Color(uiColor: colores.borde)
        let titulo = nombre.isEmpty ? (color.isEmpty ? "Mi bloque" : "Bloque \(color)") : nombre
        let cabecera = VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 24) {
                if !color.isEmpty {
                    Circle().fill(EscaladaDatos.color(color)).frame(width: 64, height: 64)
                        .overlay(Circle().strokeBorder(claro.opacity(0.9), lineWidth: 4))
                }
                Text(titulo).font(letra(80, .bold)).foregroundStyle(claro)
                    .lineLimit(2).minimumScaleFactor(0.5)
            }
            HStack(spacing: 14) {
                if let nivel { chip("Nivel \(nivel)", claro, oscuro) }
                chip("Intento nº \(intento)", claro, oscuro)
            }
        }
        .padding(.horizontal, 64).padding(.top, 130).padding(.bottom, 10)
        .frame(width: CGFloat(MontadorPresumir.ancho), alignment: .leading)

        let lenta = HStack(spacing: 12) {
            Image(systemName: "tortoise.fill")
            Text("CÁMARA LENTA")
        }
        .font(letra(34, .bold)).foregroundStyle(oscuro)
        .padding(.horizontal, 26).padding(.vertical, 12)
        .background(Color(uiColor: colores.centro), in: Capsule())

        let chapa = Text("¡Encadenado!")
            .font(letra(110, .heavy)).foregroundStyle(oscuro)
            .padding(.horizontal, 56).padding(.vertical, 26)
            .background(Color(uiColor: colores.hueso), in: RoundedRectangle(cornerRadius: 40, style: .continuous))
            .rotationEffect(.degrees(-4))
            .padding(40)

        let marca = Text("Tom").font(letra(40, .bold)).foregroundStyle(claro)

        return OpcionesPresumir(cabecera: imagen(cabecera), encadenado: encadenado ? imagen(chapa) : nil,
                                lenta: imagen(lenta), marca: imagen(marca), colores: colores,
                                miniMapa: miniMapa, resumen: resumen, titulo: titulo, fecha: HojaTarjetaRuta.fecha())
    }

    private static func chip(_ t: String, _ claro: Color, _ oscuro: Color) -> some View {
        Text(t).font(letra(40, .semibold)).foregroundStyle(claro)
            .padding(.horizontal, 26).padding(.vertical, 10)
            .background(oscuro.opacity(0.55), in: Capsule())
    }

    private static func imagen(_ v: some View) -> CGImage? {
        let r = ImageRenderer(content: v.environment(\.colorScheme, .dark))
        r.scale = 1
        return r.cgImage
    }
}

// MARK: - la hoja

struct HojaPresumir: View {
    /// El vídeo ya grabado (modo en vivo); nil para elegirlo de Fotos.
    var video: URL?
    @Environment(\.dismiss) private var cerrar
    @State private var elegido: PhotosPickerItem?
    @State private var cargado: URL?
    @State private var leyendo = false
    @State private var nombre = ""
    @State private var color = ""
    @State private var nivel = 0
    @State private var intento = 1
    @State private var encadenado = false
    @State private var progreso: Double?
    @State private var fase = ""
    @State private var hecho: URL?
    @State private var aviso: String?
    @State private var tarea: Task<Result<HechoPresumir, Error>, Never>?
    @State private var miniMapa = true
    @State private var resumen = true
    @State private var rutaHecha: RutaParaHoja?
    @State private var ruta: RutaEsc?
    @State private var compartir = false
    @State private var guardando = false

    init(video: URL? = nil) {
        self.video = video
    }

    private var fuente: URL? { video ?? cargado }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    if let hecho {
                        listo(hecho)
                    } else {
                        formulario
                    }
                }
                .listRowBackground(Tema.carta)
            }
            .scrollContentBackground(.hidden)
            .background(Tema.fondo)
            .navigationTitle("Vídeo para presumir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(progreso != nil ? "Cancelar" : "Cerrar") {
                        tarea?.cancel()
                        cerrar()
                    }
                }
            }
            .onChange(of: elegido) { _, nuevo in carga(nuevo) }
            .onChange(of: nombre) { _, _ in cuentaIntentos() }
            .onChange(of: color) { _, _ in cuentaIntentos() }
            .onDisappear {
                tarea?.cancel()
                if let cargado { try? FileManager.default.removeItem(at: cargado) }
            }
            .sheet(item: $rutaHecha) { r in
                HojaTarjetaRuta(ruta: r.ruta, titulo: r.titulo)
            }
            .sheet(isPresented: $compartir) {
                if let hecho {
                    HojaCompartir(cosas: [hecho]).presentationDetents([.medium, .large])
                }
            }
        }
    }

    @ViewBuilder private var formulario: some View {
        Section {
            if video != nil {
                Label("El intento que acabas de grabar", systemImage: "checkmark.circle.fill")
            } else {
                PhotosPicker(selection: $elegido, matching: .videos, preferredItemEncoding: .current) {
                    Label(cargado == nil ? (leyendo ? "Leyendo el vídeo…" : "Elegir el vídeo") : "Vídeo elegido · cambiar",
                          systemImage: "video")
                }
                .disabled(leyendo || progreso != nil)
            }
        }
        Section("El rótulo") {
            TextField("Nombre del bloque", text: $nombre)
            Picker("Color de las presas", selection: $color) {
                Text("Sin color").tag("")
                ForEach(Escalada.shared.colores, id: \.self) { c in Text(c.capitalized).tag(c) }
            }
            Picker("Nivel", selection: $nivel) {
                Text("Sin nivel").tag(0)
                ForEach(1...10, id: \.self) { n in Text("\(n)").tag(n) }
            }
            Stepper("Intento nº \(intento)", value: $intento, in: 1...99)
            Toggle("¡Encadenado!", isOn: $encadenado)
        }
        Section("La ruta") {
            Toggle("Mini-mapa de la ruta", isOn: $miniMapa)
            Toggle("Resumen de 2 s al final", isOn: $resumen)
        }
        Section {
            if let progreso {
                VStack(alignment: .leading, spacing: Tema.Espacio.s) {
                    HStack {
                        Text(fase).font(Tema.fuente(.texto))
                        Spacer()
                        Text("\(Int(progreso * 100)) %").font(Tema.fuente(.texto)).monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    ProgressView(value: progreso).tint(Tema.acento)
                }
                .accessibilityElement(children: .combine)
            } else {
                Button("Crear el vídeo") { crea() }
                    .disabled(fuente == nil)
            }
            if let aviso {
                Text(aviso).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro)
            }
        } footer: {
            Text("Se hace en el iPhone, sin esperar a la Pi: vertical para historias, con el esqueleto, la estela del centro de gravedad y cámara lenta en el tramo más rápido.")
        }
    }

    @ViewBuilder private func listo(_ url: URL) -> some View {
        Section {
            BucleVideo(url: url)
                .aspectRatio(9.0 / 16.0, contentMode: .fit)
                .frame(maxHeight: 460)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Tema.Radio.celda))
                .accessibilityLabel("El vídeo para presumir")
        }
        Section {
            Button {
                compartir = true
            } label: {
                Label("Compartir", systemImage: "square.and.arrow.up")
            }
            Button {
                guarda(url)
            } label: {
                Label(guardando ? "Guardando…" : "Guardar en Fotos", systemImage: "photo.on.rectangle")
            }
            .disabled(guardando)
            if let ruta {
                Button {
                    let n = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
                    rutaHecha = RutaParaHoja(ruta: ruta, titulo: n.isEmpty ? (color.isEmpty ? "Mi bloque" : "Bloque \(color)") : n)
                } label: {
                    Label("Tarjeta de la ruta", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
            }
            if let aviso {
                Text(aviso).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            }
        }
    }

    private func cuentaIntentos() {
        let n = nombre.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let iguales = EscaladaDatos.shared.intentos.filter { x in
            n.isEmpty ? (!color.isEmpty && x.color == color && x.nombre.isEmpty) : x.nombre.lowercased() == n
        }
        intento = iguales.count + 1
    }

    private func carga(_ item: PhotosPickerItem?) {
        guard let item else { return }
        leyendo = true
        aviso = nil
        Task {
            do {
                if let v = try await item.loadTransferable(type: VideoElegido.self) {
                    if let cargado { try? FileManager.default.removeItem(at: cargado) }
                    cargado = v.url
                } else {
                    aviso = "No se ha podido leer el vídeo. Prueba con otro."
                }
            } catch {
                aviso = "No se ha podido leer el vídeo: \(error.localizedDescription)"
            }
            leyendo = false
        }
    }

    private func crea() {
        guard let fuente else { return }
        aviso = nil
        progreso = 0
        fase = "Preparando…"
        let n = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        let o = RotulosPresumir.haz(nombre: n, color: color, nivel: nivel == 0 ? nil : nivel, intento: intento,
                                     encadenado: encadenado, miniMapa: miniMapa, resumen: resumen)
        let t = Task.detached(priority: .userInitiated) { () -> Result<HechoPresumir, Error> in
            do {
                let hecho = try await MontadorPresumir.monta(fuente, o) { p, f in
                    Task { @MainActor in
                        progreso = p
                        fase = f
                    }
                }
                return .success(hecho)
            } catch {
                return .failure(error)
            }
        }
        tarea = t
        Task {
            let r = await t.value
            progreso = nil
            switch r {
            case .success(let h):
                ruta = h.ruta
                withAnimation(Tema.Muelle.pantalla) { hecho = h.url }
                Haptica.shared.toca(encadenado ? .record : .marcar)
            case .failure(let e):
                if !(e is CancellationError) {
                    aviso = "No se ha podido crear el vídeo: \(e.localizedDescription)"
                    Haptica.shared.toca(.error)
                }
            }
        }
    }

    private func guarda(_ url: URL) {
        guardando = true
        Task {
            do {
                try await Fototeca.guarda(videos: [url])
                aviso = "Guardado en Fotos."
                Haptica.shared.toca(.marcar)
            } catch {
                aviso = error.localizedDescription
                Haptica.shared.toca(.error)
            }
            guardando = false
        }
    }
}
