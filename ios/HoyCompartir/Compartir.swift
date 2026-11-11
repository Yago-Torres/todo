import SwiftUI
import UIKit
import UniformTypeIdentifiers

// «Leer luego» en la hoja de compartir (Safari o un texto con un enlace): manda la URL a todo y se cierra sola.
// todo guarda la nota al momento y el bot la resume con Claude en su siguiente vuelta (POST /api/leer/pendiente),
// así que aquí no se espera a ningún resumen. Las claves son las del app group (Almacen), las mismas de la app.

@objc(CompartirControlador)
final class CompartirControlador: UIViewController {
    private let estado = EstadoCompartir()
    private var cerrado = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let hoja = UIHostingController(rootView: HojaCompartir(estado: estado, cerrar: { [weak self] in self?.cierra() }))
        hoja.view.backgroundColor = .clear
        hoja.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(hoja)
        view.addSubview(hoja.view)
        NSLayoutConstraint.activate([
            hoja.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hoja.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hoja.view.topAnchor.constraint(equalTo: view.topAnchor),
            hoja.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hoja.didMove(toParent: self)
        Task { await guarda() }
    }

    private func guarda() async {
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        guard let enlace = await EnlaceCompartido.de(items) else {
            estado.fase = .fallo("No encuentro ningún enlace que guardar")
            cierraLuego(3)
            return
        }
        do {
            let texto = try await API.guardaParaLeer(url: enlace.url.absoluteString, titulo: enlace.titulo)
            estado.fase = .listo(texto)
            cierraLuego(1.2)
        } catch {
            estado.fase = .fallo(error.localizedDescription)
            cierraLuego(4)
        }
    }

    private func cierraLuego(_ segundos: Double) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(segundos * 1_000_000_000))
            self?.cierra()
        }
    }

    private func cierra() {
        guard !cerrado else { return }
        cerrado = true
        extensionContext?.completeRequest(returningItems: nil)
    }
}

// MARK: qué se ha compartido

struct EnlaceCompartido {
    let url: URL
    let titulo: String?

    /// La URL que manda Safari (o cualquier app que comparta un enlace); si no, la primera URL de un texto.
    /// El título: el texto que acompaña al enlace, si lo hay (todo pone el dominio si no).
    static func de(_ items: [NSExtensionItem]) async -> EnlaceCompartido? {
        var textos: [String] = []
        for item in items {
            if let t = item.attributedContentText?.string { textos.append(t) }
            if let t = item.attributedTitle?.string { textos.append(t) }
        }
        for item in items {
            for proveedor in item.attachments ?? [] {
                if proveedor.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = await cargaURL(de: proveedor), esWeb(url) {
                    return EnlaceCompartido(url: url, titulo: titulo(textos, sin: url))
                }
                if proveedor.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let t = try? await proveedor.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    textos.append(t)
                }
            }
        }
        for t in textos {
            if let url = primeraURL(t) {
                return EnlaceCompartido(url: url, titulo: titulo(textos, sin: url))
            }
        }
        return nil
    }

    private static func cargaURL(de proveedor: NSItemProvider) async -> URL? {
        guard let dato = try? await proveedor.loadItem(forTypeIdentifier: UTType.url.identifier) else { return nil }
        if let u = dato as? URL { return u }
        if let d = dato as? Data { return URL(dataRepresentation: d, relativeTo: nil) }
        if let s = dato as? String { return URL(string: s) }
        return nil
    }

    private static func esWeb(_ url: URL) -> Bool {
        url.scheme == "http" || url.scheme == "https"
    }

    private static func primeraURL(_ texto: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let rango = NSRange(texto.startIndex..., in: texto)
        let urls = detector.matches(in: texto, options: [], range: rango).compactMap { $0.url }
        return urls.first(where: { esWeb($0) })
    }

    /// El primer texto que no sea la propia URL, sin la URL dentro y en una línea.
    private static func titulo(_ textos: [String], sin url: URL) -> String? {
        for t in textos {
            let limpio = t.replacingOccurrences(of: url.absoluteString, with: " ")
                .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            if !limpio.isEmpty, primeraURL(limpio) == nil { return String(limpio.prefix(200)) }
        }
        return nil
    }
}

// MARK: la hoja

@MainActor
final class EstadoCompartir: ObservableObject {
    enum Fase {
        case guardando
        case listo(String)
        case fallo(String)
    }

    @Published var fase: Fase = .guardando
}

struct HojaCompartir: View {
    @ObservedObject var estado: EstadoCompartir
    let cerrar: () -> Void

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                icono
                    .frame(height: 48)
                Text(titulo)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                if case .fallo(let motivo) = estado.fase {
                    Text(motivo)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Cerrar", action: cerrar)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(16)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var icono: some View {
        switch estado.fase {
        case .guardando:
            ProgressView()
                .controlSize(.large)
        case .listo:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
        case .fallo:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
        }
    }

    private var titulo: String {
        switch estado.fase {
        case .guardando: return "Guardando en Leer luego…"
        case .listo(let texto): return texto
        case .fallo: return "No se ha podido guardar"
        }
    }
}
