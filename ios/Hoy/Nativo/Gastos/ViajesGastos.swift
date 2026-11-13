import SwiftUI

// El bloque «Viajes» de Gastos, como la tarjeta de la web: la hucha (lo que apartas cada ciclo, el plan ciclo a ciclo y
// las sugerencias para repartir un viaje), la lista de viajes con su presupuesto y, al tocar uno, su hoja (desglose,
// cuentas con la pareja, saldar, sus gastos). Crear, cambiar y borrar viajes son operaciones de la cola: sin red también.

struct ViajesGastos: View {
    let r: ResumenGastos
    @State private var datos = DatosGastos.shared
    @State private var editando: ViajeEnEdicion?
    @State private var abierto: ViajeAbierto?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            HStack {
                Text("Viajes").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
                Spacer()
                Button {
                    Haptica.shared.toca(.marcar)
                    editando = ViajeEnEdicion(viaje: nil)
                } label: {
                    Label("Nuevo viaje", systemImage: "plus")
                        .font(Tema.fuente(.pequeno, peso: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Tema.acentoSuave, in: Capsule())
                        .foregroundStyle(Tema.acento)
                }
                .buttonStyle(EstiloHundir())
            }
            HuchaViajes(r: r, error: $error)
            let lista = datos.viajes.sorted { $0.desde > $1.desde }
            if lista.isEmpty {
                Text("Sin viajes. Sus gastos salen aquí y no en el ciclo: las reservas (Booking, vuelos…), lo que nombre el viaje y lo de esos días.")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(lista) { v in fila(v) }
            if let error {
                Text(error).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .carta()
        .animation(Tema.Muelle.pantalla, value: datos.viajes)
        .sheet(item: $editando) { e in EditorViaje(viaje: e.viaje, pareja: r.pareja) }
        .sheet(item: $abierto) { a in HojaViaje(id: a.id) }
    }

    private func fila(_ v: EstadoGastos.Viaje) -> some View {
        let gs = datos.movimientos.filter { $0.viaje == v.id }
        let cu = r.cuentas[v.id]
        let total = cu?.parte ?? gs.reduce(0) { $0 + $1.importe }
        let n = gs.count + (v.con ? (cu?.suyos.count ?? 0) : 0)
        let sub = ["\(FechaGasto.corta(v.desde)) – \(FechaGasto.corta(v.hasta))", "\(n) gasto\(n == 1 ? "" : "s")",
                   v.con && !r.pareja.isEmpty ? "con \(r.pareja) · tu parte" : "",
                   v.moneda != "EUR" ? "en \(MonedaViaje.simbolo(v.moneda))" : ""].filter { !$0.isEmpty }
        return Button {
            Haptica.shared.toca(.marcar)
            abierto = ViajeAbierto(id: v.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: Tema.Espacio.m) {
                    Image(systemName: "airplane").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.acento)
                        .frame(width: 18).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(v.n).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto).lineLimit(1)
                        Text(sub.joined(separator: " · ")).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).lineLimit(1)
                    }
                    Spacer()
                    HStack(spacing: 0) {
                        Text(Eur.texto(total)).foregroundStyle(Tema.texto)
                        if v.presu > 0 { Text(" de \(Eur.entero(v.presu))").foregroundStyle(Tema.suave) }
                    }
                    .font(Tema.fuente(.texto)).monospacedDigit()
                    .contentTransition(.numericText())
                }
                if v.presu > 0 { BarraPresupuesto(valor: total, maximo: v.presu).frame(height: 6).accessibilityHidden(true) }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(EstiloHundir())
        .contextMenu {
            Button("Ver gastos", systemImage: "list.bullet") { abierto = ViajeAbierto(id: v.id) }
            Button("Editar viaje", systemImage: "pencil") { editando = ViajeEnEdicion(viaje: v) }
            Button("Borrar viaje", systemImage: "trash", role: .destructive) {
                Task {
                    do { try await datos.borraViaje(v); Haptica.shared.toca(.desmarcar); error = nil }
                    catch { Haptica.shared.toca(.error); self.error = DatosGastos.mensaje(error) }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Abre sus gastos y sus cuentas")
    }
}

struct ViajeEnEdicion: Identifiable {
    let id = UUID()
    let viaje: EstadoGastos.Viaje?
}

private struct ViajeAbierto: Identifiable { let id: String }

/// Un gasto en la hoja del viaje: tuyo (quien vacío) o de la pareja.
private struct GastoDeViaje: Identifiable {
    let g: Movimiento
    let quien: String
    var id: String { "\(quien)|\(g.id)" }
}

// MARK: la hucha

/// Lo que apartas cada ciclo para viajes: un fijo más del ciclo. Sin hucha, propone repartir lo de los viajes de este
/// ciclo en 3, 4 o 6; con hucha, el saldo y el plan ciclo a ciclo (los que vienen, hasta volver a cero).
private struct HuchaViajes: View {
    let r: ResumenGastos
    @Binding var error: String?
    @State private var datos = DatosGastos.shared
    @State private var texto = ""
    @State private var verPlan = false
    @FocusState private var foco: Bool

    private var periodo: String { r.diaCobro == 1 ? "mes" : "ciclo" }
    private func veces(_ n: Int) -> String { "\(n) \(periodo)\(n == 1 ? "" : periodo == "mes" ? "es" : "s")" }

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            HStack(spacing: Tema.Espacio.s) {
                Text("Apartas para viajes cada \(periodo)").font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                Spacer()
                TextField("0", text: $texto)
                    .keyboardType(.decimalPad)
                    .focused($foco)
                    .multilineTextAlignment(.trailing)
                    .font(Tema.fuente(.texto)).monospacedDigit()
                    .padding(.horizontal, Tema.Espacio.m).padding(.vertical, 8)
                    .frame(width: 100)
                    .background(Tema.carta2, in: RoundedRectangle(cornerRadius: Tema.Radio.boton, style: .continuous))
                    .accessibilityLabel("Lo que apartas para viajes cada \(periodo), en euros")
                Text("€").font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            }
            if let h = r.hucha, datos.ajustes.hucha > 0 {
                Text(h.saldo >= 0 ? "En la hucha: \(Eur.texto(h.saldo))."
                     : "La hucha está en \(Eur.texto(h.saldo)): el viaje se pagó de golpe y te lo ganas en \(veces(h.ciclosACero)) más.")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(h.saldo < 0 ? Tema.peligro : Tema.suave)
                    .fixedSize(horizontal: false, vertical: true)
                if !h.plan.isEmpty {
                    DisclosureGroup(isExpanded: $verPlan) {
                        VStack(spacing: 4) {
                            ForEach(Array(h.plan.enumerated()), id: \.offset) { _, p in paso(p) }
                        }
                        .padding(.top, Tema.Espacio.xs)
                    } label: {
                        Text("\(periodo == "mes" ? "Mes" : "Ciclo") a \(periodo)").font(Tema.fuente(.pequeno, peso: .semibold))
                    }
                    .tint(Tema.acento)
                }
            } else {
                let deuda = datos.viajes.filter { $0.hasta >= r.inicio }.reduce(0) { $0 + (r.cuentas[$1.id]?.parte ?? 0) }
                Text(deuda > 0 ? "Los viajes de este \(periodo) suman \(Eur.texto(deuda)). Para repartirlos, aparta cada \(periodo):"
                     : "Con algo cada \(periodo), los viajes salen de esta hucha y no de tus categorías: se gasta de golpe y los siguientes la rellenan.")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                    .fixedSize(horizontal: false, vertical: true)
                if deuda > 0 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Tema.Espacio.s) {
                            ForEach([3, 4, 6], id: \.self) { n in
                                let x = (deuda / Double(n) / 5).rounded(.up) * 5
                                Button("\(Eur.entero(x)) · \(veces(n))") { pon(x) }
                                    .font(Tema.fuente(.pequeno, peso: .semibold))
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(Tema.carta2, in: Capsule())
                                    .foregroundStyle(Tema.texto)
                                    .buttonStyle(EstiloHundir())
                            }
                        }
                    }
                }
            }
        }
        .padding(.bottom, Tema.Espacio.xs)
        .onAppear { texto = campo(datos.ajustes.hucha) }
        .onChange(of: datos.ajustes.hucha) { _, v in if !foco { texto = campo(v) } }
        .onChange(of: foco) { _, ahora in if !ahora { guarda() } }
    }

    private func campo(_ x: Double) -> String { x > 0 ? Eur.campo(x).replacingOccurrences(of: ",00", with: "") : "" }

    private func paso(_ p: ResumenGastos.Hucha.Paso) -> some View {
        HStack {
            Text("\(FechaViaje.mes(p.fin)) · +\(Eur.entero(p.aparta))" + (p.gastado > 0 ? " · −\(Eur.entero(p.gastado)) en viajes" : ""))
                .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).lineLimit(1)
            Spacer()
            Text((p.futuro && p.saldo >= 0 ? "✓ " : "") + Eur.texto(p.saldo))
                .font(Tema.fuente(.pequeno, peso: .semibold)).monospacedDigit()
                .foregroundStyle(p.saldo < 0 ? Tema.peligro : Tema.texto)
        }
        .opacity(p.futuro ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }

    private func guarda() {
        let nuevo = texto.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : (Eur.lee(texto) ?? datos.ajustes.hucha)
        guard abs(nuevo - datos.ajustes.hucha) > 0.004 else { texto = campo(datos.ajustes.hucha); return }
        pon(max(0, nuevo))
    }

    private func pon(_ x: Double) {
        Task {
            do {
                try await datos.ponAjustes(["hucha": x], resumen: x > 0 ? "Hucha: \(Eur.entero(x)) cada \(periodo)" : "Quitar la hucha de viajes")
                Haptica.shared.toca(.marcar)
                texto = campo(x)
                error = nil
            } catch {
                Haptica.shared.toca(.error)
                texto = campo(datos.ajustes.hucha)
                self.error = DatosGastos.mensaje(error)
            }
        }
    }
}

enum FechaViaje {
    private static let meses: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "LLLL"
        return f
    }()

    /// «Noviembre».
    static func mes(_ dia: String) -> String {
        guard let d = FechaGasto.fecha(dia) else { return dia }
        let t = meses.string(from: d)
        return t.prefix(1).uppercased() + t.dropFirst()
    }
}

// MARK: un viaje abierto

/// La hoja de un viaje: lo gastado por categoría, las cuentas con la pareja (y saldar), y sus gastos. Los tuyos se tocan
/// y se editan; los de la pareja solo se ven (se cambian en su app).
struct HojaViaje: View {
    let id: String
    @Environment(\.dismiss) private var cierra
    @State private var datos = DatosGastos.shared
    @State private var editando: ViajeEnEdicion?
    @State private var gasto: Movimiento?
    @State private var confirmaBorrar = false
    @State private var trabajando = false
    @State private var mensaje: String?
    @State private var fallo = false

    private var r: ResumenGastos? { datos.resumen }
    private var pareja: String { r?.pareja ?? "" }

    var body: some View {
        NavigationStack {
            Group {
                if let v = datos.viaje(id) { contenido(v) } else {
                    Text("Este viaje ya no está.").font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Tema.fondo.ignoresSafeArea())
            .navigationTitle(datos.viaje(id)?.n ?? "Viaje")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { cierra() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Editar") { editando = ViajeEnEdicion(viaje: datos.viaje(id)) }
                        .disabled(datos.viaje(id) == nil)
                }
            }
            .tint(Tema.acento)
        }
        .presentationBackground(Tema.fondo)
        .presentationDragIndicator(.visible)
        .sheet(item: $editando) { e in EditorViaje(viaje: e.viaje, pareja: pareja) }
        .sheet(item: $gasto) { m in EditorMovimiento(movimiento: m) }
    }

    private func contenido(_ v: EstadoGastos.Viaje) -> some View {
        let mios = datos.movimientos.filter { $0.viaje == v.id }
        let cu = r?.cuentas[v.id]
        let compartido = v.con && cu != nil
        let suyos = compartido ? (cu?.suyos ?? []) : []
        let todos = (mios.map { GastoDeViaje(g: $0, quien: "") } + suyos.map { GastoDeViaje(g: $0, quien: pareja) })
            .sorted { $0.g.dia < $1.g.dia }
        let saldar: (Movimiento) -> Bool = { compartido && ["pago", "cobro"].contains($0.reparto) }
        var porCat: [String: Double] = [:]
        for x in todos where !saldar(x.g) { porCat[x.g.cat, default: 0] += x.g.importe }
        let total = cu?.parte ?? mios.reduce(0) { $0 + $1.importe }
        return List {
            Section {
                VStack(alignment: .leading, spacing: Tema.Espacio.s) {
                    Text("\(FechaGasto.corta(v.desde)) – \(FechaGasto.corta(v.hasta))" + (v.moneda != "EUR" ? " · en \(v.moneda)" : ""))
                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(Eur.texto(total)).font(Tema.fuente(.cifra)).monospacedDigit().foregroundStyle(Tema.texto)
                            .contentTransition(.numericText(value: total))
                        if v.presu > 0 { Text("de \(Eur.entero(v.presu))").font(Tema.fuente(.texto)).foregroundStyle(Tema.suave) }
                    }
                    if v.presu > 0 { BarraPresupuesto(valor: total, maximo: v.presu).frame(height: 6).accessibilityHidden(true) }
                    Text(todos.isEmpty ? "Aún sin gastos: se le irán sumando solos."
                         : porCat.sorted { $0.value > $1.value }.map { "\(datos.nombreCat($0.key)) \(Eur.entero($0.value))" }.joined(separator: " · "))
                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(Tema.carta)
            }
            if compartido, let cu {
                Section {
                    Text("Total \(Eur.texto(cu.total)) · has pagado \(Eur.texto(cu.pagado)) · \(pareja) \(Eur.texto(cu.pagadoPareja)) · tu parte \(Eur.texto(cu.parte))")
                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                        .listRowBackground(Tema.carta)
                    HStack {
                        let d = cu.meDebe
                        Text(abs(d) < 0.01 ? "Estáis en paz" : d > 0 ? "\(pareja) te debe \(Eur.texto(d))" : "Le debes \(Eur.texto(-d)) a \(pareja)")
                            .font(Tema.fuente(.texto, peso: .semibold)).foregroundStyle(Tema.texto)
                        Spacer()
                        if abs(d) >= 0.01 {
                            Button {
                                salda(v, d)
                            } label: {
                                if trabajando { ProgressView() } else { Text("Saldar").fontWeight(.semibold) }
                            }
                            .buttonStyle(.borderless)
                            .disabled(trabajando)
                        }
                    }
                    .listRowBackground(Tema.carta)
                    if let mensaje {
                        Text(mensaje).font(Tema.fuente(.pequeno)).foregroundStyle(fallo ? Tema.peligro : Tema.suave)
                            .listRowBackground(Tema.carta)
                    }
                } header: {
                    Text("Cuentas con \(pareja)")
                } footer: {
                    Text("«Saldar» apunta el Bizum que os deja en paz: no cuenta como gasto.")
                }
            }
            Section {
                ForEach(todos) { x in
                    if x.quien.isEmpty {
                        Button { gasto = x.g } label: { filaGasto(x.g, quien: x.quien, compartido: compartido) }
                            .listRowBackground(Tema.carta)
                    } else {
                        filaGasto(x.g, quien: x.quien, compartido: compartido).listRowBackground(Tema.carta)
                    }
                }
            } header: {
                Text("Gastos")
            } footer: {
                if compartido { Text("Los de \(pareja) se cambian en su app.") }
            }
            Section {
                Button("Borrar viaje", role: .destructive) { confirmaBorrar = true }
                    .listRowBackground(Tema.carta)
            } footer: {
                Text("Sus gastos vuelven al ciclo.")
            }
        }
        .scrollContentBackground(.hidden)
        .confirmationDialog("¿Borrar el viaje \(v.n)?", isPresented: $confirmaBorrar, titleVisibility: .visible) {
            Button("Borrar", role: .destructive) {
                Task {
                    do { try await datos.borraViaje(v); Haptica.shared.toca(.desmarcar); cierra() }
                    catch { Haptica.shared.toca(.error); fallo = true; mensaje = DatosGastos.mensaje(error) }
                }
            }
            Button("Mejor no", role: .cancel) {}
        }
    }

    private func filaGasto(_ g: Movimiento, quien: String, compartido: Bool) -> some View {
        // el reparto dicho desde quien mira: «solo mío» de la pareja es «solo de ella» aquí
        let corto: [String: String] = quien.isEmpty
            ? ["mio": "solo tuyo", "suyo": "para \(pareja)", "pago": "pagas a \(pareja)", "cobro": "\(pareja) te paga"]
            : ["mio": "solo de \(quien)", "suyo": "para ti", "pago": "te paga", "cobro": "le pagas"]
        let partes = [FechaGasto.corta(g.dia), compartido ? (quien.isEmpty ? "tú" : quien) : "",
                      compartido ? (corto[g.reparto] ?? "") : "", datos.nombreCat(g.cat)].filter { !$0.isEmpty }
        return HStack(spacing: Tema.Espacio.m) {
            Circle().fill(datos.color(g.cat)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(g.titulo(datos.nombreCat(g.cat))).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto).lineLimit(1)
                Text(partes.joined(separator: " · ")).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Eur.texto(g.importe)).font(Tema.fuente(.texto)).monospacedDigit().foregroundStyle(Tema.texto)
                if g.orig > 0 {
                    Text(MonedaViaje.texto(g.orig, g.moneda)).font(Tema.fuente(.pequeno)).monospacedDigit().foregroundStyle(Tema.suave)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func salda(_ v: EstadoGastos.Viaje, _ d: Double) {
        trabajando = true
        Task {
            defer { trabajando = false }
            do {
                let t = try await datos.salda(v, meDebe: d, pareja: pareja)
                Haptica.shared.toca(.marcar)
                fallo = false
                mensaje = t.contains(API.avisoEncolado) ? t : "Apuntado: estáis en paz."
            } catch {
                Haptica.shared.toca(.error)
                fallo = true
                mensaje = DatosGastos.mensaje(error)
            }
        }
    }
}

// MARK: crear o cambiar un viaje

struct EditorViaje: View {
    let viaje: EstadoGastos.Viaje?
    let pareja: String
    @Environment(\.dismiss) private var cierra
    @State private var datos = DatosGastos.shared
    @State private var n: String
    @State private var desde: Date
    @State private var hasta: Date
    @State private var presu: String
    @State private var moneda: String
    @State private var cambio: String
    @State private var con: Bool
    @State private var buscandoCambio = false
    @State private var trabajando = false
    @State private var error: String?
    @State private var confirmaBorrar = false
    @FocusState private var enfoque: Bool

    init(viaje v: EstadoGastos.Viaje?, pareja: String) {
        viaje = v
        self.pareja = pareja
        _n = State(initialValue: v?.n ?? "")
        _desde = State(initialValue: v.flatMap { FechaGasto.fecha($0.desde) } ?? Date())
        _hasta = State(initialValue: v.flatMap { FechaGasto.fecha($0.hasta) } ?? Date())
        _presu = State(initialValue: (v?.presu ?? 0) > 0 ? Eur.campo(v!.presu) : "")
        _moneda = State(initialValue: v?.moneda ?? "EUR")
        _cambio = State(initialValue: (v?.cambio ?? 0) > 0 ? String(v!.cambio).replacingOccurrences(of: ".", with: ",") : "")
        _con = State(initialValue: v?.con ?? false)
    }

    private var nombre: String { n.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre: Londres", text: $n)
                        .focused($enfoque)
                        .font(Tema.fuente(.texto))
                        .onChange(of: n) { _, v in if v.count > 40 { n = String(v.prefix(40)) } }
                    DatePicker("Desde", selection: $desde, displayedComponents: .date)
                    DatePicker("Hasta", selection: $hasta, in: desde..., displayedComponents: .date)
                } footer: {
                    if viaje == nil {
                        Text("Al crearlo se lleva los gastos que ya son suyos: las reservas (Booking, vuelos…), los que lo nombran y los de esos días. Puedes devolverlos al ciclo.")
                    }
                }
                Section {
                    HStack {
                        TextField("Opcional", text: $presu).keyboardType(.decimalPad).monospacedDigit()
                        Text("€").foregroundStyle(Tema.suave)
                    }
                } header: {
                    Text("Presupuesto del viaje")
                }
                Section {
                    Picker("Moneda", selection: $moneda) {
                        ForEach(MonedaViaje.todas, id: \.codigo) { m in Text("\(m.codigo) (\(m.simbolo))").tag(m.codigo) }
                    }
                    if moneda != "EUR" {
                        HStack {
                            Text("1 \(MonedaViaje.simbolo(moneda)) =")
                            TextField("€ por unidad", text: $cambio).keyboardType(.decimalPad).monospacedDigit()
                                .multilineTextAlignment(.trailing)
                            if buscandoCambio { ProgressView() } else { Text("€").foregroundStyle(Tema.suave) }
                        }
                    }
                } footer: {
                    if moneda != "EUR" {
                        Text("Dentro del viaje, lo que no diga moneda se apunta en \(moneda) y se pasa a euros con este cambio (el de hoy del BCE, si hay conexión).")
                    }
                }
                if !pareja.isEmpty {
                    Section {
                        Toggle("Compartido con \(pareja)", isOn: $con)
                    } footer: {
                        Text("Cada uno apunta lo que paga en su app; aquí salen las cuentas de los dos y lo que os debéis.")
                    }
                }
                if viaje != nil {
                    Section {
                        Button("Borrar viaje", role: .destructive) { confirmaBorrar = true }
                    } footer: {
                        Text("Sus gastos vuelven al ciclo.")
                    }
                }
                if let error {
                    Text(error).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro)
                }
            }
            .font(Tema.fuente(.texto))
            .scrollContentBackground(.hidden)
            .background(Tema.fondo.ignoresSafeArea())
            .navigationTitle(viaje == nil ? "Nuevo viaje" : "Cambiar viaje")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cierra() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { guarda() } label: {
                        if trabajando { ProgressView() } else { Text(viaje == nil ? "Crear" : "Guardar").fontWeight(.semibold) }
                    }
                    .disabled(nombre.isEmpty || trabajando)
                }
            }
            .confirmationDialog("¿Borrar el viaje \(viaje?.n ?? "")?", isPresented: $confirmaBorrar, titleVisibility: .visible) {
                Button("Borrar", role: .destructive) { borra() }
                Button("Mejor no", role: .cancel) {}
            }
            .onChange(of: moneda) { _, m in buscaCambio(m) }
            .onChange(of: desde) { _, d in if hasta < d { hasta = d } }
            .onAppear { if viaje == nil { enfoque = true } }
            .tint(Tema.acento)
        }
        .presentationBackground(Tema.fondo)
        .presentationDragIndicator(.visible)
    }

    /// El cambio de hoy, para no tener que buscarlo (como la web al elegir la moneda).
    private func buscaCambio(_ m: String) {
        guard m != "EUR" else { return }
        buscandoCambio = true
        Task {
            defer { buscandoCambio = false }
            if let c = await datos.cambioDeHoy(m), m == moneda {
                cambio = String(format: "%.4f", c).replacingOccurrences(of: ".", with: ",")
            }
        }
    }

    private func guarda() {
        guard !nombre.isEmpty, !trabajando else { return }
        trabajando = true
        error = nil
        let tasa = moneda == "EUR" ? 0 : (Eur.lee(cambio) ?? 0)
        let v = EstadoGastos.Viaje(id: viaje?.id ?? DatosGastos.idViaje(), n: nombre, desde: FechaGasto.dia(desde),
                                   hasta: FechaGasto.dia(max(desde, hasta)), presu: max(0, Eur.lee(presu) ?? 0),
                                   moneda: moneda, cambio: tasa, con: !pareja.isEmpty && con)
        Task {
            defer { trabajando = false }
            do {
                try await datos.ponViaje(v, nuevo: viaje == nil)
                Haptica.shared.toca(.marcar)
                cierra()
            } catch {
                Haptica.shared.toca(.error)
                self.error = DatosGastos.mensaje(error)
            }
        }
    }

    private func borra() {
        guard let v = viaje else { return }
        trabajando = true
        Task {
            defer { trabajando = false }
            do {
                try await datos.borraViaje(v)
                Haptica.shared.toca(.desmarcar)
                cierra()
            } catch {
                Haptica.shared.toca(.error)
                self.error = DatosGastos.mensaje(error)
            }
        }
    }
}
