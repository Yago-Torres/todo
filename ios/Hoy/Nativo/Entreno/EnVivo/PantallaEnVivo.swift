import AVFoundation
import QuartzCore
import SwiftUI
import UIKit

/// Escalada en vivo: la cámara trasera a pantalla completa con el esqueleto encima en tiempo real, el centro de
/// gravedad con su estela de los últimos segundos, los ángulos de codos y rodillas y lo alto que llegas. El botón
/// grande graba dos vídeos (con el esqueleto y limpio); al parar se ven al momento y se pueden guardar, compartir o
/// mandar a la Pi para el análisis de siempre. La app va en vertical: como en Cámara, los iconos giran con el iPhone
/// y el vídeo se guarda en horizontal si empiezas a grabar en horizontal.
struct PantallaEnVivo: View {
    @Environment(\.dismiss) private var cerrar
    @Environment(\.scenePhase) private var fase
    @Environment(\.accessibilityReduceMotion) private var quieto
    @State private var motor = MotorVivo()
    @State private var colores = ColoresEsq.delTema()
    @State private var giro: Angle = .zero
    @State private var zoomInicial: CGFloat?
    @State private var verEsqueleto = true
    @State private var verMedidas = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch motor.estado {
            case .sinPermiso:
                sinPermiso
            case .sinCamara:
                mensaje("Este iPhone no deja usar la cámara trasera ahora mismo. Cierra otras apps que la usen y vuelve a entrar.")
            default:
                camara
            }
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            colores = ColoresEsq.delTema()
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            UIApplication.shared.isIdleTimerDisabled = true
            motor.arranca()
        }
        .onDisappear {
            motor.para()
            UIApplication.shared.isIdleTimerDisabled = false
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
        .onChange(of: fase) { _, nueva in
            if nueva == .background { motor.para() }
            if nueva == .active && motor.terminado == nil { motor.reanuda() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            let nuevo: Angle?
            switch UIDevice.current.orientation {
            case .portrait: nuevo = .zero
            case .landscapeLeft: nuevo = .degrees(90)
            case .landscapeRight: nuevo = .degrees(-90)
            case .portraitUpsideDown: nuevo = .degrees(180)
            default: nuevo = nil
            }
            if let nuevo, nuevo != giro {
                withAnimation(quieto ? nil : Tema.Muelle.toque) { giro = nuevo }
            }
        }
        .sheet(item: $motor.terminado, onDismiss: { motor.reanuda() }) { r in
            HojaResultadoVivo(resultado: r)
                .onAppear { motor.para() }
        }
    }

    // MARK: la cámara

    private var camara: some View {
        GeometryReader { geo in
            ZStack {
                VistaCamara(sesion: motor.sesion, lente: motor.lenteActual)
                    .ignoresSafeArea()
                    .accessibilityLabel("Lo que ve la cámara")
                if verEsqueleto {
                    CapaEsqueleto(motor: motor, colores: colores)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                VStack(spacing: 0) {
                    barraArriba
                    if verMedidas && motor.estado == .listo {
                        PanelMedidas(motor: motor, colores: colores)
                            .padding(.horizontal, Tema.Espacio.l)
                            .padding(.top, Tema.Espacio.s)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Spacer()
                    if motor.estado == .listo {
                        AvisoNoTeVeo(motor: motor)
                    }
                    if let a = motor.aviso {
                        Text(a)
                            .font(Tema.fuente(.pequeno))
                            .foregroundStyle(Tema.texto)
                            .padding(Tema.Espacio.m)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Tema.Radio.celda))
                            .padding(.horizontal, Tema.Espacio.l)
                    }
                    barraAbajo
                }
                if motor.estado == .preparando {
                    ProgressView().tint(Tema.texto)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                MagnifyGesture()
                    .onChanged { v in
                        let base = zoomInicial ?? motor.zoomActual
                        if zoomInicial == nil { zoomInicial = base }
                        motor.zoom(base * v.magnification)
                    }
                    .onEnded { _ in zoomInicial = nil }
            )
        }
    }

    private var barraArriba: some View {
        HStack(spacing: Tema.Espacio.m) {
            Button {
                cerrar()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .rotationEffect(giro)
            }
            .foregroundStyle(Tema.texto)
            .accessibilityLabel("Cerrar el modo en vivo")
            .disabled(motor.grabando)
            .opacity(motor.grabando ? 0.4 : 1)
            Spacer()
            if motor.grabando, let inicio = motor.inicioGrabacion {
                TimelineView(.periodic(from: inicio, by: 1)) { ctx in
                    let s = max(0, Int(ctx.date.timeIntervalSince(inicio)))
                    HStack(spacing: 6) {
                        Circle().fill(Tema.peligro).frame(width: 9, height: 9)
                        Text(String(format: "%02d:%02d", s / 60, s % 60))
                            .font(Tema.fuente(.destacado)).monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .padding(.horizontal, Tema.Espacio.m).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .foregroundStyle(Tema.texto)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Grabando, \(s) segundos")
                }
                .transition(.scale.combined(with: .opacity))
            } else if motor.caliente {
                Label("El iPhone está caliente: analizo menos", systemImage: "thermometer.sun")
                    .font(Tema.fuente(.pequeno))
                    .padding(.horizontal, Tema.Espacio.m).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .foregroundStyle(Tema.aviso)
            }
            Spacer()
            Menu {
                Toggle("Esqueleto", isOn: $verEsqueleto)
                Toggle("Medidas", isOn: $verMedidas)
                Button("Reiniciar la altura") { motor.reiniciaAlcance() }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .rotationEffect(giro)
            }
            .foregroundStyle(Tema.texto)
            .accessibilityLabel("Qué se ve encima")
        }
        .padding(.horizontal, Tema.Espacio.l)
        .padding(.top, Tema.Espacio.s)
        .animation(Tema.Muelle.toque, value: motor.grabando)
    }

    private var barraAbajo: some View {
        VStack(spacing: Tema.Espacio.l) {
            if motor.lentes.count > 1 {
                HStack(spacing: Tema.Espacio.s) {
                    ForEach(motor.lentes) { l in
                        let actual = l.id == motor.lenteActual
                        Button {
                            motor.elige(l)
                        } label: {
                            Text(actual ? "\(MotorVivo.cifra(motor.aumento))×" : l.nombre)
                                .font(Tema.fuente(.pequeno, peso: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(actual ? colores.centroSwiftUI : Tema.texto)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: Circle())
                                .rotationEffect(giro)
                        }
                        .disabled(motor.grabando)
                        .accessibilityLabel("Lente \(l.nombre) aumentos")
                    }
                }
                .padding(4)
                .background(.ultraThinMaterial, in: Capsule())
                .animation(Tema.Muelle.toque, value: motor.lenteActual)
            }
            BotonGrabar(grabando: motor.grabando) {
                if motor.grabando { motor.paraDeGrabar() } else { motor.graba() }
            }
            .disabled(motor.estado != .listo)
        }
        .padding(.bottom, Tema.Espacio.xl)
    }

    // MARK: sin cámara

    private var sinPermiso: some View {
        VStack(spacing: Tema.Espacio.l) {
            Image(systemName: "camera.fill").font(.system(size: 40)).foregroundStyle(Tema.suave)
            Text("Tom no tiene permiso para usar la cámara")
                .font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
                .multilineTextAlignment(.center)
            Text("Actívalo en Ajustes > Tom > Cámara y vuelve aquí.")
                .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                .multilineTextAlignment(.center)
            Button("Abrir Ajustes") {
                if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
            }
            .buttonStyle(BotonEnt(principal: true))
            .frame(maxWidth: 260)
            Button("Cerrar") { cerrar() }
                .foregroundStyle(Tema.suave)
        }
        .padding(Tema.Espacio.xl)
    }

    private func mensaje(_ t: String) -> some View {
        VStack(spacing: Tema.Espacio.l) {
            Text(t).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto).multilineTextAlignment(.center)
            Button("Cerrar") { cerrar() }.buttonStyle(BotonEnt(principal: true)).frame(maxWidth: 260)
        }
        .padding(Tema.Espacio.xl)
    }
}

// MARK: - el botón de grabar

private struct BotonGrabar: View {
    let grabando: Bool
    let toca: () -> Void

    var body: some View {
        Button(action: toca) {
            ZStack {
                Circle().strokeBorder(Tema.texto, lineWidth: 5).frame(width: 84, height: 84)
                RoundedRectangle(cornerRadius: grabando ? 8 : 34, style: .continuous)
                    .fill(Tema.peligro)
                    .frame(width: grabando ? 34 : 68, height: grabando ? 34 : 68)
            }
            .animation(Tema.Muelle.toque, value: grabando)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(grabando ? "Parar de grabar" : "Grabar")
        .accessibilityHint(grabando ? "Guarda el vídeo con el esqueleto y el limpio" : "Graba el intento con el esqueleto encima")
    }
}

// MARK: - la vista previa de AVFoundation

struct VistaCamara: UIViewRepresentable {
    let sesion: AVCaptureSession
    var lente: String?

    func makeUIView(context: Context) -> Previa {
        let v = Previa()
        v.backgroundColor = .black
        v.capa.session = sesion
        v.capa.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: Previa, context: Context) {
        uiView.setNeedsLayout()
    }

    final class Previa: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        // swiftlint:disable:next force_cast
        var capa: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            // en vertical, como los fotogramas que analiza Vision (la conexión cambia al cambiar de lente)
            if let c = capa.connection, c.isVideoRotationAngleSupported(90), c.videoRotationAngle != 90 {
                c.videoRotationAngle = 90
            }
        }
    }
}

// MARK: - el esqueleto encima, a 60 fps

/// Vision da la pose ~15 veces por segundo; aquí se persigue con un muelle exponencial en cada fotograma de pantalla,
/// así se mueve fluido sin temblar.
private final class Persecucion {
    var pose: PoseEsc?
    var t: Double = 0

    func avanza(_ objetivo: PoseEsc?, _ ahora: Double) -> PoseEsc? {
        let dt = max(0, min(0.1, ahora - t))
        t = ahora
        guard let objetivo else {
            pose = nil
            return nil
        }
        guard let actual = pose else {
            pose = objetivo
            return objetivo
        }
        let nueva = actual.mezcla(objetivo, CGFloat(1 - exp(-dt * 16)))
        pose = nueva
        return nueva
    }
}

private struct CapaEsqueleto: View {
    let motor: MotorVivo
    let colores: ColoresEsq
    @State private var persecucion = Persecucion()

    var body: some View {
        TimelineView(.animation) { ctx in
            Canvas { g, tam in
                _ = ctx.date
                let s = motor.instantanea()
                guard s.tam.width > 0, s.tam.height > 0 else { return }
                let escala = max(tam.width / s.tam.width, tam.height / s.tam.height)
                let ox = (tam.width - s.tam.width * escala) / 2, oy = (tam.height - s.tam.height * escala) / 2
                let ancho = s.tam.width * escala, alto = s.tam.height * escala
                let ahora = CACurrentMediaTime()
                let pose = persecucion.avanza(s.pose, ahora)
                // la mano más alta a la que has llegado
                if let cima = s.alcance.cima {
                    let y = oy + cima * alto
                    var linea = Path()
                    linea.move(to: CGPoint(x: 0, y: y))
                    linea.addLine(to: CGPoint(x: tam.width, y: y))
                    g.stroke(linea, with: .color(colores.centroSwiftUI.opacity(0.75)),
                             style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                }
                g.withCGContext { c in
                    PintorEsq.pinta(c, pose: pose, estela: s.estela, ahora: ahora, duracionEstela: MotorVivo.duracionEstela,
                                    tamImagen: s.tam, escala: escala,
                                    aPx: { CGPoint(x: ox + $0.x * ancho, y: oy + $0.y * alto) }, colores: colores)
                }
            }
        }
    }
}

// MARK: - el medidor

private struct PanelMedidas: View {
    let motor: MotorVivo
    let colores: ColoresEsq

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { _ in
            let s = motor.instantanea()
            let tam = s.tam
            let codos = [s.pose?.angulo(5, 8, 10, tam), s.pose?.angulo(6, 9, 11, tam)]
            let rodillas = [s.pose?.angulo(13, 15, 17, tam), s.pose?.angulo(14, 16, 18, tam)]
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(s.alcance.metros.map { String(format: "%.1f", $0).replacingOccurrences(of: ".", with: ",") } ?? "–")
                        .font(Tema.fuente(.cifra))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(colores.centroSwiftUI)
                    Text("m de alcance").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                }
                fila("Codos", codos)
                fila("Rodillas", rodillas)
                Text(Medidor.frase(codos: codos.compactMap { $0 }))
                    .font(Tema.fuente(.pequeno, peso: .semibold))
                    .foregroundStyle(Tema.texto)
            }
            .padding(Tema.Espacio.m)
            .frame(width: 200, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Tema.Radio.carta))
            .animation(Tema.Muelle.toque, value: s.alcance.metros)
            .accessibilityElement(children: .combine)
        }
    }

    private func fila(_ t: String, _ grados: [Double?]) -> some View {
        HStack(spacing: 6) {
            Text(t).font(Tema.fuente(.etiqueta)).foregroundStyle(Tema.suave).frame(width: 58, alignment: .leading)
            ForEach(0..<2, id: \.self) { i in
                let e = Medidor.estiramiento(grados[i])
                VStack(alignment: .leading, spacing: 2) {
                    BarraEnt(valor: e ?? 0, color: colores.huesoSwiftUI).frame(height: 5)
                    Text(grados[i].map { "\(Int($0))°" } ?? "–")
                        .font(Tema.fuente(.etiqueta)).monospacedDigit().foregroundStyle(Tema.texto)
                }
                .accessibilityLabel("\(t) \(i == 0 ? "izquierdo" : "derecho"): \(grados[i].map { "\(Int($0)) grados" } ?? "no se ve")")
            }
        }
    }
}

// MARK: - lo grabado

/// Al parar: el vídeo con el esqueleto en bucle y qué hacer con él.
struct HojaResultadoVivo: View {
    let resultado: MotorVivo.Resultado
    @Environment(\.dismiss) private var cerrar
    @State private var compartir = false
    @State private var analizar = false
    @State private var presumir = false
    @State private var rutaHoja: RutaParaHoja?
    @State private var guardando = false
    @State private var aviso: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Tema.Espacio.l) {
                    BucleVideo(url: resultado.esqueleto)
                        .aspectRatio(9.0 / 16.0, contentMode: .fit)
                        .frame(maxHeight: 460)
                        .clipShape(RoundedRectangle(cornerRadius: Tema.Radio.carta))
                        .accessibilityLabel("El intento grabado con el esqueleto")
                    Button {
                        presumir = true
                    } label: {
                        Label("Vídeo para presumir", systemImage: "sparkles")
                    }
                    .buttonStyle(BotonEnt(principal: true))
                    Button {
                        compartir = true
                    } label: {
                        Label("Compartir con el esqueleto", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(BotonEnt())
                    Button {
                        guarda()
                    } label: {
                        Label(guardando ? "Guardando…" : "Guardar en Fotos (los dos)", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(BotonEnt())
                    .disabled(guardando)
                    Button {
                        analizar = true
                    } label: {
                        Label("Analizar en la Pi", systemImage: "cpu")
                    }
                    .buttonStyle(BotonEnt())
                    Button {
                        abreRuta()
                    } label: {
                        Label("Tarjeta de la ruta", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                    .buttonStyle(BotonEnt())
                    if let aviso {
                        Text(aviso).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                            .multilineTextAlignment(.center)
                    }
                    Text("«Analizar en la Pi» sube el vídeo limpio como «Subir intento»: el análisis completo llega por Telegram y en Entreno.")
                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                        .multilineTextAlignment(.center)
                }
                .padding(Tema.Espacio.l)
            }
            .background(Tema.fondo)
            .navigationTitle("Intento grabado")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Seguir grabando") { cerrar() }
                }
            }
            .sheet(isPresented: $compartir) {
                HojaCompartir(cosas: [resultado.esqueleto])
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $rutaHoja) { r in
                HojaTarjetaRuta(ruta: r.ruta, titulo: r.titulo)
            }
            .sheet(isPresented: $presumir) {
                HojaPresumir(video: resultado.limpio)
            }
            .sheet(isPresented: $analizar) {
                HojaEscalada(archivo: resultado.limpio)
            }
        }
    }

    /// La ruta sale de las poses guardadas al grabar: no se recalcula nada.
    private func abreRuta() {
        guard let url = resultado.serie, let leido = SerieGuardada.lee(url),
              let ruta = RutaEsc(leido.0, tam: leido.1) else {
            aviso = "No hay bastante recorrido para la ruta: graba un intento en el que se te vea entero unos segundos."
            Haptica.shared.toca(.error)
            return
        }
        rutaHoja = RutaParaHoja(ruta: ruta, titulo: "Mi intento")
    }

    private func guarda() {
        guardando = true
        Task {
            do {
                try await Fototeca.guarda(videos: [resultado.esqueleto, resultado.limpio])
                aviso = "Guardados en Fotos: con esqueleto y limpio."
                Haptica.shared.toca(.marcar)
            } catch {
                aviso = error.localizedDescription
                Haptica.shared.toca(.error)
            }
            guardando = false
        }
    }
}

/// Tras 2 s sin ver a nadie: que se aleje hasta salir entero.
private struct AvisoNoTeVeo: View {
    let motor: MotorVivo

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            if CACurrentMediaTime() - motor.instantanea().visto > 2 {
                Label("No te veo: aléjate hasta salir entero", systemImage: "figure.stand")
                    .font(Tema.fuente(.texto, peso: .semibold))
                    .foregroundStyle(Tema.texto)
                    .padding(.horizontal, Tema.Espacio.l).padding(.vertical, Tema.Espacio.s)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, Tema.Espacio.s)
                    .transition(.opacity)
            }
        }
    }
}
