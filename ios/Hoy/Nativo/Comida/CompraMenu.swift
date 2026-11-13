import SwiftUI

// La lista de la compra del menú y sus cuentas (lo que en la web son las pestañas «Lista» y «Cuentas»): cada ingrediente
// con cuánto hace falta y dónde sale más barato, tacharlo al meterlo en el carro, lo que cuesta la semana frente al
// presupuesto y por qué cadena pasas (apagar una recalcula, como la web; se guarda en este iPhone). Tachar es un PUT
// del estado de comida con su `tachado`, por la cola: sin red se ve ya y Sincro lo junta con lo del servidor al volver.

private struct ListaCompra: Decodable {
    var filas: [Fila] = []
    var sinPrecio: [String] = []

    enum CodingKeys: String, CodingKey {
        case filas
        case sinPrecio = "sin_precio"
    }

    struct Fila: Decodable, Identifiable {
        var id: String
        var n: String
        var unidad: String
        var cantidad: Double
        var opciones: [String: Opcion]
        var tachado: Bool
        var pagado: Pagado?
    }

    struct Opcion: Decodable {
        var nombre: String
        var coste: Double
        var paquetes: Int
        var descuento: Double?
        var dudoso: Bool?
    }

    struct Pagado: Decodable {
        var dia: String
        var comercio: String
        var importe: Double
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        filas = (try? c.decodeIfPresent([Fila].self, forKey: .filas)) ?? []
        sinPrecio = (try? c.decodeIfPresent([String].self, forKey: .sinPrecio)) ?? []
    }
}

struct HojaCompraMenu: View {
    @Environment(\.dismiss) private var cierra
    @State private var lista: ListaCompra?
    @State private var cadenas: [String] = []
    @State private var presupuesto = 0.0
    @State private var tachado: [String: Bool] = [:]
    @State private var copia: Date?
    @State private var error: String?
    @State private var aviso: String?
    @State private var apagadas: Set<String> = Set(Almacen.defaults.stringArray(forKey: "comida.apagadas") ?? [])
    @State private var vista = 0
    /// Los productos fijados a mano (ingrediente → cadena → pid), del estado de comida.
    @State private var pines: [String: [String: String]] = [:]
    @State private var producto: ProductoAElegir?

    private var vivas: [String] { cadenas.filter { !apagadas.contains($0) } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Vista", selection: $vista) {
                        Text("Lista").tag(0)
                        Text("Cuentas").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                if let copia {
                    Text(API.notaCopia(copia)).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.aviso).listRowBackground(Tema.carta)
                }
                if let lista {
                    if vista == 0 { filas(lista) } else { cuentas(lista) }
                } else if let error {
                    Text(error).font(Tema.fuente(.texto)).foregroundStyle(Tema.peligro).listRowBackground(Tema.carta)
                } else {
                    Text("Cargando…").font(Tema.fuente(.texto)).foregroundStyle(Tema.suave).listRowBackground(Tema.carta)
                }
                if let aviso {
                    Text(aviso).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).listRowBackground(Tema.carta)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Tema.fondo.ignoresSafeArea())
            .navigationTitle("Lista de la compra")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { cierra() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Refrescar precios", systemImage: "arrow.clockwise") { refrescaPrecios() }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Más")
                }
            }
            .refreshable { await carga() }
            .task { await carga() }
            .tint(Tema.acento)
            .animation(Tema.Muelle.pantalla, value: vista)
        }
        .presentationBackground(Tema.fondo)
        .presentationDragIndicator(.visible)
        .sheet(item: $producto, onDismiss: { Task { await carga() } }) { p in
            HojaProducto(elegir: p, fijado: pines[p.ing]?[p.cadena] ?? "")
        }
    }

    // MARK: lista

    @ViewBuilder private func filas(_ l: ListaCompra) -> some View {
        let hechos = l.filas.filter { estaTachado($0) }.count
        Section {
            if l.filas.isEmpty {
                Text("Sin lista: genera un menú primero.").font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                    .listRowBackground(Tema.carta)
            }
            ForEach(l.filas) { f in fila(f).listRowBackground(Tema.carta) }
        } header: {
            Text(l.filas.isEmpty ? "" : "\(hechos) de \(l.filas.count) en el carro")
        } footer: {
            if !l.sinPrecio.isEmpty { Text("Sin precio en ninguna cadena: \(l.sinPrecio.joined(separator: ", ")).") }
        }
    }

    private func fila(_ f: ListaCompra.Fila) -> some View {
        let hecho = estaTachado(f)
        let gana = vivas.compactMap { c in f.opciones[c].map { (c, $0) } }.min { $0.1.coste < $1.1.coste }
        return Button {
            tacha(f, !hecho)
        } label: {
            HStack(alignment: .top, spacing: Tema.Espacio.m) {
                Image(systemName: hecho ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20)).foregroundStyle(hecho ? Tema.acento : Tema.tenue)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(f.n).font(Tema.fuente(.texto, peso: .medium)).foregroundStyle(Tema.texto)
                            .strikethrough(hecho, color: Tema.suave)
                        if !(pines[f.id] ?? [:]).isEmpty {
                            Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(Tema.acento)
                                .accessibilityLabel("Con producto fijado")
                        }
                    }
                    Text("Necesitas \(cantidad(f.cantidad, f.unidad))").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                    if let g = gana {
                        let cadena = g.0, o = g.1
                        Text("\(o.paquetes)× \(o.nombre) · \(cadena.capitalized)" + ((o.descuento ?? 0) >= 8 ? " · −\(Int(o.descuento ?? 0)) %" : "")
                             + ((o.dudoso ?? false) ? " · ?" : ""))
                            .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).lineLimit(2)
                    }
                    if let p = f.pagado {
                        Text("Pagaste \(eur(p.importe)) en \(p.comercio) · \(p.dia.suffix(2))/\(p.dia.dropFirst(5).prefix(2))")
                            .font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.tenue)
                    }
                }
                Spacer()
                if let g = gana {
                    Text(eur(g.1.coste)).font(Tema.fuente(.texto)).monospacedDigit().foregroundStyle(hecho ? Tema.tenue : Tema.texto)
                }
            }
            .opacity(hecho ? 0.6 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(hecho ? "En el carro" : "Por comprar")
        .accessibilityHint(hecho ? "Toca para sacarlo del carro" : "Toca para tacharlo")
        .contextMenu {
            // la web: tocar el precio de una cadena para fijar a mano el producto bueno
            ForEach(cadenas, id: \.self) { c in
                Button("Elegir el producto en \(c.capitalized)", systemImage: pines[f.id]?[c] != nil ? "pin.fill" : "pin") {
                    producto = ProductoAElegir(ing: f.id, nombre: f.n, cadena: c)
                }
            }
        }
    }

    // MARK: cuentas

    @ViewBuilder private func cuentas(_ l: ListaCompra) -> some View {
        // todo sale de las mismas filas, como la web: el reparto, lo de cada cadena y lo que le falta
        let c = calcula(l)
        Section {
            HStack {
                Text("Compra de la semana").font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                Spacer()
                Text(eur(c.reparto)).font(Tema.fuente(.cifra)).monospacedDigit()
                    .foregroundStyle(presupuesto > 0 && c.reparto > presupuesto ? Tema.peligro : Tema.texto)
                    .contentTransition(.numericText(value: c.reparto))
            }
            .listRowBackground(Tema.carta)
            if presupuesto > 0 {
                HStack {
                    Text("Presupuesto").foregroundStyle(Tema.suave)
                    Spacer()
                    Text(eur(presupuesto)).monospacedDigit().foregroundStyle(Tema.texto)
                }
                .font(Tema.fuente(.texto))
                .listRowBackground(Tema.carta)
            }
        }
        Section {
            ForEach(cadenas, id: \.self) { cadena in
                let apagada = apagadas.contains(cadena)
                Toggle(isOn: Binding(get: { !apagada }, set: { pon(cadena, viva: $0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(cadena.capitalized).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                            Spacer()
                            Text(c.porCadena[cadena].map { eur($0) } ?? "—").font(Tema.fuente(.texto)).monospacedDigit().foregroundStyle(Tema.texto)
                        }
                        Text(apagada ? "apagada" : (c.faltan[cadena] ?? 0) > 0 ? "le faltan \(c.faltan[cadena] ?? 0)"
                             : (c.solo[cadena] ?? 0) > 0 ? "solo aquí \(eur(c.solo[cadena] ?? 0))" : "")
                            .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                    }
                }
                .listRowBackground(Tema.carta)
            }
        } header: {
            Text("Por dónde pasas")
        } footer: {
            Text(c.masBarato > 0 && c.reparto > 0
                 ? "Pasando por todas ahorras \(eur(c.masBarato - c.reparto)) sobre comprarlo todo en la más barata."
                 : "Ninguna cadena tiene la lista entera.")
        }
    }

    private struct Cuentas {
        var reparto = 0.0
        var porCadena: [String: Double] = [:]
        var solo: [String: Double] = [:]
        var faltan: [String: Int] = [:]
        var masBarato = 0.0
    }

    private func calcula(_ l: ListaCompra) -> Cuentas {
        var c = Cuentas()
        for v in vivas { c.solo[v] = 0; c.faltan[v] = 0 }
        for f in l.filas {
            var gana: String?
            var mejor = Double.infinity
            for v in vivas {
                if let o = f.opciones[v] {
                    c.solo[v, default: 0] += o.coste
                    if o.coste < mejor { mejor = o.coste; gana = v }
                } else {
                    c.faltan[v, default: 0] += 1
                }
            }
            if let gana { c.reparto += mejor; c.porCadena[gana, default: 0] += mejor }
        }
        // solo vale como alternativa la cadena que tiene TODA la lista
        let completas = vivas.filter { (c.solo[$0] ?? 0) > 0 && (c.faltan[$0] ?? 0) == 0 }
        c.masBarato = completas.map { c.solo[$0] ?? 0 }.min() ?? 0
        return c
    }

    // MARK: acciones

    private func estaTachado(_ f: ListaCompra.Fila) -> Bool { tachado[f.id] ?? f.tachado }

    private func pon(_ cadena: String, viva: Bool) {
        Haptica.shared.toca(.marcar)
        if viva { apagadas.remove(cadena) } else { apagadas.insert(cadena) }
        Almacen.defaults.set(Array(apagadas), forKey: "comida.apagadas")
    }

    private func carga() async {
        do {
            let (d, fecha) = try await API.leeOCopia("/api/comida/lista")
            let l = try JSONDecoder().decode(ListaCompra.self, from: d)
            if let r = try? await API.leeOCopia("/api/comida/estado"),
               let o = try? JSONSerialization.jsonObject(with: r.datos) as? [String: Any] {
                cadenas = (o["cadenas"] as? [String]) ?? cadenas
                presupuesto = ((o["perfil"] as? [String: Any])?["presupuesto"] as? NSNumber)?.doubleValue ?? 0
                // lo tachado sin red aún no está en la lista del servidor: manda la copia del estado
                let t = (o["tachado"] as? [String: Any]) ?? [:]
                tachado = Dictionary(uniqueKeysWithValues: l.filas.map { ($0.id, (t[$0.id] as? Bool) ?? false) })
                var p: [String: [String: String]] = [:]
                for i in (o["ingredientes"] as? [[String: Any]]) ?? [] {
                    if let id = i["id"] as? String, let pin = i["pin"] as? [String: String], !pin.isEmpty { p[id] = pin }
                }
                pines = p
            }
            if cadenas.isEmpty { cadenas = Array(Set(l.filas.flatMap { $0.opciones.keys })).sorted() }
            withAnimation(Tema.Muelle.pantalla) { lista = l }
            copia = fecha
            error = nil
        } catch {
            self.error = "No he podido leer la lista de la compra: \(error.localizedDescription)"
        }
    }

    private func tacha(_ f: ListaCompra.Fila, _ si: Bool) {
        Haptica.shared.toca(si ? .marcar : .desmarcar)
        withAnimation(Tema.Muelle.toque) { tachado[f.id] = si }
        if let l = lista, !l.filas.isEmpty, l.filas.allSatisfy({ estaTachado($0) }) { aviso = "Compra hecha: todo en el carro." }
        Task {
            do {
                if try await DatosComida.shared.tacha(f.id, si) { aviso = API.avisoEncolado + "." }
            } catch {
                Haptica.shared.toca(.error)
                withAnimation(Tema.Muelle.toque) { tachado[f.id] = !si }
                aviso = "No se ha guardado: \(DatosGastos.mensaje(error))"
            }
        }
    }

    private func refrescaPrecios() {
        Task {
            do {
                let d = try await API.datos("/api/comida/precios", metodo: "POST", json: [String: Any]())
                let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
                aviso = (o?["ok"] as? Bool) == true
                    ? "Refrescando precios por detrás: tarda unos minutos. Tira para recargar luego."
                    : "Ya hay un refresco de precios en marcha."
            } catch {
                aviso = "No he podido pedir el refresco de precios: \(error.localizedDescription)"
            }
        }
    }

    private func eur(_ x: Double) -> String { String(format: "%.2f", x).replacingOccurrences(of: ".", with: ",") + "\u{00A0}€" }

    private func cantidad(_ c: Double, _ unidad: String) -> String {
        switch unidad {
        case "ud": return String(format: "%g ud", (c * 10).rounded() / 10).replacingOccurrences(of: ".", with: ",")
        case "l": return c >= 1000 ? String(format: "%.1f l", c / 1000).replacingOccurrences(of: ".", with: ",") : "\(Int(c)) ml"
        default: return c >= 1000 ? String(format: "%.1f kg", c / 1000).replacingOccurrences(of: ".", with: ",") : "\(Int(c)) g"
        }
    }
}


// MARK: fijar el producto de una cadena

struct ProductoAElegir: Identifiable {
    let ing: String
    let nombre: String
    let cadena: String
    var id: String { "\(ing)|\(cadena)" }
}

/// Lo que ha encontrado esa cadena para el ingrediente: tocar uno lo fija (el automático deja de decidir) y
/// «Quitar el pin» lo devuelve al automático. Buscar necesita conexión; fijar va por la cola.
private struct HojaProducto: View {
    let elegir: ProductoAElegir
    @State var fijado: String
    @Environment(\.dismiss) private var cierra
    @State private var productos: [ProductoCadena]?
    @State private var error: String?
    @State private var trabajando = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let productos {
                        if productos.isEmpty {
                            Text("Esta cadena no ha encontrado nada. Prueba a cambiar el término de búsqueda del ingrediente en la web.")
                                .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave).listRowBackground(Tema.carta)
                        }
                        ForEach(productos) { p in
                            Button { fija(p.pid) } label: { fila(p) }.listRowBackground(Tema.carta)
                        }
                    } else if error == nil {
                        HStack { ProgressView(); Text("Buscando…").foregroundStyle(Tema.suave) }.listRowBackground(Tema.carta)
                    }
                } footer: {
                    Text("Toca el producto correcto: queda fijado y el automático deja de decidir.")
                }
                if !fijado.isEmpty {
                    Section {
                        Button("Quitar el pin", role: .destructive) { fija("") }.listRowBackground(Tema.carta)
                    }
                }
                if let error {
                    Text(error).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro).listRowBackground(Tema.carta)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Tema.fondo.ignoresSafeArea())
            .navigationTitle("\(elegir.nombre) · \(elegir.cadena.capitalized)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { cierra() } } }
            .task { await busca() }
            .tint(Tema.acento)
        }
        .presentationBackground(Tema.fondo)
        .presentationDragIndicator(.visible)
    }

    private func fila(_ p: ProductoCadena) -> some View {
        HStack(alignment: .top, spacing: Tema.Espacio.m) {
            Image(systemName: p.pid == fijado ? "pin.fill" : "circle")
                .foregroundStyle(p.pid == fijado ? Tema.acento : Tema.tenue)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.nombre).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                Text([p.categoria ?? "", "envase \(String(format: "%.2f", p.precio).replacingOccurrences(of: ".", with: ",")) €"]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            }
            Spacer()
            Text("\(String(format: "%.2f", p.porUnidad).replacingOccurrences(of: ".", with: ",")) €/\(p.unidad)")
                .font(Tema.fuente(.pequeno, peso: .semibold)).monospacedDigit().foregroundStyle(Tema.texto)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func busca() async {
        do {
            productos = try await DatosComida.shared.candidatos(elegir.ing).filter { $0.cadena == elegir.cadena }
        } catch {
            self.error = "No he podido buscar los productos (hace falta conexión): \(DatosGastos.mensaje(error))"
        }
    }

    private func fija(_ pid: String) {
        guard !trabajando else { return }
        trabajando = true
        Task {
            defer { trabajando = false }
            do {
                try await DatosComida.shared.fija(elegir.ing, cadena: elegir.cadena, pid: pid, nombre: elegir.nombre)
                Haptica.shared.toca(.marcar)
                fijado = pid
                cierra()
            } catch {
                Haptica.shared.toca(.error)
                self.error = DatosGastos.mensaje(error)
            }
        }
    }
}
