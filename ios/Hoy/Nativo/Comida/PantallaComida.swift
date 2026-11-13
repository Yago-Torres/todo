import SwiftUI

/// Comida en nativo (13/11): lo principal es la LISTA de alimentos (lo que hay en casa o se quiere comprar), cada uno con
/// sus macros por 100 g y por la cantidad puesta, y el total frente al objetivo del día. De ahí sale «Hazme una receta»:
/// eliges unos cuantos y Claude propone una receta con ellos, con pasos y macros. Las recetas buenas se guardan.
/// El menú semanal sigue (lo usa el bot de Telegram), en la tercera pestaña.
struct PantallaComida: View {
    enum Seccion: Hashable { case lista, recetas, menu }

    @State private var datos = DatosLista.shared
    @State private var seccion = Seccion.lista
    @State private var haciendoReceta = false
    @State private var abierta: RecetaLista?

    /// Las pestañas como bloques de «app-comida»: Configurar → Pantallas cambia su orden y oculta las que sobren.
    static let bloques: [(String, String)] = [("lista", "Lista"), ("recetas", "Recetas"), ("menu", "Menú semanal")]

    private var pestanas: [Seccion] {
        let visibles = Aspecto.shared.bloques("app-comida").aplica(Self.bloques.map { $0.0 }).compactMap { id -> Seccion? in
            switch id {
            case "lista": return .lista
            case "recetas": return .recetas
            case "menu": return .menu
            default: return nil
            }
        }
        return visibles.isEmpty ? [.lista] : visibles
    }

    private func titulo(_ s: Seccion) -> String {
        switch s {
        case .lista: return "Lista · \(datos.cesta.items.filter { !$0.hecho }.count)"
        case .recetas: return "Recetas · \(datos.cesta.favoritas.count)"
        case .menu: return "Menú semanal"
        }
    }

    var body: some View {
        VStack(spacing: Tema.Espacio.m) {
            cabecera
            if pestanas.count > 1 {
                SelectorPildoras(opciones: pestanas.map { (valor: $0, titulo: titulo($0)) }, seleccion: $seccion)
            }
            Group {
                switch seccion {
                case .lista: ListaComida(haciendoReceta: $haciendoReceta)
                case .recetas: RecetasComida(haciendoReceta: $haciendoReceta, abierta: $abierta)
                case .menu: MenuSemanaComida()
                }
            }
            .transition(.opacity)
        }
        .padding(.top, Tema.Espacio.s)
        .animation(Tema.Muelle.pantalla, value: seccion)
        .tostada(datos.aviso) { datos.aviso = nil }
        .task { await datos.carga() }
        .onAppear { if !pestanas.contains(seccion), let p = pestanas.first { seccion = p } }
        .sheet(isPresented: $haciendoReceta) { HojaHazReceta() }
        .sheet(item: $abierta) { r in DetalleRecetaLista(receta: r) }
    }

    private var cabecera: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.xs) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    if let o = datos.cesta.objetivo, o.kcal > 0 {
                        Text("Objetivo del día: \(Formato.entero(o.kcal)) kcal · \(Formato.entero(o.proteina)) g de proteína")
                            .estiloEtiqueta().foregroundStyle(Tema.suave)
                            .contentTransition(.numericText())
                    } else {
                        Text("Lo que hay y lo que comes").estiloEtiqueta().foregroundStyle(Tema.suave)
                    }
                    Text("Comida").font(Tema.fuente(.titulo)).foregroundStyle(Tema.texto)
                }
                Spacer()
                if !datos.cargado && datos.error == nil {
                    ProgressView().tint(Tema.suave)
                }
            }
            if let copia = datos.copia, seccion != .menu {
                Label(API.notaCopia(copia), systemImage: "wifi.slash")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.aviso)
            }
            if !datos.cargado, let error = datos.error {
                Text(error).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro)
            }
        }
        .padding(.horizontal, Tema.Espacio.l)
    }
}

// MARK: colores de los macros

/// Proteína, hidratos y grasa siempre del mismo color en toda la sección (todos del tema).
enum ColorMacro {
    static var prot: Color { Tema.acento }
    static var hc: Color { Tema.aviso }
    static var grasa: Color { Tema.suave }
}

/// La barra de reparto de kcal entre proteína, hidratos y grasa.
struct BarraMacros: View {
    let macros: Macros
    var alto: CGFloat = 8

    var body: some View {
        let r = macros.reparto
        GeometryReader { g in
            HStack(spacing: r.prot > 0 && r.hc > 0 ? 2 : 0) {
                if r.prot > 0 { Capsule().fill(ColorMacro.prot).frame(width: max(2, (g.size.width - 4) * r.prot)) }
                if r.hc > 0 { Capsule().fill(ColorMacro.hc).frame(width: max(2, (g.size.width - 4) * r.hc)) }
                if r.grasa > 0 { Capsule().fill(ColorMacro.grasa).frame(width: max(2, (g.size.width - 4) * r.grasa)) }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Capsule().fill(Tema.carta2))
        }
        .frame(height: alto)
        .animation(Tema.Muelle.pantalla, value: macros)
        .accessibilityHidden(true)
    }
}

/// «● Proteína 34 g»
struct LeyendaMacro: View {
    let nombre: String
    let gramos: Double
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(nombre).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            Text("\(Formato.entero(gramos)) g").font(Tema.fuente(.pequeno, peso: .semibold)).monospacedDigit()
                .foregroundStyle(Tema.texto)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }
}

/// Una barra de progreso hacia un objetivo, con su cifra.
struct BarraObjetivo: View {
    let nombre: String
    let valor: Double
    let objetivo: Double
    let unidad: String
    var color: Color = Tema.acento

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(nombre).font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.suave)
                Spacer()
                Text("\(Formato.entero(valor)) / \(Formato.entero(objetivo)) \(unidad)")
                    .font(Tema.fuente(.pequeno)).monospacedDigit()
                    .foregroundStyle(valor > objetivo * 1.05 ? Tema.aviso : Tema.texto)
                    .contentTransition(.numericText())
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Tema.carta2)
                    Capsule().fill(color).frame(width: g.size.width * min(max(valor / max(objetivo, 1), 0), 1))
                }
            }
            .frame(height: 5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(nombre): \(Formato.entero(valor)) de \(Formato.entero(objetivo)) \(unidad == "g" ? "gramos" : "kilocalorías")")
    }
}
