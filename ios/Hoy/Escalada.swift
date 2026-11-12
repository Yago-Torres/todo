import AVFoundation
import CoreTransferable
import Foundation
import Observation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications
import Vision
import WebKit

/// Subir un intento de escalada desde la app: la web pide la hoja ({accion:"escalada-subir"}), se elige el vídeo con
/// PhotosPicker (sin permiso de fototeca), se comprime aquí, sube con un URLSession en segundo plano a POST /api/escalada
/// y, mientras sube, Vision saca una vista previa del esqueleto (POST /api/escalada/<intento>/previa). El análisis bueno
/// lo sigue haciendo ~/escalada en el PC o en la Pi. La web se entera con el evento «tom-escalada».
///
/// Cloudflare (plan gratis) corta las peticiones de más de 100 MB: por eso se comprime hasta que pese 95 MB o menos.
@MainActor @Observable
final class Escalada {
    static let shared = Escalada()
    static let coloresPorDefecto = ["amarillo", "naranja", "rojo", "rosa", "morado", "azul", "verde", "blanco", "negro"]

    @ObservationIgnored weak var web: WKWebView?
    var hojaVisible = false
    var colores = Escalada.coloresPorDefecto
    var quien = "Yago"
    /// Lo que se está preparando ahora (leer el vídeo, comprimir); nil cuando ya está subiendo o no hay nada.
    var trabajo: String?
    var progreso: Double?
    var aviso: String?
    var fallidas: [DatosIntento] = []

    private init() {}

    // MARK: la hoja

    /// Al abrir la hoja: los colores y el nombre del servidor, y las subidas que se cortaron.
    func prepara() async {
        await revisa()
        do {
            let crudo = try await API.datos("/api/escalada")
            if let objeto = try JSONSerialization.jsonObject(with: crudo) as? [String: Any] {
                if let c = objeto["colores"] as? [String], !c.isEmpty { colores = c }
                if let q = objeto["quien"] as? String, !q.isEmpty { quien = q }
            }
        } catch {
            // sin red: los colores de siempre
        }
    }

    /// Las que constan subiendo pero ya no tienen tarea (la app se cerró a la fuerza, por ejemplo) pasan a fallidas.
    func revisa() async {
        let vivas = await Subidas.shared.vivas()
        for d in RegistroSubidas.todas() where d.error == nil && !vivas.contains(d.intento) {
            RegistroSubidas.marcaError(d.intento, "La subida se cortó")
        }
        refrescaFallidas()
    }

    func refrescaFallidas() {
        fallidas = RegistroSubidas.todas().filter { $0.error != nil }.sorted { $0.intento > $1.intento }
    }

    func empieza(_ elegido: PhotosPickerItem, _ datos: DatosIntento) {
        guard trabajo == nil else { return }
        trabajo = "Leyendo el vídeo…"
        progreso = nil
        aviso = nil
        Task { await procesa(elegido, datos) }
    }

    func reintenta(_ d: DatosIntento) {
        do {
            try Subidas.shared.sube(d)
            emite(d.intento, "subiendo", progreso: 0, datos: d)
            aviso = "Subiendo otra vez el intento de las \(Self.hora(d.intento))"
        } catch {
            aviso = error.localizedDescription
        }
        refrescaFallidas()
    }

    func descarta(_ d: DatosIntento) {
        try? FileManager.default.removeItem(at: ArchivosEscalada.carpeta.appendingPathComponent(d.fichero))
        RegistroSubidas.quita(d.intento)
        refrescaFallidas()
    }

    // MARK: el proceso

    private func procesa(_ elegido: PhotosPickerItem, _ base: DatosIntento) async {
        var original: URL?
        defer {
            trabajo = nil
            progreso = nil
            if let original { try? FileManager.default.removeItem(at: original) }
        }
        var datos = base
        do {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            guard let video = try await elegido.loadTransferable(type: VideoElegido.self) else {
                throw APIError(mensaje: "No se ha podido leer el vídeo")
            }
            original = video.url
            datos.intento = await Self.idIntento(video.url)
            let intento = datos.intento, inicial = datos
            trabajo = "Comprimiendo…"
            progreso = 0
            emite(intento, "comprimiendo", progreso: 0, datos: inicial)
            let (comprimido, tipo) = try await Self.comprime(video.url, intento: intento) { [weak self] p in
                guard let self else { return }
                self.progreso = p
                self.emite(intento, "comprimiendo", progreso: p, datos: inicial)
            }
            datos.fichero = comprimido.lastPathComponent
            datos.tipo = tipo
            // la previa lee su propio enlace del fichero: la subida lo borra al acabar y puede acabar antes
            let paraPrevia = ArchivosEscalada.carpeta.appendingPathComponent("previa-\(comprimido.lastPathComponent)")
            try? FileManager.default.removeItem(at: paraPrevia)
            let hayPrevia = (try? FileManager.default.linkItem(at: comprimido, to: paraPrevia)) != nil
            try Subidas.shared.sube(datos)
            emite(intento, "subiendo", progreso: 0, datos: datos)
            aviso = "Subiendo en segundo plano: puedes cerrar esto. Te aviso al acabar."
            trabajo = nil
            if hayPrevia {
                let copia = datos
                Task { await self.previa(paraPrevia, copia) }
            }
        } catch {
            aviso = error.localizedDescription
            if !datos.intento.isEmpty { emite(datos.intento, "error", texto: error.localizedDescription, datos: datos) }
        }
    }

    /// Vision en una tarea de baja prioridad y el JSON, pequeño, por la vía normal. Si falla no pasa nada: es solo
    /// lo que se ve mientras llega el análisis bueno.
    private func previa(_ video: URL, _ d: DatosIntento) async {
        defer { try? FileManager.default.removeItem(at: video) }
        let meta = ["color": d.color, "nombre": d.nombre, "quien": d.quien, "resultado": d.resultado]
        let json = await Task.detached(priority: .background) { () -> Data? in
            try? await VistaPrevia.saca(video, meta: meta)
        }.value
        guard let json else { return }
        do {
            var p = try API.peticion("/api/escalada/\(d.intento)/previa", metodo: "POST")
            p.httpBody = json
            p.setValue("application/json", forHTTPHeaderField: "Content-Type")
            p.timeoutInterval = 60
            let (_, respuesta) = try await URLSession.shared.data(for: p)
            if let http = respuesta as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                emite(d.intento, "previa", datos: d)
            }
        } catch {
            // sin previa: la web enseña «subiendo…» y luego el análisis
        }
    }

    // MARK: la web

    /// window.dispatchEvent(new CustomEvent("tom-escalada", {detail: {intento, fase, progreso, texto, color, nombre}})).
    func emite(_ intento: String, _ fase: String, progreso: Double? = nil, texto: String = "", datos: DatosIntento? = nil) {
        guard let web else { return }
        var detalle: [String: Any] = ["intento": intento, "fase": fase, "texto": texto]
        if let progreso, progreso.isFinite { detalle["progreso"] = min(1, max(0, progreso)) }
        if let datos {
            detalle["color"] = datos.color
            detalle["nombre"] = datos.nombre
        }
        guard let json = try? JSONSerialization.data(withJSONObject: detalle),
              let texto = String(data: json, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.dispatchEvent(new CustomEvent(\"tom-escalada\",{detail:\(texto)}));true",
                               completionHandler: nil)
    }

    // MARK: el vídeo

    private static let maxBytes = 95 * 1024 * 1024

    /// La fecha del vídeo (si la trae) o la de ahora, como la pide el servidor: 20261111-183000.
    private static func idIntento(_ url: URL) async -> String {
        let asset = AVURLAsset(url: url)
        var fecha = Date()
        if let item = try? await asset.load(.creationDate), let d = try? await item.load(.dateValue) {
            fecha = d
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: fecha)
    }

    static func hora(_ intento: String) -> String {
        guard intento.count == 15 else { return intento }
        let c = Array(intento)
        return "\(String(c[9...10])):\(String(c[11...12]))"
    }

    /// HEVC 1080p; si aún pasa de 95 MB, 720p y luego 540p. Devuelve el fichero y su Content-Type.
    private static func comprime(_ origen: URL, intento: String,
                                 progreso: @escaping (Double) -> Void) async throws -> (URL, String) {
        let asset = AVURLAsset(url: origen)
        let presets = [AVAssetExportPresetHEVC1920x1080, AVAssetExportPreset1280x720, AVAssetExportPreset960x540]
        var ultimo: Error = APIError(mensaje: "No se ha podido comprimir el vídeo")
        for preset in presets {
            guard let sesion = AVAssetExportSession(asset: asset, presetName: preset) else { continue }
            let mp4 = sesion.supportedFileTypes.contains(.mp4)
            let destino = ArchivosEscalada.carpeta.appendingPathComponent("\(intento).\(mp4 ? "mp4" : "mov")")
            try? FileManager.default.removeItem(at: destino)
            sesion.outputURL = destino
            sesion.outputFileType = mp4 ? .mp4 : .mov
            sesion.shouldOptimizeForNetworkUse = true
            do {
                try await exporta(sesion, progreso: progreso)
            } catch {
                ultimo = error
                continue
            }
            let bytes = (try? destino.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            if bytes > 0 && bytes <= maxBytes { return (destino, mp4 ? "video/mp4" : "video/quicktime") }
            try? FileManager.default.removeItem(at: destino)
            ultimo = APIError(mensaje: "Comprimido sigue pasando de 95 MB: recórtalo en Fotos y vuelve a subirlo")
        }
        throw ultimo
    }

    private static func exporta(_ sesion: AVAssetExportSession, progreso: @escaping (Double) -> Void) async throws {
        let vigia = Task { @MainActor in
            while !Task.isCancelled {
                progreso(Double(sesion.progress))
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
        defer { vigia.cancel() }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            sesion.exportAsynchronously { c.resume() }
        }
        guard sesion.status == .completed else {
            throw sesion.error ?? APIError(mensaje: "No se ha podido comprimir el vídeo")
        }
    }
}

// MARK: - lo que se sube

struct DatosIntento: Codable, Identifiable, Hashable {
    var intento = ""
    var angulo = 1
    var quien = "Yago"
    var color = ""
    var nombre = ""
    var resultado = "probando"
    var nivel: Int?
    /// El vídeo comprimido, dentro de ArchivosEscalada.carpeta.
    var fichero = ""
    var tipo = "video/mp4"
    /// Por qué falló la última vez (nil mientras sube).
    var error: String?

    var id: String { intento }

    /// POST /api/escalada?intento=…&angulo=…: todo en la URL y el vídeo en crudo como cuerpo, como el atajo.
    var ruta: String {
        var c = URLComponents()
        c.path = "/api/escalada"
        c.queryItems = [
            URLQueryItem(name: "intento", value: intento),
            URLQueryItem(name: "angulo", value: String(angulo)),
            URLQueryItem(name: "quien", value: quien),
            URLQueryItem(name: "color", value: color),
            URLQueryItem(name: "nombre", value: nombre),
            URLQueryItem(name: "resultado", value: resultado),
            URLQueryItem(name: "nivel", value: nivel.map { String($0) } ?? ""),
        ]
        // URLComponents deja el «+» tal cual y el servidor lo leería como un espacio
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return c.string ?? "/api/escalada"
    }
}

enum ArchivosEscalada {
    /// En Application Support (no en tmp: el sistema podría borrarlo a media subida).
    static var carpeta: URL {
        let c = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Escalada", isDirectory: true)
        try? FileManager.default.createDirectory(at: c, withIntermediateDirectories: true)
        return c
    }
}

/// El vídeo que da PhotosPicker, copiado a la carpeta propia (el temporal que da desaparece al volver).
struct VideoElegido: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { recibido in
            let ext = recibido.file.pathExtension.isEmpty ? "mov" : recibido.file.pathExtension
            let destino = ArchivosEscalada.carpeta.appendingPathComponent("original-\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: recibido.file, to: destino)
            return VideoElegido(url: destino)
        }
    }
}

/// Las subidas en curso o fallidas, en un JSON propio: sobreviven a que iOS cierre la app mientras sube.
enum RegistroSubidas {
    private static let cerrojo = NSLock()
    private static var fichero: URL { ArchivosEscalada.carpeta.appendingPathComponent("subidas.json") }

    static func todas() -> [DatosIntento] {
        cerrojo.lock()
        defer { cerrojo.unlock() }
        return lee()
    }

    static func guarda(_ d: DatosIntento) {
        cambia { lista in
            lista.removeAll { $0.intento == d.intento }
            lista.append(d)
        }
    }

    static func quita(_ intento: String) {
        cambia { lista in lista.removeAll { $0.intento == intento } }
    }

    static func marcaError(_ intento: String, _ texto: String) {
        cambia { lista in
            if let i = lista.firstIndex(where: { $0.intento == intento }) { lista[i].error = texto }
        }
    }

    private static func cambia(_ f: (inout [DatosIntento]) -> Void) {
        cerrojo.lock()
        defer { cerrojo.unlock() }
        var lista = lee()
        f(&lista)
        if let datos = try? JSONEncoder().encode(lista) { try? datos.write(to: fichero, options: .atomic) }
    }

    private static func lee() -> [DatosIntento] {
        guard let datos = try? Data(contentsOf: fichero) else { return [] }
        return (try? JSONDecoder().decode([DatosIntento].self, from: datos)) ?? []
    }
}

// MARK: - la subida en segundo plano

/// Un URLSession de fondo: sigue subiendo con la app suspendida o cerrada por iOS (no si la cierras tú a la fuerza).
/// Al acabar, iOS despierta la app (application(_:handleEventsForBackgroundURLSession:) en AppDelegate).
final class Subidas: NSObject, URLSessionDataDelegate {
    static let shared = Subidas()
    static let identificador = "dev.yagotg.hoy.subidas"

    /// El completionHandler que da iOS al despertar la app por esta sesión: se llama cuando ya se ha avisado de todo.
    var alAcabar: (() -> Void)?
    // solo desde la cola del delegado (una operación a la vez)
    private var respuestas: [Int: Data] = [:]
    private var ultimoAviso: [String: Date] = [:]

    private lazy var sesion: URLSession = {
        let c = URLSessionConfiguration.background(withIdentifier: Subidas.identificador)
        c.isDiscretionary = false
        c.sessionSendsLaunchEvents = true
        c.timeoutIntervalForResource = 24 * 3600
        let cola = OperationQueue()
        cola.maxConcurrentOperationCount = 1
        return URLSession(configuration: c, delegate: self, delegateQueue: cola)
    }()

    private override init() {
        super.init()
    }

    /// Crea la sesión: al arrancar, para que lleguen los eventos de las subidas que acabaron con la app cerrada.
    func arranca() {
        _ = sesion
    }

    func sube(_ d: DatosIntento) throws {
        let fichero = ArchivosEscalada.carpeta.appendingPathComponent(d.fichero)
        guard !d.fichero.isEmpty, FileManager.default.fileExists(atPath: fichero.path) else {
            RegistroSubidas.quita(d.intento)
            throw APIError(mensaje: "Ya no está el vídeo comprimido: vuelve a elegirlo")
        }
        var p = try API.peticion(d.ruta, metodo: "POST")
        p.setValue(d.tipo, forHTTPHeaderField: "Content-Type")
        p.timeoutInterval = 120
        var limpio = d
        limpio.error = nil
        RegistroSubidas.guarda(limpio)
        let tarea = sesion.uploadTask(with: p, fromFile: fichero)
        tarea.taskDescription = d.intento
        tarea.resume()
    }

    /// Los intentos que tienen una tarea viva en la sesión.
    func vivas() async -> Set<String> {
        await withCheckedContinuation { (c: CheckedContinuation<Set<String>, Never>) in
            sesion.getAllTasks { tareas in
                c.resume(returning: Set(tareas.compactMap { $0.taskDescription }))
            }
        }
    }

    // MARK: URLSessionDataDelegate

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard let intento = task.taskDescription, totalBytesExpectedToSend > 0 else { return }
        let ahora = Date()
        if let antes = ultimoAviso[intento], ahora.timeIntervalSince(antes) < 0.5 { return }
        ultimoAviso[intento] = ahora
        let p = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        Task { @MainActor in Escalada.shared.emite(intento, "subiendo", progreso: p) }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        respuestas[dataTask.taskIdentifier, default: Data()].append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let cuerpo = respuestas.removeValue(forKey: task.taskIdentifier) ?? Data()
        guard let intento = task.taskDescription else { return }
        ultimoAviso[intento] = nil
        let http = task.response as? HTTPURLResponse
        let objeto = try? JSONSerialization.jsonObject(with: cuerpo) as? [String: Any]
        var fallo: String?
        if let error {
            fallo = "Sin conexión con el servidor: \(error.localizedDescription)"
        } else if let host = http?.url?.host, host != Config.web.host {
            fallo = "Cloudflare Access no acepta el service token (CF-Access-Client-Id/Secret)"
        } else if let codigo = http?.statusCode, !(200..<300).contains(codigo) {
            fallo = (objeto?["detail"] as? String)
                ?? (codigo == 413 ? "Demasiado grande: Cloudflare no deja pasar más de 100 MB" : "Error \(codigo) del servidor")
        } else if http == nil {
            fallo = "Respuesta rara del servidor"
        }
        let registro = RegistroSubidas.todas().first { $0.intento == intento }
        if let fallo {
            RegistroSubidas.marcaError(intento, fallo)
            Self.notifica("No se ha podido subir el intento", fallo + " · Reinténtalo desde «Subir intento» en Entreno.")
            Task { @MainActor in
                Escalada.shared.emite(intento, "error", texto: fallo, datos: registro)
                Escalada.shared.refrescaFallidas()
            }
        } else {
            let texto = (objeto?["texto"] as? String) ?? "Recibido: te aviso por Telegram cuando esté analizado."
            if let registro {
                try? FileManager.default.removeItem(at: ArchivosEscalada.carpeta.appendingPathComponent(registro.fichero))
            }
            RegistroSubidas.quita(intento)
            Self.notifica("Intento subido", texto)
            Task { @MainActor in
                Escalada.shared.emite(intento, "listo", texto: texto, datos: registro)
                Escalada.shared.refrescaFallidas()
            }
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.alAcabar?()
            self.alAcabar = nil
        }
    }

    private static func notifica(_ titulo: String, _ cuerpo: String) {
        let c = UNMutableNotificationContent()
        c.title = titulo
        c.body = cuerpo
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "escalada-\(UUID().uuidString)",
                                                                     content: c, trigger: nil),
                                               withCompletionHandler: nil)
    }
}

// MARK: - la vista previa con Vision

/// Esqueleto (VNDetectHumanBodyPoseRequest) a ~5 fps, como mucho 300 fotogramas, y el centro de gravedad aproximado.
/// JSON: {fps, ancho, alto, fotogramas: [[t, cx, cy, [[x, y, c] × 19]]], meta, primero}; coordenadas 0-1 con la y
/// hacia abajo, como las dibuja la web (entreno.html, vistaPrevia). cx y cy son null si no se ve el cuerpo.
enum VistaPrevia {
    /// El orden lo usa también la web (HUESOS en entreno.html): no cambiarlo.
    static let articulaciones: [VNHumanBodyPoseObservation.JointName] = [
        .nose, .leftEye, .rightEye, .leftEar, .rightEar, .leftShoulder, .rightShoulder, .neck,
        .leftElbow, .rightElbow, .leftWrist, .rightWrist, .root, .leftHip, .rightHip,
        .leftKnee, .rightKnee, .leftAnkle, .rightAnkle,
    ]
    /// Caderas, hombros y rodillas (índices de arriba) y lo que pesa cada uno en la media.
    private static let pesos: [(Int, Double)] = [(13, 3), (14, 3), (5, 2), (6, 2), (15, 1), (16, 1)]

    static func saca(_ url: URL, meta: [String: String]) async throws -> Data {
        let asset = AVURLAsset(url: url)
        let duracion = try await asset.load(.duration).seconds
        guard duracion.isFinite, duracion > 0,
              let pista = try await asset.loadTracks(withMediaType: .video).first else {
            throw APIError(mensaje: "El vídeo no tiene imagen")
        }
        let (tam, giro) = try await pista.load(.naturalSize, .preferredTransform)
        let caja = CGRect(origin: .zero, size: tam).applying(giro)
        let n = max(1, min(300, Int(duracion * 5)))
        let paso = duracion / Double(n)

        let generador = AVAssetImageGenerator(asset: asset)
        generador.appliesPreferredTrackTransform = true
        generador.maximumSize = CGSize(width: 640, height: 640)
        let margen = CMTime(seconds: paso / 2, preferredTimescale: 600)
        generador.requestedTimeToleranceBefore = margen
        generador.requestedTimeToleranceAfter = margen

        var fotogramas: [Any] = []
        var primero: String?
        for i in 0..<n {
            if Task.isCancelled { break }
            guard let r = try? await generador.image(at: CMTime(seconds: Double(i) * paso, preferredTimescale: 600)) else {
                continue
            }
            if primero == nil, let jpg = UIImage(cgImage: r.image).jpegData(compressionQuality: 0.6) {
                primero = "data:image/jpeg;base64," + jpg.base64EncodedString()
            }
            let puntos = pose(r.image)
            let (cx, cy) = centro(puntos)
            fotogramas.append([redondea(max(0, r.actualTime.seconds)), valor(cx), valor(cy), puntos] as [Any])
        }
        guard !fotogramas.isEmpty else { throw APIError(mensaje: "No se ha podido leer ningún fotograma") }
        var json: [String: Any] = ["fps": Double(n) / duracion, "ancho": Int(abs(caja.width)), "alto": Int(abs(caja.height)),
                                   "fotogramas": fotogramas, "meta": meta]
        if let primero, primero.count < 390_000 { json["primero"] = primero }
        return try JSONSerialization.data(withJSONObject: json)
    }

    /// Los 19 puntos [x, y, confianza] de la persona más clara del fotograma; [0, 0, 0] los que no se ven.
    private static func pose(_ imagen: CGImage) -> [[Double]] {
        let vacio = Array(repeating: [0.0, 0.0, 0.0], count: articulaciones.count)
        let peticion = VNDetectHumanBodyPoseRequest()
        let manejador = VNImageRequestHandler(cgImage: imagen, options: [:])
        guard (try? manejador.perform([peticion])) != nil,
              let cuerpo = (peticion.results ?? []).max(by: { confianza($0) < confianza($1) }),
              let puntos = try? cuerpo.recognizedPoints(.all) else { return vacio }
        return articulaciones.map { j -> [Double] in
            guard let p = puntos[j], p.confidence > 0 else { return [0, 0, 0] }
            return [redondea(Double(p.location.x)), redondea(1 - Double(p.location.y)), redondea(Double(p.confidence))]
        }
    }

    private static func confianza(_ cuerpo: VNHumanBodyPoseObservation) -> Double {
        guard let puntos = try? cuerpo.recognizedPoints(.all) else { return 0 }
        return puntos.values.reduce(0) { $0 + Double($1.confidence) }
    }

    private static func centro(_ puntos: [[Double]]) -> (Double?, Double?) {
        var x = 0.0, y = 0.0, w = 0.0
        for (i, peso) in pesos where puntos[i][2] > 0.3 {
            x += puntos[i][0] * peso
            y += puntos[i][1] * peso
            w += peso
        }
        guard w > 0 else { return (nil, nil) }
        return (x / w, y / w)
    }

    private static func redondea(_ v: Double) -> Double {
        v.isFinite ? (v * 1000).rounded() / 1000 : 0
    }

    private static func valor(_ v: Double?) -> Any {
        if let v { return redondea(v) }
        return NSNull()
    }
}

// MARK: - la hoja

struct HojaEscalada: View {
    @Environment(\.dismiss) private var cerrar
    @State private var elegido: PhotosPickerItem?
    @State private var color = ""
    @State private var resultado = "probando"
    @State private var angulo = 1
    @State private var nombre = ""
    @State private var nivel = 0
    @State private var quien = ""

    private var escalada: Escalada { Escalada.shared }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                Section {
                    PhotosPicker(selection: $elegido, matching: .videos, preferredItemEncoding: .current) {
                        Label(elegido == nil ? "Elegir el vídeo" : "Vídeo elegido · cambiar", systemImage: "video")
                    }
                }
                Section("El bloque") {
                    Picker("Color de las presas", selection: $color) {
                        Text("Elige").tag("")
                        ForEach(escalada.colores, id: \.self) { c in
                            Text(c.capitalized).tag(c)
                        }
                    }
                    Picker("Cómo fue", selection: $resultado) {
                        Text("Hecho").tag("hecho")
                        Text("Me caí").tag("caida")
                        Text("Probando").tag("probando")
                    }
                    .pickerStyle(.segmented)
                    Picker("Ángulo", selection: $angulo) {
                        ForEach(1...4, id: \.self) { n in
                            Text("\(n)").tag(n)
                        }
                    }
                    TextField("Nombre del bloque (opcional)", text: $nombre)
                    Picker("Nivel", selection: $nivel) {
                        Text("Sin nivel").tag(0)
                        ForEach(1...10, id: \.self) { n in
                            Text("\(n)").tag(n)
                        }
                    }
                    TextField("Quién escala", text: $quien)
                }
                Section {
                    Button("Subir") { sube() }
                        .disabled(elegido == nil || color.isEmpty || escalada.trabajo != nil)
                    if let trabajo = escalada.trabajo {
                        HStack {
                            Text(trabajo)
                            Spacer()
                            if let p = escalada.progreso {
                                ProgressView(value: p)
                                    .frame(width: 110)
                            } else {
                                ProgressView()
                            }
                        }
                    }
                    if let aviso = escalada.aviso {
                        Text(aviso)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Se comprime en el iPhone y sube en segundo plano. Mientras, el iPhone saca una vista previa del esqueleto; el análisis completo llega por Telegram y en Entreno.")
                }
                if !escalada.fallidas.isEmpty {
                    Section("No se han podido subir") {
                        ForEach(escalada.fallidas) { d in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(d.nombre.isEmpty ? "Bloque \(d.color)" : d.nombre) · \(Escalada.hora(d.intento))")
                                Text(d.error ?? "")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                HStack {
                                    Button("Reintentar") { escalada.reintenta(d) }
                                    Spacer()
                                    Button("Descartar", role: .destructive) { escalada.descarta(d) }
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                }
                .listRowBackground(Tema.carta)
            }
            .scrollContentBackground(.hidden)
            .background(Tema.fondo)
            .navigationTitle("Subir intento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { cerrar() }
                }
            }
            .task {
                await escalada.prepara()
                if quien.isEmpty { quien = escalada.quien }
            }
        }
    }

    private func sube() {
        guard let elegido else { return }
        var d = DatosIntento()
        d.angulo = angulo
        d.quien = quien.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? escalada.quien : quien
        d.color = color
        d.nombre = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        d.resultado = resultado
        d.nivel = nivel == 0 ? nil : nivel
        escalada.empieza(elegido, d)
        self.elegido = nil
        nombre = ""
    }
}
