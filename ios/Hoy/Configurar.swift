import SwiftUI
import LocalAuthentication
import WidgetKit

/// Claves y ajustes. La primera vez sale sola; después se abre agitando el iPhone con la web delante
/// (ver la extensión de UIWindow en HoyApp.swift).
struct Configurar: View {
    let alGuardar: (Claves) -> Void

    @Environment(\.dismiss) private var cerrar
    @AppStorage("faceID", store: Almacen.defaults) private var faceID = false
    @AppStorage("salud", store: Almacen.defaults) private var salud = false
    @AppStorage("avisos", store: Almacen.defaults) private var avisos = false

    @State private var cfId = ""
    @State private var cfSecret = ""
    @State private var pass = ""
    @State private var probando = false
    @State private var resultado: String?
    @State private var fallo: String?
    @State private var aviso: String?
    @State private var sincronizando = false
    @State private var resumenSalud: String?
    @State private var hayClaves = Almacen.claves != nil

    init(alGuardar: @escaping (Claves) -> Void) {
        self.alGuardar = alGuardar
    }

    private var completas: Bool {
        ![cfId, cfSecret, pass].contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        Form {
            Section {
                SecureField("CF-Access-Client-Id", text: $cfId)
                SecureField("CF-Access-Client-Secret", text: $cfSecret)
                SecureField("Contraseña de la app (TODO_PASS)", text: $pass)
                Button {
                    Task { await pruebaYGuarda() }
                } label: {
                    HStack {
                        Text("Probar y guardar")
                        if probando {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(!completas || probando)
            } header: {
                Text("Claves")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if let fallo {
                        Text(fallo).foregroundStyle(.red)
                    } else if let resultado {
                        Text(resultado).foregroundStyle(.green)
                    }
                    Text("Se guardan solo en este iPhone. El service token es el de Cloudflare Access; la contraseña, la de la web.")
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Section {
                Toggle("Face ID al abrir", isOn: $faceID)
                    .onChange(of: faceID) { _, activo in
                        if activo { compruebaFaceID() }
                    }
                Toggle("Mandar Salud al servidor", isOn: $salud)
                    .disabled(!Salud.disponible)
                    .onChange(of: salud) { _, activo in
                        if activo { Task { await activaSalud() } }
                    }
                Toggle("Avisos en el iPhone", isOn: $avisos)
                    .onChange(of: avisos) { _, activo in
                        Task { await cambiaAvisos(activo) }
                    }
            } header: {
                Text("Ajustes")
            } footer: {
                if let aviso {
                    Text(aviso).foregroundStyle(.orange)
                } else {
                    Text("Salud manda sueño, pasos, peso y entrenos. Los avisos son locales y se recalculan al abrir la app.")
                }
            }

            if salud {
                Section {
                    Button {
                        Task { await sincronizaSalud() }
                    } label: {
                        HStack {
                            Text("Sincronizar Salud ahora")
                            if sincronizando {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(sincronizando || !hayClaves)
                    if let resumenSalud {
                        Text(resumenSalud)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            if hayClaves {
                SeccionSinConexion()
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color("Fondo"))
        .navigationTitle("Configurar Tom")
        .toolbar {
            if hayClaves {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { cerrar() }
                }
            }
        }
        .onAppear(perform: rellena)
    }

    private func rellena() {
        guard let c = Almacen.claves else { return }
        cfId = c.cfId
        cfSecret = c.cfSecret
        pass = c.pass
    }

    private func pruebaYGuarda() async {
        let claves = Claves(cfId: cfId.trimmingCharacters(in: .whitespacesAndNewlines),
                            cfSecret: cfSecret.trimmingCharacters(in: .whitespacesAndNewlines),
                            pass: pass.trimmingCharacters(in: .whitespacesAndNewlines))
        probando = true
        fallo = nil
        resultado = nil
        defer { probando = false }
        do {
            let hoy = try await API.prueba(claves)
            Almacen.claves = claves
            hayClaves = true
            let hechos = hoy.habitos.filter(\.hecho).count
            resultado = "Conectado: \(hechos)/\(hoy.habitos.count) hábitos hechos hoy."
            _ = try? await API.hoy()   // deja la caché lista para el widget
            WidgetCenter.shared.reloadAllTimelines()
            alGuardar(claves)
        } catch {
            fallo = error.localizedDescription
        }
    }

    private func compruebaFaceID() {
        var error: NSError?
        if !LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            faceID = false
            aviso = "Este iPhone no tiene Face ID ni código: \(error?.localizedDescription ?? "")"
        }
    }

    private func activaSalud() async {
        aviso = nil
        if await Salud.autoriza() {
            Salud.activaSegundoPlano()
        } else {
            salud = false
            aviso = "Salud no ha dado permiso. Revísalo en Ajustes > Salud > Acceso a datos."
        }
    }

    private func cambiaAvisos(_ activo: Bool) async {
        aviso = nil
        if activo, !(await Avisos.pidePermiso()) {
            avisos = false
            aviso = "Sin permiso para avisar. Actívalo en Ajustes > Notificaciones > Tom."
            return
        }
        await Avisos.programa()   // apagados, borra los que hubiera
    }

    private func sincronizaSalud() async {
        sincronizando = true
        defer { sincronizando = false }
        resumenSalud = await Salud.sincroniza() ?? "Nada nuevo que mandar (o falló la conexión)."
    }
}
