import SwiftUI

// El editor de ingredientes de la web (Cuentas → Ingredientes): buscar, crear, corregir los macros por 100 g, la unidad
// de compra, los gramos por unidad y la fuente; «Rellenar» propone valores de Open Food Facts (se revisan antes de
// guardar), y cada ingrediente tiene sus variantes (cocidas, de bote…) con «Predeterminada» y «Borrar». Guarda con
// POST /api/comida/ingrediente y /variante: sin red se quedan en la cola y salen al volver.

struct HojaIngredientes: View {
    @Environment(\.dismiss) private var cierra
    @State private var datos = DatosComida.shared
    @State private var busca = ""
    @State private var nuevo: NombreNuevo?

    private var lista: [EstadoComida.Ingrediente] {
        let q = busca.trimmingCharacters(in: .whitespaces).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
        return (datos.estado?.ingredientes ?? []).filter {
            q.isEmpty || $0.n.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES")).contains(q)
        }
        .sorted { $0.n.localizedCaseInsensitiveCompare($1.n) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                let l = lista
                if l.isEmpty {
                    Text(busca.isEmpty ? "Sin ingredientes todavía." : "Nada con ese nombre. «Añadir» lo crea.")
                        .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave).listRowBackground(Tema.carta)
                }
                ForEach(l) { i in
                    NavigationLink {
                        FichaIngrediente(id: i.id, nombreNuevo: "")
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(i.n).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                            Text(i.n100?.texto ?? "Sin datos nutricionales")
                                .font(Tema.fuente(.pequeno)).monospacedDigit()
                                .foregroundStyle(i.n100 == nil ? Tema.aviso : Tema.suave)
                            if !i.fuente.isEmpty || i.gUd != nil || !i.variantes.isEmpty {
                                Text([i.fuente, i.gUd.map { "\(FichaNum.texto($0)) g/ud" } ?? "",
                                      i.variantes.isEmpty ? "" : "\(i.variantes.count) variante\(i.variantes.count == 1 ? "" : "s")"]
                                    .filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.tenue)
                            }
                        }
                    }
                    .listRowBackground(Tema.carta)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Tema.fondo.ignoresSafeArea())
            .searchable(text: $busca, prompt: "Buscar o añadir (nombre)")
            .navigationTitle("Ingredientes")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $nuevo) { n in FichaIngrediente(id: nil, nombreNuevo: n.id) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { cierra() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { nuevo = NombreNuevo(id: busca.trimmingCharacters(in: .whitespaces)) } label: {
                        Label("Añadir", systemImage: "plus")
                    }
                }
            }
            .refreshable { await datos.carga() }
            .tint(Tema.acento)
        }
        .presentationBackground(Tema.fondo)
        .presentationDragIndicator(.visible)
    }
}

private struct NombreNuevo: Identifiable, Hashable { let id: String }

enum FichaNum {
    /// 12 → «12», 12.5 → «12,5».
    static func texto(_ x: Double) -> String {
        x == x.rounded() ? String(Int(x)) : String(format: "%g", x).replacingOccurrences(of: ".", with: ",")
    }

    static func campo(_ x: Double?) -> String { x.map { texto($0) } ?? "" }

    /// Lo que se manda como g_ud: vacío lo borra.
    static func gramos(_ t: String) -> Any {
        let limpio = t.trimmingCharacters(in: .whitespaces)
        if limpio.isEmpty { return "" }
        if let x = Eur.lee(limpio) { return x }
        return limpio
    }
}

/// Los campos de nutrición, comunes al ingrediente y a sus variantes.
private struct CamposNutricion: View {
    @Binding var kcal: String
    @Binding var prot: String
    @Binding var hc: String
    @Binding var grasa: String
    @Binding var fibra: String
    @Binding var gUd: String

    var body: some View {
        campo("Calorías", "kcal", $kcal)
        campo("Proteína", "g", $prot)
        campo("Hidratos", "g", $hc)
        campo("Grasa", "g", $grasa)
        campo("Fibra (opcional)", "g", $fibra)
        campo("Gramos por unidad", "g/ud", $gUd)
    }

    private func campo(_ titulo: String, _ unidad: String, _ texto: Binding<String>) -> some View {
        HStack {
            Text(titulo)
            Spacer()
            TextField("—", text: texto)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).monospacedDigit()
                .frame(maxWidth: 110)
            Text(unidad).foregroundStyle(Tema.suave).frame(width: 36, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// «Rellenar»: lo que tiene Open Food Facts con ese nombre; tocar uno copia sus valores (se revisan antes de guardar).
private struct Rellenar: View {
    let nombre: String
    let elige: (PropuestaNutricion) -> Void
    @State private var datos = DatosComida.shared
    @State private var propuestas: [PropuestaNutricion] = []
    @State private var buscando = false
    @State private var nota: String?

    var body: some View {
        Section {
            Button {
                busca()
            } label: {
                HStack {
                    Label("Rellenar con Open Food Facts", systemImage: "wand.and.stars")
                    if buscando { Spacer(); ProgressView() }
                }
            }
            .disabled(nombre.trimmingCharacters(in: .whitespaces).isEmpty || buscando)
            ForEach(propuestas) { p in
                Button {
                    Haptica.shared.toca(.marcar)
                    elige(p)
                    propuestas = []
                    nota = "Rellenado desde «\(p.n)». Revísalo antes de guardar."
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.n).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                        Text([p.marca ?? "", "\(Int((p.n100.kcal ?? 0).rounded())) kcal",
                              "P \(FichaNum.campo(p.n100.prot))", "HC \(FichaNum.campo(p.n100.hc))", "G \(FichaNum.campo(p.n100.grasa))"]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                    }
                }
            }
        } footer: {
            Text(nota ?? "Valores por 100 g en crudo. Las recetas cuentan g, ml (como g) o unidades × gramos por unidad. Lo de Open Food Facts lo pone la gente: revísalo.")
        }
    }

    private func busca() {
        buscando = true
        nota = "Buscando en Open Food Facts…"
        Task {
            defer { buscando = false }
            do {
                propuestas = try await datos.rellena(nombre)
                nota = propuestas.isEmpty ? "Open Food Facts no tiene nada con ese nombre: escríbelos a mano."
                    : "Toca el que más se parezca; luego revisa y guarda."
            } catch {
                nota = "No ha podido buscar (hace falta conexión): \(DatosGastos.mensaje(error))"
            }
        }
    }
}

/// Lo que se manda de nutrición: nada si no se ha escrito ninguno; si hay alguno, los cuatro (fibra opcional).
private func cuerpoNutricion(kcal: String, prot: String, hc: String, grasa: String, fibra: String,
                             obligatorio: Bool) throws -> [String: Any] {
    let valores = [("kcal", kcal), ("prot", prot), ("hc", hc), ("grasa", grasa)]
    let alguno = valores.contains { !$0.1.trimmingCharacters(in: .whitespaces).isEmpty } || !fibra.trimmingCharacters(in: .whitespaces).isEmpty
    guard alguno || obligatorio else { return [:] }
    var c: [String: Any] = [:]
    for (k, t) in valores {
        guard let x = Eur.lee(t.trimmingCharacters(in: .whitespaces)), x >= 0 else {
            throw APIError(mensaje: "Faltan los cuatro valores por 100 g: calorías, proteína, hidratos y grasa.")
        }
        c[k] = x
    }
    let f = fibra.trimmingCharacters(in: .whitespaces)
    if let x = Eur.lee(f), !f.isEmpty { c["fibra"] = x } else { c["fibra"] = NSNull() }
    return c
}

// MARK: un ingrediente

struct FichaIngrediente: View {
    /// nil = nuevo (con `nombreNuevo`).
    let id: String?
    @Environment(\.dismiss) private var vuelve
    @State private var datos = DatosComida.shared
    @State private var n: String
    @State private var vn = ""
    @State private var unidad = "kg"
    @State private var kcal = ""
    @State private var prot = ""
    @State private var hc = ""
    @State private var grasa = ""
    @State private var fibra = ""
    @State private var gUd = ""
    @State private var fuente = ""
    @State private var trabajando = false
    @State private var error: String?
    @State private var cargado = false

    init(id: String?, nombreNuevo: String) {
        self.id = id
        _n = State(initialValue: nombreNuevo)
    }

    private var ing: EstadoComida.Ingrediente? { id.flatMap { datos.estado?.ingrediente($0) } }

    var body: some View {
        Form {
            Section {
                TextField("Nombre", text: $n)
                TextField("Forma por defecto (secas, crudo…)", text: $vn)
                Picker("Se compra en", selection: $unidad) {
                    Text("kg").tag("kg")
                    Text("l").tag("l")
                    Text("ud").tag("ud")
                }
            }
            Section {
                CamposNutricion(kcal: $kcal, prot: $prot, hc: $hc, grasa: $grasa, fibra: $fibra, gUd: $gUd)
                TextField("Fuente: BEDCA, etiqueta…", text: $fuente)
            } header: {
                Text("Por 100 g en crudo")
            }
            Rellenar(nombre: n) { p in
                kcal = FichaNum.campo(p.n100.kcal); prot = FichaNum.campo(p.n100.prot); hc = FichaNum.campo(p.n100.hc)
                grasa = FichaNum.campo(p.n100.grasa); fibra = FichaNum.campo(p.n100.fibra); fuente = p.fuente
            }
            if let ing {
                Section {
                    ForEach(ing.variantes) { v in
                        NavigationLink {
                            FichaVariante(ing: ing.id, variante: v.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(v.n).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                                Text(v.n100?.texto ?? "Sin datos").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                            }
                        }
                    }
                    if ing.variantes.count < 8 {
                        NavigationLink {
                            FichaVariante(ing: ing.id, variante: nil)
                        } label: {
                            Label("Añadir variante", systemImage: "plus")
                        }
                    }
                } header: {
                    Text("Otras formas")
                } footer: {
                    Text("Cocidas, de bote…: se eligen en cada receta. No cambian lo que se compra.")
                }
            }
            if let error {
                Text(error).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro)
            }
        }
        .font(Tema.fuente(.texto))
        .scrollContentBackground(.hidden)
        .background(Tema.fondo.ignoresSafeArea())
        .navigationTitle(id == nil ? "Nuevo ingrediente" : (ing?.n ?? "Ingrediente"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { guarda() } label: {
                    if trabajando { ProgressView() } else { Text("Guardar").fontWeight(.semibold) }
                }
                .disabled(n.trimmingCharacters(in: .whitespaces).isEmpty || trabajando)
            }
        }
        .onAppear(perform: rellenaCampos)
    }

    private func rellenaCampos() {
        guard !cargado, let i = ing else { return }
        cargado = true
        n = i.n; vn = i.vn; unidad = i.unidad; fuente = i.fuente; gUd = FichaNum.campo(i.gUd)
        if let x = i.n100 {
            kcal = FichaNum.texto(x.kcal); prot = FichaNum.texto(x.prot); hc = FichaNum.texto(x.hc)
            grasa = FichaNum.texto(x.grasa); fibra = FichaNum.campo(x.fibra)
        }
    }

    private func guarda() {
        trabajando = true
        error = nil
        Task {
            defer { trabajando = false }
            do {
                var c = try cuerpoNutricion(kcal: kcal, prot: prot, hc: hc, grasa: grasa, fibra: fibra, obligatorio: false)
                c["n"] = n.trimmingCharacters(in: .whitespaces)
                c["unidad"] = unidad
                c["vn"] = vn.trimmingCharacters(in: .whitespaces)
                c["fuente"] = fuente.trimmingCharacters(in: .whitespaces)
                c["g_ud"] = FichaNum.gramos(gUd)
                if let id { c["id"] = id }
                Haptica.shared.toca(.marcar)
                if let aviso = try await datos.guarda("ingrediente", c) { error = aviso } else { vuelve() }
            } catch {
                Haptica.shared.toca(.error)
                self.error = "No se guarda: \(DatosGastos.mensaje(error))"
            }
        }
    }
}

// MARK: una variante

private struct FichaVariante: View {
    let ing: String
    /// nil = nueva.
    let variante: String?
    @Environment(\.dismiss) private var vuelve
    @State private var datos = DatosComida.shared
    @State private var n = ""
    @State private var kcal = ""
    @State private var prot = ""
    @State private var hc = ""
    @State private var grasa = ""
    @State private var fibra = ""
    @State private var gUd = ""
    @State private var fuente = ""
    @State private var trabajando = false
    @State private var error: String?
    @State private var cargado = false
    @State private var confirmaBorrar = false

    private var ingrediente: EstadoComida.Ingrediente? { datos.estado?.ingrediente(ing) }
    private var v: EstadoComida.Ingrediente.Variante? { variante.flatMap { id in ingrediente?.variantes.first { $0.id == id } } }

    var body: some View {
        Form {
            Section {
                TextField("Nombre: cocidas, de bote…", text: $n)
            } header: {
                Text("Variante de \(ingrediente?.n ?? ing)")
            }
            Section {
                CamposNutricion(kcal: $kcal, prot: $prot, hc: $hc, grasa: $grasa, fibra: $fibra, gUd: $gUd)
                TextField("Fuente", text: $fuente)
            } header: {
                Text("Por 100 g")
            } footer: {
                Text("Sin gramos por unidad, usa los de la forma por defecto.")
            }
            // se busca con el ingrediente delante: «garbanzos» + «de bote»
            Rellenar(nombre: "\(ingrediente?.n ?? "") \(n)".trimmingCharacters(in: .whitespaces)) { p in
                kcal = FichaNum.campo(p.n100.kcal); prot = FichaNum.campo(p.n100.prot); hc = FichaNum.campo(p.n100.hc)
                grasa = FichaNum.campo(p.n100.grasa); fibra = FichaNum.campo(p.n100.fibra); fuente = p.fuente
            }
            if variante != nil {
                Section {
                    Button("Hacerla la predeterminada") { manda(["defecto": true], "Ahora es la predeterminada.") }
                    Button("Borrar variante", role: .destructive) { confirmaBorrar = true }
                } footer: {
                    Text("Al hacerla predeterminada, las recetas se reescriben para que no cambien de valor. Al borrarla, las que la usaban pasan a la de por defecto.")
                }
            }
            if let error {
                Text(error).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro)
            }
        }
        .font(Tema.fuente(.texto))
        .scrollContentBackground(.hidden)
        .background(Tema.fondo.ignoresSafeArea())
        .navigationTitle(variante == nil ? "Nueva variante" : (v?.n ?? "Variante"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { guarda() } label: {
                    if trabajando { ProgressView() } else { Text("Guardar").fontWeight(.semibold) }
                }
                .disabled(n.trimmingCharacters(in: .whitespaces).isEmpty || trabajando)
            }
        }
        .confirmationDialog("¿Borrar la variante «\(v?.n ?? "")»?", isPresented: $confirmaBorrar, titleVisibility: .visible) {
            Button("Borrar", role: .destructive) { manda(["borrar": true], "Variante borrada.") }
            Button("Mejor no", role: .cancel) {}
        }
        .onAppear {
            guard !cargado, let v else { return }
            cargado = true
            n = v.n; fuente = v.fuente; gUd = FichaNum.campo(v.gUd)
            if let x = v.n100 {
                kcal = FichaNum.texto(x.kcal); prot = FichaNum.texto(x.prot); hc = FichaNum.texto(x.hc)
                grasa = FichaNum.texto(x.grasa); fibra = FichaNum.campo(x.fibra)
            }
        }
    }

    private func guarda() {
        do {
            var c = try cuerpoNutricion(kcal: kcal, prot: prot, hc: hc, grasa: grasa, fibra: fibra, obligatorio: variante == nil)
            c["n"] = n.trimmingCharacters(in: .whitespaces)
            c["fuente"] = fuente.trimmingCharacters(in: .whitespaces)
            c["g_ud"] = FichaNum.gramos(gUd)
            manda(c, nil)
        } catch {
            Haptica.shared.toca(.error)
            self.error = DatosGastos.mensaje(error)
        }
    }

    private func manda(_ extra: [String: Any], _ texto: String?) {
        trabajando = true
        error = nil
        var c = extra
        c["id"] = ing
        if let variante { c["v"] = variante }
        Task {
            defer { trabajando = false }
            do {
                Haptica.shared.toca(.marcar)
                if let aviso = try await datos.guarda("variante", c) { error = aviso } else { vuelve() }
            } catch {
                Haptica.shared.toca(.error)
                self.error = "No se guarda: \(DatosGastos.mensaje(error))"
            }
        }
    }
}
