import Foundation
import UIKit
import WidgetKit

// De dónde saca el fondo de bloqueo lo que enseña, sin abrir la app y sin red:
// - /api/hoy: lo último que se bajó (hoy.json del app group, legible con el iPhone bloqueado); con red, se refresca
//   antes con un límite de 3 s.
// - el entreno con sus ejercicios: la copia InstantaneaFondo (Compartido/MomentoFondo.swift), que se rehace desde la
//   base local cada vez que la app se activa (con el iPhone bloqueado la base no se abre) o, si falta la de hoy, desde
//   /api/state con red.

enum DatosFondo {
    static let tipoWidget = "TomMomento"

    /// Al activar la app (HoyApp): la copia del entreno al día para las automatizaciones de mañana.
    static func alActivar() {
        refresca()
        WidgetCenter.shared.reloadTimelines(ofKind: tipoWidget)
    }

    /// Rehace la copia del entreno de hoy y mañana desde el estado dado o, si no, desde la base local.
    @discardableResult
    static func refresca(estado dado: [String: Any]? = nil) -> InstantaneaFondo? {
        var estado = dado
        if estado == nil, let r = Local.lee(Local.clave("GET", "/api/state")) {
            estado = (try? JSONSerialization.jsonObject(with: r.cuerpo)) as? [String: Any]
        }
        guard let estado else { return nil }
        let e = EstadoEntreno(crudo: estado)
        var dias: [String: [EntrenoFondo]] = [:]
        for salto in 0...1 {
            guard let d = Calendar.current.date(byAdding: .day, value: salto, to: Date()) else { continue }
            let dia = Fecha.dia(d)
            dias[dia] = e.entrenoDe(dia).map { h in
                let r = e.rutinaDe(dia, h) ?? e.rutinas.first { $0.hab == h }
                return EntrenoFondo(hab: h, nombre: r?.n ?? e.habito(h)?.n ?? h, tipo: r?.tipo ?? "otro",
                                    hecho: e.hecho(dia, h), ejercicios: (r?.bloques ?? []).prefix(5).map(texto))
            }
        }
        let inst = InstantaneaFondo(fecha: Date(), dias: dias)
        inst.guarda()
        return inst
    }

    /// «Sentadilla · 4×6-8 · 80 kg», «Plancha · 3×40 s».
    static func texto(_ b: BloqueGym) -> String {
        var s = b.ej
        let repes = b.porTiempo ? "\(b.seg) s" : b.repes
        if b.series > 0 && !repes.isEmpty {
            s += " · \(b.series)×\(repes)"
        } else if b.series > 1 {
            s += " · \(b.series) series"
        }
        if b.kg > 0 {
            let kg = b.kg.rounded() == b.kg ? String(Int(b.kg)) : String(format: "%.1f", b.kg).replacingOccurrences(of: ".", with: ",")
            s += " · \(kg) kg"
        }
        return s
    }

    /// Lo que necesita el generador. Primero lo guardado; con red (y como mucho unos segundos), lo del servidor.
    static func paraGenerar() async -> (hoy: Hoy?, inst: InstantaneaFondo?) {
        var hoy = Almacen.leeHoy()
        let conClaves = Almacen.claves != nil
        if conClaves, let crudo = await conLimite(3, { try await API.datos("/api/hoy") }),
           let nuevo = try? JSONDecoder().decode(Hoy.self, from: crudo) {
            Almacen.guardaHoy(crudo)
            hoy = nuevo
        }
        var inst = refresca() ?? InstantaneaFondo.lee()
        if inst?.dias[Fecha.hoy()] == nil, conClaves,
           let crudo = await conLimite(4, { try await API.datos("/api/state") }),
           let estado = (try? JSONSerialization.jsonObject(with: crudo)) as? [String: Any] {
            inst = refresca(estado: estado) ?? inst
        }
        return (hoy, inst)
    }

    /// La petición, o nil si falla o tarda más de `segundos` (sin red, el fondo sale igual con lo guardado).
    private static func conLimite(_ segundos: Double, _ peticion: @escaping @Sendable () async throws -> Data) async -> Data? {
        await withTaskGroup(of: Data?.self) { grupo in
            grupo.addTask { try? await peticion() }
            grupo.addTask {
                try? await Task.sleep(nanoseconds: UInt64(segundos * 1_000_000_000))
                return nil
            }
            let primero = await grupo.next() ?? nil
            grupo.cancelAll()
            return primero
        }
    }
}

/// El tamaño de la pantalla del iPhone: el fondo se dibuja a su resolución nativa (nativeBounds).
@MainActor
enum PantallaFondo {
    /// En puntos, en vertical.
    static var puntos: CGSize {
        let p = UIScreen.main.nativeBounds.size
        let s = escala
        let ancho = min(p.width, p.height) / s, alto = max(p.width, p.height) / s
        return CGSize(width: ancho, height: alto)
    }

    static var escala: CGFloat { max(1, UIScreen.main.nativeScale) }
}
