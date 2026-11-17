import SwiftUI
import UIKit

/// Notas rápidas (lo de static/notas.html), en una hoja sobre Pendientes: las ideas que aún no son tareas. Apuntar
/// arriba; deslizar a la derecha la pasa a Pendientes y a la izquierda la borra, las dos con «Deshacer».
struct PantallaNotas: View {
    @State private var datos = DatosNotas.shared
    @State private var nueva = ""
    @State private var busca = ""
    @State private var enviando = false
    @FocusState private var escribiendo: Bool
    @Environment(\.dismiss) private var cierra

    private var visibles: [NotaRapida] {
        let q = busca.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return datos.notas }
        return datos.notas.filter { $0.t.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Tema.Espacio.m) {
                apuntar
                if datos.notas.count >= 8 {
                    CampoBusqueda(texto: $busca, pista: "Buscar en las notas")
                        .padding(.horizontal, Tema.Espacio.l)
                }
                lista
            }
            .padding(.top, Tema.Espacio.s)
            .background(Tema.fondo.ignoresSafeArea())
            .navigationTitle("Notas rápidas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { cierra() }
                }
            }
            .tostada(datos.aviso) { datos.quitaAviso() }
            .task { await datos.carga() }
        }
        .tint(Tema.acento)
        .presentationDetents([.large])
    }

    private var apuntar: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            if let copia = datos.copia {
                Label(API.notaCopia(copia), systemImage: "wifi.slash")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.aviso)
            }
            HStack(spacing: Tema.Espacio.s) {
                TextField("Lo que se te acaba de ocurrir…", text: $nueva, axis: .vertical)
                    .lineLimit(1...4)
                    .font(Tema.fuente(.destacado))
                    .foregroundStyle(Tema.texto)
                    .focused($escribiendo)
                    .submitLabel(.done)
                    .onSubmit(envia)
                    // Intro en un campo de varias líneas escribe un salto en vez de llamar a onSubmit
                    .onChange(of: nueva) { _, v in
                        guard v.contains("\n") else { return }
                        nueva = v.replacingOccurrences(of: "\n", with: " ")
                        envia()
                    }
                    .accessibilityLabel("Nota nueva")
                Button(action: envia) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Tema.acentoTexto)
                        .frame(width: 34, height: 34)
                        .background(vacia ? Tema.tenue : Tema.acento, in: Circle())
                }
                .disabled(vacia || enviando)
                .accessibilityLabel("Apuntar nota")
            }
        }
        .carta(relleno: Tema.Espacio.m)
        .padding(.horizontal, Tema.Espacio.l)
    }

    private var vacia: Bool { nueva.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func envia() {
        guard !enviando, !vacia else { return }
        enviando = true
        Haptica.shared.toca(.marcar)
        Task {
            let r = await datos.apunta(nueva)
            if r.ok {
                nueva = ""
                if r.encolada { datos.avisa(API.avisoEncolado) }
            } else if let e = r.error {
                datos.avisa("No se ha apuntado: \(e)", error: true)
            }
            enviando = false
        }
    }

    private var lista: some View {
        List {
            ForEach(visibles) { n in
                fila(n)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if !n.provisional {
                            Button { Task { await datos.aTarea(n) } } label: {
                                Label("A Pendientes", systemImage: "checklist")
                            }
                            .tint(Tema.acento)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if !n.provisional {
                            Button(role: .destructive) { Task { await datos.borra(n) } } label: {
                                Label("Borrar", systemImage: "trash")
                            }
                        }
                    }
                    .contextMenu {
                        if !n.provisional {
                            Button { Task { await datos.aTarea(n) } } label: { Label("Pasar a Pendientes", systemImage: "checklist") }
                            Button { UIPasteboard.general.string = n.t } label: { Label("Copiar", systemImage: "doc.on.doc") }
                            Button(role: .destructive) { Task { await datos.borra(n) } } label: { Label("Borrar", systemImage: "trash") }
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await datos.carga() }
        .overlay { vacio }
    }

    private func fila(_ n: NotaRapida) -> some View {
        HStack(alignment: .top, spacing: Tema.Espacio.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(n.t)
                    .font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                    .textSelection(.enabled)
                Text(n.provisional ? "Sin enviar" : Self.cuando(n.cuando))
                    .font(Tema.fuente(.pequeno)).foregroundStyle(n.provisional ? Tema.aviso : Tema.suave)
            }
            Spacer(minLength: 0)
            if !n.provisional {
                Button { Task { await datos.aTarea(n) } } label: {
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 20)).foregroundStyle(Tema.acento)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pasar a Pendientes")
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(Tema.carta)
    }

    @ViewBuilder private var vacio: some View {
        if visibles.isEmpty && !datos.cargando {
            VStack(spacing: Tema.Espacio.s) {
                Image(systemName: busca.isEmpty ? "lightbulb" : "magnifyingglass")
                    .font(.system(size: 34)).foregroundStyle(Tema.tenue)
                Text(busca.isEmpty ? (datos.error ?? "Sin notas. Lo que apuntes aquí no es una tarea hasta que tú lo digas.")
                                   : "Nada con «\(busca)»")
                    .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                    .multilineTextAlignment(.center)
            }
            .padding(Tema.Espacio.xl)
            .allowsHitTesting(false)
        }
    }

    /// «hoy, 10:32», «17 nov, 10:32», «escrita en Obsidian».
    static func cuando(_ s: String) -> String {
        let partes = s.split(separator: " ")
        guard partes.count == 2 else { return "Escrita en Obsidian" }
        let dia = String(partes[0]), hora = String(partes[1])
        if dia == Fecha.hoy() { return "hoy, \(hora)" }
        let trozos = dia.split(separator: "-").compactMap { Int($0) }
        guard trozos.count == 3 else { return s }
        let meses = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]
        let anio = Calendar.current.component(.year, from: Date())
        return "\(trozos[2]) \(meses[max(0, min(11, trozos[1] - 1))])\(trozos[0] != anio ? " \(trozos[0])" : ""), \(hora)"
    }
}
