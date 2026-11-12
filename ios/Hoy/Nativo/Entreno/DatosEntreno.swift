import Foundation
import Observation
import SwiftUI
import WidgetKit

/// El estado de todo para Entreno: lo lee de /api/state (sin red, la copia de Local) y lo guarda con un PUT del estado
/// entero, como la web, con la versión (X-Version). Si otro sitio escribió entre medias (409), junta los dos lados con
/// Fusion a partir de lo último que vino del servidor. Sin red, el PUT va a la cola de Local (con su base, para que
/// Sincro lo junte al volver) y la copia local se queda con lo cambiado: lo hecho en la sesión no se pierde.
@MainActor @Observable
final class DatosEntreno {
    static let shared = DatosEntreno()

    enum Guardado: Equatable {
        case nada, guardando, guardado, enCola, error(String)
    }

    private(set) var e = EstadoEntreno()
    private(set) var cargado = false
    private(set) var cargando = false
    /// La fecha de la copia si lo que se ve no viene fresco del servidor.
    private(set) var copia: Date?
    private(set) var guardado: Guardado = .nada
    /// Un aviso para enseñar un momento (un choque al guardar, un error).
    var aviso: String?

    @ObservationIgnored private var crudo: [String: Any] = [:]
    /// Lo último que vino del servidor (la base de la fusión) y su versión.
    @ObservationIgnored private var base: [String: Any]?
    @ObservationIgnored private var version: String?
    @ObservationIgnored private var sucio = false
    @ObservationIgnored private var enviando = false
    @ObservationIgnored private var tocaLog = false
    @ObservationIgnored private var reintentar = false
    @ObservationIgnored private var temporizador: Task<Void, Never>?
    @ObservationIgnored private var ultimaCarga: Date?

    private static let ruta = "/api/state"
    private static var clave: String { Local.clave("GET", ruta) }

    private init() {
        if let r = Local.lee(Self.clave) {
            adopta(r.cuerpo, version: r.version, delServidor: !r.local)
            copia = r.fecha
        }
    }

    var hoy: String { Fecha.hoy() }

    // MARK: leer

    /// Recarga si hace más de `margen` segundos. Con cambios sin salir no se pisa lo de aquí.
    func carga(margen: TimeInterval = 15) async {
        if sucio || enviando { return }
        if let ultimaCarga, Date().timeIntervalSince(ultimaCarga) < margen { return }
        guard !cargando else { return }
        cargando = true
        defer { cargando = false }
        guard let p = try? API.peticion(Self.ruta) else {
            leeCopia()
            return
        }
        let cola = hayCola()
        switch await Sincro.pide(p) {
        case .ok(let datos, let http):
            ultimaCarga = Date()
            guard !sucio && !enviando else { return }   // se cambió algo mientras llegaba
            // lo de la cola aún no está en el servidor: se sigue viendo lo de aquí y se intenta mandar
            if cola, let r = Local.lee(Self.clave), r.local {
                adopta(r.cuerpo, version: r.version, delServidor: false)
                copia = nil
                Task { _ = await Sincro.vacia() }
                return
            }
            let v = http.value(forHTTPHeaderField: "X-Version")
            Local.guarda(Self.clave, cuerpo: datos, tipo: "application/json", version: v, fecha: Sincro.fechaDe(http))
            adopta(datos, version: v, delServidor: true)
            copia = nil
        case .sinRed:
            leeCopia()
        case .estado(let codigo, _):
            aviso = codigo == 401 ? "La contraseña de todo no vale: revísala en Ajustes de Tom."
                : "No he podido cargar el entreno (error \(codigo)). Tira hacia abajo para reintentar."
            leeCopia()
        }
    }

    func recarga() async {
        ultimaCarga = nil
        await carga()
    }

    private func leeCopia() {
        guard let r = Local.lee(Self.clave) else { return }
        if !cargado || r.local { adopta(r.cuerpo, version: r.version, delServidor: !r.local) }
        copia = r.fecha
    }

    private func adopta(_ datos: Data, version v: String?, delServidor: Bool) {
        guard let objeto = (try? JSONSerialization.jsonObject(with: datos)) as? [String: Any] else { return }
        crudo = objeto
        if delServidor { base = objeto }
        version = v
        e = EstadoEntreno(crudo: objeto)
        cargado = true
    }

    // MARK: cambiar

    /// Cambia el estado al momento (la pantalla no espera al servidor) y lo manda poco después. `log`: si cambia lo
    /// hecho, Hoy y Hábitos recargan tras guardar. `ya`: sin esperar (fin de sesión, app a segundo plano).
    func cambia(log: Bool = false, ya: Bool = false, _ cambio: (inout EstadoEntreno) -> Void) {
        var nuevo = e
        cambio(&nuevo)
        e = nuevo
        sucio = true
        if log { tocaLog = true }
        programa(ya ? 0 : 0.6)
    }

    /// Lo que quede por mandar, ya (al pasar a segundo plano).
    func guardaYa() {
        guard sucio else { return }
        programa(0)
    }

    private func programa(_ espera: Double) {
        temporizador?.cancel()
        temporizador = Task { [weak self] in
            if espera > 0 { try? await Task.sleep(for: .seconds(espera)) }
            guard !Task.isCancelled else { return }
            // en una tarea aparte: cancelar el temporizador no puede cortar un envío a medias
            Task { @MainActor [weak self] in await self?.vacia() }
        }
    }

    private func vacia() async {
        guard !enviando else { return }   // al acabar el envío en curso se vuelve a mirar `sucio`
        enviando = true
        defer { enviando = false }
        while sucio {
            sucio = false
            guardado = .guardando
            await envia(e.escribe(en: crudo))
        }
        if reintentar {
            reintentar = false
            sucio = true
            programa(30)
        }
    }

    private func hayCola() -> Bool {
        Local.cambios().contains { $0.metodo == "PUT" && $0.rutaSinQuery == Self.ruta && $0.estado == .pendiente }
    }

    private func envia(_ inicial: [String: Any]) async {
        var local = inicial
        // con un PUT del estado esperando en la cola, este se junta con él: si no, se pisarían al salir
        if hayCola() || !Red.shared.hayRed {
            encola(local)
            if Red.shared.hayRed { Task { _ = await Sincro.vacia() } }
            return
        }
        for _ in 0..<3 {
            guard var p = try? API.peticion(Self.ruta, metodo: "PUT", json: local) else {
                guardado = .error("Faltan las claves")
                return
            }
            if let version { p.setValue(version, forHTTPHeaderField: "X-Version") }
            switch await Sincro.pide(p) {
            case .ok(let datos, let http):
                let v = http.value(forHTTPHeaderField: "X-Version")
                version = v
                Local.guarda(Self.clave, cuerpo: datos, tipo: "application/json", version: v,
                             fecha: Sincro.fechaDe(http), forzar: true)
                if let servidor = (try? JSONSerialization.jsonObject(with: datos)) as? [String: Any] {
                    base = servidor
                    // lo que devuelve es el estado ya limpio; si se ha cambiado algo mientras, se queda lo de aquí
                    if !sucio {
                        crudo = servidor
                        e = EstadoEntreno(crudo: servidor)
                    } else {
                        crudo = servidor
                    }
                }
                guardado = .guardado
                copia = nil
                if tocaLog {
                    tocaLog = false
                    WidgetCenter.shared.reloadAllTimelines()
                    Task { await DatosNativos.shared.recarga() }
                }
                return
            case .estado(409, _):
                // otro sitio escribió: lo de ahora del servidor, y lo de aquí encima
                guard let pg = try? API.peticion(Self.ruta), case .ok(let datos, let http) = await Sincro.pide(pg),
                      let remoto = (try? JSONSerialization.jsonObject(with: datos)) as? [String: Any] else {
                    encola(local)
                    return
                }
                let v = http.value(forHTTPHeaderField: "X-Version")
                do {
                    if let fundido = try Fusion.fusiona(base, local, remoto) as? [String: Any] {
                        local = fundido
                    } else {
                        local = remoto
                    }
                    base = remoto
                    version = v
                    crudo = remoto
                    if !sucio { e = EstadoEntreno(crudo: local) }
                } catch {
                    // los dos tocaron lo mismo: manda lo del servidor y se avisa
                    base = remoto
                    version = v
                    crudo = remoto
                    e = EstadoEntreno(crudo: remoto)
                    Local.guarda(Self.clave, cuerpo: datos, tipo: "application/json", version: v,
                                 fecha: Sincro.fechaDe(http), forzar: true)
                    aviso = "Había cambios de otro sitio en lo mismo: repite lo último."
                    guardado = .error("Cambios de otro sitio")
                    Haptica.shared.toca(.error)
                    return
                }
            case .estado(let codigo, let datos):
                let detalle = (try? JSONSerialization.jsonObject(with: datos) as? [String: Any])?["detail"] as? String
                let texto = codigo == 401 ? "La contraseña de todo no vale" : detalle ?? "Error \(codigo) del servidor"
                guardado = .error(texto)
                aviso = "No se ha guardado: \(texto). Lo tienes aquí; vuelve a probar en un rato."
                Haptica.shared.toca(.error)
                reintentar = true   // que no se pierda: se vuelve a probar en un rato
                return
            case .sinRed:
                encola(local)
                return
            }
        }
        reintentar = true
        guardado = .error("El estado cambia sin parar en el servidor")
    }

    /// Sin red: a la cola de Local (con la base del servidor si es la de esta versión) y la copia con lo cambiado.
    private func encola(_ local: [String: Any]) {
        guard let cuerpo = try? JSONSerialization.data(withJSONObject: local) else { return }
        var cabeceras = ["content-type": "application/json"]
        if let version { cabeceras["x-version"] = version }
        let datosBase = base.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        if Local.encola(metodo: "PUT", ruta: Self.ruta, cuerpo: cuerpo, cabeceras: cabeceras, base: datosBase) {
            Local.guarda(Self.clave, cuerpo: cuerpo, tipo: "application/json", version: version, fecha: Date(),
                         local: true, forzar: true)
            crudo = local
            guardado = .enCola
        } else {
            guardado = .error("No he podido guardarlo en el iPhone")
            reintentar = true
        }
    }

    // MARK: atajos

    func marca(_ h: String, dia: String? = nil, _ on: Bool) {
        let d = dia ?? hoy
        cambia(log: true) { $0.marca(h, dia: d, on) }
    }

    var textoGuardado: String? {
        switch guardado {
        case .nada, .guardado: return nil
        case .guardando: return "Guardando…"
        case .enCola: return "Sin conexión: se manda al volver"
        case .error(let t): return "Sin guardar: \(t)"
        }
    }
}
