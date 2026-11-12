import SwiftUI
import Speech
import AVFoundation
import WidgetKit
import Observation

/// El modo voz de Tom: escucha (es-ES, en el iPhone si se puede), manda lo dicho a /api/tom, lee la respuesta en
/// voz alta y vuelve a escuchar. Se cierra con Parar o tras un rato sin decir nada. Lo abren «Habla con Tom» (Siri),
/// el botón del centro de control y hoy://voz.
struct Voz: View {
    @Environment(\.dismiss) private var cerrar
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento
    @State private var charla = Conversacion()

    private let acento = Color.accentColor   // el acento Calma (oliva / lima en oscuro), como la web

    var body: some View {
        ZStack {
            Color("Fondo").ignoresSafeArea()
            VStack(spacing: 20) {
                HStack {
                    Spacer()
                    Button {
                        charla.termina()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title3.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .tint(.secondary)
                    .accessibilityLabel("Cerrar")
                }

                Button {
                    Task { await charla.empieza() }
                } label: {
                    Orbe(charla: charla, sinMovimiento: sinMovimiento)
                }
                .buttonStyle(.plain)
                .disabled(!charla.puedeReintentar)
                .accessibilityLabel("Volver a escuchar")
                .accessibilityHidden(!charla.puedeReintentar)

                VStack(spacing: 6) {
                    Text(charla.fase.titulo)
                        .font(.title2.bold())
                    Text(charla.subtitulo)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                }
                .accessibilityElement(children: .combine)

                Turnos(turnos: charla.turnos, acento: acento)

                Button {
                    charla.termina()
                } label: {
                    Label("Parar", systemImage: "stop.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(acento)
                .foregroundStyle(Color("AcentoTexto"))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .task {
            Navegador.shared.olvidaVoz()
            await charla.empieza()
        }
        .onDisappear { charla.termina() }
        .onChange(of: charla.cerrada) { _, cerrada in
            if cerrada { cerrar() }
        }
    }
}

// MARK: vistas

private struct Turnos: View {
    let turnos: [Conversacion.Turno]
    let acento: Color

    var body: some View {
        ScrollViewReader { lector in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(turnos) { turno in
                        Burbuja(turno: turno, acento: acento)
                            .id(turno.id)
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .onChange(of: turnos.count) { _, _ in
                guard let ultimo = turnos.last else { return }
                withAnimation { lector.scrollTo(ultimo.id, anchor: .bottom) }
            }
        }
    }
}

private struct Burbuja: View {
    let turno: Conversacion.Turno
    let acento: Color

    var body: some View {
        HStack {
            if !turno.deTom { Spacer(minLength: 40) }
            Text(turno.texto)
                .foregroundStyle(turno.deTom ? Color.primary : Color("AcentoTexto"))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(turno.deTom ? Color("Carta") : acento,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            if turno.deTom { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(turno.deTom ? "Tom: \(turno.texto)" : "Tú: \(turno.texto)")
    }
}

// MARK: la conversación

@MainActor @Observable
final class Conversacion: NSObject, AVSpeechSynthesizerDelegate {
    enum Fase: Equatable {
        case preparando, escuchando, pensando, hablando
        case parada(String)
    }

    struct Turno: Identifiable {
        let id = UUID()
        let deTom: Bool
        let texto: String
    }

    private(set) var fase: Fase = .preparando
    private(set) var parcial = ""
    private(set) var turnos: [Turno] = []
    private(set) var cerrada = false
    /// Nivel del micrófono (0…1, RMS en dB) y última palabra de Tom: los lee el orbe en cada fotograma, sin observar.
    @ObservationIgnored private(set) var nivel: Double = 0
    @ObservationIgnored private(set) var ultimoPulso: TimeInterval = 0

    private static let sinHablar: Double = 8      // s sin decir nada al escuchar: se acabó la conversación
    private static let trasHablar: Double = 1.6   // s de silencio después de hablar: la frase ha terminado

    private let reconocedor = SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))
    private let motor = AVAudioEngine()
    private let sintetizador = AVSpeechSynthesizer()
    @ObservationIgnored private var peticion: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var tarea: SFSpeechRecognitionTask?
    @ObservationIgnored private var reloj: Task<Void, Never>?
    @ObservationIgnored private var activa = false
    @ObservationIgnored private var escuchoAlgo = false   // el micro llegó a captar voz en esta escucha
    @ObservationIgnored private var ronda = 0   // cambia en cada escucha: lo que llegue tarde de la anterior no cuenta

    override init() {
        super.init()
        sintetizador.delegate = self
    }

    var puedeReintentar: Bool {
        if case .parada = fase { return true }
        return false
    }

    var subtitulo: String {
        switch fase {
        case .preparando: return " "
        case .escuchando: return parcial.isEmpty ? "Dime qué quieres: mover el entreno, apuntar algo, qué toca…" : parcial
        case .pensando: return "Se lo paso a Tom"
        case .hablando: return " "
        case .parada(let motivo): return motivo
        }
    }

    func empieza() async {
        guard !cerrada else { return }
        activa = true
        fase = .preparando
        guard await permisos() else { return }
        escucha()
    }

    /// Para todo y cierra la hoja. Se puede llamar varias veces (Parar, cerrar, desaparecer).
    func termina() {
        activa = false
        paraEscucha()
        if sintetizador.isSpeaking { sintetizador.stopSpeaking(at: .immediate) }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        Sonido.ambiente()   // de vuelta a la web: sus sonidos otra vez discretos
        cerrada = true
    }

    // MARK: permisos

    private func permisos() async -> Bool {
        let voz = await Self.pidePermisoVoz()
        guard voz == .authorized else {
            fase = .parada("Sin permiso para reconocer la voz. Actívalo en Ajustes > Tom.")
            return false
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            fase = .parada("Sin permiso para el micrófono. Actívalo en Ajustes > Tom.")
            return false
        }
        return true
    }

    nonisolated private static func pidePermisoVoz() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { estado in c.resume(returning: estado) }
        }
    }

    // MARK: escuchar

    private func escucha() {
        guard activa else { return }
        guard let reconocedor, reconocedor.isAvailable else {
            fase = .parada("El reconocimiento de voz no está disponible ahora. Toca para reintentar.")
            return
        }
        paraEscucha()
        do {
            let sesion = AVAudioSession.sharedInstance()
            try sesion.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .duckOthers])
            try sesion.setActive(true, options: .notifyOthersOnDeactivation)

            let p = SFSpeechAudioBufferRecognitionRequest()
            p.shouldReportPartialResults = true
            p.addsPunctuation = true
            // sin exigir el modelo del iPhone: si no está descargado, el reconocimiento falla al instante sin oír nada

            let entrada = motor.inputNode
            let formato = entrada.outputFormat(forBus: 0)
            guard formato.sampleRate > 0, formato.channelCount > 0 else {
                fase = .parada("No encuentro el micrófono. Toca para reintentar.")
                return
            }
            nivel = 0
            escuchoAlgo = false
            Self.conecta(entrada, formato, p) { [weak self] valor in
                guard let self else { return }
                self.nivel += (valor - self.nivel) * 0.5   // suavizado; el orbe vuelve a suavizar por fotograma
                if valor > 0.35 { self.escuchoAlgo = true }
            }
            motor.prepare()
            try motor.start()

            ronda += 1
            let estaRonda = ronda
            peticion = p
            tarea = Self.reconoce(reconocedor, p) { [weak self] texto, acabado, fallo in
                self?.oye(texto, acabado: acabado, fallo: fallo, ronda: estaRonda)
            }
            parcial = ""
            fase = .escuchando
            esperaSilencio(Self.sinHablar)
        } catch {
            paraEscucha()
            fase = .parada("No puedo usar el micrófono: \(error.localizedDescription)")
        }
    }

    // El micrófono y el reconocedor llaman desde sus propias colas: estos cierres no son del hilo principal.
    nonisolated private static func conecta(_ nodo: AVAudioInputNode, _ formato: AVAudioFormat,
                                            _ p: SFSpeechAudioBufferRecognitionRequest,
                                            _ alNivel: @escaping @MainActor (Double) -> Void) {
        nodo.removeTap(onBus: 0)
        nodo.installTap(onBus: 0, bufferSize: 1024, format: formato) { buffer, _ in
            p.append(buffer)
            let valor = Conversacion.rms(de: buffer)
            Task { @MainActor in alNivel(valor) }
        }
    }

    /// RMS del primer canal pasado a dB y a 0…1 (-50 dB → 0, -10 dB → 1).
    nonisolated private static func rms(de buffer: AVAudioPCMBuffer) -> Double {
        guard let canal = buffer.floatChannelData?[0] else { return 0 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var suma: Float = 0
        for i in 0..<n {
            let v = canal[i]
            suma += v * v
        }
        let rms = (suma / Float(n)).squareRoot()
        let db = 20 * log10(Double(max(rms, 0.000_01)))
        return min(max((db + 50) / 40, 0), 1)
    }

    nonisolated private static func reconoce(_ r: SFSpeechRecognizer, _ p: SFSpeechAudioBufferRecognitionRequest,
                                             _ alOir: @escaping @MainActor (String?, Bool, String?) -> Void) -> SFSpeechRecognitionTask {
        r.recognitionTask(with: p) { resultado, error in
            let texto = resultado?.bestTranscription.formattedString
            let acabado = resultado?.isFinal ?? false
            let fallo = error.map { ($0 as NSError).localizedDescription }
            Task { @MainActor in alOir(texto, acabado, fallo) }
        }
    }

    private func oye(_ texto: String?, acabado: Bool, fallo: String?, ronda deEsta: Int) {
        guard deEsta == ronda, fase == .escuchando else { return }
        if let texto, !texto.isEmpty, texto != parcial {
            parcial = texto
            esperaSilencio(Self.trasHablar)
        }
        // falló sin haber oído nada (y no por silencio): se cuenta, no se cierra la hoja a escondidas
        if let fallo, parcial.trimmingCharacters(in: .whitespaces).isEmpty {
            paraEscucha()
            fase = .parada("No te he podido oír: \(fallo) Toca para reintentar.")
            return
        }
        if acabado || fallo != nil { cierraFrase() }
    }

    private func esperaSilencio(_ segundos: Double) {
        reloj?.cancel()
        let estaRonda = ronda
        reloj = Task { [weak self] in
            try? await Task.sleep(for: .seconds(segundos))
            guard !Task.isCancelled, let self, self.ronda == estaRonda, self.fase == .escuchando else { return }
            self.cierraFrase()
        }
    }

    private func paraEscucha() {
        reloj?.cancel()
        reloj = nil
        ronda += 1
        if motor.isRunning { motor.stop() }
        motor.inputNode.removeTap(onBus: 0)
        nivel = 0
        peticion?.endAudio()
        tarea?.cancel()
        peticion = nil
        tarea = nil
    }

    /// Lo dicho hasta ahora va a Tom; sin nada dicho, la conversación se acaba.
    private func cierraFrase() {
        let dicho = parcial.trimmingCharacters(in: .whitespacesAndNewlines)
        paraEscucha()
        guard !dicho.isEmpty else {
            if escuchoAlgo || !turnos.isEmpty {
                termina()   // silencio de verdad: se acabó la conversación
            } else {
                fase = .parada("No me llega sonido del micrófono. ¿Lo está usando otra app (llamada, grabación)? Toca para reintentar.")
            }
            return
        }
        turnos.append(Turno(deTom: false, texto: dicho))
        parcial = ""
        fase = .pensando
        Task { await pregunta(dicho) }
    }

    private func pregunta(_ dicho: String) async {
        let respuesta: String
        do {
            respuesta = try await API.tom(dicho).texto
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            respuesta = error.localizedDescription
        }
        guard activa else { return }
        turnos.append(Turno(deTom: true, texto: respuesta))
        habla(respuesta)
    }

    // MARK: hablar

    private func habla(_ texto: String) {
        guard activa else { return }
        fase = .hablando
        let frase = AVSpeechUtterance(string: texto)
        frase.voice = AVSpeechSynthesisVoice(language: "es-ES")
        frase.rate = AVSpeechUtteranceDefaultSpeechRate
        sintetizador.speak(frase)
    }

    private func acabaDeHablar() {
        guard activa, fase == .hablando else { return }
        escucha()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.acabaDeHablar() }
    }

    /// Cada palabra que va a decir Tom es un latido del orbe.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange,
                                       utterance: AVSpeechUtterance) {
        Task { @MainActor in self.ultimoPulso = Date.timeIntervalSinceReferenceDate }
    }
}

/// La sesión de audio de la app fuera del modo voz.
enum Sonido {
    /// .ambient: respeta el interruptor de silencio y se mezcla con la música que suene. El modo voz pone
    /// .playAndRecord mientras escucha y habla, y vuelve aquí al cerrarse.
    static func ambiente() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [])
    }
}

extension Conversacion.Fase {
    var titulo: String {
        switch self {
        case .preparando: return "Un momento…"
        case .escuchando: return "Te escucho"
        case .pensando: return "Pensando…"
        case .hablando: return "Tom habla"
        case .parada: return "En pausa"
        }
    }

    var simbolo: String {
        switch self {
        case .preparando: return "ellipsis"
        case .escuchando: return "waveform"
        case .pensando: return "ellipsis.bubble"
        case .hablando: return "speaker.wave.2.fill"
        case .parada: return "mic.slash"
        }
    }
}
