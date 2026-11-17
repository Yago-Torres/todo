//! Las tres claves de todo (las mismas que pide Tom) y dónde se guardan.
//!
//! Van al llavero del sistema: el Administrador de credenciales en Windows y el Secret Service
//! (gnome-keyring o KeePassXC) en Linux. Si el llavero no está (un Omarchy sin gnome-keyring), van a un
//! fichero que solo puede leer el usuario; `guarda()` dice cuál de los dos ha usado.

use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

const SERVICIO: &str = "dev.yagotg.todo-escritorio";
const CUENTA: &str = "claves";
pub const BASE: &str = "https://todo.yagotg.dev";

#[derive(Serialize, Deserialize, Clone)]
pub struct Claves {
    #[serde(default = "base")]
    pub base: String,
    pub id: String,
    pub secreto: String,
    pub pass: String,
}

fn base() -> String {
    BASE.to_string()
}

/// Carpeta de la app: `que` es "config" o "cache". Sin el crate `dirs`: son dos variables de entorno.
pub fn carpeta(que: &str) -> PathBuf {
    #[cfg(windows)]
    let raiz = std::env::var_os(if que == "cache" { "LOCALAPPDATA" } else { "APPDATA" }).map(PathBuf::from);
    #[cfg(not(windows))]
    let raiz = std::env::var_os(if que == "cache" { "XDG_CACHE_HOME" } else { "XDG_CONFIG_HOME" })
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(if que == "cache" { ".cache" } else { ".config" })));
    raiz.unwrap_or_else(std::env::temp_dir).join("todo-escritorio")
}

fn fichero() -> PathBuf {
    carpeta("config").join("claves.json")
}

fn entrada() -> Option<keyring::Entry> {
    keyring::Entry::new(SERVICIO, CUENTA).ok()
}

pub fn lee() -> Option<Claves> {
    if let Some(s) = entrada().and_then(|e| e.get_password().ok()) {
        if let Ok(c) = serde_json::from_str(&s) {
            return Some(c);
        }
    }
    serde_json::from_str(&fs::read_to_string(fichero()).ok()?).ok()
}

pub fn guarda(c: &Claves) -> Result<&'static str, String> {
    let s = serde_json::to_string(c).map_err(|e| e.to_string())?;
    if let Some(e) = entrada() {
        // se relee para saber que de verdad ha quedado guardado y no en un llavero de mentira
        if e.set_password(&s).is_ok() && e.get_password().ok().as_deref() == Some(s.as_str()) {
            let _ = fs::remove_file(fichero());
            return Ok("el llavero del sistema");
        }
    }
    let f = fichero();
    fs::create_dir_all(f.parent().unwrap()).map_err(|e| e.to_string())?;
    fs::write(&f, &s).map_err(|e| e.to_string())?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&f, fs::Permissions::from_mode(0o600)).map_err(|e| e.to_string())?;
    }
    Ok("un fichero que solo puede leer tu usuario")
}

pub fn borra() {
    if let Some(e) = entrada() {
        let _ = e.delete_credential();
    }
    let _ = fs::remove_file(fichero());
}
