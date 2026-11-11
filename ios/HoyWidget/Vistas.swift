import SwiftUI
import WidgetKit
import AppIntents

func rutaURL(_ ruta: String) -> URL {
    var c = URLComponents()
    c.scheme = "hoy"
    c.host = "ruta"
    c.queryItems = [URLQueryItem(name: "r", value: ruta)]
    return c.url ?? URL(string: "hoy://ruta")!
}

struct HoyWidgetVista: View {
    @Environment(\.widgetFamily) private var familia
    let entrada: Entrada

    private var esAccesorio: Bool {
        switch familia {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: return true
        default: return false
        }
    }

    var body: some View {
        contenido
            .widgetURL(rutaURL(rutaPara(familia)))
            .containerBackground(for: .widget) {
                if esAccesorio { AccessoryWidgetBackground() } else { Paleta.fondo }
            }
    }

    private func rutaPara(_ f: WidgetFamily) -> String {
        switch f {
        case .systemMedium: return "/pendientes.html"
        case .systemLarge: return "/habitos.html"
        default: return "/"
        }
    }

    @ViewBuilder private var contenido: some View {
        switch entrada.estado {
        case .sinClaves:
            mensaje("Abre Tom para configurarlo", detalle: nil)
        case .sinDatos(let motivo):
            mensaje("Tom", detalle: "Sin datos: \(motivo)")
        case .datos(let h):
            let r = Resumen(h, ahora: entrada.date)
            switch familia {
            case .accessoryInline: LineaVista(r: r)
            case .accessoryCircular: Anillos(valores: r.progresos, grosor: 5, separacion: 2).padding(4)
            case .accessoryRectangular: RectangularVista(r: r)
            case .systemMedium: MedianoVista(r: r)
            case .systemLarge: GrandeVista(r: r)
            default: PequenoVista(r: r)
            }
        }
    }

    @ViewBuilder private func mensaje(_ titulo: String, detalle: String?) -> some View {
        if familia == .accessoryInline {
            Text(titulo)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(titulo)
                    .font(.system(size: esAccesorio ? 12 : 14, weight: .bold))
                    .foregroundStyle(esAccesorio ? Color.primary : Paleta.texto)
                if let detalle {
                    Text(detalle)
                        .font(.system(size: 11))
                        .foregroundStyle(esAccesorio ? Color.secondary : Paleta.suave)
                }
            }
            .minimumScaleFactor(0.7)
            .padding(0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

struct PequenoVista: View {
    let r: Resumen
    var body: some View {
        Anillos(valores: r.progresos, grosor: 12)
    }
}

struct PendienteVista: View {
    let r: Resumen
    let cuantas: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(r.tareas.isEmpty ? "Pendiente" : "Pendiente · \(r.tareas.count)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Paleta.suave)
                .padding(.bottom, 2)
            if r.tareas.isEmpty {
                Text("Nada que venza hoy").font(.system(size: 13)).foregroundStyle(Paleta.texto)
            }
            ForEach(Array(r.tareas.prefix(cuantas).enumerated()), id: \.offset) { _, t in
                Text("→ " + Resumen.linea(t))
                    .font(.system(size: 13))
                    .foregroundStyle(Paleta.texto)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if r.tareas.count > cuantas {
                Text("y \(r.tareas.count - cuantas) más").font(.system(size: 11)).foregroundStyle(Paleta.suave)
            }
        }
    }
}

struct MedianoVista: View {
    let r: Resumen
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Anillos(valores: r.progresos, grosor: 10)
                .frame(width: 100, height: 100)
            VStack(alignment: .leading, spacing: 6) {
                Link(destination: rutaURL("/pendientes.html")) {
                    PendienteVista(r: r, cuantas: r.textoGastos == nil ? 3 : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let gastos = r.textoGastos {
                    LineaGastos(texto: gastos, pasado: r.gastosPasados)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct GrandeVista: View {
    let r: Resumen

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Anillos(valores: r.progresos, grosor: 8)
                    .frame(width: 84, height: 84)
                Link(destination: rutaURL("/pendientes.html")) {
                    PendienteVista(r: r, cuantas: 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let gastos = r.textoGastos {
                LineaGastos(texto: gastos, pasado: r.gastosPasados)
                    .padding(.top, 8)
            }
            Text("Hábitos · \(r.hechos)/\(r.habitos.count)" + (r.enJuego ? " · racha en juego" : ""))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(r.enJuego ? Paleta.aviso : Paleta.suave)
                .padding(.top, 10)
                .padding(.bottom, 4)
            ForEach(Array(r.habitos.prefix(r.textoGastos == nil ? 10 : 9))) { h in
                FilaHabito(h: h, enJuego: r.enJuego)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Lo que queda del presupuesto del ciclo de gastos; toca para abrir Gastos.
struct LineaGastos: View {
    let texto: String
    let pasado: Bool

    var body: some View {
        Link(destination: rutaURL("/gastos.html")) {
            Label {
                Text(texto)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } icon: {
                Image(systemName: "eurosign.circle")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(pasado ? Paleta.aviso : Paleta.suave)
        }
    }
}

struct FilaHabito: View {
    let h: Habito
    let enJuego: Bool

    var body: some View {
        if h.hecho {
            fila
        } else {
            Button(intent: MarcaHabitoIntent(habito: h.id, nombre: h.n, hecho: true)) { fila }
                .buttonStyle(.plain)
        }
    }

    private var fila: some View {
        HStack(spacing: 0) {
            Text(h.hecho ? "✓ " : "○ ")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(h.hecho ? Color(hex: h.c) : Paleta.suave)
            Text(h.n)
                .font(.system(size: 13, weight: !h.hecho && h.plan ? .bold : .regular))
                .foregroundStyle(h.hecho ? Paleta.suave : Paleta.texto)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            if h.racha > 0 {
                Text("\(h.racha) d")
                    .font(.system(size: 12))
                    .foregroundStyle(h.racha >= 2 && !h.hecho && enJuego ? Paleta.aviso : Paleta.suave)
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
    }
}

struct RectangularVista: View {
    let r: Resumen
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(r.hechos)/\(r.habitos.count) hábitos" + (r.enJuego ? " · racha en juego" : ""))
                .font(.system(size: 13, weight: .bold))
            Text("\(r.textoPasos) pasos · \(r.textoSueno) dormido")
                .font(.system(size: 12))
            Text(r.tareas.first.map(Resumen.linea) ?? "Nada que venza hoy")
                .font(.system(size: 12))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LineaVista: View {
    let r: Resumen
    var body: some View {
        Text("\(r.hechos)/\(r.habitos.count) hábitos · \(r.textoPasos) pasos · \(r.textoSueno)")
    }
}
