import Charts
import SwiftUI

/// La Pi por dentro (GET /api/sistema, observa.py): una tarjeta en Hoy y, al tocarla, la pantalla entera con lo que
/// pasa, lo que falla y lo que consume. «‹ Hoy» vuelve. El mapa y todas las gráficas, en la web (/sistema.html).

// MARK: modelos

struct PanelSistema: Decodable {
    struct Cuenta: Decodable { var total: Int; var enMarcha: Int }
    struct CuentaTimers: Decodable { var total: Int; var mal: Int }
    struct Docker: Decodable { var sanos: Double?; var total: Double? }
    struct Ahora: Decodable {
        var servicios: Cuenta
        var timers: CuentaTimers
        var peticiones24h: Int
        var fallos5xx24h: Int
        var msMedio24h: Int?
        var erroresLogs24h: Int
        var eventos24h: Int
        var claude30dUsd: Double
        var temperatura: Double?
        var memoriaLibreMb: Double?
        var discoLibreGb: Double?
        var carga: Double?
        var copiaHoras: Double?
        var bajonesPeriodo: Int
        var docker: Docker
        var webs: [String: Double]
    }
    struct Evento: Decodable, Hashable { var t: Int; var tipo: String; var quien: String; var detalle: String }
    struct Servicio: Decodable, Hashable { var servicio: String; var estado: String?; var desde: Int?; var errores: Int; var reinicios: Int }
    struct TimerSis: Decodable, Hashable { var timer: String; var ultima: Int?; var proxima: Int?; var resultado: String; var segundos: Int? }
    struct Quien: Decodable, Hashable { var quien: String; var llamadas: Int; var usd: Double }
    struct Claude: Decodable { var porDia: [String: [String: Double]]; var porQuien: [Quien] }

    var generado: Int
    var ahora: Ahora
    var eventos: [Evento]
    var servicios: [Servicio]
    var timers: [TimerSis]
    var claude: Claude
    var serie: [String: [String: Double]]

    /// Todo bien: servicios en marcha, ningún timer mal, ningún 5xx.
    var sano: Bool { ahora.servicios.enMarcha == ahora.servicios.total && ahora.timers.mal == 0 && ahora.fallos5xx24h == 0 }
}

@MainActor @Observable
final class DatosSistema {
    static let shared = DatosSistema()
    private(set) var panel: PanelSistema?
    private(set) var cargando = false
    var dias = 7
    var error: String?

    func carga() async {
        guard !cargando else { return }
        cargando = true
        defer { cargando = false }
        do {
            let d = try await API.datos("/api/sistema?dias=" + String(dias))
            let dec = JSONDecoder()
            dec.keyDecodingStrategy = .convertFromSnakeCase
            let p = try dec.decode(PanelSistema.self, from: d)
            withAnimation(Tema.Muelle.pantalla) { panel = p }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private func hace(_ ts: Int) -> String {
    let m = Int((Date().timeIntervalSince1970 - Double(ts)) / 60)
    if m < 60 { return "hace " + String(max(0, m)) + " min" }
    if m < 1440 { return "hace " + String(m / 60) + " h" }
    return "hace " + String(m / 1440) + " d"
}

private func cuando(_ ts: Int) -> String {
    let f = DateFormatter()
    f.locale = FechasES.locale
    f.dateFormat = "EEE d, HH:mm"
    return f.string(from: Date(timeIntervalSince1970: Double(ts)))
}

private func coma(_ x: Double, _ d: Int = 0) -> String {
    x.formatted(.number.precision(.fractionLength(d...d)).locale(FechasES.locale))
}

private let verde = Color(red: 0.11, green: 0.69, blue: 0.48)   // «bien», igual en todos los temas (--serie-3 de la web)

// MARK: la tarjeta de Hoy

struct BloqueSistemaHoy: View {
    @State private var datos = DatosSistema.shared

    private func linea(_ p: PanelSistema) -> String {
        let a = p.ahora
        var t = String(a.servicios.enMarcha) + "/" + String(a.servicios.total) + " servicios"
        if a.timers.mal > 0 { t += " · " + String(a.timers.mal) + " timers mal" }
        if a.fallos5xx24h > 0 { t += " · " + String(a.fallos5xx24h) + " fallos" }
        if let temp = a.temperatura { t += " · " + coma(temp) + " °C" }
        t += " · Claude " + coma(a.claude30dUsd) + " $/mes"
        return t
    }

    var body: some View {
        Button {
            Haptica.shared.toca(.marcar)
            Navegador.shared.toca("/sistema.html")
        } label: {
            HStack(spacing: Tema.Espacio.m) {
                Circle().fill(datos.panel.map { $0.sano ? verde : Tema.peligro } ?? Tema.tenue).frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text("La Pi").font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
                    Text(datos.panel.map(linea) ?? (datos.error ?? "Mirando cómo está…"))
                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Tema.tenue)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .carta()
        .accessibilityHint("Abre el panel del sistema")
        .task { if datos.panel == nil { await datos.carga() } }
    }
}

// MARK: la pantalla

struct PantallaSistema: View {
    @State private var datos = DatosSistema.shared
    @State private var seccion = "resumen"

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Tema.Espacio.l) {
                Button {
                    Haptica.shared.toca(.desmarcar)
                    Navegador.shared.toca("/")
                } label: {
                    Label("Hoy", systemImage: "chevron.left").font(Tema.fuente(.texto, peso: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Tema.acento)
                .padding(.top, Tema.Espacio.s)
                .accessibilityHint("Vuelve a Hoy")

                VStack(alignment: .leading, spacing: 2) {
                    Text(datos.panel.map { "Actualizado " + cuando($0.generado) } ?? "La Pi por dentro")
                        .estiloEtiqueta().foregroundStyle(Tema.suave)
                    Text("Sistema").font(Tema.fuente(.titulo)).foregroundStyle(Tema.texto)
                }
                Picker("Sección", selection: $seccion) {
                    Text("Resumen").tag("resumen")
                    Text("Fallos").tag("fallos")
                    Text("Consumo").tag("consumo")
                }
                .pickerStyle(.segmented)

                if let p = datos.panel {
                    switch seccion {
                    case "fallos": FallosSistema(p: p)
                    case "consumo": ConsumoSistema(p: p)
                    default: ResumenSistema(p: p)
                    }
                } else {
                    Text(datos.error ?? "Cargando…").font(Tema.fuente(.texto))
                        .foregroundStyle(datos.error == nil ? Tema.suave : Tema.peligro)
                }
                if let url = URL(string: "https://todo.yagotg.dev/sistema.html") {
                    Link(destination: url) {
                        Label("El mapa de todo y todas las gráficas, en la web", systemImage: "safari")
                            .font(Tema.fuente(.pequeno, peso: .medium))
                    }
                    .foregroundStyle(Tema.acento)
                }
            }
            .padding(.horizontal, Tema.Espacio.l)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .refreshable { await datos.carga() }
        .task { await datos.carga() }
    }
}

// MARK: resumen

private struct Cifra: Identifiable {
    let et: String
    let valor: String
    let sub: String
    let color: Color?
    var id: String { et }
}

private struct ResumenSistema: View {
    let p: PanelSistema

    private var cifras: [Cifra] {
        let a = p.ahora
        var c: [Cifra] = []
        let caidos = a.servicios.total - a.servicios.enMarcha
        c.append(Cifra(et: "Servicios", valor: String(a.servicios.enMarcha) + "/" + String(a.servicios.total),
                       sub: caidos > 0 ? String(caidos) + " caídos" : "todos en marcha", color: caidos > 0 ? Tema.peligro : verde))
        c.append(Cifra(et: "Timers mal", valor: String(a.timers.mal), sub: "de " + String(a.timers.total), color: a.timers.mal > 0 ? Tema.peligro : verde))
        c.append(Cifra(et: "Peticiones 24 h", valor: String(a.peticiones24h), sub: a.msMedio24h.map { String($0) + " ms de media" } ?? "", color: nil))
        c.append(Cifra(et: "Fallos 5xx 24 h", valor: String(a.fallos5xx24h), sub: "dentro de las webs", color: a.fallos5xx24h > 0 ? Tema.peligro : verde))
        c.append(Cifra(et: "Errores en logs", valor: String(a.erroresLogs24h), sub: "últimas 24 h", color: a.erroresLogs24h > 50 ? Tema.aviso : nil))
        c.append(Cifra(et: "Claude 30 días", valor: coma(a.claude30dUsd, 2) + " $", sub: "", color: nil))
        let temp = a.temperatura ?? 0
        c.append(Cifra(et: "Temperatura", valor: a.temperatura.map { coma($0, 1) + " °C" } ?? "—", sub: "se frena a 80",
                       color: temp > 75 ? Tema.peligro : (temp > 68 ? Tema.aviso : nil)))
        c.append(Cifra(et: "Memoria libre", valor: a.memoriaLibreMb.map { coma($0 / 1024, 1) + " GB" } ?? "—",
                       sub: a.carga.map { "carga " + coma($0, 2) } ?? "", color: nil))
        c.append(Cifra(et: "Disco libre", valor: a.discoLibreGb.map { coma($0, 1) + " GB" } ?? "—", sub: "en la SD", color: nil))
        let horas = a.copiaHoras ?? 99
        c.append(Cifra(et: "Última copia", valor: a.copiaHoras.map { "hace " + coma($0) + " h" } ?? "—", sub: "al pendrive",
                       color: horas > 30 ? Tema.peligro : verde))
        c.append(Cifra(et: "Bajones de tensión", valor: String(a.bajonesPeriodo), sub: "en el periodo", color: a.bajonesPeriodo > 0 ? Tema.aviso : verde))
        let sanos = Int(a.docker.sanos ?? 0), total = Int(a.docker.total ?? 0)
        c.append(Cifra(et: "Docker", valor: String(sanos) + "/" + String(total), sub: "contenedores sanos", color: sanos < total ? Tema.peligro : verde))
        return c
    }

    private var webs: [(String, String)] {
        let orden = ["todo", "todo-aitana", "gastos", "gastos-aitana", "home-assistant", "filebrowser", "pistatus"]
        return orden.compactMap { n in
            guard let v = p.ahora.webs[n] else { return nil }
            return (n, v < 0 ? "no contesta" : coma(v) + " ms")
        }
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Tema.Espacio.s), GridItem(.flexible(), spacing: Tema.Espacio.s)],
                  spacing: Tema.Espacio.s) {
            ForEach(cifras) { c in
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.et).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).lineLimit(1)
                    Text(c.valor).font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(c.color ?? Tema.texto).lineLimit(1).minimumScaleFactor(0.7)
                    if !c.sub.isEmpty {
                        Text(c.sub).font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.suave).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Tema.Espacio.s + 2)
                .background(Tema.carta2, in: RoundedRectangle(cornerRadius: Tema.Radio.celda))
            }
        }
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            Text("Lo último que ha pasado").font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
            ListaEventos(eventos: Array(p.eventos.prefix(6)))
        }
        .carta()
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            Text("Las webs ahora").font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
            ForEach(webs, id: \.0) { w in
                HStack {
                    Text(w.0).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                    Spacer()
                    Text(w.1).font(Tema.fuente(.texto)).monospacedDigit().foregroundStyle(w.1 == "no contesta" ? Tema.peligro : Tema.suave)
                }
            }
        }
        .carta()
    }
}

private struct ListaEventos: View {
    let eventos: [PanelSistema.Evento]

    private func icono(_ tipo: String) -> String {
        switch tipo {
        case "reinicio": return "arrow.clockwise"
        case "caido": return "xmark.octagon"
        case "timer": return "timer"
        default: return "shippingbox"
        }
    }

    var body: some View {
        if eventos.isEmpty {
            Text("Nada que contar: todo ha ido bien.").font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
        }
        ForEach(eventos, id: \.self) { e in
            HStack(alignment: .top, spacing: Tema.Espacio.s) {
                Image(systemName: icono(e.tipo)).foregroundStyle(Tema.aviso).frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.quien + ": " + e.detalle).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(cuando(e.t) + " · " + hace(e.t)).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                }
            }
        }
    }
}

// MARK: fallos

private struct FallosSistema: View {
    let p: PanelSistema

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            Text("Servicios").font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
            ForEach(p.servicios, id: \.self) { s in
                FilaServicio(s: s)
            }
        }
        .carta()
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            Text("Timers").font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
            ForEach(p.timers, id: \.self) { t in
                FilaTimer(t: t)
            }
        }
        .carta()
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            Text("Todos los eventos").font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
            ListaEventos(eventos: p.eventos)
        }
        .carta()
    }
}

private struct FilaServicio: View {
    let s: PanelSistema.Servicio

    private var detalle: String {
        var t = s.desde.map { "en marcha " + hace($0) } ?? ""
        if s.reinicios > 0 { t += " · " + String(s.reinicios) + " reinicios" }
        if s.errores > 0 { t += " · " + String(s.errores) + " errores" }
        return t
    }

    var body: some View {
        HStack(spacing: Tema.Espacio.s) {
            Circle().fill(s.estado == "active" ? verde : Tema.peligro).frame(width: 9, height: 9)
            Text(s.servicio).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
            Spacer(minLength: 4)
            Text(detalle).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).lineLimit(1)
        }
    }
}

private struct FilaTimer: View {
    let t: PanelSistema.TimerSis

    private var bien: Bool { t.resultado == "success" || t.resultado.isEmpty }

    private var detalle: String {
        let ultima = t.ultima.map { hace($0) } ?? "aún no"
        let proxima = t.proxima.map { " · próxima " + cuando($0) } ?? ""
        return ultima + proxima
    }

    var body: some View {
        HStack(spacing: Tema.Espacio.s) {
            Circle().fill(bien ? verde : Tema.peligro).frame(width: 9, height: 9)
            Text(t.timer).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
            Spacer(minLength: 4)
            Text(detalle).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).lineLimit(1)
        }
    }
}

// MARK: consumo

private struct PuntoHora: Identifiable {
    let id: String
    let fecha: Date
    let valor: Double
}

private struct BarraDia: Identifiable {
    let id: String
    let dia: String
    let quien: String
    let usd: Double
}

private struct ConsumoSistema: View {
    let p: PanelSistema

    private func serie(_ clave: String) -> [PuntoHora] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let valores = p.serie[clave] ?? [:]
        return valores.keys.sorted().compactMap { k in
            guard let d = f.date(from: k), let v = valores[k] else { return nil }
            return PuntoHora(id: k, fecha: d, valor: v)
        }
    }

    private var barras: [BarraDia] {
        var out: [BarraDia] = []
        for dia in p.claude.porDia.keys.sorted() {
            for (q, v) in p.claude.porDia[dia] ?? [:] {
                out.append(BarraDia(id: dia + q, dia: String(dia.suffix(5)), quien: q, usd: v))
            }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            Text("Claude, por quién (7 días)").font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
            ForEach(p.claude.porQuien, id: \.self) { q in
                HStack {
                    Text(q.quien).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                    Spacer()
                    Text(String(q.llamadas) + " llamadas · " + coma(q.usd, 2) + " $")
                        .font(Tema.fuente(.pequeno)).monospacedDigit().foregroundStyle(Tema.suave)
                }
            }
        }
        .carta()
        if !barras.isEmpty {
            VStack(alignment: .leading, spacing: Tema.Espacio.s) {
                Text("Claude, por día").font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
                Chart(barras) { b in
                    BarMark(x: .value("Día", b.dia), y: .value("$", b.usd))
                        .foregroundStyle(by: .value("Quién", b.quien))
                }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 200)
            }
            .carta()
        }
        GraficaHoras(titulo: "Temperatura (°C)", puntos: serie("pi:temperatura"), color: Tema.peligro)
        GraficaHoras(titulo: "Carga (núcleos ocupados, de 4)", puntos: serie("pi:carga"), color: Tema.acento)
        GraficaHoras(titulo: "Memoria libre (MB)", puntos: serie("pi:memoria_libre_mb"), color: verde)
    }
}

private struct GraficaHoras: View {
    let titulo: String
    let puntos: [PuntoHora]
    let color: Color

    var body: some View {
        if !puntos.isEmpty {
            VStack(alignment: .leading, spacing: Tema.Espacio.s) {
                Text(titulo).font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
                Chart(puntos) { p in
                    LineMark(x: .value("Hora", p.fecha), y: .value("Valor", p.valor))
                        .foregroundStyle(color)
                        .interpolationMethod(.catmullRom)
                    if puntos.count < 24 {
                        PointMark(x: .value("Hora", p.fecha), y: .value("Valor", p.valor)).foregroundStyle(color)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 140)
            }
            .carta()
        }
    }
}
