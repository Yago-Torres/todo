import SwiftUI

/// Gastos en nativo: el ciclo de cobro (gastado, presupuesto, lo que queda y a cuánto sale al día), apuntar al vuelo,
/// categorías con su presupuesto, gráficas y movimientos (buscar, editar, borrar). Los gastos de Aitana son otra
/// instancia con sus propios datos: se cambia con el selector de arriba y nada se suma entre las dos.
struct PantallaGastos: View {
    @State private var datos = DatosGastos.shared
    @State private var filtro: String?
    @State private var abierto: Movimiento?
    @State private var aviso: String?

    /// Los bloques (ids estables, orden y ocultos en la disposición «app-gastos»).
    static let bloques: [(String, String)] = [
        ("resumen", "Cifra del ciclo"), ("importante", "Lo importante"), ("apuntar", "Apuntar"),
        ("categorias", "Por categoría"), ("graficas", "Gráficas"), ("viajes", "Viajes"),
        ("suscripciones", "Suscripciones"), ("ingresos", "Ingresos"), ("movimientos", "Movimientos"),
    ]

    var body: some View {
        PantallaEditable(pantalla: "app-gastos", titulo: "Gastos", bloques: Self.bloques,
                         recarga: { await datos.recarga() }) { editar in
            VStack(alignment: .leading, spacing: Tema.Espacio.l) {
                CabeceraGastos(editar: editar)
                if let copia = datos.copia {
                    Label(API.notaCopia(copia), systemImage: "wifi.slash")
                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.aviso)
                }
                if datos.resumen == nil {
                    if let error = datos.error {
                        Text(error).font(Tema.fuente(.texto)).foregroundStyle(Tema.peligro).carta()
                    } else {
                        Text("Cargando…").font(Tema.fuente(.texto)).foregroundStyle(Tema.suave).carta()
                    }
                }
            }
        } bloque: { id in
            bloque(id)
        } pie: {
            if let aviso {
                Text(aviso).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro)
                    .transition(.opacity)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .task { await datos.carga() }
        .sheet(item: $abierto) { m in EditorMovimiento(movimiento: m) }
        .overlay(alignment: .bottom) { if let b = datos.borrado { DeshacerBorrado(texto: b.texto) } }
        .animation(Tema.Muelle.pantalla, value: datos.borrado == nil)
        .animation(Tema.Muelle.pantalla, value: aviso)
    }

    @ViewBuilder private func bloque(_ id: String) -> some View {
        if let r = datos.resumen {
            switch id {
            case "resumen": HeroGastos(r: r)
            case "importante": if !r.insights.isEmpty { InsightsGastos(insights: r.insights) }
            case "apuntar": ApuntarRapido()
            case "categorias": CategoriasGastos(r: r, filtro: $filtro, aviso: $aviso)
            case "graficas": GraficasGastos(r: r)
            case "viajes": ViajesGastos(r: r)
            case "suscripciones": if !r.suscripciones.isEmpty { SuscripcionesGastos(r: r) }
            case "ingresos": if !r.ingresos.isEmpty { IngresosGastos(r: r) }
            case "movimientos": MovimientosGastos(r: r, filtro: $filtro, abrir: { abierto = $0 })
            default: EmptyView()
            }
        }
    }
}

// MARK: cabecera: quién, y qué ciclo

private struct CabeceraGastos: View {
    let editar: () -> Void
    @State private var datos = DatosGastos.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(datos.instancia == .yago ? "Tus cuentas" : "Cuentas de Aitana, aparte de las tuyas")
                        .estiloEtiqueta().foregroundStyle(Tema.suave)
                        .contentTransition(.interpolate)
                    Text("Gastos").font(Tema.fuente(.titulo)).foregroundStyle(Tema.texto)
                }
                Spacer()
                SelectorInstancia()
                Button(action: editar) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 16, weight: .medium)).foregroundStyle(Tema.suave)
                        .frame(width: 40, height: 40).background(Tema.carta, in: Circle())
                }
                .accessibilityLabel("Editar Gastos")
            }
            if let r = datos.resumen { navegador(r) }
        }
        .padding(.top, Tema.Espacio.s)
    }

    private func navegador(_ r: ResumenGastos) -> some View {
        HStack(spacing: Tema.Espacio.m) {
            Button {
                Haptica.shared.toca(.marcar)
                Task { await datos.ciclo(-1) }
            } label: { Image(systemName: "chevron.left").frame(width: 32, height: 32) }
                .accessibilityLabel("Ciclo anterior")
            Text("\(FechaGasto.corta(r.inicio)) – \(FechaGasto.corta(r.fin))")
                .font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
                .contentTransition(.numericText())
                .animation(Tema.Muelle.pantalla, value: r.inicio)
            Button {
                Haptica.shared.toca(.marcar)
                Task { await datos.ciclo(1) }
            } label: { Image(systemName: "chevron.right").frame(width: 32, height: 32) }
                .disabled(r.fin >= Fecha.hoy())
                .accessibilityLabel("Ciclo siguiente")
            Spacer()
            if datos.ref != Fecha.hoy() {
                Button("Hoy") { Task { await datos.vuelveAHoy() } }
                    .font(Tema.fuente(.pequeno, peso: .semibold))
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(Tema.acento)
    }
}

/// Yago | Aitana: la gota se desliza de uno a otro con muelle.
private struct SelectorInstancia: View {
    @State private var datos = DatosGastos.shared
    @Namespace private var espacio

    var body: some View {
        HStack(spacing: 2) {
            ForEach(InstanciaGastos.allCases) { inst in
                let elegido = inst == datos.instancia
                Button {
                    Haptica.shared.toca(.marcar)
                    Task { await datos.cambia(a: inst) }
                } label: {
                    Text(inst.nombre)
                        .font(Tema.fuente(.pequeno, peso: .semibold))
                        .foregroundStyle(elegido ? Tema.acentoTexto : Tema.suave)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background {
                            if elegido { Capsule().fill(Tema.acento).matchedGeometryEffect(id: "elegido", in: espacio) }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Gastos de \(inst.nombre)")
                .accessibilityAddTraits(elegido ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Tema.carta, in: Capsule())
        .overlay(Capsule().strokeBorder(Tema.linea.opacity(0.6), lineWidth: 0.5))
        .animation(Tema.Muelle.gota, value: datos.instancia)
    }
}

// MARK: la cifra grande

private struct HeroGastos: View {
    let r: ResumenGastos

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            Text(r.actual ? "Este ciclo" : "Ciclo cerrado")
                .estiloEtiqueta().foregroundStyle(Tema.suave)
            Text(Eur.texto(r.total))
                .font(Tema.fuente(.gigante)).monospacedDigit()
                .foregroundStyle(r.pasado ? Tema.peligro : Tema.texto)
                .contentTransition(.numericText(value: r.total))
                .animation(Tema.Muelle.pantalla, value: r.total)
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(bajo)
                .font(Tema.fuente(.pequeno))
                .foregroundStyle(r.pasado ? Tema.peligro : Tema.suave)
                .contentTransition(.interpolate)
            if r.presu > 0 {
                BarraPresupuesto(valor: r.total, maximo: r.presu, ritmo: r.ritmo)
                    .frame(height: 8)
                    .accessibilityHidden(true)
            }
            HStack(alignment: .top, spacing: Tema.Espacio.m) {
                ForEach(cifras, id: \.titulo) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.titulo).estiloEtiqueta().foregroundStyle(Tema.suave)
                        Text(c.valor).font(Tema.fuente(.destacado)).monospacedDigit()
                            .foregroundStyle(c.mal ? Tema.peligro : Tema.texto)
                            .contentTransition(.numericText())
                            .animation(Tema.Muelle.pantalla, value: c.valor)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, Tema.Espacio.xs)
        }
        .carta()
        .accessibilityElement(children: .combine)
    }

    private var bajo: String {
        var t: String
        if r.presu > 0 {
            t = "de \(Eur.entero(r.presu)) · " + (r.pasado ? "te has pasado \(Eur.texto(r.total - r.presu))"
                                                          : "quedan \(Eur.texto(r.presu - r.total))")
            if r.actual { t += " · \(r.quedan) día\(r.quedan == 1 ? "" : "s")" }
        } else {
            t = "\(r.n) gasto\(r.n == 1 ? "" : "s") · sin presupuesto"
        }
        if r.aparte > 0 { t += " · incluye \(Eur.entero(r.aparte)) para viajes" }
        return t
    }

    private struct Cifra { var titulo: String; var valor: String; var mal: Bool }

    private var cifras: [Cifra] {
        var l: [Cifra] = []
        if r.actual && r.presu > 0 {
            l.append(Cifra(titulo: "Al día", valor: Eur.entero(r.alDia), mal: r.pasado))
        } else {
            l.append(Cifra(titulo: "Gastos", valor: String(r.n), mal: false))
        }
        l.append(Cifra(titulo: r.actual ? "Acabarás en" : "Total", valor: Eur.entero(r.cierre),
                       mal: r.presu > 0 && r.cierre > r.presu))
        if r.ingreso > 0 {
            l.append(Cifra(titulo: r.actual ? "Ahorro previsto" : "Ahorro", valor: Eur.entero(r.ahorro), mal: r.ahorro < 0))
        } else {
            // sin ingreso fijo no hay ahorro que calcular: la referencia es el ciclo anterior
            let previo = r.historico.count >= 2 ? r.historico[r.historico.count - 2].total : 0
            l.append(Cifra(titulo: r.diaCobro == 1 ? "Mes anterior" : "Ciclo anterior", valor: Eur.entero(previo), mal: false))
        }
        return l
    }
}

/// Lo gastado contra el presupuesto, con una raya donde deberías ir hoy si gastaras al ritmo del presupuesto.
struct BarraPresupuesto: View {
    let valor: Double
    let maximo: Double
    var ritmo: Double?
    var color: Color?

    var body: some View {
        GeometryReader { g in
            let ancho = g.size.width
            let lleno = maximo > 0 ? min(max(valor / maximo, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Tema.carta2)
                Capsule().fill(color ?? (valor > maximo ? Tema.peligro : Tema.acento))
                    .frame(width: ancho * lleno)
                    .animation(Tema.Muelle.pantalla, value: lleno)
                if let ritmo {
                    Rectangle().fill(Tema.texto.opacity(0.55))
                        .frame(width: 2, height: g.size.height + 4)
                        .offset(x: max(0, ancho * min(ritmo, 1) - 1), y: 0)
                }
            }
        }
    }
}

// MARK: lo importante

private struct InsightsGastos: View {
    let insights: [ResumenGastos.Insight]

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            Text("Lo importante").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
            ForEach(Array(insights.enumerated()), id: \.offset) { _, i in
                HStack(alignment: .firstTextBaseline, spacing: Tema.Espacio.s) {
                    Image(systemName: icono(i.nivel))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(color(i.nivel))
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    Text(i.texto).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .carta()
    }

    private func icono(_ nivel: String) -> String {
        switch nivel {
        case "mal": return "exclamationmark.triangle.fill"
        case "ojo": return "exclamationmark.circle.fill"
        case "ok": return "checkmark.circle.fill"
        default: return "info.circle.fill"
        }
    }

    private func color(_ nivel: String) -> Color {
        switch nivel {
        case "mal": return Tema.peligro
        case "ojo": return Tema.aviso
        case "ok": return Tema.acento
        default: return Tema.suave
        }
    }
}

// MARK: apuntar

private struct ApuntarRapido: View {
    @State private var datos = DatosGastos.shared
    @State private var tipo: TipoApunte = .gasto
    @State private var importe = ""
    @State private var nota = ""
    @State private var cat: String?
    @State private var enviando = false
    @State private var respuesta: String?
    @State private var fallo = false
    @State private var toques = 0
    @FocusState private var enfoque: Bool

    private var cifra: Double? { Eur.lee(importe) }

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            Text("Apuntar").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
            Picker("Qué apuntas", selection: $tipo) {
                ForEach(TipoApunte.allCases) { Text($0.nombre).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack(spacing: Tema.Espacio.s) {
                TextField("0,00", text: $importe)
                    .keyboardType(.decimalPad)
                    .focused($enfoque)
                    .font(Tema.fuente(.cifra)).monospacedDigit()
                    .foregroundStyle(Tema.texto)
                    .frame(maxWidth: 140)
                    .accessibilityLabel("Importe en euros")
                Text("€").font(Tema.fuente(.destacado)).foregroundStyle(Tema.suave)
                TextField(tipo == .gasto ? "Nota o comercio" : tipo == .devuelve ? "Quién y de qué" : "De quién",
                          text: $nota)
                    .font(Tema.fuente(.texto))
                    .padding(.horizontal, Tema.Espacio.m).padding(.vertical, 10)
                    .background(Tema.carta2, in: RoundedRectangle(cornerRadius: Tema.Radio.boton, style: .continuous))
                    .submitLabel(.done)
                    .onSubmit { enfoque = false }
            }
            if tipo != .extra {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Tema.Espacio.s) {
                        chip("Auto", id: nil, color: Tema.suave)
                        ForEach(datos.categorias) { c in
                            chip(c.n, id: c.id, color: datos.color(c.id))
                        }
                    }
                }
            }
            Button {
                envia()
            } label: {
                HStack {
                    if enviando { ProgressView().tint(Tema.acentoTexto) }
                    Text(tipo == .gasto ? "Apuntar gasto" : "Apuntar ingreso")
                        .font(Tema.fuente(.destacado))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .foregroundStyle(Tema.acentoTexto)
                .background(Tema.acento.opacity(cifra == nil ? 0.4 : 1),
                            in: RoundedRectangle(cornerRadius: Tema.Radio.boton, style: .continuous))
            }
            .buttonStyle(EstiloHundir())
            .disabled(cifra == nil || enviando)
            if let respuesta {
                Text(respuesta)
                    .font(Tema.fuente(.pequeno))
                    .foregroundStyle(fallo ? Tema.peligro : Tema.suave)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .carta()
        .animation(Tema.Muelle.pantalla, value: tipo)
        .animation(Tema.Muelle.pantalla, value: respuesta)
        .sensoryFeedback(.success, trigger: toques)
    }

    private func chip(_ nombre: String, id: String?, color: Color) -> some View {
        let elegido = cat == id
        return Button {
            Haptica.shared.toca(.marcar)
            cat = id
        } label: {
            HStack(spacing: 6) {
                if id != nil { Circle().fill(color).frame(width: 8, height: 8) }
                Text(nombre).font(Tema.fuente(.pequeno, peso: elegido ? .semibold : .regular))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .foregroundStyle(elegido ? Tema.acentoTexto : Tema.texto)
            .background(elegido ? Tema.acento : Tema.carta2, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(elegido ? .isSelected : [])
    }

    private func envia() {
        guard let x = cifra, !enviando else { return }
        enviando = true
        enfoque = false
        Task {
            defer { enviando = false }
            do {
                let texto = try await datos.apunta(tipo: tipo, importe: x, nota: nota, cat: tipo == .extra ? nil : cat)
                toques += 1
                fallo = false
                respuesta = texto
                importe = ""
                nota = ""
            } catch {
                Haptica.shared.toca(.error)
                fallo = true
                respuesta = DatosGastos.mensaje(error)
            }
        }
    }
}

// MARK: categorías y presupuestos

private struct CategoriasGastos: View {
    let r: ResumenGastos
    @Binding var filtro: String?
    @Binding var aviso: String?
    @State private var datos = DatosGastos.shared
    @State private var editando = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            HStack {
                Text("Por categoría").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
                Spacer()
                Button(editando ? "Hecho" : "Presupuestos") {
                    Haptica.shared.toca(.marcar)
                    withAnimation(Tema.Muelle.pantalla) { editando.toggle() }
                    if !editando { aviso = nil }
                }
                .font(Tema.fuente(.pequeno, peso: .semibold))
                .foregroundStyle(Tema.acento)
            }
            if editando { ajustes }
            let visibles = r.cats.filter { $0.gastado != 0 || $0.presu > 0 || editando }
            if visibles.isEmpty {
                Text("Nada en este ciclo.").font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            }
            ForEach(visibles) { c in
                if editando {
                    FilaPresupuesto(c: c, color: datos.color(c.id)) { aviso = $0 }
                } else {
                    fila(c)
                }
            }
            if r.aparte > 0 && !editando {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle().fill(Tema.acento).frame(width: 8, height: 8)
                        Text("Hucha de viajes").font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                        Spacer()
                        Text(Eur.texto(r.aparte)).font(Tema.fuente(.texto)).monospacedDigit().foregroundStyle(Tema.texto)
                    }
                    Text("Apartado este ciclo: los viajes salen de aquí, no de tus categorías.")
                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                }
            }
        }
        .carta()
        .animation(Tema.Muelle.pantalla, value: editando)
    }

    private var ajustes: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            let total = r.cats.reduce(0) { $0 + $1.presu }
            Text(total > 0 ? "Presupuesto total: \(Eur.entero(total)) al ciclo."
                           : "Los sugeridos suman \(Eur.entero(r.sugeridoTotal)) al ciclo.")
                .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            Button("Usar sugeridos") {
                Haptica.shared.toca(.marcar)
                Task {
                    do { try await datos.usaSugeridos(); aviso = nil }
                    catch { Haptica.shared.toca(.error); aviso = DatosGastos.mensaje(error) }
                }
            }
            .font(Tema.fuente(.pequeno, peso: .semibold))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Tema.acentoSuave, in: Capsule())
            .foregroundStyle(Tema.acento)
        }
    }

    private func fila(_ c: ResumenGastos.Categoria) -> some View {
        let elegida = filtro == c.id
        return Button {
            Haptica.shared.toca(.marcar)
            withAnimation(Tema.Muelle.pantalla) { filtro = elegida ? nil : c.id }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: Tema.Espacio.s) {
                    Circle().fill(datos.color(c.id)).frame(width: 8, height: 8)
                    Text(c.n).font(Tema.fuente(.texto, peso: elegida ? .semibold : .regular)).foregroundStyle(Tema.texto)
                    if c.estado != "ok" {
                        Text(c.estado == "pasado" ? "pasado" : "ojo")
                            .font(Tema.fuente(.etiqueta))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background((c.estado == "pasado" ? Tema.peligro : Tema.aviso).opacity(0.15), in: Capsule())
                            .foregroundStyle(c.estado == "pasado" ? Tema.peligro : Tema.aviso)
                    }
                    Spacer()
                    HStack(spacing: 0) {
                        Text(Eur.texto(c.gastado)).foregroundStyle(Tema.texto)
                        if c.presu > 0 { Text(" / \(Eur.entero(c.presu))").foregroundStyle(Tema.suave) }
                    }
                    .font(Tema.fuente(.texto)).monospacedDigit()
                    .contentTransition(.numericText())
                }
                if c.presu > 0 {
                    // los fijos (casa, suscripciones) se pagan de golpe: la raya del ritmo no les aplica
                    BarraPresupuesto(valor: c.gastado, maximo: c.presu,
                               ritmo: ["casa", "suscripciones"].contains(c.id) ? nil : r.ritmo,
                               color: c.estado == "pasado" ? Tema.peligro : c.estado == "ojo" ? Tema.aviso : datos.color(c.id))
                        .frame(height: 6)
                } else if c.sugerido > 0 {
                    Text("Sin límite · sugerido \(Eur.entero(c.sugerido))")
                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                }
                if c.devuelto > 0 {
                    Text("Ya descontados \(Eur.texto(c.devuelto)) que te han devuelto")
                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(EstiloHundir())
        .accessibilityAddTraits(elegida ? .isSelected : [])
        .accessibilityHint("Filtra los movimientos por esta categoría")
    }
}

/// Una categoría con su presupuesto editable. Se guarda al salir del campo.
private struct FilaPresupuesto: View {
    let c: ResumenGastos.Categoria
    let color: Color
    let alError: (String?) -> Void
    @State private var datos = DatosGastos.shared
    @State private var texto: String
    @FocusState private var foco: Bool

    init(c: ResumenGastos.Categoria, color: Color, alError: @escaping (String?) -> Void) {
        self.c = c
        self.color = color
        self.alError = alError
        _texto = State(initialValue: c.presu > 0 ? Eur.campo(c.presu) : "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Tema.Espacio.s) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(c.n).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                Spacer()
                TextField(c.sugerido > 0 ? Eur.campo(c.sugerido) : "sin límite", text: $texto)
                    .keyboardType(.decimalPad)
                    .focused($foco)
                    .multilineTextAlignment(.trailing)
                    .font(Tema.fuente(.texto)).monospacedDigit()
                    .padding(.horizontal, Tema.Espacio.m).padding(.vertical, 8)
                    .frame(width: 120)
                    .background(Tema.carta2, in: RoundedRectangle(cornerRadius: Tema.Radio.boton, style: .continuous))
                    .accessibilityLabel("Presupuesto de \(c.n) por ciclo")
            }
            if !c.por.isEmpty {
                Text(c.sugerido > 0 ? "Sugerido \(Eur.entero(c.sugerido)): \(c.por)" : c.por)
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            }
        }
        .onChange(of: foco) { _, ahora in
            if !ahora { guarda() }
        }
    }

    private func guarda() {
        let nuevo = texto.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : (Eur.lee(texto) ?? c.presu)
        guard abs(nuevo - c.presu) > 0.004 else { return }
        Task {
            do {
                try await datos.ponPresupuesto(c.id, nuevo)
                Haptica.shared.toca(.marcar)
                alError(nil)
            } catch {
                Haptica.shared.toca(.error)
                texto = c.presu > 0 ? Eur.campo(c.presu) : ""
                alError(DatosGastos.mensaje(error))
            }
        }
    }
}

// MARK: viajes, suscripciones, ingresos (solo lectura: se crean y se editan en la web)

private struct ViajesGastos: View {
    let r: ResumenGastos
    @State private var datos = DatosGastos.shared

    var body: some View {
        let viajes = datos.estado?.viajes ?? []
        if !viajes.isEmpty || (r.hucha?.aporte ?? 0) > 0 {
            VStack(alignment: .leading, spacing: Tema.Espacio.m) {
                Text("Viajes").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
                if let h = r.hucha, h.aporte > 0 {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hucha de viajes").font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                            Text("Aparta \(Eur.entero(h.aporte)) cada ciclo")
                                .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Eur.texto(h.saldo)).font(Tema.fuente(.texto, peso: .semibold)).monospacedDigit()
                                .foregroundStyle(h.saldo < 0 ? Tema.peligro : Tema.texto)
                            Text("saldo").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                        }
                    }
                }
                ForEach(viajes.sorted { $0.desde > $1.desde }) { v in
                    let gastado = datos.movimientos.filter { $0.viaje == v.id }.reduce(0) { $0 + $1.importe }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(v.n).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                                Text("\(FechaGasto.corta(v.desde)) – \(FechaGasto.corta(v.hasta))")
                                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                            }
                            Spacer()
                            HStack(spacing: 0) {
                                Text(Eur.texto(gastado)).foregroundStyle(Tema.texto)
                                if v.presu > 0 { Text(" / \(Eur.entero(v.presu))").foregroundStyle(Tema.suave) }
                            }
                            .font(Tema.fuente(.texto)).monospacedDigit()
                        }
                        if v.presu > 0 { BarraPresupuesto(valor: gastado, maximo: v.presu).frame(height: 6) }
                    }
                }
                Text("Para crear o cambiar un viaje, usa la web de gastos.")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.tenue)
            }
            .carta()
        }
    }
}

private struct SuscripcionesGastos: View {
    let r: ResumenGastos
    @State private var datos = DatosGastos.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Suscripciones").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
                Spacer()
                Text("\(Eur.texto(r.suscripciones.reduce(0) { $0 + $1.alMes })) al mes")
                    .font(Tema.fuente(.pequeno)).monospacedDigit().foregroundStyle(Tema.suave)
            }
            ForEach(Array(r.suscripciones.enumerated()), id: \.offset) { _, s in
                HStack(spacing: Tema.Espacio.m) {
                    Circle().fill(datos.color(s.cat)).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.n).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto).lineLimit(1)
                        Text("cada \(s.cada) · próximo cobro: \(s.proximo == Fecha.hoy() ? "hoy" : FechaGasto.corta(s.proximo))")
                            .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                    }
                    Spacer()
                    Text(Eur.texto(s.importe)).font(Tema.fuente(.texto)).monospacedDigit().foregroundStyle(Tema.texto)
                }
            }
        }
        .carta()
    }
}

private struct IngresosGastos: View {
    let r: ResumenGastos
    @State private var datos = DatosGastos.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ingresos").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
                Spacer()
                Text("+" + Eur.texto(r.ingresos.reduce(0) { $0 + $1.importe }))
                    .font(Tema.fuente(.pequeno)).monospacedDigit().foregroundStyle(Tema.acento)
            }
            ForEach(r.ingresos.sorted { $0.dia > $1.dia }) { i in
                HStack(spacing: Tema.Espacio.m) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(!i.nota.isEmpty ? i.nota : !i.comercio.isEmpty ? i.comercio
                             : (i.tipo == "devuelve" ? "Te devuelven" : "Ingreso"))
                            .font(Tema.fuente(.texto)).foregroundStyle(Tema.texto).lineLimit(1)
                        Text([FechaGasto.titulo(i.dia),
                              i.tipo == "devuelve" ? "te devuelven de \(datos.nombreCat(i.cat))" : "ingreso extra"]
                            .joined(separator: " · "))
                            .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                    }
                    Spacer()
                    Text("+" + Eur.texto(i.importe)).font(Tema.fuente(.texto)).monospacedDigit().foregroundStyle(Tema.acento)
                }
            }
        }
        .carta()
    }
}

// MARK: movimientos

private struct MovimientosGastos: View {
    let r: ResumenGastos
    @Binding var filtro: String?
    let abrir: (Movimiento) -> Void
    @State private var datos = DatosGastos.shared
    @State private var busqueda = ""

    private var buscando: Bool { !busqueda.trimmingCharacters(in: .whitespaces).isEmpty }

    private var lista: [Movimiento] {
        let todos = datos.movimientos
        let l: [Movimiento]
        if buscando {
            // buscando se mira todo el historial de esta instancia, no solo el ciclo
            let q = sinTildes(busqueda.trimmingCharacters(in: .whitespaces))
            l = todos.filter { m in
                sinTildes("\(m.comercio) \(m.nota) \(datos.nombreCat(m.cat)) \(Eur.campo(m.importe))").contains(q)
            }
        } else {
            l = todos.filter { $0.dia >= r.inicio && $0.dia <= r.fin && (filtro == nil || $0.cat == filtro) }
        }
        return Array(l.sorted { $0.dia != $1.dia ? $0.dia > $1.dia : $0.id > $1.id }.prefix(150))
    }

    private func sinTildes(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
    }

    var body: some View {
        let movs = lista
        let dias = Dictionary(grouping: movs, by: \.dia).keys.sorted(by: >)
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Movimientos").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
                Spacer()
                if let f = filtro, !buscando {
                    Button {
                        withAnimation(Tema.Muelle.pantalla) { filtro = nil }
                    } label: {
                        Label(datos.nombreCat(f), systemImage: "xmark.circle.fill")
                            .font(Tema.fuente(.pequeno, peso: .semibold))
                            .foregroundStyle(Tema.acento)
                    }
                    .accessibilityLabel("Quitar el filtro de \(datos.nombreCat(f))")
                }
                Text("\(movs.count)").font(Tema.fuente(.pequeno)).monospacedDigit().foregroundStyle(Tema.suave)
                    .contentTransition(.numericText())
            }
            HStack(spacing: Tema.Espacio.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(Tema.suave)
                TextField("Buscar por comercio, nota o importe", text: $busqueda)
                    .font(Tema.fuente(.texto))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if buscando {
                    Button { busqueda = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Tema.tenue) }
                        .accessibilityLabel("Borrar búsqueda")
                }
            }
            .padding(.horizontal, Tema.Espacio.m).padding(.vertical, 10)
            .background(Tema.carta2, in: RoundedRectangle(cornerRadius: Tema.Radio.boton, style: .continuous))
            if buscando {
                Text("Resultados en todo el historial de \(datos.instancia.nombre).")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            }
            if movs.isEmpty {
                Text(buscando ? "No hay nada que coincida." : filtro != nil ? "Nada en esta categoría." : "Sin gastos en este ciclo.")
                    .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            }
            ForEach(dias, id: \.self) { dia in
                let delDia = movs.filter { $0.dia == dia }
                HStack {
                    Text(FechaGasto.titulo(dia)).estiloEtiqueta().foregroundStyle(Tema.suave)
                    Spacer()
                    Text(Eur.texto(delDia.reduce(0) { $0 + $1.importe }))
                        .font(Tema.fuente(.pequeno)).monospacedDigit().foregroundStyle(Tema.suave)
                }
                .padding(.top, Tema.Espacio.xs)
                ForEach(delDia) { m in fila(m) }
            }
        }
        .carta()
        .animation(Tema.Muelle.pantalla, value: movs.map(\.id))
    }

    private func fila(_ m: Movimiento) -> some View {
        Button {
            guard !m.pendiente else { return }
            Haptica.shared.toca(.marcar)
            abrir(m)
        } label: {
            HStack(spacing: Tema.Espacio.m) {
                Circle().fill(datos.color(m.cat)).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.titulo(datos.nombreCat(m.cat)))
                        .font(Tema.fuente(.texto)).foregroundStyle(Tema.texto).lineLimit(1)
                    Text(subtitulo(m)).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).lineLimit(1)
                }
                Spacer()
                Text(Eur.texto(m.importe)).font(Tema.fuente(.texto)).monospacedDigit()
                    .foregroundStyle(Tema.texto)
                    .opacity(m.pendiente ? 0.6 : 1)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(EstiloHundir())
        .contextMenu {
            if !m.pendiente {
                Button("Editar", systemImage: "pencil") { abrir(m) }
                Button("Borrar", systemImage: "trash", role: .destructive) {
                    Task {
                        do { try await datos.borra(m); Haptica.shared.toca(.desmarcar) }
                        catch { Haptica.shared.toca(.error) }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func subtitulo(_ m: Movimiento) -> String {
        var partes: [String] = []
        if m.pendiente { partes.append("Sin enviar") }
        if buscando { partes.append(FechaGasto.corta(m.dia)) }
        if m.orig > 0 { partes.append("\(String(format: "%.2f", m.orig).replacingOccurrences(of: ".", with: ",")) \(m.moneda)") }
        if !m.viaje.isEmpty { partes.append("Viaje: \(datos.nombreViaje(m.viaje))") }
        partes.append(datos.nombreCat(m.cat))
        if !m.comercio.isEmpty && !m.nota.isEmpty { partes.append(m.nota) }
        if !m.origen.isEmpty { partes.append(m.origen) }
        return partes.joined(separator: " · ")
    }
}

// MARK: deshacer

private struct DeshacerBorrado: View {
    let texto: String
    @State private var datos = DatosGastos.shared

    var body: some View {
        HStack(spacing: Tema.Espacio.m) {
            Text(texto).font(Tema.fuente(.pequeno, peso: .semibold)).foregroundStyle(Tema.texto)
            Button("Deshacer") {
                Haptica.shared.toca(.marcar)
                Task { try? await datos.deshazBorrado() }
            }
            .font(Tema.fuente(.pequeno, peso: .semibold))
            .foregroundStyle(Tema.acento)
        }
        .padding(.horizontal, Tema.Espacio.l).padding(.vertical, Tema.Espacio.m)
        .background(Tema.carta, in: Capsule())
        .overlay(Capsule().strokeBorder(Tema.linea, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .padding(.bottom, 96)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
