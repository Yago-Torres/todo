import SwiftUI

// Un bloque de Hoy que tenía la web (hoy.html) y faltaba en Tom: «Tu año» (un punto por día desde el 1 de enero, más
// intenso cuantos más hábitos hechos). Sale de la misma /api/hoy que el resto de Hoy (con su copia en Local, así que sin
// red también); el modelo compartido `Hoy` no lo trae, así que se lee aparte de esa copia, una vez por versión.

/// Lo de /api/hoy que solo usa este bloque.
private struct ExtrasHoy: Decodable {
    var anio: [Int]?
    var hoy: String?
}

@MainActor
private enum CacheExtrasHoy {
    static var fecha: Date?
    static var valor: ExtrasHoy?

    /// La copia guardada de /api/hoy, decodificada solo cuando cambia.
    static func lee() -> ExtrasHoy? {
        guard let r = Local.lee(Local.clave("GET", "/api/hoy")) else { return valor }
        if r.fecha != fecha || valor == nil {
            valor = try? JSONDecoder().decode(ExtrasHoy.self, from: r.cuerpo)
            fecha = r.fecha
        }
        return valor
    }
}

/// El año en puntos: 53 columnas (semanas) × 7 filas (lunes a domingo), como la web.
struct BloqueAnioHoy: View {
    @State private var datos = DatosNativos.shared

    var body: some View {
        let _ = datos.hoy
        if let x = CacheExtrasHoy.lee(), let anio = x.anio, !anio.isEmpty, let hoy = x.hoy ?? Optional(Fecha.hoy()) {
            let completos = anio.filter { $0 >= 3 }.count
            VStack(alignment: .leading, spacing: Tema.Espacio.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Tu año").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
                    Spacer()
                    Text("\(completos) días completos").font(Tema.fuente(.pequeno)).monospacedDigit().foregroundStyle(Tema.suave)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Tema.tenue)
                }
                Rejilla(anio: anio, hoy: hoy)
                    .aspectRatio(53.0 / 7.0, contentMode: .fit)
                    .accessibilityElement()
                    .accessibilityLabel("Año \(hoy.prefix(4)): \(completos) días con casi todos los hábitos hechos de \(anio.count) días que van")
                HStack {
                    Text("ene"); Spacer(); Text("Más intenso, más hábitos hechos"); Spacer(); Text("dic")
                }
                .font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.suave)
            }
            .carta()
            .contentShape(Rectangle())
            .onTapGesture { Navegador.shared.toca("/anio.html") }   // tu año en números (PantallaAnio)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Abre tu año en números")
        }
    }

    private struct Rejilla: View {
        let anio: [Int]
        let hoy: String

        var body: some View {
            Canvas { ctx, size in
                let lado = min(size.width / 53, size.height / 7)
                let hueco = max(1, lado * 0.15)
                let año = Int(hoy.prefix(4)) ?? 2026
                var cal = Calendar(identifier: .gregorian)
                cal.firstWeekday = 2
                guard let ini = cal.date(from: DateComponents(year: año, month: 1, day: 1)) else { return }
                // la fila del 1 de enero (lunes = 0)
                let desfase = (cal.component(.weekday, from: ini) + 5) % 7
                let dias = cal.range(of: .day, in: .year, for: ini)?.count ?? 365
                for k in 0..<dias {
                    let pos = k + desfase
                    let r = CGRect(x: CGFloat(pos / 7) * lado, y: CGFloat(pos % 7) * lado,
                                   width: lado - hueco, height: lado - hueco)
                    let forma = Path(roundedRect: r, cornerRadius: lado * 0.2)
                    if k < anio.count {
                        let n = anio[k]
                        ctx.fill(forma, with: .color(n == 0 ? Tema.carta2 : Tema.acento.opacity([0, 0.35, 0.68, 1][min(3, n)])))
                        if k == anio.count - 1 { ctx.stroke(forma, with: .color(Tema.texto), lineWidth: 1.5) }
                    } else {
                        ctx.stroke(forma, with: .color(Tema.linea), lineWidth: 0.5)
                    }
                }
            }
        }
    }
}
