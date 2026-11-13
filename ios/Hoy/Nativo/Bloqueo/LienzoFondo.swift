import SwiftUI

/// El fondo de bloqueo entero, a tamaño de pantalla (en puntos). Lo dibujan ImageRenderer (la imagen de verdad) y la
/// vista previa de Ajustes, así que lo que se ve al configurarlo es exactamente lo que sale.
struct LienzoFondo: View {
    let lienzo: CGSize
    let foto: FotoPreparada?
    let ajusteFoto: AjusteFoto
    let ajustes: AjustesFondo
    let contenido: ContenidoMomento
    let estilo: EstiloFondo
    /// Solo en la vista previa: la hora, los widgets y los botones del bloqueo encima, para ver que no se pisan.
    var horaSimulada: Date?

    /// La zona de la hora (y de los widgets de debajo, si se deja sitio) y la de la linterna y la cámara.
    private var reservaArriba: CGFloat { lienzo.height * (ajustes.huecoWidgets ? 0.365 : 0.265) }
    private var reservaAbajo: CGFloat { lienzo.height * 0.15 }
    private var margen: CGFloat { lienzo.width * 0.065 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            fondo
            colocada
            if let horaSimulada {
                HoraSimulada(lienzo: lienzo, fecha: horaSimulada, widgets: ajustes.huecoWidgets,
                             arriba: reservaArriba, abajo: reservaAbajo)
            }
        }
        .frame(width: lienzo.width, height: lienzo.height)
        .clipped()
        .coordinateSpace(name: "lienzo")
    }

    // MARK: la foto

    @ViewBuilder private var fondo: some View {
        if let foto {
            capaFoto(foto.desenfocada ?? foto.nitida, foto.tamano)
                .overlay(Color.black.opacity(min(0.85, max(0, ajusteFoto.oscurecer))))
        } else {
            // sin foto: un degradado del tema
            ZStack {
                estilo.velo
                LinearGradient(colors: [estilo.acento.opacity(0.55), estilo.velo.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [estilo.acento.opacity(0.35), .clear], center: .bottomTrailing,
                               startRadius: 0, endRadius: lienzo.height * 0.6)
            }
            .frame(width: lienzo.width, height: lienzo.height)
        }
    }

    private func capaFoto(_ img: CGImage, _ fuente: CGSize) -> some View {
        let g = Encuadre.geometria(fuente, lienzo, ajusteFoto)
        return ZStack(alignment: .topLeading) {
            Image(decorative: img, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: g.tam.width, height: g.tam.height)
                .position(g.centro)
        }
        .frame(width: lienzo.width, height: lienzo.height)
        .clipped()
    }

    /// El cristal: la foto muy desenfocada, del tamaño del lienzo, recortada luego a la tarjeta.
    @ViewBuilder private var vidrio: some View {
        if let foto, let cristal = foto.cristal {
            capaFoto(cristal, foto.tamano)
                .overlay(Color.black.opacity(min(0.85, max(0, ajusteFoto.oscurecer))))
        } else {
            Color.clear.frame(width: lienzo.width, height: lienzo.height)
        }
    }

    // MARK: la capa

    private var alineacion: Alignment {
        switch ajustes.posicion {
        case .arriba: return .top
        case .centro: return .center
        case .abajo: return .bottom
        }
    }

    private var colocada: some View {
        let banda = ajustes.estilo == .banda
        return VStack(spacing: 0) {
            Color.clear.frame(height: reservaArriba)
            ZStack(alignment: alineacion) {
                Color.clear
                capa.padding(.horizontal, banda ? 0 : margen)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Color.clear.frame(height: reservaAbajo)
        }
        .frame(width: lienzo.width, height: lienzo.height)
    }

    @ViewBuilder private var capa: some View {
        let info = CapaInfo(contenido: contenido, elementos: ajustes.elementos(contenido.momento), estilo: estilo)
        switch ajustes.estilo {
        case .cristal:
            let forma = RoundedRectangle(cornerRadius: estilo.radio, style: .continuous)
            info
                .padding(lienzo.width * 0.055)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { recorte(forma) }
                .overlay(forma.strokeBorder(estilo.texto.opacity(0.16), lineWidth: 0.75))
        case .banda:
            info
                .padding(.horizontal, margen)
                .padding(.vertical, lienzo.width * 0.06)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { recorte(Rectangle(), opacidad: 0.5) }
        case .sombra:
            info
                .frame(maxWidth: .infinity, alignment: .leading)
                .shadow(color: estilo.velo.opacity(0.75), radius: 7, y: 1)
                .shadow(color: estilo.velo.opacity(0.35), radius: 18)
        }
    }

    /// Lo de detrás de la tarjeta: el cristal alineado con el lienzo y un velo del color de la capa.
    private func recorte<S: Shape>(_ forma: S, opacidad: Double = 0.34) -> some View {
        GeometryReader { g in
            let o = g.frame(in: .named("lienzo")).origin
            ZStack(alignment: .topLeading) {
                vidrio.offset(x: -o.x, y: -o.y)
                estilo.velo.opacity(foto?.cristal == nil ? opacidad + 0.2 : opacidad)
                    .frame(width: g.size.width, height: g.size.height)
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
            .clipShape(forma)
        }
    }
}

// MARK: lo que dice

/// Los elementos visibles del momento, en su orden. Un elemento sin nada que decir no ocupa sitio.
struct CapaInfo: View {
    let contenido: ContenidoMomento
    let elementos: [ElementoVisible]
    let estilo: EstiloFondo

    private var bloques: [ElementoFondo] {
        elementos.filter(\.visible).map(\.elemento).filter(tieneAlgo)
    }

    var body: some View {
        let lista = bloques
        VStack(alignment: .leading, spacing: 16 * estilo.tamano) {
            ForEach(lista) { e in bloque(e) }
            if lista.isEmpty || lista == [.titulo] {
                Text(contenido.hayDatos ? "Nada pendiente por ahora." : "Abre Tom con conexión para traer lo de hoy.")
                    .font(estilo.fuente(16, .regular)).foregroundStyle(estilo.suave)
            }
        }
        .foregroundStyle(estilo.texto)
        .multilineTextAlignment(.leading)
        .lineLimit(2)
    }

    private func tieneAlgo(_ e: ElementoFondo) -> Bool {
        let c = contenido
        switch e {
        case .titulo: return true
        case .entreno: return !c.entrenos.isEmpty
        case .ejercicios: return !c.entrenoPendiente.isEmpty
        case .habitos: return !c.habitos.isEmpty
        case .faltan: return !c.faltan.isEmpty || c.completo
        case .racha: return c.rachaEnJuego > 0 && !c.faltan.isEmpty
        case .tareas: return !c.tareas.isEmpty
        case .sueno: return (c.suenoMin ?? 0) > 0
        case .pasos: return (c.pasosAyer ?? 0) > 0
        }
    }

    @ViewBuilder private func bloque(_ e: ElementoFondo) -> some View {
        let c = contenido
        switch e {
        case .titulo:
            VStack(alignment: .leading, spacing: 4) {
                Text(c.titulo).font(estilo.fuente(30, .bold, titulo: true)).lineLimit(2).minimumScaleFactor(0.7)
                if let sub = subtitulo { Text(sub).font(estilo.fuente(15, .medium)).foregroundStyle(estilo.suave) }
            }
        case .entreno:
            seccion("Entreno") {
                ForEach(c.entrenos, id: \.self) { en in
                    fila(en.hecho ? "checkmark.circle.fill" : icono(en.tipo), en.nombre, hecho: en.hecho)
                }
            }
        case .ejercicios:
            let en = c.entrenoPendiente.first { $0.tipo != "movilidad" } ?? c.entrenoPendiente[0]
            seccion(en.nombre) {
                if en.ejercicios.isEmpty {
                    Text("Sin ejercicios apuntados en la rutina").font(estilo.fuente(16, .regular)).foregroundStyle(estilo.suave)
                }
                ForEach(Array(en.ejercicios.enumerated()), id: \.offset) { i, ej in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(i + 1)").font(estilo.fuente(15, .bold)).foregroundStyle(estilo.acento).monospacedDigit()
                        Text(ej).font(estilo.fuente(16, .regular)).lineLimit(1).minimumScaleFactor(0.75)
                    }
                }
            }
        case .habitos:
            let hechos = c.habitos.filter(\.hecho).count
            seccion("Hábitos · \(hechos)/\(c.habitos.count)") {
                ForEach(c.habitos.prefix(6), id: \.id) { h in
                    fila(h.hecho ? "checkmark.circle.fill" : "circle", h.n, hecho: h.hecho)
                }
            }
        case .faltan:
            if c.faltan.isEmpty {
                fila("checkmark.seal.fill", "Todo hecho hoy", hecho: false)
            } else {
                seccion(c.faltan.count == 1 ? "Falta uno" : "Faltan \(c.faltan.count)") {
                    ForEach(c.faltan.prefix(6), id: \.id) { h in
                        HStack(spacing: 8) {
                            fila("circle", h.n, hecho: false)
                            if h.racha > 0 {
                                Label("\(h.racha)", systemImage: "flame.fill")
                                    .font(estilo.fuente(14, .semibold)).foregroundStyle(estilo.acento)
                                    .labelStyle(.titleAndIcon)
                            }
                        }
                    }
                }
            }
        case .racha:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "flame.fill").foregroundStyle(estilo.acento)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.rachaEnJuego == 1 ? "Racha de 1 día en juego" : "Racha de \(c.rachaEnJuego) días en juego")
                        .font(estilo.fuente(18, .semibold))
                    if let n = c.nombreRacha { Text(n).font(estilo.fuente(14, .regular)).foregroundStyle(estilo.suave) }
                }
            }
            .font(estilo.fuente(18, .semibold))
        case .tareas:
            seccion("Con hora") {
                ForEach(c.tareas.prefix(4), id: \.self) { t in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(t.hora).font(estilo.fuente(15, .semibold)).foregroundStyle(estilo.acento).monospacedDigit()
                        Text(t.texto).font(estilo.fuente(16, .regular)).lineLimit(1)
                    }
                }
            }
        case .sueno:
            fila("bed.double.fill", "Dormiste \(ContenidoMomento.horas(c.suenoMin ?? 0))", hecho: false)
        case .pasos:
            fila("figure.walk", "Ayer, \(ContenidoMomento.miles(c.pasosAyer ?? 0)) pasos", hecho: false)
        }
    }

    private var subtitulo: String? {
        let c = contenido
        switch c.momento {
        case .manana: return nil
        case .entreno:
            guard let h = c.inicioEntreno else { return nil }
            let f = DateFormatter()
            f.dateFormat = "H:mm"
            return "A las \(f.string(from: h))"
        case .noche:
            if c.completo { return "Todo hecho. Buen trabajo." }
            return nil
        }
    }

    private func seccion<C: View>(_ titulo: String, @ViewBuilder _ contenido: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 7 * estilo.tamano) {
            Text(titulo.uppercased())
                .font(estilo.fuente(12, .semibold)).tracking(1.1)
                .foregroundStyle(estilo.suave)
            contenido()
        }
    }

    private func fila(_ simbolo: String, _ texto: String, hecho: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: simbolo)
                .font(estilo.fuente(15, .semibold))
                .foregroundStyle(hecho ? estilo.acento : estilo.texto)
            Text(texto)
                .font(estilo.fuente(17, .regular))
                .foregroundStyle(hecho ? estilo.suave : estilo.texto)
                .strikethrough(hecho, color: estilo.suave)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func icono(_ tipo: String) -> String {
        switch tipo {
        case "carrera": return "figure.run"
        case "movilidad": return "figure.flexibility"
        case "pesas": return "dumbbell"
        default: return "figure.strengthtraining.traditional"
        }
    }
}

// MARK: la hora del bloqueo, simulada

/// La fecha, la hora, los widgets y los botones de linterna y cámara como los pone iOS, y la zona que se deja libre.
struct HoraSimulada: View {
    let lienzo: CGSize
    let fecha: Date
    let widgets: Bool
    let arriba: CGFloat
    let abajo: CGFloat

    var body: some View {
        let h = lienzo.height, w = lienzo.width
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                Text(fecha, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(size: h * 0.022, weight: .semibold))
                Text(fecha, format: .dateTime.hour().minute())
                    .font(.system(size: h * 0.112, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: w)
            .position(x: w / 2, y: h * 0.17)

            if widgets {
                HStack(spacing: w * 0.035) {
                    ForEach(0..<4, id: \.self) { _ in
                        Circle().fill(.white.opacity(0.22)).frame(width: h * 0.07, height: h * 0.07)
                    }
                }
                .frame(width: w)
                .position(x: w / 2, y: h * 0.3)
            }

            // el límite de la zona libre
            Rectangle().fill(.white.opacity(0.35)).frame(width: w * 0.8, height: 1)
                .position(x: w / 2, y: arriba)
            Rectangle().fill(.white.opacity(0.35)).frame(width: w * 0.8, height: 1)
                .position(x: w / 2, y: h - abajo)

            ForEach([0.15, 0.85], id: \.self) { x in
                Circle().fill(.black.opacity(0.35))
                    .frame(width: h * 0.059, height: h * 0.059)
                    .overlay(Image(systemName: x < 0.5 ? "flashlight.off.fill" : "camera.fill")
                        .font(.system(size: h * 0.022)).foregroundStyle(.white))
                    .position(x: w * x, y: h * 0.925)
            }
            Capsule().fill(.white.opacity(0.8)).frame(width: w * 0.35, height: 5)
                .position(x: w / 2, y: h - 10)
        }
        .frame(width: w, height: h)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
