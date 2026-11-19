import Foundation
import SwiftUI
import Observation
import UIKit

// Los datos del calendario: GET /api/calendario por rangos (sin red, la copia de ese rango) y crear, cambiar o
// borrar eventos por la cola. Tareas y recordatorios van por /api/tarea, como en Pendientes.

@MainActor @Observable
final class DatosCalendario {
    static let shared = DatosCalendario()

    private(set) var calendarios: [CalendarioTom] = []
    private(set) var eventos: [EventoCal] = []
    /// «Mercados» (BCE, Fed, resultados): aparte, y solo se ve con el interruptor (casi siempre apagado)
    private(set) var mercado: [EventoCal] = []
    var verMercado = Almacen.defaults.bool(forKey: "calMercado") {
        didSet { Almacen.defaults.set(verMercado, forKey: "calMercado") }
    }
    /// Lo que se pinta: tus eventos y, con el interruptor, los de «Mercados».
    var visibles: [EventoCal] {
        verMercado ? (eventos + mercado).sorted { ($0.dia, $0.inicio) < ($1.dia, $1.inicio) } : eventos
    }
    private(set) var tareas: [TareaCal] = []
    private(set) var hoy = UtilCal.hoy()
    /// Lo que hay cargado: de `desde` a `hasta`, los dos incluidos.
    private(set) var desde = ""
    private(set) var hasta = ""
    private(set) var copia: Date?
    private(set) var cargando = false
    private(set) var error: String?
    var aviso: AvisoTom?

    /// El rango que se pide de una vez: desde una semana antes del mes hasta 12 semanas después (cubre Mes,
    /// Semana y la Agenda sin pedir a cada paso). Siempre el mismo para el mismo mes, así la copia sin red se encuentra.
    private static func rango(para dia: String) -> (String, String) {
        let d = UtilCal.suma(UtilCal.inicioMes(dia), dias: -7)
        return (d, UtilCal.suma(d, dias: 91))
    }

    private static func ruta(_ d: String, _ h: String) -> String { "/api/calendario?desde=\(d)&hasta=\(h)" }

    init() {
        let (d, h) = Self.rango(para: UtilCal.hoy())
        if let r = Local.lee(Local.clave("GET", Self.ruta(d, h))),
           let x = try? JSONDecoder().decode(RespuestaCal.self, from: r.cuerpo) {
            pon(x, d, h)
            copia = r.fecha
        }
    }

    private func pon(_ x: RespuestaCal, _ d: String, _ h: String) {
        calendarios = x.calendarios ?? calendarios
        eventos = (x.eventos ?? []).sorted { ($0.dia, $0.inicio) < ($1.dia, $1.inicio) }
        tareas = x.tareas ?? []
        mercado = x.mercado ?? []
        if let delServidor = x.hoy, !delServidor.isEmpty { hoy = delServidor }
        desde = d
        hasta = h
    }

    func color(_ cal: String) -> Color {
        if cal == "mercado" { return Color(hex: "#64748B") }
        return calendarios.first { $0.id == cal }?.tinta ?? Tema.acento
    }

    func calendario(_ id: String) -> CalendarioTom? { calendarios.first { $0.id == id } }

    /// Que esté cargado lo que va de `a` a `b` (si no, se pide el rango del mes de `a`).
    func asegura(_ a: String, _ b: String) async {
        if !desde.isEmpty && desde <= a && b <= hasta { return }
        await carga(alrededor: a)
    }

    func recarga() async { await carga(alrededor: desde.isEmpty ? UtilCal.hoy() : UtilCal.suma(desde, dias: 7)) }

    func carga(alrededor dia: String) async {
        guard !cargando else { return }
        cargando = true
        defer { cargando = false }
        let (d, h) = Self.rango(para: dia)
        do {
            let (crudo, fecha) = try await API.leeOCopia(Self.ruta(d, h))
            let x = try JSONDecoder().decode(RespuestaCal.self, from: crudo)
            // lo creado sin red sigue a la vista hasta que salga de la cola
            let esperando = fecha == nil ? [] : eventos.filter(\.provisional)
            let tareasEsperando = fecha == nil ? [] : tareas.filter(\.provisional)
            withAnimation(Tema.Muelle.pantalla) {
                pon(x, d, h)
                eventos += esperando
                tareas += tareasEsperando
            }
            copia = fecha
            error = nil
        } catch let e as DecodingError {
            error = "No entiendo lo que devuelve /api/calendario (\(e.localizedDescription))"
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: lo de un día

    func elementos(_ dia: String) -> [ElementoDiaCal] {
        let es = visibles.filter { $0.cubre(dia) }.map { ElementoDiaCal.evento($0) }
        let ts = tareas.filter { $0.due == dia }.map { ElementoDiaCal.tarea($0) }
        return (es + ts).sorted { $0.orden < $1.orden }
    }

    /// Los colores de los puntos de un día en la vista Mes (como mucho 4: uno por calendario, y uno para tareas).
    func puntos(_ dia: String) -> [Color] {
        var vistos: [String] = []
        for e in visibles where e.cubre(dia) && !vistos.contains(e.cal) { vistos.append(e.cal) }
        var out = vistos.prefix(3).map { color($0) }
        if tareas.contains(where: { $0.due == dia && !$0.hecha }) { out.append(Tema.suave) }
        return Array(out.prefix(4))
    }

    // MARK: avisos

    func avisa(_ texto: String, error: Bool = false, deshacer: (@MainActor () async -> Void)? = nil) {
        aviso = AvisoTom(texto: texto, error: error, deshacer: deshacer)
        AccessibilityNotification.Announcement(texto).post()
        Haptica.shared.toca(error ? .error : .dia)
    }

    func quitaAviso() { aviso = nil }

    private static func objeto(_ datos: Data?) -> [String: Any]? {
        datos.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    // MARK: eventos

    /// `campos`: t, dia, fin_dia, inicio, fin, cal, nota, lugar, aviso, repite, hasta.
    @discardableResult
    func creaEvento(_ campos: [String: Any]) async -> Bool {
        do {
            let r = try await API.escribeOEncola("/api/evento", json: campos)
            if r == nil {
                withAnimation(Tema.Muelle.pantalla) { eventos.append(Self.provisional(campos)) }
                avisa(API.avisoEncolado)
            } else {
                avisa("Evento apuntado")
                await recarga()
            }
            return true
        } catch {
            avisa("No se ha apuntado: \(error.localizedDescription)", error: true)
            return false
        }
    }

    private static func provisional(_ c: [String: Any]) -> EventoCal {
        func s(_ k: String) -> String { (c[k] as? String) ?? "" }
        return EventoCal(id: "tmp:\(UUID().uuidString)", t: s("t"), dia: s("dia"), finDia: s("fin_dia"),
                         inicio: s("inicio"), fin: s("fin"), cal: s("cal"), nota: s("nota"), lugar: s("lugar"),
                         aviso: (c["aviso"] as? Int) ?? -1, repite: s("repite"), hasta: s("hasta"),
                         sincro: SincroCal(google: "pendiente", icloud: "pendiente"))
    }

    /// Cambia la serie entera (todas las repeticiones).
    @discardableResult
    func editaEvento(_ id: String, _ campos: [String: Any]) async -> Bool {
        var json = campos
        json["id"] = id
        do {
            let r = try await API.escribeOEncola("/api/evento/edita", json: json)
            if r == nil {
                withAnimation(Tema.Muelle.pantalla) {
                    for i in eventos.indices where eventos[i].id == id {
                        var e = Self.provisional(campos)
                        e.id = id
                        e.dia = eventos[i].dia == eventos[i].origen ? e.dia : eventos[i].dia
                        eventos[i] = e
                    }
                }
                avisa("Cambiado. Se enviará en cuanto haya conexión")
            } else {
                avisa("Evento cambiado")
                await recarga()
            }
            return true
        } catch {
            avisa("No se ha cambiado: \(error.localizedDescription)", error: true)
            return false
        }
    }

    func borraEvento(_ e: EventoCal) async {
        let antes = eventos
        withAnimation(Tema.Muelle.pantalla) { eventos.removeAll { $0.id == e.id } }
        if e.provisional { return }
        do {
            let r = try await API.escribeOEncola("/api/evento/borra", json: ["id": e.id])
            guard let o = Self.objeto(r), let borrado = o["evento"] as? [String: Any] else {
                avisa("Borrado. Se enviará en cuanto haya conexión")
                return
            }
            avisa(e.repite.isEmpty ? "Evento borrado" : "Serie borrada", deshacer: { [weak self] in
                await self?.restaura(borrado)
            })
        } catch {
            withAnimation(Tema.Muelle.pantalla) { eventos = antes }
            avisa("No se ha borrado: \(error.localizedDescription)", error: true)
        }
    }

    private func restaura(_ evento: [String: Any]) async {
        do {
            _ = try await API.datos("/api/evento/restaura", metodo: "POST", json: ["evento": evento])
            await recarga()
        } catch {
            avisa("No se ha podido deshacer: \(error.localizedDescription)", error: true)
        }
    }

    /// Arrastrar en la semana (o cambiar de día) sin abrir la hoja: mueve la serie entera a ese día y hora.
    func mueve(_ e: EventoCal, a dia: String, inicio: String?) async {
        let dur = (UtilCal.minutos(e.fin) ?? 0) - (UtilCal.minutos(e.inicio) ?? 0)
        let dias = max(0, Calendar.current.dateComponents([.day], from: UtilCal.fecha(e.dia), to: UtilCal.fecha(e.finDia)).day ?? 0)
        var c = Self.campos(e)
        // el desplazamiento se aplica a la serie: si mueves una repetición, se mueve el origen lo mismo
        let salto = Calendar.current.dateComponents([.day], from: UtilCal.fecha(e.dia), to: UtilCal.fecha(dia)).day ?? 0
        let origen = UtilCal.suma(e.origen, dias: salto)
        c["dia"] = origen
        c["fin_dia"] = UtilCal.suma(origen, dias: dias)
        if let inicio, !e.todoElDia, let m = UtilCal.minutos(inicio) {
            c["inicio"] = inicio
            c["fin"] = e.fin.isEmpty ? "" : UtilCal.hhmm(m + max(15, dur))
        }
        await editaEvento(e.id, c)
    }

    /// Los campos de un evento como los pide la API (para editar partiendo de él).
    static func campos(_ e: EventoCal) -> [String: Any] {
        ["t": e.t, "dia": e.origen, "fin_dia": UtilCal.suma(e.origen, dias: Calendar.current.dateComponents(
            [.day], from: UtilCal.fecha(e.dia), to: UtilCal.fecha(e.finDia)).day ?? 0),
         "inicio": e.inicio, "fin": e.fin, "cal": e.cal, "nota": e.nota, "lugar": e.lugar,
         "aviso": e.aviso, "repite": e.repite, "hasta": e.hasta]
    }

    // MARK: tareas y recordatorios

    /// Con hora es un recordatorio (el bot avisa a esa hora).
    @discardableResult
    func creaTarea(_ t: String, dia: String, hora: String) async -> Bool {
        let limpio = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty else { return false }
        do {
            let r = try await API.escribeOEncola("/api/tarea", json: ["t": limpio, "due": dia, "hora": hora])
            if r == nil {
                withAnimation(Tema.Muelle.pantalla) {
                    tareas.append(TareaCal(id: "tmp:\(UUID().uuidString)", t: limpio, due: dia, hora: hora))
                }
                avisa(API.avisoEncolado)
            } else {
                avisa(hora.isEmpty ? "Tarea apuntada" : "Recordatorio apuntado: te aviso a las \(hora)")
                await recarga()
            }
            await DatosPendientes.shared.recarga()
            return true
        } catch {
            avisa("No se ha apuntado: \(error.localizedDescription)", error: true)
            return false
        }
    }

    func marca(_ t: TareaCal, hecha: Bool) async {
        guard !t.provisional, let i = tareas.firstIndex(where: { $0.id == t.id }) else { return }
        withAnimation(Tema.Muelle.toque) { tareas[i].hecha = hecha }
        Haptica.shared.toca(hecha ? .marcar : .desmarcar)
        do {
            let r = try await API.escribeOEncola("/api/tarea/hecha", json: ["id": t.id, "hecha": hecha])
            // el id cambia al tacharla (va por la línea del vault): con el nuevo, se puede volver a desmarcar
            if let o = Self.objeto(r), let nuevo = o["id"] as? String, let j = tareas.firstIndex(where: { $0.id == t.id }) {
                tareas[j].id = nuevo
            }
            await DatosPendientes.shared.recarga()
        } catch {
            if let j = tareas.firstIndex(where: { $0.id == t.id }) { tareas[j].hecha = !hecha }
            avisa("No se ha marcado: \(error.localizedDescription)", error: true)
        }
    }
}
