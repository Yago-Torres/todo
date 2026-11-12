import AudioToolbox
import Foundation
import Observation
import SwiftUI
import UIKit

/// La rutina guiada (tipo movilidad: la de la mañana, el core): paso a paso con su cuenta atrás, la pausa para
/// colocarse entre pasos y pitidos al cambiar. Con la hora de fin de cada paso, no contando tics: si la pantalla se
/// apaga, al volver va por donde toca. Se apunta en el iPhone y caduca a los 20 min (una rutina abandonada a medias
/// no se da por hecha horas después).
@MainActor @Observable
final class GuiaEnCurso {
    static let shared = GuiaEnCurso()

    private(set) var rutina: RutinaGym?
    private(set) var i = 0
    private(set) var fin = Date()
    private(set) var pausa = false
    private(set) var queda = 0
    /// En la pausa entre paso y paso («Prepárate»).
    private(set) var cambio = false
    var visible = false

    @ObservationIgnored private var bucle: Task<Void, Never>?
    @ObservationIgnored private var pitado = 0
    private static let claveMarcha = "entreno.guiaEnMarcha"

    private init() {}

    /// El paso que se enseña (en la pausa, el siguiente).
    var paso: BloqueGym? {
        guard let r = rutina else { return nil }
        return r.bloques.segura(i + (cambio ? 1 : 0))
    }

    var indiceVisible: Int { i + (cambio ? 1 : 0) }

    var totalPaso: Int {
        guard let r = rutina else { return 1 }
        return cambio ? max(1, r.pausa ?? 0) : max(1, paso?.seg ?? 30)
    }

    var siguiente: BloqueGym? { rutina?.bloques.segura(indiceVisible + 1) }

    // MARK: empezar y parar

    func empieza(_ r: RutinaGym) {
        guard !r.bloques.isEmpty else { return }
        rutina = r
        i = 0
        cambio = false
        pausa = false
        fin = Date().addingTimeInterval(TimeInterval(r.bloques[0].seg > 0 ? r.bloques[0].seg : 30))
        queda = r.bloques[0].seg > 0 ? r.bloques[0].seg : 30
        AudioServicesPlaySystemSound(1057)
        arranca()
    }

    private func arranca() {
        UIApplication.shared.isIdleTimerDisabled = true
        withAnimation(Tema.Muelle.pantalla) { visible = true }
        apunta()
        bucle?.cancel()
        bucle = Task { [weak self] in
            while !Task.isCancelled {
                self?.tic()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    func para() {
        bucle?.cancel()
        rutina = nil
        UIApplication.shared.isIdleTimerDisabled = false
        UserDefaults.standard.removeObject(forKey: Self.claveMarcha)
        withAnimation(Tema.Muelle.pantalla) { visible = false }
    }

    func alternaPausa() {
        guard rutina != nil else { return }
        pausa.toggle()
        if pausa {
            queda = max(1, Int(ceil(fin.timeIntervalSinceNow)))
        } else {
            fin = Date().addingTimeInterval(TimeInterval(queda))
        }
        apunta()
    }

    func salta() {
        guard rutina != nil else { return }
        avanza(desde: Date())
    }

    // MARK: el reloj

    private func tic() {
        guard rutina != nil, !pausa else { return }
        var saltados = 0
        while rutina != nil, Date() >= fin {
            avanza(desde: fin)
            saltados += 1
        }
        guard rutina != nil else { return }
        if saltados > 0 {
            AudioServicesPlaySystemSound(1052)
            Haptica.shared.toca(.serie)
        }
        let q = max(1, Int(ceil(fin.timeIntervalSinceNow)))
        if q != queda { queda = q }
        if q <= 3, q != pitado {
            pitado = q
            AudioServicesPlaySystemSound(1057)
        }
    }

    private func avanza(desde: Date) {
        guard let r = rutina else { return }
        // entre paso y paso, la pausa de la rutina para colocarse; saltar durante la pausa empieza ya el siguiente
        if !cambio, let p = r.pausa, p > 0, i + 1 < r.bloques.count {
            cambio = true
            fin = desde.addingTimeInterval(TimeInterval(p))
            queda = p
            apunta()
            return
        }
        cambio = false
        i += 1
        guard i < r.bloques.count else { return acaba() }
        let seg = r.bloques[i].seg > 0 ? r.bloques[i].seg : 30
        fin = desde.addingTimeInterval(TimeInterval(seg))
        queda = seg
        apunta()
    }

    private func acaba() {
        let h = rutina?.hab ?? ""
        AudioServicesPlaySystemSound(1025)
        Haptica.shared.toca(.dia)
        para()
        let datos = DatosEntreno.shared
        if !h.isEmpty, !datos.e.hecho(datos.hoy, h) { datos.marca(h, true) }
    }

    // MARK: en el iPhone

    private struct Marcha: Codable {
        var guia: String
        var i: Int
        var fin: Date
        var pausa: Bool
        var queda: Int
        var cambio: Bool
        var dia: String
        var hasta: Date
    }

    private func apunta() {
        guard let r = rutina else { return }
        let m = Marcha(guia: r.id, i: i, fin: fin, pausa: pausa, queda: queda, cambio: cambio, dia: Fecha.hoy(),
                       hasta: Date().addingTimeInterval(20 * 60))
        if let d = try? JSONEncoder().encode(m) { UserDefaults.standard.set(d, forKey: Self.claveMarcha) }
    }

    static var hayEnMarcha: Bool {
        guard let d = UserDefaults.standard.data(forKey: claveMarcha),
              let m = try? JSONDecoder().decode(Marcha.self, from: d) else { return false }
        return m.dia == Fecha.hoy() && m.hasta > Date()
    }

    func reanuda() {
        guard rutina == nil, let d = UserDefaults.standard.data(forKey: Self.claveMarcha),
              let m = try? JSONDecoder().decode(Marcha.self, from: d) else { return }
        guard m.dia == Fecha.hoy(), m.hasta > Date(), let r = DatosEntreno.shared.e.rutina(m.guia), m.i < r.bloques.count else {
            UserDefaults.standard.removeObject(forKey: Self.claveMarcha)
            return
        }
        rutina = r
        i = m.i
        fin = m.fin
        pausa = m.pausa
        queda = m.queda
        cambio = m.cambio
        arranca()
    }
}
