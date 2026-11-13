import SwiftUI

/// La lista: añadir arriba (con autocompletado del catálogo, sin red también), el total frente al objetivo y una fila
/// por alimento con su cantidad y sus macros. Deslizar a la derecha marca, a la izquierda quita (con «Deshacer»).
struct ListaComida: View {
    @Binding var haciendoReceta: Bool
    @State private var datos = DatosLista.shared
    @State private var texto = ""
    @State private var editando: ItemLista?
    @FocusState private var escribiendo: Bool

    private var separado: (cantidad: Double?, unidad: UnidadLista?, nombre: String) { BuscaAlimentos.separa(texto) }
    private var sugerencias: [Alimento] { BuscaAlimentos.busca(separado.nombre, en: datos.catalogo) }

    var body: some View {
        VStack(spacing: Tema.Espacio.m) {
            anadir
            List {
                if !datos.cesta.items.isEmpty {
                    Section { resumen.listRowBackground(Tema.carta) }
                }
                Section {
                    ForEach(datos.items) { i in fila(i) }
                } footer: {
                    if datos.cesta.items.contains(where: \.hecho) {
                        Button("Quitar los marcados") { datos.quitaMarcados() }
                            .font(Tema.fuente(.pequeno, peso: .medium)).foregroundStyle(Tema.acento)
                            .padding(.top, Tema.Espacio.xs)
                    }
                }
                if datos.cesta.items.contains(where: { !$0.hecho }) {
                    Section {
                        Button {
                            Haptica.shared.toca(.marcar)
                            escribiendo = false
                            haciendoReceta = true
                        } label: {
                            Label("Hazme una receta", systemImage: "frying.pan")
                                .font(Tema.fuente(.destacado)).foregroundStyle(Tema.acentoTexto)
                                .frame(maxWidth: .infinity).padding(.vertical, 4)
                        }
                        .listRowBackground(Tema.acento)
                        .accessibilityHint("Elige ingredientes de la lista y Claude te propone una receta")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .listSectionSpacing(Tema.Espacio.m)
            .contentMargins(.top, 0, for: .scrollContent)
            .contentMargins(.bottom, 110, for: .scrollContent)
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await datos.carga() }
            .overlay { vacio }
        }
        .sheet(item: $editando) { i in HojaItem(item: i) }
    }

    // MARK: añadir

    private var anadir: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Tema.Espacio.s) {
                Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(Tema.acento)
                TextField("Añadir: «200 g pollo», «2 huevos»…", text: $texto)
                    .font(Tema.fuente(.destacado))
                    .foregroundStyle(Tema.texto)
                    .focused($escribiendo)
                    .submitLabel(.done)
                    .autocorrectionDisabled()
                    .onSubmit { anadeLoEscrito() }
                    .accessibilityLabel("Añadir un alimento a la lista")
                if !texto.isEmpty {
                    Button { texto = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Tema.tenue) }
                        .accessibilityLabel("Borrar lo escrito")
                }
            }
            .padding(Tema.Espacio.m)
            if !separado.nombre.isEmpty && escribiendo {
                Divider().overlay(Tema.linea)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sugerencias) { a in
                        Button { anade(a) } label: { FilaSugerencia(alimento: a, cantidad: separado.cantidad, unidad: separado.unidad) }
                            .buttonStyle(EstiloHundir())
                    }
                    if !sugerencias.contains(where: { BuscaAlimentos.clave($0.n) == BuscaAlimentos.clave(separado.nombre) }) {
                        Button { estima() } label: {
                            HStack(spacing: Tema.Espacio.s) {
                                if datos.estimando != nil {
                                    ProgressView().tint(Tema.acento).frame(width: 22)
                                } else {
                                    Image(systemName: "sparkles").foregroundStyle(Tema.acento).frame(width: 22)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(datos.estimando != nil ? "Calculando los macros de «\(separado.nombre)»…"
                                                                : "Añadir «\(separado.nombre)» y calcular sus macros")
                                        .font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                                        .multilineTextAlignment(.leading)
                                    Text("No está en la tabla: Claude estima los valores y se guardan")
                                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, Tema.Espacio.m).padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(EstiloHundir())
                        .disabled(datos.estimando != nil)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Tema.carta, in: RoundedRectangle(cornerRadius: Tema.Radio.carta, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Tema.Radio.carta, style: .continuous)
            .strokeBorder(Tema.linea.opacity(0.6), lineWidth: 0.5))
        .padding(.horizontal, Tema.Espacio.l)
        .animation(Tema.Muelle.toque, value: sugerencias.map(\.id))
        .animation(Tema.Muelle.toque, value: escribiendo)
    }

    private func anade(_ a: Alimento) {
        let s = separado
        datos.anade(a, nombre: a.n, cantidad: s.cantidad, unidad: s.unidad == .ud && a.g_ud == nil ? a.u : s.unidad)
        texto = ""
    }

    /// Intro: la primera sugerencia si casa bien; si no hay ninguna, a estimar.
    private func anadeLoEscrito() {
        guard !separado.nombre.isEmpty else { return }
        if let a = sugerencias.first { anade(a) } else { estima() }
    }

    private func estima() {
        let s = separado
        Task {
            await datos.estimaYAnade(s.nombre, cantidad: s.cantidad, unidad: s.unidad)
            if datos.aviso?.error != true { texto = "" }
        }
    }

    // MARK: resumen

    private var resumen: some View {
        let t = datos.total
        let o = datos.cesta.objetivo
        return VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total de la lista").estiloEtiqueta().foregroundStyle(Tema.suave)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(Formato.entero(t.kcal)).font(Tema.fuente(.cifra)).monospacedDigit()
                            .foregroundStyle(Tema.texto)
                            .contentTransition(.numericText(value: t.kcal))
                        Text("kcal").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Proteína").estiloEtiqueta().foregroundStyle(Tema.suave)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(Formato.entero(t.prot)).font(Tema.fuente(.cifra)).monospacedDigit()
                            .foregroundStyle(ColorMacro.prot)
                            .contentTransition(.numericText(value: t.prot))
                        Text("g").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            if let o, o.kcal > 0 {
                VStack(spacing: Tema.Espacio.s) {
                    BarraObjetivo(nombre: "Frente al objetivo de kcal", valor: t.kcal, objetivo: o.kcal, unidad: "kcal")
                    BarraObjetivo(nombre: "Frente al objetivo de proteína", valor: t.prot, objetivo: o.proteina, unidad: "g",
                                  color: ColorMacro.prot)
                }
            }
            VStack(alignment: .leading, spacing: Tema.Espacio.s) {
                Text("Reparto de las kcal").font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.suave)
                BarraMacros(macros: t)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Tema.Espacio.m) { leyenda(t) }
                    VStack(alignment: .leading, spacing: 4) { leyenda(t) }
                }
            }
            if datos.sinDatos > 0 {
                Label(datos.sinDatos == 1 ? "1 alimento sin macros: tócalo para calcularlos"
                                          : "\(datos.sinDatos) alimentos sin macros: tócalos para calcularlos",
                      systemImage: "questionmark.circle")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.aviso)
            }
        }
        .padding(.vertical, Tema.Espacio.xs)
        .animation(Tema.Muelle.pantalla, value: t)
    }

    @ViewBuilder private func leyenda(_ t: Macros) -> some View {
        LeyendaMacro(nombre: "Proteína", gramos: t.prot, color: ColorMacro.prot)
        LeyendaMacro(nombre: "Hidratos", gramos: t.hc, color: ColorMacro.hc)
        LeyendaMacro(nombre: "Grasa", gramos: t.grasa, color: ColorMacro.grasa)
    }

    // MARK: filas

    private func fila(_ i: ItemLista) -> some View {
        FilaItem(item: i) { datos.marca(i) }
            .contentShape(Rectangle())
            .onTapGesture { escribiendo = false; editando = i }
            .listRowBackground(Tema.carta)
            .listRowSeparatorTint(Tema.linea)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button { datos.marca(i) } label: {
                    Label(i.hecho ? "Desmarcar" : "Marcar", systemImage: i.hecho ? "arrow.uturn.backward" : "checkmark")
                }
                .tint(Tema.acento)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) { datos.quita(i) } label: { Label("Quitar", systemImage: "trash") }
            }
            .contextMenu {
                Button { editando = i } label: { Label("Cambiar cantidad", systemImage: "scalemass") }
                Button { datos.marca(i) } label: {
                    Label(i.hecho ? "Desmarcar" : "Marcar", systemImage: "checkmark.circle")
                }
                Button(role: .destructive) { datos.quita(i) } label: { Label("Quitar", systemImage: "trash") }
            }
    }

    @ViewBuilder private var vacio: some View {
        if datos.cesta.items.isEmpty && datos.cargado {
            VStack(spacing: Tema.Espacio.s) {
                Image(systemName: "basket").font(.system(size: 34)).foregroundStyle(Tema.tenue)
                Text("La lista está vacía. Escribe arriba lo que tienes o quieres comprar y verás sus macros.")
                    .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                    .multilineTextAlignment(.center)
            }
            .padding(Tema.Espacio.xl)
            .allowsHitTesting(false)
        }
    }
}

/// Una sugerencia del autocompletado: nombre, de dónde sale y lo que da por 100 g (o la cantidad escrita).
private struct FilaSugerencia: View {
    let alimento: Alimento
    let cantidad: Double?
    let unidad: UnidadLista?

    var body: some View {
        let a = alimento
        HStack(spacing: Tema.Espacio.s) {
            Image(systemName: a.origen == "estimado" ? "sparkles" : "leaf")
                .font(.system(size: 13)).foregroundStyle(Tema.suave).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(a.n).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                Text("Por 100 \(a.u == .ml ? "ml" : "g"): P \(Formato.decimal(a.n100.prot)) · H \(Formato.decimal(a.n100.hc)) · G \(Formato.decimal(a.n100.grasa))")
                    .font(Tema.fuente(.pequeno)).monospacedDigit().foregroundStyle(Tema.suave)
            }
            Spacer(minLength: 0)
            Text("\(Formato.entero(a.n100.kcal)) kcal").font(Tema.fuente(.pequeno, peso: .medium)).monospacedDigit()
                .foregroundStyle(Tema.texto)
        }
        .padding(.horizontal, Tema.Espacio.m).padding(.vertical, 9)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Añade \(a.n) a la lista")
    }
}

/// Una línea de la lista: marcar, nombre, cantidad y macros, kcal a la derecha.
private struct FilaItem: View {
    let item: ItemLista
    let marca: () -> Void

    var body: some View {
        let m = item.macros
        HStack(alignment: .center, spacing: Tema.Espacio.m) {
            Button(action: marca) {
                Image(systemName: item.hecho ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(item.hecho ? Tema.acento : Tema.tenue)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.hecho ? "Desmarcar \(item.n)" : "Marcar \(item.n)")
            VStack(alignment: .leading, spacing: 4) {
                Text(item.n.capitalizadoComida)
                    .font(Tema.fuente(.texto, peso: .medium))
                    .foregroundStyle(item.hecho ? Tema.suave : Tema.texto)
                    .strikethrough(item.hecho, color: Tema.suave)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(item.cantidadTexto).contentTransition(.numericText(value: item.c))
                    if let m {
                        Text("·")
                        Text("P \(Formato.entero(m.prot)) · H \(Formato.entero(m.hc)) · G \(Formato.entero(m.grasa))")
                            .contentTransition(.numericText())
                    } else {
                        Text("· sin macros").foregroundStyle(Tema.aviso)
                    }
                }
                .font(Tema.fuente(.pequeno)).monospacedDigit().foregroundStyle(Tema.suave)
                if let m, !item.hecho {
                    BarraMacros(macros: m, alto: 3).frame(maxWidth: 120)
                }
            }
            Spacer(minLength: 0)
            if let m {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(Formato.entero(m.kcal)).font(Tema.fuente(.destacado)).monospacedDigit()
                        .foregroundStyle(item.hecho ? Tema.suave : Tema.texto)
                        .contentTransition(.numericText(value: m.kcal))
                    Text("kcal").font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.suave)
                }
            }
        }
        .padding(.vertical, 2)
        .animation(Tema.Muelle.toque, value: item)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(etiqueta)
        .accessibilityHint("Toca para cambiar la cantidad")
    }

    private var etiqueta: String {
        var t = "\(item.n), \(item.cantidadTexto)"
        if let m = item.macros {
            t += ", \(Formato.entero(m.kcal)) kilocalorías, \(Formato.entero(m.prot)) gramos de proteína"
        } else {
            t += ", sin macros"
        }
        if item.hecho { t += ", marcado" }
        return t
    }
}

// MARK: cambiar una línea

/// La hoja de una línea: la cantidad (con atajos), la unidad y sus macros al momento; sin datos, calcularlos.
struct HojaItem: View {
    @State private var item: ItemLista
    @State private var textoCantidad: String
    @State private var datos = DatosLista.shared
    @Environment(\.dismiss) private var cierra
    @FocusState private var enCantidad: Bool

    init(item: ItemLista) {
        _item = State(initialValue: item)
        _textoCantidad = State(initialValue: Formato.decimal(item.c, 1).replacingOccurrences(of: ".", with: ""))
    }

    private var alimento: Alimento? { datos.alimento(item.a) }
    private var parecidos: [Alimento] { BuscaAlimentos.busca(item.n, en: datos.catalogo, limite: 4) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tema.Espacio.l) {
                    cantidad
                    macros
                    if item.n100 == nil { sinDatos }
                    if let a = alimento {
                        Text("Datos: \(a.fuente.isEmpty ? a.origen : a.fuente)")
                            .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.tenue)
                    }
                    Button(role: .destructive) {
                        datos.quita(item)
                        cierra()
                    } label: {
                        Label("Quitar de la lista", systemImage: "trash")
                            .font(Tema.fuente(.destacado)).frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                    .foregroundStyle(Tema.peligro)
                }
                .padding(Tema.Espacio.l)
            }
            .background(Tema.fondo.ignoresSafeArea())
            .navigationTitle(item.n.capitalizadoComida)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { cierra() }.foregroundStyle(Tema.suave)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { guarda() }.font(Tema.fuente(.destacado)).foregroundStyle(Tema.acento)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Tema.fondo)
        .presentationDragIndicator(.visible)
    }

    private var cantidad: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            Text("Cantidad").estiloEtiqueta().foregroundStyle(Tema.suave)
            HStack(spacing: Tema.Espacio.m) {
                TextField("0", text: $textoCantidad)
                    .keyboardType(.decimalPad)
                    .font(Tema.fuente(.cifra)).monospacedDigit()
                    .foregroundStyle(Tema.texto)
                    .focused($enCantidad)
                    .onChange(of: textoCantidad) { _, t in
                        if let x = Formato.lee(t), x >= 0, x <= 100000 { item.c = x }
                    }
                    .accessibilityLabel("Cantidad en \(item.u.largo)")
                Picker("Unidad", selection: $item.u) {
                    ForEach(UnidadLista.allCases) { u in Text(u.nombre).tag(u) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 170)
            }
            HStack(spacing: Tema.Espacio.s) {
                ForEach(atajos, id: \.self) { x in
                    Button {
                        Haptica.shared.toca(.marcar)
                        item.c = max(0, item.c + x)
                        textoCantidad = Formato.decimal(item.c, 1).replacingOccurrences(of: ".", with: "")
                    } label: {
                        Text(x > 0 ? "+\(Formato.decimal(x))" : Formato.decimal(x))
                            .font(Tema.fuente(.pequeno, peso: .medium)).monospacedDigit()
                            .foregroundStyle(Tema.texto)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Tema.carta2, in: Capsule())
                    }
                    .buttonStyle(EstiloHundir())
                    .accessibilityLabel("\(x > 0 ? "Sumar" : "Restar") \(Formato.decimal(abs(x))) \(item.u.largo)")
                }
            }
            if item.u == .ud && item.n100 != nil && item.g_ud == nil {
                Text("No sé cuánto pesa una unidad de esto: ponlo en gramos para ver sus macros.")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.aviso)
            } else if item.u == .ud, let g = item.g_ud {
                Text("Una unidad ≈ \(Formato.entero(g)) g").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            }
        }
        .carta()
    }

    private var atajos: [Double] { item.u == .ud ? [-1, 1, 2, 6] : [-50, 50, 100, 250] }

    private var macros: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            if let m = item.macros {
                HStack(spacing: 0) {
                    cifra("kcal", m.kcal, "", Tema.texto)
                    cifra("Proteína", m.prot, "g", ColorMacro.prot)
                    cifra("Hidratos", m.hc, "g", ColorMacro.hc)
                    cifra("Grasa", m.grasa, "g", ColorMacro.grasa)
                }
                BarraMacros(macros: m)
            }
            if let n = item.n100 {
                Text("Por 100 \(item.u == .ml ? "ml" : "g"): \(Formato.entero(n.kcal)) kcal · P \(Formato.decimal(n.prot)) · H \(Formato.decimal(n.hc)) · G \(Formato.decimal(n.grasa))")
                    .font(Tema.fuente(.pequeno)).monospacedDigit().foregroundStyle(Tema.suave)
            }
        }
        .carta()
        .animation(Tema.Muelle.toque, value: item.c)
    }

    private func cifra(_ titulo: String, _ valor: Double, _ unidad: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titulo).estiloEtiqueta().foregroundStyle(Tema.suave)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(Formato.entero(valor)).font(Tema.fuente(.destacado)).monospacedDigit().foregroundStyle(color)
                    .contentTransition(.numericText(value: valor))
                if !unidad.isEmpty { Text(unidad).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var sinDatos: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            Text("Sin macros todavía").font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
            if !parecidos.isEmpty {
                Text("¿Es alguno de estos?").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                ForEach(parecidos) { a in
                    Button {
                        datos.engancha(item, a)
                        cierra()
                    } label: {
                        HStack {
                            Text(a.n).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                            Spacer()
                            Text("\(Formato.entero(a.n100.kcal)) kcal/100").font(Tema.fuente(.pequeno)).monospacedDigit()
                                .foregroundStyle(Tema.suave)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(EstiloHundir())
                }
            }
            Button {
                Task {
                    await datos.estima(item)
                    if datos.aviso?.error != true { cierra() }
                }
            } label: {
                HStack(spacing: Tema.Espacio.s) {
                    if datos.estimando != nil { ProgressView().tint(Tema.acentoTexto) } else { Image(systemName: "sparkles") }
                    Text(datos.estimando != nil ? "Calculando…" : "Calcular con Claude")
                }
                .font(Tema.fuente(.destacado)).foregroundStyle(Tema.acentoTexto)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(Tema.acento, in: RoundedRectangle(cornerRadius: Tema.Radio.boton, style: .continuous))
            }
            .buttonStyle(EstiloHundir())
            .disabled(datos.estimando != nil)
        }
        .carta()
    }

    private func guarda() {
        if let x = Formato.lee(textoCantidad), x >= 0 { item.c = x }
        Haptica.shared.toca(.marcar)
        datos.cambia(item)
        cierra()
    }
}
