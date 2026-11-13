import AVKit
import Observation
import Photos
import SwiftUI
import UIKit

/// Lo que se abre desde el bloque de escalada (y desde el acceso del icono): el modo en vivo, el vídeo para presumir
/// y la tarjeta de la sesión. Vive aquí y no en una vista para que el acceso del icono lo pida antes de que exista
/// la pantalla de Entreno.
@MainActor @Observable
final class VivoEscalada {
    static let shared = VivoEscalada()
    var enVivo = false
    private init() {}

    /// Desde el acceso del icono o el atajo: Entreno delante y la cámara encima.
    func abre() {
        enVivo = true
        Navegador.shared.abre("/entreno.html")
    }
}

/// La hoja de compartir de iOS (historias, WhatsApp, AirDrop…).
struct HojaCompartir: UIViewControllerRepresentable {
    let cosas: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: cosas, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Guardar vídeos o imágenes en Fotos (solo pide permiso para añadir, no para ver tu fototeca).
enum Fototeca {
    static func guarda(videos: [URL] = [], imagen: UIImage? = nil) async throws {
        let estado = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard estado == .authorized || estado == .limited else {
            throw APIError(mensaje: "Tom no tiene permiso para guardar en Fotos. Actívalo en Ajustes > Tom > Fotos.")
        }
        try await PHPhotoLibrary.shared().performChanges {
            for u in videos { _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: u) }
            if let imagen { _ = PHAssetChangeRequest.creationRequestForAsset(from: imagen) }
        }
    }
}

/// Un vídeo local en bucle, sin controles (para ver lo grabado al momento).
struct BucleVideo: View {
    let url: URL
    @State private var jugador: AVQueuePlayer?
    @State private var bucle: AVPlayerLooper?

    var body: some View {
        Group {
            if let jugador {
                VideoPlayer(player: jugador)
            } else {
                Rectangle().fill(Tema.carta2)
            }
        }
        .onAppear {
            guard jugador == nil else { return }
            let j = AVQueuePlayer()
            j.isMuted = true
            bucle = AVPlayerLooper(player: j, templateItem: AVPlayerItem(url: url))
            jugador = j
            j.play()
        }
        .onDisappear {
            jugador?.pause()
        }
    }
}
