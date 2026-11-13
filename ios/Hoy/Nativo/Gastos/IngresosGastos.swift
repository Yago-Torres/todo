import SwiftUI

// El bloque «Ingresos» de Gastos: lo que entra aparte del sueldo en el ciclo (extras y lo que te devuelven). Tocar uno
// lo edita; mantenerlo pulsado, editar o borrar (con deshacer). Operaciones de la cola: sin red también.

struct IngresosGastos: View {
    let r: ResumenGastos
    @State private var datos = DatosGastos.shared
    @State private var abierto: ResumenGastos.IngresoCiclo?
    @State private var error: String?

    var body: some View {
        let lista = datos.ingresosDelCiclo(r)
        if !lista.isEmpty {
            VStack(alignment: .leading, spacing: Tema.Espacio.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Ingresos").font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
                    Spacer()
                    Text("+" + Eur.texto(lista.reduce(0) { $0 + $1.importe }))
                        .font(Tema.fuente(.pequeno)).monospacedDigit().foregroundStyle(Tema.acento)
                        .contentTransition(.numericText())
                }
                ForEach(lista) { i in fila(i) }
                if let error {
                    Text(error).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro)
                }
            }
            .carta()
            .animation(Tema.Muelle.pantalla, value: lista.map(\.id))
            .sheet(item: $abierto) { i in EditorIngreso(ingreso: i) }
        }
    }

    private func fila(_ i: ResumenGastos.IngresoCiclo) -> some View {
        Button {
            Haptica.shared.toca(.marcar)
            abierto = i
        } label: {
            HStack(spacing: Tema.Espacio.m) {
                Circle().fill(i.tipo == "devuelve" ? datos.color(i.cat) : Tema.acento).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(i.titulo).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto).lineLimit(1)
                    Text([FechaGasto.titulo(i.dia),
                          i.tipo == "devuelve" ? "te devuelven de \(datos.nombreCat(i.cat))" : "ingreso extra",
                          origen(i.src)].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).lineLimit(1)
                }
                Spacer()
                Text("+" + Eur.texto(i.importe)).font(Tema.fuente(.texto)).monospacedDigit().foregroundStyle(Tema.acento)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(EstiloHundir())
        .contextMenu {
            Button("Editar", systemImage: "pencil") { abierto = i }
            Button("Borrar", systemImage: "trash", role: .destructive) {
                Task {
                    do { try await datos.borraIngreso(i); Haptica.shared.toca(.desmarcar); error = nil }
                    catch { Haptica.shared.toca(.error); self.error = DatosGastos.mensaje(error) }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func origen(_ src: String) -> String {
        ["atajo": "atajo", "applepay": "Apple Pay", "bot": "Telegram", "ticket": "ticket", "banco": "banco", "siri": "Siri"][src] ?? ""
    }
}

/// Cambiar o borrar un ingreso: importe, día, qué es (extra o te devuelven, y de qué categoría) y de quién.
struct EditorIngreso: View {
    let ingreso: ResumenGastos.IngresoCiclo
    @Environment(\.dismiss) private var cierra
    @State private var datos = DatosGastos.shared
    @State private var importe: String
    @State private var dia: Date
    @State private var tipo: String
    @State private var cat: String
    @State private var nota: String
    @State private var trabajando = false
    @State private var error: String?
    @State private var confirmaBorrar = false

    init(ingreso i: ResumenGastos.IngresoCiclo) {
        ingreso = i
        _importe = State(initialValue: Eur.campo(i.importe))
        _dia = State(initialValue: FechaGasto.fecha(i.dia) ?? Date())
        _tipo = State(initialValue: i.tipo)
        _cat = State(initialValue: i.cat)
        _nota = State(initialValue: i.nota.isEmpty ? i.comercio : i.nota)
    }

    private var cifra: Double? {
        guard let x = Eur.lee(importe), x > 0 else { return nil }
        return x
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("+").font(Tema.fuente(.cifra)).foregroundStyle(Tema.acento)
                        TextField("0,00", text: $importe)
                            .keyboardType(.decimalPad)
                            .font(Tema.fuente(.cifra)).monospacedDigit()
                            .accessibilityLabel("Importe en euros")
                        Text("€").font(Tema.fuente(.destacado)).foregroundStyle(Tema.suave)
                    }
                    DatePicker("Día", selection: $dia, displayedComponents: .date)
                }
                Section {
                    Picker("Qué es", selection: $tipo) {
                        Text("Ingreso extra").tag("extra")
                        Text("Me devuelven de un gasto").tag("devuelve")
                    }
                    if tipo == "devuelve" {
                        Picker("De qué categoría", selection: $cat) {
                            ForEach(datos.categorias) { Text($0.n).tag($0.id) }
                        }
                    }
                    TextField("De quién o de qué", text: $nota)
                        .onChange(of: nota) { _, v in if v.count > 120 { nota = String(v.prefix(120)) } }
                } footer: {
                    Text(tipo == "devuelve" ? "Lo que te devuelven resta del gasto de su categoría: las cuentas salen netas."
                         : "Un ingreso extra suma a lo que entra este ciclo y al ahorro.")
                }
                Section {
                    Button("Borrar ingreso", role: .destructive) { confirmaBorrar = true }
                }
                if let error {
                    Text(error).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro)
                }
            }
            .font(Tema.fuente(.texto))
            .scrollContentBackground(.hidden)
            .background(Tema.fondo.ignoresSafeArea())
            .navigationTitle("Ingreso")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cierra() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { guarda() } label: {
                        if trabajando { ProgressView() } else { Text("Guardar").fontWeight(.semibold) }
                    }
                    .disabled(cifra == nil || trabajando)
                }
            }
            .confirmationDialog("¿Borrar este ingreso de \(Eur.texto(ingreso.importe))?", isPresented: $confirmaBorrar,
                                titleVisibility: .visible) {
                Button("Borrar", role: .destructive) { borra() }
                Button("Mejor no", role: .cancel) {}
            }
            .onAppear { if cat.isEmpty { cat = datos.categorias.first { $0.id == "otros" }?.id ?? datos.categorias.first?.id ?? "otros" } }
            .tint(Tema.acento)
        }
        .presentationBackground(Tema.fondo)
        .presentationDragIndicator(.visible)
    }

    private func guarda() {
        guard let x = cifra, !trabajando else { return }
        trabajando = true
        error = nil
        Task {
            defer { trabajando = false }
            do {
                try await datos.editaIngreso(ingreso, importe: x, dia: FechaGasto.dia(dia), tipo: tipo, cat: cat, nota: nota)
                Haptica.shared.toca(.marcar)
                cierra()
            } catch {
                Haptica.shared.toca(.error)
                self.error = DatosGastos.mensaje(error)
            }
        }
    }

    private func borra() {
        trabajando = true
        Task {
            defer { trabajando = false }
            do {
                try await datos.borraIngreso(ingreso)
                Haptica.shared.toca(.desmarcar)
                cierra()
            } catch {
                Haptica.shared.toca(.error)
                self.error = DatosGastos.mensaje(error)
            }
        }
    }
}
