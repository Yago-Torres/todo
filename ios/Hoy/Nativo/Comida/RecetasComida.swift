import SwiftUI
import UIKit

/// Las recetas: la última que hizo Claude con lo de la lista y las favoritas.
struct RecetasComida: View {
    @Binding var haciendoReceta: Bool
    @Binding var abierta: RecetaLista?
    @State private var datos = DatosLista.shared

    var body: some View {
        List {
            Section {
                Button {
                    Haptica.shared.toca(.marcar)
                    haciendoReceta = true
                } label: {
                    Label("Hazme una receta con la lista", systemImage: "frying.pan")
                        .font(Tema.fuente(.destacado)).foregroundStyle(Tema.acentoTexto)
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .listRowBackground(Tema.acento)
                .disabled(datos.cesta.items.allSatisfy(\.hecho))
            } footer: {
                if datos.cesta.items.allSatisfy(\.hecho) {
                    Text("Añade antes algo a la lista: la receta se hace con lo que tengas.")
                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                }
            }
            if let r = datos.cesta.ultima, !datos.esFavorita(r) {
                Section {
                    fila(r)
                } header: {
                    Text("La última").estiloEtiqueta().foregroundStyle(Tema.suave)
                }
            }
            Section {
                ForEach(datos.cesta.favoritas.sorted { $0.t > $1.t }) { r in
                    fila(r)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { datos.alternaFavorita(r) } label: {
                                Label("Quitar de favoritas", systemImage: "star.slash")
                            }
                        }
                }
            } header: {
                Text("Favoritas · \(datos.cesta.favoritas.count)").estiloEtiqueta().foregroundStyle(Tema.suave)
            } footer: {
                if datos.cesta.favoritas.isEmpty {
                    Text("Las recetas que marques con la estrella se quedan aquí, también sin conexión.")
                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .listSectionSpacing(Tema.Espacio.m)
        .contentMargins(.top, 0, for: .scrollContent)
        .contentMargins(.bottom, 110, for: .scrollContent)
        .refreshable { await datos.carga() }
    }

    private func fila(_ r: RecetaLista) -> some View {
        Button {
            Haptica.shared.toca(.marcar)
            abierta = r
        } label: {
            HStack(alignment: .center, spacing: Tema.Espacio.m) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(r.n).font(Tema.fuente(.texto, peso: .medium)).foregroundStyle(Tema.texto)
                        .multilineTextAlignment(.leading)
                    Text(subtitulo(r)).font(Tema.fuente(.pequeno)).monospacedDigit().foregroundStyle(Tema.suave)
                    BarraMacros(macros: r.racion, alto: 3).frame(maxWidth: 120)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(r.completa ? "" : "~")\(Formato.entero(r.racion.kcal))").font(Tema.fuente(.destacado))
                        .monospacedDigit().foregroundStyle(Tema.texto)
                    Text("kcal/ración").font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.suave)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Tema.carta)
        .listRowSeparatorTint(Tema.linea)
        .accessibilityLabel("\(r.n), \(Formato.entero(r.racion.kcal)) kilocalorías y \(Formato.entero(r.racion.prot)) gramos de proteína por ración")
        .accessibilityHint("Abre la receta")
    }

    private func subtitulo(_ r: RecetaLista) -> String {
        var t = "\(Formato.entero(r.racion.prot)) g proteína por ración"
        if r.raciones > 1 { t += " · \(r.raciones) raciones" }
        if r.tiempo > 0 { t += " · \(r.tiempo) min" }
        return t
    }
}

// MARK: hazme una receta

/// Elegir ingredientes de la lista (todos los pendientes de partida), una instrucción opcional y las raciones.
/// Cuando Claude contesta, la misma hoja enseña la receta.
struct HojaHazReceta: View {
    @State private var datos = DatosLista.shared
    @State private var elegidos: Set<String> = []
    @State private var instruccion = ""
    @State private var raciones = 1
    @State private var empezado = false
    @Environment(\.dismiss) private var cierra

    private static let ideas = ["Cena ligera", "Alta en proteína", "Rápida, 15 minutos", "Para llevar en táper", "Desayuno"]

    var body: some View {
        Group {
            if let r = datos.recetaNueva, empezado {
                DetalleRecetaLista(receta: r)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                formulario.transition(.opacity)
            }
        }
        .animation(Tema.Muelle.pantalla, value: datos.recetaNueva?.id)
        .presentationBackground(Tema.fondo)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(datos.cocinando)
        .onAppear {
            datos.recetaNueva = nil
            elegidos = Set(datos.items.filter { !$0.hecho }.map(\.id))
        }
    }

    private var formulario: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(datos.items) { i in
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            if elegidos.contains(i.id) { elegidos.remove(i.id) } else { elegidos.insert(i.id) }
                        } label: {
                            HStack(spacing: Tema.Espacio.m) {
                                Image(systemName: elegidos.contains(i.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 21))
                                    .foregroundStyle(elegidos.contains(i.id) ? Tema.acento : Tema.tenue)
                                    .contentTransition(.symbolEffect(.replace))
                                Text(i.n.capitalizadoComida).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                                Spacer()
                                Text(i.cantidadTexto).font(Tema.fuente(.pequeno)).monospacedDigit().foregroundStyle(Tema.suave)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Tema.carta)
                        .accessibilityAddTraits(elegidos.contains(i.id) ? .isSelected : [])
                    }
                } header: {
                    HStack {
                        Text("Con qué · \(elegidos.count)").estiloEtiqueta().foregroundStyle(Tema.suave)
                        Spacer()
                        Button(elegidos.isEmpty ? "Todos" : "Ninguno") {
                            elegidos = elegidos.isEmpty ? Set(datos.items.map(\.id)) : []
                        }
                        .font(Tema.fuente(.pequeno, peso: .medium)).foregroundStyle(Tema.acento)
                    }
                }
                Section {
                    TextField("Algo más (opcional): «cena ligera», «sin horno»…", text: $instruccion, axis: .vertical)
                        .lineLimit(1...3)
                        .font(Tema.fuente(.texto))
                        .listRowBackground(Tema.carta)
                    ScrollView(.horizontal) {
                        HStack(spacing: Tema.Espacio.s) {
                            ForEach(Self.ideas, id: \.self) { idea in
                                Button {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    instruccion = instruccion.isEmpty ? idea.lowercased() : "\(instruccion), \(idea.lowercased())"
                                } label: {
                                    Text(idea).font(Tema.fuente(.pequeno, peso: .medium)).foregroundStyle(Tema.texto)
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(Tema.carta2, in: Capsule())
                                }
                                .buttonStyle(EstiloHundir())
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .listRowBackground(Tema.carta)
                    Stepper(value: $raciones, in: 1...8) {
                        HStack {
                            Text("Raciones").font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                            Spacer()
                            Text("\(raciones)").font(Tema.fuente(.destacado)).monospacedDigit().foregroundStyle(Tema.texto)
                                .contentTransition(.numericText(value: Double(raciones)))
                        }
                    }
                    .listRowBackground(Tema.carta)
                    .animation(Tema.Muelle.toque, value: raciones)
                } header: {
                    Text("Cómo la quieres").estiloEtiqueta().foregroundStyle(Tema.suave)
                } footer: {
                    if let e = datos.errorReceta {
                        Text(e).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro)
                    } else if datos.cocinando {
                        Text("Claude está pensando la receta. Suele tardar unos 20 segundos.")
                            .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Tema.fondo.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { boton }
            .navigationTitle("Hazme una receta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { cierra() }.foregroundStyle(Tema.suave).disabled(datos.cocinando)
                }
            }
        }
    }

    private var boton: some View {
        Button {
            Haptica.shared.toca(.marcar)
            empezado = true
            let ids = datos.items.map(\.id).filter { elegidos.contains($0) }
            Task { _ = await datos.hazReceta(con: ids, instruccion: instruccion, raciones: raciones) }
        } label: {
            HStack(spacing: Tema.Espacio.s) {
                if datos.cocinando { ProgressView().tint(Tema.acentoTexto) } else { Image(systemName: "sparkles") }
                Text(datos.cocinando ? "Cocinando la idea…" : "Proponer receta")
            }
            .font(Tema.fuente(.destacado)).foregroundStyle(Tema.acentoTexto)
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(Tema.acento.opacity(elegidos.isEmpty || datos.cocinando ? 0.5 : 1),
                        in: RoundedRectangle(cornerRadius: Tema.Radio.boton, style: .continuous))
        }
        .buttonStyle(EstiloHundir())
        .disabled(elegidos.isEmpty || datos.cocinando)
        .padding(.horizontal, Tema.Espacio.l)
        .padding(.vertical, Tema.Espacio.s)
        .background(Tema.fondo.opacity(0.95))
        .animation(Tema.Muelle.pantalla, value: datos.cocinando)
    }
}

// MARK: una receta

/// La receta: macros totales y por ración, ingredientes (lo extra marcado), pasos y la estrella de favorita.
struct DetalleRecetaLista: View {
    let receta: RecetaLista
    @State private var datos = DatosLista.shared
    @State private var porRacion = true
    @Environment(\.dismiss) private var cierra

    private var m: Macros { porRacion ? receta.racion : receta.total }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tema.Espacio.l) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(etiqueta).estiloEtiqueta().foregroundStyle(Tema.suave)
                        Text(receta.n).font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button {
                        datos.alternaFavorita(receta)
                    } label: {
                        Image(systemName: datos.esFavorita(receta) ? "star.fill" : "star")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(datos.esFavorita(receta) ? Tema.aviso : Tema.suave)
                            .frame(width: 40, height: 40).background(Tema.carta, in: Circle())
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .accessibilityLabel(datos.esFavorita(receta) ? "Quitar de favoritas" : "Guardar en favoritas")
                    Button("Listo") { cierra() }
                        .font(Tema.fuente(.destacado)).foregroundStyle(Tema.acento)
                        .frame(height: 40)
                }
                macros
                if !receta.nota.isEmpty {
                    Text(receta.nota).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ingredientes
                if !receta.pasos.isEmpty { pasos }
            }
            .padding(Tema.Espacio.l)
        }
        .background(Tema.fondo.ignoresSafeArea())
        .presentationBackground(Tema.fondo)
        .presentationDragIndicator(.visible)
    }

    private var etiqueta: String {
        var t = receta.raciones == 1 ? "1 ración" : "\(receta.raciones) raciones"
        if receta.tiempo > 0 { t += " · \(receta.tiempo) min" }
        return t
    }

    private var macros: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            if receta.raciones > 1 {
                Picker("Ver", selection: $porRacion) {
                    Text("Por ración").tag(true)
                    Text("Total").tag(false)
                }
                .pickerStyle(.segmented)
            }
            HStack(spacing: 0) {
                cifra("kcal", m.kcal, "", Tema.texto)
                cifra("Proteína", m.prot, "g", ColorMacro.prot)
                cifra("Hidratos", m.hc, "g", ColorMacro.hc)
                cifra("Grasa", m.grasa, "g", ColorMacro.grasa)
            }
            BarraMacros(macros: m)
            HStack(spacing: Tema.Espacio.m) {
                LeyendaMacro(nombre: "P", gramos: m.prot, color: ColorMacro.prot)
                LeyendaMacro(nombre: "H", gramos: m.hc, color: ColorMacro.hc)
                LeyendaMacro(nombre: "G", gramos: m.grasa, color: ColorMacro.grasa)
            }
            if let o = datos.cesta.objetivo, o.kcal > 0 {
                Text("Es el \(Int((receta.racion.kcal / o.kcal * 100).rounded())) % de tus kcal del día y el \(Int((receta.racion.prot / max(o.proteina, 1) * 100).rounded())) % de la proteína (por ración).")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            }
            if !receta.completa {
                Text("Cifras aproximadas: a algún ingrediente le faltan datos.")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.aviso)
            }
        }
        .carta()
        .animation(Tema.Muelle.pantalla, value: porRacion)
    }

    private func cifra(_ titulo: String, _ valor: Double, _ unidad: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titulo).estiloEtiqueta().foregroundStyle(Tema.suave)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(Formato.entero(valor)).font(Tema.fuente(.cifra)).monospacedDigit().foregroundStyle(color)
                    .contentTransition(.numericText(value: valor))
                if !unidad.isEmpty { Text(unidad).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var ingredientes: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            Text("Ingredientes").font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
            ForEach(Array(receta.ing.enumerated()), id: \.offset) { _, l in
                HStack(alignment: .firstTextBaseline, spacing: Tema.Espacio.s) {
                    Text(l.n.capitalizadoComida).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                    if l.extra {
                        Text("extra").font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.suave)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Tema.carta2, in: Capsule())
                    }
                    Spacer()
                    Text(Formato.cantidad(l.c, l.u)).font(Tema.fuente(.texto)).monospacedDigit().foregroundStyle(Tema.suave)
                    Text(l.completa ? "\(Formato.entero(l.kcal)) kcal" : "—")
                        .font(Tema.fuente(.pequeno)).monospacedDigit().foregroundStyle(Tema.tenue)
                        .frame(minWidth: 62, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .carta()
    }

    private var pasos: some View {
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
                .accessibilityElement(children: .combine)
            }
        }
        .carta()
    }
}
