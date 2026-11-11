import SwiftUI
import WebKit

/// El puente entre la web y Local. La web pide por aquí la copia guardada de cada GET de /api, guarda las respuestas
/// buenas y deja en la cola las escrituras que no llegan al servidor. Solo contesta a la propia web (todo.yagotg.dev,
/// marco principal): son datos privados.
@MainActor
final class PuenteLocal: NSObject, WKScriptMessageHandlerWithReply {
    static let nombre = "tomLocal"
    static weak var activo: PuenteLocal?

    weak var vista: WKWebView?

    override init() {
        super.init()
        PuenteLocal.activo = self
    }

    // MARK: avisos a la web

    func red(_ hay: Bool) { ejecuta("window.__tom && window.__tom.red(\(hay ? "true" : "false"))") }

    func sincronizado(_ enviados: Int) { ejecuta("window.__tom && window.__tom.sincronizado(\(enviados))") }

    func conflicto(_ ruta: String, _ motivo: String) {
        let detalle: [String: Any] = ["ruta": ruta, "motivo": motivo]
        guard let d = try? JSONSerialization.data(withJSONObject: detalle),
              let json = String(data: d, encoding: .utf8) else { return }
        ejecuta("window.__tom && window.__tom.conflicto(\(json))")
    }

    /// Tras «Borrar datos locales»: que la web vuelva a precargar las páginas en cuanto pueda.
    func olvidaPrecarga() { ejecuta("try { localStorage.removeItem('tom-precarga'); } catch (e) {}") }

    private func ejecuta(_ js: String) {
        vista?.evaluateJavaScript(js, completionHandler: nil)
    }

    /// Plan B sin red y sin service worker que la sirva: una ruta de /api guardada (un documento de «Ver»).
    static func copiaDe(_ url: URL) -> (cuerpo: Data, mime: String)? {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.percentEncodedPath.hasPrefix("/api/") else {
            return nil
        }
        let ruta = c.percentEncodedPath + (c.percentEncodedQuery.map { "?" + $0 } ?? "")
        guard let r = Local.lee(Local.clave("GET", ruta)) else { return nil }
        let mime = (r.tipo.components(separatedBy: ";").first ?? "").trimmingCharacters(in: .whitespaces)
        return (r.cuerpo, mime.isEmpty ? "application/octet-stream" : mime)
    }

    // MARK: mensajes de la web

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.host == Config.web.host,
              let datos = message.body as? [String: Any], let op = datos["op"] as? String else { return (nil, nil) }
        switch op {
        case "estado":
            return (["red": Red.shared.hayRed, "pendientes": Local.numeroPendientes()] as [String: Any], nil)
        case "fecha":
            guard let clave = datos["clave"] as? String, let m = Local.meta(clave) else { return (nil, nil) }
            return (["fecha": m.fecha.timeIntervalSince1970 * 1000, "local": m.local] as [String: Any], nil)
        case "lee":
            // solo texto (JSON): los binarios no pasan por aquí
            guard let clave = datos["clave"] as? String, let r = Local.lee(clave),
                  let cuerpo = String(data: r.cuerpo, encoding: .utf8) else { return (nil, nil) }
            var salida: [String: Any] = ["cuerpo": cuerpo, "tipo": r.tipo, "fecha": r.fecha.timeIntervalSince1970 * 1000,
                                         "local": r.local]
            if let v = r.version { salida["version"] = v }
            return (salida, nil)
        case "guarda":
            guard let clave = datos["clave"] as? String, clave.hasPrefix("GET /api/"),
                  let cuerpo = datos["cuerpo"] as? String else { return (false, nil) }
            let fecha = (datos["fecha"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
            let ok = Local.guarda(clave, cuerpo: Data(cuerpo.utf8), tipo: (datos["tipo"] as? String) ?? "application/json",
                                  version: datos["version"] as? String, fecha: fecha,
                                  forzar: (datos["forzar"] as? Bool) ?? false)
            return (ok, nil)
        case "encola":
            return (encola(datos), nil)
        default:
            return (nil, nil)
        }
    }

    private func encola(_ datos: [String: Any]) -> [String: Any] {
        guard let metodo = (datos["metodo"] as? String)?.uppercased(), let ruta = datos["ruta"] as? String,
              ruta.hasPrefix("/api/"), let texto = datos["cuerpo"] as? String else { return ["ok": false] }
        // de las cabeceras solo lo que hace falta para mandarlo luego
        var cabeceras: [String: String] = [:]
        for (k, v) in (datos["cabeceras"] as? [String: Any]) ?? [:] {
            let nombre = k.lowercased()
            if let v = v as? String, nombre == "content-type" || nombre == "x-version" { cabeceras[nombre] = v }
        }
        let cuerpo = Data(texto.utf8)
        let soloRuta = ruta.components(separatedBy: "?").first ?? ruta
        let completo = metodo == "PUT" && Sincro.esEstadoCompleto(soloRuta)
        let claveGET = Local.clave("GET", soloRuta)
        let actual = completo ? Local.lee(claveGET) : nil
        // la base de la fusión: lo último del servidor, y en /api/state solo si es la versión de la que partió la web
        var base: Data?
        if let actual, !actual.local {
            if soloRuta == "/api/state" {
                if actual.version != nil && actual.version == cabeceras["x-version"] { base = actual.cuerpo }
            } else {
                base = actual.cuerpo
            }
        }
        guard Local.encola(metodo: metodo, ruta: ruta, cuerpo: cuerpo, cabeceras: cabeceras, base: base) else {
            return ["ok": false]
        }
        // recargar sin red enseña lo cambiado, no la copia de antes
        if completo {
            Local.guarda(claveGET, cuerpo: cuerpo, tipo: "application/json", version: cabeceras["x-version"] ?? actual?.version,
                         fecha: Date(), local: true, forzar: true)
        }
        return ["ok": true]
    }

    // MARK: el guion de la web

    /// Va al principio de cada página, antes que calma.js (que envuelve fetch encima de este) y que sinred.js.
    /// El orden queda: la página → este envoltorio → el service worker (sw.js) → la red. sw.js ya da su copia si la red
    /// tarda o falla; aquí la copia de Local manda cuando no hay red (NWPathMonitor), cuando la red falla o tarda
    /// más de 4 s, con un 5xx, o cuando la de Local es más nueva que la que dio el service worker.
    /// Las marcas de hábitos las sigue llevando sinred.js (POST /api/marca no se toca).
    static var guion: String { guionBase.replacingOccurrences(of: "__HOST__", with: Config.web.host ?? "") }

    private static let guionBase = #"""
    (function () {
      if (window.__tom || location.hostname !== "__HOST__") return;
      var canal = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.tomLocal;
      if (!canal || !window.fetch) return;
      var red = window.fetch.bind(window);
      var hayRed = navigator.onLine !== false;
      var MAX = 5 * 1024 * 1024;
      var COMPLETOS = /^\/api\/(state|gastos\/estado|gastos-aitana\/estado|comida\/estado)$/;
      // lo que se puede mandar más tarde: cuerpo JSON y una respuesta que la página no necesita de verdad
      var ENCOLABLES = [
        /^PUT \/api\/(state|gastos\/estado|gastos-aitana\/estado|comida\/estado)$/,
        /^POST \/api\/tarea(\/(hecha|edita|borra))?$/,
        /^POST \/api\/leido$/,
        /^POST \/api\/(gastos|gastos-aitana)\/(gasto|ingreso)$/,
        /^POST \/api\/documentos\/[^\/]+(\/(borra|restaura))?$/,
        /^POST \/api\/ajustes$/
      ];
      var CAIDA = [502, 503, 504, 520, 521, 522, 523, 524, 525, 526, 527, 530];
      var PAGINAS = ["/", "/habitos.html", "/pendientes.html", "/entreno.html", "/salud.html", "/carrera.html",
                     "/documentos.html", "/comida.html", "/gastos.html", "/ajustes.html"];

      function nativo(m) {
        try { return Promise.resolve(canal.postMessage(m)).catch(function () { return null; }); }
        catch (e) { return Promise.resolve(null); }
      }
      nativo({op: "estado"}).then(function (s) { if (s && typeof s.red === "boolean") hayRed = s.red; });

      // ---------- la pastilla «Sin conexión · datos de las 18:30» ----------
      var aviso = null, reloj = null;
      function pinta() {
        var p = document.getElementById("tom-sinred");
        if (!aviso) { if (p) p.remove(); return; }
        if (!document.body) return;
        if (!p) {
          p = document.createElement("div");
          p.id = "tom-sinred";
          p.setAttribute("role", "status");
          p.style.cssText = "position:fixed;left:50%;transform:translateX(-50%);top:calc(env(safe-area-inset-top, 0px) + 6px);" +
            "z-index:2147483000;pointer-events:none;max-width:calc(100% - 32px);box-sizing:border-box;white-space:nowrap;" +
            "overflow:hidden;text-overflow:ellipsis;font:600 12px/1.3 var(--fuente, -apple-system, system-ui, sans-serif);" +
            "padding:5px 12px;border-radius:999px;background:var(--aviso-suave, #FBF1DD);color:var(--aviso, #B97A0E);" +
            "border:1px solid var(--linea, rgba(0,0,0,.08));box-shadow:var(--sombra, 0 1px 2px rgba(0,0,0,.06))";
          document.body.appendChild(p);
        }
        p.textContent = aviso;
      }
      function pastilla(texto, ms) {
        aviso = texto || null;
        clearTimeout(reloj);
        if (aviso && ms) reloj = setTimeout(function () { pastilla(null); }, ms);
        pinta();
      }
      document.addEventListener("DOMContentLoaded", pinta);
      function cuando(ms) {
        var d = new Date(ms), h = d.toLocaleTimeString("es-ES", {hour: "2-digit", minute: "2-digit"});
        return d.toDateString() === new Date().toDateString() ? "de las " + h : "del " + d.getDate() + "/" + (d.getMonth() + 1) + " a las " + h;
      }

      // ---------- utilidades ----------
      function clave(metodo, u) {
        var pares = [];
        u.searchParams.forEach(function (v, k) { pares.push([k, v]); });
        pares.sort(function (a, b) {
          if (a[0] !== b[0]) return a[0] < b[0] ? -1 : 1;
          return a[1] < b[1] ? -1 : a[1] > b[1] ? 1 : 0;
        });
        var q = pares.map(function (p) { return p[0] + "=" + p[1]; }).join("&");
        return metodo + " " + u.pathname + (q ? "?" + q : "");
      }
      function fechaDe(res) {
        var d = Date.parse(res.headers.get("Date") || "");
        return isNaN(d) ? Date.now() : d;
      }
      function guarda(k, res, fecha, forzar) {
        var tipo = res.headers.get("Content-Type") || "";
        if (!/json|text|javascript|xml/.test(tipo) || +res.headers.get("Content-Length") > MAX) return;
        res.text().then(function (t) {
          if (t.length > MAX) return;
          nativo({op: "guarda", clave: k, cuerpo: t, tipo: tipo, version: res.headers.get("X-Version"), fecha: fecha, forzar: !!forzar});
        }).catch(function () {});
      }
      function desdeCopia(g) {
        var h = new Headers();
        h.set("Content-Type", g.tipo || "application/json");
        h.set("X-Tom-Offline", "1");
        h.set("X-Tom-Fecha", new Date(g.fecha).toISOString());
        if (g.version) h.set("X-Version", g.version);
        pastilla(g.local ? "Sin conexión · con cambios sin enviar" : "Sin conexión · datos " + cuando(g.fecha));
        return new Response(g.cuerpo, {status: 200, headers: h});
      }

      // ---------- lecturas ----------
      function lee(input, init, k) {
        var meta = nativo({op: "fecha", clave: k});
        function copia() { return nativo({op: "lee", clave: k}); }
        function porRed() {
          return new Promise(function (ok, mal) {
            var listo = false;
            function fin(r) { if (!listo) { listo = true; ok(r); } }
            // la red no contesta y hay copia: la copia (la respuesta, si llega, se guarda igual)
            var plazo = setTimeout(function () {
              meta.then(function (m) { return m && !listo ? copia() : null; })
                  .then(function (g) { if (g) fin(desdeCopia(g)); });
            }, 4000);
            red(input, init).then(function (res) {
              clearTimeout(plazo);
              var bueno = res.ok && res.type === "basic" && !res.redirected;
              var otra = bueno ? res.clone() : null;
              meta.then(function (m) {
                var fecha = bueno ? fechaDe(res) : 0;
                // la del service worker puede ser más vieja que la de aquí (o que lo cambiado sin red)
                if (bueno && !(m && m.fecha > fecha + 1000)) {
                  guarda(k, otra, fecha, false);
                  if (!listo) {
                    if (fecha > Date.now() - 120000) pastilla(null);
                    else if (!hayRed) pastilla("Sin conexión · datos " + cuando(fecha));
                  }
                  return fin(res);
                }
                if (m && (bueno || res.status >= 500)) {
                  return copia().then(function (g) { fin(g ? desdeCopia(g) : res); });
                }
                fin(res);
              });
            }, function (e) {
              clearTimeout(plazo);
              meta.then(function (m) { return m ? copia() : null; }).then(function (g) {
                if (listo) return;
                if (g) fin(desdeCopia(g));
                else { listo = true; mal(e); }
              });
            });
          });
        }
        if (hayRed) return porRed();
        return copia().then(function (g) { return g ? desdeCopia(g) : porRed(); });
      }

      // ---------- escrituras ----------
      function sintetica(metodo, ruta, cuerpo, h) {
        var cab = {"Content-Type": "application/json", "X-Tom-Offline": "1", "X-Tom-Encolado": "1"};
        if (metodo === "PUT") {
          // el estado tal cual, como si fuera el ya limpio, y la versión de la que partió: los siguientes PUT se juntan
          if (h["x-version"]) cab["X-Version"] = h["x-version"];
          return new Response(cuerpo, {status: 202, headers: cab});
        }
        var datos = {};
        try { datos = JSON.parse(cuerpo) || {}; } catch (e) {}
        var salida = datos, m = /^\/api\/(gastos|gastos-aitana)\/(gasto|ingreso)$/.exec(ruta);
        if (m) {
          salida = {texto: "Sin conexión: apuntado, se enviará al volver", avisos: []};
          salida[m[2]] = Object.assign({id: "sinred-" + Date.now(), dia: new Date().toLocaleDateString("sv")}, datos);
        }
        return new Response(JSON.stringify(salida), {status: 202, headers: cab});
      }
      function encola(metodo, u, cuerpo, cabeceras, motivo) {
        var h = {};
        cabeceras.forEach(function (v, k) { h[k] = v; });
        return nativo({op: "encola", metodo: metodo, ruta: u.pathname + u.search, cuerpo: cuerpo, cabeceras: h}).then(function (r) {
          if (!r || !r.ok) {
            if (motivo instanceof Response) return motivo;
            throw motivo || new TypeError("Sin conexión");
          }
          pastilla("Sin conexión · se enviará al volver", 4000);
          return sintetica(metodo, u.pathname, cuerpo, h);
        });
      }
      function trasEscribir(metodo, u, res) {
        // lo que devuelve un PUT del estado entero es el estado nuevo: vale como copia del GET
        if (metodo === "PUT" && COMPLETOS.test(u.pathname) && res.ok && res.type === "basic") guarda(clave("GET", u), res.clone(), fechaDe(res), true);
      }
      function escribe(metodo, u, input, init, cabeceras) {
        var cuerpo = init.body;
        var firma = metodo + " " + u.pathname;
        var encolable = typeof cuerpo === "string" && !cabeceras.has("x-doc") && ENCOLABLES.some(function (r) { return r.test(firma); });
        if (!encolable) return red(input, init).then(function (res) { trasEscribir(metodo, u, res); return res; });
        if (!hayRed) return encola(metodo, u, cuerpo, cabeceras, null);
        return red(input, init).then(function (res) {
          if (CAIDA.indexOf(res.status) >= 0 && !/json/.test(res.headers.get("Content-Type") || "")) return encola(metodo, u, cuerpo, cabeceras, res);
          trasEscribir(metodo, u, res);
          return res;
        }, function (e) { return encola(metodo, u, cuerpo, cabeceras, e); });
      }

      // ---------- el envoltorio ----------
      window.fetch = function (input, init) {
        var u, metodo, esPeticion = typeof Request !== "undefined" && input instanceof Request;
        try {
          u = new URL(esPeticion ? input.url : String(input), location.href);
          metodo = String((init && init.method) || (esPeticion ? input.method : "GET")).toUpperCase();
        } catch (e) { return red(input, init); }
        if (u.origin !== location.origin || u.pathname.indexOf("/api/") !== 0 || /^\/api\/(login|logout|push)(\/|$)/.test(u.pathname)) {
          return red(input, init);
        }
        if (metodo === "GET") return lee(input, init, clave("GET", u));
        if (esPeticion || !init) return red(input, init);
        var cabeceras;
        try { cabeceras = new Headers(init.headers || {}); } catch (e) { return red(input, init); }
        return escribe(metodo, u, input, init, cabeceras);
      };

      // ---------- las páginas, al service worker, para abrirlas sin red aunque no se hayan visitado ----------
      function precarga() {
        var antes = 0;
        try { antes = +localStorage.getItem("tom-precarga") || 0; } catch (e) { return; }
        if (!hayRed || Date.now() - antes < 6 * 3600 * 1000) return;
        if (!navigator.serviceWorker || !navigator.serviceWorker.controller) return;
        try { localStorage.setItem("tom-precarga", String(Date.now())); } catch (e) { return; }
        var vistos = {};
        PAGINAS.reduce(function (cadena, pagina) {
          return cadena.then(function () {
            return red(pagina, {credentials: "same-origin"}).then(function (r) {
              return r.ok && !r.redirected ? r.text() : "";
            }).then(function (html) {
              var re = /(?:src|href)="([^"]+\.(?:js|css)(?:\?[^"]*)?)"/g, m, lista = [];
              while ((m = re.exec(html))) {
                var x = new URL(m[1], location.href);
                if (vistos[x.href]) continue;
                vistos[x.href] = true;
                lista.push(red(x.href, x.origin === location.origin ? {credentials: "same-origin"} : {mode: "no-cors"}).catch(function () {}));
              }
              return Promise.all(lista);
            }).catch(function () {});
          });
        }, Promise.resolve());
      }
      window.addEventListener("load", function () { setTimeout(precarga, 5000); });

      // ---------- lo que llama la app ----------
      window.__tom = {
        red: function (si) {
          var antes = hayRed;
          hayRed = !!si;
          if (hayRed && !antes) {
            pastilla(null);
            try { window.dispatchEvent(new Event("online")); } catch (e) {}   // sinred.js manda sus marcas
          }
        },
        sincronizado: function (n) {
          pastilla(null);
          window.dispatchEvent(new CustomEvent("tom-sincronizado", {detail: {enviados: n}}));
          // como el aviso «fresco» de sw.js en calma.js: la página recarga lo suyo respetando lo que esté a medias
          var f = window.refresca || window.cargar;
          if (n > 0 && typeof f === "function") { try { f(); } catch (e) {} }
        },
        conflicto: function (d) {
          window.dispatchEvent(new CustomEvent("tom-conflicto", {detail: d}));
          pastilla("Un cambio no se ha podido guardar · agita el iPhone para verlo", 8000);
        }
      };
    })();
    """#
}

/// La sección «Sin conexión» de Configurar.
struct SeccionSinConexion: View {
    @State private var cambios: [Local.Cambio] = []
    @State private var ultima: Date?
    @State private var sincronizando = false
    @State private var borrando = false
    @State private var preguntaBorrar = false
    @State private var mensaje: String?

    private var pendientes: Int { cambios.filter { $0.estado == .pendiente }.count }

    var body: some View {
        Section {
            LabeledContent("Última sincronización",
                           value: ultima.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Nunca")
                .onAppear(perform: recarga)
            LabeledContent("Cambios pendientes", value: "\(pendientes)")
            ForEach(cambios.prefix(50)) { c in
                fila(c)
            }
            Button {
                Task { await sincroniza() }
            } label: {
                HStack {
                    Text("Sincronizar ahora")
                    if sincronizando {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(sincronizando)
            Button("Borrar datos locales", role: .destructive) { preguntaBorrar = true }
                .disabled(borrando)
                .confirmationDialog("¿Borrar los datos guardados en este iPhone?", isPresented: $preguntaBorrar,
                                    titleVisibility: .visible) {
                    Button("Borrar", role: .destructive) { Task { await borra() } }
                } message: {
                    Text("Se vuelven a bajar en cuanto haya conexión. Los cambios sin enviar no se tocan.")
                }
        } header: {
            Text("Sin conexión")
        } footer: {
            Text(mensaje ?? "Tom guarda en este iPhone (y solo aquí) una copia de tus datos para usarlos sin red. Lo que cambies sin conexión se envía al volver.")
        }
    }

    private func fila(_ c: Local.Cambio) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(c.resumen)
            Text(detalle(c))
                .font(.caption)
                .foregroundStyle(c.estado == .pendiente ? Color.secondary : Color.orange)
        }
        .swipeActions {
            Button("Descartar", role: .destructive) { descarta(c) }
            if c.estado != .pendiente {
                Button("Reintentar") { reintenta(c) }
                    .tint(.blue)
            }
        }
    }

    private func detalle(_ c: Local.Cambio) -> String {
        let cuando = c.fecha.formatted(date: .abbreviated, time: .shortened)
        switch c.estado {
        case .pendiente:
            guard c.intentos > 0 else { return cuando }
            return "\(cuando) · \(c.intentos) intentos · \(c.error ?? "")"
        case .conflicto:
            return "Conflicto: \(c.error ?? ""). Desliza para reintentar o descartar."
        case .error:
            return "Error: \(c.error ?? ""). Desliza para reintentar o descartar."
        }
    }

    private func recarga() {
        cambios = Local.cambios()
        ultima = Local.ultimaSincronizacion
    }

    private func descarta(_ c: Local.Cambio) {
        Local.descarta(c.id)
        recarga()
    }

    private func reintenta(_ c: Local.Cambio) {
        Local.reintenta(c.id)
        recarga()
        Task {
            await Sincro.vacia(forzar: true)
            recarga()
        }
    }

    private func sincroniza() async {
        sincronizando = true
        mensaje = nil
        let enviados = await Sincro.vacia(forzar: true)
        await Sincro.precarga(forzar: true)
        sincronizando = false
        recarga()
        mensaje = Red.shared.hayRed
            ? "Hecho: \(enviados) \(enviados == 1 ? "cambio enviado" : "cambios enviados") y datos al día."
            : "Sin conexión: se enviará solo al volver la red."
    }

    private func borra() async {
        borrando = true
        Local.borraRespuestas()
        // la copia del service worker (páginas y datos) también es de aquí; las cookies y sinred.js se quedan
        await WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeFetchCache, WKWebsiteDataTypeDiskCache,
                                                                WKWebsiteDataTypeMemoryCache],
                                                      modifiedSince: .distantPast)
        PuenteLocal.activo?.olvidaPrecarga()
        borrando = false
        recarga()
        mensaje = "Datos locales borrados. Se vuelven a bajar con conexión."
    }
}
