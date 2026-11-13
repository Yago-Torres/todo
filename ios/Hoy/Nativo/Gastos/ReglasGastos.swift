import SwiftUI
import Observation

// Reglas de categoría que propone Tom y gastos recurrentes (semana, mes, año) de cada instancia.
//
// Las reglas viven en el data.json de gastos (`reglas`, `rechazadas`, `recurrentes`) y se cambian con operaciones de la
// cola sobre /estado (Compartido/OperacionesGastos.swift): se ven al momento, funcionan sin red y Sincro las aplica sobre
// el estado fresco. Las propuestas las calcula el servidor (GET /reglas, con copia en Local) y, tras corregir la
// categoría de un gasto, el propio iPhone (misma palabra que `patron()` del servidor). Yago y Aitana, siempre aparte.

private extension KeyedDecodingContainer {
    func v2<T: Decodable>(_ clave: Key, _ por: T) -> T { (try? decodeIfPresent(T.self, forKey: clave)) ?? por }
}

struct ReglaGasto: Decodable, Identifiable, Hashable {
    var id = ""
    var txt = ""
    var cat = ""

    enum CodingKeys: String, CodingKey { case id, txt, cat }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.v2(.id, ""); txt = c.v2(.txt, ""); cat = c.v2(.cat, "")
    }
}

struct PropuestaRegla: Decodable, Identifiable, Hashable {
    var txt = ""
    var cat = ""
    var encajan = 0
    var cambiarian = 0
    /// El id de la regla que esta propuesta cambiaría (corregiste contra una regla), o "".
    var cambia = ""
    var ejemplos: [String] = []

    var id: String { "\(txt)|\(cat)" }

    enum CodingKeys: String, CodingKey { case txt, cat, encajan, cambiarian, cambia, ejemplos }

    init(txt: String, cat: String, encajan: Int, cambiarian: Int, cambia: String = "", ejemplos: [String] = []) {
        self.txt = txt; self.cat = cat; self.encajan = encajan; self.cambiarian = cambiarian
        self.cambia = cambia; self.ejemplos = ejemplos
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        txt = c.v2(.txt, ""); cat = c.v2(.cat, ""); encajan = c.v2(.encajan, 0); cambiarian = c.v2(.cambiarian, 0)
        cambia = c.v2(.cambia, ""); ejemplos = c.v2(.ejemplos, [])
    }
}

struct Recurrente: Decodable, Identifiable, Hashable {
    var clave = ""
    var n = ""
    var importe = 0.0
    var cada = "mes"
    var cat = ""
    var ultimo = ""
    var proximo = ""
    var veces = 1
    var alMes = 0.0
    var alAno = 0.0
    /// si (confirmado), no (ignorado) o "" (detectado).
    var estado = ""

    var id: String { clave }

    enum CodingKeys: String, CodingKey {
        case clave, n, importe, cada, cat, ultimo, proximo, veces, estado
        case alMes = "al_mes"
        case alAno = "al_año"
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        clave = c.v2(.clave, ""); n = c.v2(.n, ""); importe = c.v2(.importe, 0); cada = c.v2(.cada, "mes")
        cat = c.v2(.cat, ""); ultimo = c.v2(.ultimo, ""); proximo = c.v2(.proximo, ""); veces = c.v2(.veces, 1)
        alMes = c.v2(.alMes, 0); alAno = c.v2(.alAno, alMes * 12); estado = c.v2(.estado, "")
    }

    /// «cada semana», «cada mes», «cada año».
    var periodo: String { ["semana": "cada semana", "mes": "cada mes", "año": "cada año"][cada] ?? "cada \(cada)" }
}

private struct RespuestaReglas: Decodable {
    var propuestas: [PropuestaRegla] = []

    enum CodingKeys: String, CodingKey { case propuestas }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        propuestas = c.v2(.propuestas, [])
    }
}

/// Las propuestas de cada instancia y la que se ofrece ahora mismo (tras corregir o apuntar).
@MainActor @Observable
final class ReglasTom {
    static let shared = ReglasTom()

    struct Oferta: Equatable {
        var instancia: InstanciaGastos
        var propuesta: PropuestaRegla
    }

    private var delServidor: [InstanciaGastos: [PropuestaRegla]] = [:]
    /// La que sale abajo: «¿Siempre así?». Se va al aceptar, rechazar o cerrar.
    var oferta: Oferta?

    func carga(_ inst: InstanciaGastos) async {
        guard let r = try? await API.leeOCopia("\(inst.base)/reglas"),
              let d = try? JSONDecoder().decode(RespuestaReglas.self, from: r.datos) else { return }
        withAnimation(Tema.Muelle.pantalla) { delServidor[inst] = d.propuestas }
    }

    func ofrece(_ p: PropuestaRegla, en inst: InstanciaGastos) {
        withAnimation(Tema.Muelle.pantalla) { oferta = Oferta(instancia: inst, propuesta: p) }
    }

    func cierraOferta() {
        withAnimation(Tema.Muelle.pantalla) { oferta = nil }
    }

    func propuestas(_ inst: InstanciaGastos) -> [PropuestaRegla] { delServidor[inst] ?? [] }
}

// MARK: datos (sobre el estado de la instancia que se ve)

extension DatosGastos {
    var reglas: [ReglaGasto] { estado?.reglas ?? [] }

    /// Las propuestas del servidor que siguen en pie con lo de este iPhone (lo aceptado o rechazado sin red ya no sale),
    /// con las cuentas rehechas sobre los movimientos de ahora.
    var propuestas: [PropuestaRegla] {
        let hechas = Set(reglas.map(\.txt)), no = Set(estado?.rechazadas ?? [])
        return ReglasTom.shared.propuestas(instancia).compactMap { p in
            guard !hechas.contains(p.txt), !no.contains(p.txt) else { return nil }
            var q = p
            q.encajan = encajan(p.txt)
            q.cambiarian = cambiarian(p.txt, a: p.cat)
            return q
        }
    }

    func encajan(_ txt: String) -> Int {
        let t = ReglasGastos.norma(txt)
        return movimientos.filter { ReglasGastos.encaja(t, comercio: $0.comercio, nota: $0.nota) }.count
    }

    func cambiarian(_ txt: String, a cat: String) -> Int {
        let t = ReglasGastos.norma(txt)
        return movimientos.filter { $0.cat != cat && ReglasGastos.encaja(t, comercio: $0.comercio, nota: $0.nota) }.count
    }

    /// Tras cambiar la categoría de un gasto a mano: la regla de su palabra, si hay algo que aprender.
    func propuestaTrasCorregir(comercio: String, nota: String, cat: String) -> PropuestaRegla? {
        let p = ReglasGastos.patron(comercio: comercio, nota: nota)
        guard !p.isEmpty, !(estado?.rechazadas ?? []).contains(p) else { return nil }
        let regla = reglas.first { ReglasGastos.encaja($0.txt, comercio: comercio, nota: nota) }
        if let regla, regla.cat == cat { return nil }
        let ejemplos = Array(NSOrderedSet(array: movimientos
            .filter { $0.cat != cat && ReglasGastos.encaja(p, comercio: $0.comercio, nota: $0.nota) }
            .map { $0.comercio.isEmpty ? $0.nota : $0.comercio }).array.compactMap { $0 as? String }.prefix(3))
        return PropuestaRegla(txt: p, cat: cat, encajan: encajan(p), cambiarian: cambiarian(p, a: cat),
                              cambia: regla?.txt == p ? (regla?.id ?? "") : "", ejemplos: ejemplos)
    }

    // MARK: operaciones (a la cola: sin red también)

    /// Crea o cambia una regla. Con `aplicar`, también los gastos de antes que casan.
    func ponRegla(id: String = "", txt: String, cat: String, aplicar: Bool, en inst: InstanciaGastos? = nil) async throws {
        let inst = inst ?? instancia
        let t = String(ReglasGastos.norma(txt).prefix(40))
        guard !t.isEmpty else { throw APIError(mensaje: "Escribe qué tiene que decir el concepto: por ejemplo, «mercadona».") }
        let rid = !id.isEmpty ? id : (reglas.first { $0.txt == t }?.id ?? "r" + UUID().uuidString.prefix(8).lowercased())
        try await opera(inst, ["op": "regla.pon", "regla": ["id": rid, "txt": t, "cat": cat],
                               "resumen": "Regla: «\(t)» → \(nombreCat(cat))"])
        if aplicar {
            try await opera(inst, ["op": "regla.aplica", "txt": t, "cat": cat,
                                   "resumen": "Aplicar «\(t)» a los gastos anteriores"])
        }
        await refresca(inst)
    }

    func aplicaRegla(_ r: ReglaGasto) async throws {
        let inst = instancia
        try await opera(inst, ["op": "regla.aplica", "txt": r.txt, "cat": r.cat,
                               "resumen": "Aplicar «\(r.txt)» a los gastos anteriores"])
        await refresca(inst)
    }

    func borraRegla(_ r: ReglaGasto) async throws {
        let inst = instancia
        try await opera(inst, ["op": "regla.borra", "id": r.id, "resumen": "Borrar la regla «\(r.txt)»"])
        await refresca(inst)
    }

    func ordenaReglas(_ ids: [String]) async throws {
        let inst = instancia
        try await opera(inst, ["op": "regla.ordena", "ids": ids, "resumen": "Cambiar la prioridad de las reglas"])
        await refresca(inst)
    }

    func rechazaRegla(_ txt: String, en inst: InstanciaGastos? = nil) async throws {
        let inst = inst ?? instancia
        try await opera(inst, ["op": "regla.rechaza", "txt": txt, "resumen": "No proponer «\(txt)»"])
        await refresca(inst)
    }

    /// Los recurrentes de la instancia, con lo confirmado o ignorado en este iPhone encima (también sin red).
    var recurrentes: [Recurrente] {
        let lista = resumen?.recurrentes ?? []
        guard let marcas = estado?.recurrentes else { return lista }
        return lista.map { r in
            var r = r
            r.estado = marcas[r.clave] ?? ""
            return r
        }
    }

    func marcaRecurrente(_ r: Recurrente, _ estado: String) async throws {
        let inst = instancia
        let que = estado == "si" ? "Confirmar" : estado == "no" ? "Ignorar" : "Deshacer"
        try await opera(inst, ["op": "recurrente.marca", "clave": r.clave, "estado": estado,
                               "resumen": "\(que) el recurrente \(r.n)"])
        await refresca(inst)
        AvisosRecurrentes.programa(inst, recurrentes)
    }
}

// MARK: bloque «Reglas» de la pantalla

struct BloqueReglas: View {
    @State private var datos = DatosGastos.shared
    @State private var gestion = false
    @State private var editando: PropuestaRegla?
    @State private var error: String?

    var body: some View {
        let props = datos.propuestas
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Reglas").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
                Spacer()
                Button {
                    Haptica.shared.toca(.marcar)
                    gestion = true
                } label: {
                    Text(datos.reglas.isEmpty ? "Ver" : "\(datos.reglas.count) regla\(datos.reglas.count == 1 ? "" : "s")")
                        .font(Tema.fuente(.pequeno, peso: .semibold)).foregroundStyle(Tema.acento)
                        .contentTransition(.numericText())
                }
                .accessibilityLabel("Gestionar las reglas de categoría")
            }
            if props.isEmpty {
                Text(datos.reglas.isEmpty
                     ? "Cuando corrijas la categoría de un gasto o se repita un comercio, Tom te propondrá una regla: «si dice mercadona → Súper»."
                     : "Las reglas ponen solas la categoría de lo que apuntas, de Telegram y de las capturas del banco.")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(props.prefix(3)) { p in
                FilaPropuesta(p: p, editar: { editando = p }, error: $error)
                    .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity)))
            }
            if props.count > 3 {
                Button("Ver las \(props.count) propuestas") { gestion = true }
                    .font(Tema.fuente(.pequeno, peso: .semibold)).foregroundStyle(Tema.acento)
            }
            if let error {
                Text(error).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .carta()
        .animation(Tema.Muelle.pantalla, value: props.map(\.id))
        .sheet(isPresented: $gestion) { HojaReglas() }
        .sheet(item: $editando) { p in
            EditorRegla(id: p.cambia, txt: p.txt, cat: p.cat, propuesta: true)
        }
    }
}

/// «Si el concepto contiene "mercadona" → Súper · 12 gastos encajan», con aceptar, editar y rechazar.
struct FilaPropuesta: View {
    let p: PropuestaRegla
    var instancia: InstanciaGastos?
    let editar: () -> Void
    @Binding var error: String?
    var alAcabar: () -> Void = {}
    @State private var datos = DatosGastos.shared
    @State private var trabajando = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            HStack(spacing: Tema.Espacio.s) {
                Circle().fill(datos.color(p.cat)).frame(width: 8, height: 8)
                (Text("Si el concepto contiene ").foregroundStyle(Tema.suave)
                 + Text("«\(p.txt)»").foregroundStyle(Tema.texto).bold()
                 + Text(" → ").foregroundStyle(Tema.suave)
                 + Text(datos.nombreCat(p.cat)).foregroundStyle(Tema.texto).bold())
                    .font(Tema.fuente(.texto))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(detalle).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Tema.Espacio.s) { botones }
                VStack(alignment: .leading, spacing: Tema.Espacio.s) { botones }
            }
            .disabled(trabajando)
        }
        .padding(Tema.Espacio.m)
        .background(Tema.acentoSuave.opacity(0.6), in: RoundedRectangle(cornerRadius: Tema.Radio.boton, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var detalle: String {
        var t = "\(p.encajan) gasto\(p.encajan == 1 ? "" : "s") encaja\(p.encajan == 1 ? "" : "n")"
        if !p.ejemplos.isEmpty { t += " (\(p.ejemplos.joined(separator: ", ")))" }
        if !p.cambia.isEmpty { t += ". Cambia la regla que ya tienes para «\(p.txt)»" }
        return t + "."
    }

    @ViewBuilder private var botones: some View {
        if p.cambiarian > 0 {
            boton("Aplicar también a \(p.cambiarian) anterior\(p.cambiarian == 1 ? "" : "es")", principal: true) { acepta(true) }
        }
        boton(p.cambiarian > 0 ? "Solo a los nuevos" : "Aceptar", principal: p.cambiarian == 0) { acepta(false) }
        HStack(spacing: Tema.Espacio.s) {
            boton("Editar", principal: false, accion: editar)
            boton("No, gracias", principal: false) { rechaza() }
        }
    }

    private func boton(_ titulo: String, principal: Bool, accion: @escaping () -> Void) -> some View {
        Button {
            Haptica.shared.toca(.marcar)
            accion()
        } label: {
            Text(titulo)
                .font(Tema.fuente(.pequeno, peso: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .foregroundStyle(principal ? Tema.acentoTexto : Tema.acento)
                .background(principal ? Tema.acento : Tema.carta, in: Capsule())
        }
        .buttonStyle(EstiloHundir())
    }

    private func acepta(_ aplicar: Bool) {
        trabajando = true
        Task {
            defer { trabajando = false }
            do {
                try await datos.ponRegla(id: p.cambia, txt: p.txt, cat: p.cat, aplicar: aplicar, en: instancia)
                error = nil
                alAcabar()
            } catch {
                Haptica.shared.toca(.error)
                self.error = DatosGastos.mensaje(error)
            }
        }
    }

    private func rechaza() {
        trabajando = true
        Task {
            defer { trabajando = false }
            do {
                try await datos.rechazaRegla(p.txt, en: instancia)
                Haptica.shared.toca(.desmarcar)
                error = nil
                alAcabar()
            } catch {
                Haptica.shared.toca(.error)
                self.error = DatosGastos.mensaje(error)
            }
        }
    }
}

/// La tarjeta de abajo tras corregir una categoría (o elegirla a mano al apuntar): «¿Siempre así?».
struct OfertaRegla: View {
    let oferta: ReglasTom.Oferta
    @State private var datos = DatosGastos.shared
    @State private var error: String?
    @State private var editando = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            HStack {
                Label("¿Siempre así?", systemImage: "wand.and.stars")
                    .font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
                Spacer()
                Button {
                    ReglasTom.shared.cierraOferta()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.suave)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Ahora no")
            }
            FilaPropuesta(p: oferta.propuesta, instancia: oferta.instancia, editar: { editando = true }, error: $error,
                          alAcabar: { ReglasTom.shared.cierraOferta() })
            if let error {
                Text(error).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro)
            }
        }
        .padding(Tema.Espacio.l)
        .background(Tema.carta, in: RoundedRectangle(cornerRadius: Tema.Radio.carta, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Tema.Radio.carta, style: .continuous).strokeBorder(Tema.linea, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.14), radius: 12, y: 3)
        .padding(.horizontal, Tema.Espacio.l)
        .padding(.bottom, 96)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .sheet(isPresented: $editando, onDismiss: { ReglasTom.shared.cierraOferta() }) {
            EditorRegla(id: oferta.propuesta.cambia, txt: oferta.propuesta.txt, cat: oferta.propuesta.cat, propuesta: true)
        }
    }
}

// MARK: gestionar las reglas

struct HojaReglas: View {
    @Environment(\.dismiss) private var cierra
    @State private var datos = DatosGastos.shared
    @State private var editando: ReglaGasto?
    @State private var nueva = false
    @State private var propuestaAbierta: PropuestaRegla?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                let props = datos.propuestas
                if !props.isEmpty {
                    Section {
                        ForEach(props) { p in
                            FilaPropuesta(p: p, editar: { propuestaAbierta = p }, error: $error)
                                .listRowBackground(Tema.carta)
                        }
                    } header: {
                        Text("Tom propone")
                    }
                }
                Section {
                    if datos.reglas.isEmpty {
                        Text("Aún no tienes reglas. Acepta una propuesta o crea una con «Nueva».")
                            .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                            .listRowBackground(Tema.carta)
                    }
                    ForEach(Array(datos.reglas.enumerated()), id: \.element.id) { i, r in
                        Button { editando = r } label: { fila(r, prioridad: i + 1) }
                            .listRowBackground(Tema.carta)
                            .swipeActions(edge: .leading) {
                                Button("Aplicar") { haz { try await datos.aplicaRegla(r) } }.tint(Tema.acento)
                            }
                    }
                    .onDelete { indices in
                        let quitar = indices.map { datos.reglas[$0] }
                        haz { for r in quitar { try await datos.borraRegla(r) } }
                    }
                    .onMove { desde, hasta in
                        var ids = datos.reglas.map(\.id)
                        ids.move(fromOffsets: desde, toOffset: hasta)
                        haz { try await datos.ordenaReglas(ids) }
                    }
                } header: {
                    Text("Tus reglas · \(datos.instancia.nombre)")
                } footer: {
                    Text("Se aplican solas a lo nuevo: lo que apuntas sin elegir categoría, Telegram, los tickets, Apple Pay y las capturas del banco. Si dos casan, gana la de más arriba (arrastra para cambiar la prioridad). Desliza a la derecha para aplicarla a los gastos de antes.")
                }
                if let error {
                    Text(error).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro).listRowBackground(Tema.carta)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Tema.fondo.ignoresSafeArea())
            .navigationTitle("Reglas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { cierra() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { nueva = true } label: { Label("Nueva", systemImage: "plus") }
                }
                ToolbarItem(placement: .bottomBar) { if !datos.reglas.isEmpty { EditButton() } }
            }
            .tint(Tema.acento)
        }
        .presentationBackground(Tema.fondo)
        .presentationDragIndicator(.visible)
        .sheet(item: $editando) { r in EditorRegla(id: r.id, txt: r.txt, cat: r.cat, propuesta: false) }
        .sheet(isPresented: $nueva) { EditorRegla(id: "", txt: "", cat: datos.categorias.first?.id ?? "otros", propuesta: false) }
        .sheet(item: $propuestaAbierta) { p in EditorRegla(id: p.cambia, txt: p.txt, cat: p.cat, propuesta: true) }
    }

    private func fila(_ r: ReglaGasto, prioridad: Int) -> some View {
        let n = datos.encajan(r.txt), pendientes = datos.cambiarian(r.txt, a: r.cat)
        return HStack(spacing: Tema.Espacio.m) {
            Circle().fill(datos.color(r.cat)).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text("«\(r.txt)» → \(datos.nombreCat(r.cat))").font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                Text("\(n) gasto\(n == 1 ? "" : "s") encaja\(n == 1 ? "" : "n")"
                     + (pendientes > 0 ? " · \(pendientes) con otra categoría" : ""))
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            }
            Spacer()
            Text("\(prioridad)").font(Tema.fuente(.pequeno)).monospacedDigit().foregroundStyle(Tema.tenue)
                .accessibilityLabel("Prioridad \(prioridad)")
        }
        .contentShape(Rectangle())
    }

    private func haz(_ trabajo: @escaping () async throws -> Void) {
        Task {
            do {
                try await trabajo()
                Haptica.shared.toca(.marcar)
                error = nil
            } catch {
                Haptica.shared.toca(.error)
                self.error = DatosGastos.mensaje(error)
            }
        }
    }
}

/// Crear, cambiar o aceptar (editada) una regla: el texto, la categoría y si se aplica a lo de antes.
struct EditorRegla: View {
    let id: String
    let propuesta: Bool
    @Environment(\.dismiss) private var cierra
    @State private var datos = DatosGastos.shared
    @State private var txt: String
    @State private var cat: String
    @State private var aplicar = true
    @State private var trabajando = false
    @State private var error: String?
    @State private var confirmaBorrar = false

    init(id: String, txt: String, cat: String, propuesta: Bool) {
        self.id = id
        self.propuesta = propuesta
        _txt = State(initialValue: txt)
        _cat = State(initialValue: cat)
    }

    private var existente: ReglaGasto? { id.isEmpty ? nil : datos.reglas.first { $0.id == id } }
    private var normal: String { ReglasGastos.norma(txt) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("mercadona", text: $txt)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(Tema.fuente(.texto))
                    Picker("Categoría", selection: $cat) {
                        ForEach(datos.categorias) { Text($0.n).tag($0.id) }
                    }
                } header: {
                    Text("Si el concepto contiene")
                } footer: {
                    Text(normal.isEmpty ? "El concepto es el comercio y la nota, sin tildes ni mayúsculas. Cuenta por palabras enteras: «bar» no casa con «barbería»."
                         : "Busca «\(normal)» por palabras enteras en el comercio y la nota. \(datos.encajan(normal)) gasto\(datos.encajan(normal) == 1 ? "" : "s") encaja\(datos.encajan(normal) == 1 ? "" : "n") ahora.")
                }
                let n = datos.cambiarian(normal, a: cat)
                if n > 0 {
                    Section {
                        Toggle("Aplicar también a \(n) gasto\(n == 1 ? "" : "s") anterior\(n == 1 ? "" : "es")", isOn: $aplicar)
                    } footer: {
                        Text("Pasan a \(datos.nombreCat(cat)) los que ya casan y tienen otra categoría.")
                    }
                }
                if existente != nil {
                    Section {
                        Button("Borrar la regla", role: .destructive) { confirmaBorrar = true }
                    }
                }
                if let error {
                    Text(error).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Tema.fondo.ignoresSafeArea())
            .navigationTitle(existente == nil ? (propuesta ? "Aceptar regla" : "Nueva regla") : "Cambiar regla")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cierra() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { guarda() } label: {
                        if trabajando { ProgressView() } else { Text("Guardar").fontWeight(.semibold) }
                    }
                    .disabled(normal.isEmpty || cat.isEmpty || trabajando)
                }
            }
            .confirmationDialog("¿Borrar la regla «\(normal)»?", isPresented: $confirmaBorrar, titleVisibility: .visible) {
                Button("Borrar", role: .destructive) { borra() }
                Button("Mejor no", role: .cancel) {}
            }
            .tint(Tema.acento)
        }
        .presentationBackground(Tema.fondo)
        .presentationDragIndicator(.visible)
    }

    private func guarda() {
        trabajando = true
        error = nil
        let aplica = aplicar && datos.cambiarian(normal, a: cat) > 0
        Task {
            defer { trabajando = false }
            do {
                try await datos.ponRegla(id: id, txt: normal, cat: cat, aplicar: aplica)
                Haptica.shared.toca(.marcar)
                cierra()
            } catch {
                Haptica.shared.toca(.error)
                self.error = DatosGastos.mensaje(error)
            }
        }
    }

    private func borra() {
        guard let r = existente else { return }
        trabajando = true
        Task {
            defer { trabajando = false }
            do {
                try await datos.borraRegla(r)
                Haptica.shared.toca(.desmarcar)
                cierra()
            } catch {
                Haptica.shared.toca(.error)
                self.error = DatosGastos.mensaje(error)
            }
        }
    }
}

// MARK: bloque «Recurrentes» (el id «suscripciones» de siempre)

struct RecurrentesGastos: View {
    @State private var datos = DatosGastos.shared
    @State private var verIgnorados = false
    @State private var error: String?

    var body: some View {
        let todos = datos.recurrentes
        let cuentan = todos.filter { $0.estado != "no" }, ignorados = todos.filter { $0.estado == "no" }
        let alMes = cuentan.reduce(0) { $0 + $1.alMes }
        if !todos.isEmpty {
            VStack(alignment: .leading, spacing: Tema.Espacio.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Recurrentes").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(Eur.texto(alMes)) al mes").font(Tema.fuente(.pequeno, peso: .semibold)).foregroundStyle(Tema.texto)
                        Text("\(Eur.entero(alMes * 12)) al año").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                    }
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityElement(children: .combine)
                }
                ForEach(cuentan) { r in fila(r) }
                if !ignorados.isEmpty {
                    Button {
                        withAnimation(Tema.Muelle.pantalla) { verIgnorados.toggle() }
                    } label: {
                        Label(verIgnorados ? "Ocultar los ignorados" : "Ignorados (\(ignorados.count))",
                              systemImage: verIgnorados ? "chevron.up" : "chevron.down")
                            .font(Tema.fuente(.pequeno, peso: .semibold)).foregroundStyle(Tema.suave)
                    }
                    if verIgnorados { ForEach(ignorados) { r in fila(r).opacity(0.55) } }
                }
                if let error {
                    Text(error).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro)
                }
            }
            .carta()
            .animation(Tema.Muelle.pantalla, value: todos.map { $0.clave + $0.estado })
        }
    }

    private func fila(_ r: Recurrente) -> some View {
        HStack(spacing: Tema.Espacio.m) {
            Circle().fill(datos.color(r.cat)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(r.n).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto).lineLimit(1)
                    if r.estado == "si" {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 12)).foregroundStyle(Tema.acento)
                            .accessibilityLabel("confirmado")
                    }
                }
                Text(subtitulo(r)).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Eur.texto(r.importe)).font(Tema.fuente(.texto)).monospacedDigit().foregroundStyle(Tema.texto)
                if r.cada != "mes" {
                    Text("\(Eur.texto(r.alMes))/mes").font(Tema.fuente(.etiqueta)).monospacedDigit().foregroundStyle(Tema.suave)
                }
            }
            Menu {
                if r.estado != "si" { Button("Confirmar: se cobra solo", systemImage: "checkmark.seal") { marca(r, "si") } }
                if r.estado != "no" { Button("Ignorar: no es recurrente", systemImage: "eye.slash") { marca(r, "no") } }
                if !r.estado.isEmpty { Button("Deshacer", systemImage: "arrow.uturn.backward") { marca(r, "") } }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 18)).foregroundStyle(Tema.suave)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Opciones de \(r.n)")
        }
        .accessibilityElement(children: .contain)
    }

    private func subtitulo(_ r: Recurrente) -> String {
        if r.estado == "no" { return "Ignorado: no cuenta en el total" }
        let hoy = Fecha.hoy(), manana = FechaGasto.desplaza(hoy, 1)
        let cuando = r.proximo == hoy ? "hoy" : r.proximo == manana ? "mañana" : r.proximo < hoy ? "tocaba el \(FechaGasto.corta(r.proximo))"
            : "el \(FechaGasto.corta(r.proximo))"
        return "\(r.periodo.prefix(1).uppercased() + r.periodo.dropFirst()) · próximo cargo \(cuando)"
    }

    private func marca(_ r: Recurrente, _ estado: String) {
        Haptica.shared.toca(estado == "no" ? .desmarcar : .marcar)
        Task {
            do { try await datos.marcaRecurrente(r, estado); error = nil }
            catch { Haptica.shared.toca(.error); self.error = DatosGastos.mensaje(error) }
        }
    }
}
