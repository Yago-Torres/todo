import SwiftUI

/// La barra de abajo, nativa: la misma que la web (calma.css → nav.c-dock), grafito flotante con la gota lima que se
/// desliza con muelle hasta la sección actual. Hoy y Hábitos son pantallas nativas; el resto abre la web en su ruta.
struct Dock: View {
    struct Entrada: Identifiable {
        let href: String
        let nombre: String
        let icono: String
        var id: String { href }
    }

    static let entradas: [Entrada] = [
        Entrada(href: "/", nombre: "Hoy", icono: "sun.max"),
        Entrada(href: "/habitos.html", nombre: "Hábitos", icono: "checkmark.circle"),
        Entrada(href: "/pendientes.html", nombre: "Pendientes", icono: "list.bullet"),
        Entrada(href: "/entreno.html", nombre: "Entreno", icono: "dumbbell"),
        Entrada(href: "/salud.html", nombre: "Salud", icono: "heart"),
        Entrada(href: "/comida.html", nombre: "Comida", icono: "fork.knife"),
        Entrada(href: "/gastos.html", nombre: "Gastos", icono: "creditcard"),
        Entrada(href: "/documentos.html", nombre: "Docs", icono: "doc.text"),
    ]

    let actual: String
    let toca: (String) -> Void
    @Namespace private var espacio

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.entradas) { e in
                let activa = e.href == actual
                Button {
                    toca(e.href)
                } label: {
                    VStack(spacing: 3) {
                        ZStack {
                            if activa {
                                Circle()
                                    .fill(Tema.gota)
                                    .frame(width: 50, height: 50)
                                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                                    .matchedGeometryEffect(id: "gota", in: espacio)
                            }
                            Image(systemName: e.icono)
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(activa ? Tema.gotaTexto : Tema.dockTexto)
                        }
                        .frame(height: 50)
                        .offset(y: activa ? -22 : 0)
                        Text(e.nombre)
                            .font(.system(size: 10, weight: activa ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(activa ? Color.white : Tema.dockTexto)
                            .offset(y: activa ? -14 : -8)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(e.nombre)
                .accessibilityAddTraits(activa ? .isSelected : [])
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 62)
        .background(Tema.dock, in: RoundedRectangle(cornerRadius: Tema.Radio.dock, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 14, y: 8)
        .frame(maxWidth: 560)
        .padding(.horizontal, 8)
        .animation(Tema.Muelle.gota, value: actual)
        .sensoryFeedback(.selection, trigger: actual)
    }
}
