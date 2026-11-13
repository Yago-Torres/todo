import Foundation
import SwiftUI
import Observation
import WidgetKit

/// Lo que enseña Gastos en nativo. Lee /resumen y /estado de la instancia elegida (por el proxy de todo; sin red, la
/// copia de Local) y escribe por los mismos caminos que la web: POST /gasto e /ingreso (a la cola si no hay red) y, para
/// editar, borrar y los presupuestos, operaciones de la cola (Compartido/Operaciones.swift): se ven al momento y Sincro
/// las aplica sobre el estado fresco del servidor, así que tampoco necesitan red ni pisan lo que el bot apuntó.
///
/// Las dos instancias (Yago y Aitana) tienen cada una sus copias en memoria y en Local; ninguna cuenta se suma con la otra.
@MainActor @Observable
final class DatosGastos {
    static let shared = DatosGastos()

    var instancia: InstanciaGastos = .yago
    /// Un día cualquiera del ciclo que se mira (hoy, o uno anterior al navegar).
    var ref: String = Fecha.hoy()

    private var resumenes: [String: ResumenGastos] = [:]
    private var estados: [InstanciaGastos: EstadoGastos] = [:]
    private var copias: [String: Date] = [:]
    /// Los ids apuntados sin red que aún esperan en la cola (salen con «Sin enviar»).
    private var enCola: Set<String> = []
    private var enCurso = 0
    var cargando: Bool { enCurso > 0 }
    private(set) var error: String?

    /// Lo último que se puede deshacer unos segundos (un borrado, lo recién apuntado, un viaje…): el texto del aviso y
    /// la operación de la cola que lo deshace.
    private(set) var borrado: (instancia: InstanciaGastos, deshacer: [String: Any], texto: String)?
    private var tareaBorrado: Task<Void, Never>?

    private func clave(_ inst: InstanciaGastos, _ dia: String) -> String { "\(inst.rawValue)|\(dia)" }
    private func rutaResumen(_ inst: InstanciaGastos, _ dia: String) -> String { "\(inst.base)/resumen?dia=\(dia)" }

    // MARK: lo que se pinta

    var resumen: ResumenGastos? { resumenes[clave(instancia, ref)] }
    var estado: EstadoGastos? { estados[instancia] }
    /// La fecha de la copia si lo que se ve no viene fresco del servidor (sin red).
    var copia: Date? { copias[clave(instancia, ref)] }

    /// Los movimientos de la instancia (la copia local ya lleva los apuntados sin red).
    var movimientos: [Movimiento] {
        (estado?.gastos ?? []).map { m in
            var m = m
            m.pendiente = enCola.contains(m.id)
            return m
        }
    }

    /// Qué gastos siguen en la cola sin salir.
    private func miraCola() {
        enCola = Set(Local.cambios().filter { $0.estado == .pendiente && $0.metodo == "POST" && $0.rutaSinQuery.hasSuffix("/gasto") }
            .compactMap { c in (c.cuerpo.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])?["id"] as? String })
    }

    /// La copia local del estado de `inst` (con lo pendiente encima), a la pantalla.
    private func pintaLocal(_ inst: InstanciaGastos) {
        miraCola()
        if let r = Local.lee(Local.clave("GET", "\(inst.base)/estado")),
           let e = try? JSONDecoder().decode(EstadoGastos.self, from: r.cuerpo) {
            withAnimation(Tema.Muelle.pantalla) { estados[inst] = e }
        }
    }

    func nombreCat(_ id: String) -> String {
        resumen?.cats.first { $0.id == id }?.n ?? estado?.cats.first { $0.id == id }?.n ?? id
    }

    /// Posición de la categoría en la lista (le da su color).
    func indiceCat(_ id: String) -> Int {
        let ids = estado?.cats.map(\.id) ?? resumen?.cats.map(\.id) ?? []
        return ids.firstIndex(of: id) ?? 0
    }

    /// Las categorías para elegir (id y nombre), en el orden del servidor.
    var categorias: [OpcionCat] {
        if let e = estado, !e.cats.isEmpty { return e.cats.map { OpcionCat(id: $0.id, n: $0.n) } }
        return (resumen?.cats ?? []).map { OpcionCat(id: $0.id, n: $0.n) }
    }

    func nombreViaje(_ id: String) -> String { estado?.viajes.first { $0.id == id }?.n ?? "" }

    func color(_ cat: String) -> Color { SerieGastos.color(indiceCat(cat)) }

    // MARK: cargar

    /// Pinta al momento lo último guardado (si lo hay) y luego pide lo de ahora.
    func carga(margen: TimeInterval = 0) async {
        let inst = instancia, dia = ref
        pintaGuardado(inst, dia)
        enCurso += 1
        defer { enCurso -= 1 }
        do {
            let (crudo, fecha) = try await API.leeOCopia(rutaResumen(inst, dia))
            let r = try JSONDecoder().decode(ResumenGastos.self, from: crudo)
            let k = clave(inst, dia)
            withAnimation(Tema.Muelle.pantalla) { resumenes[k] = r }
            copias[k] = fecha
            error = nil
            AvisosRecurrentes.programa(inst, r.recurrentes)
        } catch {
            if resumenes[clave(inst, dia)] == nil { self.error = Self.mensaje(error) }
            else { self.error = nil }
        }
        if let r = try? await API.leeOCopia("\(inst.base)/estado"),
           let e = try? JSONDecoder().decode(EstadoGastos.self, from: r.datos) {
            estados[inst] = e
        }
        await ReglasTom.shared.carga(inst)
        miraCola()
        if inst == .yago { WidgetCenter.shared.reloadAllTimelines() }
    }

    func recarga() async { await carga() }

    /// Lo guardado del ciclo que se ve, ya en memoria antes de abrir la pantalla (Precarga).
    func precarga() { pintaGuardado(instancia, ref) }

    private func pintaGuardado(_ inst: InstanciaGastos, _ dia: String) {
        let k = clave(inst, dia)
        if resumenes[k] == nil, let r = Local.lee(Local.clave("GET", rutaResumen(inst, dia))),
           let d = try? JSONDecoder().decode(ResumenGastos.self, from: r.cuerpo) {
            resumenes[k] = d
            copias[k] = r.fecha
        }
        if estados[inst] == nil, let r = Local.lee(Local.clave("GET", "\(inst.base)/estado")),
           let e = try? JSONDecoder().decode(EstadoGastos.self, from: r.cuerpo) {
            estados[inst] = e
        }
    }

    /// Cambia de ciclo (-1 el anterior, +1 el siguiente) apoyándose en las fechas del que se ve.
    func ciclo(_ paso: Int) async {
        guard let r = resumen else { return }
        let nuevo = paso < 0 ? FechaGasto.desplaza(r.inicio, -1) : FechaGasto.desplaza(r.fin, 1)
        if paso > 0, nuevo > Fecha.hoy() { return }
        withAnimation(Tema.Muelle.pantalla) { ref = nuevo }
        await carga()
    }

    func vuelveAHoy() async {
        withAnimation(Tema.Muelle.pantalla) { ref = Fecha.hoy() }
        await carga()
    }

    func cambia(a inst: InstanciaGastos) async {
        guard inst != instancia else { return }
        withAnimation(Tema.Muelle.pantalla) {
            instancia = inst
            ref = Fecha.hoy()
            error = nil
        }
        await carga()
    }

    // MARK: apuntar

    /// Apunta un gasto (o un ingreso). Devuelve el texto del servidor (con los avisos de presupuesto) o el aviso de que
    /// se enviará al volver la conexión.
    func apunta(tipo: TipoApunte, importe: Double, nota: String, cat: String?, dia: String = Fecha.hoy(),
                extra: [String: Any] = [:]) async throws -> String {
        guard importe.isFinite, importe > 0 else { throw APIError(mensaje: "El importe tiene que ser mayor que cero") }
        let inst = instancia
        let redondeado = (importe * 100).rounded() / 100
        let id = (tipo == .gasto ? "app-" : "iapp-") + UUID().uuidString.prefix(8).lowercased()
        var json: [String: Any] = ["importe": redondeado, "src": "web", "dia": dia, "id": id]
        let limpia = nota.trimmingCharacters(in: .whitespacesAndNewlines)
        if !limpia.isEmpty { json["nota"] = limpia }
        if tipo != .extra, let cat, !cat.isEmpty { json["cat"] = cat }
        if tipo != .gasto { json["tipo"] = tipo.rawValue }
        for (k, v) in extra { json[k] = v }   // moneda, viaje, reparto (saldar un viaje compartido)
        let ruta = "\(inst.base)/\(tipo == .gasto ? "gasto" : "ingreso")"
        let quitar: [String: Any] = tipo == .gasto
            ? ["op": "gasto.borra", "id": id, "resumen": "Quitar el gasto de \(Eur.texto(redondeado))"]
            : ["op": "ingreso.borra", "id": id, "resumen": "Quitar el ingreso de \(Eur.texto(redondeado))"]
        guard let crudo = try await API.escribeOEncola(ruta, json: json) else {
            pintaLocal(inst)   // la copia local ya lo lleva (Operaciones)
            ofreceDeshacer(inst, "Apuntado: \(Eur.texto(redondeado))", quitar)
            return "\(tipo.verbo) de \(Eur.texto(redondeado)). \(API.avisoEncolado)."
        }
        let objeto = try? JSONSerialization.jsonObject(with: crudo) as? [String: Any]
        let texto = (objeto?["texto"] as? String) ?? "Apuntado"
        // elegiste la categoría a mano y no es lo que saldría solo: ¿hacer regla?
        if let p = objeto?["propuesta"] as? [String: Any], let d = try? JSONSerialization.data(withJSONObject: p),
           let propuesta = try? JSONDecoder().decode(PropuestaRegla.self, from: d) {
            ReglasTom.shared.ofrece(propuesta, en: inst)
        }
        // lo recién apuntado entra en el ciclo de hoy: se pide de nuevo ese (y se vuelve a él si se miraba otro)
        if inst == instancia, ref != Fecha.hoy() { withAnimation(Tema.Muelle.pantalla) { ref = Fecha.hoy() } }
        await carga()
        ofreceDeshacer(inst, "Apuntado: \(Eur.texto(redondeado))", quitar)
        return texto
    }

    // MARK: editar y borrar (operaciones de la cola)

    /// Apunta la operación sobre el estado de `inst`, la pinta y la manda. Con red espera a que llegue y, si el servidor
    /// la rechaza (el gasto ya no está…), lanza el motivo. Sin red vuelve enseguida: sale sola al volver la conexión.
    @discardableResult
    func opera(_ inst: InstanciaGastos, _ op: [String: Any]) async throws -> Bool {
        guard let id = Operaciones.encola("\(inst.base)/estado", op) else {
            throw APIError(mensaje: "No he podido guardar el cambio en el iPhone. Desbloquéalo y vuelve a probar.")
        }
        pintaLocal(inst)
        await Sincro.vacia()
        pintaLocal(inst)
        guard let c = Local.cambio(id) else { return false }
        if c.estado != .pendiente { throw APIError(mensaje: c.error ?? "El servidor no ha aceptado el cambio.") }
        return true
    }

    /// Sin red, el resumen (lo calcula el servidor) no se entera del presupuesto nuevo: se le pone a mano en pantalla.
    private func ponEnResumen(_ valores: [String: Double]) {
        let k = clave(instancia, ref)
        guard var r = resumenes[k] else { return }
        for i in r.cats.indices { if let v = valores[r.cats[i].id] { r.cats[i].presu = v } }
        r.presu = r.cats.reduce(0) { $0 + $1.presu }
        withAnimation(Tema.Muelle.pantalla) { resumenes[k] = r }
    }

    func refresca(_ inst: InstanciaGastos) async {
        guard inst == instancia else { return }
        await carga()
    }

    struct Cambios {
        var importe: Double
        var dia: String
        var cat: String
        var comercio: String
        var nota: String
        var viaje: String
        var reparto: String = "medias"
    }

    func edita(_ m: Movimiento, _ c: Cambios) async throws {
        let inst = instancia
        let importe = (c.importe * 100).rounded() / 100
        let cambios: [String: Any] = ["importe": importe, "dia": c.dia, "cat": c.cat, "comercio": c.comercio,
                                      "nota": c.nota, "viaje": c.viaje, "reparto": c.reparto]
        try await opera(inst, ["op": "gasto.edita", "id": m.id, "cambios": cambios,
                               "resumen": "Cambiar el gasto de \(Eur.texto(importe))"])
        await refresca(inst)
        // corregiste la categoría: ¿que sea así siempre?
        if c.cat != m.cat, let p = propuestaTrasCorregir(comercio: c.comercio, nota: c.nota, cat: c.cat) {
            ReglasTom.shared.ofrece(p, en: inst)
        }
    }

    func borra(_ m: Movimiento) async throws {
        let inst = instancia
        // lo que había, para poder deshacerlo (de la copia local: con o sin red)
        let quitado = Local.lee(Local.clave("GET", "\(inst.base)/estado"))
            .flatMap { (try? JSONSerialization.jsonObject(with: $0.cuerpo)) as? [String: Any] }
            .flatMap { ($0["gastos"] as? [[String: Any]])?.first { ($0["id"] as? String) == m.id } }
        try await opera(inst, ["op": "gasto.borra", "id": m.id, "resumen": "Borrar el gasto de \(Eur.texto(m.importe))"])
        if let quitado {
            ofreceDeshacer(inst, "Borrado: \(Eur.texto(m.importe))",
                           ["op": "gasto.restaura", "id": m.id, "gasto": quitado, "resumen": "Recuperar un gasto borrado"])
        }
        await refresca(inst)
    }

    /// Enseña «Deshacer» siete segundos; al tocarlo se manda `op` (por la cola, como todo).
    func ofreceDeshacer(_ inst: InstanciaGastos, _ texto: String, _ op: [String: Any]) {
        withAnimation(Tema.Muelle.pantalla) { borrado = (inst, op, texto) }
        tareaBorrado?.cancel()
        tareaBorrado = Task { [weak self] in
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled else { return }
            await MainActor.run { withAnimation(Tema.Muelle.pantalla) { self?.borrado = nil } }
        }
    }

    func deshazBorrado() async throws {
        guard let b = borrado else { return }
        tareaBorrado?.cancel()
        withAnimation(Tema.Muelle.pantalla) { borrado = nil }
        try await opera(b.instancia, b.deshacer)
        await refresca(b.instancia)
    }

    // MARK: presupuestos

    func ponPresupuesto(_ cat: String, _ valor: Double) async throws {
        let inst = instancia
        let enCola = try await opera(inst, ["op": "presupuesto.pon", "valores": [cat: max(0, valor)],
                                            "resumen": "Presupuesto de \(nombreCat(cat)): \(Eur.texto(max(0, valor)))"])
        await refresca(inst)
        if enCola { ponEnResumen([cat: max(0, valor)]) }
    }

    /// «Usar sugeridos»: copia el presupuesto sugerido de cada categoría que tenga uno.
    func usaSugeridos() async throws {
        let inst = instancia
        let sugeridos = Dictionary(uniqueKeysWithValues: (resumen?.cats ?? []).filter { $0.sugerido > 0 }.map { ($0.id, $0.sugerido) })
        guard !sugeridos.isEmpty else { return }
        let enCola = try await opera(inst, ["op": "presupuesto.pon", "valores": sugeridos, "resumen": "Usar los presupuestos sugeridos"])
        await refresca(inst)
        if enCola { ponEnResumen(sugeridos) }
    }

    static func mensaje(_ error: Error) -> String {
        if let e = error as? APIError { return e.mensaje }
        if error is DecodingError { return "No entiendo lo que devuelve el servidor de gastos." }
        return error.localizedDescription
    }
}

enum TipoApunte: String, CaseIterable, Identifiable {
    case gasto, devuelve, extra
    var id: String { rawValue }

    var nombre: String {
        switch self {
        case .gasto: return "Gasto"
        case .devuelve: return "Me devuelven"
        case .extra: return "Ingreso"
        }
    }

    var verbo: String { self == .gasto ? "Gasto" : "Ingreso" }
}

struct OpcionCat: Identifiable, Hashable {
    var id: String
    var n: String
}
