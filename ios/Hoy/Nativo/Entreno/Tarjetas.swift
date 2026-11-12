import Charts
import SwiftUI

/// Cada mañana: la rutina guiada de movilidad.
struct TarjetaManana: View {
    @State private var datos = DatosEntreno.shared

    var body: some View {
        let e = datos.e
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            TituloEnt("Cada mañana")
            if let r = e.rutinas.first(where: { $0.tipo == "movilidad" }) {
                FichaEntreno(dia: datos.hoy, habito: e.habito(r.hab) ?? HabitoGym(id: "", n: "Movilidad", c: "#888888"),
                             rutina: r, viendo: .constant(nil))
            } else {
                Text("Sin rutina de movilidad.").font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            }
        }
        .carta()
    }
}

/// Músculos: el mapa de delante y detrás y las mismas series en barras (se leen sin colores).
struct TarjetaMusculos: View {
    @State private var datos = DatosEntreno.shared
    @State private var elegido: String?

    var body: some View {
        let n = Musculos.porMusculo(datos.e, hoy: datos.hoy)
        let tope = max(10, n.values.max() ?? 0)
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            TituloEnt(titulo: "Músculos") {
                Text("series en 7 días").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            }
            MapaCuerpo(series: n, elegido: $elegido)
            Group {
                if let m = elegido, let nombre = Musculos.lista.first(where: { $0.id == m })?.n {
                    Text("\(nombre) · \(FormatoEnt.num(n[m] ?? 0)) series en 7 días")
                        .font(Tema.fuente(.pequeno, peso: .semibold)).foregroundStyle(Tema.texto)
                } else {
                    Text("Toca un músculo para ver sus series").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.tenue)
                }
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 6) {
                ForEach(Musculos.lista.sorted { (n[$0.id] ?? 0) > (n[$1.id] ?? 0) }, id: \.id) { m in
                    Button {
                        withAnimation(Tema.Muelle.toque) { elegido = elegido == m.id ? nil : m.id }
                    } label: {
                        HStack(spacing: Tema.Espacio.m) {
                            Text(m.n).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.texto)
                                .frame(width: 92, alignment: .leading)
                            BarraEnt(valor: (n[m.id] ?? 0) / tope).frame(height: 6)
                            Text(FormatoEnt.num(n[m.id] ?? 0)).font(Tema.fuente(.pequeno, peso: .semibold))
                                .monospacedDigit().foregroundStyle(Tema.texto)
                                .frame(width: 36, alignment: .trailing)
                        }
                        .padding(.vertical, 3).padding(.horizontal, 4)
                        .background(elegido == m.id ? Tema.carta2 : .clear, in: RoundedRectangle(cornerRadius: Tema.Radio.celda))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(m.n): \(FormatoEnt.num(n[m.id] ?? 0)) series")
                }
            }
        }
        .carta()
    }
}

/// Progreso de un ejercicio: la fuerza estimada de cada sesión (o las repes sin peso), récords y los datos.
struct TarjetaProgreso: View {
    struct Punto: Identifiable {
        var dia: String
        var mejor: SerieGym
        var series: [SerieGym]
        var id: String { dia + "\(series.count)\(mejor.kg)\(mejor.n)" }
    }

    @State private var datos = DatosEntreno.shared
    @State private var elegido: String?
    @State private var verDatos = false

    var body: some View {
        let hist = historial
        let nombres = hist.keys.sorted { a, b in
            let na = hist[a]?.count ?? 0, nb = hist[b]?.count ?? 0
            if na != nb { return na > nb }
            return (hist[a]?.map(\.mejor.kg).max() ?? 0) > (hist[b]?.map(\.mejor.kg).max() ?? 0)
        }
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            TituloEnt("Progreso")
            if nombres.isEmpty {
                Text("Cuando apuntes series en una sesión, aquí verás cómo sube cada ejercicio: tu fuerza estimada, récords y cuándo toca subir peso.")
                    .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            } else {
                let actual = elegido.flatMap { nombres.contains($0) ? $0 : nil } ?? nombres[0]
                Menu {
                    ForEach(nombres, id: \.self) { n in
                        let c = hist[n]?.count ?? 0
                        Button("\(n) · \(c) \(c == 1 ? "sesión" : "sesiones")") { withAnimation(Tema.Muelle.toque) { elegido = n } }
                    }
                } label: {
                    HStack {
                        Text(actual).font(Tema.fuente(.texto, peso: .medium)).lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Tema.texto)
                    .padding(.horizontal, Tema.Espacio.m).frame(minHeight: 40)
                    .background(Tema.carta2, in: RoundedRectangle(cornerRadius: Tema.Radio.boton))
                }
                if let h = hist[actual], let ultimo = h.last {
                    detalle(actual, h, ultimo)
                }
            }
        }
        .carta()
    }

    private var historial: [String: [Punto]] {
        var out: [String: [Punto]] = [:]
        for x in datos.e.sesiones {
            for e in x.s.ej where !e.series.isEmpty {
                let mejor = e.series.reduce(e.series[0]) { $1.e1rm > $0.e1rm ? $1 : $0 }
                out[e.ej, default: []].append(Punto(dia: x.dia, mejor: mejor, series: e.series))
            }
        }
        return out
    }

    @ViewBuilder private func detalle(_ nombre: String, _ h: [Punto], _ ultimo: Punto) -> some View {
        let conPeso = h.contains { $0.mejor.kg > 0 }
        let valor: (Punto) -> Double = { conPeso ? $0.mejor.e1rm : Double($0.mejor.n) }
        let top = h.max { valor($0) < valor($1) } ?? ultimo
        let pesado = h.max { $0.mejor.kg < $1.mejor.kg } ?? ultimo
        let vol = ultimo.series.reduce(0) { $0 + $1.kg * Double($1.n) }
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Ahora").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(FormatoEnt.num((valor(ultimo) * 2).rounded() / 2))
                        .font(Tema.fuente(.gigante)).monospacedDigit().foregroundStyle(Tema.texto)
                        .contentTransition(.numericText(value: valor(ultimo)))
                    Text(conPeso ? "kg de 1RM estimado" : "repeticiones").font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                }
            }
            HStack(spacing: Tema.Espacio.s) {
                cifra("Récord", conPeso ? "\(FormatoEnt.num((top.mejor.e1rm * 2).rounded() / 2)) kg" : "\(top.mejor.n) rep")
                cifra("Más peso", conPeso ? "\(FormatoEnt.num(pesado.mejor.kg))×\(pesado.mejor.n)" : "—")
                cifra(vol > 0 ? "Última · \(FormatoEnt.miles(Int(vol))) kg" : "Última", FormatoEnt.corta(ultimo.dia))
            }
            Chart(Array(h.enumerated()), id: \.offset) { i, p in
                LineMark(x: .value("Sesión", i), y: .value(conPeso ? "1RM" : "Repes", valor(p)))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Tema.acento)
                if h.count <= 20 {
                    PointMark(x: .value("Sesión", i), y: .value(conPeso ? "1RM" : "Repes", valor(p)))
                        .foregroundStyle(Tema.acento)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { v in
                    AxisValueLabel {
                        if let i = v.as(Int.self), let p = h.segura(i) {
                            Text(FormatoEnt.corta(p.dia)).font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.tenue)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(Tema.linea)
                    AxisValueLabel().font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.tenue)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 200)
            .accessibilityLabel("\(conPeso ? "1RM estimado" : "Repeticiones") de \(nombre) por sesión")
            DisclosureGroup(isExpanded: $verDatos) {
                VStack(spacing: 0) {
                    filaTabla(["Día", "Mejor serie", conPeso ? "1RM est." : "Rep", "Series"], cabecera: true)
                    ForEach(h.reversed()) { p in
                        filaTabla([FormatoEnt.corta(p.dia), conPeso ? "\(FormatoEnt.num(p.mejor.kg))×\(p.mejor.n)" : "\(p.mejor.n)",
                                   conPeso ? FormatoEnt.num((p.mejor.e1rm * 2).rounded() / 2) : "\(p.mejor.n)", "\(p.series.count)"])
                    }
                }
            } label: {
                Text("Ver los datos").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            }
            .tint(Tema.suave)
        }
    }

    private func cifra(_ t: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).lineLimit(1).minimumScaleFactor(0.8)
            Text(v).font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Tema.Espacio.s)
        .background(Tema.carta2, in: RoundedRectangle(cornerRadius: Tema.Radio.celda))
    }
}

/// Una fila de tabla de datos (cifras alineadas a la derecha salvo la primera).
func filaTabla(_ celdas: [String], cabecera: Bool = false) -> some View {
    HStack(spacing: Tema.Espacio.s) {
        ForEach(Array(celdas.enumerated()), id: \.offset) { i, c in
            Text(c)
                .font(Tema.fuente(.pequeno, peso: cabecera ? .semibold : .regular))
                .foregroundStyle(cabecera ? Tema.suave : Tema.texto)
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: i == 0 ? .leading : .trailing)
        }
    }
    .padding(.vertical, 5)
    .overlay(alignment: .bottom) { Rectangle().fill(Tema.linea).frame(height: 0.5) }
}

/// Historial: las últimas 15 sesiones, cada una con sus series. Borrar pide dos toques.
struct TarjetaHistorial: View {
    @State private var datos = DatosEntreno.shared
    @State private var abierta: String?
    @State private var seguro: String?

    var body: some View {
        let hoy = datos.hoy
        let lista = Array(datos.e.sesiones.filter { $0.s.fin || $0.dia < hoy }.reversed())
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            TituloEnt(titulo: "Historial") {
                if !lista.isEmpty {
                    Text("\(lista.count) \(lista.count == 1 ? "sesión" : "sesiones")")
                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).monospacedDigit()
                }
            }
            if lista.isEmpty {
                Text("Aún no hay sesiones apuntadas.").font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            }
            ForEach(lista.prefix(15), id: \.s.id) { x in
                fila(x.dia, x.s)
                Divider().overlay(Tema.linea)
            }
        }
        .carta()
    }

    private func fila(_ dia: String, _ s: SesionGym) -> some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            Button {
                withAnimation(Tema.Muelle.toque) { abierta = abierta == s.id ? nil : s.id; seguro = nil }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: Tema.Espacio.m) {
                    Text(FormatoEnt.diaSemana(dia)).font(Tema.fuente(.pequeno, peso: .semibold)).foregroundStyle(Tema.suave)
                        .frame(width: 52, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.n).font(Tema.fuente(.texto, peso: .medium)).foregroundStyle(Tema.texto).lineLimit(1)
                        Text(s.resumen).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).monospacedDigit()
                    }
                    Spacer()
                    Image(systemName: "chevron.down").rotationEffect(.degrees(abierta == s.id ? 180 : 0))
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Tema.tenue)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if abierta == s.id {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(s.ej, id: \.ej) { e in
                        (Text(e.ej + "  ").foregroundStyle(Tema.texto)
                         + Text(e.series.map { $0.kg > 0 ? "\(FormatoEnt.num($0.kg))×\($0.n)" : "\($0.n)" }.joined(separator: " · "))
                            .foregroundStyle(Tema.suave))
                            .font(Tema.fuente(.pequeno)).monospacedDigit()
                    }
                    Button(seguro == s.id ? "Toca otra vez para borrar" : "Borrar sesión", role: .destructive) {
                        if seguro != s.id {
                            seguro = s.id
                            Haptica.shared.toca(.error)
                            return
                        }
                        withAnimation(Tema.Muelle.toque) {
                            datos.cambia { e in
                                e.gym[dia] = (e.gym[dia] ?? []).filter { $0.id != s.id }
                                if e.gym[dia]?.isEmpty == true { e.gym[dia] = nil }
                            }
                        }
                    }
                    .buttonStyle(BotonMini(color: Tema.peligro))
                    .padding(.top, Tema.Espacio.xs)
                }
                .padding(.leading, 64)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, Tema.Espacio.xs)
    }
}

/// Carrera esta semana (lo del calendario de todo) y lo último que mandó el atajo o el bot.
struct TarjetaCarreraSemana: View {
    let abrePlan: () -> Void
    @State private var datos = DatosEntreno.shared

    var body: some View {
        let e = datos.e
        let hoy = datos.hoy
        let lunes = FormatoEnt.lunes(hoy)
        let filas: [(dia: String, h: String, r: RutinaGym)] = (0..<7).flatMap { i -> [(dia: String, h: String, r: RutinaGym)] in
            let d = FormatoEnt.mas(lunes, i)
            return (e.sesion[d] ?? [:]).sorted { $0.key < $1.key }.compactMap { par -> (dia: String, h: String, r: RutinaGym)? in
                guard let r = e.rutina(par.value), r.tipo == "carrera" else { return nil }
                return (dia: d, h: par.key, r: r)
            }
        }
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            TituloEnt(titulo: "Carrera esta semana") {
                Button("Plan y gráficas", action: abrePlan).buttonStyle(BotonMini())
            }
            if filas.isEmpty {
                Text("Sin carreras esta semana.").font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            }
            ForEach(filas, id: \.dia) { f in
                let hecho = e.hecho(f.dia, f.h)
                HStack(spacing: Tema.Espacio.m) {
                    Text(FormatoEnt.diaSemana(f.dia)).font(Tema.fuente(.pequeno, peso: .semibold)).foregroundStyle(Tema.suave)
                        .frame(width: 52, alignment: .leading)
                    Text(f.r.n).font(Tema.fuente(.texto, peso: .medium))
                        .foregroundStyle(hecho ? Tema.suave : Tema.texto).strikethrough(hecho, color: Tema.tenue).lineLimit(1)
                    Spacer()
                    if hecho { ChipEnt(texto: "Hecho") } else if f.dia < hoy {
                        Text("Pendiente").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.aviso)
                    }
                }
                .padding(Tema.Espacio.s)
                .background(Tema.carta2, in: RoundedRectangle(cornerRadius: Tema.Radio.celda))
                .overlay(RoundedRectangle(cornerRadius: Tema.Radio.celda).strokeBorder(f.dia == hoy ? Tema.acento : .clear, lineWidth: 2))
            }
            if let dia = e.actividad.keys.max(), let a = e.actividad[dia]?.last {
                HStack(alignment: .firstTextBaseline, spacing: Tema.Espacio.s) {
                    Text(a.n.isEmpty ? a.t : a.n).font(Tema.fuente(.texto, peso: .semibold)).foregroundStyle(Tema.texto)
                    Text([FormatoEnt.corta(dia), a.km > 0 ? "\(FormatoEnt.num(a.km)) km" : "", a.min > 0 ? "\(a.min) min" : "", a.ritmo]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).monospacedDigit()
                }
                .padding(.leading, Tema.Espacio.s)
                .overlay(alignment: .leading) { Rectangle().fill(Tema.acento).frame(width: 3) }
                .padding(.top, Tema.Espacio.xs)
            }
        }
        .carta()
    }
}

/// Peso: el último, la media de 7 pesajes (la diaria rebota con el agua; la media no) y la tendencia de 30.
struct TarjetaPeso: View {
    @State private var datos = DatosEntreno.shared
    @State private var texto = ""
    @FocusState private var enfocado: Bool

    var body: some View {
        let peso = datos.e.peso
        let dias = peso.keys.sorted()
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            TituloEnt("Peso")
            if let ult = dias.last, let kg = peso[ult] {
                let sem = dias.suffix(7).compactMap { peso[$0] }
                let media = sem.reduce(0, +) / Double(max(1, sem.count))
                HStack(alignment: .firstTextBaseline, spacing: Tema.Espacio.s) {
                    Text(FormatoEnt.num(kg)).font(Tema.fuente(.cifra)).monospacedDigit().foregroundStyle(Tema.texto)
                        .contentTransition(.numericText(value: kg))
                    Text("kg · \(FormatoEnt.corta(ult))").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                    Spacer()
                    Text(FormatoEnt.num((media * 10).rounded() / 10)).font(Tema.fuente(.cifra)).monospacedDigit()
                        .foregroundStyle(Tema.texto).contentTransition(.numericText(value: media))
                    Text("media 7").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                }
                let ultimos = Array(dias.suffix(30))
                if ultimos.count > 2 {
                    Chart(Array(ultimos.enumerated()), id: \.offset) { i, d in
                        BarMark(x: .value("Día", i), y: .value("Kg", peso[d] ?? 0))
                            .foregroundStyle(Tema.acento.opacity(i == ultimos.count - 1 ? 1 : 0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                    }
                    .chartYScale(domain: (ultimos.compactMap { peso[$0] }.min() ?? 0) - 0.5 ... (ultimos.compactMap { peso[$0] }.max() ?? 1) + 0.2)
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 44)
                    .accessibilityLabel("Tendencia de \(ultimos.count) pesajes")
                }
            } else {
                Text("Sin registros. Apúntalo abajo.").font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            }
            HStack(spacing: Tema.Espacio.s) {
                TextField("Peso de hoy", text: $texto)
                    .keyboardType(.decimalPad)
                    .focused($enfocado)
                    .font(Tema.fuente(.texto))
                    .padding(.horizontal, Tema.Espacio.m).frame(minHeight: 44)
                    .background(Tema.carta2, in: RoundedRectangle(cornerRadius: Tema.Radio.boton))
                    .accessibilityLabel("Peso de hoy en kilos")
                Button("Guardar", action: guarda)
                    .buttonStyle(BotonEnt(principal: true))
                    .frame(width: 110)
                    .disabled(FormatoEnt.lee(texto) == nil)
            }
        }
        .carta()
    }

    private func guarda() {
        guard let v = FormatoEnt.lee(texto) else { return }
        let kg = (v * 10).rounded() / 10
        guard kg >= 20 && kg <= 400 else {
            Haptica.shared.toca(.error)
            return
        }
        let hoy = datos.hoy
        withAnimation(Tema.Muelle.toque) { datos.cambia { $0.peso[hoy] = kg } }
        texto = ""
        enfocado = false
        Haptica.shared.toca(.marcar)
    }
}
