import SwiftUI

/// Comida en nativo: SOLO el menú de la semana. Cada receta con sus ingredientes, kcal y macros (proteína, hidratos,
/// grasa), el objetivo diario de kcal y proteína, y regenerar el menú con una instrucción opcional. Sin lista de la
/// compra ni cuentas (Yago, 12/11): eso sigue en comida.yagotg.dev.
struct PantallaComida: View {
    @State private var datos = DatosComida.shared
    @State private var receta: EstadoComida.Receta?

    /// Los bloques (ids estables, orden y ocultos en la disposición «app-comida»).
    static let bloques: [(String, String)] = [
        ("objetivo", "Objetivo diario"), ("menu", "Menú de la semana"), ("generar", "Menú nuevo"),
    ]

    var body: some View {
        PantallaEditable(pantalla: "app-comida", titulo: "Comida", bloques: Self.bloques,
                         recarga: { await datos.carga() }) { editar in
            VStack(alignment: .leading, spacing: Tema.Espacio.l) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Esta semana").estiloEtiqueta().foregroundStyle(Tema.suave)
                        Text("Comida").font(Tema.fuente(.titulo)).foregroundStyle(Tema.texto)
                    }
                    Spacer()
                    Button(action: editar) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 16, weight: .medium)).foregroundStyle(Tema.suave)
                            .frame(width: 40, height: 40).background(Tema.carta, in: Circle())
                    }
                    .accessibilityLabel("Editar Comida")
                }
                .padding(.top, Tema.Espacio.s)
                if let copia = datos.copia {
                    Label(API.notaCopia(copia), systemImage: "wifi.slash")
                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.aviso)
                }
                if datos.estado == nil {
                    if let error = datos.error {
                        Text(error).font(Tema.fuente(.texto)).foregroundStyle(Tema.peligro).carta()
                    } else {
                        Text("Cargando…").font(Tema.fuente(.texto)).foregroundStyle(Tema.suave).carta()
                    }
                }
            }
        } bloque: { id in
            bloque(id)
        }
        .scrollDismissesKeyboard(.interactively)
        .task { await datos.carga() }
        .sheet(item: $receta) { r in
            if let e = datos.estado { DetalleReceta(receta: r, estado: e) }
        }
    }

    @ViewBuilder private func bloque(_ id: String) -> some View {
        if let e = datos.estado {
            switch id {
            case "objetivo":
                if let o = e.objetivo, o.kcal > 0 { ObjetivoDiario(o: o) }
            case "menu":
                VStack(alignment: .leading, spacing: Tema.Espacio.l) {
                    if !datos.dias.contains(where: { !(e.menu[$0] ?? [:]).isEmpty }) {
                        Text("Todavía no hay menú para esta semana. Genera uno aquí abajo.")
                            .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave).carta()
                    }
                    ForEach(datos.dias, id: \.self) { dia in
                        DiaMenu(dia: dia, estado: e) { receta = $0 }
                    }
                }
            case "generar": GenerarMenu()
            default: EmptyView()
            }
        }
    }
}

// MARK: objetivo del día

private struct ObjetivoDiario: View {
    let o: EstadoComida.Objetivo

    var body: some View {
        HStack(spacing: Tema.Espacio.l) {
            cifra("Objetivo diario", Self.miles(o.kcal), "kcal")
            cifra("Proteína", Self.miles(o.proteina), "g")
        }
        .carta()
        .accessibilityElement(children: .combine)
    }

    private func cifra(_ titulo: String, _ valor: String, _ unidad: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titulo).estiloEtiqueta().foregroundStyle(Tema.suave)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(valor).font(Tema.fuente(.cifra)).monospacedDigit().foregroundStyle(Tema.texto)
                    .contentTransition(.numericText())
                Text(unidad).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func miles(_ x: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: x)) ?? String(Int(x.rounded()))
    }
}

// MARK: un día del menú

private struct DiaMenu: View {
    let dia: String
    let estado: EstadoComida
    let abre: (EstadoComida.Receta) -> Void

    private static let franjas = [("desayuno", "Desayuno"), ("comida", "Comida"), ("cena", "Cena")]

    private var esHoy: Bool { dia == Fecha.hoy() }

    private struct Franja: Identifiable {
        var id: String
        var nombre: String
        var receta: EstadoComida.Receta?
    }

    private var recetas: [Franja] {
        let del = estado.menu[dia] ?? [:]
        return Self.franjas.map { f in Franja(id: f.0, nombre: f.1, receta: del[f.0].flatMap { estado.receta($0) }) }
    }

    private var kcal: Double { recetas.reduce(0) { $0 + ($1.receta?.kcal ?? 0) } }
    private var prot: Double { recetas.reduce(0) { $0 + ($1.receta?.prot ?? 0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.titulo(dia)).font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
                if esHoy {
                    Text("Hoy").font(Tema.fuente(.etiqueta))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Tema.acento, in: Capsule())
                        .foregroundStyle(Tema.acentoTexto)
                }
                Spacer()
            }
            ForEach(recetas) { x in
                if let r = x.receta {
                    Button {
                        Haptica.shared.toca(.marcar)
                        abre(r)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: Tema.Espacio.m) {
                            Text(x.nombre).estiloEtiqueta().foregroundStyle(Tema.suave)
                                .frame(width: 78, alignment: .leading)
                            Text(r.n).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(r.calculada ? "" : "~")\(Int(r.kcal.rounded())) kcal · \(Int(r.prot.rounded())) g")
                                .font(Tema.fuente(.pequeno)).monospacedDigit().foregroundStyle(Tema.suave)
                        }
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(EstiloHundir())
                    .accessibilityLabel("\(x.nombre): \(r.n), \(Int(r.kcal.rounded())) kilocalorías")
                    .accessibilityHint("Abre la receta")
                } else {
                    HStack(spacing: Tema.Espacio.m) {
                        Text(x.nombre).estiloEtiqueta().foregroundStyle(Tema.suave)
                            .frame(width: 78, alignment: .leading)
                        Text("—").font(Tema.fuente(.texto)).foregroundStyle(Tema.tenue)
                    }
                    .padding(.vertical, 5)
                    .accessibilityElement(children: .combine)
                }
            }
            if let o = estado.objetivo, o.kcal > 0, kcal > 0 {
                VStack(spacing: 6) {
                    total("Energía", valor: kcal, objetivo: o.kcal, unidad: "kcal")
                    total("Proteína", valor: prot, objetivo: o.proteina, unidad: "g")
                }
                .padding(.top, Tema.Espacio.xs)
            }
        }
        .padding(Tema.Espacio.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(esHoy ? Tema.acentoSuave : Tema.carta,
                    in: RoundedRectangle(cornerRadius: Tema.Radio.carta, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Tema.Radio.carta, style: .continuous)
            .strokeBorder(Tema.linea.opacity(0.6), lineWidth: 0.5))
        .animation(Tema.Muelle.pantalla, value: kcal)
    }

    private func total(_ nombre: String, valor: Double, objetivo: Double, unidad: String) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(nombre).font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.suave)
                Spacer()
                Text("\(ObjetivoDiario.miles(valor)) / \(ObjetivoDiario.miles(objetivo)) \(unidad)")
                    .font(Tema.fuente(.pequeno)).monospacedDigit().foregroundStyle(Tema.texto)
                    .contentTransition(.numericText())
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Tema.carta2)
                    Capsule().fill(Tema.acento).frame(width: g.size.width * min(max(valor / max(objetivo, 1), 0), 1))
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .combine)
    }

    /// «Jueves 12».
    static func titulo(_ dia: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: dia) else { return dia }
        let g = DateFormatter()
        g.locale = Locale(identifier: "es_ES")
        g.dateFormat = "EEEE d"
        let t = g.string(from: d)
        return t.prefix(1).uppercased() + t.dropFirst()
    }
}

// MARK: una receta

private struct DetalleReceta: View {
    let receta: EstadoComida.Receta
    let estado: EstadoComida
    @Environment(\.dismiss) private var cierra

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tema.Espacio.l) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(receta.tipo).estiloEtiqueta().foregroundStyle(Tema.suave)
                        Text(receta.n).font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Listo") { cierra() }
                        .font(Tema.fuente(.destacado)).foregroundStyle(Tema.acento)
                }
                macros
                if !receta.ing.isEmpty {
                    VStack(alignment: .leading, spacing: Tema.Espacio.s) {
                        Text("Ingredientes").font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
                        ForEach(Array(receta.ing.enumerated()), id: \.offset) { _, l in
                            HStack(alignment: .firstTextBaseline) {
                                Text(estado.nombre(l)).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                                Spacer()
                                Text(estado.cantidad(l)).font(Tema.fuente(.texto)).monospacedDigit()
                                    .foregroundStyle(Tema.suave)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .carta()
                }
                if !receta.pasos.isEmpty {
                    VStack(alignment: .leading, spacing: Tema.Espacio.m) {
                        Text("Pasos").font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
                        ForEach(Array(receta.pasos.enumerated()), id: \.offset) { i, p in
                            HStack(alignment: .firstTextBaseline, spacing: Tema.Espacio.m) {
                                Text("\(i + 1)").font(Tema.fuente(.pequeno, peso: .semibold)).monospacedDigit()
                                    .foregroundStyle(Tema.acentoTexto)
                                    .frame(width: 22, height: 22)
                                    .background(Tema.acento, in: Circle())
                                Text(p).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .carta()
                }
            }
            .padding(Tema.Espacio.l)
        }
        .background(Tema.fondo.ignoresSafeArea())
        .presentationBackground(Tema.fondo)
        .presentationDragIndicator(.visible)
    }

    private var macros: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            HStack(spacing: 0) {
                macro("kcal", Int(receta.kcal.rounded()), "")
                macro("Proteína", Int(receta.prot.rounded()), "g")
                macro("Hidratos", receta.hc.map { Int($0.rounded()) }, "g")
                macro("Grasa", receta.grasa.map { Int($0.rounded()) }, "g")
            }
            if !receta.calculada {
                Text("Cifras estimadas: a algún ingrediente le faltan datos nutricionales.")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            }
        }
        .carta()
    }

    private func macro(_ titulo: String, _ valor: Int?, _ unidad: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titulo).estiloEtiqueta().foregroundStyle(Tema.suave)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(valor.map { "\(receta.calculada ? "" : "~")\($0)" } ?? "—")
                    .font(Tema.fuente(.destacado)).monospacedDigit().foregroundStyle(Tema.texto)
                if valor != nil, !unidad.isEmpty {
                    Text(unidad).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: generar

private struct GenerarMenu: View {
    @State private var datos = DatosComida.shared
    @State private var instruccion = ""
    @State private var toques = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            Text("Menú nuevo").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
            Text("Claude rehace los siete días. Si quieres, dile algo: «sin pescado», «más legumbres»…")
                .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            TextField("Instrucción (opcional)", text: $instruccion, axis: .vertical)
                .lineLimit(1...4)
                .font(Tema.fuente(.texto))
                .padding(.horizontal, Tema.Espacio.m).padding(.vertical, 10)
                .background(Tema.carta2, in: RoundedRectangle(cornerRadius: Tema.Radio.boton, style: .continuous))
                .disabled(datos.generando)
            Button {
                Haptica.shared.toca(.marcar)
                Task {
                    await datos.genera(instruccion: instruccion)
                    if !datos.mensajeEsError { instruccion = ""; toques += 1 }
                }
            } label: {
                HStack(spacing: Tema.Espacio.s) {
                    if datos.generando { ProgressView().tint(Tema.acentoTexto) }
                    Text(datos.generando ? "Generando…" : "Generar menú").font(Tema.fuente(.destacado))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .foregroundStyle(Tema.acentoTexto)
                .background(Tema.acento.opacity(datos.generando ? 0.5 : 1),
                            in: RoundedRectangle(cornerRadius: Tema.Radio.boton, style: .continuous))
            }
            .buttonStyle(EstiloHundir())
            .disabled(datos.generando)
            if let m = datos.mensaje {
                Text(m).font(Tema.fuente(.pequeno))
                    .foregroundStyle(datos.mensajeEsError ? Tema.peligro : Tema.suave)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .carta()
        .animation(Tema.Muelle.pantalla, value: datos.mensaje)
        .animation(Tema.Muelle.pantalla, value: datos.generando)
        .sensoryFeedback(.success, trigger: toques)
    }
}
