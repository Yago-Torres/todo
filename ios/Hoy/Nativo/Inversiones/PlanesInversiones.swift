import SwiftUI
import UserNotifications

// La pestaña Planes (como la de la web): el presupuesto de inversión que se pone en Gastos, los planes de ahorro que el
// servidor apunta solos cada mes y las alertas de precio. Los avisos de los planes los programa Tom en local (sin cuenta
// de pago de Apple no hay push del servidor al iPhone); las alertas, que no se saben de antemano, llegan por el push de
// la web o por Telegram (aviso.py en la Pi).

struct PlanInv: Codable, Identifiable, Hashable {
    var id: String
    var activo: String
    var importe: Double
    var dia: Int
    var comision: Double
    var desde: String
    var pausado: Bool
    var nota: String
    var hechos: [String]
    var proximo: String?
}

struct AlertaInv: Codable, Identifiable, Hashable {
    var id: String
    var activo: String      // "*" = toda la cartera (solo «cae»)
    var tipo: String        // bajo | sobre | cae
    var valor: Double
    var nota: String
    var armada: Bool
    var ultima: String
}

struct LeccionInv: Codable, Hashable {
    var fecha: String
    var texto: String
}

/// Lo que hace falta del resumen de Gastos: el presupuesto de inversión del ciclo.
struct PresupuestoInv: Decodable {
    struct Inversion: Decodable { var presu: Double; var aportado: Double? }
    var inversion: Inversion?
    var fin: String
    var diaCobro: Int

    enum CodingKeys: String, CodingKey { case inversion, fin, diaCobro = "dia_cobro" }
}

extension DatosInversiones {
    func guardaPlan(_ p: [String: Any]) async -> Bool {
        await escribe("/api/inversiones/plan", p, p["id"] == nil ? "Plan creado: la compra se apuntará sola" : "Plan guardado")
    }

    func guardaAlerta(_ a: [String: Any]) async -> Bool {
        await escribe("/api/inversiones/alerta", a, a["id"] == nil ? "Alerta creada" : "Alerta guardada")
    }

    func borraPlan(_ p: PlanInv) async { await quita("/api/inversiones/plan", p.id, "Plan borrado (sus compras se quedan)") }

    func borraAlerta(_ a: AlertaInv) async { await quita("/api/inversiones/alerta", a.id, "Alerta borrada") }

    func presupuesto() async -> PresupuestoInv? {
        guard let r = try? await API.leeOCopia("/api/gastos/resumen") else { return nil }
        return try? JSONDecoder().decode(PresupuestoInv.self, from: r.datos)
    }

    private func escribe(_ ruta: String, _ cuerpo: [String: Any], _ ok: String) async -> Bool {
        do {
            _ = try await API.datos(ruta, metodo: "POST", json: cuerpo)
            Haptica.shared.toca(.marcar)
            avisa(ok)
            await carga()
            return true
        } catch {
            avisa("No se ha guardado: \(error.localizedDescription)", error: true)
            return false
        }
    }

    private func quita(_ ruta: String, _ id: String, _ texto: String) async {
        do {
            let r = try await API.datos("\(ruta)/borra", metodo: "POST", json: ["id": id])
            await carga()
            var deshacer: (@MainActor () async -> Void)?
            if let viejo = (try? JSONSerialization.jsonObject(with: r)) as? [String: Any] {
                deshacer = { [weak self] in
                    _ = try? await API.datos(ruta, metodo: "POST", json: viejo)
                    await self?.carga()
                }
            }
            avisa(texto, deshacer: deshacer)
        } catch {
            avisa("No se ha borrado: \(error.localizedDescription)", error: true)
        }
    }
}

/// Los avisos locales de Inversiones: el día de cada plan (a las 19:00, cuando ya está apuntado con el precio del día)
/// y el domingo de la review. Se reprograman cada vez que se carga la cartera.
enum AvisosInversiones {
    private static let prefijo = "inv."

    static func programa(_ inf: InformeInv) async {
        let centro = UNUserNotificationCenter.current()
        let viejos = await centro.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefijo) }
        centro.removePendingNotificationRequests(withIdentifiers: viejos)
        guard Almacen.defaults.bool(forKey: "avisos") else { return }   // el mismo interruptor que los demás avisos de Tom
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        for p in inf.planes ?? [] where !p.pausado {
            guard let dia = p.proximo, let fecha = Fecha.fecha(dia),
                  let cuando = cal.date(bySettingHour: 19, minute: 0, second: 0, of: fecha), cuando > Date() else { continue }
            let c = UNMutableNotificationContent()
            c.title = "Plan de ahorro"
            c.body = "Hoy toca: \(DineroES.eur(p.importe)) en \(inf.activo(p.activo)?.nombre ?? p.activo). Ya está apuntado con el precio del día; "
                + "si Trade Republic te dio otro, mándale la confirmación al bot y lo corrige."
            c.sound = .default
            c.userInfo = ["ruta": "/inversiones.html"]
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: cuando)
            try? await centro.add(UNNotificationRequest(identifier: "\(prefijo)plan.\(p.id)", content: c,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
        // la review sale los domingos a las 10:00 (inversiones-review.timer) y tarda un rato: a las 11:30
        guard inf.posiciones.contains(where: { $0.cantidad > 0 }) else { return }
        let c = UNMutableNotificationContent()
        c.title = "Review de inversiones"
        c.body = "Ya tienes la review del domingo y la lección de la semana."
        c.sound = .default
        c.userInfo = ["ruta": "/inversiones.html"]
        var comps = DateComponents()
        comps.weekday = 1
        comps.hour = 11
        comps.minute = 30
        try? await centro.add(UNNotificationRequest(identifier: "\(prefijo)review", content: c,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
    }
}

struct PlanesInversiones: View {
    let inf: InformeInv
    @State private var datos = DatosInversiones.shared
    @State private var presu: PresupuestoInv?
    @State private var leidoPresu = false
    @State private var planNuevo = false
    @State private var planEditado: PlanInv?
    @State private var alertaNueva = false
    @State private var alertaEditada: AlertaInv?

    private var planes: [PlanInv] { inf.planes ?? [] }
    private var alertas: [AlertaInv] { inf.alertas ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.l) {
            presupuesto
            listaPlanes
            listaAlertas
            Text("Planes, alertas, la review y la renta te llegan como notificación: los días de los planes y el domingo, de Tom; "
                 + "las alertas, del push de la web (actívalo en Entreno o en Inversiones de la web) o, si no, por Telegram.")
                .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task { presu = await datos.presupuesto(); leidoPresu = true }
        .sheet(isPresented: $planNuevo) { HojaPlanInv(plan: nil) }
        .sheet(item: $planEditado) { p in HojaPlanInv(plan: p) }
        .sheet(isPresented: $alertaNueva) { HojaAlertaInv(alerta: nil) }
        .sheet(item: $alertaEditada) { a in HojaAlertaInv(alerta: a) }
    }

    private var presupuesto: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            Text("Presupuesto de inversión").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
            if let iv = presu?.inversion, iv.presu > 0, let p = presu {
                let ap = iv.aportado ?? 0
                Text("\(DineroES.eur(ap)) de \(DineroES.eur(iv.presu))")
                    .font(Tema.fuente(.destacado, peso: .semibold)).foregroundStyle(Tema.texto).monospacedDigit()
                ProgressView(value: min(1, ap / iv.presu)).tint(Tema.acento)
                Text(ap >= iv.presu ? "Hecho este \(p.diaCobro == 1 ? "mes" : "ciclo") (hasta el \(FechasES.corta(p.fin)))."
                                    : "Te quedan \(DineroES.eur(iv.presu - ap)) por invertir hasta el \(FechasES.corta(p.fin)).")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            } else {
                Text(leidoPresu ? "Sin presupuesto. En Gastos → Presupuestos → «Para invertir cada ciclo» le dedicas una cantidad: cuenta como un fijo del ciclo."
                                : "Leyendo Gastos…")
                    .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .carta()
    }

    private var listaPlanes: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            HStack {
                Text("Planes de ahorro").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
                Spacer()
                if !inf.activos.isEmpty {
                    Button { planNuevo = true } label: { Label("Nuevo", systemImage: "plus").font(Tema.fuente(.pequeno, peso: .semibold)) }
                        .tint(Tema.acento)
                }
            }
            if planes.isEmpty {
                Text(inf.activos.isEmpty ? "Primero apunta un activo en Operaciones."
                                         : "Si tienes un plan en Trade Republic, apúntalo: cada mes se apunta sola la compra con el precio de ese día.")
                    .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(planes.enumerated()), id: \.element.id) { i, p in
                Button { planEditado = p } label: {
                    fila("\(DineroES.eur(p.importe)) en \(nombre(p.activo))",
                         ["el \(p.dia) de cada mes", p.pausado ? "en pausa" : p.proximo.map { "próximo: \(FechasES.corta($0))" } ?? "", p.nota]
                            .filter { !$0.isEmpty }.joined(separator: " · "),
                         icono: p.pausado ? "pause.circle" : "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button { planEditado = p } label: { Label("Cambiar", systemImage: "pencil") }
                    Button {
                        Task { _ = await datos.guardaPlan(["id": p.id, "pausado": !p.pausado]) }
                    } label: { Label(p.pausado ? "Reanudar" : "Pausar", systemImage: p.pausado ? "play" : "pause") }
                    Button(role: .destructive) { Task { await datos.borraPlan(p) } } label: { Label("Borrar", systemImage: "trash") }
                }
                if i < planes.count - 1 { Divider().overlay(Tema.linea) }
            }
        }
        .carta()
    }

    private var listaAlertas: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            HStack {
                Text("Alertas de precio").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
                Spacer()
                if !inf.activos.isEmpty {
                    Button { alertaNueva = true } label: { Label("Nueva", systemImage: "plus").font(Tema.fuente(.pequeno, peso: .semibold)) }
                        .tint(Tema.acento)
                }
            }
            if alertas.isEmpty {
                Text("Sin alertas. Se miran cada 15 minutos con el precio de L&S y avisan una vez.")
                    .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            }
            ForEach(Array(alertas.enumerated()), id: \.element.id) { i, a in
                Button { alertaEditada = a } label: {
                    fila(HojaAlertaInv.texto(a, nombre(a.activo)),
                         [a.tipo != "cae" && !a.armada ? "saltó el \(FechasES.corta(a.ultima)): se reactiva al alejarse un 2 %" : "", a.nota]
                            .filter { !$0.isEmpty }.joined(separator: " · "),
                         icono: a.armada || a.tipo == "cae" ? "bell" : "bell.slash")
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button { alertaEditada = a } label: { Label("Cambiar", systemImage: "pencil") }
                    Button(role: .destructive) { Task { await datos.borraAlerta(a) } } label: { Label("Borrar", systemImage: "trash") }
                }
                if i < alertas.count - 1 { Divider().overlay(Tema.linea) }
            }
        }
        .carta()
    }

    private func nombre(_ id: String) -> String { id == "*" ? "Toda la cartera" : inf.activo(id)?.nombre ?? id }

    private func fila(_ titulo: String, _ sub: String, icono: String) -> some View {
        HStack(spacing: Tema.Espacio.m) {
            Image(systemName: icono).foregroundStyle(Tema.acento).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto).lineLimit(2)
                if !sub.isEmpty {
                    Text(sub).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Tema.tenue)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Toca para cambiarlo; mantén pulsado para más")
    }
}

/// La lección de la última review, arriba de Cartera.
struct LeccionInvCarta: View {
    let leccion: LeccionInv

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            HStack(alignment: .firstTextBaseline) {
                Label("Lección de la semana", systemImage: "graduationcap")
                    .font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
                Spacer()
                Text(FechasES.corta(leccion.fecha)).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            }
            MarkdownInv(texto: leccion.texto)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .carta()
    }
}

// MARK: hojas

struct HojaPlanInv: View {
    let plan: PlanInv?
    @State private var datos = DatosInversiones.shared
    @Environment(\.dismiss) private var cierra
    @State private var activo: String
    @State private var importe: String
    @State private var dia: Int
    @State private var comision: String
    @State private var desde: Date
    @State private var pausado: Bool
    @State private var nota: String
    @State private var guardando = false
    @State private var confirmaBorrar = false

    init(plan: PlanInv?) {
        self.plan = plan
        _activo = State(initialValue: plan?.activo ?? DatosInversiones.shared.inf?.activos.first?.id ?? "")
        _importe = State(initialValue: DineroES.campo(plan?.importe))
        _dia = State(initialValue: plan?.dia ?? 2)
        _comision = State(initialValue: DineroES.campo(plan?.comision))
        _desde = State(initialValue: Fecha.fecha(plan?.desde ?? Fecha.hoy()) ?? Date())
        _pausado = State(initialValue: plan?.pausado ?? false)
        _nota = State(initialValue: plan?.nota ?? "")
    }

    private var valido: Bool { !activo.isEmpty && (DineroES.numero(importe) ?? 0) >= 1 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Activo", selection: $activo) {
                        ForEach(datos.inf?.activos ?? []) { a in Text(a.nombre).tag(a.id) }
                    }
                    HStack {
                        Text("Cada mes (€)")
                        Spacer(minLength: Tema.Espacio.m)
                        TextField("100", text: $importe).keyboardType(.decimalPad).multilineTextAlignment(.trailing).monospacedDigit().frame(maxWidth: 140)
                    }
                    Picker("Día del mes", selection: $dia) {
                        ForEach(1...28, id: \.self) { Text("El \($0)").tag($0) }
                    }
                    HStack {
                        Text("Comisión (€)")
                        Spacer(minLength: Tema.Espacio.m)
                        TextField("0", text: $comision).keyboardType(.decimalPad).multilineTextAlignment(.trailing).monospacedDigit().frame(maxWidth: 140)
                    }
                    DatePicker("Desde", selection: $desde, displayedComponents: .date)
                    if plan != nil { Toggle("En pausa", isOn: $pausado) }
                } footer: {
                    Text("Si el día cae en fin de semana, el lunes. La compra se apunta sola con el precio de ese día (estimado): "
                         + "si pones una fecha pasada, se apuntan también los meses de atrás.")
                }
                .listRowBackground(Tema.carta)
                Section {
                    TextField("Opcional", text: $nota)
                } header: { Text("Nota").estiloEtiqueta() }
                .listRowBackground(Tema.carta)
                if let plan {
                    Section {
                        Button("Borrar plan", role: .destructive) { confirmaBorrar = true }
                    } footer: { Text("Las compras que ya apuntó se quedan.") }
                    .listRowBackground(Tema.carta)
                    .confirmationDialog("¿Borrar este plan?", isPresented: $confirmaBorrar, titleVisibility: .visible) {
                        Button("Borrar", role: .destructive) { Task { await datos.borraPlan(plan); cierra() } }
                        Button("Cancelar", role: .cancel) {}
                    }
                }
            }
            .font(Tema.fuente(.texto))
            .scrollContentBackground(.hidden)
            .background(Tema.fondo)
            .tint(Tema.acento)
            .navigationTitle(plan == nil ? "Plan de ahorro" : "Cambiar plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cierra() } }
                ToolbarItem(placement: .confirmationAction) {
                    if guardando { ProgressView() } else {
                        Button("Guardar") { guarda() }.fontWeight(.semibold).disabled(!valido)
                    }
                }
            }
            .interactiveDismissDisabled(guardando)
        }
        .environment(\.locale, FechasES.locale)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Tema.fondo)
    }

    private func guarda() {
        guardando = true
        var p: [String: Any] = ["activo": activo, "importe": DineroES.numero(importe) ?? 0, "dia": dia,
                                "comision": DineroES.numero(comision) ?? 0, "desde": Fecha.dia(desde), "pausado": pausado,
                                "nota": nota.trimmingCharacters(in: .whitespacesAndNewlines)]
        if let plan { p["id"] = plan.id }
        Task { if await datos.guardaPlan(p) { cierra() } else { guardando = false } }
    }
}

struct HojaAlertaInv: View {
    let alerta: AlertaInv?
    @State private var datos = DatosInversiones.shared
    @Environment(\.dismiss) private var cierra
    @State private var activo: String
    @State private var tipo: String
    @State private var valor: String
    @State private var nota: String
    @State private var guardando = false

    init(alerta: AlertaInv?) {
        self.alerta = alerta
        _activo = State(initialValue: alerta?.activo ?? DatosInversiones.shared.inf?.activos.first?.id ?? "")
        _tipo = State(initialValue: alerta?.tipo ?? "bajo")
        _valor = State(initialValue: DineroES.campo(alerta?.valor))
        _nota = State(initialValue: alerta?.nota ?? "")
    }

    static func texto(_ a: AlertaInv, _ nombre: String) -> String {
        switch a.tipo {
        case "bajo": return "\(nombre) baja de \(DineroES.eur(a.valor))"
        case "sobre": return "\(nombre) sube de \(DineroES.eur(a.valor))"
        default: return "\(nombre) cae en un día un \(FechasES.coma(a.valor, 1)) %"
        }
    }

    private var valido: Bool { !activo.isEmpty && (DineroES.numero(valor) ?? 0) > 0 && (activo != "*" || tipo == "cae") }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("De", selection: $activo) {
                        if tipo == "cae" { Text("Toda la cartera").tag("*") }
                        ForEach(datos.inf?.activos ?? []) { a in Text(a.nombre).tag(a.id) }
                    }
                    Picker("Cuando", selection: $tipo.animation(Tema.Muelle.pantalla)) {
                        Text("Baje de").tag("bajo")
                        Text("Suba de").tag("sobre")
                        Text("Caiga en un día").tag("cae")
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Text(tipo == "cae" ? "Caída (%)" : "Precio (€)")
                        Spacer(minLength: Tema.Espacio.m)
                        TextField(tipo == "cae" ? "3" : "100", text: $valor).keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing).monospacedDigit().frame(maxWidth: 140)
                    }
                } footer: {
                    Text(tipo == "cae" ? "Avisa una vez al día como mucho." : "Avisa una vez y se vuelve a activar cuando el precio se aleja un 2 %.")
                }
                .listRowBackground(Tema.carta)
                Section {
                    TextField("Por qué te importa (comprar más, revisar…)", text: $nota)
                } header: { Text("Nota").estiloEtiqueta() }
                .listRowBackground(Tema.carta)
            }
            .font(Tema.fuente(.texto))
            .scrollContentBackground(.hidden)
            .background(Tema.fondo)
            .tint(Tema.acento)
            .navigationTitle(alerta == nil ? "Alerta de precio" : "Cambiar alerta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cierra() } }
                ToolbarItem(placement: .confirmationAction) {
                    if guardando { ProgressView() } else {
                        Button("Guardar") { guarda() }.fontWeight(.semibold).disabled(!valido)
                    }
                }
            }
            .onChange(of: tipo) { _, t in
                if t != "cae" && activo == "*" { activo = datos.inf?.activos.first?.id ?? "" }
            }
            .interactiveDismissDisabled(guardando)
        }
        .environment(\.locale, FechasES.locale)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Tema.fondo)
    }

    private func guarda() {
        guardando = true
        var a: [String: Any] = ["activo": activo, "tipo": tipo, "valor": DineroES.numero(valor) ?? 0,
                                "nota": nota.trimmingCharacters(in: .whitespacesAndNewlines)]
        if let alerta { a["id"] = alerta.id }
        Task { if await datos.guardaAlerta(a) { cierra() } else { guardando = false } }
    }
}
