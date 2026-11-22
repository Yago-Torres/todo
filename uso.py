"""Qué usas, qué no y cuándo: un registro ligero de uso de todas las piezas (lo pidió Yago el 20/11).

Una línea JSON por cosa hecha en `uso.jsonl` (junto a data.json, fuera del repo):
    {"t": "2026-11-20T21:04:11", "app": "todo", "que": "inversiones:explorar", "cli": "tom", "m": "POST"}

Quién escribe:
- todo (main.py, un middleware): las ACCIONES (POST/PUT/DELETE) y las páginas web que abres. Los GET de datos no,
  que la web y Tom los piden solos cada pocos segundos y no dicen nada de lo que usas.
- Tom: cada pantalla que abres (POST /api/uso), porque pinta su copia local sin pedir nada.
- el bot (todo-bot/bot.py): cada mensaje (texto, voz, foto, enlace, orden), cada botón y cada aviso que manda.
Lo automático (atajos, sincronizaciones, avisos) va con `auto: true` y no cuenta como uso tuyo.

El informe (`informe()`): por función, cuántas veces, cuántos días, la última, a qué hora sueles y desde dónde; y lo
que no has tocado en el periodo. Lo leen /uso del bot, el resumen del domingo, Ajustes → Uso y el Claude de Tom.
"""
import json
import os
import re
from collections import Counter
from datetime import date, datetime, timedelta
from pathlib import Path

USO = Path(os.getenv("TODO_USO") or Path(os.getenv("TODO_DB", Path(__file__).with_name("data.json"))).with_name("uso.jsonl"))
GUARDA_DIAS = 400

# ruta (prefijo) → función. El primer prefijo que case gana: lo más concreto, arriba.
RUTAS = [
    ("/api/inversiones/", None),   # inversiones:<lo que venga>
    ("/api/gastos", "gastos"), ("/gastos", "gastos"),
    ("/api/marca", "habitos:marcar"), ("/api/habito/aportar", "habitos:aportar"),
    ("/api/descanso", "habitos:descansos"), ("/api/vacaciones", "habitos:descansos"), ("/api/comodin", "habitos:descansos"),
    ("/api/state", "habitos:editar"), ("/index.html", "habitos"), ("/habitos.html", "habitos"), ("/claude.html", "claude"), ("/anio.html", "anio"), ("/api/anio", "anio"),
    ("/api/tarea", "pendientes"), ("/pendientes.html", "pendientes"),
    ("/api/evento", "calendario"), ("/calendario.html", "calendario"),
    ("/api/nota", "notas"), ("/notas.html", "notas"),
    ("/api/leido", "leer luego"), ("/api/leer", "leer luego"),
    ("/api/escalada", "escalada"),
    ("/api/entreno", "entreno"), ("/api/mueve", "entreno:mover"), ("/entreno.html", "entreno"),
    ("/api/sistema", "sistema"), ("/sistema.html", "sistema"),
    ("/api/actividad/fit", "carrera:fit"), ("/api/rutas", "carrera:rutas"), ("/api/segmentos", "carrera:segmentos"), ("/actividad.html", "carrera:actividad"), ("/carrera.html", "carrera"), ("/salud.html", "salud"),
    ("/api/documentos", "documentos"), ("/documentos.html", "documentos"),
    ("/api/ajustes", "ajustes"), ("/api/apariencia", "ajustes"), ("/ajustes.html", "ajustes"),
    ("/api/tom", "tom:voz"), ("/api/charla", "claude"),
    ("/inversiones.html", "inversiones"), ("/hoy.html", "hoy"), ("/", "hoy"),
]
# lo que llega solo (atajos, sincronizaciones de Tom, scripts): se apunta, pero no es uso tuyo
AUTO = ("/api/pantalla", "/api/movil/revisa", "/api/salud", "/api/push/", "/api/login", "/api/logout",
        "/api/leer/pendiente", "/api/inversiones/precios", "/api/escalada/fantasma")
# lo que hay, para decir «esto no lo has tocado»
CONOCIDAS = ["hoy", "habitos", "habitos:marcar", "habitos:editar", "habitos:descansos", "pendientes", "calendario", "notas",
             "leer luego", "entreno", "entreno:mover", "escalada", "carrera", "carrera:fit", "carrera:actividad", "carrera:gpx", "carrera:rutas", "carrera:segmentos", "bot:fit", "tom:foto", "sistema", "salud", "documentos", "gastos",
             "inversiones", "inversiones:explorar", "inversiones:pregunta", "inversiones:operacion", "inversiones:plan",
             "inversiones:alerta", "inversiones:compara", "tom:voz", "claude", "bot:texto", "bot:voz", "bot:foto",
             "bot:enlace", "bot:/gastos", "bot:/dudas", "bot:/pendientes", "bot:/carrera", "bot:/noticias", "bot:/post",
             "bot:/claude", "ajustes"]



def apunta(que, cli, auto=False, app="todo", **extra):
    """Una línea al registro. Nunca rompe a quien llama."""
    try:
        x = {"t": datetime.now().isoformat(timespec="seconds"), "app": app, "que": str(que)[:60], "cli": str(cli)[:20]}
        if auto:
            x["auto"] = True
        x.update({k: v for k, v in extra.items() if v not in (None, "")})
        with USO.open("a", encoding="utf-8") as f:
            f.write(json.dumps(x, ensure_ascii=False) + "\n")
    except Exception:
        pass


def cliente(ua, ip):
    ua = ua or ""
    if ip in ("127.0.0.1", "::1"):
        return "pi"
    if re.search(r"Shortcuts|BackgroundShortcut|WorkflowKit", ua):
        return "atajo"
    if re.search(r"reqwest|Tauri", ua, re.I):
        return "escritorio"
    if "Mozilla" in ua:
        return "web-movil" if re.search(r"iPhone|Android|Mobile", ua) else "web"
    if re.search(r"CFNetwork|Darwin|^Tom|^Hoy", ua):
        return "tom"
    return "otro"


def funcion(ruta):
    if ruta.startswith("/api/inversiones/"):
        return "inversiones:" + ruta.split("/")[3]
    if ruta.startswith("/api/actividad/") and ruta.endswith("/gpx"):
        return "carrera:gpx"
    for prefijo, nombre in RUTAS:
        if ruta == prefijo or (prefijo != "/" and ruta.startswith(prefijo)):
            return nombre
    return None


def de_peticion(metodo, ruta, ua, ip, codigo):
    """Lo que apunta el middleware de main.py. None si no es uso (un GET de datos, un error, una ruta sin nombre)."""
    if codigo >= 400 or ruta.startswith("/api/uso"):
        return None
    if metodo == "GET" and not (ruta == "/" or ruta.endswith(".html")):
        return None
    que = funcion(ruta)
    if not que:
        return None
    apunta(que, cliente(ua, ip), auto=ruta.startswith(AUTO) or cliente(ua, ip) in ("pi", "atajo"), m=metodo)
    return que


def lee(dias, hoy=None):
    hoy = hoy or date.today()
    desde = (hoy - timedelta(days=dias - 1)).isoformat()
    out = []
    try:
        with USO.open(encoding="utf-8") as f:
            for l in f:
                try:
                    x = json.loads(l)
                except ValueError:
                    continue
                if x.get("t", "") >= desde:
                    out.append(x)
    except OSError:
        pass
    return out


def franja(h):
    return "madrugada" if h < 6 else "mañana" if h < 14 else "tarde" if h < 21 else "noche"


def informe(dias=30, hoy=None):
    hoy = hoy or date.today()
    xs = lee(dias, hoy)
    tuyos = [x for x in xs if not x.get("auto") and not x["que"].startswith("aviso:")]
    por = {}
    for x in tuyos:
        p = por.setdefault(x["que"], {"que": x["que"], "n": 0, "dias": set(), "ultimo": "", "franjas": Counter(), "cli": Counter()})
        p["n"] += 1
        p["dias"].add(x["t"][:10])
        p["ultimo"] = max(p["ultimo"], x["t"])
        p["franjas"][franja(int(x["t"][11:13]))] += 1
        p["cli"][x["cli"]] += 1
    funciones = sorted(({"que": p["que"], "n": p["n"], "dias": len(p["dias"]), "ultimo": p["ultimo"][:16],
                         "franja": p["franjas"].most_common(1)[0][0], "desde": dict(p["cli"].most_common())}
                        for p in por.values()), key=lambda p: (-p["dias"], -p["n"]))
    avisos = Counter(x["que"][6:] for x in xs if x["que"].startswith("aviso:"))
    horas = Counter(int(x["t"][11:13]) for x in tuyos)
    dias_activos = len({x["t"][:10] for x in tuyos})
    primero = min((x["t"][:10] for x in xs), default=None)
    return {"dias": dias, "desde": primero, "acciones": len(tuyos), "dias_activos": dias_activos, "funciones": funciones,
            "sin_usar": [c for c in CONOCIDAS if c not in por], "clientes": dict(Counter(x["cli"] for x in tuyos).most_common()),
            "horas": [horas.get(h, 0) for h in range(24)], "avisos": dict(avisos.most_common())}


def lineas(dias=7, hoy=None):
    """Para Telegram (/uso y el domingo)."""
    r = informe(dias, hoy)
    if not r["acciones"]:
        return [f"Aún no hay uso apuntado en los últimos {dias} días (se apunta desde el 20/11)."]
    out = [f"{r['acciones']} cosas hechas en {r['dias_activos']} de {dias} días. Desde: "
           + ", ".join(f"{k} {v}" for k, v in r["clientes"].items()) + "."]
    out += [f"• {f['que']}: {f['n']} {'vez' if f['n'] == 1 else 'veces'} en {f['dias']} {'día' if f['dias'] == 1 else 'días'}, "
            f"sobre todo por la {f['franja']}" for f in r["funciones"][:8]]
    if r["desde"] and r["desde"] <= ((hoy or date.today()) - timedelta(days=dias - 1)).isoformat():
        sin = [s for s in r["sin_usar"] if ":" not in s or s.startswith("bot:/")][:10]
        if sin:
            out.append("Sin tocar: " + ", ".join(sin) + ".")
    if r["avisos"]:
        out.append("Avisos que te he mandado: " + ", ".join(f"{k} {v}" for k, v in r["avisos"].items()) + ".")
    return out


def poda():
    """Lo de hace más de GUARDA_DIAS días fuera (al arrancar todo)."""
    try:
        corte = (date.today() - timedelta(days=GUARDA_DIAS)).isoformat()
        ls = USO.read_text("utf-8").splitlines()
        quedan = [l for l in ls if l[7:17] >= corte]
        if len(quedan) < len(ls):
            tmp = USO.with_suffix(".tmp")
            tmp.write_text("\n".join(quedan) + "\n", "utf-8")
            tmp.replace(USO)
    except OSError:
        pass
