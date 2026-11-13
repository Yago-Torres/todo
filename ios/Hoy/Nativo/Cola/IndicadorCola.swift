import SwiftUI

/// La pastilla discreta de encima de la barra: «3 cambios por enviar» (o «1 sin guardar» si el servidor rechazó algo).
/// Tocarla abre la hoja con la lista. Sin nada en la cola no ocupa sitio.
struct IndicadorCola: View {
    @State private var cola = EstadoCola.shared
    @State private var abierta = false

    var body: some View {
        Group {
            if !cola.cambios.isEmpty {
                Button {
                    Haptica.shared.toca(.marcar)
                    abierta = true
                } label: {
                    HStack(spacing: Tema.Espacio.s) {
                        Circle()
                            .fill(cola.conProblema > 0 ? Tema.peligro : Tema.aviso)
                            .frame(width: 7, height: 7)
                        Text(texto)
                            .font(Tema.fuente(.pequeno, peso: .semibold))
                            .foregroundStyle(Tema.texto)
                            .contentTransition(.numericText())
                        if cola.enviando { ProgressView().controlSize(.mini).tint(Tema.suave) }
                    }
                    .padding(.horizontal, Tema.Espacio.m)
                    .padding(.vertical, Tema.Espacio.xs + 1)
                    .background(Tema.carta, in: Capsule())
                    .overlay(Capsule().strokeBorder(Tema.linea))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(texto)
                .accessibilityHint("Abre la lista de cambios hechos en este iPhone que aún no han llegado al servidor")
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(Tema.Muelle.toque, value: cola.cambios.count)
        .sheet(isPresented: $abierta) { HojaCola() }
    }

    private var texto: String {
        let n = cola.pendientes, mal = cola.conProblema
        if mal > 0 {
            let malos = "\(mal) sin guardar"
            return n > 0 ? "\(malos) · \(n) por enviar" : malos
        }
        if cola.enviando { return "Enviando \(n) \(n == 1 ? "cambio" : "cambios")…" }
        return "\(n) \(n == 1 ? "cambio" : "cambios") por enviar"
    }
}

/// La lista de lo que espera en la cola: qué es, cómo va, y reintentar o descartar cada uno.
struct HojaCola: View {
    @Environment(\.dismiss) private var cerrar
    @State private var cola = EstadoCola.shared
    @State private var descartando: Local.Cambio?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(cola.cambios) { c in fila(c) }
                        .listRowBackground(Tema.carta)
                    if cola.cambios.isEmpty {
                        Text("Todo enviado. No queda nada pendiente.")
                            .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                            .listRowBackground(Tema.carta)
                    }
                } footer: {
                    Text(pie).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Tema.fondo)
            .navigationTitle("Cambios por enviar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Listo") { cerrar() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await cola.enviaAhora() }
                    } label: {
                        if cola.enviando { ProgressView() } else { Text("Enviar ahora") }
                    }
                    .disabled(cola.enviando || cola.cambios.isEmpty)
                }
            }
            .confirmationDialog("¿Descartar este cambio?", isPresented: Binding(get: { descartando != nil },
                                                                              set: { if !$0 { descartando = nil } }),
                                titleVisibility: .visible, presenting: descartando) { c in
                Button("Descartar", role: .destructive) { cola.descarta(c) }
            } message: { c in
                Text("«\(c.resumen)» no se enviará y deja de verse en este iPhone. No se puede deshacer.")
            }
            .onAppear { cola.recarga() }
        }
        .presentationDetents([.medium, .large])
        .tint(Tema.acento)
    }

    private var pie: String {
        Red.shared.hayRed
            ? "Salen solos y en orden, encima de lo último del servidor: no pisan lo que hayas cambiado en la web o con el bot."
            : "Sin conexión. Salen solos y en orden en cuanto vuelva la red, sin pisar lo cambiado en otro sitio."
    }

    private func fila(_ c: Local.Cambio) -> some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Tema.Espacio.s) {
                Circle().fill(color(c)).frame(width: 7, height: 7)
                Text(c.resumen).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
            }
            Text(detalle(c)).font(Tema.fuente(.pequeno)).foregroundStyle(c.estado == .pendiente ? Tema.suave : Tema.peligro)
            HStack(spacing: Tema.Espacio.l) {
                if c.estado != .pendiente || c.intentos > 0 {
                    Button("Reintentar") { cola.reintenta(c) }
                        .foregroundStyle(Tema.acento)
                }
                Button("Descartar", role: .destructive) { descartando = c }
                    .foregroundStyle(Tema.peligro)
            }
            .font(Tema.fuente(.pequeno, peso: .semibold))
            .buttonStyle(.borderless)
        }
        .padding(.vertical, Tema.Espacio.xs)
        .accessibilityElement(children: .contain)
    }

    private func color(_ c: Local.Cambio) -> Color {
        c.estado == .pendiente ? Tema.aviso : Tema.peligro
    }

    private func detalle(_ c: Local.Cambio) -> String {
        let cuando = "Apuntado \(c.fecha.formatted(.relative(presentation: .named)))"
        switch c.estado {
        case .pendiente:
            if let error = c.error, !error.isEmpty {
                let cuenta = c.intentos > 0 ? " · \(c.intentos) \(c.intentos == 1 ? "intento" : "intentos")" : ""
                let otra = c.proximo.map { " Se vuelve a probar \($0.formatted(.relative(presentation: .named)))." } ?? ""
                return "\(cuando)\(cuenta). \(error).\(otra)"
            }
            return Red.shared.hayRed ? "\(cuando). Saliendo…" : "\(cuando). Sale al volver la conexión."
        case .conflicto:
            return "Choca con un cambio hecho en otro sitio: \(c.error ?? "sin detalle"). Reinténtalo o descártalo."
        case .error:
            return "El servidor no lo acepta: \(c.error ?? "sin detalle"). Descártalo, o reinténtalo si ya está arreglado."
        }
    }
}
