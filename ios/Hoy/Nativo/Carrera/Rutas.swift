import Charts
import SwiftUI

/// Rutas del COROS en Tom, como en la web (rutas.py hace los cálculos; aquí solo se pinta):
/// - en el detalle de una carrera: contra tu fantasma (la última vez en esa ruta), sus segmentos y el GPX para el reloj;
/// - en Carrera: tu biblioteca de rutas (con las que encajan con la próxima carrera del plan) y tus segmentos.
/// Los segmentos se crean y las rutas se renombran en la web (/actividad.html y /carrera.html).

// MARK: modelos

struct KmDif: Decodable, Hashable {
    var km: Int
    var dif: Int
}

struct Comparacion: Decodable {
    var id: String
    var dia: String?
    var km: [KmDif]
    var fin: Int        // segundos de diferencia al final; < 0 = hoy más rápido
    var m: Int          // metros comparados (la distancia común)
    var seg: Int        // lo que tardaste aquella vez en esos metros
    var serie: [[Double]]

    enum CodingKeys: String, CodingKey {
        case id, dia, km, m, seg, serie
        case fin = "final"
    }
}

struct Fantasma: Decodable {
    var veces: Int
    var ultima: Comparacion?
    var mejor: Comparacion?
}

struct RutaDe: Decodable {
    var id: String
    var nombre: String
    var veces: Int
}

struct Intento: Decodable, Hashable {
    var fit: String?
    var dia: String?
    var seg: Int
    var m: Int?
}

struct SegmentoAqui: Decodable, Identifiable {
    var id: String
    var nombre: String
    var m: Int
    var veces: Int
    var mejor: Intento?
    var aqui: [Intento]
    var puesto: Int?
}

struct RutaBiblio: Decodable, Identifiable {
    struct Mejor: Decodable {
        var id: String
        var dia: String
        var seg: Int?
        var ritmo: String?
    }
    var id: String
    var nombre: String
    var km: Double
    var ref: String
    var veces: Int
    var ultima: String?
    var mejor: Mejor?
}

struct SesionRuta: Decodable {
    var dia: String
    var n: String
    var min: Int
    var km: Double
}

struct Biblioteca: Decodable {
    var rutas: [RutaBiblio]
    var sesion: SesionRuta?
    var sugeridas: [String]
}

struct Segmento: Decodable, Identifiable {
    var id: String
    var nombre: String
    var m: Int
    var veces: Int
    var mejor: Intento?
    var intentos: [Intento]
}

/// Un fichero listo para la hoja de compartir.
struct ArchivoCompartido: Identifiable {
    let url: URL
    var id: String { url.path }
}

extension API {
    /// Baja un GPX (/api/actividad/<id>/gpx o /api/rutas/<id>/gpx) a un fichero temporal para compartirlo con la app
    /// del COROS (Rutas → importar) y llevarlo en el reloj.
    static func gpx(_ ruta: String, nombre: String) async throws -> URL {
        var p = try peticion(ruta)
        p.timeoutInterval = 60
        p.setValue("application/gpx+xml", forHTTPHeaderField: "Accept")
        let (datos, _) = try await mandaCrudo(p)
        let limpio = nombre.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined(separator: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(limpio + ".gpx")
        try datos.write(to: url, options: .atomic)
        return url
    }
}

private func mmssR(_ s: Double) -> String {
    let n = Int(abs(s).rounded())
    return String(n / 60) + ":" + (n % 60 < 10 ? "0" : "") + String(n % 60)
}

private func conSigno(_ s: Int) -> String {
    (s < 0 ? "−" : s > 0 ? "+" : "±") + mmssR(Double(s))
}

private func kmTexto(_ x: Double) -> String {
    x.formatted(.number.precision(.fractionLength(0...1)).locale(FechasES.locale))
}

private func metros(_ m: Int) -> String {
    m >= 1000 ? kmTexto(Double(m) / 1000) + " km" : String(m) + " m"
}

private func diaMes(_ s: String?) -> String {
    guard let s, s.count == 10 else { return "" }
    let d = Int(s.suffix(2)) ?? 0, mes = Int(s.dropFirst(5).prefix(2)) ?? 0
    return String(d) + "/" + String(mes)
}

// MARK: botón del GPX

struct BotonGPX: View {
    let ruta: String
    let nombre: String
    var titulo = "GPX para el reloj"
    @State private var archivo: ArchivoCompartido?
    @State private var bajando = false
    @State private var fallo = false

    var body: some View {
        Button {
            Task {
                bajando = true
                defer { bajando = false }
                if let u = try? await API.gpx(ruta, nombre: nombre) {
                    archivo = ArchivoCompartido(url: u)
                } else {
                    fallo = true
                }
            }
        } label: {
            Label(bajando ? "Bajando…" : (fallo ? "Sin conexión" : titulo), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .font(Tema.fuente(.pequeno, peso: .semibold))
        }
        .buttonStyle(.bordered).tint(Tema.acento).disabled(bajando)
        .sheet(item: $archivo) { a in
            HojaCompartir(cosas: [a.url]).presentationDetents([.medium, .large])
        }
    }
}

// MARK: contra tu fantasma (en el detalle)

private struct PuntoFantasma: Identifiable {
    let id: Int
    let km: Double
    let delante: Double   // segundos por delante (> 0) o por detrás (< 0)
}

struct CartaFantasma: View {
    let f: Fantasma?

    private func veces(_ n: Int) -> String {
        n == 1 ? "2.ª vez en esta ruta" : String(n + 1) + " veces aquí"
    }

    private func comparado(_ u: Comparacion) -> String {
        let dia: String = diaMes(u.dia)
        if abs(u.fin) < 3 { return "igual que el " + dia }
        return (u.fin < 0 ? "más rápido" : "más lento") + " que el " + dia
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            if let f, let u = f.ultima {
                TituloCarta(titulo: "Contra tu fantasma", detalle: veces(f.veces))
                HStack(alignment: .firstTextBaseline, spacing: Tema.Espacio.s) {
                    Text(conSigno(u.fin)).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(u.fin < 0 ? Tema.acento : Tema.texto)
                    Text(comparado(u))
                        .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                }
                if let m = f.mejor {
                    let frente: String = "Frente a tu mejor vez aquí, el " + diaMes(m.dia)
                    Text(frente + ": " + conSigno(m.fin))
                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                }
                GraficaFantasma(serie: u.serie)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(u.km, id: \.km) { k in
                        HStack(spacing: 4) {
                            Text("km " + String(k.km)).foregroundStyle(Tema.suave)
                            Text(conSigno(k.dif)).fontWeight(.semibold).foregroundStyle(k.dif < 0 ? Tema.acento : Tema.texto)
                        }
                        .font(Tema.fuente(.pequeno)).monospacedDigit()
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Tema.carta2, in: RoundedRectangle(cornerRadius: Tema.Radio.celda))
                    }
                }
                Text("Arriba de la línea vas por delante. Las pausas no cuentan.")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.tenue)
            } else {
                TituloCarta(titulo: "Contra tu fantasma")
                Text("Primera vez en esta ruta. Cuando la repitas, correrás contra esta.")
                    .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave).fixedSize(horizontal: false, vertical: true)
            }
        }
        .carta()
    }
}

private struct GraficaFantasma: View {
    let serie: [[Double]]

    private var puntos: [PuntoFantasma] {
        var out = [PuntoFantasma(id: 0, km: 0, delante: 0)]
        for (i, p) in serie.enumerated() where p.count >= 2 {
            out.append(PuntoFantasma(id: i + 1, km: p[0] / 1000, delante: -p[1]))
        }
        return out
    }

    var body: some View {
        Chart(puntos) { p in
            AreaMark(x: .value("Km", p.km), y: .value("Segundos", p.delante))
                .foregroundStyle(Tema.acento.opacity(0.18))
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("Km", p.km), y: .value("Segundos", p.delante))
                .foregroundStyle(Tema.acento)
                .interpolationMethod(.catmullRom)
            RuleMark(y: .value("Empate", 0)).foregroundStyle(Tema.suave.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1))
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { v in
                AxisGridLine()
                AxisValueLabel { Text(conSigno(-Int(v.as(Double.self) ?? 0))) }
            }
        }
        .frame(height: 130)
    }
}

// MARK: segmentos de esta carrera (en el detalle)

struct CartaSegmentosAqui: View {
    let segmentos: [SegmentoAqui]

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            TituloCarta(titulo: "Segmentos", detalle: "se crean en la web")
            ForEach(segmentos) { s in
                FilaSegmentoAqui(s: s)
            }
        }
        .carta()
    }
}

private struct FilaSegmentoAqui: View {
    let s: SegmentoAqui

    private var tiempo: Int { s.aqui.map(\.seg).min() ?? 0 }
    private var marca: String {
        let porKm: Double = Double(tiempo) / Double(max(1, s.m)) * 1000
        return mmssR(Double(tiempo)) + " · " + mmssR(porKm) + "/km"
    }
    private var detalle: String {
        var t: String = metros(s.m) + " · "
        if s.veces == 1 {
            t += "primera vez"
        } else if s.puesto == 1 {
            t += "mejor marca de " + String(s.veces)
        } else {
            t += String(s.puesto ?? 0) + ".º de " + String(s.veces)
            if let m = s.mejor {
                let mejor: String = mmssR(Double(m.seg))
                t += " · tu mejor: " + mejor + " el " + diaMes(m.dia)
            }
        }
        return t
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(s.nombre).font(Tema.fuente(.texto, peso: .semibold)).foregroundStyle(Tema.texto).lineLimit(1)
                Spacer(minLength: 6)
                Text(marca)
                    .font(Tema.fuente(.texto, peso: .semibold)).monospacedDigit()
                    .foregroundStyle(s.puesto == 1 && s.veces > 1 ? Tema.acento : Tema.texto)
            }
            Text(detalle).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
        }
        .padding(Tema.Espacio.s + 2)
        .background(Tema.carta2, in: RoundedRectangle(cornerRadius: Tema.Radio.celda))
    }
}

// MARK: tu biblioteca de rutas y tus segmentos (en Carrera)

struct CartaRutas: View {
    @State private var fit = CarrerasFit.shared
    @State private var biblio: Biblioteca?
    @State private var segmentos: [Segmento] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            TituloCarta(titulo: "Tus rutas", detalle: "GPX → COROS → reloj")
            if let b = biblio {
                if let s = b.sesion {
                    Text(frase(s, sugeridas: b.sugeridas.count))
                        .font(Tema.fuente(.texto)).foregroundStyle(Tema.texto).fixedSize(horizontal: false, vertical: true)
                }
                if b.rutas.isEmpty {
                    Text("Aún no hay rutas: sube un .fit del COROS.").font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                }
                ForEach(b.rutas) { r in
                    FilaRuta(r: r, sugerida: b.sugeridas.contains(r.id)) {
                        fit.abierta = fit.lista.first(where: { $0.id == (r.mejor?.id ?? r.ref) })
                    }
                }
            } else {
                Text("Cargando…").font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            }
            if !segmentos.isEmpty {
                Text("Tus segmentos").font(Tema.fuente(.texto, peso: .semibold)).foregroundStyle(Tema.texto).padding(.top, Tema.Espacio.s)
                ForEach(segmentos) { s in
                    FilaSegmento(s: s)
                }
            }
            Text("Cada .fit cae en su ruta. El nombre se cambia y los segmentos se crean en la web.")
                .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.tenue).fixedSize(horizontal: false, vertical: true)
        }
        .carta()
        .task(id: fit.subidas) { await carga() }
    }

    private func frase(_ s: SesionRuta, sugeridas: Int) -> String {
        let cuando: String = FechasES.corta(s.dia) + ": " + s.n
        let cuanto: String = ", unos " + kmTexto(s.km) + " km"
        let cuales: String
        if sugeridas == 0 {
            cuales = ". Ninguna de tus rutas se acerca todavía."
        } else if sugeridas == 1 {
            cuales = " → te propongo la marcada."
        } else {
            cuales = " → te propongo las marcadas."
        }
        return cuando + cuanto + cuales
    }

    private func carga() async {
        if let d = try? await API.datos("/api/rutas"), let b = try? JSONDecoder().decode(Biblioteca.self, from: d) {
            withAnimation(Tema.Muelle.pantalla) { biblio = b }
        }
        if let d = try? await API.datos("/api/segmentos"), let s = try? JSONDecoder().decode([Segmento].self, from: d) {
            withAnimation(Tema.Muelle.pantalla) { segmentos = s }
        }
    }
}

private struct FilaRuta: View {
    let r: RutaBiblio
    let sugerida: Bool
    let abre: () -> Void

    private var detalle: String {
        let veces: String = r.veces == 1 ? "1 vez" : String(r.veces) + " veces"
        var t: String = kmTexto(r.km) + " km · " + veces
        if let m = r.mejor, let ri = m.ritmo {
            let ritmo: String = ri.replacingOccurrences(of: " /km", with: "")
            t += " · mejor " + ritmo + "/km el " + diaMes(m.dia)
        }
        return t
    }

    var body: some View {
        HStack(spacing: Tema.Espacio.s) {
            Button(action: abre) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.nombre).font(Tema.fuente(.texto, peso: .semibold)).foregroundStyle(Tema.texto).lineLimit(1)
                    if sugerida {
                        Text("Para la próxima").font(Tema.fuente(.pequeno, peso: .semibold)).foregroundStyle(Tema.acento)
                    }
                    Text(detalle).font(Tema.fuente(.pequeno)).monospacedDigit().foregroundStyle(Tema.suave)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            BotonGPX(ruta: "/api/rutas/" + r.id + "/gpx", nombre: r.nombre, titulo: "GPX")
        }
        .padding(Tema.Espacio.s + 2)
        .background(Tema.carta2, in: RoundedRectangle(cornerRadius: Tema.Radio.celda))
        .overlay {
            if sugerida { RoundedRectangle(cornerRadius: Tema.Radio.celda).stroke(Tema.acento, lineWidth: 2) }
        }
    }
}

private struct FilaSegmento: View {
    let s: Segmento

    private var detalle: String {
        let veces: String = s.veces == 1 ? "1 vez" : String(s.veces) + " veces"
        var t: String = metros(s.m) + " · " + veces
        if let m = s.mejor {
            let porKm: Double = Double(m.seg) / Double(max(1, s.m)) * 1000
            let tiempo: String = mmssR(Double(m.seg))
            t += " · mejor " + tiempo
            t += " (" + mmssR(porKm) + "/km) el " + diaMes(m.dia)
        }
        return t
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(s.nombre).font(Tema.fuente(.texto, peso: .semibold)).foregroundStyle(Tema.texto).lineLimit(1)
            Text(detalle).font(Tema.fuente(.pequeno)).monospacedDigit().foregroundStyle(Tema.suave)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Tema.Espacio.s + 2)
        .background(Tema.carta2, in: RoundedRectangle(cornerRadius: Tema.Radio.celda))
    }
}
