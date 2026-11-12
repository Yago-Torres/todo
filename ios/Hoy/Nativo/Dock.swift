import SwiftUI

/// La barra de abajo, nativa: la misma que la web (calma.css → nav.c-dock), grafito flotante con la gota lima que se
/// desliza con muelle hasta la sección actual. Hoy y Hábitos son pantallas nativas; el resto abre la web en su ruta.
struct Dock: View {
    struct Entrada: Identifiable {
        let clave: String   // el id en la disposición "app-dock" (orden y ocultos, Configurar → Pantallas)
        let href: String
        let nombre: String
        let icono: String
        var id: String { href }
    }

    static let entradas: [Entrada] = [
        Entrada(clave: "hoy", href: "/", nombre: "Hoy", icono: "sun.max"),
        Entrada(clave: "habitos", href: "/habitos.html", nombre: "Hábitos", icono: "checkmark.circle"),
        Entrada(clave: "pendientes", href: "/pendientes.html", nombre: "Pendientes", icono: "list.bullet"),
        Entrada(clave: "entreno", href: "/entreno.html", nombre: "Entreno", icono: "dumbbell"),
        Entrada(clave: "salud", href: "/salud.html", nombre: "Salud", icono: "heart"),
        Entrada(clave: "comida", href: "/comida.html", nombre: "Comida", icono: "fork.knife"),
        Entrada(clave: "gastos", href: "/gastos.html", nombre: "Gastos", icono: "creditcard"),
        Entrada(clave: "documentos", href: "/documentos.html", nombre: "Docs", icono: "doc.text"),
    ]

    let actual: String
    let toca: (String) -> Void

    /// Las entradas en el orden elegido, sin las ocultas (Hoy no se puede ocultar).
    static func visibles() -> [Entrada] {
        var b = Aspecto.shared.bloques("app-dock")
        b.ocultos.removeAll { $0 == "hoy" }
        return b.aplica(entradas.map(\.clave)).compactMap { c in entradas.first { $0.clave == c } }
    }

    /// Mientras el dedo arrastra por la barra: dónde está (x) y la sección que tiene debajo.
    @State private var dedo: CGFloat?
    @State private var bajoDedo: Int?

    var body: some View {
        let lista = Self.visibles()
        let actualIdx = lista.firstIndex { $0.href == actual }
        let marcada = bajoDedo ?? actualIdx
        GeometryReader { geo in
            let ancho = max(1, geo.size.width - 8)
            let celda = ancho / CGFloat(max(lista.count, 1))
            // la gota: en su sección, o siguiendo al dedo mientras arrastra
            let xGota: CGFloat? = dedo.map { min(max($0, 4 + celda / 2), 4 + ancho - celda / 2) }
                ?? marcada.map { 4 + celda * (CGFloat($0) + 0.5) }
            ZStack(alignment: .topLeading) {
                if let xGota {
                    Circle()
                        .fill(Tema.gota)
                        .frame(width: 50, height: 50)
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                        .position(x: xGota, y: 31 - 22)
                        .animation(dedo == nil ? Tema.Muelle.gota : .interactiveSpring(response: 0.18, dampingFraction: 0.86), value: xGota)
                }
                HStack(spacing: 0) {
                    ForEach(Array(lista.enumerated()), id: \.element.id) { i, e in
                        let activa = i == marcada
                        VStack(spacing: 3) {
                            Image(systemName: e.icono)
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(activa ? Tema.gotaTexto : Tema.dockTexto)
                                .frame(height: 50)
                                .offset(y: activa ? -22 : 0)
                            Text(e.nombre)
                                .font(.system(size: 10, weight: activa ? .semibold : .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .foregroundStyle(activa ? Color.white : Tema.dockTexto)
                                .offset(y: activa ? -14 : -8)
                        }
                        .frame(width: celda, height: 62)
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(e.nombre)
                        .accessibilityAddTraits(i == actualIdx ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { toca(e.href) }
                    }
                }
                .padding(.horizontal, 4)
                .animation(Tema.Muelle.gota, value: marcada)
            }
            .frame(width: geo.size.width, height: 62)
            .background(Tema.dock, in: RoundedRectangle(cornerRadius: Tema.Radio.dock, style: .continuous))
            .contentShape(Rectangle())
            // tocar y arrastrar son el mismo gesto: la gota sigue al dedo y al soltar se va a la sección de debajo
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { g in
                    dedo = g.location.x
                    let i = Int(((g.location.x - 4) / celda).rounded(.down))
                    let idx = min(max(i, 0), lista.count - 1)
                    if idx != bajoDedo {
                        if bajoDedo != nil { Haptica.shared.toca(.marcar) }
                        bajoDedo = idx
                    }
                }
                .onEnded { _ in
                    let idx = bajoDedo
                    withAnimation(Tema.Muelle.gota) {
                        dedo = nil
                        bajoDedo = nil
                    }
                    if let idx, lista.indices.contains(idx) { toca(lista[idx].href) }
                })
        }
        .frame(height: 62)
        .shadow(color: .black.opacity(0.2), radius: 14, y: 8)
        .frame(maxWidth: 560)
        .padding(.horizontal, 8)
        .sensoryFeedback(.selection, trigger: actual)
    }
}
