import SwiftUI

/// Guardar un documento nuevo (con su fichero ya elegido) o cambiar los datos de uno que ya está.
struct HojaDocumento: View {
    enum Modo {
        case nuevo(BorradorDocumento)
        case cambiar(DocumentoTom)
    }

    let modo: Modo
    let categorias: [(id: String, nombre: String)]
    let alGuardar: (FichaDocumento) async -> Bool
    var alBorrar: (() async -> Void)?

    @Environment(\.dismiss) private var cierra
    @State private var nombre: String
    @State private var cat: String
    @State private var caduca: Bool
    @State private var fecha: Date
    @State private var titular: String
    @State private var notas: String
    @State private var guardando = false
    @State private var confirmaBorrar = false

    init(modo: Modo, categorias: [(id: String, nombre: String)], alGuardar: @escaping (FichaDocumento) async -> Bool,
         alBorrar: (() async -> Void)? = nil) {
        self.modo = modo
        self.categorias = categorias
        self.alGuardar = alGuardar
        self.alBorrar = alBorrar
        switch modo {
        case .nuevo(let b):
            _nombre = State(initialValue: b.nombreSugerido)
            _cat = State(initialValue: "identidad")
            _caduca = State(initialValue: false)
            _fecha = State(initialValue: FechasES.fecha(Fecha.hoy()) ?? Date())
            _titular = State(initialValue: "")
            _notas = State(initialValue: "")
        case .cambiar(let d):
            _nombre = State(initialValue: d.n)
            _cat = State(initialValue: d.cat)
            _caduca = State(initialValue: !d.caduca.isEmpty)
            _fecha = State(initialValue: FechasES.fecha(d.caduca) ?? FechasES.fecha(Fecha.hoy()) ?? Date())
            _titular = State(initialValue: d.titular)
            _notas = State(initialValue: d.notas)
        }
    }

    private var esNuevo: Bool { if case .nuevo = modo { return true } else { return false } }
    private var valido: Bool { !nombre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                if case .nuevo(let b) = modo {
                    Section {
                        Label(b.nombre, systemImage: b.nombre.lowercased().hasSuffix(".pdf") ? "doc.fill" : "photo")
                            .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                            .lineLimit(1)
                        Text("\(ByteCountFormatter.string(fromByteCount: Int64(b.datos.count), countStyle: .file)) · se guarda también en este iPhone, para verlo sin red")
                            .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                    }
                    .listRowBackground(Tema.carta)
                }
                Section {
                    TextField("Qué es: Pasaporte, Seguro del coche…", text: $nombre)
                        .textInputAutocapitalization(.sentences)
                    Picker("Tipo", selection: $cat) {
                        ForEach(categorias, id: \.id) { Text($0.nombre).tag($0.id) }
                    }
                    TextField("A nombre de (opcional)", text: $titular)
                } header: {
                    Text("Documento").estiloEtiqueta()
                }
                .listRowBackground(Tema.carta)
                Section {
                    Toggle("Caduca", isOn: $caduca.animation(Tema.Muelle.pantalla))
                    if caduca {
                        DatePicker("Fecha", selection: $fecha, displayedComponents: .date)
                    }
                } footer: {
                    Text(caduca && cat != "garantias" ? "Te apunto en Pendientes renovarlo un mes antes." : "")
                }
                .listRowBackground(Tema.carta)
                Section {
                    TextField("Aseguradora, teléfono de asistencia…", text: $notas, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("Notas").estiloEtiqueta()
                } footer: {
                    Text("Sin números de documento.")
                }
                .listRowBackground(Tema.carta)
                if alBorrar != nil {
                    Section {
                        Button("Borrar documento", role: .destructive) { confirmaBorrar = true }
                    }
                    .listRowBackground(Tema.carta)
                }
            }
            .font(Tema.fuente(.texto))
            .scrollContentBackground(.hidden)
            .background(Tema.fondo)
            .tint(Tema.acento)
            .navigationTitle(esNuevo ? "Guardar documento" : "Cambiar documento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cierra() } }
                ToolbarItem(placement: .confirmationAction) {
                    if guardando {
                        ProgressView()
                    } else {
                        Button("Guardar") { guarda() }.fontWeight(.semibold).disabled(!valido)
                    }
                }
            }
            .confirmationDialog("¿Borrar este documento?", isPresented: $confirmaBorrar, titleVisibility: .visible) {
                Button("Borrar", role: .destructive) {
                    Task {
                        await alBorrar?()
                        cierra()
                    }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Va a la papelera del servidor y puedes deshacerlo unos segundos.")
            }
            .interactiveDismissDisabled(guardando)
        }
        .environment(\.locale, FechasES.locale)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Tema.fondo)
    }

    private func guarda() {
        guardando = true
        let ficha = FichaDocumento(n: nombre.trimmingCharacters(in: .whitespacesAndNewlines), cat: cat,
                                   caduca: caduca ? Fecha.dia(fecha) : nil,
                                   titular: titular.trimmingCharacters(in: .whitespacesAndNewlines),
                                   notas: notas.trimmingCharacters(in: .whitespacesAndNewlines))
        Task {
            if await alGuardar(ficha) { cierra() } else { guardando = false }
        }
    }
}
