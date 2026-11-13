import Foundation
import SwiftUI
import Observation
import WidgetKit

/// Lo que enseña Gastos en nativo. Lee /resumen y /estado de la instancia elegida (por el proxy de todo; sin red, la
/// copia de Local) y escribe por los mismos caminos que la web: POST /gasto e /ingreso (a la cola si no hay red) y, para
/// editar o borrar, leer-modificar-escribir del estado entero (solo con red: un PUT de todo el estado hecho a ciegas
/// podría pisar lo que el bot apuntó mientras tanto).
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
    private var pendientes: [InstanciaGastos: [Movimiento]] = [:]
    private var enCurso = 0
    var cargando: Bool { enCurso > 0 }
    private(set) var error: String?

    /// El último borrado, para deshacerlo unos segundos.
    private(set) var borrado: (instancia: InstanciaGastos, crudo: [String: Any], texto: String)?
    private var tareaBorrado: Task<Void, Never>?

    private func clave(_ inst: InstanciaGastos, _ dia: String) -> String { "\(inst.rawValue)|\(dia)" }
    private func rutaResumen(_ inst: InstanciaGastos, _ dia: String) -> String { "\(inst.base)/resumen?dia=\(dia)" }

    // MARK: lo que se pinta

    var resumen: ResumenGastos? { resumenes[clave(instancia, ref)] }
    var estado: EstadoGastos? { estados[instancia] }
    /// La fecha de la copia si lo que se ve no viene fresco del servidor (sin red).
    var copia: Date? { copias[clave(instancia, ref)] }

    /// Los movimientos de la instancia, con los apuntados sin red delante.
    var movimientos: [Movimiento] {
        (pendientes[instancia] ?? []) + (estado?.gastos ?? [])
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
            if fecha == nil, Local.numeroPendientes() == 0 { pendientes[inst] = nil }
        } catch {
            if resumenes[clave(inst, dia)] == nil { self.error = Self.mensaje(error) }
            else { self.error = nil }
        }
        if let r = try? await API.leeOCopia("\(inst.base)/estado"),
           let e = try? JSONDecoder().decode(EstadoGastos.self, from: r.datos) {
            estados[inst] = e
        }
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
    func apunta(tipo: TipoApunte, importe: Double, nota: String, cat: String?, dia: String = Fecha.hoy()) async throws -> String {
        guard importe.isFinite, importe > 0 else { throw APIError(mensaje: "El importe tiene que ser mayor que cero") }
        let inst = instancia
        let redondeado = (importe * 100).rounded() / 100
        let id = (tipo == .gasto ? "app-" : "iapp-") + UUID().uuidString.prefix(8).lowercased()
        var json: [String: Any] = ["importe": redondeado, "src": "web", "dia": dia, "id": id]
        let limpia = nota.trimmingCharacters(in: .whitespacesAndNewlines)
        if !limpia.isEmpty { json["nota"] = limpia }
        if tipo != .extra, let cat, !cat.isEmpty { json["cat"] = cat }
        if tipo != .gasto { json["tipo"] = tipo.rawValue }
        let ruta = "\(inst.base)/\(tipo == .gasto ? "gasto" : "ingreso")"
        guard let crudo = try await API.escribeOEncola(ruta, json: json) else {
            if tipo == .gasto {
                var m = Movimiento(id: id, dia: dia, importe: redondeado, cat: cat ?? "", nota: limpia, pendiente: true)
                m.src = "web"
                withAnimation(Tema.Muelle.pantalla) { pendientes[inst, default: []].insert(m, at: 0) }
            }
            return "\(tipo.verbo) de \(Eur.texto(redondeado)). \(API.avisoEncolado)."
        }
        let objeto = try? JSONSerialization.jsonObject(with: crudo) as? [String: Any]
        let texto = (objeto?["texto"] as? String) ?? "Apuntado"
        // lo recién apuntado entra en el ciclo de hoy: se pide de nuevo ese (y se vuelve a él si se miraba otro)
        if inst == instancia, ref != Fecha.hoy() { withAnimation(Tema.Muelle.pantalla) { ref = Fecha.hoy() } }
        await carga()
        return texto
    }

    // MARK: editar y borrar (leer-modificar-escribir del estado entero)

    /// Trae el estado de ahora, lo cambia con `cambio` y lo guarda. Sin red no se hace: avisa y no toca nada.
    private func modifica(_ inst: InstanciaGastos, _ cambio: (inout [String: Any]) throws -> Void) async throws {
        do {
            let crudo = try await API.datos("\(inst.base)/estado")
            guard var e = try JSONSerialization.jsonObject(with: crudo) as? [String: Any] else {
                throw APIError(mensaje: "No entiendo lo que devuelve el servidor. Vuelve a probar en un momento.")
            }
            try cambio(&e)
            let guardado = try await API.datos("\(inst.base)/estado", metodo: "PUT", json: e)
            if let limpio = try? JSONDecoder().decode(EstadoGastos.self, from: guardado) {
                withAnimation(Tema.Muelle.pantalla) { estados[inst] = limpio }
            }
        } catch let e as APIError where e.sinRed {
            throw APIError(mensaje: "Sin conexión: para editar o borrar gastos hace falta red. Prueba otra vez cuando vuelva.")
        }
    }

    private func refresca(_ inst: InstanciaGastos) async {
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
    }

    func edita(_ m: Movimiento, _ c: Cambios) async throws {
        let inst = instancia
        try await modifica(inst) { e in
            var gastos = (e["gastos"] as? [[String: Any]]) ?? []
            guard let i = gastos.firstIndex(where: { ($0["id"] as? String) == m.id }) else {
                throw APIError(mensaje: "Ese gasto ya no está: alguien lo ha borrado. Recarga la lista.")
            }
            gastos[i]["importe"] = (c.importe * 100).rounded() / 100
            gastos[i]["dia"] = c.dia
            gastos[i]["cat"] = c.cat
            gastos[i]["comercio"] = c.comercio
            gastos[i]["nota"] = c.nota
            gastos[i]["viaje"] = c.viaje
            e["gastos"] = gastos
        }
        await refresca(inst)
    }

    func borra(_ m: Movimiento) async throws {
        let inst = instancia
        var quitado: [String: Any]?
        try await modifica(inst) { e in
            var gastos = (e["gastos"] as? [[String: Any]]) ?? []
            guard let i = gastos.firstIndex(where: { ($0["id"] as? String) == m.id }) else { return }
            quitado = gastos.remove(at: i)
            e["gastos"] = gastos
        }
        if let quitado {
            borrado = (inst, quitado, "Borrado: \(Eur.texto(m.importe))")
            tareaBorrado?.cancel()
            tareaBorrado = Task { [weak self] in
                try? await Task.sleep(for: .seconds(7))
                guard !Task.isCancelled else { return }
                await MainActor.run { withAnimation(Tema.Muelle.pantalla) { self?.borrado = nil } }
            }
        }
        await refresca(inst)
    }

    func deshazBorrado() async throws {
        guard let b = borrado else { return }
        tareaBorrado?.cancel()
        withAnimation(Tema.Muelle.pantalla) { borrado = nil }
        try await modifica(b.instancia) { e in
            var gastos = (e["gastos"] as? [[String: Any]]) ?? []
            if !gastos.contains(where: { ($0["id"] as? String) == (b.crudo["id"] as? String) }) { gastos.append(b.crudo) }
            e["gastos"] = gastos
        }
        await refresca(b.instancia)
    }

    // MARK: presupuestos

    func ponPresupuesto(_ cat: String, _ valor: Double) async throws {
        let inst = instancia
        try await modifica(inst) { e in
            var cats = (e["cats"] as? [[String: Any]]) ?? []
            guard let i = cats.firstIndex(where: { ($0["id"] as? String) == cat }) else { return }
            cats[i]["presu"] = max(0, valor)
            e["cats"] = cats
        }
        await refresca(inst)
    }

    /// «Usar sugeridos»: copia el presupuesto sugerido de cada categoría que tenga uno.
    func usaSugeridos() async throws {
        let inst = instancia
        let sugeridos = Dictionary(uniqueKeysWithValues: (resumen?.cats ?? []).filter { $0.sugerido > 0 }.map { ($0.id, $0.sugerido) })
        try await modifica(inst) { e in
            var cats = (e["cats"] as? [[String: Any]]) ?? []
            for i in cats.indices {
                if let id = cats[i]["id"] as? String, let s = sugeridos[id] { cats[i]["presu"] = s }
            }
            e["cats"] = cats
        }
        await refresca(inst)
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
