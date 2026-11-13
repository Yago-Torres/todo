import SwiftUI

/// El bloque «Rachas» de Hoy (id "rachas" en app-hoy): las rachas vivas, lo que falta para el siguiente hito y, si hay
/// alguna en juego, la llamada a la acción con los hábitos concretos que la salvan hoy (se marcan desde aquí).
struct BloqueRachas: View {
    @State private var rachas = DatosRachas.shared
    @State private var datos = DatosNativos.shared
    @State private var verDescansos = false

    var body: some View {
        let vivas = rachas.vivas
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            cabecera
            if let error = rachas.error {
                Text(error).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro)
            }
            if let llamada = rachas.llamada {
                tarjetaLlamada(dias: llamada.dias, habitos: llamada.habitos)
                    .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity), removal: .opacity))
            }
            if vivas.isEmpty {
                Text("Aún no tienes rachas. Marca un hábito hoy y empieza una.")
                    .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .carta()
            } else {
                VStack(spacing: 0) {
                    ForEach(vivas.prefix(6)) { r in
                        FilaRacha(r: r)
                        if r.id != vivas.prefix(6).last?.id { Divider().overlay(Tema.linea) }
                    }
                }
                .carta(relleno: Tema.Espacio.m)
            }
        }
        .animation(Tema.Muelle.pantalla, value: rachas.llamada?.habitos.map(\.id))
        .task { await rachas.carga() }
        .onChange(of: datos.hoy?.habitos.map(\.hecho)) { _, _ in
            Task { await rachas.recarga() }   // un hito o una racha que deja de estar en juego, con la cuenta del servidor
        }
        .sheet(isPresented: $verDescansos) { HojaDescansos() }
    }

    private var cabecera: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tema.Espacio.s) {
            Text("Rachas").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
            Label("\(rachas.quedan)", systemImage: "snowflake")
                .estiloEtiqueta().monospacedDigit()
                .foregroundStyle(Tema.acento)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Tema.acentoSuave, in: Capsule())
                .contentTransition(.numericText())
                .accessibilityLabel("Te quedan \(rachas.quedan) comodines este mes")
            Spacer()
            Button("Descansos") { verDescansos = true }
                .font(Tema.fuente(.pequeno, peso: .medium))
                .foregroundStyle(Tema.acento)
                .accessibilityHint("Descansar hoy, vacaciones y comodines")
        }
        .padding(.top, Tema.Espacio.s)
    }

    // MARK: la llamada a la acción

    private func tarjetaLlamada(dias: Int, habitos: [RachaHabito]) -> some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            HStack(alignment: .top, spacing: Tema.Espacio.m) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Tema.aviso)
                    .symbolEffect(.pulse, options: .repeating, isActive: !quieto)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mantén tu racha de \(DatosRachas.dias(dias))")
                        .font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
                        .contentTransition(.numericText())
                    Text("Hoy la salva: \(DatosRachas.nombres(habitos.map(\.n))). \(Self.horasRestantes())")
                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // un botón por hábito: marcarlo desde aquí
            FlujoBotones(habitos: habitos) { r in
                Haptica.shared.toca(.marcar)
                Task { await datos.marca(r.id, hecho: true) }
            }
            HStack(spacing: Tema.Espacio.s) {
                Menu {
                    ForEach(habitos) { r in
                        Button(r.n, systemImage: "leaf") { Task { await rachas.descansa(r.id) } }
                    }
                    Button("Todos los hábitos", systemImage: "leaf.fill") { Task { await rachas.descansa(nil) } }
                } label: {
                    Label("Descansar hoy", systemImage: "leaf")
                }
                .accessibilityHint("Hoy no cuenta y la racha no se rompe")
                if rachas.quedan > 0 {
                    Button {
                        Haptica.shared.toca(.marcar)
                        Task { await rachas.usaComodin() }
                    } label: {
                        Label("Usar comodín", systemImage: "snowflake")
                    }
                    .accessibilityHint("Congela hoy todas las rachas. Te quedan \(rachas.quedan)")
                }
                Spacer(minLength: 0)
            }
            .font(Tema.fuente(.pequeno, peso: .medium))
            .foregroundStyle(Tema.acento)
            .buttonStyle(.plain)
        }
        .carta()
        .overlay(RoundedRectangle(cornerRadius: Tema.Radio.carta, style: .continuous).strokeBorder(Tema.aviso.opacity(0.5), lineWidth: 1.5))
        .accessibilityElement(children: .contain)
    }

    @Environment(\.accessibilityReduceMotion) private var quieto

    /// «Te quedan 5 h» hasta medianoche (con menos de una, en minutos).
    static func horasRestantes(_ ahora: Date = Date()) -> String {
        let cal = Calendar.current
        guard let fin = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: ahora)) else { return "" }
        let minutos = Int(fin.timeIntervalSince(ahora) / 60)
        return minutos < 60 ? "Te quedan \(minutos) min." : "Te quedan \(minutos / 60) h."
    }
}

/// Los hábitos que salvan la racha, en botones que saltan de línea si no caben.
private struct FlujoBotones: View {
    let habitos: [RachaHabito]
    let toca: (RachaHabito) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Tema.Espacio.s) { botones }
            VStack(alignment: .leading, spacing: Tema.Espacio.s) { botones }
        }
    }

    @ViewBuilder private var botones: some View {
        ForEach(habitos) { r in
            Button { toca(r) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                    Text(r.n).lineLimit(1)
                }
                .font(Tema.fuente(.pequeno, peso: .semibold))
                .foregroundStyle(Tema.acentoTexto)
                .padding(.horizontal, Tema.Espacio.m).padding(.vertical, Tema.Espacio.s)
                .background(Color(hex: r.c), in: Capsule())
            }
            .buttonStyle(EstiloHundir())
            .accessibilityLabel("Marcar \(r.n) como hecho")
        }
    }
}

/// Una racha: color, nombre, días (llama, o el icono del descanso si hoy descansa) y la barra hasta el siguiente hito.
private struct FilaRacha: View {
    let r: RachaHabito
    @State private var rachas = DatosRachas.shared

    var body: some View {
        let n = rachas.racha(r)
        let libre = rachas.libreHoy(r)
        let juego = rachas.enJuego(r)
        let sig = rachas.siguienteHito(n)
        let ant = rachas.hitoAnterior(n)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Tema.Espacio.s) {
                Circle().fill(Color(hex: r.c)).frame(width: 8, height: 8)
                Text(r.n).font(Tema.fuente(.texto, peso: .medium)).foregroundStyle(Tema.texto).lineLimit(1)
                Spacer(minLength: Tema.Espacio.s)
                if let libre {
                    Image(systemName: DatosRachas.icono(libre))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Tema.suave)
                        .accessibilityLabel(DatosRachas.nombre(libre))
                }
                Label("\(n)", systemImage: libre != nil ? "snowflake" : "flame.fill")
                    .font(Tema.fuente(.pequeno, peso: .semibold)).monospacedDigit()
                    .foregroundStyle(juego ? Tema.aviso : libre != nil ? Tema.suave : rachas.hechoAhora(r) ? Tema.aviso : Tema.tenue)
                    .contentTransition(.numericText())
            }
            if let sig {
                HStack(spacing: Tema.Espacio.s) {
                    Barra(valor: Double(n - ant) / Double(max(sig - ant, 1)), color: Color(hex: r.c))
                        .frame(height: 4)
                        .animation(Tema.Muelle.toque, value: n)
                    Text(sig - n == 1 ? "1 día para \(sig)" : "\(sig - n) días para \(sig)")
                        .font(Tema.fuente(.etiqueta)).monospacedDigit().foregroundStyle(Tema.suave)
                        .contentTransition(.numericText())
                }
            }
        }
        .padding(.vertical, Tema.Espacio.s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(etiqueta(n: n, libre: libre, juego: juego, sig: sig))
    }

    private func etiqueta(n: Int, libre: String?, juego: Bool, sig: Int?) -> String {
        var t = "\(r.n): racha de \(DatosRachas.dias(n))"
        if let libre { t += ", congelada (\(DatosRachas.nombre(libre).lowercased()))" }
        if juego { t += ", en juego hoy" }
        if let sig { t += ". Faltan \(DatosRachas.dias(sig - n)) para \(sig)" }
        return t
    }
}
