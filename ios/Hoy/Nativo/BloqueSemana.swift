import SwiftUI

/// El resumen de la semana (GET /api/semana): la actual contra la pasada, con las frases que compone el servidor.
/// Los domingos y lunes va arriba de Hoy y desplegado; el resto de días, abajo y plegado. El domingo a las 20:00
/// Avisos.swift manda además el mismo resumen como aviso local.
struct SemanaApi: Decodable {
    struct Entrenos: Decodable { var hechos: Int?; var planificados: Int? }
    struct Media: Decodable { var media: Int? }
    struct Peso: Decodable { var inicio: Double?; var fin: Double? }
    struct Periodo: Decodable {
        var desde: String?
        var hasta: String?
        var hechos: Int?
        var objetivo: Int?
        var entrenos: Entrenos?
        var sueno: Media?
        var pasos: Media?
        var peso: Peso?
    }
    struct Cambio: Decodable { var sueno: Int?; var pasos: Int? }

    var actual: Periodo
    var pasada: Periodo
    var cambio: Cambio?
    var resumen: [String]
}

struct BloqueSemana: View {
    /// Domingo o lunes: arriba y desplegado.
    let destacado: Bool
    @State private var datos: SemanaApi?
    @State private var copia: Date?
    @State private var abierto: Bool

    init(destacado: Bool) {
        self.destacado = destacado
        _abierto = State(initialValue: destacado)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            Button {
                withAnimation(Tema.Muelle.pantalla) { abierto.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: Tema.Espacio.s) {
                    Text("Tu semana").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
                    if let d = datos, let h = d.actual.hechos, let o = d.actual.objetivo, o > 0 {
                        Text("\(h)/\(o)")
                            .estiloEtiqueta().monospacedDigit()
                            .foregroundStyle(Tema.acento)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Tema.acentoSuave, in: Capsule())
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Tema.suave)
                        .rotationEffect(.degrees(abierto ? 180 : 0))
                }
                .padding(.top, Tema.Espacio.s)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tu semana")
            .accessibilityHint(abierto ? "Toca para plegar" : "Toca para desplegar")

            if abierto {
                Group {
                    if let d = datos { contenido(d) } else { vacio }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .task { await carga() }
    }

    private var vacio: some View {
        Text("Cargando el resumen de la semana…")
            .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            .frame(maxWidth: .infinity, alignment: .leading)
            .carta()
    }

    private func contenido(_ d: SemanaApi) -> some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            ForEach(Array(d.resumen.enumerated()), id: \.offset) { _, frase in
                Text(frase).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider().overlay(Tema.linea)
            // esta semana contra la pasada
            Grid(alignment: .leading, horizontalSpacing: Tema.Espacio.m, verticalSpacing: Tema.Espacio.s) {
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    Text("Esta").estiloEtiqueta().foregroundStyle(Tema.suave)
                    Text("Pasada").estiloEtiqueta().foregroundStyle(Tema.suave)
                }
                fila("Hábitos", Self.par(d.actual.hechos, d.actual.objetivo), Self.par(d.pasada.hechos, d.pasada.objetivo))
                fila("Entrenos", Self.par(d.actual.entrenos?.hechos, d.actual.entrenos?.planificados),
                     Self.par(d.pasada.entrenos?.hechos, d.pasada.entrenos?.planificados))
                fila("Sueño", Self.horas(d.actual.sueno?.media), Self.horas(d.pasada.sueno?.media), cambio: Self.cambioSueno(d.cambio?.sueno))
                fila("Pasos", Self.miles(d.actual.pasos?.media), Self.miles(d.pasada.pasos?.media))
                fila("Peso", Self.pesos(d.actual.peso), Self.pesos(d.pasada.peso))
            }
            if let copia {
                Label(API.notaCopia(copia), systemImage: "wifi.slash")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.aviso)
            }
        }
        .carta()
        .accessibilityElement(children: .contain)
    }

    private func fila(_ nombre: String, _ actual: String, _ pasada: String, cambio: String? = nil) -> some View {
        GridRow {
            Text(nombre).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            VStack(alignment: .leading, spacing: 0) {
                Text(actual).font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto).monospacedDigit()
                if let cambio { Text(cambio).font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.suave) }
            }
            Text(pasada).font(Tema.fuente(.texto)).foregroundStyle(Tema.suave).monospacedDigit()
        }
    }

    private func carga() async {
        guard let (crudo, fecha) = try? await API.leeOCopia("/api/semana"),
              let nuevo = try? JSONDecoder().decode(SemanaApi.self, from: crudo) else { return }
        withAnimation(Tema.Muelle.pantalla) {
            datos = nuevo
            copia = fecha
        }
    }

    // MARK: formatos

    private static func par(_ a: Int?, _ b: Int?) -> String {
        guard let a, let b, b > 0 else { return "—" }
        return "\(a)/\(b)"
    }

    private static func horas(_ m: Int?) -> String { m.map(PantallaHoy.hm) ?? "—" }

    private static func miles(_ n: Int?) -> String { n.map(PantallaHoy.miles) ?? "—" }

    private static func cambioSueno(_ m: Int?) -> String? {
        guard let m, abs(m) >= 5 else { return nil }
        return (m > 0 ? "+" : "−") + "\(abs(m)) min"
    }

    private static func pesos(_ p: SemanaApi.Peso?) -> String {
        func kg(_ x: Double) -> String { String(format: "%.1f", x).replacingOccurrences(of: ".", with: ",") }
        guard let ini = p?.inicio, let fin = p?.fin else { return "—" }
        return abs(ini - fin) < 0.05 ? "\(kg(fin)) kg" : "\(kg(ini)) → \(kg(fin))"
    }
}
