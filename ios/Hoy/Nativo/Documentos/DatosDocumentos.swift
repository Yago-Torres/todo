import Foundation
import SwiftUI
import Observation
import LocalAuthentication

// Documentos: la lista de GET /api/documentos y sus ficheros.
//
// Regla de Yago: los documentos privados (DNI, seguros…) se bajan igual que el resto, pero en la app se guardan en la
// base local del iPhone (Local: tom.sqlite, con NSFileProtectionComplete, solo legible con el iPhone desbloqueado) para
// que todo funcione sin red. No se copian a ningún otro sitio: ni iCloud, ni el repo, ni el widget. Para enseñarlos a
// QuickLook se escribe un fichero temporal con la misma protección, que se borra al cerrar la vista previa.

struct DocumentoTom: Identifiable, Hashable {
    var id: String
    var n: String
    var cat: String
    var titular: String
    var caduca: String
    var notas: String
    var fichero: String
    var subido: String
    /// Subido sin red y todavía en la cola.
    var provisional = false

    var extension_: String {
        let e = (fichero as NSString).pathExtension
        return e.isEmpty ? "pdf" : e.lowercased()
    }

    var esImagen: Bool { ["jpg", "jpeg", "png", "heic", "webp"].contains(extension_) }
    var clave: String { Local.clave("GET", "/api/documentos/\(id)/fichero") }
}

extension DocumentoTom: Decodable {
    private enum Claves: String, CodingKey { case id, n, cat, titular, caduca, notas, fichero, subido }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Claves.self)
        func texto(_ k: Claves) -> String {
            if let s = try? c.decode(String.self, forKey: k) { return s }
            if let n = try? c.decode(Int.self, forKey: k) { return String(n) }
            return ""
        }
        id = texto(.id)
        guard !id.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "Documento sin id")
        }
        n = texto(.n).isEmpty ? "Documento" : texto(.n)
        cat = texto(.cat).isEmpty ? "otros" : texto(.cat)
        titular = texto(.titular)
        caduca = texto(.caduca)
        notas = texto(.notas)
        fichero = texto(.fichero)
        subido = texto(.subido)
    }
}

/// Cómo está de vigente: el chip y el texto, como en la web.
struct Vigencia {
    enum Nivel { case normal, ojo, mal }
    let nivel: Nivel
    let texto: String

    init?(_ d: DocumentoTom) {
        guard !d.caduca.isEmpty else { return nil }
        let n = FechasES.entre(Fecha.hoy(), d.caduca)
        let garantia = d.cat == "garantias"
        let fecha = FechasES.larga(d.caduca)
        if n < 0 {
            nivel = garantia ? .normal : .mal
            texto = "\(garantia ? "garantía hasta" : "caducó el") \(fecha)"
        } else if n <= 30 && !garantia {
            nivel = .mal
            texto = n == 0 ? "caduca hoy" : "caduca en \(n) día\(n == 1 ? "" : "s")"
        } else if n <= 90 && !garantia {
            nivel = .ojo
            texto = "caduca el \(fecha)"
        } else {
            nivel = .normal
            texto = "\(garantia ? "garantía hasta" : "vale hasta") \(fecha)"
        }
    }

    var color: Color {
        switch nivel {
        case .normal: return Tema.suave
        case .ojo: return Tema.aviso
        case .mal: return Tema.peligro
        }
    }
}

/// Lo que se manda al guardar o cambiar un documento.
struct FichaDocumento {
    var n: String
    var cat: String
    var caduca: String?
    var titular: String
    var notas: String

    var json: [String: Any] {
        ["n": n, "cat": cat, "caduca": caduca ?? "", "titular": titular, "notas": notas]
    }
}

/// Un fichero elegido o capturado, a la espera de que le pongas nombre y tipo.
struct BorradorDocumento: Identifiable {
    let id = UUID()
    var datos: Data
    /// Con extensión (la del servidor decide si vale: pdf, jpg, png, heic, webp).
    var nombre: String
    var tipo: String

    var nombreSugerido: String {
        ((nombre as NSString).deletingPathExtension)
            .replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
    }
}

/// Face ID antes de abrir un documento privado, si el bloqueo está activado (Configurar → Face ID al abrir).
enum PuertaPrivada {
    static let categorias: Set<String> = ["identidad", "salud", "seguros"]

    static func abre(_ d: DocumentoTom) async -> Bool {
        guard categorias.contains(d.cat), Almacen.defaults.bool(forKey: "faceID") else { return true }
        let contexto = LAContext()
        contexto.touchIDAuthenticationAllowableReuseDuration = 60   // si acabas de desbloquear Tom, no lo vuelve a pedir
        var fallo: NSError?
        guard contexto.canEvaluatePolicy(.deviceOwnerAuthentication, error: &fallo) else { return true }
        do {
            return try await contexto.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Abrir \(d.n)")
        } catch {
            return false
        }
    }
}

@MainActor @Observable
final class DatosDocumentos {
    static let shared = DatosDocumentos()

    static let ordenCategorias = ["identidad", "coche", "casa", "trabajo", "estudios", "salud", "seguros", "garantias", "otros"]
    private static let nombresPorDefecto = ["identidad": "Identidad", "coche": "Coche", "casa": "Casa", "trabajo": "Trabajo",
                                            "estudios": "Títulos", "salud": "Salud", "seguros": "Seguros",
                                            "garantias": "Garantías", "otros": "Otros"]

    private(set) var docs: [DocumentoTom] = []
    private(set) var nombres: [String: String] = DatosDocumentos.nombresPorDefecto
    private(set) var copia: Date?
    private(set) var cargando = false
    private(set) var error: String?
    /// Los que tienen su fichero guardado en este iPhone (se ven sin red).
    private(set) var enLocal: Set<String> = []
    /// Subidos sin red: se enseñan hasta que la cola los mande.
    private(set) var pendientes: [DocumentoTom] = []
    var aviso: AvisoTom?

    private var ultimaCarga: Date?
    private static let ruta = "/api/documentos"

    private struct Respuesta: Decodable {
        var docs: [DocumentoTom]
        var cats: [String: String]

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Claves.self)
            // un documento que no se entienda no tumba la lista entera
            docs = ((try? c.decode([Tolerante<DocumentoTom>].self, forKey: .docs)) ?? []).compactMap(\.valor)
            cats = (try? c.decode([String: String].self, forKey: .cats)) ?? [:]
        }

        private enum Claves: String, CodingKey { case docs, cats }
    }

    private struct Tolerante<T: Decodable>: Decodable {
        let valor: T?
        init(from decoder: Decoder) throws { valor = try? T(from: decoder) }
    }

    init() {
        if let r = Local.lee(Local.clave("GET", Self.ruta)), let x = try? JSONDecoder().decode(Respuesta.self, from: r.cuerpo) {
            aplica(x)
        }
    }

    private func aplica(_ r: Respuesta) {
        docs = r.docs
        var n = Self.nombresPorDefecto
        for (k, v) in r.cats { n[k] = v }
        nombres = n
        refrescaLocal()
    }

    func refrescaLocal() {
        enLocal = Set(docs.filter { Local.existe($0.clave) }.map(\.id))
    }

    func carga(margen: TimeInterval = 20) async {
        if let ultimaCarga, Date().timeIntervalSince(ultimaCarga) < margen { return }
        guard !cargando else { return }
        cargando = true
        defer { cargando = false }
        do {
            let (crudo, fecha) = try await API.leeOCopia(Self.ruta)
            let nueva = try JSONDecoder().decode(Respuesta.self, from: crudo)
            withAnimation(Tema.Muelle.pantalla) { aplica(nueva) }
            copia = fecha
            error = nil
            ultimaCarga = Date()
            if fecha == nil { pendientes = [] }
        } catch let e as DecodingError {
            error = "No entiendo lo que devuelve /api/documentos (\(e.localizedDescription))"
        } catch {
            self.error = error.localizedDescription
        }
    }

    func recarga() async {
        ultimaCarga = nil
        await carga()
    }

    // MARK: categorías

    /// Las categorías en su orden, y las que el servidor añada al final.
    var categorias: [(id: String, nombre: String)] {
        let extra = nombres.keys.filter { !Self.ordenCategorias.contains($0) }.sorted()
        return (Self.ordenCategorias + extra).compactMap { k in nombres[k].map { (id: k, nombre: $0) } }
    }

    func nombre(_ cat: String) -> String { nombres[cat] ?? cat.capitalized }

    // MARK: avisos

    func avisa(_ texto: String, error: Bool = false, deshacer: (@MainActor () async -> Void)? = nil) {
        aviso = AvisoTom(texto: texto, error: error, deshacer: deshacer)
        AccessibilityNotification.Announcement(texto).post()
        if error { Haptica.shared.toca(.error) }
    }

    func quitaAviso() { aviso = nil }

    // MARK: ver

    /// El fichero del documento en un archivo temporal para QuickLook. Sale de la base local si está; si no, se baja
    /// y se guarda en ella para la próxima vez.
    func ficheroParaVer(_ d: DocumentoTom) async throws -> URL {
        var datos: Data
        if let r = Local.lee(d.clave) {
            datos = r.cuerpo
        } else {
            let (bajado, tipo) = try await API.ficheroDocumento(d.id)
            datos = bajado
            if datos.count <= 30 * 1024 * 1024 {
                Local.guarda(d.clave, cuerpo: datos, tipo: tipo, version: nil, fecha: Date())
                enLocal.insert(d.id)
            }
        }
        let carpeta = Self.carpetaTemporal.appendingPathComponent(d.id, isDirectory: true)
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        let limpio = d.n.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>")).joined(separator: "-")
        let url = carpeta.appendingPathComponent("\(limpio.isEmpty ? "Documento" : limpio).\(d.extension_)")
        try datos.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static var carpetaTemporal: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Documentos", isDirectory: true)
    }

    /// Borra los ficheros temporales de la vista previa.
    static func limpiaTemporales() {
        try? FileManager.default.removeItem(at: carpetaTemporal)
    }

    // MARK: guardar

    /// Sube un fichero nuevo. Sin red, queda en la cola con todos sus datos y sale cuando vuelva la conexión.
    func sube(_ b: BorradorDocumento, ficha: FichaDocumento) async -> Bool {
        var meta = ficha.json
        meta["nombre"] = b.nombre
        guard b.datos.count <= 25 * 1024 * 1024 else {
            avisa("Pesa más de 25 MB. Mándalo en PDF o con una foto más pequeña.", error: true)
            return false
        }
        do {
            let r = try await API.subeDocumento(b.datos, tipo: b.tipo, meta: meta)
            if let id = r["id"] as? String {
                // ya está en el iPhone: se ve sin red desde el primer momento
                Local.guarda(Local.clave("GET", "/api/documentos/\(id)/fichero"), cuerpo: b.datos, tipo: b.tipo, version: nil, fecha: Date())
            }
            await recarga()
            let aviso = (r["aviso"] as? String) ?? ""
            avisa(aviso.isEmpty ? "Guardado: \(ficha.n)" : "Guardado. Te recuerdo renovarlo el \(FechasES.larga(aviso))")
            return true
        } catch let e as APIError where e.sinRed {
            let cabeceras = ["content-type": b.tipo, "x-doc": API.cabeceraDocumento(meta)]
            guard Local.encola(metodo: "POST", ruta: "/api/documentos", cuerpo: b.datos, cabeceras: cabeceras) else {
                avisa("No se ha guardado: \(e.localizedDescription)", error: true)
                return false
            }
            let ext = (b.nombre as NSString).pathExtension
            let id = "tmp:\(b.id.uuidString)"
            withAnimation(Tema.Muelle.pantalla) {
                pendientes.append(DocumentoTom(id: id, n: ficha.n, cat: ficha.cat, titular: ficha.titular,
                                               caduca: ficha.caduca ?? "", notas: ficha.notas,
                                               fichero: "\(id).\(ext.isEmpty ? "pdf" : ext)", subido: Fecha.hoy(), provisional: true))
            }
            avisa("Guardado en este iPhone. Se subirá al volver la conexión")
            return true
        } catch {
            avisa("No se ha guardado: \(error.localizedDescription)", error: true)
            return false
        }
    }

    func edita(_ d: DocumentoTom, ficha: FichaDocumento) async -> Bool {
        guard !d.provisional else {
            avisa("Este documento aún no se ha subido. Cámbialo cuando vuelva la conexión.", error: true)
            return false
        }
        withAnimation(Tema.Muelle.pantalla) {
            if let i = docs.firstIndex(where: { $0.id == d.id }) {
                docs[i].n = ficha.n
                docs[i].cat = ficha.cat
                docs[i].caduca = ficha.caduca ?? ""
                docs[i].titular = ficha.titular
                docs[i].notas = ficha.notas
            }
        }
        do {
            let r = try await API.escribeOEncola("/api/documentos/\(d.id)", json: ficha.json)
            if let r, let o = (try? JSONSerialization.jsonObject(with: r)) as? [String: Any],
               let aviso = o["aviso"] as? String, !aviso.isEmpty {
                avisa("Guardado. Te recuerdo renovarlo el \(FechasES.larga(aviso))")
            } else {
                avisa(r == nil ? "Guardado. Se enviará al volver la conexión" : "Guardado")
            }
            return true
        } catch {
            avisa("No se ha guardado: \(error.localizedDescription)", error: true)
            await recarga()
            return false
        }
    }

    func borra(_ d: DocumentoTom) async {
        if d.provisional {
            withAnimation(Tema.Muelle.pantalla) { pendientes.removeAll { $0.id == d.id } }
            return
        }
        Haptica.shared.toca(.desmarcar)
        withAnimation(Tema.Muelle.pantalla) { docs.removeAll { $0.id == d.id } }
        do {
            let r = try await API.escribeOEncola("/api/documentos/\(d.id)/borra", json: [:])
            if r != nil {
                // en la papelera del servidor; aquí se queda el fichero por si lo deshaces
                avisa("Borrado: \(d.n)") { [weak self] in await self?.restaura(d) }
            } else {
                avisa("Borrado. Se enviará al volver la conexión")
            }
        } catch {
            avisa("No se ha borrado: \(error.localizedDescription)", error: true)
            await recarga()
        }
    }

    private func restaura(_ d: DocumentoTom) async {
        do {
            _ = try await API.escribeOEncola("/api/documentos/\(d.id)/restaura", json: [:])
            await recarga()
        } catch {
            avisa("No se ha podido recuperar: \(error.localizedDescription)", error: true)
        }
    }

    // MARK: lo que se pinta

    var todos: [DocumentoTom] { pendientes + docs }

    /// Lo que caduca en 90 días (o ya caducó), sin las garantías: lo que hay que renovar.
    var pronto: [DocumentoTom] {
        docs.filter { !$0.caduca.isEmpty && $0.cat != "garantias" && FechasES.entre(Fecha.hoy(), $0.caduca) <= 90 }
            .sorted { $0.caduca < $1.caduca }
    }

    func filtrados(categoria: String?, buscando q: String) -> [DocumentoTom] {
        todos.filter { d in
            (categoria == nil || d.cat == categoria)
                && (d.n.contieneBusqueda(q) || d.titular.contieneBusqueda(q) || d.notas.contieneBusqueda(q))
        }
    }
}
