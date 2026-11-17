import Foundation
import SwiftUI
import Observation
import UIKit

// Inversiones (lo de static/inversiones.html, inversiones.py del servidor): la cartera apuntada a mano, los precios de
// Yahoo ya en euros y la review del domingo. El servidor hace todas las cuentas (FIFO, la serie frente a la referencia,
// la proyección): aquí solo se pinta GET /api/inversiones. Apuntar una operación va por la cola si no hay red; buscar un
// activo, guardarlo o pedir precios necesitan conexión (bajan datos de Yahoo).

struct PerfilInv: Codable, Equatable {
    var edad: Int?
    var horizonte = ""
    var objetivo = ""
    var aportacion: Double = 0
    var estable: Bool?
    var emergencia = ""
    var tolerancia = ""
    var caida = ""
    var broker = ""
    var referencia = "VWCE.DE"
    var notas = ""
}

struct ActivoInv: Codable, Identifiable, Hashable {
    var id: String
    var nombre: String
    var isin: String
    var simbolo: String
    var tipo: String
    var divisa: String
    var ter: Double?
    var papel: String
}

struct OperacionInv: Codable, Identifiable, Hashable {
    var id: String
    var fecha: String
    var activo: String
    var tipo: String        // compra | venta | dividendo (precio = importe neto, cantidad 0)
    var cantidad: Double
    var precio: Double
    var comision: Double
    var nota: String

    /// Lo que sale (compra, negativo) o entra (venta, dividendo) en la cuenta.
    var total: Double {
        switch tipo {
        case "compra": return -(cantidad * precio + comision)
        case "venta": return cantidad * precio - comision
        default: return precio
        }
    }
}

struct PosicionInv: Decodable, Identifiable, Hashable {
    var id: String
    var nombre: String
    var isin: String
    var simbolo: String
    var tipo: String
    var ter: Double?
    var papel: String
    var cantidad: Double
    var coste: Double
    var costeMedio: Double?
    var precio: Double?
    var valor: Double?
    var latente: Double?
    var rent: Double?
    var dia: Double?
    var realizado: Double
    var dividendos: Double
    var comisiones: Double
    var peso: Double
    var precioHora: String?

    enum CodingKeys: String, CodingKey {
        case id, nombre, isin, simbolo, tipo, ter, papel, cantidad, coste, precio, valor, latente, rent, dia, realizado,
             dividendos, comisiones, peso
        case costeMedio = "coste_medio"
        case precioHora = "precio_hora"
    }
}

struct TotalInv: Decodable, Hashable {
    var valor: Double
    var coste: Double
    var latente: Double
    var rent: Double?
    var realizado: Double
    var dividendos: Double
    var comisiones: Double
    var terMedio: Double
    var dia: Double

    enum CodingKeys: String, CodingKey {
        case valor, coste, latente, rent, realizado, dividendos, comisiones, dia
        case terMedio = "ter_medio"
    }
}

struct PuntoSerieInv: Decodable, Hashable {
    var dia: String
    var valor: Double
    var metido: Double
    var referencia: Double?
}

struct ProyeccionInv: Decodable, Hashable {
    var tasa: Double?
    var anios: [Double]
}

struct ReferenciaInv: Decodable, Hashable {
    var simbolo: String
    var nombre: String?
}

struct InformeInv: Decodable {
    var perfil: PerfilInv
    var activos: [ActivoInv]
    var operaciones: [OperacionInv]
    var posiciones: [PosicionInv]
    var total: TotalInv
    var reparto: [String: Double]
    var serie: [PuntoSerieInv]
    var historicos: [String: [String: Double]]
    var referencia: ReferenciaInv
    var proyeccion: [String: ProyeccionInv]
    var stress: [String: Double]
    var reviews: [String]

    /// Lo que tienes ahora, de más a menos valor.
    var abiertas: [PosicionInv] {
        posiciones.filter { $0.cantidad > 0 }.sorted { ($0.valor ?? 0) > ($1.valor ?? 0) }
    }

    func activo(_ id: String) -> ActivoInv? { activos.first { $0.id == id } }
}

struct CandidatoInv: Decodable, Identifiable, Hashable {
    var simbolo: String
    var nombre: String
    var bolsa: String
    var clase: String
    var id: String { simbolo }

    /// Cotiza en una bolsa en euros (lo que Trade Republic usa: Xetra, mejor que Londres en dólares).
    var enEuros: Bool {
        [".DE", ".F", ".AS", ".PA", ".MI", ".MC", ".SG", ".MU", ".BE"].contains { simbolo.hasSuffix($0) }
    }
}

private struct ListaCandidatos: Decodable { var candidatos: [CandidatoInv] }
private struct TextoReview: Decodable { var fecha: String; var texto: String }
private struct ResultadoActivo: Decodable { var id: String; var fallos: [String] }
private struct ResultadoPrecios: Decodable { var fallos: [String] }

/// Cifras de dinero como en la web: «1.234,56 €», «+52,16 €», «+25,82 %».
enum DineroES {
    static func eur(_ x: Double?, _ decimales: Int = 2) -> String {
        guard let x, x.isFinite else { return "—" }
        let f = NumberFormatter()
        f.locale = FechasES.locale
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        f.minimumFractionDigits = decimales
        f.maximumFractionDigits = decimales
        return f.string(from: NSNumber(value: x)) ?? "\(FechasES.coma(x, decimales)) €"
    }

    /// Precios de una participación: con 4 decimales si vale menos de 10 €.
    static func precio(_ x: Double?) -> String { eur(x, (x ?? 10) < 10 ? 4 : 2) }

    static func signo(_ x: Double?) -> String {
        guard let x else { return "—" }
        return (x > 0 ? "+" : "") + eur(x)
    }

    static func pct(_ x: Double?) -> String {
        guard let x, x.isFinite else { return "—" }
        return (x > 0 ? "+" : "") + FechasES.coma(x, 2) + " %"
    }

    /// Para los ejes: «250 €», «12 k€».
    static func corto(_ x: Double) -> String {
        abs(x) >= 10_000 ? "\(Int((x / 1000).rounded())) k€" : "\(FechasES.miles(x)) €"
    }

    static func color(_ x: Double?) -> Color {
        guard let x, x != 0 else { return Tema.texto }
        return x > 0 ? Tema.acento : Tema.peligro
    }

    /// «1.234,56» y «1234.56» valen igual: con coma, los puntos son de miles.
    static func numero(_ s: String) -> Double? {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "€", with: "")
        if t.contains(",") {
            t = t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        }
        guard let n = Double(t), n.isFinite else { return nil }
        return n
    }

    /// Para rellenar un campo: «3,25» sin ceros de más.
    static func campo(_ x: Double?) -> String {
        guard let x, x != 0 else { return "" }
        var s = String(format: "%.6f", x)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s.replacingOccurrences(of: ".", with: ",")
    }
}

/// Los colores de las series de la web (--serie-1…8 de calma.css): una posición tiene el mismo color en las dos.
enum ColoresInv {
    static let serie: [Color] = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#6250d6", "#e34948"]
        .map { Color(uiColor: UIColor(hex: $0)) }

    static func de(_ i: Int) -> Color { serie[((i % serie.count) + serie.count) % serie.count] }

    static let tipos: [String: String] = ["etf": "ETF", "fondo": "Fondo", "accion": "Acción", "cripto": "Cripto",
                                          "bono": "Renta fija", "liquidez": "Liquidez", "otro": "Otro"]
    static let ordenTipos = ["etf", "fondo", "accion", "cripto", "bono", "liquidez", "otro"]
}

@MainActor @Observable
final class DatosInversiones {
    static let shared = DatosInversiones()

    private(set) var inf: InformeInv?
    private(set) var copia: Date?
    private(set) var cargando = false
    private(set) var error: String?
    var aviso: AvisoTom?
    /// La review que hay que enseñar (un enlace «?review=fecha» o la que se ha tocado).
    var reviewElegida: String?
    private(set) var textos: [String: String] = [:]

    static let ruta = "/api/inversiones"

    init() {
        if let r = Local.lee(Local.clave("GET", Self.ruta)), let i = try? JSONDecoder().decode(InformeInv.self, from: r.cuerpo) {
            inf = i
        }
    }

    func carga() async {
        guard !cargando else { return }
        cargando = true
        defer { cargando = false }
        do {
            let (crudo, fecha) = try await API.leeOCopia(Self.ruta)
            let nuevo = try JSONDecoder().decode(InformeInv.self, from: crudo)
            withAnimation(Tema.Muelle.pantalla) { inf = nuevo }
            copia = fecha
            error = nil
        } catch let e as DecodingError {
            error = "No entiendo lo que devuelve /api/inversiones (\(e.localizedDescription))"
        } catch {
            self.error = error.localizedDescription
        }
    }

    func avisa(_ texto: String, error: Bool = false, deshacer: (@MainActor () async -> Void)? = nil) {
        aviso = AvisoTom(texto: texto, error: error, deshacer: deshacer)
        AccessibilityNotification.Announcement(texto).post()
        if error { Haptica.shared.toca(.error) }
    }

    func quitaAviso() { aviso = nil }

    // MARK: operaciones

    /// Nueva (sin id) o cambiada. Sin red se queda en la cola y sale sola.
    func guardaOperacion(_ o: [String: Any]) async -> Bool {
        do {
            let r = try await API.escribeOEncola("/api/inversiones/operacion", json: o)
            Haptica.shared.toca(.marcar)
            if r == nil {
                avisa(API.avisoEncolado)
            } else {
                avisa(o["id"] == nil ? "Apuntada" : "Operación cambiada")
                await carga()
            }
            return true
        } catch {
            avisa("No se ha guardado: \(error.localizedDescription)", error: true)
            return false
        }
    }

    func borraOperacion(_ o: OperacionInv) async {
        do {
            let r = try await API.escribeOEncola("/api/inversiones/operacion/borra", json: ["id": o.id])
            guard let r, let vieja = try? JSONSerialization.jsonObject(with: r) as? [String: Any] else {
                avisa("Borrada. Se enviará en cuanto haya conexión")
                return
            }
            await carga()
            avisa("Operación borrada", deshacer: { [weak self] in
                do {
                    _ = try await API.datos("/api/inversiones/operacion", metodo: "POST", json: vieja)
                    await self?.carga()
                } catch {
                    self?.avisa("No se ha podido deshacer: \(error.localizedDescription)", error: true)
                }
            })
        } catch {
            avisa("No se ha borrado: \(error.localizedDescription)", error: true)
        }
    }

    // MARK: activos

    func busca(_ q: String) async throws -> [CandidatoInv] {
        let texto = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard texto.count >= 2 else { return [] }
        var permitidos = CharacterSet.urlQueryAllowed
        permitidos.remove(charactersIn: "&+=?#")
        let cod = texto.addingPercentEncoding(withAllowedCharacters: permitidos) ?? texto
        let r = try await API.datos("/api/inversiones/busca?q=\(cod)")
        return try JSONDecoder().decode(ListaCandidatos.self, from: r).candidatos
    }

    /// Devuelve el id con el que ha quedado, o nil si no se ha guardado. Baja sus precios (necesita red).
    func guardaActivo(_ a: [String: Any]) async -> String? {
        do {
            let r = try await API.datos("/api/inversiones/activo", metodo: "POST", json: a)
            let res = try JSONDecoder().decode(ResultadoActivo.self, from: r)
            if res.fallos.isEmpty {
                avisa("Activo guardado")
            } else {
                avisa("Guardado, pero Yahoo no da precios de \(a["simbolo"] as? String ?? "ese símbolo"): revísalo", error: true)
            }
            await carga()
            return res.id
        } catch {
            avisa("No se ha guardado: \(error.localizedDescription)", error: true)
            return nil
        }
    }

    func borraActivo(_ id: String) async -> Bool {
        do {
            _ = try await API.datos("/api/inversiones/activo/borra", metodo: "POST", json: ["id": id])
            avisa("Activo borrado")
            await carga()
            return true
        } catch {
            avisa(error.localizedDescription, error: true)
            return false
        }
    }

    func actualizaPrecios() async {
        do {
            let r = try await API.datos("/api/inversiones/precios", metodo: "POST", json: [String: Any]())
            let res = try JSONDecoder().decode(ResultadoPrecios.self, from: r)
            await carga()
            if !res.fallos.isEmpty {
                let nombres = res.fallos.map { $0.components(separatedBy: ":").first ?? $0 }.joined(separator: ", ")
                avisa("No se ha podido con: \(nombres)", error: true)
            } else {
                avisa("Precios al día")
            }
        } catch {
            avisa("No se ha podido: \(error.localizedDescription)", error: true)
        }
    }

    // MARK: perfil

    func guardaPerfil(_ p: PerfilInv) async -> Bool {
        let cuerpo: [String: Any] = [
            "edad": p.edad.map { $0 as Any } ?? NSNull(), "horizonte": p.horizonte, "objetivo": p.objetivo,
            "aportacion": p.aportacion, "estable": p.estable.map { $0 as Any } ?? NSNull(), "emergencia": p.emergencia,
            "tolerancia": p.tolerancia, "caida": p.caida, "broker": p.broker, "referencia": p.referencia, "notas": p.notas,
        ]
        let cambiaReferencia = p.referencia.uppercased() != inf?.perfil.referencia
        do {
            _ = try await API.datos("/api/inversiones/perfil", metodo: "POST", json: cuerpo)
            if cambiaReferencia {   // sin los precios de la referencia nueva no hay comparación
                _ = try? await API.datos("/api/inversiones/precios", metodo: "POST", json: [String: Any]())
            }
            avisa("Perfil guardado")
            await carga()
            return true
        } catch {
            avisa("No se ha guardado: \(error.localizedDescription)", error: true)
            return false
        }
    }

    // MARK: reviews

    /// El Markdown de una review (también sin red, si ya se leyó alguna vez).
    func review(_ fecha: String) async -> String? {
        if let t = textos[fecha] { return t }
        do {
            let (crudo, _) = try await API.leeOCopia("/api/inversiones/review/\(fecha)")
            let t = try JSONDecoder().decode(TextoReview.self, from: crudo).texto
            textos[fecha] = t
            return t
        } catch {
            return nil
        }
    }
}
