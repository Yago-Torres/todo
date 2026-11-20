import SwiftUI

/// «Explorar» (como en la web, explorar.py del servidor): ideas del mes que estudiar —temas, fondos y empresas— pensadas
/// para tu cartera y tu perfil, con el porqué, el mejor argumento en contra y cómo se compraría. Lo que respondes a cada
/// idea («Me interesa», «Ya lo tengo», «Descartar») afina las siguientes. Abajo, el comparador de dos fondos o acciones,
/// que va por la Pregunta de siempre (tipo «compara»). Mientras algo piensa, se mira cada 4 s.

struct IdeaExplorar: Decodable, Identifiable, Hashable {
    var id: String
    var tipo: String
    var nombre: String
    var ticker: String
    var isin: String
    var gancho: String
    var porQueTu: String
    var tesis: String
    var contra: String
    var riesgos: [String]
    var como: String
    var encaje: String
    var senales: String
    var riesgo: Int
    var horizonte: String
    var dato: String
    var fuentes: [String]

    enum CodingKeys: String, CodingKey {
        case id, tipo, nombre, ticker, isin, gancho, tesis, contra, riesgos, como, encaje, senales, riesgo, horizonte, dato, fuentes
        case porQueTu = "por_que_tu"
    }

    var codigo: String { [ticker, isin].filter { !$0.isEmpty }.joined(separator: " · ") }
    var nombreTipo: String { ["tema": "Tema", "fondo": "Fondo / ETF", "empresa": "Empresa"][tipo] ?? tipo }
}

struct InformeExplorar: Decodable, Identifiable, Hashable {
    struct Hueco: Decodable, Hashable { var t: String; var porQue: String
        enum CodingKeys: String, CodingKey { case t, porQue = "por_que" } }
    struct Seguimiento: Decodable, Hashable { var nombre: String; var queHaPasado: String; var sigue: Bool
        enum CodingKeys: String, CodingKey { case nombre, sigue, queHaPasado = "que_ha_pasado" } }
    struct Aprender: Decodable, Hashable { var titulo: String; var texto: String }

    var id: String
    var fecha: String
    var estado: String
    var error: String?
    var resumen: String?
    var huecos: [Hueco]?
    var ideas: [IdeaExplorar]?
    var seguimiento: [Seguimiento]?
    var aprender: Aprender?
}

struct ReaccionExplorar: Decodable, Hashable {
    var estado: String
    var nota: String?
}

struct RespuestaExplorar: Decodable {
    var informes: [InformeExplorar]
    var reacciones: [String: ReaccionExplorar]
    var comparas: [PreguntaInv]
}

extension DatosInversiones {
    func explorar() async -> RespuestaExplorar? {
        guard let d = try? await API.datos("/api/inversiones/explorar") else { return nil }
        return try? JSONDecoder().decode(RespuestaExplorar.self, from: d)
    }

    func pideIdeas() async -> Bool {
        do {
            _ = try await API.datos("/api/inversiones/explorar/genera", metodo: "POST", json: [String: Any]())
            Haptica.shared.toca(.marcar)
            return true
        } catch {
            avisa(error.localizedDescription, error: true)
            return false
        }
    }

    func reacciona(_ id: String, _ estado: String, nota: String = "") async {
        do {
            _ = try await API.datos("/api/inversiones/explorar/reaccion", metodo: "POST", json: ["id": id, "estado": estado, "nota": nota])
            Haptica.shared.toca(.marcar)
        } catch {
            avisa(error.localizedDescription, error: true)
        }
    }

    func compara(_ a: String, _ b: String) async -> Bool {
        do {
            _ = try await API.datos("/api/inversiones/compara", metodo: "POST", json: ["a": a, "b": b])
            Haptica.shared.toca(.marcar)
            return true
        } catch {
            avisa(error.localizedDescription, error: true)
            return false
        }
    }
}

struct ExplorarInversiones: View {
    @State private var datos = DatosInversiones.shared
    @State private var r: RespuestaExplorar?
    @State private var vista: String?
    @State private var pidiendo = false
    @State private var a = ""
    @State private var b = ""
    @State private var comparando = false
    @State private var descartando: IdeaExplorar?
    @State private var motivo = ""
    var irAPregunta: () -> Void = {}

    private var informe: InformeExplorar? { r?.informes.first { $0.id == vista } ?? r?.informes.first }
    private var pensando: Bool { r?.informes.contains { $0.estado == "generando" } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.l) {
            cabecera
            if let inf = informe {
                switch inf.estado {
                case "generando":
                    HStack(spacing: Tema.Espacio.s) {
                        ProgressView()
                        Text("Buscando ideas que encajen contigo… puedes irte y volver.").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                    }
                    .carta()
                case "error":
                    Text(inf.error ?? "No salió").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro).carta()
                default:
                    contenido(inf)
                }
            } else if r != nil {
                Text("Aún no hay ideas. Pide las primeras: tarda unos minutos porque busca datos de hoy en la web.")
                    .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            }
            comparador
        }
        .task { await vigila() }
        .alert("¿Por qué no?", isPresented: Binding(get: { descartando != nil }, set: { if !$0 { descartando = nil } })) {
            TextField("Opcional: ayuda a afinar las próximas", text: $motivo)
            Button("Descartar", role: .destructive) {
                if let i = descartando { Task { await datos.reacciona(i.id, "descarta", nota: motivo); await recarga() } }
                descartando = nil
            }
            Button("Cancelar", role: .cancel) { descartando = nil }
        }
    }

    private var cabecera: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            Text("Ideas para estudiar").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
            Text("Temas, fondos y empresas que encajan con tu perfil y con lo que le falta a tu cartera, con el porqué, el mejor argumento en contra y cómo se compraría. Llegan el primer sábado de cada mes. Lo que respondas afina las siguientes. Para estudiar, no órdenes de compra.")
                .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            if let infs = r?.informes, infs.count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: Tema.Espacio.s) {
                        ForEach(infs.prefix(12)) { x in
                            Button(x.estado == "generando" ? "Pensando…" : FechasES.corta(x.fecha)) { vista = x.id }
                                .font(Tema.fuente(.pequeno))
                                .buttonStyle(.bordered)
                                .tint(x.id == informe?.id ? Tema.acento : Tema.suave)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            Button {
                Task {
                    pidiendo = true
                    if await datos.pideIdeas() { vista = nil; await recarga() }
                    pidiendo = false
                }
            } label: {
                Label(pensando ? "Pensando… (unos minutos)" : "Ideas nuevas", systemImage: "sparkle.magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Tema.acento)
            .disabled(pensando || pidiendo)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .carta()
    }

    @ViewBuilder
    private func contenido(_ inf: InformeExplorar) -> some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            Text("Este mes").font(Tema.fuente(.destacado, peso: .semibold)).foregroundStyle(Tema.texto)
            Text(inf.resumen ?? "").font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
            if let huecos = inf.huecos, !huecos.isEmpty {
                Text("Lo que le falta a tu cartera").font(Tema.fuente(.etiqueta, peso: .semibold)).foregroundStyle(Tema.suave)
                ForEach(huecos, id: \.self) { h in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(h.t).font(Tema.fuente(.pequeno, peso: .semibold)).foregroundStyle(Tema.acento)
                        Text(h.porQue).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.texto)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Tema.Espacio.s + 2)
                    .background(Tema.acentoSuave, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .carta()

        let reac = r?.reacciones ?? [:]
        // lo descartado, al final
        ForEach((inf.ideas ?? []).sorted { (reac[$0.id]?.estado == "descarta" ? 1 : 0) < (reac[$1.id]?.estado == "descarta" ? 1 : 0) }) { i in
            TarjetaIdea(idea: i, reaccion: reac[i.id],
                        reacciona: { estado in
                            if estado == "descarta" && reac[i.id]?.estado != "descarta" { motivo = ""; descartando = i; return }
                            Task { await datos.reacciona(i.id, reac[i.id]?.estado == estado ? "" : estado); await recarga() }
                        },
                        profundiza: {
                            Task {
                                let cod = i.codigo.isEmpty ? "" : " (\(i.codigo))"
                                if await datos.pregunta("Profundiza en «\(i.nombre)»\(cod) para mí: cómo funciona por dentro, si de verdad encaja con mi cartera y mi perfil, qué % tendría sentido, cómo lo compraría con mi broker y qué tendría que pasar para descartarlo.") {
                                    irAPregunta()
                                }
                            }
                        })
        }

        if let seg = inf.seguimiento, !seg.isEmpty {
            VStack(alignment: .leading, spacing: Tema.Espacio.s) {
                Text("Lo que te interesó: qué ha pasado").font(Tema.fuente(.destacado, peso: .semibold)).foregroundStyle(Tema.texto)
                ForEach(seg, id: \.self) { s in
                    (Text("\(s.nombre) · \(s.sigue ? "sigue en pie" : "ya no lo veo"): ").bold() + Text(s.queHaPasado))
                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.texto)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .carta()
        }
        if let ap = inf.aprender {
            VStack(alignment: .leading, spacing: Tema.Espacio.s) {
                Text("Para aprender: \(ap.titulo)").font(Tema.fuente(.destacado, peso: .semibold)).foregroundStyle(Tema.texto)
                Text(ap.texto).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.texto)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .carta()
        }
    }

    private var comparador: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            Text("Comparar dos fondos o acciones").font(Tema.fuente(.destacado, peso: .semibold)).foregroundStyle(Tema.texto)
            Text("Costes, qué llevan dentro, cuánto se solapan entre sí y con tu cartera, impuestos en España y cuál te encaja mejor. Nombre, ticker o ISIN.")
                .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            HStack(spacing: Tema.Espacio.s) {
                TextField("Primero", text: $a).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .padding(Tema.Espacio.s + 2).background(Tema.texto.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                TextField("Segundo", text: $b).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .padding(Tema.Espacio.s + 2).background(Tema.texto.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            }
            .font(Tema.fuente(.texto))
            Button {
                Task {
                    comparando = true
                    if await datos.compara(a.trimmingCharacters(in: .whitespaces), b.trimmingCharacters(in: .whitespaces)) {
                        a = ""; b = ""
                        await recarga()
                    }
                    comparando = false
                }
            } label: {
                Label(comparando ? "Enviando…" : "Comparar", systemImage: "arrow.left.arrow.right").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Tema.acento)
            .disabled(comparando || a.trimmingCharacters(in: .whitespaces).isEmpty || b.trimmingCharacters(in: .whitespaces).isEmpty)

            ForEach(r?.comparas ?? []) { p in
                Divider().overlay(Tema.linea)
                VStack(alignment: .leading, spacing: Tema.Espacio.s) {
                    Text(p.titulo ?? p.q).font(Tema.fuente(.texto, peso: .semibold)).foregroundStyle(Tema.texto)
                    switch p.estado {
                    case "pensando":
                        HStack(spacing: Tema.Espacio.s) {
                            ProgressView()
                            Text("Comparando… (busca los datos de hoy)").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                        }
                    case "error":
                        Text(p.r).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro)
                    default:
                        MarkdownInv(texto: p.r)
                    }
                    HStack {
                        Text(p.cuando.replacingOccurrences(of: "T", with: " · ")).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                        Spacer()
                        Button("Borrar", role: .destructive) {
                            Task { await datos.borraPregunta(p.id); await recarga() }
                        }
                        .font(Tema.fuente(.pequeno))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .carta()
    }

    private func recarga() async {
        if let n = await datos.explorar() {
            withAnimation(Tema.Muelle.pantalla) { r = n }
        }
    }

    /// Mientras la vista está en pantalla: carga y, si algo piensa, vuelve a mirar cada 4 s.
    private func vigila() async {
        await recarga()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(4))
            if pensando || (r?.comparas.contains { $0.estado == "pensando" } ?? false) { await recarga() }
        }
    }
}

/// Una idea: lo esencial a la vista y la tesis, el argumento en contra y cómo comprarlo al desplegar.
struct TarjetaIdea: View {
    let idea: IdeaExplorar
    let reaccion: ReaccionExplorar?
    let reacciona: (String) -> Void
    let profundiza: () -> Void
    @State private var abierta = false

    private static let reacciones = [("interesa", "Me interesa", "star"), ("tengo", "Ya lo tengo", "checkmark"), ("descarta", "Descartar", "xmark")]

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            HStack(spacing: Tema.Espacio.s) {
                Text(idea.nombreTipo)
                    .estiloEtiqueta()
                    .foregroundStyle(idea.tipo == "tema" ? Tema.acento : Tema.suave)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(idea.tipo == "tema" ? Tema.acentoSuave : Tema.linea, in: Capsule())
                Spacer()
                HStack(spacing: 3) {
                    ForEach(1...5, id: \.self) { n in
                        Circle().fill(n <= idea.riesgo ? Tema.peligro : Tema.linea).frame(width: 7, height: 7)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Riesgo \(idea.riesgo) de 5")
                if !idea.horizonte.isEmpty {
                    Text(idea.horizonte).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                }
            }
            Text(idea.nombre).font(Tema.fuente(.destacado, peso: .semibold)).foregroundStyle(Tema.texto)
            if !idea.codigo.isEmpty {
                Text(idea.codigo).font(Tema.fuente(.pequeno)).monospacedDigit().foregroundStyle(Tema.suave).textSelection(.enabled)
            }
            Text(idea.gancho).font(Tema.fuente(.texto, peso: .medium)).foregroundStyle(Tema.texto)
            Text(idea.porQueTu).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)

            DisclosureGroup(isExpanded: $abierta) {
                VStack(alignment: .leading, spacing: Tema.Espacio.m) {
                    campo("La tesis", idea.tesis)
                    campo("En contra", idea.contra, contra: true)
                    if !idea.riesgos.isEmpty { campo("Riesgos", idea.riesgos.map { "• " + $0 }.joined(separator: "\n")) }
                    campo("Cómo tenerlo", idea.como)
                    campo("En tu cartera", idea.encaje)
                    campo("Qué vigilar", idea.senales)
                    campo("Un dato de hoy", idea.dato)
                    if !idea.fuentes.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("FUENTES").font(Tema.fuente(.etiqueta, peso: .semibold)).foregroundStyle(Tema.suave)
                            ForEach(idea.fuentes, id: \.self) { u in
                                if let url = URL(string: u) {
                                    Link(url.host()?.replacingOccurrences(of: "www.", with: "") ?? u, destination: url)
                                        .font(Tema.fuente(.pequeno))
                                }
                            }
                        }
                    }
                }
                .padding(.top, Tema.Espacio.s)
            } label: {
                Text("La tesis, el argumento en contra y cómo se compraría")
                    .font(Tema.fuente(.pequeno, peso: .semibold)).foregroundStyle(Tema.acento)
            }
            .tint(Tema.acento)

            ScrollView(.horizontal) {
                HStack(spacing: Tema.Espacio.s) {
                    ForEach(Self.reacciones, id: \.0) { x in
                        let puesta = reaccion?.estado == x.0
                        Button { reacciona(x.0) } label: { Label(x.1, systemImage: x.2) }
                            .font(Tema.fuente(.pequeno))
                            .buttonStyle(.bordered)
                            .tint(puesta ? Tema.acento : Tema.suave)
                            .accessibilityAddTraits(puesta ? .isSelected : [])
                    }
                    Button { profundiza() } label: { Label("Profundizar", systemImage: "sparkles") }
                        .font(Tema.fuente(.pequeno)).buttonStyle(.bordered).tint(Tema.acento)
                }
            }
            .scrollIndicators(.hidden)
            if let nota = reaccion?.nota, !nota.isEmpty {
                Text("Motivo: \(nota)").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .carta()
        .opacity(reaccion?.estado == "descarta" ? 0.55 : 1)
    }

    @ViewBuilder
    private func campo(_ titulo: String, _ texto: String, contra: Bool = false) -> some View {
        if !texto.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo.uppercased()).font(Tema.fuente(.etiqueta, peso: .semibold)).foregroundStyle(contra ? Tema.peligro : Tema.suave)
                Text(texto).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.texto).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, contra ? Tema.Espacio.s : 0)
            .overlay(alignment: .leading) {
                if contra { Rectangle().fill(Tema.peligro).frame(width: 3) }
            }
        }
    }
}
