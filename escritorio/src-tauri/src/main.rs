//! todo para el escritorio (Windows y Omarchy). La ventana es la web de siempre, servida por un proxy
//! local que pone las claves (proxy.rs); encima va lo que el navegador no hace: bandeja con lo que queda
//! hoy, atajo global para apuntar, avisos del sistema a la hora de cada tarea, arranque al encender,
//! copia para cuando no hay red y el módulo de Waybar (`--waybar`).
//!
//! Argumentos: `--oculta` (arranca en la bandeja), `--apuntar` (abre la caja de apuntar; si la app ya
//! está abierta se lo dice a esa), `--notas`, `--mini` (el mini widget siempre encima), `--waybar`.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod claves;
mod proxy;
mod resumen;
mod waybar;

use std::collections::HashSet;
use std::sync::Arc;
use std::time::Duration;
use tauri::menu::{CheckMenuItem, Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Manager, RunEvent, WebviewUrl, WebviewWindowBuilder, WindowEvent};
use tauri_plugin_autostart::{MacosLauncher, ManagerExt};
use tauri_plugin_global_shortcut::{Code, GlobalShortcutExt, Modifiers, Shortcut, ShortcutState};
use tauri_plugin_notification::NotificationExt;

/// Fijo para que el origen (y con él localStorage: la cola de sinred.js, el perfil) sea el mismo cada vez.
const PUERTO: u16 = 47821;

fn estado(app: &AppHandle) -> Arc<proxy::Estado> {
    app.state::<Arc<proxy::Estado>>().inner().clone()
}

fn url(e: &proxy::Estado, ruta: &str) -> tauri::Url {
    let sep = if ruta.contains('?') { '&' } else { '?' };
    format!("http://127.0.0.1:{}{ruta}{sep}llave={}", e.puerto, e.llave).parse().expect("url local")
}

/// Enseña la ventana principal (la crea si no existe). Con `ruta`, además navega allí.
fn principal(app: &AppHandle, ruta: Option<&str>, mostrar: bool) {
    if let Some(w) = app.get_webview_window("principal") {
        if let Some(r) = ruta {
            let _ = w.eval(&format!("location.href = {}", serde_json::to_string(r).unwrap()));
        }
        if mostrar {
            let _ = w.show();
            let _ = w.unminimize();
            let _ = w.set_focus();
        }
        return;
    }
    let e = estado(app);
    let _ = WebviewWindowBuilder::new(app, "principal", WebviewUrl::External(url(&e, ruta.unwrap_or("/"))))
        .title("todo")
        .inner_size(1280.0, 820.0)
        .min_inner_size(420.0, 560.0)
        .visible(mostrar)
        // el de Tauri para soltar ficheros se queda el arrastre de WebView2 y el board no se podía arrastrar
        .disable_drag_drop_handler()
        .build();
}

/// La caja flotante de apuntar (nota, tarea o gasto). Se esconde sola al guardar o con Escape.
fn apuntar(app: &AppHandle) {
    if let Some(w) = app.get_webview_window("apuntar") {
        let _ = w.eval("window.limpia && limpia()");
        let _ = w.show();
        let _ = w.set_focus();
        return;
    }
    let e = estado(app);
    // el título es el que busca la regla de Hyprland para dejarla flotando (omarchy/instalar.sh)
    let _ = WebviewWindowBuilder::new(app, "apuntar", WebviewUrl::External(url(&e, "/_escritorio/apuntar")))
        .title("todo · apuntar")
        .inner_size(560.0, 300.0)
        .resizable(false)
        .always_on_top(true)
        .skip_taskbar(true)
        .center()
        .focused(true)
        .disable_drag_drop_handler()
        .build();
}

/// El mini widget: una ventanita siempre encima para ir apuntando notas y tareas sin que se cierre. Si estaba
/// abierto al salir, vuelve a abrirse al arrancar (la marca `mini-abierto`).
fn marca_mini() -> std::path::PathBuf {
    claves::carpeta("config").join("mini-abierto")
}

fn mini(app: &AppHandle, abrir: bool) {
    let marca = marca_mini();
    if let Some(w) = app.get_webview_window("mini") {
        let visible = w.is_visible().unwrap_or(false);
        if abrir && !visible {
            let _ = w.show();
            let _ = w.set_focus();
        } else if !abrir || visible {
            let _ = w.hide();
            let _ = std::fs::remove_file(&marca);
            return;
        }
    } else {
        let e = estado(app);
        // el título lo busca la regla de Hyprland (flotante y en todos los escritorios)
        let _ = WebviewWindowBuilder::new(app, "mini", WebviewUrl::External(url(&e, "/_escritorio/mini")))
            .title("todo · mini")
            .inner_size(320.0, 380.0)
            .min_inner_size(260.0, 200.0)
            .always_on_top(true)
            .skip_taskbar(true)
            .disable_drag_drop_handler()
            .build();
    }
    let _ = std::fs::create_dir_all(marca.parent().unwrap());
    let _ = std::fs::write(&marca, "");
}

fn bandeja(app: &AppHandle) -> tauri::Result<()> {
    let arranque = app.autolaunch().is_enabled().unwrap_or(false);
    let resumen = MenuItem::with_id(app, "resumen", "Cargando…", false, None::<&str>)?;
    let _ = MENU_RESUMEN.set(resumen.clone());
    let menu = Menu::with_items(
        app,
        &[
            &resumen,
            &PredefinedMenuItem::separator(app)?,
            &MenuItem::with_id(app, "abrir", "Abrir todo", true, None::<&str>)?,
            &MenuItem::with_id(app, "apuntar", "Apuntar…", true, None::<&str>)?,
            &MenuItem::with_id(app, "notas", "Notas rápidas", true, None::<&str>)?,
            &MenuItem::with_id(app, "mini", "Mini widget (siempre encima)", true, None::<&str>)?,
            &PredefinedMenuItem::separator(app)?,
            &CheckMenuItem::with_id(app, "arranque", "Abrir al encender", true, arranque, None::<&str>)?,
            &MenuItem::with_id(app, "claves", "Cambiar las claves…", true, None::<&str>)?,
            &PredefinedMenuItem::separator(app)?,
            &MenuItem::with_id(app, "salir", "Salir", true, None::<&str>)?,
        ],
    )?;
    #[allow(deprecated)] // show_menu_on_left_click solo existe desde tauri 2.2; este vale en todas las 2.x
    TrayIconBuilder::with_id("bandeja")
        .icon(app.default_window_icon().cloned().expect("icono"))
        .tooltip("todo")
        .menu(&menu)
        .menu_on_left_click(false)
        .on_menu_event(|app, ev| match ev.id().as_ref() {
            "abrir" => principal(app, None, true),
            "apuntar" => apuntar(app),
            "notas" => principal(app, Some("/notas.html"), true),
            "claves" => principal(app, Some("/_escritorio/configurar"), true),
            "mini" => mini(app, true),
            "arranque" => {
                let a = app.autolaunch();
                let _ = if a.is_enabled().unwrap_or(false) { a.disable() } else { a.enable() };
            }
            "salir" => app.exit(0),
            _ => {}
        })
        .on_tray_icon_event(|icono, ev| {
            // clic izquierdo (Windows): abre la ventana; el menú sale con el derecho
            if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = ev {
                principal(icono.app_handle(), None, true);
            }
        })
        .build(app)?;
    Ok(())
}

/// Cada minuto: pone al día la bandeja y avisa de las tareas de hoy con hora (⏰) cuando llega su hora.
/// Los datos se piden cada 5 minutos; la hora se mira cada minuto.
fn avisos(app: AppHandle) {
    std::thread::spawn(move || {
        let e = estado(&app);
        let mut avisadas: HashSet<String> = HashSet::new();
        let mut ultimo: Option<resumen::Resumen> = None;
        let mut vuelta = 0u32;
        loop {
            if vuelta % 5 == 0 || ultimo.is_none() {
                match e.json("/api/hoy") {
                    Ok(v) => {
                        let r = resumen::de(&v);
                        if let Some(t) = app.tray_by_id("bandeja") {
                            let _ = t.set_tooltip(Some(format!("todo · {}\n{}", r.texto(), r.detalle()).trim_end()));
                        }
                        let _ = pon_resumen(&app, &r.texto());
                        ultimo = Some(r);
                    }
                    Err(_) => {
                        let _ = pon_resumen(&app, "Sin conexión con todo");
                    }
                }
            }
            if let Some(r) = &ultimo {
                let ahora = chrono::Local::now();
                let (dia, hora) = (ahora.format("%Y-%m-%d").to_string(), ahora.format("%H:%M").to_string());
                let hace10 = (ahora - chrono::Duration::minutes(10)).format("%H:%M").to_string();
                for (due, t, h) in &r.tareas {
                    // solo las de hoy: las vencidas de otro día no tienen una hora que valga hoy
                    let clave = format!("{dia} {h} {t}");
                    if *due == dia && !h.is_empty() && *h <= hora && *h >= hace10 && avisadas.insert(clave) {
                        let _ = app.notification().builder().title(t.as_str()).body(format!("A las {h} · todo")).show();
                    }
                }
            }
            vuelta = vuelta.wrapping_add(1);
            std::thread::sleep(Duration::from_secs(60));
        }
    });
}

/// La primera línea del menú de la bandeja: «2 hábitos y 1 tarea por hoy».
fn pon_resumen(app: &AppHandle, texto: &str) -> tauri::Result<()> {
    if let Some(m) = MENU_RESUMEN.get() {
        m.set_text(texto)?;
    }
    Ok(())
}

static MENU_RESUMEN: std::sync::OnceLock<MenuItem<tauri::Wry>> = std::sync::OnceLock::new();

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let tiene = |a: &str| args.iter().any(|x| x == a);
    if tiene("--waybar") {
        return waybar::imprime();
    }
    // WebKitGTK en Wayland (Hyprland) se queda en blanco con algunas gráficas si usa DMA-BUF
    #[cfg(target_os = "linux")]
    if std::env::var_os("WEBKIT_DISABLE_DMABUF_RENDERER").is_none() {
        std::env::set_var("WEBKIT_DISABLE_DMABUF_RENDERER", "1");
    }
    let oculta = tiene("--oculta");
    let (abre_apuntar, abre_notas, tiene_mini) = (tiene("--apuntar"), tiene("--notas"), tiene("--mini"));
    let e = proxy::arranca(PUERTO).expect("no se pudo abrir el proxy local");

    let app = tauri::Builder::default()
        // tiene que ir la primera: si ya hay una abierta, le pasa los argumentos y esta se cierra
        .plugin(tauri_plugin_single_instance::init(|app, argv, _| {
            if argv.iter().any(|a| a == "--apuntar") {
                apuntar(app)
            } else if argv.iter().any(|a| a == "--mini") {
                mini(app, true)
            } else if argv.iter().any(|a| a == "--notas") {
                principal(app, Some("/notas.html?nueva=1"), true)
            } else {
                principal(app, None, true)
            }
        }))
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_autostart::init(MacosLauncher::LaunchAgent, Some(vec!["--oculta"])))
        .plugin(
            tauri_plugin_global_shortcut::Builder::new()
                .with_handler(|app, _atajo, ev| {
                    if ev.state() == ShortcutState::Pressed {
                        apuntar(app);
                    }
                })
                .build(),
        )
        .manage(e.clone())
        .setup(move |app| {
            let h = app.handle().clone();
            let _ = e.app.set(h.clone());
            principal(&h, abre_notas.then_some("/notas.html?nueva=1"), !oculta || abre_notas);
            if let Err(x) = bandeja(&h) {
                eprintln!("sin bandeja: {x}"); // en un escritorio sin bandeja la app sigue valiendo
            }
            // Ctrl+Alt+N en Windows. En Wayland no hay atajos globales para las apps: en Omarchy lo pone Hyprland
            // (bind … exec todo-escritorio --apuntar, ver omarchy/instalar.sh), así que aquí da igual que falle
            let _ = h.global_shortcut().register(Shortcut::new(Some(Modifiers::CONTROL | Modifiers::ALT), Code::KeyN));
            // la primera vez en Windows, que arranque al encender (se quita en el menú de la bandeja)
            #[cfg(windows)]
            {
                let marca = claves::carpeta("config").join("arranque-puesto");
                if !marca.exists() {
                    let _ = h.autolaunch().enable();
                    let _ = std::fs::create_dir_all(marca.parent().unwrap());
                    let _ = std::fs::write(&marca, "");
                }
            }
            if abre_apuntar {
                apuntar(&h);
            }
            if tiene_mini || marca_mini().exists() {
                mini(&h, true);
            }
            avisos(h);
            Ok(())
        })
        .on_window_event(|w, ev| {
            // cerrar no sale: se queda en la bandeja (para salir, «Salir» en el menú)
            if let WindowEvent::CloseRequested { api, .. } = ev {
                api.prevent_close();
                let _ = w.hide();
                if w.label() == "mini" {
                    let _ = std::fs::remove_file(marca_mini());
                }
            }
        })
        .build(tauri::generate_context!())
        .expect("no se pudo arrancar la app");

    app.run(|_, ev| {
        // sin ventanas a la vista sigue viva en la bandeja; app.exit(0) trae código y sí sale
        if let RunEvent::ExitRequested { api, code: None, .. } = ev {
            api.prevent_exit();
        }
    });
}
