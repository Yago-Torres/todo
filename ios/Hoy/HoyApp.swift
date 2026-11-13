import SwiftUI
import UIKit
import WidgetKit
import Observation
import AppIntents
import AVFoundation

@main
struct HoyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegado
    @Environment(\.scenePhase) private var fase
    @State private var estado = EstadoApp()

    init() {
        Navegador.nativas = RegistroNativo.rutas   // qué secciones son pantallas nativas (Hoy/Nativo/Registro.swift)
    }

    var body: some Scene {
        WindowGroup {
            Raiz(estado: estado)
                .onOpenURL(perform: abre)
        }
        .onChange(of: fase) { _, nueva in
            switch nueva {
            case .active:
                // primero se pinta lo guardado; lo demás, por detrás (Arranque.swift)
                Arranque.alActivar(conClaves: estado.claves != nil)
            case .background:
                Avisos.pideRefresco()
                WidgetCenter.shared.reloadAllTimelines()
                if Almacen.defaults.bool(forKey: "faceID") { estado.bloqueado = true }
            default:
                break
            }
        }
    }

    /// hoy://ruta?r=/habitos.html (el widget, los controles): la pantalla nativa de esa ruta (una desconocida, Hoy).
    /// hoy://voz abre el modo voz.
    /// hoy://configurar abre Configurar (sin claves ya está delante).
    private func abre(_ url: URL) {
        guard url.scheme == "hoy" else { return }
        if url.host == "voz" {
            Navegador.shared.voz = true
            return
        }
        if url.host == "configurar" {
            if estado.claves != nil { estado.configurando = true }
            return
        }
        // hoy://freno?app=instagram: lo abre la automatización de Atajos cuando la app no tiene pase (Freno.swift)
        if url.host == "freno" {
            let nombre = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "app" }?.value
            let revision = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "revision" }?.value == "1"
            if let nombre, let app = AppFrenada(rawValue: nombre) {
                Freno.revision = revision   // desde un «¿sigues?»: sin espera, con lo que llevas
                estado.freno = app
            }
            return
        }
        let r = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "r" }?.value
        Navegador.shared.abre(r.flatMap { $0.hasPrefix("/") ? $0 : nil } ?? "/")
    }
}

@MainActor @Observable
final class EstadoApp {
    var claves: Claves? = Almacen.claves
    var bloqueado: Bool = Almacen.defaults.bool(forKey: "faceID")
    var configurando = false
    /// La pantalla de freno de apps, encima de todo (también del bloqueo: no enseña nada tuyo).
    var freno: AppFrenada?
}

struct Raiz: View {
    @Bindable var estado: EstadoApp
    @ObservedObject private var navegador = Navegador.shared

    /// Con Face ID puesto, el modo voz espera a que se desbloquee: no puede saltarse el bloqueo.
    private var vozVisible: Binding<Bool> {
        Binding(get: { navegador.voz && !estado.bloqueado },
                set: { navegador.voz = $0 })
    }

    /// La hoja de subir un intento de escalada (desde Entreno), tampoco por encima del bloqueo.
    private var escaladaVisible: Binding<Bool> {
        Binding(get: { Escalada.shared.hojaVisible && !estado.bloqueado },
                set: { Escalada.shared.hojaVisible = $0 })
    }

    /// Igual con Configurar: lo pedido con la app bloqueada sale después de desbloquear.
    private var configurarVisible: Binding<Bool> {
        Binding(get: { estado.configurando && !estado.bloqueado },
                set: { estado.configurando = $0 })
    }

    var body: some View {
        ZStack {
            Tema.fondo.ignoresSafeArea()
            if let claves = estado.claves {
                // leído aquí, en body, para que Observation repinte al pedir la hoja (el get del Binding va fuera de body)
                let _ = Escalada.shared.hojaVisible
                // las pantallas nativas y la barra (Hoy/Nativo/Pestanas.swift). Se pintan ya, con la última copia, también
                // debajo del bloqueo: al pasar Face ID está todo listo y no se pierde lo que tenías a medias
                Pestanas(claves: claves)
                    .sheet(isPresented: configurarVisible) {
                        NavigationStack {
                            Configurar { estado.claves = $0 }
                        }
                    }
                    .sheet(isPresented: escaladaVisible) {
                        HojaEscalada()
                    }
                    .fullScreenCover(isPresented: vozVisible) {
                        Voz()
                    }
                if estado.bloqueado {
                    Bloqueo { estado.bloqueado = false }
                        .transition(.opacity)
                }
            } else {
                NavigationStack {
                    Configurar { estado.claves = $0 }
                }
            }
            if let app = estado.freno {
                PantallaFreno(app: app) { estado.freno = nil }
                    .id(app)
                    .transition(.move(edge: .bottom))
                    .zIndex(10)
            }
        }
        .animation(.default, value: estado.bloqueado)
        .animation(.spring(duration: 0.4), value: estado.freno)
        // modo y acento de la apariencia elegida (Configurar → Apariencia, o la web del ordenador); de noche, oscuro
        .preferredColorScheme(Aspecto.shared.esquema)
        .tint(Tema.acento)
        // el acceso «Ajustes de Tom» del icono y Ajustes → «Ajustes de la app»
        .onChange(of: navegador.configurar, initial: true) { _, pedido in
            guard pedido else { return }
            navegador.configurar = false
            if estado.claves != nil { estado.configurando = true }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // lo que tiene que estar antes de acabar el arranque (tareas de fondo, Salud en segundo plano); lo demás,
        // en Arranque cuando ya se ha pintado
        Avisos.registraTareaFondo()
        Red.shared.empieza()
        if Almacen.defaults.bool(forKey: "salud") { Salud.activaSegundoPlano() }
        return true
    }

    /// iOS despierta la app cuando acaba una subida en segundo plano (Escalada.swift): se reabre la sesión, que
    /// recibe los eventos, y se llama a completionHandler cuando ya se ha avisado (urlSessionDidFinishEvents).
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == Subidas.identificador else {
            completionHandler()
            return
        }
        Subidas.shared.alAcabar = completionHandler
        Subidas.shared.arranca()
    }

    // con escenas, el acceso del icono que lanza la app en frío llega aquí y no en launchOptions
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let acceso = options.shortcutItem { Accesos.maneja(acceso.type) }
        let configuracion = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuracion.delegateClass = EscenaDelegado.self
        return configuracion
    }
}

/// Solo para los accesos del icono con la app ya abierta; lo demás lo lleva SwiftUI.
final class EscenaDelegado: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        Accesos.maneja(shortcutItem.type)
        completionHandler(true)
    }
}
