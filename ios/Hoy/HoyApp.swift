import SwiftUI
import UIKit
import WidgetKit
import Observation
import AppIntents

@main
struct HoyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegado
    @Environment(\.scenePhase) private var fase
    @State private var estado = EstadoApp()

    var body: some Scene {
        WindowGroup {
            Raiz(estado: estado)
                .onOpenURL(perform: abre)
        }
        .onChange(of: fase) { _, nueva in
            switch nueva {
            case .active:
                Accesos.instala()
                guard estado.claves != nil else { return }
                Navegador.shared.recogeVoz()
                // los hábitos de hoy como valores de «Marca … en Tom»
                AtajosHoy.updateAppShortcutParameters()
                Task {
                    await Salud.sincroniza()
                    await Avisos.programa()
                    WidgetCenter.shared.reloadAllTimelines()
                }
                // lo apuntado sin red sale ya, y se baja lo principal para tenerlo sin conexión
                Task { await Sincro.alActivar() }
            case .background:
                Avisos.pideRefresco()
                WidgetCenter.shared.reloadAllTimelines()
                if Almacen.defaults.bool(forKey: "faceID") { estado.bloqueado = true }
            default:
                break
            }
        }
    }

    /// hoy://ruta?r=/habitos.html (el widget): la web navega a esa ruta. hoy://voz abre el modo voz.
    private func abre(_ url: URL) {
        guard url.scheme == "hoy" else { return }
        if url.host == "voz" {
            Navegador.shared.voz = true
            return
        }
        guard let r = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "r" })?.value,
              r.hasPrefix("/") else { return }
        Navegador.shared.abre(r)
    }
}

@MainActor @Observable
final class EstadoApp {
    var claves: Claves? = Almacen.claves
    var bloqueado: Bool = Almacen.defaults.bool(forKey: "faceID")
    var configurando = false
}

struct Raiz: View {
    @Bindable var estado: EstadoApp
    @ObservedObject private var navegador = Navegador.shared

    /// Con Face ID puesto, el modo voz espera a que se desbloquee: no puede saltarse el bloqueo.
    private var vozVisible: Binding<Bool> {
        Binding(get: { navegador.voz && !estado.bloqueado },
                set: { navegador.voz = $0 })
    }

    var body: some View {
        ZStack {
            Color("Fondo").ignoresSafeArea()
            if let claves = estado.claves {
                // la web sigue viva debajo del bloqueo: al desbloquear no se recarga ni pierde lo que tenías a medias
                Web(claves: claves)
                    .ignoresSafeArea()
                    .onReceive(NotificationCenter.default.publisher(for: .hoyAgitado)) { _ in
                        if !estado.bloqueado { estado.configurando = true }
                    }
                    .sheet(isPresented: $estado.configurando) {
                        NavigationStack {
                            Configurar { estado.claves = $0 }
                        }
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
        }
        .animation(.default, value: estado.bloqueado)
    }
}

extension Notification.Name {
    static let hoyAgitado = Notification.Name("hoyAgitado")
}

// Configurar se abre AGITANDO el iPhone con la web delante: la web ocupa toda la pantalla y no hay sitio para un
// botón nativo. El agitado llega aquí por la cadena de respondedores desde el WKWebView (o la ventana, si no hay
// primer respondedor), así que basta con escucharlo en la ventana.
extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .hoyAgitado, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Avisos.registraTareaFondo()
        Red.shared.empieza()
        if Almacen.defaults.bool(forKey: "salud") { Salud.activaSegundoPlano() }
        return true
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
