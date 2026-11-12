import SwiftUI

/// Salud en nativo (lo de static/salud.html): la puntuación de anoche, la noche hora a hora, las fases por noche, la
/// puntuación del último mes, el peso con su media de 7 días, la composición y los pasos. Los datos llegan cada mañana
/// de Salud (los manda la app, Hoy/Salud.swift); aquí solo se leen de /api/sueno, y sin red sale la última copia.
struct PantallaSalud: View {
    /// Los bloques (ids estables: se guardan en la disposición «app-salud»).
    static let bloques: [(String, String)] = [
        ("anoche", "Anoche"), ("noche", "La noche"), ("fases", "Fases por noche"), ("puntuacion", "Puntuación"),
        ("peso", "Peso"), ("composicion", "Composición"), ("pasos", "Pasos"), ("como", "Cómo se calcula"),
    ]

    @State private var datos = DatosSalud.shared
    @State private var periodo = PeriodoSalud.quincena

    var body: some View {
        PantallaEditable(pantalla: "app-salud", titulo: "Salud", bloques: Self.bloques,
                         recarga: { await datos.recarga() }) { editar in
            cabecera(editar)
        } bloque: { id in
            bloque(id)
        } pie: {
            if let error = datos.error, datos.informe == nil {
                Text(error).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro).carta()
            } else if datos.informe == nil {
                Text("Cargando…").font(Tema.fuente(.texto)).foregroundStyle(Tema.suave).carta()
            }
            if periodo.rawValue > 30 && datos.informe != nil {
                Text("Del sueño y los pasos el servidor guarda las últimas 30 noches.")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.tenue)
            }
        }
        .task { await datos.carga() }
        .environment(\.locale, FechasES.locale)
    }

    private func cabecera(_ editar: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sueño, pasos y peso").estiloEtiqueta().foregroundStyle(Tema.suave)
                    Text("Salud").font(Tema.fuente(.titulo)).foregroundStyle(Tema.texto)
                }
                Spacer()
                Button(action: editar) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Tema.suave)
                        .frame(width: 40, height: 40)
                        .background(Tema.carta, in: Circle())
                }
                .accessibilityLabel("Editar Salud")
            }
            .padding(.top, Tema.Espacio.s)
            if let copia = datos.copia {
                Label(API.notaCopia(copia), systemImage: "wifi.slash")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.aviso)
            }
            SelectorPildoras(opciones: PeriodoSalud.allCases.map { (valor: $0, titulo: $0.titulo) }, seleccion: $periodo)
                .padding(.horizontal, -Tema.Espacio.l)
        }
    }

    @ViewBuilder private func bloque(_ id: String) -> some View {
        if let i = datos.informe {
            switch id {
            case "anoche": CartaAnoche(informe: i)
            case "noche":
                if let tramos = i.anoche?.tramos, !tramos.isEmpty, let dia = i.anoche?.dia {
                    CartaNoche(dia: dia, tramos: tramos)
                } else {
                    CartaVacia(titulo: "La noche",
                               texto: "Cuando Tom mande los tramos de la noche (fase, hora y minutos) verás aquí la noche hora a hora.")
                }
            case "fases": CartaFases(noches: datos.noches(periodo), periodo: periodo)
            case "puntuacion": CartaPuntuacion(noches: datos.noches(periodo), periodo: periodo)
            case "peso": CartaPeso(datos: datos, periodo: periodo)
            case "composicion": CartaComposicion(datos: datos, periodo: periodo)
            case "pasos": CartaPasos(noches: datos.noches(periodo), periodo: periodo)
            case "como": ComoSeCalcula()
            default: EmptyView()
            }
        }
    }
}

/// Título de carta: nombre a la izquierda y un dato pequeño a la derecha.
struct TituloCarta: View {
    let titulo: String
    var detalle: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(titulo).font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
            Spacer(minLength: Tema.Espacio.s)
            if let detalle { Text(detalle).estiloEtiqueta().foregroundStyle(Tema.suave) }
        }
    }
}

struct CartaVacia: View {
    let titulo: String
    let texto: String

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            TituloCarta(titulo: titulo)
            Text(texto).font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
        }
        .carta()
    }
}

// MARK: anoche

struct CartaAnoche: View {
    let informe: InformeSueno

    private var ultimaConSueno: NocheSueno? { informe.noches.last(where: { ($0.sueno ?? 0) > 0 }) }

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            Text("Anoche").estiloEtiqueta().foregroundStyle(Tema.suave)
            if let a = informe.anoche, let nota = a.nota {
                HStack(alignment: .firstTextBaseline, spacing: Tema.Espacio.m) {
                    Text("\(nota.total)")
                        .font(Tema.fuente(.gigante)).foregroundStyle(Tema.texto)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(nota.nivel)
                        .font(Tema.fuente(.pequeno, peso: .semibold))
                        .foregroundStyle(color(nota.total))
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(color(nota.total).opacity(0.15), in: Capsule())
                }
                Text(resumen(a))
                    .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                HStack(spacing: Tema.Espacio.s) {
                    parte("Duración", nota.duracion, 50)
                    parte("Hora de acostarte", nota.hora, 30)
                    parte("Interrupciones", nota.interrupciones, 20)
                }
                .padding(.top, Tema.Espacio.s)
            } else if let n = ultimaConSueno, let s = n.sueno {
                Text(FechasES.hm(s))
                    .font(Tema.fuente(.gigante)).foregroundStyle(Tema.texto).monospacedDigit()
                Text("dormido. Para la puntuación y las fases, Tom tiene que mandar los tramos de la noche.")
                    .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            } else {
                Text("—").font(Tema.fuente(.gigante)).foregroundStyle(Tema.tenue)
                Text("Sin datos todavía: llegan cada mañana desde Salud.")
                    .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            }
        }
        .carta()
        .accessibilityElement(children: .combine)
    }

    private func color(_ total: Int) -> Color { total >= 80 ? Tema.acento : total < 70 ? Tema.peligro : Tema.aviso }

    private func resumen(_ a: AnocheSueno) -> String {
        var t = ""
        if let s = a.sueno { t = "\(FechasES.hm(s)) dormido" }
        if let ac = a.acostarse, let le = a.levantarse { t += (t.isEmpty ? "" : " · ") + "de \(ac) a \(le)" }
        if a.dia != informe.noches.last?.dia { t += " · \(FechasES.corta(a.dia))" }
        return t
    }

    private func parte(_ nombre: String, _ valor: Int, _ de: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(nombre).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).lineLimit(1).minimumScaleFactor(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(valor)").font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto).monospacedDigit()
                Text("/ \(de)").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            }
        }
        .padding(Tema.Espacio.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.carta2, in: RoundedRectangle(cornerRadius: Tema.Radio.boton, style: .continuous))
    }
}

// MARK: cómo se calcula

struct ComoSeCalcula: View {
    @State private var abierto = false

    var body: some View {
        DisclosureGroup(isExpanded: $abierto) {
            VStack(alignment: .leading, spacing: Tema.Espacio.s) {
                Text("Cada mañana Tom manda lo que el COROS apuntó anoche, tramo a tramo. Lo despierto antes de dormirte y después de levantarte no cuenta.")
                Text("La puntuación sigue la receta de Salud, sobre 100: duración hasta 50 (8 h dormido son 50), hora de acostarte hasta 30 (30 si es a la media hora de tu media de las dos últimas semanas, 0 si te desvías dos horas) e interrupciones hasta 20 (se pierden con el tiempo despierto).")
            }
            .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            .padding(.top, Tema.Espacio.s)
        } label: {
            Text("Cómo se calcula").font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
        }
        .tint(Tema.suave)
        .carta()
    }
}
