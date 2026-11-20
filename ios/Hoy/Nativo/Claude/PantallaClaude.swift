import SwiftUI

/// «Claude»: un Claude que sabe todo lo tuyo (hábitos, entrenos, carrera, sueño, gastos, cartera, calendario,
/// pendientes, lo que usas y `yo.md`), puede leer tu vault de Obsidian y buscar en la web (charla.py del servidor).
/// Conversaciones con hilo: ve los últimos turnos de la suya. Tarda de 15 s a un minuto; puedes irte y volver
/// (se contesta en el servidor y aquí se mira cada 3 s mientras piensa). No cambia nada: para eso, la voz de Tom.

struct MensajeClaude: Decodable, Identifiable, Hashable {
    var id: String
    var hilo: String
    var q: String
    var r: String
    var estado: String
    var cuando: String
}

struct HiloClaude: Decodable, Identifiable, Hashable {
    var hilo: String
    var mensajes: [MensajeClaude]
    var cuando: String
    var id: String { hilo }
}

@MainActor @Observable
final class DatosClaude {
    static let shared = DatosClaude()
    var hilos: [HiloClaude] = []
    var actual: String?   // nil: conversación nueva
    var cargado = false
    var error: String?

    var mensajes: [MensajeClaude] { hilos.first { $0.hilo == actual }?.mensajes ?? [] }
    var pensando: Bool { hilos.contains { $0.mensajes.contains { $0.estado == "pensando" } } }

    func carga() async {
        struct R: Decodable { var hilos: [HiloClaude] }
        do {
            let d = try await API.datos("/api/charla")
            let r = try JSONDecoder().decode(R.self, from: d)
            withAnimation(Tema.Muelle.pantalla) { hilos = r.hilos }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        cargado = true
    }

    func pregunta(_ q: String) async -> Bool {
        var json: [String: Any] = ["q": q]
        if let actual { json["hilo"] = actual }
        do {
            let d = try await API.datos("/api/charla", metodo: "POST", json: json)
            if let m = try? JSONDecoder().decode(MensajeClaude.self, from: d) { actual = m.hilo }
            Haptica.shared.toca(.marcar)
            await carga()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func borraHilo(_ hilo: String) async {
        _ = try? await API.datos("/api/charla/borra", metodo: "POST", json: ["hilo": hilo])
        if actual == hilo { actual = nil }
        await carga()
    }
}

struct PantallaClaude: View {
    @State private var datos = DatosClaude.shared
    @State private var texto = ""
    @State private var enviando = false
    @State private var verHilos = false
    @FocusState private var enfocado: Bool

    private static let sugerencias = [
        "¿Cómo voy esta semana y qué priorizo mañana?",
        "¿Qué hábito se me está cayendo y por qué?",
        "¿Duermo peor los días que entreno tarde?",
        "¿En qué se me va el dinero este ciclo?",
        "¿Qué tengo pendiente que se me esté olvidando?",
        "Resúmeme lo que escribí en el vault esta semana",
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { lector in
                ScrollView {
                    VStack(alignment: .leading, spacing: Tema.Espacio.l) {
                        cabecera
                        if datos.mensajes.isEmpty {
                            vacio
                        }
                        ForEach(datos.mensajes) { m in
                            burbujas(m).id(m.id)
                        }
                        if let e = datos.error {
                            Label(e, systemImage: "exclamationmark.triangle").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro)
                        }
                        Color.clear.frame(height: 1).id("fin")
                    }
                    .padding(.horizontal, Tema.Espacio.l)
                    .padding(.top, Tema.Espacio.s)
                    .padding(.bottom, Tema.Espacio.l)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: datos.mensajes.last?.estado) { _, _ in
                    withAnimation(Tema.Muelle.pantalla) { lector.scrollTo("fin", anchor: .bottom) }
                }
                .onChange(of: datos.actual) { _, _ in lector.scrollTo("fin", anchor: .bottom) }
            }
            caja
                .padding(.horizontal, Tema.Espacio.l)
                .padding(.bottom, 96)   // la barra de abajo
        }
        .task { await vigila() }
        .sheet(isPresented: $verHilos) { listaHilos }
    }

    private var cabecera: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sabe todo lo tuyo").estiloEtiqueta().foregroundStyle(Tema.suave)
                Text("Claude").font(Tema.fuente(.titulo)).foregroundStyle(Tema.texto)
            }
            Spacer()
            if !datos.hilos.isEmpty {
                Button { verHilos = true } label: { Image(systemName: "clock.arrow.circlepath") }
                    .accessibilityLabel("Conversaciones")
            }
            Button {
                withAnimation(Tema.Muelle.pantalla) { datos.actual = nil }
                enfocado = true
            } label: { Image(systemName: "square.and.pencil") }
                .accessibilityLabel("Conversación nueva")
                .padding(.leading, Tema.Espacio.m)
        }
        .font(.title3)
        .tint(Tema.acento)
    }

    private var vacio: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            Text("Pregúntale lo que quieras sobre ti: tus hábitos, entrenos, carrera, sueño, gastos, cartera, calendario, pendientes o lo que tienes en el vault. Puede buscar en la web. No cambia nada: para apuntar o mover cosas, la voz de Tom.")
                .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            ForEach(Self.sugerencias, id: \.self) { s in
                Button {
                    texto = s
                    enfocado = true
                } label: {
                    Text(s).font(Tema.fuente(.pequeno)).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Tema.Espacio.s + 2)
                        .background(Tema.carta, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Tema.texto)
            }
        }
    }

    @ViewBuilder
    private func burbujas(_ m: MensajeClaude) -> some View {
        HStack {
            Spacer(minLength: 48)
            Text(m.q)
                .font(Tema.fuente(.texto)).foregroundStyle(Tema.acentoTexto)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Tema.acento, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            switch m.estado {
            case "pensando":
                HStack(spacing: Tema.Espacio.s) {
                    ProgressView()
                    Text("Mirando tus datos…").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                }
            case "error":
                Text(m.r).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro)
            default:
                MarkdownInv(texto: m.r)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .carta()
    }

    private var caja: some View {
        HStack(alignment: .bottom, spacing: Tema.Espacio.s) {
            TextField(datos.actual == nil ? "Pregúntale a Claude" : "Sigue la conversación", text: $texto, axis: .vertical)
                .lineLimit(1...5)
                .focused($enfocado)
                .font(Tema.fuente(.texto))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Tema.carta, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Button {
                Task { await envia() }
            } label: {
                Image(systemName: enviando ? "ellipsis" : "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Tema.acentoTexto)
                    .frame(width: 40, height: 40)
                    .background(Tema.acento, in: Circle())
            }
            .disabled(enviando || texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Enviar")
        }
        .padding(.top, Tema.Espacio.s)
    }

    private var listaHilos: some View {
        NavigationStack {
            List {
                ForEach(datos.hilos) { h in
                    Button {
                        datos.actual = h.hilo
                        verHilos = false
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(h.mensajes.first?.q ?? "").lineLimit(2).foregroundStyle(Tema.texto)
                            Text("\(h.cuando.replacingOccurrences(of: "T", with: " · ")) · \(h.mensajes.count) \(h.mensajes.count == 1 ? "mensaje" : "mensajes")")
                                .font(.caption).foregroundStyle(Tema.suave)
                        }
                    }
                    .swipeActions {
                        Button("Borrar", role: .destructive) { Task { await datos.borraHilo(h.hilo) } }
                    }
                }
            }
            .navigationTitle("Conversaciones")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { verHilos = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func envia() async {
        let q = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        enviando = true
        if await datos.pregunta(q) {
            texto = ""
            enfocado = false
        }
        enviando = false
    }

    /// Mientras la pantalla está a la vista: carga y, si algo piensa, vuelve a mirar cada 3 s.
    private func vigila() async {
        await datos.carga()
        if datos.actual == nil, let ultimo = datos.hilos.first, ultimo.mensajes.contains(where: { $0.estado == "pensando" }) {
            datos.actual = ultimo.hilo
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            if datos.pensando { await datos.carga() }
        }
    }
}
