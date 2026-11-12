import SwiftUI

/// Lo de /ajustes.html que no estaba en Configurar: cómo te saludo, sonidos, secciones, límites del móvil y la mascota.
/// Son varias `Section` para meterlas en cualquier List o Form (Configurar y la pantalla Ajustes las comparten).
struct SeccionAjustesTom: View {
    @State private var modelo = ModeloAjustes.shared

    var body: some View {
        Group {
            if let a = modelo.ajustes {
                tu(a)
                sonidos(a)
                secciones(a)
                mascota(a)
                limites(a)
                estado
            } else {
                Section {
                    if modelo.cargando {
                        HStack { ProgressView(); Text("Cargando tus ajustes…").foregroundStyle(Tema.suave) }
                    } else {
                        Text(modelo.error ?? "Tus ajustes de Tom aún no han llegado.")
                            .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                        Button("Volver a intentarlo") { Task { await modelo.carga(forzar: true) } }
                    }
                } header: { Text("Tom") }
            }
        }
        .listRowBackground(Tema.carta)
        .task { await modelo.carga() }
    }

    // MARK: Tú

    private func tu(_ a: AjustesTom) -> some View {
        Section {
            TextField("Cómo te saludo", text: Binding(
                get: { a.nombre },
                set: { v in modelo.cambia { $0.nombre = String(v.prefix(30)) } }))
                .textContentType(.givenName)
                .submitLabel(.done)
        } header: {
            Text("Tú")
        } footer: {
            Text("Con tu nombre, Tom te saluda en Hoy y en los mensajes.")
        }
    }

    // MARK: Sonidos

    private func sonidos(_ a: AjustesTom) -> some View {
        Section {
            Toggle(isOn: Binding(get: { a.sonidos }, set: { v in
                Haptica.shared.toca(.marcar)
                modelo.cambia { $0.sonidos = v }
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sonidos sutiles")
                    Text("Un clic al marcar, una campanita al completar el día, el fin del descanso y cuando algo falla. Respetan el modo silencio.")
                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                }
            }
        } header: {
            Text("Sonidos")
        } footer: {
            Text("Es el ajuste de la web; la app usa su propia háptica.")
        }
    }

    // MARK: Secciones

    private func secciones(_ a: AjustesTom) -> some View {
        Section {
            ForEach(AjustesTom.modulosConocidos, id: \.id) { m in
                let fuera = a.sinApp.contains(m.id)
                let mod = a.modulo(m.id)
                Toggle(isOn: Binding(get: { mod.activo && !fuera }, set: { v in
                    Haptica.shared.toca(.marcar)
                    modelo.cambia { var x = $0.modulo(m.id); x.activo = v; $0.modulos[m.id] = x }
                })) {
                    HStack(spacing: Tema.Espacio.s) {
                        Text(m.nombre)
                        if fuera {
                            Text("sin conectar").estiloEtiqueta().foregroundStyle(Tema.suave)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Tema.carta2, in: Capsule())
                        }
                    }
                }
                .disabled(fuera)
                if mod.activo && !fuera {
                    Toggle("En la barra de abajo", isOn: Binding(get: { mod.barra }, set: { v in
                        Haptica.shared.toca(.marcar)
                        modelo.cambia { var x = $0.modulo(m.id); x.barra = v; $0.modulos[m.id] = x }
                    }))
                    .font(Tema.fuente(.pequeno))
                    .foregroundStyle(Tema.suave)
                    .padding(.leading, Tema.Espacio.l)
                    .transition(.opacity)
                }
            }
        } header: {
            Text("Secciones")
        } footer: {
            Text("Lo que no esté activo desaparece también de Hoy. Lo activo puede quedarse fuera de la barra: sigue en Hoy, pero no ocupa sitio. El orden de la barra de la app se cambia en Pantallas.")
        }
    }

    // MARK: Mascota

    private func mascota(_ a: AjustesTom) -> some View {
        Section {
            NavigationLink {
                EditorMascota()
                    .navigationTitle("Tu mascota")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                HStack(spacing: Tema.Espacio.m) {
                    Circle().fill(Color(hex: a.mascota.color)).frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tu mascota")
                        Text(a.mascota.tipo == "flor" ? "Una flor de boli" : "Un fantasma")
                            .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                    }
                }
            }
        } header: {
            Text("Mascota")
        }
    }

    // MARK: Límites del móvil

    @ViewBuilder private func limites(_ a: AjustesTom) -> some View {
        let apps = Array(Set(a.limites.keys).union(modelo.appsVistas)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        Section {
            if apps.isEmpty {
                Text("Aún no ha llegado ningún aviso del atajo de Pantalla.")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            }
            ForEach(apps, id: \.self) { app in
                FilaLimite(app: app, minutos: a.limites[app]) { m in
                    modelo.cambia { if let m { $0.limites[app] = m } else { $0.limites[app] = nil } }
                }
            }
        } header: {
            Text("Móvil: límite al día")
        } footer: {
            Text("Al abrir la app, el aviso del atajo te dice cuánto te queda; al pasarte, te escribo por Telegram. Déjalo vacío para no poner límite.")
        }
    }

    // MARK: estado del guardado

    @ViewBuilder private var estado: some View {
        switch modelo.estado {
        case .reposo, .guardado:
            EmptyView()
        case .guardando:
            Section { Label("Guardando…", systemImage: "arrow.triangle.2.circlepath").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave) }
        case .encolado:
            Section { Label("Sin conexión: se guardará al volver la red.", systemImage: "wifi.slash").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.aviso) }
        case .fallo(let texto):
            Section { Label("No se ha guardado: \(texto)", systemImage: "exclamationmark.triangle").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro) }
        }
    }
}

/// Una app con su límite diario en minutos (1 a 600); vacío = sin límite.
private struct FilaLimite: View {
    let app: String
    let minutos: Int?
    let cambia: (Int?) -> Void
    @State private var texto = ""

    var body: some View {
        HStack {
            Text(app)
            Spacer()
            TextField("sin límite", text: $texto)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 96)
                .accessibilityLabel("Límite de \(app) en minutos")
            Text("min").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
        }
        .onAppear { texto = minutos.map(String.init) ?? "" }
        .onChange(of: texto) { _, v in
            let limpio = v.filter(\.isNumber)
            if limpio != v { texto = limpio; return }
            if limpio.isEmpty { if minutos != nil { cambia(nil) }; return }
            let n = min(600, max(1, Int(limpio) ?? 1))
            if n != Int(limpio) { texto = String(n); return }
            if n != minutos { cambia(n) }
        }
    }
}
