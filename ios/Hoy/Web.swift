import SwiftUI
import UIKit
import WebKit
import Combine
import WidgetKit

/// La PWA a pantalla completa, como en modo app del iPhone: la web ya se aparta sola con env(safe-area-inset-*).
struct Web: UIViewRepresentable {
    let claves: Claves

    func makeCoordinator() -> Coordinador { Coordinador(claves: claves) }

    func makeUIView(context: Context) -> WKWebView { context.coordinator.creaVista() }

    func updateUIView(_ vista: WKWebView, context: Context) { context.coordinator.cambia(claves) }

    static func dismantleUIView(_ vista: WKWebView, coordinator: Coordinador) { coordinator.desmonta() }
}

@MainActor
final class Coordinador: NSObject, WKNavigationDelegate, WKUIDelegate {
    private static let propios: Set<String> = ["todo.yagotg.dev", "yagotg.dev", "yagoraspberry.cloudflareaccess.com"]

    private var claves: Claves
    private weak var vista: WKWebView?
    private let refresco = UIRefreshControl()
    private var suscripcion: AnyCancellable?
    private var listo = false            // las cookies ya están (o se intentó): se puede cargar
    private var pendiente: String?       // lo que pidió el Navegador antes de estar listo
    private var ultima: URL?             // la última página propia pedida, para volver a ella tras renovar
    private var reintentado = false      // renovar las cookies una sola vez por fallo, sin bucles
    private var planB: (url: URL, cuando: Date)?   // la última copia de Local cargada sin red, para no repetirla en bucle

    init(claves: Claves) {
        self.claves = claves
        super.init()
    }

    func creaVista() -> WKWebView {
        let conf = WKWebViewConfiguration()
        conf.websiteDataStore = .default()
        // el service worker solo funciona en un WKWebView limitado a los dominios de WKAppBoundDomains
        conf.limitsNavigationsToAppBoundDomains = true
        conf.allowsInlineMediaPlayback = true
        let contenido = WKUserContentController()
        contenido.addUserScript(WKUserScript(source: Self.puente, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        contenido.add(MensajeroDebil(self), name: "hoy")
        // los datos sin red (Offline.swift): la copia de Local y la cola de cambios
        contenido.addUserScript(WKUserScript(source: PuenteLocal.guion, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let local = PuenteLocal()
        contenido.addScriptMessageHandler(local, contentWorld: .page, name: PuenteLocal.nombre)
        conf.userContentController = contenido

        let v = WKWebView(frame: .zero, configuration: conf)
        local.vista = v
        // sin esto, al arrancar se ve un destello blanco antes de que pinte la web
        let fondo = UIColor(named: "Fondo") ?? .systemBackground
        v.isOpaque = false
        v.backgroundColor = fondo
        v.scrollView.backgroundColor = fondo
        v.underPageBackgroundColor = fondo
        v.scrollView.contentInsetAdjustmentBehavior = .never
        v.allowsBackForwardNavigationGestures = true
        v.navigationDelegate = self
        v.uiDelegate = self
        #if DEBUG
        v.isInspectable = true
        #endif
        refresco.addTarget(self, action: #selector(recarga), for: .valueChanged)
        v.scrollView.refreshControl = refresco
        vista = v
        Entreno.shared.web = v

        suscripcion = Navegador.shared.$ruta
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ruta in self?.ve(ruta) }

        Task {
            await prepara(forzar: false)
            listo = true
            carga(pendiente ?? "/")
            pendiente = nil
        }
        return v
    }

    func cambia(_ nuevas: Claves) {
        guard nuevas != claves else { return }
        claves = nuevas
        reintentado = false
        renueva(volviendoA: ultima)
    }

    func desmonta() {
        suscripcion?.cancel()
        vista?.configuration.userContentController.removeScriptMessageHandler(forName: "hoy")
        vista?.configuration.userContentController.removeScriptMessageHandler(forName: PuenteLocal.nombre, contentWorld: .page)
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: navegar

    private func ve(_ ruta: String) {
        Navegador.shared.ruta = nil
        if listo { carga(ruta) } else { pendiente = ruta }
    }

    private func carga(_ ruta: String) {
        guard let url = URL(string: ruta, relativeTo: Config.web)?.absoluteURL else { return }
        ultima = url
        vista?.load(URLRequest(url: url))
    }

    @objc private func recarga() {
        if let ultima { vista?.load(URLRequest(url: ultima)) } else { carga("/") }
    }

    private func renueva(volviendoA url: URL?) {
        Task {
            await prepara(forzar: true)
            if let url { vista?.load(URLRequest(url: url)) } else { carga("/") }
        }
    }

    private static func esPropio(_ url: URL) -> Bool {
        propios.contains(url.host?.lowercased() ?? "")
    }

    private static func esLoginAccess(_ url: URL) -> Bool {
        url.host?.lowercased().hasSuffix("cloudflareaccess.com") == true || url.path.hasPrefix("/cdn-cgi/access/login")
    }

    // MARK: cookies

    /// CF_Authorization (Access, 1 mes) y todo_sesion (la app, 90 días), copiadas al almacén de la web.
    /// Se renuevan si faltan o caducan en menos de 3 días.
    private func prepara(forzar: Bool) async {
        // sin red no se renueva nada (ni se espera a que falle): la web sale de la copia del service worker
        guard Red.shared.hayRed else { return }
        let almacen = WKWebsiteDataStore.default().httpCookieStore
        if !forzar {
            let actuales = await almacen.allCookies()
            let limite = Date().addingTimeInterval(3 * 24 * 3600)
            let vigentes = Set(actuales.filter { ($0.expiresDate ?? .distantPast) > limite && Self.dominioPropio($0) }.map(\.name))
            if vigentes.contains("CF_Authorization") && vigentes.contains("todo_sesion") { return }
        }
        for galleta in await Galletas.nuevas(claves) {
            await almacen.setCookie(galleta)
        }
    }

    private static func dominioPropio(_ c: HTTPCookie) -> Bool {
        let dominio = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain
        return Config.web.host == dominio || Config.web.host?.hasSuffix("." + dominio) == true
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor accion: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = accion.request.url else { return .allow }
        let esquema = url.scheme?.lowercased() ?? ""
        if ["about", "blob", "data", "javascript"].contains(esquema) { return .allow }
        let principal = accion.targetFrame?.isMainFrame ?? true

        // obsidian://, mailto:, tel:... y las webs de fuera, a su app o a Safari
        guard esquema == "http" || esquema == "https", Self.esPropio(url) else {
            if principal {
                _ = await UIApplication.shared.open(url)
                return .cancel
            }
            return .allow
        }
        if accion.targetFrame == nil {   // target="_blank" o window.open de una página propia: en la misma vista
            webView.load(accion.request)
            return .cancel
        }
        if principal && Self.esLoginAccess(url) {
            if !reintentado {
                reintentado = true
                renueva(volviendoA: ultima)
                return .cancel
            }
            return .allow   // si renovar no bastó, que se pueda entrar a mano en Access
        }
        if principal { ultima = url }
        return .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor respuesta: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if respuesta.isForMainFrame, !reintentado,
           let http = respuesta.response as? HTTPURLResponse, [401, 403].contains(http.statusCode),
           let url = http.url, url.host == Config.web.host {
            reintentado = true
            renueva(volviendoA: url)
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        UIApplication.shared.isIdleTimerDisabled = false   // página nueva: su wake lock ya no existe
        // en el entreno, tirar hacia abajo sin querer recargaría y se perdería la serie en curso
        let enEntreno = webView.url?.path.hasPrefix("/entreno") == true
        webView.scrollView.refreshControl = enEntreno ? nil : refresco
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refresco.endRefreshing()
        if webView.url?.host == Config.web.host { reintentado = false }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        refresco.endRefreshing()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        refresco.endRefreshing()
        let e = error as NSError
        // cancelada por nosotros (renovar cookies) o porque empezó otra: no es un fallo de red
        if e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled { return }
        if e.domain == "WebKitErrorDomain" && e.code == 102 { return }   // «frame load interrupted» por la política
        // sin red ni service worker: lo guardado en Local de esa ruta (un documento de «Ver»), si lo hay
        if let fallida = e.userInfo[NSURLErrorFailingURLErrorKey] as? URL, Self.esPropio(fallida),
           !(planB.map { $0.url == fallida && Date().timeIntervalSince($0.cuando) < 5 } ?? false),
           let copia = PuenteLocal.copiaDe(fallida) {
            planB = (fallida, Date())
            webView.load(copia.cuerpo, mimeType: copia.mime, characterEncodingName: "utf-8", baseURL: fallida)
            return
        }
        // sin red y sin service worker que la sirva: una página mínima desde la que tirar hacia abajo para reintentar
        webView.loadHTMLString(Self.paginaError(e.localizedDescription), baseURL: nil)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        recarga()
    }

    // MARK: WKUIDelegate (sin esto alert() y confirm() de la web no hacen nada)

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let alerta = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alerta.addAction(UIAlertAction(title: "Vale", style: .default) { _ in c.resume() })
            if !presenta(alerta) { c.resume() }
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            let alerta = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alerta.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in c.resume(returning: false) })
            alerta.addAction(UIAlertAction(title: "Aceptar", style: .default) { _ in c.resume(returning: true) })
            if !presenta(alerta) { c.resume(returning: false) }
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo) async -> String? {
        await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
            let alerta = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            alerta.addTextField { $0.text = defaultText }
            alerta.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in c.resume(returning: nil) })
            alerta.addAction(UIAlertAction(title: "Aceptar", style: .default) { [weak alerta] _ in
                c.resume(returning: alerta?.textFields?.first?.text ?? "")
            })
            if !presenta(alerta) { c.resume(returning: nil) }
        }
    }

    private func presenta(_ alerta: UIAlertController) -> Bool {
        var arriba = vista?.window?.rootViewController
        while let encima = arriba?.presentedViewController { arriba = encima }
        guard let arriba else { return false }
        arriba.present(alerta, animated: true)
        return true
    }

    // MARK: mensajes de la web

    fileprivate func recibe(_ mensaje: WKScriptMessage) {
        guard let datos = mensaje.body as? [String: Any], let accion = datos["accion"] as? String else { return }
        switch accion {
        case "vibra":
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case "pantalla":
            UIApplication.shared.isIdleTimerDisabled = datos["activa"] as? Bool ?? false
        case "entreno":
            if let estado = datos["estado"] as? [String: Any] { Entreno.shared.recibe(estado) }
        case "entrenoFin":
            Entreno.shared.termina()
        default:
            break
        }
    }

    private static func paginaError(_ motivo: String) -> String {
        let limpio = motivo.replacingOccurrences(of: "<", with: "&lt;")
        return """
        <!doctype html><html lang="es"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
        <style>
        body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;text-align:center;
        font:17px -apple-system,sans-serif;background:#F4F5F0;color:#2B3028;padding:24px;box-sizing:border-box}
        @media (prefers-color-scheme:dark){body{background:#171A16;color:#EEF0E8}}
        p{opacity:.7}
        </style></head><body><div><h2>Sin conexión</h2><p>\(limpio)</p><p>Tira hacia abajo para reintentar.</p></div></body></html>
        """
    }

    /// Lo que la web necesita saber de la app, inyectado antes que su propio código:
    /// navigator.standalone (calma.js decide así si está en modo app), vibrate y wakeLock (WKWebView no los tiene)
    /// y window.HoyApp para que la web sepa que va dentro de la app.
    private static let puente = #"""
    (function () {
      if (window.HoyApp) return;
      window.HoyApp = true;
      try { Object.defineProperty(navigator, "standalone", { get: function () { return true; }, configurable: true }); } catch (e) {}

      function manda(m) { try { window.webkit.messageHandlers.hoy.postMessage(m); } catch (e) {} }

      navigator.vibrate = function (patron) {
        var hay = Array.isArray(patron) ? patron.some(function (x) { return x > 0; }) : Number(patron) > 0;
        if (hay) manda({ accion: "vibra" });
        return true;
      };

      var vivos = [];
      function avisa() { manda({ accion: "pantalla", activa: vivos.length > 0 }); }
      function Cerrojo() { this.type = "screen"; this.released = false; this.onrelease = null; this._oyentes = []; }
      Cerrojo.prototype.addEventListener = function (tipo, f) {
        if (tipo === "release" && typeof f === "function") this._oyentes.push(f);
      };
      Cerrojo.prototype.removeEventListener = function (tipo, f) {
        this._oyentes = this._oyentes.filter(function (g) { return g !== f; });
      };
      Cerrojo.prototype.release = function () {
        if (this.released) return Promise.resolve();
        this.released = true;
        var yo = this;
        vivos = vivos.filter(function (c) { return c !== yo; });
        avisa();
        var ev = { type: "release", target: yo };
        this._oyentes.slice().forEach(function (f) { try { f.call(yo, ev); } catch (e) {} });
        if (typeof this.onrelease === "function") { try { this.onrelease(ev); } catch (e) {} }
        return Promise.resolve();
      };
      var wakeLock = {
        request: function (tipo) {
          if (document.hidden) return Promise.reject(new DOMException("La página no está visible", "NotAllowedError"));
          var c = new Cerrojo();
          vivos.push(c);
          avisa();
          return Promise.resolve(c);
        }
      };
      try { Object.defineProperty(navigator, "wakeLock", { value: wakeLock, configurable: true }); } catch (e) {}
      function sueltaTodo() { vivos.slice().forEach(function (c) { c.release(); }); }
      document.addEventListener("visibilitychange", function () { if (document.hidden) sueltaTodo(); });
      window.addEventListener("pagehide", sueltaTodo);
    })();
    """#
}

/// El WKUserContentController retiene a su manejador: con este intermediario el coordinador no queda atrapado.
@MainActor
private final class MensajeroDebil: NSObject, WKScriptMessageHandler {
    weak var destino: Coordinador?

    init(_ destino: Coordinador) {
        self.destino = destino
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        destino?.recibe(message)
    }
}

/// Las cookies de la web, pedidas con un URLSession efímero para no mezclarlas con las peticiones nativas.
enum Galletas {
    static func nuevas(_ claves: Claves) async -> [HTTPCookie] {
        let sesion = URLSession(configuration: .ephemeral)
        defer { sesion.finishTasksAndInvalidate() }
        var porNombre: [String: HTTPCookie] = [:]
        // con el service token, Access contesta con Set-Cookie: CF_Authorization
        if let p = try? API.peticion("/manifest.json", claves: claves) {
            for c in await pide(sesion, p) { porNombre[c.name] = c }
        }
        // y el login de la app, con la cookie todo_sesion
        if let p = try? API.peticion("/api/login", metodo: "POST", json: ["pass": claves.pass], claves: claves) {
            for c in await pide(sesion, p) { porNombre[c.name] = c }
        }
        return Array(porNombre.values)
    }

    private static func pide(_ sesion: URLSession, _ peticion: URLRequest) async -> [HTTPCookie] {
        guard let resultado = try? await sesion.data(for: peticion),
              let http = resultado.1 as? HTTPURLResponse,
              let url = http.url ?? peticion.url else { return [] }
        var cabeceras: [String: String] = [:]
        for (k, v) in http.allHeaderFields {
            if let k = k as? String, let v = v as? String { cabeceras[k] = v }
        }
        var galletas = HTTPCookie.cookies(withResponseHeaderFields: cabeceras, for: url)
        // si hubo redirecciones, las Set-Cookie intermedias solo quedan en el almacén de la sesión
        if let guardadas = sesion.configuration.httpCookieStorage?.cookies(for: url) {
            let nombres = Set(galletas.map(\.name))
            galletas += guardadas.filter { !nombres.contains($0.name) }
        }
        return galletas
    }
}
