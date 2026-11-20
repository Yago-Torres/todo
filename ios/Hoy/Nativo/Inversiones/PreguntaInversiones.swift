import SwiftUI

/// «Pregunta» (como en la web): una pregunta a Claude que sabe tu cartera, la review y el informe de mercado, y que
/// puede buscar en la web. El servidor contesta en un hilo (tarda de 20 s a un par de minutos); aquí se mira la lista
/// cada 3 s mientras alguna está «pensando».

struct PreguntaInv: Decodable, Identifiable, Hashable {
    var id: String
    var q: String
    var r: String
    var estado: String
    var cuando: String
    /// «compara» para las del comparador de Explorar (con su `titulo`, «A frente a B»); nada en las de siempre.
    var tipo: String? = nil
    var titulo: String? = nil
}

extension DatosInversiones {
    func preguntas() async -> [PreguntaInv]? {
        struct R: Decodable { var preguntas: [PreguntaInv] }
        guard let d = try? await API.datos("/api/inversiones/preguntas") else { return nil }
        return (try? JSONDecoder().decode(R.self, from: d))?.preguntas
    }

    func pregunta(_ q: String) async -> Bool {
        do {
            _ = try await API.datos("/api/inversiones/pregunta", metodo: "POST", json: ["q": q])
            Haptica.shared.toca(.marcar)
            return true
        } catch {
            avisa("No se ha enviado: \(error.localizedDescription)", error: true)
            return false
        }
    }

    func borraPregunta(_ id: String) async {
        _ = try? await API.datos("/api/inversiones/pregunta/borra", metodo: "POST", json: ["id": id])
    }
}

struct PreguntaInversiones: View {
    @State private var datos = DatosInversiones.shared
    @State private var lista: [PreguntaInv] = []
    @State private var cargado = false
    @State private var texto = ""
    @State private var enviando = false
    @FocusState private var enfocado: Bool

    private static let sugerencias = ["¿Estoy demasiado concentrado?", "¿Qué pasa con mi cartera si la bolsa cae un 30 %?",
                                      "¿Me conviene un plan de ahorro en un ETF mundial?", "Explícame cómo tributan mis ganancias"]

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.l) {
            VStack(alignment: .leading, spacing: Tema.Espacio.m) {
                Text("Pregúntale a Claude").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
                Text("Sabe tu cartera, tu perfil, la última review y el informe de mercado, y puede buscar en la web. Tarda de 20 segundos a un par de minutos: puedes irte y volver.")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                TextField("Tu pregunta", text: $texto, axis: .vertical)
                    .lineLimit(2...6)
                    .focused($enfocado)
                    .font(Tema.fuente(.texto))
                    .padding(Tema.Espacio.m)
                    .background(Tema.texto.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                ScrollView(.horizontal) {
                    HStack(spacing: Tema.Espacio.s) {
                        ForEach(Self.sugerencias, id: \.self) { s in
                            Button(s) { texto = s; enfocado = true }
                                .font(Tema.fuente(.pequeno)).buttonStyle(.bordered).tint(Tema.acento)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .sinDeslizarSeccion()
                Button {
                    Task { await envia() }
                } label: {
                    Label(enviando ? "Enviando…" : "Preguntar", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Tema.acento)
                .disabled(enviando || texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .carta()

            if cargado && lista.isEmpty {
                Text("Aún no has preguntado nada.").font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            }
            ForEach(lista) { p in
                VStack(alignment: .leading, spacing: Tema.Espacio.s) {
                    Text(p.titulo ?? p.q).font(Tema.fuente(.texto, peso: .semibold)).foregroundStyle(Tema.texto)
                    switch p.estado {
                    case "pensando":
                        HStack(spacing: Tema.Espacio.s) {
                            ProgressView()
                            Text("Pensando… (puede buscar en la web)").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                        }
                    case "error":
                        Text(p.r).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro)
                    default:
                        MarkdownInv(texto: p.r)
                    }
                    HStack {
                        Text(p.cuando.replacingOccurrences(of: "T", with: " · "))
                            .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                        Spacer()
                        Button("Borrar", role: .destructive) {
                            Task {
                                await datos.borraPregunta(p.id)
                                withAnimation(Tema.Muelle.pantalla) { lista.removeAll { $0.id == p.id } }
                            }
                        }
                        .font(Tema.fuente(.pequeno))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .carta()
            }
        }
        .task { await vigila() }
    }

    private func envia() async {
        let q = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        enviando = true
        if await datos.pregunta(q) {
            texto = ""
            enfocado = false
            await recarga()
        }
        enviando = false
    }

    private func recarga() async {
        if let l = await datos.preguntas() {
            withAnimation(Tema.Muelle.pantalla) { lista = l }
        }
        cargado = true
    }

    /// Mientras la vista está en pantalla: carga y, si algo está pensando, vuelve a mirar cada 3 s.
    private func vigila() async {
        await recarga()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            if lista.contains(where: { $0.estado == "pensando" }) { await recarga() }
        }
    }
}
