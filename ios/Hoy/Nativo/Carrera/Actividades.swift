import Charts
import MapKit
import SwiftUI
import UniformTypeIdentifiers

/// Las carreras del COROS (.fit): la lista en Carrera, subir un .fit (el selector de archivos, o Compartir → Tom desde la
/// app del COROS, que llega por onOpenURL) y el detalle con mapa, ritmo y pulso, y km a km. Como /actividad.html.
/// El servidor lo lee todo (fit.py): aquí solo se pinta.

struct ResumenActividad: Decodable, Identifiable, Hashable {
    var id: String
    var dia: String
    var t: String
    var km: Double
    var seg: Int
    var ritmo: String
    var src: String
    var hora: String?
    var fc: Int?
    var mapa: Bool
}

struct Parcial: Decodable, Hashable {
    var km: Int
    var seg: Int
    var ritmo: String
    var fc: Int?
    var dalt: Int?
}

struct DetalleActividad: Decodable {
    struct Traza: Decodable {
        var puntos: [[Double?]]
        var fantasma: Fantasma?
    }
    var id: String
    var dia: String
    var t: String
    var km: Double
    var seg: Int
    var ritmo: String
    var src: String?
    var hora: String?
    var total: Int?
    var fc: Int?
    var fcMax: Int?
    var cad: Int?
    var sube: Int?
    var baja: Int?
    var kcal: Int?
    var pot: Int?
    var efecto: Double?
    var velMax: Double?
    var parciales: [Parcial]?
    var traza: Traza?
    var ruta: RutaDe?
    var segmentos: [SegmentoAqui]?
}

/// Un punto de la traza ([t, lat, lon, m, alt, fc, vel, cad] cada 5 s), ya con el ritmo suavizado.
struct PuntoTraza: Identifiable {
    var id: Int
    var km: Double
    var lat: Double?
    var lon: Double?
    var alt: Double?
    var fc: Double?
    var ritmo: Double?   // s/km; nil si estabas parado
}

enum TipoFit {
    static var tipo: UTType { UTType(filenameExtension: "fit") ?? .data }
}

@MainActor @Observable
final class CarrerasFit {
    static let shared = CarrerasFit()

    private(set) var lista: [ResumenActividad] = []
    private(set) var subiendo = false
    /// Sube con cada .fit nuevo: la carta de rutas se recarga con ella.
    private(set) var subidas = 0
    var mensaje: String?
    var error = false
    var abierta: ResumenActividad?

    func carga() async {
        guard let d = try? await API.datos("/api/actividades?dias=120"),
              let l = try? JSONDecoder().decode([ResumenActividad].self, from: d) else { return }
        withAnimation(Tema.Muelle.pantalla) { lista = Array(l.filter { $0.km > 0 }.prefix(10)) }
    }

    /// Sube el .fit y abre su detalle. `url` puede venir de fuera (Compartir), de ahí el acceso con permiso.
    func sube(_ url: URL) async {
        let acceso = url.startAccessingSecurityScopedResource()
        defer { if acceso { url.stopAccessingSecurityScopedResource() } }
        guard let bytes = try? Data(contentsOf: url) else {
            avisa("No he podido leer el archivo", error: true)
            return
        }
        subiendo = true
        defer { subiendo = false }
        do {
            var p = try API.peticion("/api/actividad/fit", metodo: "POST")
            p.timeoutInterval = 90
            p.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            let (respuesta, _) = try await API.mandaCrudo(p, subiendo: bytes)
            let o = (try? JSONSerialization.jsonObject(with: respuesta)) as? [String: Any] ?? [:]
            avisa(o["texto"] as? String ?? "Apuntada", error: false)
            Haptica.shared.toca(.record)
            subidas += 1
            await carga()
            await CarreraDatos.shared.carga()
            if let id = o["id"] as? String, let a = lista.first(where: { $0.id == id }) {
                abierta = a
            }
        } catch {
            avisa(error.localizedDescription, error: true)
        }
    }

    func avisa(_ texto: String, error: Bool) {
        withAnimation(Tema.Muelle.pantalla) {
            mensaje = texto
            self.error = error
        }
    }
}

private func mmss(_ s: Double) -> String {
    let n = Int(s.rounded())
    return String(n / 60) + ":" + (n % 60 < 10 ? "0" : "") + String(n % 60)
}

private func hms(_ s: Int) -> String {
    if s < 3600 { return mmss(Double(s)) }
    let resto = mmss(Double(s % 3600))
    return String(s / 3600) + ":" + (resto.count < 5 ? "0" : "") + resto
}

private func coma(_ x: Double, _ dec: Int = 2) -> String {
    x.formatted(.number.precision(.fractionLength(0...dec)).locale(FechasES.locale))
}

// MARK: la carta de Carrera

struct CartaActividades: View {
    @State private var datos = CarrerasFit.shared
    @State private var eligiendo = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            HStack {
                Text("Tus carreras").font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
                Spacer()
                Button {
                    eligiendo = true
                } label: {
                    Label(datos.subiendo ? "Subiendo…" : "Subir .fit", systemImage: "square.and.arrow.up")
                        .font(Tema.fuente(.pequeno, peso: .semibold))
                }
                .buttonStyle(.bordered).tint(Tema.acento).disabled(datos.subiendo)
            }
            if let m = datos.mensaje {
                Text(m).font(Tema.fuente(.pequeno)).foregroundStyle(datos.error ? Tema.peligro : Tema.acento)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if datos.lista.isEmpty {
                Text("Aún no hay carreras apuntadas.").font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            }
            ForEach(datos.lista) { a in
                Button {
                    datos.abierta = a
                } label: {
                    FilaActividad(a: a)
                }
                .buttonStyle(.plain)
            }
            Text("En la app del COROS: la actividad → Compartir → exportar .fit → Tom (o súbelo aquí, o mándaselo al bot).")
                .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.tenue).fixedSize(horizontal: false, vertical: true)
        }
        .carta()
        .task { await datos.carga() }
        .fileImporter(isPresented: $eligiendo, allowedContentTypes: [TipoFit.tipo, .data], allowsMultipleSelection: false) { r in
            if case .success(let urls) = r, let u = urls.first {
                Task { await datos.sube(u) }
            }
        }
        .sheet(item: $datos.abierta) { a in
            PantallaActividad(id: a.id)
                .presentationDragIndicator(.visible)
        }
    }
}

private struct FilaActividad: View {
    let a: ResumenActividad

    private var dia: String { FechasES.corta(a.dia) }
    private var detalle: String {
        var t: [String] = []
        if let fc = a.fc { t.append(String(fc) + " ppm") }
        t.append(a.mapa ? "mapa" : (a.src == "coros" ? "COROS" : "atajo"))
        return t.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: Tema.Espacio.m) {
            Text(dia).font(Tema.fuente(.pequeno, peso: .semibold)).foregroundStyle(Tema.suave).frame(width: 56, alignment: .leading)
            Text(coma(a.km) + " km").font(Tema.fuente(.texto, peso: .semibold)).monospacedDigit().foregroundStyle(Tema.texto)
            Text(a.ritmo).font(Tema.fuente(.pequeno)).monospacedDigit().foregroundStyle(Tema.suave)
            Spacer(minLength: 4)
            Text(detalle).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Tema.tenue)
        }
        .padding(Tema.Espacio.s + 2)
        .background(Tema.carta2, in: RoundedRectangle(cornerRadius: Tema.Radio.celda))
        .contentShape(Rectangle())
    }
}

// MARK: el detalle

struct PantallaActividad: View {
    let id: String
    @State private var a: DetalleActividad?
    @State private var puntos: [PuntoTraza] = []
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tema.Espacio.l) {
                if let a {
                    CabeceraActividad(a: a)
                    CifrasActividad(a: a)
                    if puntos.contains(where: { $0.lat != nil }) {
                        MapaActividad(puntos: puntos, id: a.id, ruta: a.ruta)
                    }
                    if puntos.count > 5 { GraficaActividad(puntos: puntos) }
                    if puntos.contains(where: { $0.lat != nil }) { CartaFantasma(f: a.traza?.fantasma) }
                    if let s = a.segmentos, !s.isEmpty { CartaSegmentosAqui(segmentos: s) }
                    if let p = a.parciales, !p.isEmpty { TablaParciales(parciales: p) }
                } else {
                    Text(error ?? "Cargando…").font(Tema.fuente(.texto)).foregroundStyle(error == nil ? Tema.suave : Tema.peligro)
                        .padding(.top, Tema.Espacio.xl)
                }
            }
            .padding(Tema.Espacio.l)
        }
        .background(Tema.fondo)
        .task { await carga() }
    }

    private func carga() async {
        do {
            let d = try await API.datos("/api/actividad/" + id)
            let dec = JSONDecoder()
            dec.keyDecodingStrategy = .convertFromSnakeCase
            let x = try dec.decode(DetalleActividad.self, from: d)
            puntos = Self.prepara(x.traza?.puntos ?? [])
            withAnimation(Tema.Muelle.pantalla) { a = x }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Los puntos crudos a PuntoTraza, con el ritmo de 30 s alrededor (parado = nil, y como mucho 10:00).
    static func prepara(_ crudos: [[Double?]]) -> [PuntoTraza] {
        let filas = crudos.filter { $0.count >= 8 && $0[3] != nil }
        var out: [PuntoTraza] = []
        for (i, f) in filas.enumerated() {
            let desde = max(0, i - 3), hasta = min(filas.count, i + 3)
            var suma = 0.0, n = 0.0
            for j in desde..<hasta {
                if let v = filas[j][6], v > 0.5 { suma += v; n += 1 }
            }
            let ritmo: Double? = n > 0 ? min(600, 1000 / (suma / n)) : nil
            let m: Double = f[3] ?? 0
            out.append(PuntoTraza(id: i, km: m / 1000, lat: f[1], lon: f[2], alt: f[4], fc: f[5], ritmo: ritmo))
        }
        return out
    }
}

private struct CabeceraActividad: View {
    let a: DetalleActividad

    private var linea: String {
        var t = FechasES.corta(a.dia)
        if let h = a.hora { t += " · " + h }
        if a.src == "coros" { t += " · COROS" }
        return t
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(linea).estiloEtiqueta().foregroundStyle(Tema.suave)
            Text(a.t).font(Tema.fuente(.titulo)).foregroundStyle(Tema.texto)
        }
    }
}

private struct Dato: Identifiable {
    let etiqueta: String
    let valor: String
    var id: String { etiqueta }
}

private struct CifrasActividad: View {
    let a: DetalleActividad

    private var pequenas: [Dato] {
        var t: [Dato] = []
        if let x = a.fc { t.append(Dato(etiqueta: "Pulso medio", valor: String(x) + " ppm")) }
        if let x = a.fcMax { t.append(Dato(etiqueta: "Pulso máximo", valor: String(x) + " ppm")) }
        if let x = a.cad { t.append(Dato(etiqueta: "Cadencia", valor: String(x) + " ppm")) }
        if let x = a.sube { t.append(Dato(etiqueta: "Desnivel", valor: "+" + String(x) + " / −" + String(a.baja ?? 0) + " m")) }
        if let x = a.pot { t.append(Dato(etiqueta: "Potencia", valor: String(x) + " W")) }
        if let x = a.kcal { t.append(Dato(etiqueta: "Calorías", valor: String(x) + " kcal")) }
        if let x = a.total, x - a.seg > 30 { t.append(Dato(etiqueta: "Con pausas", valor: hms(x))) }
        if let x = a.velMax, x > 0 { t.append(Dato(etiqueta: "Más rápido", valor: mmss(1000 / x) + " /km")) }
        if let x = a.efecto { t.append(Dato(etiqueta: "Efecto aeróbico", valor: coma(x, 1))) }
        return t
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            HStack(alignment: .top) {
                grande("Distancia", coma(a.km), "km")
                grande("Tiempo", hms(a.seg), "")
                grande("Ritmo", a.ritmo.replacingOccurrences(of: " /km", with: ""), "/km")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: Tema.Espacio.s)], spacing: Tema.Espacio.s) {
                ForEach(pequenas) { p in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.etiqueta).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).lineLimit(1)
                        Text(p.valor).font(Tema.fuente(.texto, peso: .semibold)).monospacedDigit().foregroundStyle(Tema.texto).lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Tema.Espacio.s + 2)
                    .background(Tema.carta2, in: RoundedRectangle(cornerRadius: Tema.Radio.celda))
                }
            }
        }
        .carta()
    }

    private func grande(_ etiqueta: String, _ valor: String, _ unidad: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(etiqueta).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(valor).font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Tema.texto)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(unidad).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MapaActividad: View {
    let puntos: [PuntoTraza]
    let id: String
    let ruta: RutaDe?

    private var coords: [CLLocationCoordinate2D] {
        puntos.compactMap { p in
            guard let la = p.lat, let lo = p.lon else { return nil }
            return CLLocationCoordinate2D(latitude: la, longitude: lo)
        }
    }

    var body: some View {
        let c = coords
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            TituloCarta(titulo: "Ruta", detalle: "verde, la salida")
            if let ruta {
                Text(ruta.nombre + (ruta.veces > 1 ? " · " + String(ruta.veces) + " veces" : " · la primera vez"))
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            }
            Map(interactionModes: [.pan, .zoom]) {
                MapPolyline(coordinates: c)
                    .stroke(Tema.acento, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                if let ini = c.first {
                    Annotation("Salida", coordinate: ini) {
                        Circle().fill(Color.green).frame(width: 12, height: 12).overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
                if let fin = c.last {
                    Annotation("Llegada", coordinate: fin) {
                        Circle().fill(Tema.texto).frame(width: 12, height: 12).overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: Tema.Radio.celda))
            BotonGPX(ruta: "/api/actividad/" + id + "/gpx", nombre: ruta?.nombre ?? ("Carrera " + id))
        }
        .carta()
    }
}

private struct GraficaActividad: View {
    let puntos: [PuntoTraza]
    @State private var sel: Double?

    private var conRitmo: [PuntoTraza] { puntos.filter { $0.ritmo != nil } }

    /// Del 3 % más rápido al 97 %, con margen y en medios minutos: sin la arrancada ni las paradas.
    private var rango: ClosedRange<Double> {
        let r = conRitmo.compactMap(\.ritmo).sorted()
        guard r.count > 2 else { return 180...600 }
        let lo = r[Int(Double(r.count - 1) * 0.03)], hi = r[Int(Double(r.count - 1) * 0.97)]
        let a = max(120, ((lo - 20) / 30).rounded(.down) * 30)
        let b = min(600, ((hi + 20) / 30).rounded(.up) * 30)
        return a...max(a + 60, b)
    }

    private var lectura: String? {
        guard let sel, let p = puntos.min(by: { abs($0.km - sel) < abs($1.km - sel) }) else { return nil }
        var t = coma(p.km) + " km"
        if let r = p.ritmo { t += " · " + mmss(r) + " /km" }
        if let f = p.fc { t += " · " + String(Int(f)) + " ppm" }
        if let al = p.alt { t += " · " + String(Int(al)) + " m" }
        return t
    }

    var body: some View {
        let r = rango
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            TituloCarta(titulo: "Ritmo", detalle: "arriba, más rápido")
            GraficaRitmoKm(puntos: conRitmo, rango: r, sel: $sel)
            GraficaPulso(puntos: puntos, sel: $sel)
            if let lectura {
                Lectura(texto: lectura)
            }
        }
        .carta()
    }
}

/// El ritmo en negativo para que arriba sea lo rápido (Charts no da la vuelta a un eje); las etiquetas, en positivo.
private struct GraficaRitmoKm: View {
    let puntos: [PuntoTraza]
    let rango: ClosedRange<Double>
    @Binding var sel: Double?

    private func y(_ p: PuntoTraza) -> Double {
        let r: Double = p.ritmo ?? rango.upperBound
        return -min(rango.upperBound, r)
    }

    var body: some View {
        let paso: Double = rango.upperBound - rango.lowerBound > 180 ? 60 : 30
        Chart(puntos) { p in
            LineMark(x: .value("Km", p.km), y: .value("Ritmo", y(p)))
                .foregroundStyle(Tema.acento)
                .interpolationMethod(.catmullRom)
        }
        .chartYScale(domain: -rango.upperBound ... -rango.lowerBound)
        .chartYAxis {
            AxisMarks(values: .stride(by: paso)) { v in
                AxisGridLine()
                AxisValueLabel { Text(mmss(-(v.as(Double.self) ?? 0))) }
            }
        }
        .chartXSelection(value: $sel)
        .frame(height: 170)
    }
}

private struct GraficaPulso: View {
    let puntos: [PuntoTraza]
    @Binding var sel: Double?

    var body: some View {
        let conFc = puntos.filter { $0.fc != nil }
        if conFc.count > 5 {
            VStack(alignment: .leading, spacing: Tema.Espacio.s) {
                Text("Pulso").font(Tema.fuente(.pequeno, peso: .semibold)).foregroundStyle(Tema.suave)
                Chart(conFc) { p in
                    LineMark(x: .value("Km", p.km), y: .value("Pulso", p.fc ?? 0))
                        .foregroundStyle(Tema.peligro)
                        .interpolationMethod(.catmullRom)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXSelection(value: $sel)
                .frame(height: 120)
            }
        }
    }
}

private struct TablaParciales: View {
    let parciales: [Parcial]

    var body: some View {
        let rapido = parciales.map(\.seg).min() ?? 0
        let lento = parciales.map(\.seg).max() ?? 1
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            TituloCarta(titulo: "Kilómetro a kilómetro", detalle: "sin las pausas")
            ForEach(parciales, id: \.km) { p in
                FilaParcial(p: p, rapido: rapido, lento: lento)
            }
        }
        .carta()
    }
}

private struct FilaParcial: View {
    let p: Parcial
    let rapido: Int
    let lento: Int

    private var parte: Double {
        let rango = Double(max(1, lento - rapido))
        return max(0.08, 1 - Double(p.seg - rapido) / rango * 0.7)
    }

    private var desnivel: String {
        guard let d = p.dalt else { return "—" }
        return (d > 0 ? "+" : "") + String(d)
    }

    var body: some View {
        HStack(spacing: Tema.Espacio.s) {
            Text(String(p.km)).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).frame(width: 22, alignment: .leading)
            Text(mmss(Double(p.seg))).font(Tema.fuente(.texto, peso: p.seg == rapido ? .bold : .regular)).monospacedDigit()
                .foregroundStyle(p.seg == rapido ? Tema.acento : Tema.texto).frame(width: 48, alignment: .leading)
            GeometryReader { g in
                Capsule().fill(Tema.acento).frame(width: g.size.width * parte, height: 8)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 16)
            Text(p.fc.map { String($0) } ?? "—").font(Tema.fuente(.pequeno)).monospacedDigit().foregroundStyle(Tema.suave)
                .frame(width: 32, alignment: .trailing)
            Text(desnivel).font(Tema.fuente(.pequeno)).monospacedDigit().foregroundStyle(Tema.suave).frame(width: 34, alignment: .trailing)
        }
    }
}
