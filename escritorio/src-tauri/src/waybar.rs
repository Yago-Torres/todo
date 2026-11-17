//! `todo-escritorio --waybar`: imprime una línea JSON para un módulo `custom` de Waybar y sale.
//! No abre ventana ni proxy: lee las claves y pregunta a /api/hoy directamente.

use crate::{claves, proxy, resumen};
use serde_json::json;

pub fn imprime() {
    let salida = match claves::lee() {
        None => json!({"text": "todo", "tooltip": "Abre la app de todo para poner las claves", "class": "sin-claves"}),
        Some(c) => match proxy::pide(&proxy::agente(), &c, "GET", "/api/hoy", None, &[]) {
            Ok(r) if r.estado == 200 => match serde_json::from_slice(&r.cuerpo) {
                Ok(v) => {
                    let r = resumen::de(&v);
                    let (h, t) = (r.habitos.len(), r.tareas.len());
                    let tip = format!("{}\n{}", r.texto(), r.detalle());
                    if h + t == 0 {
                        json!({"text": "✓", "tooltip": tip.trim_end(), "class": "hecho"})
                    } else {
                        json!({"text": format!("◯ {h}  ☐ {t}"), "tooltip": tip.trim_end(), "class": "pendiente"})
                    }
                }
                Err(_) => json!({"text": "todo ?", "tooltip": "/api/hoy devuelve algo raro", "class": "error"}),
            },
            Ok(r) => json!({"text": "todo !", "tooltip": format!("El servidor contesta {}", r.estado), "class": "error"}),
            Err(_) => json!({"text": "todo ⨯", "tooltip": "Sin conexión con todo", "class": "sin-red"}),
        },
    };
    println!("{salida}");
}
