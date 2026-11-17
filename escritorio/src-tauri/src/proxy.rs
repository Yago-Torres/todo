//! El proxy local: la ventana carga http://127.0.0.1:47821 y esto reenvía cada petición a todo.yagotg.dev
//! con las cabeceras de Cloudflare Access y el bearer de todo. Así la web no sabe que va dentro de una app
//! (pide /api/... como siempre) y nunca enseña la pantalla de contraseña.
//!
//! Tres cosas más:
//! - Solo atiende a la ventana: cada arranque estrena una llave que va en la primera URL y se queda en una
//!   cookie. Otro programa del ordenador (o una web que apunte a 127.0.0.1) se lleva un 403.
//! - Sin red: lo último que llegó de cada GET se guarda en disco y se sirve con `X-Todo-Sin-Red: 1`. Marcar
//!   hábitos sin red ya lo resuelve la web (sinred.js); aquí un POST sin red da 503 y la web lo reintenta.
//! - Las páginas propias (`/_escritorio/...`): configurar las claves y la caja de apuntar.

use crate::claves::{self, Claves};
use std::collections::hash_map::DefaultHasher;
use std::fs;
use std::hash::{Hash, Hasher};
use std::io::Read;
use std::sync::{Arc, OnceLock, RwLock};
use std::time::Duration;
use tauri::{AppHandle, Manager};
use tiny_http::{Header, Request, Response, Server};

const CONFIGURAR: &str = include_str!("../paginas/configurar.html");
const APUNTAR: &str = include_str!("../paginas/apuntar.html");
const SIN_RED: &str = "<!doctype html><meta charset=utf-8><meta name=color-scheme content='light dark'><title>Sin red</title>\
<body style='font:16px system-ui;display:grid;place-items:center;height:90vh;margin:0'><div style='text-align:center'>\
<h2>Sin conexión</h2><p>Esta página aún no estaba guardada. Vuelve a probar cuando haya red.</p>\
<button onclick='location.reload()'>Reintentar</button></div>";
const MAX_COPIA: usize = 8 * 1024 * 1024;

pub struct Estado {
    pub puerto: u16,
    pub llave: String,
    agente: ureq::Agent,
    claves: RwLock<Option<Claves>>,
    pub app: OnceLock<AppHandle>,
}

pub struct Respuesta {
    pub estado: u16,
    pub tipo: String,
    pub cuerpo: Vec<u8>,
    pub ubicacion: Option<String>,
    pub disposicion: Option<String>,
}

pub fn agente() -> ureq::Agent {
    ureq::AgentBuilder::new()
        .redirects(0) // un 302 de Access tiene que llegar aquí, no seguirse hasta la página de login
        .timeout_connect(Duration::from_secs(6))
        .timeout(Duration::from_secs(120))
        .build()
}

/// Una petición a todo con las claves. Err = no hay red (o no se llega al servidor).
pub fn pide(agente: &ureq::Agent, c: &Claves, metodo: &str, ruta: &str, tipo: Option<&str>, cuerpo: &[u8]) -> Result<Respuesta, String> {
    let mut r = agente
        .request(metodo, &format!("{}{}", c.base.trim_end_matches('/'), ruta))
        .set("CF-Access-Client-Id", &c.id)
        .set("CF-Access-Client-Secret", &c.secreto)
        .set("Authorization", &format!("Bearer {}", c.pass))
        .set("Accept", "*/*");
    if let Some(t) = tipo {
        r = r.set("Content-Type", t);
    }
    let res = if metodo == "GET" || metodo == "HEAD" { r.call() } else { r.send_bytes(cuerpo) };
    let res = match res {
        Ok(x) => x,
        Err(ureq::Error::Status(_, x)) => x,
        Err(e) => return Err(e.to_string()),
    };
    let estado = res.status();
    let tipo = res.header("Content-Type").unwrap_or("application/octet-stream").to_string();
    let ubicacion = res.header("Location").map(str::to_string);
    let disposicion = res.header("Content-Disposition").map(str::to_string);
    let mut cuerpo = Vec::new();
    res.into_reader().read_to_end(&mut cuerpo).map_err(|e| e.to_string())?;
    Ok(Respuesta { estado, tipo, cuerpo, ubicacion, disposicion })
}

/// Lo que Access contesta cuando las claves de servicio no valen: un 302 a su login o un 403.
pub fn es_access(r: &Respuesta) -> bool {
    (r.estado == 403 && !r.tipo.contains("json")) || r.ubicacion.as_deref().is_some_and(|u| u.contains("cloudflareaccess.com"))
}

impl Estado {
    pub fn claves(&self) -> Option<Claves> {
        self.claves.read().unwrap().clone()
    }

    /// GET a la API de todo y el JSON que devuelve (lo usan la bandeja y los avisos, sin pasar por la ventana).
    pub fn json(&self, ruta: &str) -> Result<serde_json::Value, String> {
        let c = self.claves().ok_or("sin claves")?;
        let r = pide(&self.agente, &c, "GET", ruta, None, &[])?;
        if r.estado != 200 {
            return Err(format!("{ruta}: {}", r.estado));
        }
        serde_json::from_slice(&r.cuerpo).map_err(|e| e.to_string())
    }
}

fn llave_nueva() -> String {
    let mut b = [0u8; 24];
    getrandom::getrandom(&mut b).expect("sin aleatoriedad del sistema");
    b.iter().map(|x| format!("{x:02x}")).collect()
}

/// Arranca el proxy en `puerto` (si está cogido, en uno libre: se pierde lo guardado en localStorage, que va por origen).
pub fn arranca(puerto: u16) -> Result<Arc<Estado>, String> {
    let server = Server::http(("127.0.0.1", puerto))
        .or_else(|_| Server::http(("127.0.0.1", 0)))
        .map_err(|e| e.to_string())?;
    let puerto = server.server_addr().to_ip().map(|a| a.port()).ok_or("sin puerto")?;
    let estado = Arc::new(Estado {
        puerto,
        llave: llave_nueva(),
        agente: agente(),
        claves: RwLock::new(claves::lee()),
        app: OnceLock::new(),
    });
    let e = estado.clone();
    std::thread::spawn(move || {
        for req in server.incoming_requests() {
            let e = e.clone();
            std::thread::spawn(move || atiende(req, &e));
        }
    });
    Ok(estado)
}

fn cabecera(nombre: &str, valor: &str) -> Option<Header> {
    Header::from_bytes(nombre.as_bytes(), valor.as_bytes()).ok()
}

fn responde(req: Request, estado: u16, tipo: &str, cuerpo: Vec<u8>, extra: &[(&str, String)]) {
    let mut r = Response::from_data(cuerpo).with_status_code(estado);
    for h in std::iter::once(("Content-Type", tipo.to_string())).chain(extra.iter().cloned()) {
        if let Some(h) = cabecera(h.0, &h.1) {
            r = r.with_header(h);
        }
    }
    let _ = req.respond(r);
}

fn json(req: Request, estado: u16, v: serde_json::Value) {
    responde(req, estado, "application/json", v.to_string().into_bytes(), &[]);
}

fn lee_cabecera(req: &Request, nombre: &str) -> Option<String> {
    req.headers().iter().find(|h| h.field.as_str().as_str().eq_ignore_ascii_case(nombre)).map(|h| h.value.as_str().to_string())
}

/// Quita `llave=...` de la URL. Devuelve la URL limpia y la llave, si venía.
fn saca_llave(url: &str) -> (String, Option<String>) {
    let Some((ruta, q)) = url.split_once('?') else { return (url.to_string(), None) };
    let mut llave = None;
    let resto: Vec<&str> = q
        .split('&')
        .filter(|p| match p.strip_prefix("llave=") {
            Some(v) => {
                llave = Some(v.to_string());
                false
            }
            None => !p.is_empty(),
        })
        .collect();
    (if resto.is_empty() { ruta.to_string() } else { format!("{ruta}?{}", resto.join("&")) }, llave)
}

fn copia(url: &str) -> std::path::PathBuf {
    let mut h = DefaultHasher::new();
    url.hash(&mut h);
    claves::carpeta("cache").join("copia").join(format!("{:016x}", h.finish()))
}

fn guarda_copia(url: &str, tipo: &str, cuerpo: &[u8]) {
    if cuerpo.len() > MAX_COPIA {
        return;
    }
    let f = copia(url);
    let _ = fs::create_dir_all(f.parent().unwrap());
    let tmp = f.with_extension("tmp");
    let mut datos = format!("{tipo}\n").into_bytes();
    datos.extend_from_slice(cuerpo);
    if fs::write(&tmp, datos).is_ok() {
        let _ = fs::rename(tmp, f);
    }
}

fn lee_copia(url: &str) -> Option<(String, Vec<u8>)> {
    let d = fs::read(copia(url)).ok()?;
    let n = d.iter().position(|&b| b == b'\n')?;
    Some((String::from_utf8_lossy(&d[..n]).into_owned(), d[n + 1..].to_vec()))
}

fn atiende(mut req: Request, e: &Estado) {
    // otra web que haga apuntar su dominio a 127.0.0.1 llega con otro Host: fuera
    if lee_cabecera(&req, "Host").as_deref() != Some(&format!("127.0.0.1:{}", e.puerto)) {
        return responde(req, 403, "text/plain", b"Solo para la app de todo".to_vec(), &[]);
    }
    let (url, llave) = saca_llave(req.url());
    if let Some(l) = llave {
        if l != e.llave {
            return responde(req, 403, "text/plain", b"Llave caducada: abre la ventana desde la app".to_vec(), &[]);
        }
        let cookie = format!("todo_escritorio={}; Path=/; HttpOnly; SameSite=Strict", e.llave);
        return responde(req, 302, "text/plain", Vec::new(), &[("Location", url), ("Set-Cookie", cookie)]);
    }
    let galleta = lee_cabecera(&req, "Cookie").unwrap_or_default();
    if !galleta.split(';').any(|c| c.trim() == format!("todo_escritorio={}", e.llave)) {
        return responde(req, 403, "text/plain", b"Solo para la app de todo".to_vec(), &[]);
    }

    let metodo = req.method().as_str().to_string();
    let ruta = url.split('?').next().unwrap_or("/").to_string();
    let mut cuerpo = Vec::new();
    if metodo != "GET" && metodo != "HEAD" {
        let _ = req.as_reader().read_to_end(&mut cuerpo);
    }

    // ---------- las páginas de la app ----------
    match (metodo.as_str(), ruta.as_str()) {
        ("GET", "/_escritorio/configurar") => return responde(req, 200, "text/html; charset=utf-8", CONFIGURAR.into(), &[]),
        ("GET", "/_escritorio/apuntar") => return responde(req, 200, "text/html; charset=utf-8", APUNTAR.into(), &[]),
        ("GET", "/_escritorio/claves") => {
            let c = e.claves();
            let base = c.as_ref().map(|c| c.base.clone()).unwrap_or_else(|| claves::BASE.into());
            return json(req, 200, serde_json::json!({"configurado": c.is_some(), "base": base}));
        }
        ("POST", "/_escritorio/claves") => return guarda_claves(req, e, &cuerpo),
        ("POST", "/_escritorio/cerrar") => {
            if let Some(w) = e.app.get().and_then(|a| a.get_webview_window("apuntar")) {
                let _ = w.hide();
            }
            return json(req, 200, serde_json::json!({"ok": true}));
        }
        _ => {}
    }

    let Some(c) = e.claves() else {
        return if ruta.starts_with("/api/") {
            json(req, 503, serde_json::json!({"detail": "Faltan las claves de la app"}))
        } else {
            responde(req, 302, "text/plain", Vec::new(), &[("Location", "/_escritorio/configurar".into())])
        };
    };

    let tipo = lee_cabecera(&req, "Content-Type");
    match pide(&e.agente, &c, &metodo, &url, tipo.as_deref(), &cuerpo) {
        Ok(r) if es_access(&r) => {
            if ruta.starts_with("/api/") {
                json(req, 502, serde_json::json!({"detail": "Cloudflare Access no acepta las claves de la app"}))
            } else {
                responde(req, 302, "text/plain", Vec::new(), &[("Location", "/_escritorio/configurar?error=access".into())])
            }
        }
        Ok(r) => {
            if metodo == "GET" && r.estado == 200 {
                guarda_copia(&url, &r.tipo, &r.cuerpo);
            }
            let mut extra = vec![("Cache-Control", "no-cache".to_string())];
            if let Some(u) = r.ubicacion {
                // un redirect del servidor a su propio dominio se queda dentro de la app
                extra.push(("Location", u.strip_prefix(c.base.trim_end_matches('/')).map(str::to_string).unwrap_or(u)));
            }
            if let Some(d) = r.disposicion {
                extra.push(("Content-Disposition", d));
            }
            responde(req, r.estado, &r.tipo, r.cuerpo, &extra)
        }
        Err(_) if metodo == "GET" => match lee_copia(&url) {
            Some((tipo, cuerpo)) => responde(req, 200, &tipo, cuerpo, &[("X-Todo-Sin-Red", "1".into()), ("Cache-Control", "no-store".into())]),
            None if ruta.starts_with("/api/") => json(req, 503, serde_json::json!({"detail": "Sin conexión"})),
            None => responde(req, 503, "text/html; charset=utf-8", SIN_RED.into(), &[]),
        },
        Err(_) => json(req, 503, serde_json::json!({"detail": "Sin conexión"})),
    }
}

fn guarda_claves(req: Request, e: &Estado, cuerpo: &[u8]) {
    let Ok(mut c) = serde_json::from_slice::<Claves>(cuerpo) else {
        return json(req, 400, serde_json::json!({"detail": "Faltan campos"}));
    };
    c.base = c.base.trim().trim_end_matches('/').to_string();
    c.id = c.id.trim().to_string();
    c.secreto = c.secreto.trim().to_string();
    if !c.base.starts_with("https://") && !c.base.starts_with("http://") {
        return json(req, 400, serde_json::json!({"detail": "La dirección tiene que empezar por https://"}));
    }
    // se prueban antes de guardarlas: mejor un error aquí que una ventana en blanco después
    let error = match pide(&e.agente, &c, "GET", "/api/notas", None, &[]) {
        Err(x) => Some(format!("No llego a {}: {x}", c.base)),
        Ok(r) if es_access(&r) => Some("Cloudflare Access no acepta el Client ID o el Client Secret".into()),
        Ok(r) if r.estado == 401 => Some("La contraseña de todo no es esa".into()),
        Ok(r) if r.estado != 200 => Some(format!("El servidor contesta {}", r.estado)),
        Ok(_) => None,
    };
    if let Some(x) = error {
        return json(req, 400, serde_json::json!({"detail": x}));
    }
    match claves::guarda(&c) {
        Ok(donde) => {
            *e.claves.write().unwrap() = Some(c);
            json(req, 200, serde_json::json!({"ok": true, "donde": donde}))
        }
        Err(x) => json(req, 500, serde_json::json!({"detail": format!("No se pudieron guardar: {x}")})),
    }
}

#[cfg(test)]
mod pruebas {
    use super::saca_llave;

    #[test]
    fn llave_fuera_de_la_url() {
        assert_eq!(saca_llave("/?llave=abc"), ("/".into(), Some("abc".into())));
        assert_eq!(saca_llave("/notas.html?nueva=1&llave=abc"), ("/notas.html?nueva=1".into(), Some("abc".into())));
        assert_eq!(saca_llave("/api/hoy"), ("/api/hoy".into(), None));
    }
}
