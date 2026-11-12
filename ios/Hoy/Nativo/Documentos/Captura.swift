import SwiftUI
import UIKit
import VisionKit
import PDFKit

/// El escáner de documentos de iOS (VisionKit): recorta, endereza y junta las páginas en un PDF.
struct EscanerDocumentos: UIViewControllerRepresentable {
    let alTerminar: (Data) -> Void
    let alFallar: (String) -> Void
    let cierra: () -> Void

    static var disponible: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let c = VNDocumentCameraViewController()
        c.delegate = context.coordinator
        return c
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinador { Coordinador(self) }

    final class Coordinador: NSObject, VNDocumentCameraViewControllerDelegate {
        let padre: EscanerDocumentos
        init(_ padre: EscanerDocumentos) { self.padre = padre }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pdf = PDFDocument()
            for i in 0..<scan.pageCount {
                if let pagina = PDFPage(image: scan.imageOfPage(at: i)) { pdf.insert(pagina, at: pdf.pageCount) }
            }
            if let datos = pdf.dataRepresentation(), pdf.pageCount > 0 {
                padre.alTerminar(datos)
            } else {
                padre.alFallar("No he podido montar el PDF con lo escaneado. Vuelve a intentarlo.")
            }
            padre.cierra()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            padre.cierra()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            padre.alFallar("El escáner ha fallado: \(error.localizedDescription)")
            padre.cierra()
        }
    }
}

/// La cámara para una foto suelta (un recibo, el DNI de frente…). Sale en JPEG.
struct CamaraFoto: UIViewControllerRepresentable {
    let alTerminar: (Data) -> Void
    let cierra: () -> Void

    static var disponible: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = .camera
        c.delegate = context.coordinator
        return c
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinador { Coordinador(self) }

    final class Coordinador: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let padre: CamaraFoto
        init(_ padre: CamaraFoto) { self.padre = padre }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let imagen = info[.originalImage] as? UIImage, let datos = imagen.jpegData(compressionQuality: 0.85) {
                padre.alTerminar(datos)
            }
            padre.cierra()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            padre.cierra()
        }
    }
}
