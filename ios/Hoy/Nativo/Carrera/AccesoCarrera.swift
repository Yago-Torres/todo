import SwiftUI

/// La tarjeta de arriba del todo en Entreno: lleva a Carrera (el plan de 5k) con la próxima sesión a la vista.
/// Carrera se abre de lado como una sección más y tiene su «‹ Entreno» para volver.
struct AccesoCarrera: View {
    @State private var datos = CarreraDatos.shared

    private var proxima: InformeCarrera.Agenda? {
        let hoy = Fecha.hoy()
        return datos.informe?.agenda.first { !$0.hecho && $0.dia >= hoy }
    }

    private var detalle: String {
        var t = "Plan de 5k"
        if let e = datos.informe?.estimacion { t += " · estimado " + tiempo(e.seg) }
        if let p = proxima { t += " · " + FechasES.corta(p.dia) + ": " + p.n }
        return t
    }

    private func tiempo(_ s: Double) -> String {
        let n = Int(s.rounded())
        return String(n / 60) + ":" + (n % 60 < 10 ? "0" : "") + String(n % 60)
    }

    var body: some View {
        Button {
            Haptica.shared.toca(.marcar)
            Navegador.shared.toca("/carrera.html")
        } label: {
            HStack(spacing: Tema.Espacio.m) {
                Image(systemName: "figure.run")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Tema.acento)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Carrera").font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
                    Text(detalle).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Tema.tenue)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .carta()
        .accessibilityHint("Abre el plan de carrera")
        .task { if datos.informe == nil { await datos.carga() } }
    }
}
