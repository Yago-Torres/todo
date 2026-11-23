import SwiftUI

/// Apuntar un peso a mano y corregir o borrar los que llegaron mal (de otra persona en la báscula, uno repetido…).
/// Lo que se toca aquí el servidor lo da por bueno: lo que mande luego Salud para ese día ya no lo pisa.
struct HojaPesos: View {
    let datos: DatosSalud
    @Environment(\.dismiss) private var cierra
    @State private var dia = Date()
    @State private var kg = ""
    @State private var mensaje: String?
    @State private var guardando = false
    @FocusState private var enKg: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Día", selection: $dia, in: ...Date(), displayedComponents: .date)
                    TextField("Kilos", text: $kg)
                        .keyboardType(.decimalPad)
                        .focused($enKg)
                        .monospacedDigit()
                    Button("Guardar") { Task { await guarda() } }
                        .disabled(guardando || numero == nil)
                } header: {
                    Text("Apuntar o corregir")
                } footer: {
                    Text(mensaje ?? "Toca un pesaje para corregirlo; desliza para borrarlo.")
                }
                Section("Pesajes") {
                    if pesos.isEmpty {
                        Text("Sin pesajes todavía.").foregroundStyle(Tema.suave)
                    }
                    ForEach(pesos, id: \.dia) { p in
                        Button { edita(p) } label: {
                            HStack {
                                Text(FechasES.corta(p.dia)).foregroundStyle(Tema.texto)
                                Spacer()
                                Text("\(FechasES.coma(p.kg)) kg").monospacedDigit().foregroundStyle(Tema.suave)
                            }
                        }
                        .swipeActions {
                            Button("Borrar", role: .destructive) { Task { await borra(p) } }
                        }
                    }
                }
            }
            .navigationTitle("Peso")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Hecho") { cierra() } }
            }
        }
    }

    private var pesos: [PesajeCuerpo] { (datos.informe?.cuerpo.peso ?? []).reversed() }

    private var numero: Double? {
        let n = Double(kg.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        return n.flatMap { (20...400).contains($0) ? $0 : nil }
    }

    private func edita(_ p: PesajeCuerpo) {
        dia = FechasES.fecha(p.dia) ?? Date()
        kg = FechasES.coma(p.kg)
        enKg = true
    }

    private func guarda() async {
        guard let n = numero else { return }
        guardando = true
        defer { guardando = false }
        do {
            mensaje = try await datos.corrige(dia: Fecha.dia(dia), campo: "peso", valor: n)
            kg = ""
            enKg = false
            Haptica.shared.toca(.marcar)
        } catch {
            mensaje = error.localizedDescription
        }
    }

    private func borra(_ p: PesajeCuerpo) async {
        do {
            mensaje = try await datos.corrige(dia: p.dia, campo: "peso", valor: nil)
        } catch {
            mensaje = error.localizedDescription
        }
    }
}
