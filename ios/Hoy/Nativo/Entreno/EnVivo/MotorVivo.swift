import AVFoundation
import Observation
import QuartzCore
import UIKit
import Vision

/// La cámara del modo en vivo: AVCaptureSession con la trasera a 1080p y 30 fps; cada fotograma va a la vista previa
/// (la capa de AVFoundation, sin pasar por aquí) y, uno de cada dos (o menos si el iPhone se calienta), a Vision en su
/// propia cola: si Vision va ocupada, el fotograma se salta y no se acumula nada. La pose sale suavizada (One Euro)
/// y la pantalla la interpola a 60 fps. Al grabar escribe dos vídeos a la vez: el limpio (para el análisis de la Pi
/// y el vídeo para presumir) y otro con el esqueleto quemado encima.
@Observable
final class MotorVivo: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum Estado: Equatable {
        case preparando, listo, sinPermiso, sinCamara
    }

    struct Lente: Identifiable, Equatable {
        var id: String
        var nombre: String
        var dispositivo: String
        var zoom: CGFloat
        /// Lo que «vale» un aumento de 1 en este dispositivo comparado con el gran angular (0,5 en el ultra gran angular).
        var base: CGFloat
    }

    struct Resultado: Identifiable {
        let id = UUID()
        let limpio: URL
        let esqueleto: URL
    }

    /// Cuánto se ha subido: del pie más bajo a la mano más alta, en metros aproximados (el tronco mide ~0,5 m).
    struct Alcance {
        var suelo: CGFloat?
        var cima: CGFloat?
        var metros: Double?
    }

    struct Instantanea {
        var pose: PoseEsc?
        var estela: [PuntoEstela]
        var tam: CGSize
        var alcance: Alcance
    }

    // MARK: lo que ve la pantalla (solo en el hilo principal)

    var estado: Estado = .preparando
    var grabando = false
    var inicioGrabacion: Date?
    var lentes: [Lente] = []
    var lenteActual: String?
    /// El aumento como lo diría la app de Cámara (0,5×, 1×, 2,4×…).
    var aumento: CGFloat = 1
    var terminado: Resultado?
    var aviso: String?
    var caliente = false

    // MARK: por dentro

    let sesion = AVCaptureSession()
    private let salida = AVCaptureVideoDataOutput()
    private let colaSesion = DispatchQueue(label: "dev.yagotg.hoy.vivo.sesion")
    private let colaVideo = DispatchQueue(label: "dev.yagotg.hoy.vivo.video", qos: .userInteractive)
    private let colaVision = DispatchQueue(label: "dev.yagotg.hoy.vivo.vision", qos: .userInitiated)
    @ObservationIgnored private var entrada: AVCaptureDeviceInput?
    @ObservationIgnored private var dispositivos: [String: AVCaptureDevice] = [:]
    @ObservationIgnored private var configurado = false

    // con el cerrojo: lo comparten la cola de Vision, la de vídeo y la pantalla
    private let cerrojo = NSLock()
    @ObservationIgnored private var _pose: PoseEsc?
    @ObservationIgnored private var _estela: [PuntoEstela] = []
    @ObservationIgnored private var _tam: CGSize = .zero
    @ObservationIgnored private var _alcance = Alcance()
    @ObservationIgnored private var _tronco: CGFloat = 0
    @ObservationIgnored private var visionOcupada = false
    @ObservationIgnored private var pedido: (giro: CGAffineTransform, colores: ColoresEsq)?

    // solo en la cola de Vision
    @ObservationIgnored private var suavizador = SuavizadorPose()
    private let peticion = VNDetectHumanBodyPoseRequest()

    // solo en la cola de vídeo
    @ObservationIgnored private var cuenta = 0
    @ObservationIgnored private var grabadora: Grabadora?
    @ObservationIgnored private var coloresGrabando: ColoresEsq?

    static let duracionEstela = 3.0

    override init() {
        super.init()
    }

    // MARK: arrancar y parar

    @MainActor func arranca() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configura()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                Task { @MainActor in
                    if ok { self.configura() } else { self.estado = .sinPermiso }
                }
            }
        default:
            estado = .sinPermiso
        }
    }

    @MainActor func para() {
        if grabando { paraDeGrabar() }
        colaSesion.async {
            if self.sesion.isRunning { self.sesion.stopRunning() }
        }
    }

    @MainActor func reanuda() {
        guard estado == .listo else { return }
        colaSesion.async {
            if !self.sesion.isRunning { self.sesion.startRunning() }
        }
    }

    @MainActor private func configura() {
        colaSesion.async { [self] in
            if configurado {
                if !sesion.isRunning { sesion.startRunning() }
                return
            }
            let descubre = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera],
                mediaType: .video, position: .back)
            let todos = descubre.devices
            guard let principal = todos.first(where: { $0.deviceType == .builtInWideAngleCamera }) ?? todos.first,
                  let e = try? AVCaptureDeviceInput(device: principal) else {
                DispatchQueue.main.async { self.estado = .sinCamara }
                return
            }
            sesion.beginConfiguration()
            sesion.sessionPreset = sesion.canSetSessionPreset(.hd1920x1080) ? .hd1920x1080 : .high
            if sesion.canAddInput(e) { sesion.addInput(e) }
            entrada = e
            salida.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            salida.alwaysDiscardsLateVideoFrames = true
            salida.setSampleBufferDelegate(self, queue: colaVideo)
            if sesion.canAddOutput(salida) { sesion.addOutput(salida) }
            orientaSalida()
            sesion.commitConfiguration()
            ponFps(principal)
            for d in todos { dispositivos[d.uniqueID] = d }
            let lentes = Self.lentes(todos, principal: principal)
            configurado = true
            sesion.startRunning()
            DispatchQueue.main.async {
                self.lentes = lentes
                self.lenteActual = lentes.first { $0.dispositivo == principal.uniqueID && $0.zoom == 1 }?.id
                self.aumento = 1
                self.estado = .listo
            }
        }
    }

    /// Los fotogramas ya en vertical: así la pose, la vista previa y el vídeo grabado van en las mismas coordenadas.
    private func orientaSalida() {
        if let c = salida.connection(with: .video), c.isVideoRotationAngleSupported(90) {
            c.videoRotationAngle = 90
        }
    }

    private func ponFps(_ d: AVCaptureDevice) {
        guard (try? d.lockForConfiguration()) != nil else { return }
        let vale = d.activeFormat.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }
        if vale {
            d.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            d.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
        }
        d.unlockForConfiguration()
    }

    /// 0,5× (ultra gran angular), 1× y el tele si lo hay; si no, un 2× del gran angular (como en la app de Cámara).
    private static func lentes(_ todos: [AVCaptureDevice], principal: AVCaptureDevice) -> [Lente] {
        var r: [Lente] = []
        let fovPrincipal = Double(principal.activeFormat.videoFieldOfView)
        if let ultra = todos.first(where: { $0.deviceType == .builtInUltraWideCamera }) {
            r.append(Lente(id: "ultra", nombre: "0,5", dispositivo: ultra.uniqueID, zoom: 1, base: 0.5))
        }
        r.append(Lente(id: "gran", nombre: "1", dispositivo: principal.uniqueID, zoom: 1, base: 1))
        if let tele = todos.first(where: { $0.deviceType == .builtInTelephotoCamera }) {
            let fovTele = Double(tele.activeFormat.videoFieldOfView)
            let x = fovTele > 0 ? tan(fovPrincipal * .pi / 360) / tan(fovTele * .pi / 360) : 2
            let factor = max(1.5, min(10, x))
            r.append(Lente(id: "tele", nombre: Self.cifra(factor), dispositivo: tele.uniqueID, zoom: 1, base: factor))
        } else if principal.maxAvailableVideoZoomFactor >= 2 {
            r.append(Lente(id: "doble", nombre: "2", dispositivo: principal.uniqueID, zoom: 2, base: 1))
        }
        return r
    }

    static func cifra(_ x: CGFloat) -> String {
        let r = (x * 10).rounded() / 10
        return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", Double(r)).replacingOccurrences(of: ".", with: ",")
    }

    // MARK: lentes y zoom

    @MainActor func elige(_ l: Lente) {
        guard !grabando, l.id != lenteActual else { return }
        Haptica.shared.toca(.desmarcar)
        colaSesion.async { [self] in
            guard let d = dispositivos[l.dispositivo] else { return }
            if entrada?.device.uniqueID != d.uniqueID, let nueva = try? AVCaptureDeviceInput(device: d) {
                sesion.beginConfiguration()
                if let entrada { sesion.removeInput(entrada) }
                if sesion.canAddInput(nueva) {
                    sesion.addInput(nueva)
                    entrada = nueva
                } else if let entrada {
                    sesion.addInput(entrada)
                }
                orientaSalida()
                sesion.commitConfiguration()
                ponFps(d)
            }
            let z = aplicaZoom(l.zoom)
            DispatchQueue.main.async {
                self.lenteActual = l.id
                self.aumento = l.base * z
            }
        }
    }

    /// El aumento del dispositivo actual (lo que da el pellizco).
    @MainActor var zoomActual: CGFloat {
        let base = lentes.first { $0.id == lenteActual }?.base ?? 1
        return aumento / max(base, 0.1)
    }

    @MainActor func zoom(_ factor: CGFloat) {
        let base = lentes.first { $0.id == lenteActual }?.base ?? 1
        colaSesion.async { [self] in
            let z = aplicaZoom(factor)
            DispatchQueue.main.async { self.aumento = base * z }
        }
    }

    /// En la cola de la sesión. Devuelve el que ha quedado.
    private func aplicaZoom(_ factor: CGFloat) -> CGFloat {
        guard let d = entrada?.device, (try? d.lockForConfiguration()) != nil else { return 1 }
        let z = max(d.minAvailableVideoZoomFactor, min(factor, min(d.maxAvailableVideoZoomFactor, 10)))
        d.videoZoomFactor = z
        d.unlockForConfiguration()
        return z
    }

    // MARK: grabar

    @MainActor func graba() {
        guard !grabando, estado == .listo else { return }
        let giro = Self.giro(UIDevice.current.orientation)
        let colores = ColoresEsq.delTema()
        grabando = true
        inicioGrabacion = Date()
        aviso = nil
        Haptica.shared.toca(.serie)
        cerrojo.lock()
        pedido = (giro, colores)
        _alcance = Alcance()
        cerrojo.unlock()
    }

    @MainActor func paraDeGrabar() {
        guard grabando else { return }
        Haptica.shared.toca(.marcar)
        cerrojo.lock()
        pedido = nil
        cerrojo.unlock()
        colaVideo.async { [self] in
            let g = grabadora
            grabadora = nil
            guard let g else {
                DispatchQueue.main.async {
                    self.grabando = false
                    self.inicioGrabacion = nil
                }
                return
            }
            g.termina { limpio, esqueleto in
                self.grabando = false
                self.inicioGrabacion = nil
                if let limpio, let esqueleto {
                    self.terminado = Resultado(limpio: limpio, esqueleto: esqueleto)
                } else {
                    self.aviso = "No se ha podido guardar el vídeo. Prueba otra vez; si sigue, cierra y abre el modo en vivo."
                    Haptica.shared.toca(.error)
                }
            }
        }
    }

    /// El giro que se guarda en el vídeo según cómo tengas el iPhone al empezar (la imagen va siempre en vertical).
    private static func giro(_ o: UIDeviceOrientation) -> CGAffineTransform {
        switch o {
        case .landscapeLeft: return CGAffineTransform(rotationAngle: -.pi / 2)
        case .landscapeRight: return CGAffineTransform(rotationAngle: .pi / 2)
        case .portraitUpsideDown: return CGAffineTransform(rotationAngle: .pi)
        default: return .identity
        }
    }

    // MARK: lo que ve la pantalla

    func instantanea() -> Instantanea {
        cerrojo.lock()
        defer { cerrojo.unlock() }
        return Instantanea(pose: _pose, estela: _estela, tam: _tam, alcance: _alcance)
    }

    @MainActor func reiniciaAlcance() {
        cerrojo.lock()
        _alcance = Alcance()
        cerrojo.unlock()
    }

    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate (cola de vídeo)

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let t = pts.seconds
        cuenta += 1

        // Vision: uno de cada `salto` fotogramas, y nunca dos a la vez
        let termico = ProcessInfo.processInfo.thermalState
        let salto: Int
        switch termico {
        case .critical: salto = 4
        case .serious: salto = 3
        default: salto = 2
        }
        cerrojo.lock()
        let analiza = !visionOcupada && cuenta % salto == 0
        if analiza { visionOcupada = true }
        let pedidoAhora = pedido
        let pose = _pose
        let estela = _estela
        cerrojo.unlock()
        if analiza {
            colaVision.async { self.analiza(pb, t) }
        }
        if cuenta % 60 == 0 {
            let muy = termico == .serious || termico == .critical
            DispatchQueue.main.async { if self.caliente != muy { self.caliente = muy } }
        }

        // grabar
        if let pedidoAhora, grabadora == nil {
            let tam = CGSize(width: CVPixelBufferGetWidth(pb), height: CVPixelBufferGetHeight(pb))
            do {
                grabadora = try Grabadora(tam: tam, giro: pedidoAhora.giro)
                coloresGrabando = pedidoAhora.colores
            } catch {
                cerrojo.lock()
                pedido = nil
                cerrojo.unlock()
                DispatchQueue.main.async {
                    self.grabando = false
                    self.inicioGrabacion = nil
                    self.aviso = "No se puede grabar: \(error.localizedDescription)"
                }
            }
        }
        if let g = grabadora, let colores = coloresGrabando {
            let w = CGFloat(CVPixelBufferGetWidth(pb)), h = CGFloat(CVPixelBufferGetHeight(pb))
            let tam = CGSize(width: w, height: h)
            g.escribe(pb, pts) { ctx in
                PintorEsq.pinta(ctx, pose: pose, estela: estela, ahora: t, duracionEstela: Self.duracionEstela,
                                tamImagen: tam, escala: 1, aPx: { CGPoint(x: $0.x * w, y: $0.y * h) }, colores: colores)
            }
        }
    }

    // MARK: Vision (su cola)

    private func analiza(_ pb: CVPixelBuffer, _ t: Double) {
        let tam = CGSize(width: CVPixelBufferGetWidth(pb), height: CVPixelBufferGetHeight(pb))
        let manejador = VNImageRequestHandler(cvPixelBuffer: pb, orientation: .up, options: [:])
        let cruda: PoseEsc? = (try? manejador.perform([peticion])) != nil ? PoseEsc(peticion.results) : nil
        let pose = suavizador.filtra(cruda, t)
        let vale = pose.hayCuerpo
        let centro = vale ? pose.centro(tam) : nil
        let tronco = pose.largoTronco(tam)

        cerrojo.lock()
        defer { cerrojo.unlock() }
        visionOcupada = false
        _tam = tam
        _pose = vale ? pose : nil
        if let centro {
            _estela.append(PuntoEstela(t: t, p: CGPoint(x: centro.x / tam.width, y: centro.y / tam.height)))
        }
        _estela.removeAll { t - $0.t > Self.duracionEstela }
        guard vale else { return }
        if let tronco { _tronco = _tronco == 0 ? tronco : _tronco * 0.9 + tronco * 0.1 }
        let pies = [17, 18].filter(pose.ve).map { pose.p[$0].y }
        let manos = [10, 11].filter(pose.ve).map { pose.p[$0].y }
        if let pie = pies.max() { _alcance.suelo = max(_alcance.suelo ?? pie, pie) }
        if let mano = manos.min() { _alcance.cima = min(_alcance.cima ?? mano, mano) }
        if let s = _alcance.suelo, let c = _alcance.cima, _tronco > 0 {
            _alcance.metros = max(0, Double((s - c) * tam.height / _tronco) * 0.5)
        }
    }
}

// MARK: - los dos vídeos a la vez

/// Escribe el vídeo limpio y el del esqueleto (HEVC, sin audio) en la cola de vídeo del motor.
final class Grabadora {
    let limpio: URL
    let esqueleto: URL
    private let wLimpio: AVAssetWriter
    private let wEsq: AVAssetWriter
    private let iLimpio: AVAssetWriterInput
    private let iEsq: AVAssetWriterInput
    private let aLimpio: AVAssetWriterInputPixelBufferAdaptor
    private let aEsq: AVAssetWriterInputPixelBufferAdaptor
    private var empezado = false
    private var fallo = false

    init(tam: CGSize, giro: CGAffineTransform) throws {
        let id = Grabadora.id()
        limpio = ArchivosEscalada.carpeta.appendingPathComponent("vivo-\(id).mov")
        esqueleto = ArchivosEscalada.carpeta.appendingPathComponent("vivo-\(id)-esqueleto.mov")
        Grabadora.limpiaViejos()
        try? FileManager.default.removeItem(at: limpio)
        try? FileManager.default.removeItem(at: esqueleto)
        wLimpio = try AVAssetWriter(outputURL: limpio, fileType: .mov)
        wEsq = try AVAssetWriter(outputURL: esqueleto, fileType: .mov)
        // la fecha de grabación: con ella el servidor pone la hora del intento (Escalada.idIntento)
        let fecha = AVMutableMetadataItem()
        fecha.identifier = .quickTimeMetadataCreationDate
        fecha.value = ISO8601DateFormatter().string(from: Date()) as NSString
        wLimpio.metadata = [fecha]
        wEsq.metadata = [fecha]

        func ajustes(_ w: AVAssetWriter, bits: Int) -> [String: Any] {
            var a: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: Int(tam.width),
                                    AVVideoHeightKey: Int(tam.height),
                                    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bits]]
            if !w.canApply(outputSettings: a, forMediaType: .video) { a[AVVideoCodecKey] = AVVideoCodecType.h264 }
            return a
        }
        iLimpio = AVAssetWriterInput(mediaType: .video, outputSettings: ajustes(wLimpio, bits: 10_000_000))
        iEsq = AVAssetWriterInput(mediaType: .video, outputSettings: ajustes(wEsq, bits: 10_000_000))
        for i in [iLimpio, iEsq] {
            i.expectsMediaDataInRealTime = true
            i.transform = giro
        }
        let atributos: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                        kCVPixelBufferWidthKey as String: Int(tam.width),
                                        kCVPixelBufferHeightKey as String: Int(tam.height)]
        aLimpio = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: iLimpio, sourcePixelBufferAttributes: nil)
        aEsq = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: iEsq, sourcePixelBufferAttributes: atributos)
        guard wLimpio.canAdd(iLimpio), wEsq.canAdd(iEsq) else {
            throw APIError(mensaje: "el iPhone no deja escribir el vídeo")
        }
        wLimpio.add(iLimpio)
        wEsq.add(iEsq)
    }

    private static func id() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    /// Los vídeos en vivo de hace más de 3 días fuera (lo bueno ya está en Fotos o en la Pi).
    private static func limpiaViejos() {
        let fm = FileManager.default
        let carpeta = ArchivosEscalada.carpeta
        guard let lista = try? fm.contentsOfDirectory(at: carpeta, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let limite = Date().addingTimeInterval(-3 * 24 * 3600)
        for u in lista where u.lastPathComponent.hasPrefix("vivo-") || u.lastPathComponent.hasPrefix("presumir-") {
            if let d = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, d < limite {
                try? fm.removeItem(at: u)
            }
        }
    }

    func escribe(_ pb: CVPixelBuffer, _ t: CMTime, pinta: (CGContext) -> Void) {
        guard !fallo else { return }
        if !empezado {
            guard wLimpio.startWriting(), wEsq.startWriting() else {
                fallo = true
                return
            }
            wLimpio.startSession(atSourceTime: t)
            wEsq.startSession(atSourceTime: t)
            empezado = true
        }
        if iLimpio.isReadyForMoreMediaData {
            aLimpio.append(pb, withPresentationTime: t)
        }
        guard iEsq.isReadyForMoreMediaData, let pool = aEsq.pixelBufferPool else { return }
        var nuevo: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &nuevo)
        guard let nuevo else { return }
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        CVPixelBufferLockBaseAddress(nuevo, [])
        defer {
            CVPixelBufferUnlockBaseAddress(nuevo, [])
            CVPixelBufferUnlockBaseAddress(pb, .readOnly)
        }
        guard let origen = CVPixelBufferGetBaseAddress(pb), let destino = CVPixelBufferGetBaseAddress(nuevo) else { return }
        let alto = min(CVPixelBufferGetHeight(pb), CVPixelBufferGetHeight(nuevo))
        let ancho = min(CVPixelBufferGetWidth(pb), CVPixelBufferGetWidth(nuevo))
        let bo = CVPixelBufferGetBytesPerRow(pb), bd = CVPixelBufferGetBytesPerRow(nuevo)
        if bo == bd {
            memcpy(destino, origen, bo * alto)
        } else {
            for y in 0..<alto { memcpy(destino.advanced(by: y * bd), origen.advanced(by: y * bo), min(bo, bd)) }
        }
        if let ctx = CGContext(data: destino, width: ancho, height: alto, bitsPerComponent: 8, bytesPerRow: bd,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
            ctx.translateBy(x: 0, y: CGFloat(alto))
            ctx.scaleBy(x: 1, y: -1)
            pinta(ctx)
        }
        aEsq.append(nuevo, withPresentationTime: t)
    }

    /// Cierra los dos; `fin` llega en el hilo principal con las dos URL (o nil si algo falló).
    func termina(_ fin: @escaping @MainActor (URL?, URL?) -> Void) {
        guard empezado else {
            DispatchQueue.main.async { MainActor.assumeIsolated { fin(nil, nil) } }
            return
        }
        iLimpio.markAsFinished()
        iEsq.markAsFinished()
        let grupo = DispatchGroup()
        grupo.enter()
        wLimpio.finishWriting { grupo.leave() }
        grupo.enter()
        wEsq.finishWriting { grupo.leave() }
        grupo.notify(queue: .main) { [self] in
            let l = wLimpio.status == .completed ? limpio : nil, e = wEsq.status == .completed ? esqueleto : nil
            MainActor.assumeIsolated { fin(l, e) }
        }
    }
}
