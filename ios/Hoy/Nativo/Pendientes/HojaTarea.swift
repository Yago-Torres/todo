import SwiftUI
import UIKit

/// La hoja para cambiar una tarea (texto, día y hora) o para elegir solo el «cuándo» de una nueva (`conTexto: false`).
/// El día y la hora son opcionales: sin día no hay hora (como en el vault).
struct HojaTarea: View {
    let titulo: String
    var conTexto = true
    var alGuardar: (_ texto: String, _ dia: String?, _ hora: String?) async -> Void
    var alBorrar: (() async -> Void)?

    @Environment(\.dismiss) private var cierra
    @State private var texto: String
    @State private var conFecha: Bool
    @State private var fecha: Date
    @State private var conHora: Bool
    @State private var hora: Date
    @State private var confirmaBorrar = false
    @State private var guardando = false
    @FocusState private var enfocado: Bool

    init(titulo: String, texto: String = "", dia: String?, hora: String?, conTexto: Bool = true,
         alGuardar: @escaping (_ texto: String, _ dia: String?, _ hora: String?) async -> Void,
         alBorrar: (() async -> Void)? = nil) {
        self.titulo = titulo
        self.conTexto = conTexto
        self.alGuardar = alGuardar
        self.alBorrar = alBorrar
        _texto = State(initialValue: texto)
        _conFecha = State(initialValue: dia != nil)
        _fecha = State(initialValue: dia.flatMap(FechasES.fecha) ?? Date())
        _conHora = State(initialValue: dia != nil && hora != nil)
        var h = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
        if let hora, hora.count >= 5, let hh = Int(hora.prefix(2)), let mm = Int(hora.dropFirst(3).prefix(2)) {
            h = Calendar.current.date(bySettingHour: hh, minute: mm, second: 0, of: Date()) ?? h
        }
        _hora = State(initialValue: h)
    }

    private var valido: Bool { !conTexto || !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                if conTexto {
                    Section {
                        TextField("Llamar al dentista", text: $texto, axis: .vertical)
                            .lineLimit(1...4)
                            .focused($enfocado)
                            .submitLabel(.done)
                    } header: {
                        Text("Qué tienes que hacer").estiloEtiqueta()
                    }
                    .listRowBackground(Tema.carta)
                }
                Section {
                    Toggle("Con fecha", isOn: $conFecha.animation(Tema.Muelle.pantalla))
                    if conFecha {
                        atajos
                        DatePicker("Día", selection: $fecha, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                    }
                } header: {
                    Text("Día").estiloEtiqueta()
                }
                .listRowBackground(Tema.carta)
                Section {
                    Toggle("Con hora", isOn: $conHora.animation(Tema.Muelle.pantalla))
                        .onChange(of: conHora) { _, activa in
                            if activa { withAnimation(Tema.Muelle.pantalla) { conFecha = true } }
                        }
                    if conHora {
                        DatePicker("Hora", selection: $hora, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                    }
                } header: {
                    Text("Hora").estiloEtiqueta()
                } footer: {
                    Text(conHora ? "A esa hora te aviso por Telegram." : "Con hora, te aviso por Telegram.")
                }
                .listRowBackground(Tema.carta)
                if alBorrar != nil {
                    Section {
                        Button("Borrar tarea", role: .destructive) { confirmaBorrar = true }
                    }
                    .listRowBackground(Tema.carta)
                }
            }
            .font(Tema.fuente(.texto))
            .scrollContentBackground(.hidden)
            .background(Tema.fondo)
            .tint(Tema.acento)
            .navigationTitle(titulo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cierra() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { guarda() }
                        .fontWeight(.semibold)
                        .disabled(!valido || guardando)
                }
            }
            .confirmationDialog("¿Borrar esta tarea?", isPresented: $confirmaBorrar, titleVisibility: .visible) {
                Button("Borrar", role: .destructive) {
                    Task {
                        await alBorrar?()
                        cierra()
                    }
                }
                Button("Cancelar", role: .cancel) {}
            }
        }
        .environment(\.locale, FechasES.locale)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Tema.fondo)
        .task { if conTexto && texto.isEmpty { enfocado = true } }
    }

    /// Hoy, mañana y el lunes: lo que más se elige.
    private var atajos: some View {
        HStack(spacing: Tema.Espacio.s) {
            atajo("Hoy", Fecha.hoy())
            atajo("Mañana", FechasES.masDias(Fecha.hoy(), 1))
            atajo("Lunes", Self.proximoLunes())
        }
    }

    private func atajo(_ nombre: String, _ dia: String) -> some View {
        let activo = Fecha.dia(fecha) == dia
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(Tema.Muelle.toque) { fecha = FechasES.fecha(dia) ?? fecha }
        } label: {
            Text(nombre)
                .font(Tema.fuente(.pequeno, peso: .medium))
                .foregroundStyle(activo ? Tema.acentoTexto : Tema.texto)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(activo ? Tema.acento : Tema.carta2, in: Capsule())
        }
        .buttonStyle(.borderless)
    }

    static func proximoLunes() -> String {
        let d = Calendar.current.nextDate(after: Date(), matching: DateComponents(weekday: 2), matchingPolicy: .nextTime) ?? Date()
        return Fecha.dia(d)
    }

    private func guarda() {
        guardando = true
        let dia = conFecha ? Fecha.dia(fecha) : nil
        let h = (conFecha && conHora) ? FechasES.texto(hora, "HH:mm") : nil
        let t = texto
        Task {
            await alGuardar(t, dia, h)
            cierra()
        }
    }
}
