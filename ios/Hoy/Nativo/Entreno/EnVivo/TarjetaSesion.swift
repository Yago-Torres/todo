import SwiftUI
import UIKit

/// «Hoy en el rocódromo»: una imagen para compartir con los intentos de hoy (bloques, encadenados, nivel máximo y
/// tiempo, del primer intento al último).
struct ResumenSesion {
    var intentos: Int
    var bloques: Int
    var encadenados: Int
    var nivelMax: Int?
    var minutos: Int?
    var colores: [String]

    @MainActor static func hoy() -> ResumenSesion {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"
        let dia = f.string(from: Date())
        let xs = EscaladaDatos.shared.intentos.filter { $0.intento.hasPrefix(dia) }
        let pendientes = EscaladaDatos.shared.pendientes.filter { p in
            p.intento.hasPrefix(dia) && !xs.contains { $0.intento == p.intento }
        }
        var orden: [String] = []
        var colores: [String: String] = [:]
        for x in xs where !orden.contains(x.bloque) {
            orden.append(x.bloque)
            colores[x.bloque] = x.color
        }
        let encadenados = Set(xs.filter { $0.resultado == "hecho" }.map(\.bloque)).count
        let horas = (xs.map(\.intento) + pendientes.map(\.intento)).compactMap(segundos).sorted()
        let minutos = horas.count >= 2 ? max(1, (horas.last! - horas.first!) / 60) : nil
        return ResumenSesion(intentos: xs.count + pendientes.count, bloques: orden.count, encadenados: encadenados,
                             nivelMax: xs.compactMap(\.dificultad).max(), minutos: minutos,
                             colores: orden.compactMap { colores[$0] })
    }

    /// 20261113-183005 → segundos del día.
    private static func segundos(_ i: String) -> Int? {
        let c = Array(i)
        guard c.count == 15, let h = Int(String(c[9...10])), let m = Int(String(c[11...12])), let s = Int(String(c[13...14])) else {
            return nil
        }
        return h * 3600 + m * 60 + s
    }

    var tiempo: String {
        guard let minutos else { return "–" }
        return minutos >= 60 ? "\(minutos / 60) h \(minutos % 60) min" : "\(minutos) min"
    }
}

/// La tarjeta en sí (4:5), con los colores y letras del tema.
struct VistaTarjetaSesion: View {
    let r: ResumenSesion

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Hoy en el rocódromo").estiloEtiqueta().foregroundStyle(Tema.acento)
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "es_ES"))).capitalized)
                .font(Tema.fuente(.titulo)).foregroundStyle(Tema.texto)
            Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                GridRow {
                    cifra("\(r.bloques)", r.bloques == 1 ? "bloque" : "bloques")
                    cifra("\(r.encadenados)", r.encadenados == 1 ? "encadenado" : "encadenados", acento: true)
                }
                GridRow {
                    cifra(r.nivelMax.map { "\($0)" } ?? "–", "nivel máximo")
                    cifra(r.tiempo, "escalando")
                }
            }
            if !r.colores.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(r.colores.prefix(12).enumerated()), id: \.offset) { _, c in
                        Circle().fill(EscaladaDatos.color(c)).frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(Tema.linea, lineWidth: 1))
                    }
                }
            }
            Spacer(minLength: 0)
            HStack {
                Text("\(r.intentos) \(r.intentos == 1 ? "intento" : "intentos")")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                Spacer()
                Label("Tom", systemImage: "figure.climbing")
                    .font(Tema.fuente(.pequeno, peso: .semibold)).foregroundStyle(Tema.suave)
            }
        }
        .padding(28)
        .frame(width: 360, height: 450, alignment: .topLeading)
        .background(Tema.fondo)
    }

    private func cifra(_ v: String, _ t: String, acento: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(v).font(Tema.fuente(.cifra)).foregroundStyle(acento ? Tema.acentoTexto : Tema.texto)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(t).font(Tema.fuente(.pequeno)).foregroundStyle(acento ? Tema.acentoTexto : Tema.suave)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(acento ? Tema.acento : Tema.carta, in: RoundedRectangle(cornerRadius: Tema.Radio.carta))
    }
}

struct HojaTarjetaSesion: View {
    @Environment(\.dismiss) private var cerrar
    @Environment(\.colorScheme) private var esquema
    @State private var imagen: UIImage?
    @State private var compartir = false
    @State private var aviso: String?
    @State private var guardando = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Tema.Espacio.l) {
                    let r = ResumenSesion.hoy()
                    if r.intentos == 0 {
                        Text("Hoy aún no hay intentos. Graba o sube alguno y vuelve aquí.")
                            .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                            .multilineTextAlignment(.center)
                    }
                    VistaTarjetaSesion(r: r)
                        .clipShape(RoundedRectangle(cornerRadius: Tema.Radio.carta))
                        .shadow(color: Tema.linea, radius: 8)
                        .accessibilityElement(children: .combine)
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
                    .disabled(guardando)
                    if let aviso {
                        Text(aviso).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                    }
                }
                .padding(Tema.Espacio.l)
            }
            .background(Tema.fondo)
            .navigationTitle("Tarjeta de hoy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { cerrar() }
                }
            }
            .task { renderiza() }
            .sheet(isPresented: $compartir) {
                if let imagen {
                    HojaCompartir(cosas: [imagen]).presentationDetents([.medium, .large])
                }
            }
        }
    }

    private func renderiza() {
        let r = ImageRenderer(content: VistaTarjetaSesion(r: ResumenSesion.hoy()).environment(\.colorScheme, esquema))
        r.scale = 3
        imagen = r.uiImage
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
