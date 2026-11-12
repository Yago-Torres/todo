import AudioToolbox
import Foundation
import Observation
import SwiftUI
import UIKit

/// El modo entreno serie a serie, en nativo: la sesión abierta (en `gym` de hoy, como la web), lo escrito en cada
/// fila, el descanso con su cuenta atrás y la Live Activity. Lo que está en marcha se apunta en el iPhone
/// («entreno.enMarcha», como el localStorage «entreno-en-marcha» de la web) para reabrirlo si iOS mata la app.
@MainActor @Observable
final class SesionEnCurso {
    static let shared = SesionEnCurso()

    struct Descanso: Equatable {
        var fin: Date
        var total: Int
    }

    /// Lo que toca ahora (lo mismo que manda la web a la isla).
    struct Toca: Equatable {
        var ejercicio: String
        var serie: Int        // la que toca, de 1 a total (0 si no queda)
        var total: Int
        var detalle: String
        var descanso: Int
        var hecho: Bool
        var indice: Int { serie - 1 }
    }

    private(set) var sesionId: String?
    private(set) var dia = Fecha.hoy()
    var visible = false
    /// Filas de más por ejercicio («+ serie»).
    var extra: [String: Int] = [:]
    private(set) var descanso: Descanso?
    /// Lo escrito en cada fila: «kg|ejercicio|i» y «rep|ejercicio|i».
    var borradores: [String: String] = [:]
    /// La fila a la que llevar el foco (faltan las repes).
    var pideRepes: String?
    /// Sube con cada récord, para celebrarlo en pantalla.
    private(set) var records = 0

    @ObservationIgnored private var bucle: Task<Void, Never>?
    @ObservationIgnored private var ultimoPip = 0
    private let datos = DatosEntreno.shared

    private static let claveMarcha = "entreno.enMarcha"

    private init() {}

    // MARK: lo que se lee

    var sesion: SesionGym? {
        guard let sesionId else { return nil }
        return datos.e.sesionGym(dia, sesionId)
    }

    var rutina: RutinaGym? { sesion.flatMap { datos.e.rutina($0.rutina) } }

    /// Lo de hoy: la rutina sin lo quitado y, detrás, lo añadido. La rutina en sí no cambia.
    var bloques: [(b: BloqueGym, extra: Bool)] {
        guard let s = sesion else { return [] }
        let deRutina = rutina?.bloques ?? []
        let nombres = Set(deRutina.map(\.ej))
        let quita = Set(s.quita)
        var out = deRutina.filter { !quita.contains($0.ej) }.map { (b: $0, extra: false) }
        for e in s.ej where !nombres.contains(e.ej) {
            var b = datos.e.molde(e.ej)
            b.ej = e.ej
            out.append((b: b, extra: true))
        }
        return out
    }

    func hechas(_ ej: String) -> [SerieGym] { sesion?.ej.first { $0.ej == ej }?.series ?? [] }

    func filas(_ b: BloqueGym) -> Int { max(b.series, hechas(b.ej).count) + (extra[b.ej] ?? 0) }

    func sugerencia(_ b: BloqueGym) -> (kg: Double, sube: Bool, ultima: [SerieGym]?) {
        datos.e.sugerencia(b, menos: sesionId)
    }

    /// Lo que se ve en el campo de kilos de una fila sin hacer: lo escrito o la sugerencia.
    func kgTexto(_ b: BloqueGym, _ i: Int) -> String {
        if let s = hechas(b.ej).segura(i) { return FormatoEnt.num(s.kg) }
        if let t = borradores["kg|\(b.ej)|\(i)"] { return t }
        let kg = sugerencia(b).kg
        return kg > 0 ? FormatoEnt.num(kg) : ""
    }

    func repTexto(_ b: BloqueGym, _ i: Int) -> String {
        if let s = hechas(b.ej).segura(i) { return String(s.n) }
        return borradores["rep|\(b.ej)|\(i)"] ?? ""
    }

    /// Lo que se apunta si no escribes las repes: las de la última vez en esa serie, los segundos o el mínimo del rango.
    func repSugeridas(_ b: BloqueGym, _ i: Int) -> String {
        if let u = sugerencia(b).ultima?.segura(i) { return String(u.n) }
        if b.porTiempo { return String(b.seg) }
        if let r = FormatoEnt.rango(b.repes) { return String(r.0) }
        return ""
    }

    var toca: Toca {
        for (b, _) in bloques {
            let n = hechas(b.ej).count
            let total = filas(b)
            guard n < total else { continue }
            let kg = FormatoEnt.lee(kgTexto(b, n)) ?? 0
            var partes: [String] = []
            if kg > 0 { partes.append("\(FormatoEnt.num(kg)) kg") }
            if !b.repes.isEmpty { partes.append("\(b.repes) rep") } else if b.porTiempo { partes.append("\(b.seg) s") }
            return Toca(ejercicio: b.ej, serie: n + 1, total: total, detalle: partes.joined(separator: " · "),
                        descanso: b.porTiempo ? 60 : 90, hecho: false)
        }
        return Toca(ejercicio: "Todo hecho", serie: 0, total: 0, detalle: "", descanso: 0, hecho: true)
    }

    // MARK: abrir y cerrar

    /// Empezar (o seguir) la rutina hoy.
    func empieza(_ r: RutinaGym) {
        let hoy = Fecha.hoy()
        if let viva = (datos.e.gym[hoy] ?? []).first(where: { $0.rutina == r.id && !$0.fin }) {
            abre(viva.id, dia: hoy)
            return
        }
        let s = SesionGym(id: FormatoEnt.uid(), rutina: r.id, n: r.n)
        datos.cambia { $0.gym[hoy, default: []].append(s) }
        abre(s.id, dia: hoy)
    }

    func abre(_ id: String, dia d: String, descanso previo: Descanso? = nil, extra previo2: [String: Int] = [:]) {
        if sesionId != id {
            borradores = [:]
            extra = previo2
        }
        sesionId = id
        dia = d
        descanso = previo.flatMap { $0.fin > Date() ? $0 : nil }
        UIApplication.shared.isIdleTimerDisabled = true
        Entreno.shared.nativo = { [weak self] in self?.serieHechaDesdeFuera() ?? false }
        withAnimation(Tema.Muelle.pantalla) { visible = true }
        apunta()
        arrancaBucle()
        avisaIsla()
        // las «Serie hecha» que se pulsaron en la isla con la app cerrada
        Entreno.shared.aplicaPendientesNativas()
    }

    /// Cerrar sin terminar: la sesión sigue abierta («Seguir» la retoma).
    func cierra() {
        datos.guardaYa()
        sesionId = nil
        descanso = nil
        extra = [:]
        borradores = [:]
        bucle?.cancel()
        UIApplication.shared.isIdleTimerDisabled = false
        Entreno.shared.nativo = nil
        Entreno.shared.termina()
        Self.olvida()
        withAnimation(Tema.Muelle.pantalla) { visible = false }
    }

    /// Terminar: fuera lo que no tiene series; si no queda nada, no hubo sesión. Si no, los minutos hasta la última
    /// serie (y un poco), la plantilla aprende los kilos de hoy y se marca el hábito.
    func termina() {
        guard let s = sesion, let id = sesionId else { return cierra() }
        let d = dia
        let r = rutina
        let conSeries = s.ej.filter { !$0.series.isEmpty }
        if conSeries.isEmpty {
            datos.cambia(ya: true) { e in
                e.gym[d] = (e.gym[d] ?? []).filter { $0.id != id }
                if e.gym[d]?.isEmpty == true { e.gym[d] = nil }
            }
        } else {
            let ahora = FormatoEnt.ahoraMs()
            let hasta = min(ahora, (s.t1 > 0 ? s.t1 : ahora) + 5 * 60_000)
            let minutos = min(600, Int((Double(hasta - s.t0) / 60_000).rounded()))
            datos.cambia(log: r?.hab.isEmpty == false, ya: true) { e in
                e.conSesion(d, id) {
                    $0.ej = conSeries
                    $0.fin = true
                    $0.min = max(0, minutos)
                }
                if let r, let i = e.rutinas.firstIndex(where: { $0.id == r.id }) {
                    for ej in conSeries {
                        if let j = e.rutinas[i].bloques.firstIndex(where: { $0.ej == ej.ej }) {
                            e.rutinas[i].bloques[j].kg = ej.series.map(\.kg).max() ?? 0
                        }
                    }
                    if !r.hab.isEmpty { e.marca(r.hab, dia: d, true) }
                }
            }
            Haptica.shared.toca(.dia)
        }
        cierra()
    }

    // MARK: series

    /// Marca la serie `i` de ese ejercicio (solo la siguiente por hacer). false si faltan las repes.
    @discardableResult
    func marca(_ b: BloqueGym, _ i: Int) -> Bool {
        guard let id = sesionId else { return false }
        let ya = hechas(b.ej).count
        guard i == ya else { return false }
        let kg = min(500, max(0, FormatoEnt.lee(kgTexto(b, i)) ?? 0))
        let repTxt = repTexto(b, i).isEmpty ? repSugeridas(b, i) : repTexto(b, i)
        let n = min(600, max(0, Int(repTxt) ?? 0))
        guard n > 0 else {
            pideRepes = "rep|\(b.ej)|\(i)"
            Haptica.shared.toca(.error)
            return false
        }
        let serie = SerieGym(kg: kg, n: n)
        let record = datos.e.esRecord(b.ej, serie, sesion: id)
        let d = dia
        datos.cambia { e in
            e.conSesion(d, id) { s in
                if let j = s.ej.firstIndex(where: { $0.ej == b.ej }) {
                    s.ej[j].series.append(serie)
                } else {
                    s.ej.append(EjercicioGym(ej: b.ej, series: [serie]))
                }
                s.t1 = FormatoEnt.ahoraMs()
            }
        }
        borradores["kg|\(b.ej)|\(i)"] = nil
        borradores["rep|\(b.ej)|\(i)"] = nil
        // el peso de esta serie es el de partida de la siguiente
        if borradores["kg|\(b.ej)|\(i + 1)"] == nil, kg > 0 { borradores["kg|\(b.ej)|\(i + 1)"] = FormatoEnt.num(kg) }
        Haptica.shared.toca(record ? .record : .serie)
        if record { records += 1 }
        descansa(b.porTiempo ? 60 : 90)
        return true
    }

    /// Deshacer la última serie hecha de ese ejercicio.
    func deshaz(_ b: BloqueGym) {
        guard let id = sesionId, !hechas(b.ej).isEmpty else { return }
        let d = dia
        let ultima = hechas(b.ej).last
        datos.cambia { e in
            e.conSesion(d, id) { s in
                if let j = s.ej.firstIndex(where: { $0.ej == b.ej }) { s.ej[j].series.removeLast() }
            }
        }
        if let ultima {
            let i = hechas(b.ej).count
            borradores["kg|\(b.ej)|\(i)"] = FormatoEnt.num(ultima.kg)
            borradores["rep|\(b.ej)|\(i)"] = String(ultima.n)
        }
        Haptica.shared.toca(.desmarcar)
        avisaIsla()
    }

    /// Corregir una serie ya hecha.
    func corrige(_ b: BloqueGym, _ i: Int, kg: String? = nil, rep: String? = nil) {
        guard let id = sesionId, var s = hechas(b.ej).segura(i) else { return }
        if let kg, let v = FormatoEnt.lee(kg) { s.kg = min(500, max(0, v)) }
        if let rep, let v = Int(rep), v > 0 { s.n = min(600, v) }
        let d = dia
        datos.cambia { e in
            e.conSesion(d, id) { ses in
                if let j = ses.ej.firstIndex(where: { $0.ej == b.ej }), i < ses.ej[j].series.count { ses.ej[j].series[i] = s }
            }
        }
    }

    /// La serie que toca, con lo escrito o lo sugerido (el botón grande y el de la isla).
    @discardableResult
    func serieQueToca() -> Bool {
        let t = toca
        guard !t.hecho, let b = bloques.first(where: { $0.b.ej == t.ejercicio })?.b else { return false }
        return marca(b, t.indice)
    }

    /// Desde la isla o la pantalla de bloqueo (también con la app en segundo plano).
    private func serieHechaDesdeFuera() -> Bool {
        let hecha = serieQueToca()
        avisaIsla()
        return hecha
    }

    func masSerie(_ b: BloqueGym) {
        extra[b.ej, default: 0] += 1
        apunta()
        avisaIsla()
    }

    func quita(_ b: BloqueGym, extra esExtra: Bool) {
        guard let id = sesionId else { return }
        let d = dia
        datos.cambia { e in
            e.conSesion(d, id) { s in
                if esExtra { s.ej.removeAll { $0.ej == b.ej } } else if !s.quita.contains(b.ej) { s.quita.append(b.ej) }
            }
        }
        avisaIsla()
    }

    func recupera(_ ej: String) {
        guard let id = sesionId else { return }
        let d = dia
        datos.cambia { e in e.conSesion(d, id) { $0.quita.removeAll { $0 == ej } } }
        avisaIsla()
    }

    func anade(_ nombre: String) {
        let ej = nombre.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard let id = sesionId, !ej.isEmpty, !bloques.contains(where: { $0.b.ej == ej }) else { return }
        let deRutina = rutina?.bloques.contains { $0.ej == ej } ?? false
        let d = dia
        datos.cambia { e in
            e.conSesion(d, id) { s in
                if deRutina { s.quita.removeAll { $0 == ej } } else { s.ej.append(EjercicioGym(ej: ej)) }
            }
        }
        avisaIsla()
    }

    // MARK: descanso

    func descansa(_ seg: Int) {
        descanso = Descanso(fin: Date().addingTimeInterval(TimeInterval(seg)), total: seg)
        ultimoPip = 0
        apunta()
        arrancaBucle()
        avisaIsla()
    }

    func ajustaDescanso(_ seg: Int) {
        guard var d = descanso else { return }
        d.fin = d.fin.addingTimeInterval(TimeInterval(seg))
        d.total = max(15, d.total + seg)
        if d.fin <= Date() { return saltaDescanso() }
        descanso = d
        ultimoPip = 0
        apunta()
        avisaIsla()
    }

    func saltaDescanso() {
        descanso = nil
        apunta()
        avisaIsla()
    }

    /// Con la hora de fin, no contando tics: con la pantalla bloqueada el bucle se para y al volver va por donde toca.
    private func arrancaBucle() {
        bucle?.cancel()
        bucle = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                self.tic()
            }
        }
    }

    private func tic() {
        guard let d = descanso else { return }
        let queda = Int(ceil(d.fin.timeIntervalSinceNow))
        if queda <= 0 {
            descanso = nil
            apunta()
            // al acabar (no si se vuelve a la app mucho después): vibración y dos pitidos
            if d.fin.timeIntervalSinceNow > -3 && UIApplication.shared.applicationState == .active {
                Haptica.shared.toca(.descanso)
                AudioServicesPlaySystemSound(1052)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { AudioServicesPlaySystemSound(1052) }
            }
            avisaIsla()
            return
        }
        if queda <= 3, queda != ultimoPip, UIApplication.shared.applicationState == .active {
            ultimoPip = queda
            AudioServicesPlaySystemSound(1057)
        }
    }

    // MARK: la isla

    func avisaIsla() {
        guard let s = sesion else { return }
        let t = toca
        let estado = EntrenoActividad.ContentState(ejercicio: t.ejercicio, serie: t.serie, total: t.total, detalle: t.detalle,
                                                   finDescanso: descanso?.fin, descanso: t.descanso, hecho: t.hecho)
        Entreno.shared.muestraNativo(s.n.isEmpty ? "Entreno" : s.n, estado)
    }

    // MARK: lo que está en marcha, en el iPhone

    private struct Marcha: Codable {
        var sesion: String
        var dia: String
        var hasta: Date
        var finDescanso: Date?
        var totalDescanso: Int?
        var extra: [String: Int]
        /// Copia de la sesión: si iOS mata la app antes de que salga el guardado, lo hecho sigue aquí.
        var copia: SesionGym?
    }

    /// Apunta lo que está en marcha (caduca a las 3 horas, como en la web).
    func apunta() {
        guard let id = sesionId else { return }
        let m = Marcha(sesion: id, dia: dia, hasta: Date().addingTimeInterval(3 * 3600), finDescanso: descanso?.fin,
                       totalDescanso: descanso?.total, extra: extra, copia: sesion)
        if let d = try? JSONEncoder().encode(m) { UserDefaults.standard.set(d, forKey: Self.claveMarcha) }
    }

    static func olvida() { UserDefaults.standard.removeObject(forKey: claveMarcha) }

    static var hayEnMarcha: Bool {
        guard let d = UserDefaults.standard.data(forKey: claveMarcha),
              let m = try? JSONDecoder().decode(Marcha.self, from: d) else { return false }
        return m.dia == Fecha.hoy() && m.hasta > Date()
    }

    /// Al abrir Entreno: si había una sesión abierta hoy, se reabre donde iba. Si la copia del iPhone lleva más
    /// series que la del estado (no le dio tiempo a guardarse), manda la copia.
    func reanuda() {
        guard sesionId == nil, let d = UserDefaults.standard.data(forKey: Self.claveMarcha),
              let m = try? JSONDecoder().decode(Marcha.self, from: d) else { return }
        guard m.dia == Fecha.hoy(), m.hasta > Date() else { return Self.olvida() }
        if let copia = m.copia, !copia.fin {
            let actual = datos.e.sesionGym(m.dia, m.sesion)
            if actual == nil || (actual?.fin == false && (actual?.numeroSeries ?? 0) < copia.numeroSeries) {
                datos.cambia { e in
                    var lista = e.gym[m.dia] ?? []
                    if let i = lista.firstIndex(where: { $0.id == copia.id }) { lista[i] = copia } else { lista.append(copia) }
                    e.gym[m.dia] = lista
                }
            }
        }
        guard let s = datos.e.sesionGym(m.dia, m.sesion), !s.fin else { return Self.olvida() }
        let previo = m.finDescanso.map { Descanso(fin: $0, total: m.totalDescanso ?? 90) }
        abre(s.id, dia: m.dia, descanso: previo, extra: m.extra)
    }
}

extension Array {
    /// El elemento `i` si existe (para no salirse de la lista).
    func segura(_ i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
