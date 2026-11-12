import SwiftUI

/// El modo entreno a pantalla completa: los ejercicios de hoy con sus series en filas (kilos y repes), el botón
/// grande de «Serie hecha» para la que toca y, al marcar, el descanso a pantalla completa. Marcar se hace
/// manteniendo pulsado un momento: con la mano sudada no se marca sola. La pantalla no se apaga mientras está abierta.
struct VistaSesion: View {
    @State private var sesion = SesionEnCurso.shared
    @State private var datos = DatosEntreno.shared
    @FocusState private var foco: String?
    @State private var nuevo = ""
    @State private var seguroTerminar = false

    var body: some View {
        // en un NavigationStack (sin barra) para que salga el «Listo» encima del teclado numérico
        NavigationStack { contenido.toolbar(.hidden, for: .navigationBar) }
    }

    private var contenido: some View {
        ZStack {
            Tema.fondo.ignoresSafeArea()
            VStack(spacing: 0) {
                cabecera
                lista
            }
            .safeAreaInset(edge: .bottom) { pie }
            if let d = sesion.descanso {
                VistaDescanso(descanso: d, toca: sesion.toca)
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
                    .zIndex(1)
            }
        }
        .animation(Tema.Muelle.pantalla, value: sesion.descanso)
        .onChange(of: sesion.pideRepes) { _, v in
            if let v { foco = v }
            sesion.pideRepes = nil
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Listo") { foco = nil }
            }
        }
        .sensoryFeedback(.success, trigger: sesion.records)
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var cabecera: some View {
        HStack(spacing: Tema.Espacio.m) {
            Text(sesion.sesion?.n ?? "Entreno")
                .font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto).lineLimit(1)
            Spacer()
            if let s = sesion.sesion {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(FormatoEnt.hmmss(Int(ctx.date.timeIntervalSince(s.inicio))))
                        .font(Tema.fuente(.texto, peso: .semibold)).monospacedDigit().foregroundStyle(Tema.suave)
                }
                .accessibilityLabel("Tiempo de sesión")
            }
            Button("Cerrar") { sesion.cierra() }
                .font(Tema.fuente(.texto, peso: .medium))
                .foregroundStyle(Tema.texto)
                .padding(.horizontal, 14).frame(minHeight: 36)
                .background(Tema.carta2, in: Capsule())
                .accessibilityHint("La sesión sigue abierta: «Seguir» la retoma")
        }
        .padding(.horizontal, Tema.Espacio.l)
        .padding(.vertical, Tema.Espacio.m)
        .background(Tema.carta)
        .overlay(alignment: .bottom) { Rectangle().fill(Tema.linea).frame(height: 0.5) }
    }

    private var lista: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Tema.Espacio.m) {
                    ForEach(sesion.bloques, id: \.b.ej) { x in
                        TarjetaEjercicio(b: x.b, extra: x.extra, foco: $foco)
                            .id(x.b.ej)
                    }
                    pieLista
                }
                .padding(Tema.Espacio.l)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: sesion.toca.ejercicio) { _, ej in
                withAnimation(Tema.Muelle.pantalla) { proxy.scrollTo(ej, anchor: .top) }
            }
        }
    }

    /// Lo quitado hoy (para recuperarlo) y añadir otro ejercicio.
    private var pieLista: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            let quitados = sesion.sesion?.quita ?? []
            if !quitados.isEmpty {
                Text("Quitados hoy (tócalo para volver a ponerlo):").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                FlujoEnt(espacio: 6) {
                    ForEach(quitados, id: \.self) { ej in
                        Button("↺ " + ej) { withAnimation(Tema.Muelle.toque) { sesion.recupera(ej) } }
                            .buttonStyle(BotonMini())
                    }
                }
            }
            HStack(spacing: Tema.Espacio.s) {
                TextField("Añadir un ejercicio hoy", text: $nuevo)
                    .font(Tema.fuente(.texto))
                    .submitLabel(.done)
                    .onSubmit(anade)
                    .padding(.horizontal, Tema.Espacio.m).frame(minHeight: 44)
                    .background(Tema.carta2, in: RoundedRectangle(cornerRadius: Tema.Radio.boton))
                    .accessibilityLabel("Ejercicio que añadir a la sesión de hoy")
                Menu {
                    ForEach(datos.e.ejercicios.filter { n in !sesion.bloques.contains { $0.b.ej == n } }, id: \.self) { n in
                        Button(n) { withAnimation(Tema.Muelle.toque) { sesion.anade(n) } }
                    }
                } label: {
                    Image(systemName: "list.bullet").frame(width: 44, height: 44)
                        .background(Tema.carta2, in: RoundedRectangle(cornerRadius: Tema.Radio.boton))
                }
                .accessibilityLabel("Elegir un ejercicio conocido")
                Button("Añadir", action: anade).buttonStyle(BotonMini())
                    .disabled(nuevo.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.top, Tema.Espacio.s)
    }

    private func anade() {
        withAnimation(Tema.Muelle.toque) { sesion.anade(nuevo) }
        nuevo = ""
    }

    /// El botón grande de la serie que toca y terminar.
    private var pie: some View {
        let t = sesion.toca
        return VStack(spacing: Tema.Espacio.s) {
            if !t.hecho {
                BotonMantener(alto: 64, principal: true, accion: { sesion.serieQueToca() }) {
                    VStack(spacing: 2) {
                        Text("Serie hecha").font(Tema.fuente(.destacado))
                        Text("\(t.ejercicio) · \(t.serie) de \(t.total)\(t.detalle.isEmpty ? "" : " · " + t.detalle)")
                            .font(Tema.fuente(.pequeno)).lineLimit(1).minimumScaleFactor(0.8)
                            .contentTransition(.numericText(value: Double(t.serie)))
                    }
                }
                .accessibilityLabel("Serie hecha: \(t.ejercicio), serie \(t.serie) de \(t.total)")
                .accessibilityHint("Mantén pulsado para marcarla")
            }
            Button("Terminar sesión") {
                if t.hecho || seguroTerminar {
                    sesion.termina()
                } else {
                    seguroTerminar = true
                    Haptica.shared.toca(.error)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { seguroTerminar = false }
                }
            }
            .buttonStyle(BotonEnt(principal: t.hecho, alto: t.hecho ? 64 : 48))
            if seguroTerminar && !t.hecho {
                Text("Quedan series sin hacer. Toca otra vez para terminar igual.")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.aviso)
            }
        }
        .padding(.horizontal, Tema.Espacio.l)
        .padding(.vertical, Tema.Espacio.m)
        .background(Tema.carta.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Tema.linea).frame(height: 0.5) }
        .animation(Tema.Muelle.toque, value: t)
        .animation(Tema.Muelle.toque, value: seguroTerminar)
    }
}

/// Un ejercicio de la sesión con sus filas de series.
struct TarjetaEjercicio: View {
    let b: BloqueGym
    let extra: Bool
    var foco: FocusState<String?>.Binding
    @State private var sesion = SesionEnCurso.shared

    var body: some View {
        let hechas = sesion.hechas(b.ej)
        let sg = sesion.sugerencia(b)
        let toca = sesion.toca
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            HStack(alignment: .top, spacing: Tema.Espacio.m) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: Tema.Espacio.s) {
                        Text(b.ej).font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
                        Text("\(b.series)×\(b.repes.isEmpty ? (b.porTiempo ? "\(b.seg) s" : "–") : b.repes)")
                            .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).monospacedDigit()
                    }
                    HStack(spacing: Tema.Espacio.s) {
                        if sg.sube { ChipEnt(texto: "↑ sube a \(FormatoEnt.num(sg.kg)) kg") }
                        if hechas.isEmpty {
                            Button("Quitar") { withAnimation(Tema.Muelle.toque) { sesion.quita(b, extra: extra) } }
                                .buttonStyle(BotonMini(color: Tema.suave))
                                .accessibilityLabel("Quitar \(b.ej) de la sesión de hoy")
                        }
                    }
                    if !b.nota.isEmpty {
                        Text(b.nota).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if let m = MonigoteDatos.de(b.ej) { Monigote(datos: m).frame(width: 84) }
            }
            ForEach(0..<sesion.filas(b), id: \.self) { i in
                FilaSerie(b: b, i: i, hecha: i < hechas.count, siguiente: i == hechas.count,
                          ultima: i == hechas.count - 1, actual: toca.ejercicio == b.ej && toca.indice == i, foco: foco)
            }
            HStack {
                Button("+ serie") { withAnimation(Tema.Muelle.toque) { sesion.masSerie(b) } }
                    .buttonStyle(BotonMini())
                Spacer()
            }
            if let u = sg.ultima {
                Text("La última vez: " + u.map { $0.kg > 0 ? "\(FormatoEnt.num($0.kg))×\($0.n)" : "\($0.n)" }.joined(separator: " · "))
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.tenue).monospacedDigit()
            }
        }
        .carta(relleno: Tema.Espacio.m)
        .overlay(RoundedRectangle(cornerRadius: Tema.Radio.carta, style: .continuous)
            .strokeBorder(toca.ejercicio == b.ej ? Tema.acento.opacity(0.6) : .clear, lineWidth: 1.5))
    }
}

/// Una fila: nº, kilos, repes y el botón (mantener para marcar la siguiente; tocar la última hecha la deshace).
struct FilaSerie: View {
    let b: BloqueGym
    let i: Int
    let hecha: Bool
    let siguiente: Bool
    let ultima: Bool
    let actual: Bool
    var foco: FocusState<String?>.Binding
    @State private var sesion = SesionEnCurso.shared

    var body: some View {
        HStack(spacing: Tema.Espacio.s) {
            Text("\(i + 1)").font(Tema.fuente(.pequeno, peso: .semibold)).foregroundStyle(actual ? Tema.acento : Tema.tenue)
                .frame(width: 20)
            campo("kg|\(b.ej)|\(i)", texto: kg, sugerido: "0", teclado: .decimalPad,
                  etiqueta: "Kilos, serie \(i + 1) de \(b.ej)")
            Text("kg").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            campo("rep|\(b.ej)|\(i)", texto: rep, sugerido: sesion.repSugeridas(b, i), teclado: .numberPad,
                  etiqueta: "\(b.porTiempo ? "Segundos" : "Repeticiones"), serie \(i + 1) de \(b.ej)")
            Text(b.porTiempo ? "s" : "rep").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            boton
        }
    }

    private var kg: Binding<String> {
        Binding(get: { sesion.kgTexto(b, i) }, set: { v in
            if hecha { sesion.corrige(b, i, kg: v) } else { sesion.borradores["kg|\(b.ej)|\(i)"] = v }
        })
    }

    private var rep: Binding<String> {
        Binding(get: { sesion.repTexto(b, i) }, set: { v in
            if hecha { sesion.corrige(b, i, rep: v) } else { sesion.borradores["rep|\(b.ej)|\(i)"] = v }
        })
    }

    private func campo(_ id: String, texto: Binding<String>, sugerido: String, teclado: UIKeyboardType,
                       etiqueta: String) -> some View {
        TextField(sugerido, text: texto)
            .keyboardType(teclado)
            .focused(foco, equals: id)
            .multilineTextAlignment(.trailing)
            .font(Tema.fuente(.destacado)).monospacedDigit()
            .foregroundStyle(Tema.texto)
            .padding(.horizontal, Tema.Espacio.s)
            .frame(minHeight: 48)
            .background(hecha ? Tema.acentoSuave : Tema.carta2, in: RoundedRectangle(cornerRadius: Tema.Radio.celda))
            .overlay(RoundedRectangle(cornerRadius: Tema.Radio.celda)
                .strokeBorder(foco.wrappedValue == id ? Tema.acento : .clear, lineWidth: 1.5))
            .accessibilityLabel(etiqueta)
    }

    @ViewBuilder private var boton: some View {
        if hecha {
            Button {
                if ultima { withAnimation(Tema.Muelle.toque) { sesion.deshaz(b) } }
            } label: {
                Image(systemName: "checkmark").font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Tema.acentoTexto)
                    .frame(width: 56, height: 48)
                    .background(Tema.acento, in: RoundedRectangle(cornerRadius: Tema.Radio.celda))
            }
            .buttonStyle(.plain)
            .opacity(ultima ? 1 : 0.7)
            .accessibilityLabel(ultima ? "Deshacer serie \(i + 1)" : "Serie \(i + 1) hecha")
        } else {
            BotonMantener(alto: 48, ancho: 56, principal: false, accion: { sesion.marca(b, i) }) {
                Image(systemName: "checkmark").font(.system(size: 20, weight: .bold))
            }
            .disabled(!siguiente)
            .opacity(siguiente ? 1 : 0.35)
            .accessibilityLabel("Serie \(i + 1) hecha")
            .accessibilityHint("Mantén pulsado para marcarla")
        }
    }
}

/// Mantener pulsado 0,6 s: un anillo se llena por el borde; soltar antes cancela. Con VoiceOver, la acción directa.
struct BotonMantener<Contenido: View>: View {
    var alto: CGFloat
    var ancho: CGFloat?
    var principal: Bool
    let accion: () -> Bool
    @ViewBuilder var contenido: Contenido

    @State private var lleno = false
    @Environment(\.isEnabled) private var activo
    private let dura = 0.6

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: principal ? Tema.Radio.boton : Tema.Radio.celda, style: .continuous)
        contenido
            .foregroundStyle(principal ? Tema.acentoTexto : (lleno ? Tema.acento : Tema.tenue))
            .frame(maxWidth: ancho == nil ? .infinity : nil)
            .frame(width: ancho, height: alto)
            .background(principal ? Tema.acento : (lleno ? Tema.acentoSuave : Tema.carta2), in: forma)
            .overlay {
                forma.inset(by: 1.5)
                    .trim(from: 0, to: lleno ? 1 : 0)
                    .stroke(principal ? Tema.acentoTexto.opacity(0.8) : Tema.acento, lineWidth: 3)
            }
            .scaleEffect(lleno ? 0.97 : 1)
            .contentShape(forma)
            .onLongPressGesture(minimumDuration: dura, maximumDistance: 30) {
                lleno = false
                _ = accion()
            } onPressingChanged: { pulsando in
                guard activo else { return }
                if pulsando {
                    withAnimation(.linear(duration: dura)) { lleno = true }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { lleno = false }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { _ = accion() }
    }
}

/// El descanso a pantalla completa: el número gigante, lo que viene, la barra y −15/+15/Saltar. Los últimos 10 s el
/// fondo late cada vez más rápido (quieto con «reducir movimiento»).
struct VistaDescanso: View {
    let descanso: SesionEnCurso.Descanso
    let toca: SesionEnCurso.Toca
    @State private var sesion = SesionEnCurso.shared
    @Environment(\.accessibilityReduceMotion) private var quieto

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { ctx in
            let s = max(0, descanso.fin.timeIntervalSince(ctx.date))
            let queda = Int(ceil(s))
            let late = (quieto || s > 10) ? 0 : (sin(ctx.date.timeIntervalSinceReferenceDate * .pi * 2 * (1 + (10 - s) * 0.35)) + 1) / 2 * 0.9
            ZStack {
                Tema.fondo.ignoresSafeArea()
                Tema.acentoSuave.opacity(late).ignoresSafeArea()
                VStack(spacing: Tema.Espacio.l) {
                    Spacer()
                    Text("Descanso").font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                    Text(FormatoEnt.mmss(queda))
                        .font(.system(size: 132, weight: .bold, design: .monospaced))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .foregroundStyle(Tema.acento)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(quieto ? nil : .snappy, value: queda)
                        .accessibilityLabel("Quedan \(queda) segundos")
                    Text(toca.hecho ? "Era la última: todo hecho" : "Siguiente: \(toca.ejercicio) · serie \(toca.serie) de \(toca.total)")
                        .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                        .multilineTextAlignment(.center)
                    BarraEnt(valor: 1 - s / Double(max(1, descanso.total)))
                        .frame(height: 8)
                        .frame(maxWidth: 420)
                        .padding(.horizontal, Tema.Espacio.xl)
                    Spacer()
                    HStack(spacing: Tema.Espacio.m) {
                        Button("−15") { sesion.ajustaDescanso(-15) }
                            .buttonStyle(BotonEnt(alto: 64))
                            .accessibilityLabel("15 segundos menos")
                        Button("+15") { sesion.ajustaDescanso(15) }
                            .buttonStyle(BotonEnt(alto: 64))
                            .accessibilityLabel("15 segundos más")
                        Button("Terminar") { sesion.saltaDescanso() }
                            .buttonStyle(BotonEnt(principal: true, alto: 64))
                            .accessibilityLabel("Terminar el descanso")
                    }
                    .padding(.horizontal, Tema.Espacio.l)
                    .padding(.bottom, Tema.Espacio.xl)
                }
            }
        }
    }
}

/// Fichas en filas que saltan de línea cuando no caben.
struct FlujoEnt: Layout {
    var espacio: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ancho = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, fila: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let t = v.sizeThatFits(.unspecified)
            if x > 0 && x + t.width > ancho {
                x = 0
                y += fila + espacio
                fila = 0
            }
            x += t.width + espacio
            maxX = max(maxX, x - espacio)
            fila = max(fila, t.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + fila)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, fila: CGFloat = 0
        for v in subviews {
            let t = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + t.width > bounds.maxX {
                x = bounds.minX
                y += fila + espacio
                fila = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(t))
            x += t.width + espacio
            fila = max(fila, t.height)
        }
    }
}
