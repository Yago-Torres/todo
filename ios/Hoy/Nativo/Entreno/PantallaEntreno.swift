import SwiftUI

/// Entreno en nativo (lo de static/entreno.html): lo que toca hoy y la semana planificada (mover y planificar), el
/// modo entreno serie a serie con su descanso a pantalla completa, la rutina guiada, músculos, progreso, historial,
/// peso, carrera y escalada. Funciona sin red: lo hecho se guarda en el iPhone y sale al volver la conexión.
/// Los bloques se ordenan y esconden con PantallaEditable (disposición «app-entreno»).
struct PantallaEntreno: View {
    /// Ids estables (se guardan en el servidor): no cambiarlos; uno nuevo, al final.
    static let bloques: [(String, String)] = [
        ("hoy", "Hoy"), ("semana", "Semana"), ("manana", "Cada mañana"), ("musculos", "Músculos"),
        ("progreso", "Progreso"), ("historial", "Historial"), ("carrera", "Carrera"), ("escalada", "Escalada"),
        ("peso", "Peso"),
    ]

    @State private var datos = DatosEntreno.shared
    @State private var sesion = SesionEnCurso.shared
    @State private var guia = GuiaEnCurso.shared
    @State private var escalada = EscaladaDatos.shared
    @State private var vivo = VivoEscalada.shared
    @State private var viendo: VistaRutina.Ver?
    @State private var verCarrera = false
    @Environment(\.scenePhase) private var fase

    var body: some View {
        PantallaEditable(pantalla: "app-entreno", titulo: "Entreno", bloques: Self.bloques, recarga: {
            await datos.recarga()
            await escalada.carga()
        }) { editar in
            cabecera(editar)
            avisos
        } bloque: { id in
            bloque(id)
        }
        .scrollDismissesKeyboard(.interactively)
        .task {
            await datos.carga()
            sesion.reanuda()
            guia.reanuda()
            await escalada.carga()
        }
        .onChange(of: fase) { _, nueva in
            if nueva == .active { Task { await datos.carga(margen: 30) } }
            if nueva == .background { datos.guardaYa() }
        }
        .sheet(item: $viendo) { v in
            VistaRutina(ver: v) { viendo = nil }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $verCarrera) {
            ZStack {
                Tema.fondo.ignoresSafeArea()
                PantallaCarrera(enHoja: true)
            }
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $sesion.visible) {
            VistaSesion()
        }
        .fullScreenCover(isPresented: $guia.visible) {
            VistaGuia()
        }
        .fullScreenCover(isPresented: $vivo.enVivo) {
            PantallaEnVivo()
        }
    }

    @ViewBuilder private func bloque(_ id: String) -> some View {
        if datos.cargado {
            switch id {
            case "hoy": TarjetaHoyEntreno(viendo: $viendo)
            case "semana": TarjetaSemana(viendo: $viendo)
            case "manana": TarjetaManana()
            case "musculos": TarjetaMusculos()
            case "progreso": TarjetaProgreso()
            case "historial": TarjetaHistorial()
            case "carrera": TarjetaCarreraSemana { verCarrera = true }
            case "escalada": if escalada.activa { TarjetaEscalada() }
            case "peso": TarjetaPeso()
            default: EmptyView()
            }
        }
    }

    private func cabecera(_ editar: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(FormatoEnt.larga(datos.hoy)).estiloEtiqueta().foregroundStyle(Tema.suave)
                Text("Entreno").font(Tema.fuente(.titulo)).foregroundStyle(Tema.texto)
            }
            Spacer()
            if let t = datos.textoGuardado {
                Label(t, systemImage: datos.guardado == .enCola ? "wifi.slash" : "arrow.triangle.2.circlepath")
                    .font(Tema.fuente(.pequeno))
                    .foregroundStyle(datos.guardado == .guardando ? Tema.suave : Tema.aviso)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .transition(.opacity)
            }
            Button("Editar", action: editar)
                .font(Tema.fuente(.pequeno, peso: .medium))
                .foregroundStyle(Tema.acento)
        }
        .padding(.top, Tema.Espacio.s)
        .animation(Tema.Muelle.toque, value: datos.textoGuardado)
    }

    @ViewBuilder private var avisos: some View {
        if let copia = datos.copia {
            Label(API.notaCopia(copia), systemImage: "wifi.slash")
                .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.aviso)
        }
        if let aviso = datos.aviso {
            HStack(alignment: .top) {
                Text(aviso).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro)
                Spacer()
                Button { datos.aviso = nil } label: { Image(systemName: "xmark") }
                    .foregroundStyle(Tema.suave)
                    .accessibilityLabel("Quitar el aviso")
            }
            .carta(relleno: Tema.Espacio.m)
        }
        if !datos.cargado {
            Text(datos.cargando ? "Cargando…" : "Sin datos todavía. Tira hacia abajo para cargar.")
                .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                .carta()
        }
    }
}

// MARK: piezas comunes

/// El título de una carta: nombre, a la derecha una etiqueta o un botón.
struct TituloEnt<Derecha: View>: View {
    let titulo: String
    @ViewBuilder var derecha: Derecha

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tema.Espacio.s) {
            Text(titulo).font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Tema.Espacio.s)
            derecha
        }
    }
}

extension TituloEnt where Derecha == EmptyView {
    init(_ titulo: String) {
        self.titulo = titulo
        derecha = EmptyView()
    }
}

struct ChipEnt: View {
    let texto: String
    var color: Color = Tema.acento
    var fondo: Color = Tema.acentoSuave

    var body: some View {
        Text(texto)
            .font(Tema.fuente(.pequeno, peso: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(fondo, in: Capsule())
    }
}

struct BarraEnt: View {
    let valor: Double
    var color: Color = Tema.acento

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Tema.carta2)
                Capsule().fill(color).frame(width: g.size.width * min(max(valor, 0), 1))
            }
        }
    }
}

/// Botón de Calma: relleno de acento (principal) o de carta2.
struct BotonEnt: ButtonStyle {
    var principal = false
    var alto: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Tema.fuente(.destacado))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: alto)
            .padding(.horizontal, Tema.Espacio.m)
            .foregroundStyle(principal ? Tema.acentoTexto : Tema.texto)
            .background(principal ? Tema.acento : Tema.carta2,
                        in: RoundedRectangle(cornerRadius: Tema.Radio.boton, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Tema.Muelle.toque, value: configuration.isPressed)
    }
}

/// Un botón pequeño de texto, en acento.
struct BotonMini: ButtonStyle {
    var color: Color = Tema.acento

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Tema.fuente(.pequeno, peso: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Tema.carta2, in: Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
