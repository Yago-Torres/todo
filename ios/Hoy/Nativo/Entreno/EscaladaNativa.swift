import AVKit
import Observation
import SwiftUI

/// Escalada en nativo (la tarjeta de entreno.html): subir un intento (la hoja de Hoy/Escalada.swift, que comprime,
/// sube en segundo plano y saca la vista previa con Vision), los que van de camino, Competir (tu intento contra otro
/// encima del vídeo) y los intentos por bloque, con sus vídeos, el análisis y el nombre y nivel del bloque.
struct IntentoEscalada: Decodable, Identifiable, Hashable {
    var intento: String
    var quien: String
    var color: String
    var nombre: String
    var resultado: String
    var dificultad: Int?
    var resumen: String
    var caida: String
    var bien: [String]
    var mal: [String]
    var consejos: [String]
    var hay: [String]
    var fantasma: Bool
    var fantasmas: [String: String]
    var id: String { intento }

    init(from decoder: Decoder) throws {
        let k = try decoder.container(keyedBy: CodingKeys.self)
        intento = try k.decode(String.self, forKey: .intento)
        quien = (try? k.decode(String.self, forKey: .quien)) ?? ""
        color = (try? k.decode(String.self, forKey: .color)) ?? ""
        nombre = (try? k.decode(String.self, forKey: .nombre)) ?? ""
        resultado = (try? k.decode(String.self, forKey: .resultado)) ?? ""
        dificultad = (try? k.decode(Double.self, forKey: .dificultad)).map { Int($0.rounded()) }
        resumen = (try? k.decode(String.self, forKey: .resumen)) ?? ""
        caida = (try? k.decode(String.self, forKey: .caida)) ?? ""
        bien = (try? k.decode([String].self, forKey: .bien)) ?? []
        mal = (try? k.decode([String].self, forKey: .mal)) ?? []
        consejos = (try? k.decode([String].self, forKey: .consejos)) ?? []
        hay = (try? k.decode([String].self, forKey: .hay)) ?? []
        fantasma = (try? k.decode(Bool.self, forKey: .fantasma)) ?? false
        fantasmas = (try? k.decode([String: String].self, forKey: .fantasmas)) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case intento, quien, color, nombre, resultado, dificultad, resumen, caida, bien, mal, consejos, hay, fantasma, fantasmas
    }

    var bloque: String { nombre.isEmpty ? "Bloque \(color)" : nombre }
    var quienVisto: String { quien.lowercased() == "yago" ? "Tú" : quien }

    /// 20261105-152708 → «jue 5 nov · 15:27».
    var cuando: String { EscaladaDatos.cuando(intento) }
}

struct PendienteEscalada: Decodable, Hashable {
    var intento: String
    var color: String
    var nombre: String
    var estado: String
    var error: String
    var previa: Bool

    init(from decoder: Decoder) throws {
        let k = try decoder.container(keyedBy: CodingKeys.self)
        intento = try k.decode(String.self, forKey: .intento)
        color = (try? k.decode(String.self, forKey: .color)) ?? ""
        nombre = (try? k.decode(String.self, forKey: .nombre)) ?? ""
        estado = (try? k.decode(String.self, forKey: .estado)) ?? ""
        error = (try? k.decode(String.self, forKey: .error)) ?? ""
        previa = (try? k.decode(Bool.self, forKey: .previa)) ?? false
    }

    private enum CodingKeys: String, CodingKey { case intento, color, nombre, estado, error, previa }
}

@MainActor @Observable
final class EscaladaDatos {
    static let shared = EscaladaDatos()

    private(set) var activa = false
    private(set) var intentos: [IntentoEscalada] = []
    private(set) var pendientes: [PendienteEscalada] = []
    var aviso: String?

    private struct Respuesta: Decodable {
        var activa: Bool?
        var intentos: [IntentoEscalada]?
        var pendientes: [PendienteEscalada]?
    }

    private init() {
        if let r = Local.lee(Local.clave("GET", "/api/escalada")) { lee(r.cuerpo) }
    }

    private func lee(_ d: Data) {
        guard let r = try? JSONDecoder().decode(Respuesta.self, from: d) else { return }
        activa = r.activa ?? false
        intentos = r.intentos ?? []
        pendientes = r.pendientes ?? []
    }

    func carga() async {
        guard let r = try? await API.leeOCopia("/api/escalada") else { return }
        withAnimation(Tema.Muelle.toque) { lee(r.datos) }
        // ya analizado: fuera de los de camino
        for x in intentos { Escalada.shared.vivos[x.intento] = nil }
    }

    /// Mientras se monta una competición o hay uno de camino, se mira cada 10 s.
    var hayQueSondear: Bool {
        intentos.contains { $0.fantasmas.values.contains("preparando") }
            || pendientes.contains { $0.estado != "error" }
            || Escalada.shared.vivos.values.contains { $0.fase != "error" && $0.fase != "listo" }
    }

    func guardaBloque(_ intento: String, nombre: String, nivel: Int?) async {
        var json: [String: Any] = ["nombre": nombre]
        json["nivel"] = nivel.map { String($0) } ?? ""
        do {
            try await API.datos("/api/escalada/\(intento)/bloque", metodo: "POST", json: json)
            await carga()
            Haptica.shared.toca(.marcar)
        } catch {
            aviso = "No se ha guardado: \(error.localizedDescription)"
            Haptica.shared.toca(.error)
        }
    }

    func compite(yo: String, otro: String) async {
        do {
            try await API.datos("/api/escalada/fantasma", metodo: "POST", json: ["yo": yo, "otro": otro])
            await carga()
            aviso = "Montándolo: en un minuto está aquí y en Telegram."
        } catch {
            aviso = "No se ha podido: \(error.localizedDescription)"
            Haptica.shared.toca(.error)
        }
    }

    static func cuando(_ i: String) -> String {
        let c = Array(i)
        guard c.count == 15 else { return i }
        let dia = "\(String(c[0...3]))-\(String(c[4...5]))-\(String(c[6...7]))"
        return "\(FormatoEnt.diaSemana(dia)) \(FormatoEnt.corta(dia).split(separator: " ").last ?? "") · \(String(c[9...10])):\(String(c[11...12]))"
    }

    static func corto(_ i: String) -> String {
        let c = Array(i)
        guard c.count == 15 else { return i }
        return "\(Int(String(c[6...7])) ?? 0)/\(Int(String(c[4...5])) ?? 0) \(String(c[9...10])):\(String(c[11...12]))"
    }

    /// El color de las presas (los mismos de la web).
    static func color(_ nombre: String) -> Color {
        let hex = ["amarillo": "#F2C230", "naranja": "#F08A2C", "rojo": "#E04848", "rosa": "#F08AB4", "morado": "#9466D8",
                   "azul": "#3A7FE0", "verde": "#3BA55C", "blanco": "#F4F4F0", "negro": "#222222"][nombre]
        return hex.map { Color(hex: $0) } ?? Tema.tenue
    }
}

struct TarjetaEscalada: View {
    @State private var datos = EscaladaDatos.shared
    @State private var subida = Escalada.shared
    @State private var abierto: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            TituloEnt("Escalada")
            Button {
                Escalada.shared.hojaVisible = true
            } label: {
                Label("Subir intento", systemImage: "video.badge.plus").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(BotonEnt(principal: true))
            if let t = subida.trabajo {
                HStack {
                    ProgressView().tint(Tema.acento)
                    Text(t).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                    if let p = subida.progreso { Text("\(Int(p * 100)) %").font(Tema.fuente(.pequeno)).monospacedDigit() }
                }
            }
            if let a = datos.aviso {
                Text(a).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            }
            enCurso
            CompetirEscalada()
            if datos.intentos.isEmpty && enCursoLista.isEmpty {
                Text("Aún no hay intentos: graba uno y súbelo con «Subir intento» o el atajo «Analizar escalada».")
                    .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            }
            ForEach(grupos, id: \.0) { nombre, xs in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: Tema.Espacio.s) {
                        Circle().fill(EscaladaDatos.color(xs[0].color)).frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(Tema.linea, lineWidth: 0.5))
                        Text(nombre).font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
                        if let n = xs.first(where: { $0.dificultad != nil })?.dificultad { ChipEnt(texto: "nivel \(n)", color: Tema.suave, fondo: Tema.carta2) }
                        ChipEnt(texto: "\(xs.count) \(xs.count == 1 ? "intento" : "intentos")", color: Tema.suave, fondo: Tema.carta2)
                        if xs.contains(where: { $0.resultado == "hecho" }) { ChipEnt(texto: "encadenado") }
                    }
                    .padding(.top, Tema.Espacio.m)
                    ForEach(xs) { x in fila(x) }
                }
            }
        }
        .carta()
        .task(id: datos.hayQueSondear) {
            while datos.hayQueSondear && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                await datos.carga()
            }
        }
    }

    private var grupos: [(String, [IntentoEscalada])] {
        var orden: [String] = []
        var por: [String: [IntentoEscalada]] = [:]
        for x in datos.intentos {
            if por[x.bloque] == nil { orden.append(x.bloque) }
            por[x.bloque, default: []].append(x)
        }
        return orden.map { ($0, por[$0] ?? []) }
    }

    private struct Curso: Identifiable {
        var intento: String
        var titulo: String
        var color: String
        var estado: String
        var progreso: Double?
        var fallo: Bool
        var motivo: String
        var previa: Bool
        var id: String { intento }
    }

    private var enCursoLista: [Curso] {
        var lista: [String: Curso] = [:]
        for p in datos.pendientes {
            let fallo = p.estado == "error"
            lista[p.intento] = Curso(intento: p.intento, titulo: p.nombre.isEmpty ? (p.color.isEmpty ? "Intento" : "Bloque \(p.color)") : p.nombre,
                                     color: p.color, estado: fallo ? "no se ha podido" : p.estado == "subiendo" ? "subiendo" : "analizando…",
                                     progreso: nil, fallo: fallo, motivo: p.error, previa: p.previa)
        }
        for (i, v) in subida.vivos where !datos.intentos.contains(where: { $0.intento == i }) {
            var c = lista[i] ?? Curso(intento: i, titulo: v.nombre.isEmpty ? (v.color.isEmpty ? "Intento" : "Bloque \(v.color)") : v.nombre,
                                      color: v.color, estado: "subiendo", progreso: nil, fallo: false, motivo: "", previa: false)
            if !(c.fallo && (v.fase == "listo" || v.fase == "previa")) {
                switch v.fase {
                case "comprimiendo", "subiendo":
                    c.estado = v.fase + (v.progreso.map { " \(Int($0 * 100)) %" } ?? "")
                    c.progreso = v.progreso
                case "error":
                    c.estado = "no se ha podido"
                    c.fallo = true
                    c.motivo = v.texto
                case "listo": c.estado = c.fallo ? c.estado : "analizando…"
                default: c.estado = "subiendo"
                }
            }
            lista[i] = c
        }
        return lista.values.sorted { $0.intento > $1.intento }
    }

    @ViewBuilder private var enCurso: some View {
        ForEach(enCursoLista) { c in
            VStack(alignment: .leading, spacing: Tema.Espacio.s) {
                HStack(spacing: Tema.Espacio.s) {
                    Circle().fill(EscaladaDatos.color(c.color)).frame(width: 12, height: 12)
                    Text("\(c.titulo) · \(EscaladaDatos.cuando(c.intento))").font(Tema.fuente(.texto)).foregroundStyle(Tema.texto).lineLimit(1)
                    Spacer()
                    ChipEnt(texto: c.estado, color: c.fallo ? Tema.peligro : Tema.acento, fondo: Tema.carta2)
                }
                if let p = c.progreso { BarraEnt(valor: p).frame(height: 6).animation(.linear, value: p) }
                if c.fallo && !c.motivo.isEmpty {
                    Text(c.motivo + " · Reinténtalo desde «Subir intento».").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                }
                if c.previa { VistaPreviaEscalada(intento: c.intento) }
            }
            .padding(.vertical, Tema.Espacio.s)
            .overlay(alignment: .bottom) { Rectangle().fill(Tema.linea).frame(height: 0.5) }
        }
    }

    private func resultado(_ r: String) -> some View {
        switch r {
        case "hecho": return ChipEnt(texto: "Hecho", color: Tema.acento, fondo: Tema.carta2)
        case "caida": return ChipEnt(texto: "Me caí", color: Tema.peligro, fondo: Tema.carta2)
        default: return ChipEnt(texto: r == "probando" ? "Probando" : r, color: Tema.suave, fondo: Tema.carta2)
        }
    }

    private func fila(_ x: IntentoEscalada) -> some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            Button {
                withAnimation(Tema.Muelle.toque) { abierto = abierto == x.intento ? nil : x.intento }
            } label: {
                HStack {
                    Text("\(x.cuando) · \(x.quienVisto)").font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                    Spacer()
                    resultado(x.resultado)
                }
                .frame(minHeight: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(abierto == x.intento ? "Toca para cerrarlo" : "Toca para ver el vídeo y el análisis")
            if abierto == x.intento {
                DetalleIntento(x: x)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Tema.linea).frame(height: 0.5) }
    }
}

/// Un intento por dentro: vídeos (el anotado, la beta, las competiciones), el análisis y el nombre y nivel del bloque.
private struct DetalleIntento: View {
    let x: IntentoEscalada
    @State private var datos = EscaladaDatos.shared
    @State private var fuente: String?
    @State private var nombre = ""
    @State private var nivel: Int?

    private var fuentes: [(String, String)] {
        var f: [(String, String)] = []
        if x.hay.contains("anotado") { f.append(("Tu intento", "anotado")) }
        if x.hay.contains("beta") { f.append(("Beta esperada", "beta")) }
        for (otro, est) in x.fantasmas.sorted(by: { $0.key < $1.key }) where est == "listo" {
            let o = datos.intentos.first { $0.intento == otro }
            f.append(("⚔️ contra \(o?.quienVisto ?? otro)", "fantasma-\(otro)"))
        }
        return f
    }

    var body: some View {
        let fs = fuentes
        let actual = fs.first(where: { $0.1 == fuente })?.1 ?? fs.first?.1
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            if let actual {
                if fs.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(fs, id: \.1) { f in
                                Button(f.0) { fuente = f.1 }
                                    .buttonStyle(BotonMini(color: f.1 == actual ? Tema.acento : Tema.suave))
                            }
                        }
                    }
                }
                VideoEscalada(ruta: "/api/escalada/\(x.intento)/\(actual)")
                    .id(actual)
            }
            if !x.resumen.isEmpty { Text(x.resumen).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto) }
            lista("✅ Bien", x.bien)
            lista("⚠️ A mejorar", x.mal)
            if !x.caida.isEmpty {
                Text("💥 La caída").font(Tema.fuente(.pequeno, peso: .semibold)).foregroundStyle(Tema.suave)
                Text(x.caida).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
            }
            lista("👉 Para el próximo", x.consejos)
            VStack(alignment: .leading, spacing: Tema.Espacio.s) {
                Text("El bloque (con el mismo nombre, los intentos van juntos)").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                HStack(spacing: Tema.Espacio.s) {
                    TextField("Nombre del bloque", text: $nombre)
                        .font(Tema.fuente(.texto))
                        .padding(.horizontal, Tema.Espacio.s).frame(minHeight: 40)
                        .background(Tema.carta, in: RoundedRectangle(cornerRadius: Tema.Radio.celda))
                    Menu {
                        Button("Sin nivel") { nivel = nil }
                        ForEach(1...10, id: \.self) { n in Button("Nivel \(n)") { nivel = n } }
                    } label: {
                        Text(nivel.map { "Nivel \($0)" } ?? "Nivel").font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                            .padding(.horizontal, Tema.Espacio.s).frame(minHeight: 40)
                            .background(Tema.carta, in: RoundedRectangle(cornerRadius: Tema.Radio.celda))
                    }
                    Button("Guardar") {
                        Task { await datos.guardaBloque(x.intento, nombre: nombre, nivel: nivel) }
                    }
                    .buttonStyle(BotonMini())
                }
            }
            .padding(Tema.Espacio.m)
            .background(Tema.carta2, in: RoundedRectangle(cornerRadius: Tema.Radio.celda))
        }
        .padding(.bottom, Tema.Espacio.m)
        .onAppear {
            nombre = x.nombre
            nivel = x.dificultad
        }
    }

    @ViewBuilder private func lista(_ t: String, _ xs: [String]) -> some View {
        if !xs.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(t).font(Tema.fuente(.pequeno, peso: .semibold)).foregroundStyle(Tema.suave)
                ForEach(xs, id: \.self) { s in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(Tema.tenue)
                        Text(s).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                }
            }
        }
    }
}

/// Un vídeo del servidor con las claves de siempre (Cloudflare y la contraseña van en las cabeceras).
private struct VideoEscalada: View {
    let ruta: String
    @State private var jugador: AVPlayer?

    var body: some View {
        Group {
            if let jugador {
                VideoPlayer(player: jugador)
            } else {
                Rectangle().fill(Color.black).overlay(ProgressView().tint(.white))
            }
        }
        .aspectRatio(9.0 / 16.0, contentMode: .fit)
        .frame(maxHeight: 520)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Tema.Radio.celda))
        .onAppear {
            guard jugador == nil, let p = try? API.peticion(ruta), let url = p.url else { return }
            var cab = p.allHTTPHeaderFields ?? [:]
            cab["Accept"] = "*/*"
            let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": cab])
            jugador = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        }
        .onDisappear { jugador?.pause() }
    }
}

/// Competir: tu intento contra el de otro (o uno tuyo de otro día) en el mismo bloque, y las que ya hay.
private struct CompetirEscalada: View {
    @State private var datos = EscaladaDatos.shared
    @State private var yo: String?
    @State private var otro: String?
    @State private var enviando = false

    var body: some View {
        let con = datos.intentos.filter(\.fantasma)
        let hechas = datos.intentos.flatMap { x in x.fantasmas.sorted { $0.key < $1.key }.map { (x, $0.key, $0.value) } }
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            Text("⚔️ Competir").font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
            Text("Tu intento contra el de otro (o uno tuyo de otro día) en el mismo bloque: lo ves encima de tu vídeo, salís a la vez y en cada presa sale quién llega antes.")
                .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            if con.count < 2 {
                Text("Hacen falta dos intentos del mismo bloque grabados desde el 5 de noviembre.")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            } else {
                let a = yo ?? (con.first { $0.quienVisto == "Tú" } ?? con[0]).intento
                let base = con.first { $0.intento == a }
                let otros = con.filter { $0.intento != a }
                    .sorted { p, q in
                        let pi = p.bloque == base?.bloque, qi = q.bloque == base?.bloque
                        return pi != qi ? pi : p.intento > q.intento
                    }
                let b = otro.flatMap { o in otros.contains { $0.intento == o } ? o : nil } ?? otros.first?.intento
                selector("Tú", con, a) { yo = $0 }
                selector("Contra", otros, b) { otro = $0 }
                Button(enviando ? "Pidiéndolo…" : "Competir") {
                    guard let b else { return }
                    enviando = true
                    Task {
                        await datos.compite(yo: a, otro: b)
                        enviando = false
                    }
                }
                .buttonStyle(BotonEnt(principal: true))
                .disabled(enviando || b == nil)
            }
            ForEach(Array(hechas.enumerated()), id: \.offset) { _, h in
                let o = datos.intentos.first { $0.intento == h.1 }
                HStack {
                    Text("\(h.0.quienVisto) (\(EscaladaDatos.corto(h.0.intento))) contra \(o?.quienVisto ?? "?") (\(EscaladaDatos.corto(h.1)))")
                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.texto)
                    Spacer()
                    Text(h.2 == "listo" ? "lista: ábrela en su intento" : h.2 == "preparando" ? "montándolo…" : h.2)
                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                }
                .padding(.top, 4)
            }
        }
        .padding(Tema.Espacio.m)
        .background(Tema.carta2, in: RoundedRectangle(cornerRadius: Tema.Radio.celda))
    }

    private func selector(_ t: String, _ xs: [IntentoEscalada], _ actual: String?, _ elige: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(xs) { x in
                Button("\(x.quienVisto) · \(EscaladaDatos.corto(x.intento)) · \(x.bloque)\(x.dificultad.map { " · nivel \($0)" } ?? "")") { elige(x.intento) }
            }
        } label: {
            HStack {
                Text(t).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).frame(width: 56, alignment: .leading)
                let x = xs.first { $0.intento == actual }
                Text(x.map { "\($0.quienVisto) · \(EscaladaDatos.corto($0.intento)) · \($0.bloque)" } ?? "Elegir")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.texto).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11)).foregroundStyle(Tema.suave)
            }
            .padding(.horizontal, Tema.Espacio.s).frame(minHeight: 40)
            .background(Tema.carta, in: RoundedRectangle(cornerRadius: Tema.Radio.celda))
        }
    }
}

/// La vista previa del iPhone (el esqueleto de Vision y la estela del centro de gravedad), mientras llega el análisis.
struct VistaPreviaEscalada: View {
    let intento: String
    @State private var previa: Previa?
    @Environment(\.accessibilityReduceMotion) private var quieto

    struct Previa: Decodable {
        var ancho: Double
        var alto: Double
        var fotogramas: [[Valor]]
    }

    /// Un valor del fotograma: número, nulo o la lista de puntos.
    enum Valor: Decodable {
        case num(Double), nada, puntos([[Double]])

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() { self = .nada } else if let d = try? c.decode(Double.self) { self = .num(d) } else {
                self = .puntos((try? c.decode([[Double]].self)) ?? [])
            }
        }

        var numero: Double? { if case .num(let d) = self { return d }; return nil }
        var lista: [[Double]] { if case .puntos(let p) = self { return p }; return [] }
    }

    private static let huesos = [(5, 6), (5, 8), (8, 10), (6, 9), (9, 11), (5, 13), (6, 14), (13, 14), (13, 15), (15, 17),
                                 (14, 16), (16, 18), (0, 7)]

    var body: some View {
        VStack(spacing: 4) {
            if let p = previa, !p.fotogramas.isEmpty {
                TimelineView(.animation(minimumInterval: 1.0 / 15, paused: quieto)) { ctx in
                    Canvas { g, tam in pinta(g, tam, p, ctx.date.timeIntervalSinceReferenceDate) }
                }
                .aspectRatio(p.ancho / max(1, p.alto), contentMode: .fit)
                .frame(maxHeight: 360)
                .background(Tema.carta2, in: RoundedRectangle(cornerRadius: Tema.Radio.celda))
                .accessibilityLabel("Esqueleto y centro de gravedad del intento, sacados en el iPhone")
            }
            Text("Vista previa del iPhone · el análisis completo llega en unos minutos")
                .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .task {
            guard previa == nil, let d = try? await API.datos("/api/escalada/\(intento)/previa") else { return }
            previa = try? JSONDecoder().decode(Previa.self, from: d)
        }
    }

    private func pinta(_ g: GraphicsContext, _ tam: CGSize, _ p: Previa, _ ahora: Double) {
        let fs = p.fotogramas
        let dura = max(fs.last?.first?.numero ?? 0.5, 0.5)
        let t = quieto ? dura : ahora.truncatingRemainder(dividingBy: dura + 1)
        var n = 0
        while n + 1 < fs.count, (fs[n + 1].first?.numero ?? 0) <= t { n += 1 }
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * tam.width, y: y * tam.height) }
        // la estela de los últimos 3 s
        var antes: CGPoint?
        let tn = fs[n].first?.numero ?? 0
        for k in 0...n {
            let f = fs[k]
            guard f.count == 4, let tk = f[0].numero, let cx = f[1].numero, let cy = f[2].numero, tn - tk <= 3 else {
                antes = nil
                continue
            }
            let ahoraP = pt(cx, cy)
            if let antes {
                var path = Path()
                path.move(to: antes)
                path.addLine(to: ahoraP)
                g.stroke(path, with: .color(Tema.aviso.opacity(0.25 + 0.75 * (1 - (tn - tk) / 3))), lineWidth: 3)
            }
            antes = ahoraP
        }
        guard fs[n].count == 4 else { return }
        let pts = fs[n][3].lista
        guard pts.count >= 19 else { return }
        for (a, b) in Self.huesos where pts[a].count == 3 && pts[b].count == 3 && pts[a][2] >= 0.3 && pts[b][2] >= 0.3 {
            var path = Path()
            path.move(to: pt(pts[a][0], pts[a][1]))
            path.addLine(to: pt(pts[b][0], pts[b][1]))
            g.stroke(path, with: .color(Tema.acento), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        for q in pts where q.count == 3 && q[2] >= 0.3 {
            let c = pt(q[0], q[1])
            g.fill(Path(ellipseIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)), with: .color(Tema.acento))
        }
        if let cx = fs[n][1].numero, let cy = fs[n][2].numero {
            let c = pt(cx, cy)
            g.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)), with: .color(Tema.aviso))
        }
    }
}
