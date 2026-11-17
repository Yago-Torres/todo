//! Lo que queda hoy, a partir de GET /api/hoy: lo usan la bandeja, los avisos y el módulo de Waybar.

use serde_json::Value;

pub struct Resumen {
    pub habitos: Vec<String>,
    /// (día, texto, hora "HH:MM" o "") de las tareas que vencen hoy o ya vencieron
    pub tareas: Vec<(String, String, String)>,
}

pub fn de(hoy: &Value) -> Resumen {
    let lista = |k: &str| hoy.get(k).and_then(Value::as_array).cloned().unwrap_or_default();
    let habitos = lista("habitos");
    // si hoy hay plan, cuenta lo planificado; si no, lo que falta (un hábito semanal no se planifica cada día)
    let hay_plan = habitos.iter().any(|h| h["plan"] == true);
    let habitos = habitos
        .iter()
        .filter(|h| h["hecho"] != true && (!hay_plan || h["plan"] == true))
        .filter_map(|h| h["n"].as_str().map(str::to_string))
        .collect();
    let tareas = lista("tareas") // si el vault falla, /api/hoy trae {"error": ...} en vez de la lista
        .iter()
        .filter(|t| t["hecha"] != true)
        .map(|t| {
            let s = |k: &str| t[k].as_str().unwrap_or("").to_string();
            (s("due"), s("t"), s("hora"))
        })
        .collect();
    Resumen { habitos, tareas }
}

impl Resumen {
    pub fn texto(&self) -> String {
        match (self.habitos.len(), self.tareas.len()) {
            (0, 0) => "Todo hecho por hoy".into(),
            (h, t) => format!("{h} hábito{} y {t} tarea{} por hoy", if h == 1 { "" } else { "s" }, if t == 1 { "" } else { "s" }),
        }
    }

    pub fn detalle(&self) -> String {
        let mut l = Vec::new();
        if !self.habitos.is_empty() {
            l.push(format!("Hábitos: {}", self.habitos.join(", ")));
        }
        for (_, t, hora) in &self.tareas {
            l.push(if hora.is_empty() { format!("☐ {t}") } else { format!("☐ {hora} {t}") });
        }
        l.join("\n")
    }
}

#[cfg(test)]
mod pruebas {
    use serde_json::json;

    #[test]
    fn cuenta_lo_planificado_y_lo_que_vence() {
        let v = json!({"habitos": [
            {"n": "Leer", "plan": true, "hecho": false},
            {"n": "Correr", "plan": true, "hecho": true},
            {"n": "Escalar", "plan": false, "hecho": false}],
          "tareas": [{"t": "Dentista", "due": "2026-11-17", "hora": "10:00"}]});
        let r = super::de(&v);
        assert_eq!(r.habitos, vec!["Leer"]);
        assert_eq!(r.tareas, vec![("2026-11-17".into(), "Dentista".into(), "10:00".into())]);
        assert_eq!(r.texto(), "1 hábito y 1 tarea por hoy");
        // sin plan, todo lo que falta; y si el vault falla, tareas trae {"error": ...}
        let r = super::de(&json!({"habitos": [{"n": "Leer", "plan": false, "hecho": false}], "tareas": {"error": "x"}}));
        assert_eq!((r.habitos.len(), r.tareas.len()), (1, 0));
        assert_eq!(super::de(&json!({})).texto(), "Todo hecho por hoy");
    }
}
