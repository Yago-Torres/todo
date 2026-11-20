import SwiftUI

/// «Tu año en números» (como /anio.html, anio.py del servidor): el titular y tres frases de Claude, el año en puntos y
/// una tarjeta por cosa (hábitos, gimnasio, correr, peso, sueño, pasos, móvil, gastos, inversión, Claude, uso).
/// Se abre tocando «Tu año» en Hoy. Los datos llegan tal cual del servidor (JSON suelto): cada tarjeta sale si hay dato.
struct PantallaAnio: View {
    @State private var datos: [String: Any] = [:]
    @State private var lectura: [String: Any]?
    @State private var cargado = false
    @State private var pidiendo = false
    @State private var error: String?

    private struct Tarjeta: Identifiable {
        let et: String, cifra: String, unidad: String, det: String
        var id: String { et }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tema.Espacio.l) {
                cabecera
                if let l = lectura { titular(l) } else if cargado {
                    Button {
                        Task { await pideLectura() }
                    } label: {
                        Label(pidiendo ? "Pensando…" : "Pedir el titular a Claude", systemImage: "sparkles").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(Tema.acento).disabled(pidiendo)
                }
                if let e = error { Text(e).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro) }
                ForEach(tarjetas) { t in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t.et.uppercased()).font(Tema.fuente(.etiqueta, peso: .semibold)).foregroundStyle(Tema.suave)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(t.cifra).font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Tema.texto)
                            Text(t.unidad).font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                        }
                        if !t.det.isEmpty {
                            Text(t.det).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .carta()
                }
                if cargado && tarjetas.isEmpty {
                    Text("Todavía no hay datos de este año.").font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                }
            }
            .padding(.horizontal, Tema.Espacio.l)
            .padding(.top, Tema.Espacio.s)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .refreshable { await carga() }
        .task { await carga() }
    }

    private var cabecera: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(rango).estiloEtiqueta().foregroundStyle(Tema.suave)
            Text(titulo).font(Tema.fuente(.titulo)).foregroundStyle(Tema.texto)
        }
    }

    private var titulo: String {
        if let x = num(datos["anio"]) { return "Tu " + String(Int(x)) }
        return "Tu año"
    }

    private var rango: String {
        guard let d = datos["desde"] as? String, let h = datos["hasta"] as? String else { return "En números" }
        return "Del \(FechasES.corta(d)) al \(FechasES.corta(h))"
    }

    private func titular(_ l: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            Text("«" + cad(l["titular"]) + "»").font(.system(size: 26, weight: .bold)).foregroundStyle(Tema.texto)
                .fixedSize(horizontal: false, vertical: true)
            ForEach((l["frases"] as? [String]) ?? [], id: \.self) { f in
                Text(f).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto).fixedSize(horizontal: false, vertical: true)
            }
            Text("Escrito por Claude. El 31 de diciembre se rehace con el año entero.").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .carta()
    }

    // MARK: las tarjetas, a partir del JSON

    private func dic(_ k: String) -> [String: Any] { datos[k] as? [String: Any] ?? [:] }
    private func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
    private func n(_ v: Double?, _ dec: Int = 0) -> String {
        guard let v else { return "–" }
        return v.formatted(.number.precision(.fractionLength(dec)).locale(FechasES.locale))
    }

    private func cad(_ v: Any?) -> String { v as? String ?? "" }
    private func plural(_ x: Double, _ uno: String, _ varios: String) -> String { x == 1 ? uno : varios }
    private func lista(_ v: Any?) -> [[String: Any]] { v as? [[String: Any]] ?? [] }

    // Sin literales dentro de las interpolaciones: el compilador de Xcode se perdía (20/11).
    private var tarjetas: [Tarjeta] {
        var t: [Tarjeta] = []
        let h = dic("habitos"), g = dic("gimnasio"), a = dic("actividad"), c = dic("cuerpo"), m = dic("movil"), din = dic("dinero")
        let inv = dic("inversion"), cl = dic("claude")

        if let marcas = num(h["marcas"]), marcas > 0 {
            let r = h["mejor_racha"] as? [String: Any] ?? [:]
            let dias = n(num(h["dias_con_algo"]))
            let racha = n(num(r["racha_max"]))
            let nombre = cad(r["n"])
            var det = "En " + dias + " días. Mejor racha: " + racha + " en «" + nombre + "»."
            if let mes = (h["mejor_mes"] as? [String: Any])?["mes"] as? String { det += " Tu mejor mes, " + mes + "." }
            let olvidados = (h["olvidados"] as? [String]) ?? []
            if !olvidados.isEmpty { det += "\nCasi sin tocar: " + olvidados.joined(separator: ", ") + "." }
            t.append(Tarjeta(et: "Hábitos", cifra: n(marcas), unidad: "hechos", det: det))
        }
        if let s = num(g["sesiones"]), s > 0 {
            let mejoras = lista(g["mas_mejora"]).map { x in cad(x["ej"]) + " +" + n(num(x["pct"])) + " %" }
            var det = "En " + n(s) + " " + plural(s, "sesión", "sesiones") + "."
            if !mejoras.isEmpty { det += " Lo que más ha subido: " + mejoras.joined(separator: ", ") + "." }
            t.append(Tarjeta(et: "Gimnasio", cifra: n(num(g["toneladas"]), 1), unidad: "toneladas", det: det))
        }
        if let k = num(a["carreras"]), k > 0 {
            var det = n(k) + " " + plural(k, "carrera", "carreras") + "; la más larga, " + n(num(a["mas_larga"]), 1) + " km"
            if let ritmo = a["mejor_ritmo"] as? String { det += "; mejor ritmo " + ritmo }
            t.append(Tarjeta(et: "Correr", cifra: n(num(a["km"]), 1), unidad: "km", det: det + "."))
        }
        if let e = num(a["escalada"]), e > 0 {
            t.append(Tarjeta(et: "Escalada", cifra: n(e), unidad: plural(e, "día", "días"), det: ""))
        }
        if let p = c["peso"] as? [String: Any], let cambio = num(p["cambio"]) {
            let det = "De " + n(num(p["inicio"]), 1) + " a " + n(num(p["fin"]), 1) + " kg; el mínimo, " + n(num(p["min"]), 1) + "."
            t.append(Tarjeta(et: "Peso", cifra: (cambio > 0 ? "+" : "") + n(cambio, 1), unidad: "kg", det: det))
        }
        if let s = num(c["sueno_medio"]) {
            let minutos = Int(s) % 60
            let cifra = String(Int(s) / 60) + " h " + (minutos < 10 ? "0" : "") + String(minutos)
            t.append(Tarjeta(et: "Sueño", cifra: cifra, unidad: "de media", det: "En " + n(num(c["noches"])) + " noches con datos."))
        }
        if let p = num(c["pasos"]), p > 0 {
            t.append(Tarjeta(et: "Pasos", cifra: n(p), unidad: "", det: n(num(c["pasos_medios"])) + " al día de media."))
        }
        if let hrs = num(m["horas"]), hrs > 0 {
            let top = lista(m["top"]).map { x in cad(x["app"]) + " " + n(num(x["horas"]), 1) + " h" }
            let det = "En las apps que vigilas, " + n(num(m["media_min"])) + " min al día. " + top.joined(separator: " · ")
            t.append(Tarjeta(et: "Móvil", cifra: n(hrs), unidad: "horas", det: det))
        }
        if let gas = num(din["gastado"]), gas > 0 {
            let cats = lista(din["top_cats"]).map { x in cad(x["cat"]) + " " + n(num(x["eur"])) + " €" }
            var det = "En " + n(num(din["tickets"])) + " compras; " + n(num(din["al_dia_variable"]), 2) + " € al día sin casa ni suscripciones. "
            det += cats.joined(separator: " · ")
            if let caro = (din["mes_mas_caro"] as? [String: Any])?["mes"] as? String { det += ". Mes más caro: " + caro + "." }
            t.append(Tarjeta(et: "Gastos", cifra: n(gas), unidad: "€", det: det))
        }
        if let ops = num(inv["operaciones"]), ops > 0 {
            var det = n(ops) + " " + plural(ops, "operación", "operaciones") + "."
            if let v = num(inv["valor"]) { det += " Vale " + n(v) + " € (" + n(num(inv["rent"]), 1) + " %)." }
            t.append(Tarjeta(et: "Inversión", cifra: n(num(inv["aportado"])), unidad: "€ invertidos", det: det))
        }
        if let ll = num(cl["llamadas"]), ll > 0 {
            t.append(Tarjeta(et: "Claude", cifra: n(ll), unidad: plural(ll, "vez", "veces"), det: "Lo que ha trabajado para ti en la Pi."))
        }
        if let u = datos["uso"] as? [String: Any], let dias = num(u["dias_activos"]), dias > 0 {
            let fav = u["favorita"] as? String ?? "–"
            let det = n(num(u["acciones"])) + " cosas hechas; lo que más usas: " + fav + "."
            t.append(Tarjeta(et: "Tú en la app", cifra: n(dias), unidad: plural(dias, "día", "días"), det: det))
        }
        return t
    }

    // MARK: red

    private func carga() async {
        do {
            let d = try await API.datos("/api/anio")
            let o = try JSONSerialization.jsonObject(with: d) as? [String: Any]
            withAnimation(Tema.Muelle.pantalla) {
                datos = o?["datos"] as? [String: Any] ?? [:]
                lectura = o?["lectura"] as? [String: Any]
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        cargado = true
    }

    private func pideLectura() async {
        pidiendo = true
        do {
            let d = try await API.datos("/api/anio/lectura", metodo: "POST", json: [String: Any]())
            let l = try JSONSerialization.jsonObject(with: d) as? [String: Any]
            withAnimation(Tema.Muelle.pantalla) { lectura = l }
        } catch {
            self.error = error.localizedDescription
        }
        pidiendo = false
    }
}
