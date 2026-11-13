import Foundation

// Siri, el widget y los avisos sin red: las lecturas contestan con la copia de Local (diciendo de cuándo es) y las
// escrituras se quedan en la cola de Local hasta que vuelva la conexión (Hoy/Sincro.swift las manda).
// Compila en la app y en el widget; HoyCompartir no lo incluye (API.swift no sabe nada de Local).

extension API {
    static let avisoEncolado = "Apuntado, se enviará en cuanto haya conexión"

    /// «(sin conexión, datos de las 18:30)».
    static func notaCopia(_ fecha: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "HH:mm"
        let hora = f.string(from: fecha)
        if Calendar.current.isDateInToday(fecha) { return "(sin conexión, datos de las \(hora))" }
        f.dateFormat = "d/M"
        return "(sin conexión, datos del \(f.string(from: fecha)) a las \(hora))"
    }

    /// Una escritura que, si no llega al servidor, se apunta en la cola. nil = encolada.
    /// `tmp`: el id provisional de lo que se crea (una tarea): al salir se apunta el id real para lo que vaya detrás.
    static func escribeOEncola(_ ruta: String, metodo: String = "POST", json: [String: Any],
                               tmp: String? = nil) async throws -> Data? {
        var cabeceras = ["content-type": "application/json"]
        if let tmp { cabeceras["x-tom-tmp"] = tmp }
        func alaCola(_ error: Error) throws -> Data? {
            guard let cuerpo = try? JSONSerialization.data(withJSONObject: json),
                  Local.encola(metodo: metodo, ruta: ruta, cuerpo: cuerpo, cabeceras: cabeceras) else { throw error }
            // y ya se ve en la copia local (y sigue viéndose aunque se cierre la app)
            Operaciones.anota(metodo: metodo, ruta: ruta, json: json, cabeceras: cabeceras)
            return nil
        }
        // con el id de ahora (lo creado sin red ya tiene el suyo, una tarea cambiada tiene otro)
        let crudo = try? JSONSerialization.data(withJSONObject: json)
        let (rutaAhora, cuerpoAhora) = Operaciones.resuelveIds(ruta: ruta, cuerpo: crudo)
        let jsonAhora = (cuerpoAhora.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? json
        // va sobre algo que aún espera en la cola: detrás de ello, para que salgan en orden
        if rutaAhora.contains("tmp:") || ((jsonAhora["id"] as? String)?.hasPrefix("tmp:") ?? false)
            || Operaciones.esperaEnCola(ruta) {
            return try alaCola(APIError(mensaje: "No he podido guardar el cambio en el iPhone. Desbloquéalo y vuelve a probar."))
        }
        do {
            return try await datos(rutaAhora, metodo: metodo, json: jsonAhora)
        } catch let error as APIError where error.sinRed {
            return try alaCola(error)
        }
    }

    /// Un GET que, sin red, contesta con la copia guardada. `copia` es la fecha de la copia (nil si es fresco).
    static func leeOCopia(_ ruta: String) async throws -> (datos: Data, copia: Date?) {
        do {
            let crudo = try await datos(ruta)
            // lo del servidor, con lo que aún no ha salido de la cola encima (Operaciones.swift)
            return (Operaciones.llega(ruta, crudo), nil)
        } catch let error as APIError where error.sinRed {
            if let r = Local.lee(Local.clave("GET", ruta)) { return (r.cuerpo, r.fecha) }
            if !Local.disponible {
                throw APIError(mensaje: "No hay conexión, y con el iPhone bloqueado no puedo leer los datos guardados. Desbloquéalo y vuelve a probar.")
            }
            throw error
        }
    }

    /// Devuelve true si se quedó en la cola (y ya se ve marcado en la copia local y en el widget).
    @discardableResult
    static func marcaOEncola(habito: String, hecho: Bool, dia: String = Fecha.hoy()) async throws -> Bool {
        let json: [String: Any] = ["dia": dia, "id": habito, "hecho": hecho]
        guard try await escribeOEncola("/api/marca", json: json) == nil else { return false }
        Local.apuntaMarca(dia: dia, habito: habito, hecho: hecho)
        return true
    }

    @discardableResult
    static func tareaOEncola(_ texto: String, due: String? = nil, hora: String? = nil) async throws -> Bool {
        var json: [String: Any] = ["t": texto]
        if let due { json["due"] = due }
        if let hora { json["hora"] = hora }
        return try await escribeOEncola("/api/tarea", json: json) == nil
    }

    /// Como apuntaGasto, pero con el día puesto: si sale mañana de la cola, sigue siendo el gasto de hoy.
    static func apuntaGastoOEncola(importe: Double, nota: String? = nil, cat: String? = nil,
                                   src: String = "siri") async throws -> String {
        guard importe.isFinite, importe > 0 else { throw APIError(mensaje: "El importe tiene que ser mayor que cero") }
        let redondeado = (importe * 100).rounded() / 100
        var json: [String: Any] = ["importe": redondeado, "src": src, "dia": Fecha.hoy()]
        if let nota = nota?.trimmingCharacters(in: .whitespacesAndNewlines), !nota.isEmpty { json["nota"] = nota }
        if let cat = cat?.trimmingCharacters(in: .whitespacesAndNewlines), !cat.isEmpty { json["cat"] = cat }
        guard let crudo = try await escribeOEncola("/api/gastos/gasto", json: json) else {
            return "Gasto de \(numero(redondeado, decimales: 2)) €. \(avisoEncolado)."
        }
        return texto(de: crudo, "Gasto apuntado")
    }

    /// Como peso, con el día puesto por la misma razón.
    static func pesoOEncola(_ kilos: Double) async throws -> String {
        guard kilos.isFinite, kilos >= 20, kilos <= 400 else { throw APIError(mensaje: "Ese peso no puede ser") }
        let redondeado = (kilos * 10).rounded() / 10
        let json: [String: Any] = ["peso": redondeado, "dia": Fecha.hoy()]
        guard let crudo = try await escribeOEncola("/api/salud", json: json) else {
            return "Peso de \(numero(redondeado, decimales: 1)) kg. \(avisoEncolado)."
        }
        return texto(de: crudo, "Peso apuntado")
    }

    static func tocaOCopia(dia: String) async throws -> String {
        let (crudo, copia) = try await leeOCopia("/api/toca?dia=\(dia)")
        return conNota(texto(de: crudo, "No sé qué toca"), copia)
    }

    static func presupuestoOCopia() async throws -> String {
        let (crudo, copia) = try await leeOCopia("/api/presupuesto")
        return conNota(texto(de: crudo, "No sé cómo va el presupuesto"), copia)
    }

    private static func conNota(_ texto: String, _ copia: Date?) -> String {
        guard let copia else { return texto }
        return "\(texto) \(notaCopia(copia))"
    }

    private static func texto(de crudo: Data, _ porDefecto: String) -> String {
        let objeto = try? JSONSerialization.jsonObject(with: crudo) as? [String: Any]
        return (objeto?["texto"] as? String) ?? porDefecto
    }

    private static func numero(_ x: Double, decimales: Int) -> String {
        String(format: "%.\(decimales)f", x).replacingOccurrences(of: ".", with: ",")
    }
}
