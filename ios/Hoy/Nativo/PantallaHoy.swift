import SwiftUI

/// Hoy en nativo: lo esencial de la portada web (static/hoy.html) — anillos del día, hábitos de hoy marcables,
/// entreno, lo que vence hoy, salud, carrera y gastos. Lo que no es de aquí abre su sección (web) con la barra.
struct PantallaHoy: View {
    @State private var datos = DatosNativos.shared
    @State private var verOtros = false
    @State private var toques = 0

    /// Los bloques de Hoy, con su id en la disposición "app-hoy" (orden y ocultos, Configurar → Pantallas o «Editar»).
    /// «Semana» (el resumen de /api/semana) va arriba el domingo y el lunes, y abajo y plegada el resto de días.
    static var bloques: [(String, String)] {
        let resto: [(String, String)] = [
            ("anillos", "Anillos del día"), ("habitos", "Hábitos"), ("entreno", "Entreno"), ("tareas", "Para hoy"),
            ("salud", "Salud"), ("carrera", "Carrera"), ("gastos", "Gastos"),
        ]
        let semana = ("semana", "Semana")
        return domingoOLunes ? [semana] + resto : resto + [semana]
    }

    private var hoy: Hoy? { datos.hoy }

    private var progreso: Double {
        let hs = datos.habitosDeHoy
        guard !hs.isEmpty else { return 0 }
        return Double(hs.filter(\.hecho).count) / Double(hs.count)
    }

    var body: some View {
        PantallaEditable(pantalla: "app-hoy", titulo: "Hoy", bloques: Self.bloques, recarga: { await datos.recarga() }) { editar in
            VStack(alignment: .leading, spacing: Tema.Espacio.l) {
                cabecera(editar: editar)
                if let copia = datos.copia { avisoCopia(copia) }
            }
        } bloque: { id in
            bloque(id)
        } pie: {
            if let error = datos.error, hoy == nil {
                Text(error).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro)
            }
        }
        .task { await datos.carga() }
        // completar el día: confeti con los colores del tema, háptica y sonido
        .overlay { CelebracionDia(disparo: toques).ignoresSafeArea() }
    }

    @ViewBuilder private func bloque(_ id: String) -> some View {
        switch id {
        case "anillos": anillos
        case "habitos": seccionHabitos
        case "entreno":
            if let entreno = hoy?.entreno, !entreno.isEmpty { seccionEntreno(entreno) }
        case "tareas":
            if !datos.tareasDeHoy.isEmpty { seccionTareas }
        case "salud": cifrasSalud
        case "carrera":
            if let p = hoy?.carrera?.proxima { tarjetaCarrera(p) }
        case "semana": BloqueSemana(destacado: Self.domingoOLunes)
        case "gastos":
            if let g = hoy?.gastos, g.total != nil { tarjetaGastos(g) }
        default: EmptyView()
        }
    }

    // MARK: cabecera

    private func cabecera(editar: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.fechaLarga())
                    .estiloEtiqueta()
                    .foregroundStyle(Tema.suave)
                    .textCase(.uppercase)
                // el saludo engorda con el día, como en la web (de fino a negrita)
                Text(Self.saludo())
                    .font(Tema.fuente(.titulo, peso: progreso >= 1 ? .heavy : progreso > 0.5 ? .bold : progreso > 0 ? .semibold : .regular))
                    .foregroundStyle(Tema.texto)
                    .contentTransition(.interpolate)
                    .animation(Tema.Muelle.pantalla, value: progreso)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: Tema.Espacio.s)
            MascotaHoy()
                .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 6 }
            Button {
                Haptica.shared.toca(.marcar)
                Navegador.shared.voz = true
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Tema.acentoTexto)
                    .frame(width: 40, height: 40)
                    .background(Tema.acento, in: Circle())
            }
            .accessibilityLabel("Hablar con Tom")
            Button(action: editar) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Tema.suave)
                    .frame(width: 40, height: 40)
                    .background(Tema.carta, in: Circle())
            }
            .accessibilityLabel("Editar Hoy")
            Button {
                Navegador.shared.abre("/ajustes.html")
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Tema.suave)
                    .frame(width: 40, height: 40)
                    .background(Tema.carta, in: Circle())
            }
            .accessibilityLabel("Ajustes")
        }
        .padding(.top, Tema.Espacio.s)
    }

    private func avisoCopia(_ fecha: Date) -> some View {
        Label(API.notaCopia(fecha), systemImage: "wifi.slash")
            .font(Tema.fuente(.pequeno))
            .foregroundStyle(Tema.aviso)
    }

    // MARK: anillos (hábitos, pasos, sueño)

    private var anillos: some View {
        let pasos = hoy?.salud?.pasos?.ultimo
        let sueno = hoy?.salud?.sueno?.ultimo
        let hs = datos.habitosDeHoy
        return HStack(spacing: Tema.Espacio.l) {
            ZStack {
                Anillo(valor: progreso, color: Tema.acento, grosor: 11)
                    .frame(width: 112, height: 112)
                Anillo(valor: Double(pasos ?? 0) / 10_000, color: Tema.aviso, grosor: 11)
                    .frame(width: 84, height: 84)
                Anillo(valor: Double(sueno ?? 0) / 480, color: Color(hex: "#3B5C92"), grosor: 11)
                    .frame(width: 56, height: 56)
            }
            VStack(alignment: .leading, spacing: Tema.Espacio.s) {
                filaAnillo(Tema.acento, "Hábitos", "\(hs.filter(\.hecho).count) de \(hs.count)")
                filaAnillo(Tema.aviso, "Pasos ayer", pasos.map(Self.miles) ?? "—")
                filaAnillo(Color(hex: "#3B5C92"), "Dormido", sueno.map(Self.hm) ?? "—")
            }
        }
        .carta()
        .accessibilityElement(children: .combine)
    }

    private func filaAnillo(_ color: Color, _ nombre: String, _ valor: String) -> some View {
        HStack(spacing: Tema.Espacio.s) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(nombre).estiloEtiqueta().foregroundStyle(Tema.suave)
                Text(valor).font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
                    .contentTransition(.numericText())
                    .monospacedDigit()
            }
        }
    }

    // MARK: hábitos

    private var seccionHabitos: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            encabezado("Hábitos", chip: datos.habitosDeHoy.isEmpty ? nil : "\(datos.habitosDeHoy.filter(\.hecho).count)/\(datos.habitosDeHoy.count)",
                       enlace: ("Semana", "/habitos.html"))
            VStack(spacing: 0) {
                if datos.habitosDeHoy.isEmpty {
                    Text("Nada planificado para hoy.")
                        .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                        .padding(.vertical, Tema.Espacio.m)
                }
                // lo que falta, arriba; lo hecho baja con muelle
                ForEach(datos.habitosDeHoy.sorted { !$0.hecho && $1.hecho }) { h in
                    FilaHabito(habito: h) { marca(h) }
                    if h.id != datos.habitosDeHoy.last?.id { Divider().overlay(Tema.linea) }
                }
            }
            .carta(relleno: Tema.Espacio.m)
            if !datos.otrosHabitos.isEmpty {
                Button {
                    withAnimation(Tema.Muelle.pantalla) { verOtros.toggle() }
                } label: {
                    HStack {
                        Text(verOtros ? "Ocultar el resto" : "El resto (\(datos.otrosHabitos.count))")
                        Image(systemName: "chevron.down").rotationEffect(.degrees(verOtros ? 180 : 0))
                    }
                    .font(Tema.fuente(.pequeno, peso: .medium))
                    .foregroundStyle(Tema.suave)
                }
                .buttonStyle(.plain)
                if verOtros {
                    VStack(spacing: 0) {
                        ForEach(datos.otrosHabitos) { h in
                            FilaHabito(habito: h) { marca(h) }
                        }
                    }
                    .carta(relleno: Tema.Espacio.m)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func marca(_ h: Habito) {
        let nuevo = !h.hecho
        Haptica.shared.toca(nuevo ? .marcar : .desmarcar)
        Task { await datos.marca(h.id, hecho: nuevo) }
        if nuevo, datos.habitosDeHoy.filter({ !$0.hecho && $0.id != h.id }).isEmpty, h.plan { toques += 1 }
    }

    // MARK: entreno

    private func seccionEntreno(_ entreno: [EntrenoHoy]) -> some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            encabezado("Entreno", chip: nil, enlace: ("Abrir", "/entreno.html"))
            Button {
                Navegador.shared.abre("/entreno.html")
            } label: {
                VStack(alignment: .leading, spacing: Tema.Espacio.s) {
                    ForEach(entreno, id: \.self) { e in
                        HStack(spacing: Tema.Espacio.m) {
                            Image(systemName: Self.icono(e.tipo))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(e.hecho ? Tema.acentoTexto : Tema.acento)
                                .frame(width: 34, height: 34)
                                .background(e.hecho ? Tema.acento : Tema.acentoSuave,
                                            in: RoundedRectangle(cornerRadius: Tema.Radio.celda, style: .continuous))
                            Text(e.n).font(Tema.fuente(.texto, peso: .medium)).foregroundStyle(Tema.texto)
                            Spacer()
                            if e.hecho { Image(systemName: "checkmark").foregroundStyle(Tema.acento) }
                        }
                    }
                }
                .carta(relleno: Tema.Espacio.m)
            }
            .buttonStyle(EstiloHundir())
        }
    }

    // MARK: tareas de hoy

    private var seccionTareas: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            encabezado("Para hoy", chip: "\(datos.tareasDeHoy.count)", enlace: ("Pendientes", "/pendientes.html"))
            VStack(spacing: 0) {
                ForEach(datos.tareasDeHoy, id: \.self) { t in
                    HStack(spacing: Tema.Espacio.m) {
                        Button {
                            Haptica.shared.toca(.marcar)
                            Task { await datos.tareaHecha(t) }
                        } label: {
                            Image(systemName: "circle")
                                .font(.system(size: 20))
                                .foregroundStyle(Tema.tenue)
                        }
                        .buttonStyle(.plain)
                        .disabled(t.id == nil)
                        .accessibilityLabel("Hecha: \(t.t)")
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.t).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                            if let due = t.due, due < (hoy?.hoy ?? Fecha.hoy()) {
                                Text("Venció el \(Self.diaCorto(due))").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro)
                            }
                        }
                        Spacer()
                        if let hora = t.hora, !hora.isEmpty {
                            Text(hora).font(Tema.fuente(.pequeno)).monospacedDigit().foregroundStyle(Tema.suave)
                        }
                    }
                    .padding(.vertical, Tema.Espacio.s)
                    .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .trailing).combined(with: .opacity)))
                }
            }
            .carta(relleno: Tema.Espacio.m)
        }
    }

    // MARK: salud, carrera y gastos

    private var cifrasSalud: some View {
        HStack(spacing: Tema.Espacio.s) {
            cifra("Dormido", hoy?.salud?.sueno?.ultimo.map(Self.hm), serie: hoy?.salud?.sueno?.serie)
            cifra("Pasos ayer", hoy?.salud?.pasos?.ultimo.map(Self.miles), serie: hoy?.salud?.pasos?.serie)
            cifra("Peso", hoy?.peso?.kg.map { String(format: "%.1f", $0).replacingOccurrences(of: ".", with: ",") }, serie: nil)
        }
    }

    private func cifra(_ nombre: String, _ valor: String?, serie: [Int?]?) -> some View {
        Button {
            Navegador.shared.abre("/salud.html")
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(nombre).estiloEtiqueta().foregroundStyle(Tema.suave).lineLimit(1)
                Text(valor ?? "—").font(Tema.fuente(.cifra)).foregroundStyle(Tema.texto)
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                if let serie { Linea(valores: serie).stroke(Tema.acento, lineWidth: 1.5).frame(height: 18) }
            }
            .carta(relleno: Tema.Espacio.m)
        }
        .buttonStyle(EstiloHundir())
    }

    private func tarjetaCarrera(_ p: SesionCarrera) -> some View {
        Button {
            Navegador.shared.abre("/carrera.html")
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Carrera · \(p.dia == hoy?.hoy ? "hoy" : Self.diaCorto(p.dia))")
                        .estiloEtiqueta().foregroundStyle(Tema.suave)
                    Text(p.n).font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
                }
                Spacer()
                Image(systemName: "figure.run").font(.system(size: 22)).foregroundStyle(Tema.acento)
            }
            .carta()
        }
        .buttonStyle(EstiloHundir())
    }

    private func tarjetaGastos(_ g: GastosHoy) -> some View {
        Button {
            Navegador.shared.abre("/gastos.html")
        } label: {
            VStack(alignment: .leading, spacing: Tema.Espacio.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Gastos").estiloEtiqueta().foregroundStyle(Tema.suave)
                    Spacer()
                    if let al = g.al_dia { Text("\(Self.euros(al))/día").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave) }
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Self.euros(g.total ?? 0)).font(Tema.fuente(.cifra)).foregroundStyle(Tema.texto).monospacedDigit()
                    if let presu = g.presu, presu > 0 {
                        Text("de \(Self.euros(presu))").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                    }
                }
                if let presu = g.presu, presu > 0 {
                    Barra(valor: (g.total ?? 0) / presu, color: (g.queda ?? 0) < 0 ? Tema.peligro : Tema.acento)
                        .frame(height: 6)
                }
            }
            .carta()
        }
        .buttonStyle(EstiloHundir())
    }

    private func encabezado(_ titulo: String, chip: String?, enlace: (String, String)?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tema.Espacio.s) {
            Text(titulo).font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
            if let chip {
                Text(chip)
                    .estiloEtiqueta().monospacedDigit()
                    .foregroundStyle(Tema.acento)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Tema.acentoSuave, in: Capsule())
                    .contentTransition(.numericText())
            }
            Spacer()
            if let enlace {
                Button(enlace.0) { Navegador.shared.abre(enlace.1) }
                    .font(Tema.fuente(.pequeno, peso: .medium))
                    .foregroundStyle(Tema.acento)
            }
        }
        .padding(.top, Tema.Espacio.s)
    }

    // MARK: formatos

    /// Weekday de Calendar: 1 = domingo, 2 = lunes.
    static var domingoOLunes: Bool { [1, 2].contains(Calendar.current.component(.weekday, from: Date())) }

    static func hm(_ minutos: Int) -> String { "\(minutos / 60) h \(String(format: "%02d", minutos % 60))" }

    /// 8430 → «8.430» (es_ES no agrupa los números de cuatro cifras; aquí sí, como la web).
    static func miles(_ n: Int) -> String {
        let cifras = String(abs(n))
        var out = ""
        for (i, c) in cifras.enumerated() {
            if i > 0 && (cifras.count - i) % 3 == 0 { out += "." }
            out.append(c)
        }
        return (n < 0 ? "-" : "") + out
    }

    static func euros(_ x: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        f.maximumFractionDigits = x >= 100 ? 0 : 2
        return f.string(from: NSNumber(value: x)) ?? "\(x) €"
    }

    static func fechaLarga() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEEE d 'de' MMMM"
        return f.string(from: Date())
    }

    static func diaCorto(_ dia: String) -> String {
        let p = DateFormatter()
        p.locale = Locale(identifier: "en_US_POSIX")
        p.dateFormat = "yyyy-MM-dd"
        guard let d = p.date(from: dia) else { return dia }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEEE d"
        return f.string(from: d)
    }

    static func saludo() -> String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 6 ? "Buenas noches" : h < 14 ? "Buenos días" : h < 21 ? "Buenas tardes" : "Buenas noches"
    }

    static func icono(_ tipo: String) -> String {
        switch tipo {
        case "pesas": return "dumbbell"
        case "carrera": return "figure.run"
        case "movilidad": return "figure.flexibility"
        default: return "figure.climbing"
        }
    }
}

/// Una fila de hábito: el círculo se rellena del color del hábito con un brinco al marcarlo.
struct FilaHabito: View {
    let habito: Habito
    let toca: () -> Void

    var body: some View {
        Button(action: toca) {
            HStack(spacing: Tema.Espacio.m) {
                ZStack {
                    Circle()
                        .strokeBorder(habito.hecho ? Color.clear : Color(hex: habito.c), lineWidth: 2)
                        .background(Circle().fill(habito.hecho ? Color(hex: habito.c) : Color.clear))
                    if habito.hecho {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 26, height: 26)
                .scaleEffect(habito.hecho ? 1 : 0.92)
                .animation(Tema.Muelle.toque, value: habito.hecho)
                Text(habito.n)
                    .font(Tema.fuente(.texto))
                    .foregroundStyle(habito.hecho ? Tema.suave : Tema.texto)
                    .strikethrough(habito.hecho, color: Tema.tenue)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: Tema.Espacio.s)
                if habito.plan && !habito.hecho {
                    Text("plan")
                        .estiloEtiqueta()
                        .foregroundStyle(Tema.acento)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Tema.acentoSuave, in: Capsule())
                }
                if habito.racha > 1 {
                    Label("\(habito.racha)", systemImage: "flame.fill")
                        .font(Tema.fuente(.pequeno, peso: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(habito.hecho ? Tema.aviso : Tema.tenue)
                        .contentTransition(.numericText())
                }
            }
            .padding(.vertical, Tema.Espacio.s + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(EstiloHundir())
        .accessibilityLabel("\(habito.n), \(habito.hecho ? "hecho" : "sin hacer")")
        .accessibilityHint(habito.hecho ? "Toca para desmarcar" : "Toca para marcar")
    }
}

/// Un anillo de progreso que se cierra con muelle (0…1, se recorta a 1).
struct Anillo: View {
    let valor: Double
    let color: Color
    var grosor: CGFloat = 10
    @State private var visto = 0.0

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: grosor)
            Circle()
                .trim(from: 0, to: max(0.001, min(visto, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: grosor, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(grosor / 2)
        .onAppear { withAnimation(.spring(response: 0.9, dampingFraction: 0.8).delay(0.1)) { visto = valor } }
        .onChange(of: valor) { _, nuevo in withAnimation(Tema.Muelle.toque) { visto = nuevo } }
    }
}

/// La línea de 7 días de las cifras (los huecos sin dato se saltan).
struct Linea: Shape {
    let valores: [Int?]

    func path(in r: CGRect) -> Path {
        let puntos = valores.enumerated().compactMap { i, v in v.map { (i, Double($0)) } }
        guard puntos.count > 1, let lo = puntos.map({ $0.1 }).min(), let hi = puntos.map({ $0.1 }).max() else { return Path() }
        let rango = max(hi - lo, 1)
        let paso = r.width / CGFloat(max(valores.count - 1, 1))
        var p = Path()
        for (n, (i, v)) in puntos.enumerated() {
            let pt = CGPoint(x: CGFloat(i) * paso, y: r.maxY - CGFloat((v - lo) / rango) * r.height)
            if n == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}

/// Una barra de progreso de Calma.
struct Barra: View {
    let valor: Double
    let color: Color

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Tema.carta2)
                Capsule().fill(color).frame(width: g.size.width * min(max(valor, 0), 1))
            }
        }
    }
}
