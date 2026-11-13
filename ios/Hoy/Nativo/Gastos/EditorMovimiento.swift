import SwiftUI

/// Editar o borrar un gasto (la hoja que sale al tocar un movimiento). Guarda con el leer-modificar-escribir de
/// DatosGastos; sin red el cambio se ve ya y sale solo al volver la conexión.
struct EditorMovimiento: View {
    let movimiento: Movimiento
    @Environment(\.dismiss) private var cierra
    @State private var datos = DatosGastos.shared
    @State private var importe: String
    @State private var dia: Date
    @State private var cat: String
    @State private var comercio: String
    @State private var nota: String
    @State private var viaje: String
    @State private var trabajando = false
    @State private var error: String?
    @State private var confirmaBorrar = false
    @State private var toques = 0

    init(movimiento m: Movimiento) {
        movimiento = m
        _importe = State(initialValue: Eur.campo(m.importe))
        _dia = State(initialValue: FechaGasto.fecha(m.dia) ?? Date())
        _cat = State(initialValue: m.cat)
        _comercio = State(initialValue: m.comercio)
        _nota = State(initialValue: m.nota)
        _viaje = State(initialValue: m.viaje)
    }

    private var cifra: Double? {
        guard let x = Eur.lee(importe), x > 0 else { return nil }
        return x
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tema.Espacio.l) {
                HStack {
                    Button("Cancelar") { cierra() }
                        .foregroundStyle(Tema.suave)
                    Spacer()
                    Text("Gasto").font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
                    Spacer()
                    Button {
                        guarda()
                    } label: {
                        if trabajando { ProgressView() } else { Text("Guardar").fontWeight(.semibold) }
                    }
                    .foregroundStyle(cifra == nil ? Tema.tenue : Tema.acento)
                    .disabled(cifra == nil || trabajando)
                }
                .font(Tema.fuente(.texto))

                VStack(alignment: .leading, spacing: Tema.Espacio.m) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        TextField("0,00", text: $importe)
                            .keyboardType(.decimalPad)
                            .font(Tema.fuente(.gigante)).monospacedDigit()
                            .foregroundStyle(Tema.texto)
                            .minimumScaleFactor(0.5)
                            .accessibilityLabel("Importe en euros")
                        Text("€").font(Tema.fuente(.seccion)).foregroundStyle(Tema.suave)
                    }
                    if movimiento.orig > 0 {
                        Text("Pagado en \(movimiento.moneda): \(Eur.campo(movimiento.orig)). El importe de arriba es en euros.")
                            .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                    }
                }
                .carta()

                VStack(spacing: 0) {
                    fila("Día") {
                        DatePicker("Día", selection: $dia, displayedComponents: .date)
                            .labelsHidden()
                            .environment(\.locale, Locale(identifier: "es_ES"))
                            .tint(Tema.acento)
                    }
                    Divider().overlay(Tema.linea)
                    fila("Categoría") {
                        Picker("Categoría", selection: $cat) {
                            ForEach(datos.categorias) { Text($0.n).tag($0.id) }
                        }
                        .labelsHidden()
                        .tint(Tema.acento)
                    }
                    if let viajes = datos.estado?.viajes, !viajes.isEmpty {
                        Divider().overlay(Tema.linea)
                        fila("Viaje") {
                            Picker("Viaje", selection: $viaje) {
                                Text("Ninguno: cuenta en el ciclo").tag("")
                                ForEach(viajes) { Text($0.n).tag($0.id) }
                            }
                            .labelsHidden()
                            .tint(Tema.acento)
                        }
                    }
                }
                .carta(relleno: Tema.Espacio.m)

                VStack(spacing: Tema.Espacio.m) {
                    campo("Comercio", texto: $comercio, limite: 60)
                    campo("Nota", texto: $nota, limite: 120)
                }
                .carta()

                if !movimiento.lineas.isEmpty {
                    VStack(alignment: .leading, spacing: Tema.Espacio.s) {
                        Text("Líneas del ticket").estiloEtiqueta().foregroundStyle(Tema.suave)
                        ForEach(Array(movimiento.lineas.enumerated()), id: \.offset) { _, l in
                            HStack {
                                Text(l.t).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.texto)
                                Spacer()
                                Text(Eur.texto(l.imp)).font(Tema.fuente(.pequeno)).monospacedDigit()
                                    .foregroundStyle(Tema.suave)
                            }
                        }
                    }
                    .carta()
                }

                if let error {
                    Text(error).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(role: .destructive) {
                    confirmaBorrar = true
                } label: {
                    Label("Borrar gasto", systemImage: "trash")
                        .font(Tema.fuente(.destacado))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .foregroundStyle(Tema.peligro)
                        .background(Tema.peligro.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: Tema.Radio.boton, style: .continuous))
                }
                .disabled(trabajando)
                .confirmationDialog("¿Borrar este gasto de \(Eur.texto(movimiento.importe))?",
                                    isPresented: $confirmaBorrar, titleVisibility: .visible) {
                    Button("Borrar", role: .destructive) { borra() }
                    Button("Mejor no", role: .cancel) {}
                }
            }
            .padding(Tema.Espacio.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Tema.fondo.ignoresSafeArea())
        .presentationBackground(Tema.fondo)
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.success, trigger: toques)
        .animation(Tema.Muelle.pantalla, value: error)
    }

    private func fila<C: View>(_ titulo: String, @ViewBuilder _ contenido: () -> C) -> some View {
        HStack {
            Text(titulo).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
            Spacer()
            contenido()
        }
        .padding(.vertical, 6)
    }

    private func campo(_ titulo: String, texto: Binding<String>, limite: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titulo).estiloEtiqueta().foregroundStyle(Tema.suave)
            TextField(titulo, text: texto)
                .font(Tema.fuente(.texto))
                .onChange(of: texto.wrappedValue) { _, nuevo in
                    if nuevo.count > limite { texto.wrappedValue = String(nuevo.prefix(limite)) }
                }
        }
    }

    private func guarda() {
        guard let x = cifra, !trabajando else { return }
        trabajando = true
        error = nil
        let c = DatosGastos.Cambios(importe: x, dia: FechaGasto.dia(dia), cat: cat,
                                    comercio: comercio.trimmingCharacters(in: .whitespaces),
                                    nota: nota.trimmingCharacters(in: .whitespaces), viaje: viaje)
        Task {
            defer { trabajando = false }
            do {
                try await datos.edita(movimiento, c)
                toques += 1
                cierra()
            } catch {
                Haptica.shared.toca(.error)
                self.error = DatosGastos.mensaje(error)
            }
        }
    }

    private func borra() {
        guard !trabajando else { return }
        trabajando = true
        error = nil
        Task {
            defer { trabajando = false }
            do {
                try await datos.borra(movimiento)
                Haptica.shared.toca(.desmarcar)
                cierra()
            } catch {
                Haptica.shared.toca(.error)
                self.error = DatosGastos.mensaje(error)
            }
        }
    }
}
