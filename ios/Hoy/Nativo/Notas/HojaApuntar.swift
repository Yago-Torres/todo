import SwiftUI
import WidgetKit

/// La caja rápida de apuntar: una nota rápida (no es una tarea) o un pendiente (va a Pendientes, sin fecha o para
/// hoy). Sale encima de todo desde el widget «Apuntar», hoy://apuntar?tipo=nota|tarea o el control del centro de
/// control. El teclado sale ya; Intro guarda y se cierra. Sin red, a la cola (se manda al volver).
struct HojaApuntar: View {
    @State private var tipo: TipoApunte
    @State private var texto = ""
    @State private var paraHoy = false
    @State private var enviando = false
    @State private var mensaje: String?
    @State private var error = false
    @FocusState private var escribiendo: Bool
    @Environment(\.dismiss) private var cierra

    init(tipo: TipoApunte) {
        _tipo = State(initialValue: tipo)
    }

    private var vacio: Bool { texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            HStack {
                SelectorPildoras(opciones: [(TipoApunte.nota, "Nota rápida"), (TipoApunte.tarea, "Pendiente")],
                                 seleccion: $tipo)
                Spacer(minLength: 0)
            }
            TextField(tipo == .nota ? "Una idea suelta…" : "Qué tienes que hacer…", text: $texto, axis: .vertical)
                .lineLimit(2...6)
                .font(Tema.fuente(.destacado))
                .foregroundStyle(Tema.texto)
                .focused($escribiendo)
                .submitLabel(.done)
                .onSubmit(guarda)
                // en un campo de varias líneas, Intro escribe un salto en vez de llamar a onSubmit: es «guardar»
                .onChange(of: texto) { _, nuevo in
                    guard nuevo.contains("\n") else { return }
                    texto = nuevo.replacingOccurrences(of: "\n", with: " ")
                    guarda()
                }
                .carta(relleno: Tema.Espacio.m)
                .accessibilityLabel(tipo == .nota ? "Nota rápida" : "Pendiente")
            HStack(spacing: Tema.Espacio.s) {
                if tipo == .tarea {
                    Button {
                        Haptica.shared.toca(.marcar)
                        paraHoy.toggle()
                    } label: {
                        Label(paraHoy ? "Para hoy" : "Sin fecha", systemImage: paraHoy ? "calendar.badge.clock" : "calendar")
                            .font(Tema.fuente(.pequeno, peso: .medium))
                            .foregroundStyle(paraHoy ? Tema.acentoTexto : Tema.texto)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(paraHoy ? Tema.acento : Tema.carta2, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(paraHoy ? "Para hoy (toca para quitar la fecha)" : "Sin fecha (toca para hoy)")
                } else {
                    Text("No es una tarea hasta que tú lo digas")
                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                }
                Spacer()
                Button(action: guarda) {
                    Text(enviando ? "Guardando…" : "Guardar")
                        .font(Tema.fuente(.texto, peso: .semibold))
                        .foregroundStyle(Tema.acentoTexto)
                        .padding(.horizontal, 18).padding(.vertical, 9)
                        .background(vacio ? Tema.tenue : Tema.acento, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(vacio || enviando)
            }
            if let mensaje {
                Label(mensaje, systemImage: error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(Tema.fuente(.pequeno, peso: .medium))
                    .foregroundStyle(error ? Tema.peligro : Tema.acento)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .padding(Tema.Espacio.l)
        .background(Tema.fondo.ignoresSafeArea())
        .animation(Tema.Muelle.toque, value: tipo)
        .animation(Tema.Muelle.toque, value: mensaje)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .tint(Tema.acento)
        .onAppear {
            Navegador.shared.olvidaApuntar()
            escribiendo = true
        }
    }

    private func guarda() {
        guard !enviando, !vacio else { return }
        enviando = true
        mensaje = nil
        Haptica.shared.toca(.marcar)
        Task {
            let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
            var ok = false, encolada = false
            var fallo: String?
            switch tipo {
            case .nota:
                let r = await DatosNotas.shared.apunta(limpio)
                ok = r.ok
                encolada = r.encolada
                fallo = r.error
            case .tarea:
                do {
                    encolada = try await API.tareaOEncola(limpio, due: paraHoy ? Fecha.hoy() : nil)
                    ok = true
                    await DatosPendientes.shared.recarga()
                    WidgetCenter.shared.reloadAllTimelines()
                } catch let e {
                    fallo = e.localizedDescription
                }
            }
            enviando = false
            guard ok else {
                error = true
                mensaje = "No se ha apuntado: \(fallo ?? "error desconocido")"
                Haptica.shared.toca(.error)
                return
            }
            error = false
            mensaje = encolada ? API.avisoEncolado : (tipo == .nota ? "Nota apuntada" : "Apuntado en Pendientes")
            texto = ""
            try? await Task.sleep(for: .milliseconds(encolada ? 1400 : 700))
            cierra()
        }
    }
}
