import SwiftUI

/// La pestaña Operaciones: apuntar (y cambiar o borrar) compras, ventas y dividendos, y los activos de la cartera.
struct OperacionesInversiones: View {
    let inf: InformeInv
    @State private var datos = DatosInversiones.shared
    @State private var nueva = false
    @State private var editando: OperacionInv?
    @State private var activoEditado: ActivoInv?
    @State private var activoNuevo = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.l) {
            HStack(spacing: Tema.Espacio.m) {
                Button {
                    if inf.activos.isEmpty { activoNuevo = true } else { nueva = true }
                } label: {
                    Label(inf.activos.isEmpty ? "Añadir tu primer activo" : "Apuntar operación", systemImage: "plus")
                        .font(Tema.fuente(.texto, peso: .semibold))
                        .foregroundStyle(Tema.acentoTexto)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Tema.acento, in: RoundedRectangle(cornerRadius: Tema.Radio.boton, style: .continuous))
                }
                if !inf.activos.isEmpty {
                    Button { activoNuevo = true } label: {
                        Label("Activo", systemImage: "plus.magnifyingglass")
                            .font(Tema.fuente(.texto, peso: .medium))
                            .foregroundStyle(Tema.texto)
                            .padding(.vertical, 12).padding(.horizontal, 14)
                            .background(Tema.carta, in: RoundedRectangle(cornerRadius: Tema.Radio.boton, style: .continuous))
                    }
                    .accessibilityLabel("Añadir un activo")
                }
            }
            .buttonStyle(.plain)

            historial
            if !inf.activos.isEmpty { activos }
        }
        .sheet(isPresented: $nueva) { HojaOperacionInv(operacion: nil, activoInicial: nil) }
        .sheet(item: $editando) { o in HojaOperacionInv(operacion: o, activoInicial: nil) }
        .sheet(item: $activoEditado) { a in HojaActivoInv(activo: a, alGuardar: { _ in }) }
        .sheet(isPresented: $activoNuevo) {
            // la hoja de la operación, cuando esta ya se ha ido: dos hojas a la vez, SwiftUI no abre la segunda
            HojaActivoInv(activo: nil, alGuardar: { _ in
                Task {
                    try? await Task.sleep(nanoseconds: 650_000_000)
                    nueva = true
                }
            })
        }
    }

    private var historial: some View {
        let ops = Array(inf.operaciones.reversed())
        return VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            Text("Historial").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
            if ops.isEmpty {
                Text("Sin operaciones todavía.").font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            }
            ForEach(Array(ops.enumerated()), id: \.element.id) { i, o in
                Button { editando = o } label: { fila(o) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { editando = o } label: { Label("Cambiar", systemImage: "pencil") }
                        Button(role: .destructive) { Task { await datos.borraOperacion(o) } } label: {
                            Label("Borrar", systemImage: "trash")
                        }
                    }
                if i < ops.count - 1 { Divider().overlay(Tema.linea) }
            }
        }
        .carta()
    }

    private func fila(_ o: OperacionInv) -> some View {
        let nombre = inf.activo(o.activo)?.nombre ?? o.activo
        let que: String
        switch o.tipo {
        case "compra": que = "Compra · \(DineroES.campo(o.cantidad)) × \(DineroES.precio(o.precio))"
        case "venta": que = "Venta · \(DineroES.campo(o.cantidad)) × \(DineroES.precio(o.precio))"
        default: que = "Dividendo"
        }
        return HStack(alignment: .center, spacing: Tema.Espacio.m) {
            Text(FechasES.corta(o.fecha))
                .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).monospacedDigit()
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(nombre).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto).lineLimit(1)
                Text(que + (o.nota.isEmpty ? "" : " · \(o.nota)"))
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).lineLimit(1)
            }
            Spacer(minLength: Tema.Espacio.s)
            Text((o.total < 0 ? "−" : "+") + DineroES.eur(abs(o.total)))
                .font(Tema.fuente(.texto, peso: .medium))
                .foregroundStyle(o.total < 0 ? Tema.texto : Tema.acento)
                .monospacedDigit()
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Toca para cambiarla; mantén pulsado para borrarla")
    }

    private var activos: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            Text("Activos").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
            ForEach(Array(inf.activos.enumerated()), id: \.element.id) { i, a in
                Button { activoEditado = a } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.nombre).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto).lineLimit(1)
                            Text([a.simbolo, ColoresInv.tipos[a.tipo] ?? a.tipo, a.ter.map { "TER \(FechasES.coma($0, 2)) %" } ?? ""]
                                .filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Tema.tenue)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < inf.activos.count - 1 { Divider().overlay(Tema.linea) }
            }
        }
        .carta()
    }
}

// MARK: hoja de una operación

struct HojaOperacionInv: View {
    let operacion: OperacionInv?
    @State private var datos = DatosInversiones.shared
    @Environment(\.dismiss) private var cierra
    @State private var activo: String
    @State private var tipo: String
    @State private var fecha: Date
    @State private var cantidad: String
    @State private var precio: String
    @State private var comision: String
    @State private var nota: String
    @State private var guardando = false
    @State private var confirmaBorrar = false
    @State private var activoNuevo = false

    init(operacion: OperacionInv?, activoInicial: String?) {
        self.operacion = operacion
        let activos = DatosInversiones.shared.inf?.activos ?? []
        _activo = State(initialValue: operacion?.activo ?? activoInicial ?? activos.first?.id ?? "")
        _tipo = State(initialValue: operacion?.tipo ?? "compra")
        _fecha = State(initialValue: FechasES.fecha(operacion?.fecha ?? Fecha.hoy()) ?? Date())
        _cantidad = State(initialValue: DineroES.campo(operacion?.cantidad))
        _precio = State(initialValue: DineroES.campo(operacion?.precio))
        _comision = State(initialValue: operacion.map { DineroES.campo($0.comision) } ?? "1")
        _nota = State(initialValue: operacion?.nota ?? "")
    }

    private var dividendo: Bool { tipo == "dividendo" }

    private var total: Double? {
        guard !dividendo, let c = DineroES.numero(cantidad), let p = DineroES.numero(precio) else { return nil }
        let k = DineroES.numero(comision) ?? 0
        return tipo == "compra" ? c * p + k : c * p - k
    }

    private var valido: Bool {
        guard !activo.isEmpty, let p = DineroES.numero(precio), p > 0 else { return false }
        return dividendo || (DineroES.numero(cantidad) ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Activo", selection: $activo) {
                        ForEach(datos.inf?.activos ?? []) { a in Text(a.nombre).tag(a.id) }
                    }
                    Button { activoNuevo = true } label: { Label("Otro activo…", systemImage: "plus.magnifyingglass") }
                    Picker("Tipo", selection: $tipo.animation(Tema.Muelle.pantalla)) {
                        Text("Compra").tag("compra")
                        Text("Venta").tag("venta")
                        Text("Dividendo").tag("dividendo")
                    }
                    .pickerStyle(.segmented)
                    DatePicker("Fecha", selection: $fecha, in: ...Date(), displayedComponents: .date)
                }
                .listRowBackground(Tema.carta)
                Section {
                    if !dividendo {
                        campo("Participaciones", "3,25", $cantidad)
                    }
                    campo(dividendo ? "Importe neto cobrado (€)" : "Precio por participación (€)", "118,40", $precio)
                    if !dividendo {
                        campo("Comisión (€)", "1", $comision)
                    }
                } footer: {
                    if let total {
                        Text("Total \(DineroES.eur(total))")
                    } else if !dividendo {
                        Text("El precio es el de cada participación, como sale en el justificante de Trade Republic.")
                    }
                }
                .listRowBackground(Tema.carta)
                Section {
                    TextField("Plan de ahorro, aportación extra…", text: $nota)
                } header: {
                    Text("Nota (opcional)").estiloEtiqueta()
                }
                .listRowBackground(Tema.carta)
                if let operacion {
                    Section {
                        Button("Borrar operación", role: .destructive) { confirmaBorrar = true }
                    }
                    .listRowBackground(Tema.carta)
                    .confirmationDialog("¿Borrar esta operación?", isPresented: $confirmaBorrar, titleVisibility: .visible) {
                        Button("Borrar", role: .destructive) {
                            Task {
                                await datos.borraOperacion(operacion)
                                cierra()
                            }
                        }
                        Button("Cancelar", role: .cancel) {}
                    }
                }
            }
            .font(Tema.fuente(.texto))
            .scrollContentBackground(.hidden)
            .background(Tema.fondo)
            .tint(Tema.acento)
            .navigationTitle(operacion == nil ? "Apuntar operación" : "Cambiar operación")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cierra() } }
                ToolbarItem(placement: .confirmationAction) {
                    if guardando {
                        ProgressView()
                    } else {
                        Button("Guardar") { guarda() }.fontWeight(.semibold).disabled(!valido)
                    }
                }
            }
            .sheet(isPresented: $activoNuevo) {
                HojaActivoInv(activo: nil, alGuardar: { id in activo = id })
            }
            .interactiveDismissDisabled(guardando)
        }
        .environment(\.locale, FechasES.locale)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Tema.fondo)
    }

    private func campo(_ titulo: String, _ pista: String, _ texto: Binding<String>) -> some View {
        HStack {
            Text(titulo).foregroundStyle(Tema.texto)
            Spacer(minLength: Tema.Espacio.m)
            TextField(pista, text: texto)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: 140)
        }
    }

    private func guarda() {
        guardando = true
        var o: [String: Any] = [
            "activo": activo, "tipo": tipo, "fecha": Fecha.dia(fecha),
            "cantidad": dividendo ? 0 : (DineroES.numero(cantidad) ?? 0),
            "precio": DineroES.numero(precio) ?? 0,
            "comision": dividendo ? 0 : (DineroES.numero(comision) ?? 0),
            "nota": nota.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
        if let operacion { o["id"] = operacion.id }
        Task {
            if await datos.guardaOperacion(o) { cierra() } else { guardando = false }
        }
    }
}

// MARK: hoja de un activo

/// Un activo nuevo (buscándolo en Yahoo por ISIN, ticker o nombre) o cambiar uno. `alGuardar` recibe su id.
struct HojaActivoInv: View {
    let activo: ActivoInv?
    let alGuardar: (String) -> Void
    @State private var datos = DatosInversiones.shared
    @Environment(\.dismiss) private var cierra
    @State private var q = ""
    @State private var candidatos: [CandidatoInv] = []
    @State private var buscando = false
    @State private var errorBusqueda: String?
    @State private var simbolo: String
    @State private var nombre: String
    @State private var isin: String
    @State private var tipo: String
    @State private var ter: String
    @State private var papel: String
    @State private var guardando = false
    @State private var confirmaBorrar = false

    init(activo: ActivoInv?, alGuardar: @escaping (String) -> Void) {
        self.activo = activo
        self.alGuardar = alGuardar
        _simbolo = State(initialValue: activo?.simbolo ?? "")
        _nombre = State(initialValue: activo?.nombre ?? "")
        _isin = State(initialValue: activo?.isin ?? "")
        _tipo = State(initialValue: activo?.tipo ?? "etf")
        _ter = State(initialValue: DineroES.campo(activo?.ter))
        _papel = State(initialValue: activo?.papel ?? "")
    }

    private var valido: Bool { !simbolo.trimmingCharacters(in: .whitespaces).isEmpty }

    private static func esISIN(_ s: String) -> Bool {
        s.range(of: "^[A-Z]{2}[A-Z0-9]{9}[0-9]$", options: .regularExpression) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if activo == nil {
                    Section {
                        TextField("IE00BK5BQT80 · VWCE · Vanguard All-World", text: $q)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        if buscando { ProgressView() }
                        if let errorBusqueda {
                            Text(errorBusqueda).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro)
                        }
                        ForEach(candidatos) { c in
                            Button { elige(c) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(c.simbolo) — \(c.nombre)").foregroundStyle(Tema.texto)
                                    Text(c.bolsa + (c.enEuros ? " · EUR" : "")).font(Tema.fuente(.pequeno))
                                        .foregroundStyle(c.enEuros ? Tema.acento : Tema.suave)
                                }
                            }
                        }
                    } header: {
                        Text("Busca por ISIN, ticker o nombre").estiloEtiqueta()
                    } footer: {
                        Text("Elige el que acaba en .DE (Xetra, en euros): es lo más parecido al precio de Trade Republic.")
                    }
                    .listRowBackground(Tema.carta)
                }
                Section {
                    fila("Símbolo de Yahoo", "VWCE.DE", $simbolo, mayusculas: true)
                    fila("Nombre", "Vanguard FTSE All-World", $nombre)
                    fila("ISIN", "IE00BK5BQT80", $isin, mayusculas: true)
                    Picker("Tipo", selection: $tipo) {
                        ForEach(ColoresInv.ordenTipos, id: \.self) { k in Text(ColoresInv.tipos[k] ?? k).tag(k) }
                    }
                    HStack {
                        Text("TER (%)")
                        Spacer(minLength: Tema.Espacio.m)
                        TextField("0,22", text: $ter).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 120)
                    }
                } header: {
                    Text("Activo").estiloEtiqueta()
                }
                .listRowBackground(Tema.carta)
                Section {
                    TextField("Núcleo global, apuesta por tecnología, liquidez…", text: $papel, axis: .vertical)
                        .lineLimit(1...3)
                } header: {
                    Text("Qué papel cumple en tu cartera").estiloEtiqueta()
                } footer: {
                    Text("Lo lee la review del domingo.")
                }
                .listRowBackground(Tema.carta)
                if let activo {
                    Section {
                        Button("Borrar activo", role: .destructive) { confirmaBorrar = true }
                    } footer: {
                        Text("Solo se puede si no tiene operaciones.")
                    }
                    .listRowBackground(Tema.carta)
                    .confirmationDialog("¿Borrar \(activo.nombre)?", isPresented: $confirmaBorrar, titleVisibility: .visible) {
                        Button("Borrar", role: .destructive) {
                            Task { if await datos.borraActivo(activo.id) { cierra() } }
                        }
                        Button("Cancelar", role: .cancel) {}
                    }
                }
            }
            .font(Tema.fuente(.texto))
            .scrollContentBackground(.hidden)
            .background(Tema.fondo)
            .tint(Tema.acento)
            .navigationTitle(activo == nil ? "Activo nuevo" : "Cambiar activo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cierra() } }
                ToolbarItem(placement: .confirmationAction) {
                    if guardando {
                        ProgressView()
                    } else {
                        Button("Guardar") { guarda() }.fontWeight(.semibold).disabled(!valido)
                    }
                }
            }
            // busca al dejar de escribir (Yahoo no quiere una petición por letra)
            .task(id: q) {
                let texto = q.trimmingCharacters(in: .whitespaces)
                guard texto.count >= 2 else {
                    candidatos = []
                    return
                }
                try? await Task.sleep(nanoseconds: 450_000_000)
                guard !Task.isCancelled else { return }
                buscando = true
                defer { buscando = false }
                do {
                    let r = try await datos.busca(texto)
                    guard !Task.isCancelled else { return }
                    withAnimation(Tema.Muelle.pantalla) { candidatos = r }
                    errorBusqueda = r.isEmpty ? "Yahoo no encuentra nada con eso." : nil
                } catch {
                    errorBusqueda = "Sin búsqueda: \(error.localizedDescription)"
                }
            }
            .interactiveDismissDisabled(guardando)
        }
        .environment(\.locale, FechasES.locale)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Tema.fondo)
    }

    private func fila(_ titulo: String, _ pista: String, _ texto: Binding<String>, mayusculas: Bool = false) -> some View {
        HStack {
            Text(titulo)
            Spacer(minLength: Tema.Espacio.m)
            TextField(pista, text: texto)
                .textInputAutocapitalization(mayusculas ? .characters : .sentences)
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
        }
    }

    private func elige(_ c: CandidatoInv) {
        Haptica.shared.toca(.marcar)
        simbolo = c.simbolo
        nombre = c.nombre
        let busqueda = q.trimmingCharacters(in: .whitespaces).uppercased()
        if Self.esISIN(busqueda) { isin = busqueda }
        switch c.clase {
        case "ETF": tipo = "etf"
        case "EQUITY": tipo = "accion"
        case "MUTUALFUND": tipo = "fondo"
        case "CRYPTOCURRENCY": tipo = "cripto"
        default: break
        }
        candidatos = []
    }

    private func guarda() {
        guardando = true
        var a: [String: Any] = [
            "simbolo": simbolo.trimmingCharacters(in: .whitespaces).uppercased(),
            "nombre": nombre.trimmingCharacters(in: .whitespaces),
            "isin": isin.trimmingCharacters(in: .whitespaces).uppercased(),
            "tipo": tipo,
            "ter": DineroES.numero(ter).map { $0 as Any } ?? NSNull(),
            "papel": papel.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
        if let activo { a["id"] = activo.id }
        Task {
            if let id = await datos.guardaActivo(a) {
                cierra()
                alGuardar(id)
            } else {
                guardando = false
            }
        }
    }
}
