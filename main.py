import hashlib
import hmac
import json
import os
import re
import threading
import time
import urllib.parse
import unicodedata
import urllib.error
import urllib.request
from datetime import date, datetime, timedelta
from pathlib import Path

from fastapi import Body, Cookie, FastAPI, Header, HTTPException, Request, Response
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import FileResponse, HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles

import carrera
import vault

HERE = Path(__file__).parent
DB = Path(os.getenv("TODO_DB", HERE / "data.json"))
# Las suscripciones van en su propio fichero: clean() reconstruye el estado entero
# y cualquier PUT del cliente, que no sabe de ellas, se las llevaría por delante.
SUBS = Path(os.getenv("TODO_SUBS", HERE / "subs.json"))


def guarda(p, texto):
    """Escritura atómica: temporal + fsync + renombrar. Si se corta a mitad (luz, reinicio),
    queda el fichero de antes; nunca uno vacío o a medias."""
    tmp = p.with_name(p.name + ".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(texto)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, p)
DAY = 10  # len("2026-09-28")
EMPTY = {
    "todos": [],
    "habits": [],
    "log": {},
    "plan": {},
    "rutinas": [],
    "sesion": {},
    "peso": {},
    "actividad": {},
    "salud": {},
    "gym": {},
}

# ---------- puerta ----------
# Sin contraseña la app NO se abre sola: devuelve 503. Fallar cerrado, que esto
# está expuesto a internet y un .env que no carga no puede dejar la puerta abierta.
PASS = os.getenv("TODO_PASS") or ""
SECRET = (os.getenv("TODO_SECRET") or "").encode()
COOKIE = "todo_sesion"
VIDA = 90 * 24 * 3600  # 90 días: que no te eche de la pantalla de inicio del iPhone

app = FastAPI()


def firma(exp):
    return hmac.new(SECRET, str(exp).encode(), hashlib.sha256).hexdigest()


def vale(galleta):
    """¿Es válida la cookie de sesión? Comparación en tiempo constante."""
    exp, _, sig = str(galleta or "").partition(".")
    if not exp.isdigit() or int(exp) < time.time():
        return False
    return hmac.compare_digest(sig, firma(exp))


def exige(galleta, cabecera):
    if not PASS or not SECRET:
        raise HTTPException(503, "Falta TODO_PASS/TODO_SECRET en el entorno")
    # las máquinas (el bot de Telegram) entran por cabecera, no por cookie
    if cabecera and hmac.compare_digest(cabecera.removeprefix("Bearer ").strip(), PASS):
        return
    if not vale(galleta):
        raise HTTPException(401, "No autenticado")


# ---------- limpieza del estado ----------
def day(v):
    return s if len(s := str(v or "")) == DAY else ""


def lst(v):
    return v if isinstance(v, list) else []


def dct(v):
    return v if isinstance(v, dict) else {}


def entero(v, lo, hi, por_defecto):
    try:
        return min(hi, max(lo, int(v)))
    except (TypeError, ValueError):
        return por_defecto


def real(v, lo, hi):
    try:
        n = round(float(v), 2)
    except (TypeError, ValueError):
        return None
    return n if lo <= n <= hi else None


def dias(v, ids):
    """día -> hábitos. Se caen los hábitos borrados y los días que quedan vacíos."""
    return {
        k: marcados
        for k, lista in list(dct(v).items())[:4000]
        if len(str(k)) == DAY
        and isinstance(lista, list)
        and (marcados := sorted(ids & {str(x) for x in lista}))
    }


TIPOS = {"pesas", "carrera", "movilidad", "otro"}


def bloque(b):
    return {
        "ej": str(b.get("ej") or "").strip()[:80],
        "series": entero(b.get("series"), 1, 20, 1),
        "repes": str(b.get("repes") or "").strip()[:20],  # "8-10", "AMRAP", ""
        "kg": real(b.get("kg"), 0, 500) or 0,
        "seg": entero(b.get("seg"), 0, 3600, 0),  # pasos guiados, y tambien bloques largos de carrera
        "nota": str(b.get("nota") or "").strip()[:200],  # cómo ejecutarlo
    }


def sesion_gym(s):
    return {
        "id": str(s["id"])[:24],
        "rutina": str(s.get("rutina") or "")[:24],  # puede que ya no exista: el historial se queda igual
        "n": str(s.get("n") or "").strip()[:60],
        # empezó y última serie (ms): el reloj sobrevive a cerrar la app, y los minutos no cuentan el olvido de terminar
        "t0": entero(s.get("t0"), 0, 2**42, 0),
        "t1": entero(s.get("t1"), 0, 2**42, 0),
        "min": entero(s.get("min"), 0, 600, 0),
        "fin": bool(s.get("fin")),
        # ejercicios de la rutina que hoy no se hacen (gimnasio lleno); los añadidos van en "ej" sin más
        "quita": [q for x in lst(s.get("quita"))[:30] if (q := str(x or "").strip()[:80])],
        "ej": [
            {"ej": str(e.get("ej") or "").strip()[:80],
             # cada serie hecha: [kilos, repeticiones] (o segundos, en la plancha)
             "series": [[real(x[0], 0, 500) or 0, entero(x[1], 0, 600, 0)]
                        for x in lst(e.get("series"))[:20] if isinstance(x, list) and len(x) == 2]}
            for e in lst(s.get("ej"))[:30]
            if isinstance(e, dict) and str(e.get("ej") or "").strip()
        ],
    }


def clean(state):
    """Rebuild the state with a fixed shape: anything that reaches the DB goes through here."""
    habits = [
        {
            "id": str(h["id"])[:24],
            "n": str(h.get("n") or "").strip()[:60],
            "c": str(h.get("c") or "#111111")[:7],
            "goal": entero(h.get("goal"), 1, 7, 7),
            # cada cuántas semanas toca. 2 = quincenal (escalada), para que las
            # semanas de descanso no cuenten como meta fallida
            "cada": entero(h.get("cada"), 1, 8, 1),
        }
        for h in lst(state.get("habits"))
        if isinstance(h, dict) and h.get("id") and str(h.get("n") or "").strip()
    ][:20]
    ids = {h["id"] for h in habits}

    rutinas = [
        {
            "id": str(r["id"])[:24],
            "n": str(r.get("n") or "").strip()[:60],
            "tipo": t if (t := str(r.get("tipo") or "")[:12]) in TIPOS else "pesas",
            # qué hábito marca al completarse. "" = no marca nada
            "hab": h if (h := str(r.get("hab") or "")[:24]) in ids else "",
            "bloques": [b for x in lst(r.get("bloques"))[:30] if isinstance(x, dict) and (b := bloque(x))["ej"]],
            # segundos para colocarse entre paso y paso de una rutina guiada; solo si la hay, para que las demás
            # rutinas sigan siendo iguales a las que genera carrera.py (las compara para no reescribirlas)
            **({"pausa": p} if (p := entero(r.get("pausa"), 0, 60, 0)) else {}),
        }
        for r in lst(state.get("rutinas"))
        if isinstance(r, dict) and r.get("id") and str(r.get("n") or "").strip()
    ][:30]
    rids = {r["id"] for r in rutinas}

    return {
        "todos": [
            {
                "id": str(t["id"])[:24],
                "t": str(t.get("t") or "").strip()[:200],
                "done": bool(t.get("done")),
                "due": day(t.get("due")),  # para cuándo
                "on": day(t.get("on")),  # cuándo se hizo, así sale en el calendario
            }
            for t in lst(state.get("todos"))
            if isinstance(t, dict) and t.get("id") and str(t.get("t") or "").strip()
        ][:500],
        "habits": habits,
        "log": dias(state.get("log"), ids),  # lo hecho
        "plan": dias(state.get("plan"), ids),  # lo que toca hacer
        "rutinas": rutinas,
        # día -> {hábito: rutina}. Qué sesión concreta toca ese día.
        "sesion": {
            k: asignadas
            for k, v in list(dct(state.get("sesion")).items())[:4000]
            if len(str(k)) == DAY
            and (
                asignadas := {
                    str(h): str(r)
                    for h, r in dct(v).items()
                    if str(h) in ids and str(r) in rids
                }
            )
        },
        # día -> kilos. La media semanal es lo único que no miente.
        "peso": {
            k: n
            for k, v in list(dct(state.get("peso")).items())[:4000]
            if len(str(k)) == DAY and (n := real(v, 20, 400)) is not None
        },
        # día -> entrenos registrados (atajo de iOS, o Strava si algún día se paga).
        "actividad": {
            k: acts
            for k, v in list(dct(state.get("actividad")).items())[:2000]
            if len(str(k)) == DAY
            and (
                acts := [
                    {
                        "id": str(a.get("id"))[:20],
                        "t": str(a.get("t") or "")[:24],  # Run, WeightTraining, RockClimbing...
                        "n": str(a.get("n") or "").strip()[:60],
                        "km": real(a.get("km"), 0, 500) or 0,
                        "min": entero(a.get("min"), 0, 1440, 0),
                        # los minutos redondeados no valen para un 5k: el plan de carrera usa esto
                        "seg": entero(a.get("seg"), 0, 86400, 0),
                        "ritmo":str(a.get("ritmo") or "")[:12],  # "5:58 /km"
                        "src": str(a.get("src") or "")[:8],  # ios | strava
                    }
                    for a in lst(v)[:10]
                    if isinstance(a, dict) and a.get("id")
                ]
            )
        },
        # día -> sesiones de pesas tal como se hicieron, serie a serie (la página de Entreno)
        "gym": {
            k: ses
            for k, v in list(dct(state.get("gym")).items())[:4000]
            if len(str(k)) == DAY
            and (ses := [sesion_gym(s) for s in lst(v)[:6] if isinstance(s, dict) and s.get("id")])
        },
        # día -> {sueno: minutos de la noche que acaba ese día, pasos, fases}. Lo manda el atajo de Salud.
        "salud": {
            k: d
            for k, v in list(dct(state.get("salud")).items())[:4000]
            if len(str(k)) == DAY and (d := dia_salud(v))
        },
    }


ETAPAS = ("awake", "rem", "core", "deep")
INICIO = re.compile(r"(\d{4}-\d{2}-\d{2})[T ](\d{2}):(\d{2})")


COMPOSICION = (("grasa", 2, 70), ("magra", 20, 200), ("imc", 10, 60))


def numero(v):
    """El número de lo que manda Atajos: «70,4 kg», «22,5 %», «0,225»."""
    m = re.search(r"\d+(?:[.,]\d+)?", str(v if v is not None else ""))
    return float(m[0].replace(",", ".")) if m else None


def dia_salud(v):
    v = dct(v)
    d = {c: n for c, hi in (("sueno", 1440), ("pasos", 200000)) if (n := entero(v.get(c), 0, hi, 0))}
    # de la báscula, vía Salud: % de grasa, masa magra en kg e IMC
    d |= {c: n for c, lo, hi in COMPOSICION if (n := real(v.get(c), lo, hi)) is not None}
    # los tramos de la noche: [etapa, "AAAA-MM-DDTHH:MM", segundos], en orden
    fases = [[e, i, n] for f in lst(v.get("fases"))[:400]
             if isinstance(f, list) and len(f) == 3 and (e := str(f[0])) in ETAPAS
             and INICIO.fullmatch(i := str(f[1])[:16]) and (n := entero(f[2], 0, 86400, 0))]
    if fases:
        d["fases"] = sorted(fases, key=lambda f: f[1])
    return d


# ---------- rutas ----------
@app.post("/api/login")
def login(response: Response, request: Request, datos: dict = Body(...)):
    if not PASS or not SECRET:
        raise HTTPException(503, "Falta TODO_PASS/TODO_SECRET en el entorno")
    if not hmac.compare_digest(str(datos.get("pass") or ""), PASS):
        raise HTTPException(401, "Contraseña incorrecta")
    exp = int(time.time()) + VIDA
    # Secure sólo si de verdad vamos por https: por la LAN (http://192.168.1.70:8082)
    # el navegador tiraría la cookie y no habría forma de entrar
    https = request.headers.get("x-forwarded-proto", request.url.scheme) == "https"
    response.set_cookie(
        COOKIE, f"{exp}.{firma(exp)}",
        max_age=VIDA, httponly=True, samesite="lax", secure=https, path="/",
    )
    return {"ok": True}


@app.post("/api/logout")
def logout(response: Response):
    response.delete_cookie(COOKIE, path="/")
    return {"ok": True}


# ---------- ajustes de cada usuario (ajustes.json, junto a su data.json) ----------
# Fuera de data.json a propósito: las páginas guardan el estado entero y aquí no tienen nada que pisar.
AJUSTES = DB.with_name("ajustes.json")
MODULOS = ("habitos", "pendientes", "entreno", "salud", "comida", "gastos", "documentos")
# minutos al día por app (Ajustes los cambia): al abrirla dice cuánto queda y al pasarse avisa por Telegram
LIMITES = {"Instagram": 30, "YouTube": 45, "TikTok": 30, "Reddit": 20, "BrawlStars": 30}
MASCOTA = {"semilla": (1, 9999, 14), "grumos": (0, .5, .2), "pera": (0, 1, .35), "cola": (-24, 24, -12), "flecos": (2, 6, 4),
           "fleco": (2, 14, 10), "ancho": (20, 36, 26), "alto": (50, 90, 73), "ojoI": (2, 8, 4.5), "ojoD": (2, 8, 4.5),
           "sep": (8, 26, 14), "ojosY": (.15, .6, .38)}


def conectada(m):
    """Comida y gastos son otras apps: sin su clave en el .env, esta instancia no puede llegar a ellas."""
    return m not in OTRAS or bool(os.getenv(OTRAS[m][2]))


def limpia_ajustes(v):
    v, mods, mas = dct(v), dct(dct(v).get("modulos")), dct(dct(v).get("mascota"))
    color = str(mas.get("color") or "")
    return {"nombre": " ".join(str(v.get("nombre") or "").split())[:30],
            "modulos": {m: {c: conectada(m) and dct(mods.get(m)).get(c) is not False for c in ("activo", "barra")} for m in MODULOS},
            "mascota": {**{k: d if (n := real(mas.get(k), lo, hi)) is None else n for k, (lo, hi, d) in MASCOTA.items()},
                        "tipo": "flor" if mas.get("tipo") == "flor" else "fantasma",
                        "color": color if re.fullmatch(r"#[0-9a-fA-F]{6}", color) else "#CDE77F",
                        "extra": mas.get("extra") if mas.get("extra") in ("lazo", "gorro", "gafas") else "",
                        "rubor": mas.get("rubor") is True, "paseo": mas.get("paseo") is not False},
            # sin la clave, los de siempre; con ella aunque esté vacía (es que no quiere ninguno)
            "limites": {" ".join(str(k).split())[:30]: int(n) for k, x in list(dct(v.get("limites")).items())[:30]
                        if (n := real(x, 1, 600)) is not None} if isinstance(v.get("limites"), dict) else dict(LIMITES)}


def lee_ajustes():
    return limpia_ajustes(json.loads(AJUSTES.read_text("utf-8")) if AJUSTES.exists() else {})


@app.get("/api/ajustes")
def get_ajustes(todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    exige(todo_sesion, authorization)
    return {**lee_ajustes(), "sin_app": [m for m in MODULOS if not conectada(m)]}


@app.post("/api/ajustes")
def post_ajustes(a: dict, todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    exige(todo_sesion, authorization)
    limpio = limpia_ajustes(a)
    guarda(AJUSTES, json.dumps(limpio, ensure_ascii=False))
    return limpio


def version():
    """Cambia con cada escritura de data.json. No es ETag: Cloudflare debilita los ETag al comprimir."""
    return str(DB.stat().st_mtime_ns) if DB.exists() else "0"


@app.get("/api/state")
def get_state(response: Response, todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    exige(todo_sesion, authorization)
    response.headers["X-Version"] = version()
    return clean(dct(json.loads(DB.read_text("utf-8")))) if DB.exists() else EMPTY


@app.put("/api/state")
def put_state(state: dict, response: Response, todo_sesion: str = Cookie(None), authorization: str = Header(None),
              x_version: str = Header(None)):
    exige(todo_sesion, authorization)
    # una pestaña abierta desde antes guardaba su copia vieja encima de lo hecho en otro sitio (pasó el 28/10).
    # Sin cabecera (el bot, los scripts: leen y escriben en el acto) se guarda como siempre.
    if x_version and x_version != version():
        raise HTTPException(409, "El estado ha cambiado en otro sitio")
    state = clean(state)
    guarda(DB, json.dumps(state, ensure_ascii=False))
    response.headers["X-Version"] = version()
    return state


# ---------- marcar un hábito sin el estado entero ----------
# Dice cómo queda el hábito ese día, no «cámbialo»: una marca hecha sin red puede llegar tarde o dos
# veces sin estropear nada, y no lleva X-Version porque no pisa nada más (static/sinred.js).
@app.post("/api/marca")
def marca_habito(a: dict, response: Response, todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    exige(todo_sesion, authorization)
    dia, h = day(a.get("dia")), str(a.get("id") or "")
    if not dia:
        raise HTTPException(400, "Falta el día")
    antes = version()
    estado = clean(dct(json.loads(DB.read_text("utf-8")))) if DB.exists() else clean({})
    l = set(estado["log"].get(dia, [])) - {h}
    estado["log"][dia] = sorted(l | {h} if a.get("hecho") else l)
    estado = clean(estado)   # un hábito borrado mientras esperaba se cae aquí
    guarda(DB, json.dumps(estado, ensure_ascii=False))
    # con «antes» la página sabe si nadie más escribió entre medias y puede quedarse la versión nueva
    response.headers["X-Version"] = version()
    return {"dia": dia, "hechos": estado["log"].get(dia, []), "antes": antes, "version": version()}


# ---------- el móvil: cuánto rato en cada app ----------
# Atajos avisa al abrir y al cerrar cada app que quieres vigilar (Instagram, YouTube, TikTok...): de un aviso al
# otro es el rato dentro, porque Tiempo de uso no se puede leer desde Atajos. Va en su propio fichero, junto a
# data.json: son muchos avisos al día y no deben chocar (409) con lo que guardes en la web. Si se abre una app con
# otra aún abierta (se perdió su cierre), la otra se cierra ahí; y un rato se corta a las 2 h, por si falla un cierre.
PANTALLA = DB.with_name("pantalla.json")
MAX_RATO = 2 * 3600
PAREJA = 3   # s entre el «abre» y el «cierra» de una misma apertura (en los avisos reales, 0 o 1)
cerrojo_pantalla = threading.Lock()


def lee_pantalla():
    try:
        p = dct(json.loads(PANTALLA.read_text("utf-8")))
    except (OSError, ValueError):
        p = {}
    return {"dias": dct(p.get("dias")), "abierta": p.get("abierta") if isinstance(p.get("abierta"), dict) else None,
            "calla": p.get("calla") if isinstance(p.get("calla"), dict) else None,
            "eventos": p.get("eventos") if isinstance(p.get("eventos"), list) else []}


def apunta_pantalla(p, app_, evento, ahora):
    """abre / cierra / vuelve (la abrió y eligió no entrar). ahora: segundos, como time.time().
    Con la pregunta «¿Entrar?» en el atajo, cada apertura llega como una pareja «abre» + «cierra» en el mismo
    segundo, en cualquier orden (la pregunta tapa la app y salta su automatización de cerrar). Así que:
    - una visita solo empieza con «abre»; su pareja «cierra» (justo antes o justo después, PAREJA s) no cuenta;
    - cualquier otro «cierra» de la app abierta la cierra, aunque sea al segundo (abrir y cerrar al momento);
    - un «cierra» sin nada abierto (iOS repite el cierre al bloquear o al pasar por la multitarea) o de otra app (al
      pasar de A a B, el de A llega tarde) no es nada. Antes empezaban visitas que contaban hasta el siguiente aviso.
    Los últimos avisos quedan en p["eventos"], para ver qué ha mandado el iPhone si algo no cuadra."""
    p["eventos"] = (p.get("eventos") or [])[-199:] + [[round(ahora), app_, evento]]
    def suma(dia, app__, k, v):
        x = p["dias"].setdefault(dia, {}).setdefault(app__, {"n": 0, "s": 0, "no": 0})
        x[k] += v

    def cierra(hasta):
        ab = p["abierta"]
        suma(date.fromtimestamp(ab["desde"]).isoformat(), ab["app"], "s", round(min(max(0, hasta - ab["desde"]), MAX_RATO)))
        p["abierta"] = None

    hoy, ab, cerro = date.fromtimestamp(ahora).isoformat(), p["abierta"], p.get("cerro") or {}
    p.pop("calla", None)   # de la regla de antes
    misma = bool(ab) and ab["app"] == app_
    if evento == "vuelve":   # eligió no entrar: la visita que acababa de empezar no cuenta
        if misma and ahora - ab["desde"] < 120:
            p["abierta"] = None
            suma(date.fromtimestamp(ab["desde"]).isoformat(), app_, "n", -1)
        suma(hoy, app_, "no", 1)
    elif evento == "cierra":
        if misma and not ab.get("par") and ahora - ab["desde"] <= PAREJA:
            ab["par"] = True   # la pareja del «abre» que acaba de llegar
        elif misma:
            cierra(ahora)
        p["cerro"] = {"app": app_, "t": ahora}
    elif misma and ahora - ab["desde"] <= MAX_RATO:
        pass   # un «abre» con ella abierta: la misma visita
    else:
        if ab:
            cierra(ahora)
        par = cerro.get("app") == app_ and 0 <= ahora - cerro.get("t", 0) <= PAREJA   # su «cierra» llegó antes
        p["abierta"] = {"app": app_, "desde": cerro["t"] if par else ahora, "par": par}
        suma(hoy, app_, "n", 1)
    for d in sorted(p["dias"])[:-90]:   # tres meses bastan
        del p["dias"][d]


def resumen_pantalla(p, hoy):
    """Hoy, ayer y los últimos 7 días: segundos en total y por app (de más a menos), y la serie diaria."""
    dias = [(date.fromisoformat(hoy) - timedelta(days=i)).isoformat() for i in range(6, -1, -1)]

    def por_app(ds):
        apps = {}
        for d in ds:
            for a, x in dct(p["dias"].get(d)).items():
                y = apps.setdefault(a, {"app": a, "s": 0, "n": 0, "no": 0})
                for k in ("s", "n", "no"):
                    y[k] += x.get(k, 0)
        return sorted(apps.values(), key=lambda y: (-y["s"], -y["n"]))

    def total(ds):
        apps = por_app(ds)
        return {"s": sum(a["s"] for a in apps), "n": sum(a["n"] for a in apps), "no": sum(a["no"] for a in apps), "apps": apps}
    pasada = [(date.fromisoformat(hoy) - timedelta(days=i)).isoformat() for i in range(13, 6, -1)]
    return {"hoy": total([hoy]), "ayer": total([dias[-2]]), "semana": total(dias), "pasada": total(pasada),
            "serie": [total([d])["s"] for d in dias]}


def rato(s):
    m = round(s / 60)
    return f"{m} min" if m < 60 else f"{m // 60} h {m % 60:02d} min"


@app.post("/api/pantalla")
def pantalla(a: dict, todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    exige(todo_sesion, authorization)
    # el iPhone pone mayúscula al escribir («Abre») y a veces un espacio tras la barra: da igual
    app_, evento = " ".join(str(a.get("app") or "").split())[:30], str(a.get("evento") or "").strip().lower()
    if not app_ or evento not in ("abre", "cierra", "vuelve"):
        raise HTTPException(400, "Falta la app, o el evento no es abre, cierra o vuelve")
    hoy = date.today().isoformat()
    with cerrojo_pantalla:
        p = lee_pantalla()
        antes, antes_total = dct(dct(p["dias"].get(hoy)).get(app_)).get("s", 0), segundos_dia(p, hoy)
        apunta_pantalla(p, app_, evento, time.time())
        guarda(PANTALLA, json.dumps(p, ensure_ascii=False))
    try:   # el hábito del móvil: si hoy se acaba de pasar, se pierde y avisa; los días cerrados se marcan
        for h, lim in aplica_movil(p, hoy)["pasado"].items():
            if antes_total <= lim < segundos_dia(p, hoy):
                telegram_todo(f"📵 Hoy ya llevas {rato(segundos_dia(p, hoy))} de móvil inútil: «{h}» de hoy no sale.")
    except Exception as e:
        print("hábito del móvil:", e, flush=True)
    x = next((y for y in resumen_pantalla(p, hoy)["hoy"]["apps"] if y["app"] == app_), None)
    lim = limite(app_)
    if lim and x and antes < lim * 60 <= x["s"]:   # se acaba de pasar (al cerrar la app): una vez al día
        telegram_todo(f"⛔ Hoy ya llevas {rato(x['s'])} de {app_}: tu límite es de {lim} min.")
    return {"texto": texto_pantalla(app_, x, lim)}


# ---------- el hábito del móvil, solo ----------
# Un hábito con «móvil» y un tiempo en el nombre («> 2 horas de móvil inútil») se marca con lo que cuenta
# pantalla.json, que son las apps que vigila el atajo: hecho el día que no se pasó de ese tiempo. Hoy solo se puede
# perder (al pasarse); los días ya cerrados se marcan o desmarcan según lo que hubo, aunque se tocaran a mano. Sin
# ningún aviso del atajo ese día ni el siguiente no se toca: puede que el atajo no funcionara, y no se da por bueno.
def habitos_movil(habits):
    """id -> (nombre, segundos) de los hábitos del móvil."""
    out = {}
    for h in habits:
        n = h["n"].lower()
        m = re.search(r"(\d+(?:[.,]\d+)?)\s*(h\b|horas?|min)", n)
        if m and re.search(r"m[oó]vil", n):
            out[h["id"]] = (h["n"], float(m[1].replace(",", ".")) * (60 if m[2] == "min" else 3600))
    return out


def segundos_dia(p, d):
    return sum(x.get("s", 0) for x in dct(p["dias"].get(d)).values())


def revisa_movil(s, p, hoy, dias=8):
    """Lo que hay que cambiar en el log: [(día, id, hecho)], de hoy hacia atrás."""
    cambios = []
    for i in range(dias):
        d = (date.fromisoformat(hoy) - timedelta(days=i)).isoformat()
        ant, sig = ((date.fromisoformat(d) + timedelta(days=k)).isoformat() for k in (-1, 1))
        # medido: con avisos ese día, o sin ninguno pero con el atajo funcionando el día antes y el siguiente
        medido = d in p["dias"] or (ant in p["dias"] and sig in p["dias"])
        for hid, (_, lim) in habitos_movil(s["habits"]).items():
            if segundos_dia(p, d) > lim:
                hecho = False
            elif i == 0 or not medido:
                continue
            else:
                hecho = True
            if (hid in s["log"].get(d, [])) != hecho:
                cambios.append((d, hid, hecho))
    return cambios


cerrojo_movil = threading.Lock()


def aplica_movil(p, hoy):
    """Revisa y guarda. Devuelve los cambios y, de cada hábito del móvil, su límite en segundos."""
    with cerrojo_movil:
        if not DB.exists():
            return {"cambios": [], "pasado": {}}
        s = clean(dct(json.loads(DB.read_text("utf-8"))))
        cambios = revisa_movil(s, p, hoy)
        for d, hid, hecho in cambios:
            l = set(s["log"].get(d, [])) - {hid}
            s["log"][d] = sorted(l | {hid} if hecho else l)
        if cambios:
            guarda(DB, json.dumps(clean(s), ensure_ascii=False))
    return {"cambios": cambios, "pasado": {n: lim for n, lim in habitos_movil(s["habits"]).values()}}


@app.post("/api/movil/revisa")
def revisa_habito_movil(todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    """Para el resumen de la mañana: cierra el día de ayer aunque hoy aún no haya llegado ningún aviso del atajo."""
    exige(todo_sesion, authorization)
    p, hoy = lee_pantalla(), date.today().isoformat()
    r = aplica_movil(p, hoy)
    ayer = (date.fromisoformat(hoy) - timedelta(days=1)).isoformat()
    return {"cambios": r["cambios"], "ayer": {"s": segundos_dia(p, ayer), "medido": ayer in p["dias"] or hoy in p["dias"],
                                              "habitos": [{"n": n, "lim": lim} for n, lim in r["pasado"].items()]}}


def limite(app_):
    return {k.lower(): n for k, n in lee_ajustes()["limites"].items()}.get(app_.lower())


def texto_pantalla(app_, x, lim):
    """El aviso al abrir una app (lo enseña el atajo): cuánto lleva hoy y, si tiene límite, cuánto le queda."""
    if not x:
        return app_
    t = f"{app_} hoy: {x['n']} {'vez' if x['n'] == 1 else 'veces'}, {rato(x['s'])}"
    if not lim:
        return t
    queda = lim * 60 - x["s"]
    if queda >= 60:
        return f"{t}. Te quedan {rato(queda)} de {lim} min"
    if queda > 0:
        return f"{t}. Te queda menos de 1 min de {lim}"
    return f"⛔ {t}: " + ("has llegado a tu límite" if -queda < 60 else f"te has pasado {rato(-queda)} de tu límite") + f" ({lim} min)"


TELEGRAM_ENV = os.getenv("TODO_TELEGRAM_ENV")   # el .env del bot de Telegram (solo en la app de Yago)


def telegram_todo(texto):
    """Un aviso por el bot, en un hilo para no frenar la respuesta. Sin TODO_TELEGRAM_ENV, nada."""
    if not TELEGRAM_ENV:
        return

    def manda():
        try:
            e = {k.strip(): v.strip().strip('"') for k, v in
                 (l.split("=", 1) for l in Path(TELEGRAM_ENV).read_text().splitlines() if "=" in l)}
            req = urllib.request.Request(f"https://api.telegram.org/bot{e['TELEGRAM_TOKEN']}/sendMessage",
                                         json.dumps({"chat_id": e["TELEGRAM_USER_ID"], "text": texto}).encode(),
                                         {"Content-Type": "application/json"})
            urllib.request.urlopen(req, timeout=20).close()
        except Exception as ex:
            print("telegram:", ex, flush=True)
    threading.Thread(target=manda, daemon=True).start()


@app.get("/api/pantalla")
def get_pantalla(todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    exige(todo_sesion, authorization)
    p, hoy = lee_pantalla(), date.today().isoformat()
    r, lims = resumen_pantalla(p, hoy), lee_ajustes()["limites"]
    dias = [(date.fromisoformat(hoy) - timedelta(days=i)).isoformat() for i in range(1, 8)]   # sin hoy: está a medias
    # cuántos de los últimos 7 días se pasó de cada límite
    r["excesos"] = {a: sum(dct(dct(p["dias"].get(d)).get(a)).get("s", 0) > n * 60 for d in dias) for a, n in lims.items()}
    r["limites"] = lims
    return r


# ---------- escalada: los vídeos que se analizan ----------
# El atajo «Analizar escalada» (Compartir desde Fotos) sube aquí cada vídeo, en crudo, con lo demás en la URL: no es
# nada sensible y en Atajos es lo más fácil de montar. Va a ~/escalada/entrada/<intento>/ y lo coge escalada.service
# (~/escalada/worker.py), que lo analiza y manda el resultado por Telegram. Solo la instancia con TODO_ESCALADA.
ESCALADA = Path(os.getenv("TODO_ESCALADA") or "/no/existe")
COLORES_PRESA = {"amarillo", "naranja", "rojo", "rosa", "morado", "azul", "verde", "blanco", "negro"}
# el atajo puede ir en inglés (el iPhone lo está): se aceptan los dos
EN_INGLES = {"yellow": "amarillo", "orange": "naranja", "red": "rojo", "pink": "rosa", "purple": "morado",
             "blue": "azul", "green": "verde", "white": "blanco", "black": "negro"}
COMO_FUE = {"hecho": "hecho", "me cai": "caida", "caida": "caida", "probando": "probando",
            "sent": "hecho", "topped": "hecho", "fell": "caida", "trying": "probando", "projecting": "probando"}


def llano(s):
    return unicodedata.normalize("NFD", str(s or "").lower()).encode("ascii", "ignore").decode().strip()


@app.post("/api/escalada")
async def sube_escalada(request: Request, intento: str = "", angulo: int = 1, quien: str = "Yago", color: str = "",
                        nombre: str = "", resultado: str = "probando", nivel: str = "", todo_sesion: str = Cookie(None),
                        authorization: str = Header(None)):
    exige(todo_sesion, authorization)
    if not ESCALADA.exists():
        raise HTTPException(503, "Esta app no analiza vídeos de escalada")
    intento, color = re.sub(r"[^\w-]", "", intento)[:40], EN_INGLES.get(llano(color), llano(color))
    if len(intento) < 6:
        raise HTTPException(400, "Falta el intento: en el atajo, la fecha y hora (por ejemplo 20261105-111356)")
    if color not in COLORES_PRESA:
        raise HTTPException(400, f"«{color}» no es un color de presa: {', '.join(sorted(COLORES_PRESA))}")
    tipo = request.headers.get("content-type", "")
    ext = ".mov" if "quicktime" in tipo else ".m4v" if "m4v" in tipo else ".mp4"
    d = ESCALADA / "entrada" / intento
    d.mkdir(parents=True, exist_ok=True)
    destino, tmp, total = d / f"{max(1, min(angulo, 4))}{ext}", d / f".{angulo}.tmp", 0
    with open(tmp, "wb") as f:   # a disco según llega: un vídeo de 100 MB no pasa entero por la memoria
        async for trozo in request.stream():
            total += len(trozo)
            if total > 300 * 2**20:
                f.close()
                tmp.unlink()
                raise HTTPException(413, "Más de 300 MB: en el atajo, codifícalo a 1080p")
            f.write(trozo)
    if not total:
        tmp.unlink()
        raise HTTPException(400, "Falta el vídeo: en el atajo, el cuerpo de la petición tiene que ser el archivo")
    os.replace(tmp, destino)
    guarda(d / "intento.json", json.dumps({"intento": intento, "quien": " ".join(quien.split())[:30] or "Yago", "color": color,
                                           "nombre": " ".join(nombre.split())[:60],
                                           "resultado": COMO_FUE.get(llano(resultado), "probando"),
                                           "dificultad": dificultad(nivel)}, ensure_ascii=False))
    return {"texto": f"Recibido ({total // 2**20} MB). Te aviso por Telegram cuando esté analizado, en unos minutos."}


# ---------- escalada: la sección de la app ----------
# Lee lo que guarda escalada.service de cada intento (historial/<intento>/, archiva en ~/escalada/worker.py). Los
# fantasmas se piden aquí (fantasmas/<yo>__<otro>.pide) y los monta el servicio, que también los manda por Telegram.
ID_INTENTO = re.compile(r"\d{8}-\d{6}")
FICHEROS_ESCALADA = {"anotado": ("1-anotado-sub.mp4", "1-anotado.mp4"), "beta": ("1-beta.mp4",), "pared": ("1-pared-numerada.jpg",)}


def dificultad(v):
    """El nivel de la ruta, del 1 al 10, o None."""
    n = real(str(v or "").replace(",", "."), 1, 10)
    return None if n is None else round(n)


def dir_intento(i):
    d = ESCALADA / "historial" / i
    if not ID_INTENTO.fullmatch(i) or not (d / "intento.json").exists():
        raise HTTPException(404, "No hay ese intento")
    return d


def ficha_intento(d):
    m = json.loads((d / "intento.json").read_text("utf-8"))
    c, cifras = dct(m.get("coach")), dct((m.get("angulos") or [{}])[0].get("cifras"))
    fantasmas = {f.stem.removeprefix("fantasma-"): "listo" for f in d.glob("fantasma-*.mp4")}
    for f in (ESCALADA / "fantasmas").glob(f"{d.name}__*"):
        otro = f.stem.split("__")[1]
        if f.suffix == ".pide":
            fantasmas[otro] = "preparando"
        elif f.suffix == ".error" and otro not in fantasmas:
            fantasmas[otro] = "no se ha podido: " + f.read_text("utf-8")[:200]
    return {"intento": d.name, **{k: m.get(k) or "" for k in ("quien", "color", "nombre", "resultado")},
            "dificultad": m.get("dificultad"), "resumen": c.get("resumen") or "", "caida": c.get("caida") or "",
            **{k: [str(x) for x in c.get(k) or []] for k in ("bien", "mal", "consejos")},
            "cifras": {k: cifras.get(k) for k in ("duracion_s", "movimientos_mano", "brazo_estirado_colgado_pct", "fluidez")},
            "hay": [k for k, fs in FICHEROS_ESCALADA.items() if any((d / f).exists() for f in fs)],
            "fantasma": (d / "1-pared.jpg").exists(), "fantasmas": fantasmas}


@app.get("/api/escalada")
def lista_escalada(todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    exige(todo_sesion, authorization)
    h = ESCALADA / "historial"
    ds = sorted((d for d in h.iterdir() if (d / "intento.json").exists()), reverse=True) if h.exists() else []
    return {"activa": ESCALADA.exists(), "intentos": [ficha_intento(d) for d in ds]}


@app.get("/api/escalada/{intento}/{que}")
def fichero_escalada(intento: str, que: str, todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    """Un vídeo o la pared de un intento. FileResponse sirve por trozos (Range): Safari lo necesita para el vídeo."""
    exige(todo_sesion, authorization)
    d = dir_intento(intento)
    fs = (f"{que}.mp4",) if que.startswith("fantasma-") and ID_INTENTO.fullmatch(que[9:]) else FICHEROS_ESCALADA.get(que, ())
    f = next((d / x for x in fs if (d / x).exists()), None)
    if not f:
        raise HTTPException(404, "No está")
    return FileResponse(f)


@app.post("/api/escalada/{intento}/bloque")
def bloque_escalada(intento: str, a: dict, todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    """Cómo se llama el bloque (los intentos con el mismo nombre van juntos) y su nivel."""
    exige(todo_sesion, authorization)
    d = dir_intento(intento)
    m = json.loads((d / "intento.json").read_text("utf-8"))
    m["nombre"] = " ".join(str(a.get("nombre") or "").split())[:60]
    if "nivel" in a:
        m["dificultad"] = dificultad(a["nivel"])
    guarda(d / "intento.json", json.dumps(m, ensure_ascii=False))
    return ficha_intento(d)


@app.post("/api/escalada/fantasma")
def pide_fantasma(a: dict, todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    exige(todo_sesion, authorization)
    yo, otro = dir_intento(str(a.get("yo") or "")), dir_intento(str(a.get("otro") or ""))
    if yo == otro:
        raise HTTPException(400, "Elige otro intento")
    if not (yo / "1-pared.jpg").exists() or not (otro / "1-pared.jpg").exists():
        raise HTTPException(400, "Ese intento es de antes del fantasma: no tiene la pared guardada")
    cola = ESCALADA / "fantasmas"
    cola.mkdir(exist_ok=True)
    (cola / f"{yo.name}__{otro.name}.error").unlink(missing_ok=True)
    (cola / f"{yo.name}__{otro.name}.pide").touch()
    return ficha_intento(yo)


# ---------- documentos ----------
# DNI, pasaporte, seguros, contratos, títulos, garantías: el fichero y lo que importa de él, sobre todo hasta
# cuándo vale. Fuera de data.json (el PUT del estado entero no los toca) y del repo; la copia del pendrive se
# lleva la carpeta. Nunca se guarda el número de un documento: solo qué es, de quién y hasta cuándo vale.
DOCS = Path(os.getenv("TODO_DOCS") or DB.with_name("documentos"))
CATS_DOC = {"identidad": "Identidad", "coche": "Coche", "casa": "Casa", "trabajo": "Trabajo", "estudios": "Títulos",
            "salud": "Salud", "seguros": "Seguros", "garantias": "Garantías", "otros": "Otros"}
TIPOS_DOC = {".pdf", ".jpg", ".jpeg", ".png", ".heic", ".webp"}
AVISO_DOC = 30   # días antes de caducar: la tarea de renovarlo
cerrojo_docs = threading.Lock()


def limpia_doc(d):
    d = dct(d)
    return {"id": str(d.get("id") or "")[:24], "n": " ".join(str(d.get("n") or "").split())[:80] or "Documento",
            "cat": c if (c := str(d.get("cat") or "")) in CATS_DOC else "otros",
            "titular": " ".join(str(d.get("titular") or "").split())[:60],
            "caduca": day(d.get("caduca")), "notas": str(d.get("notas") or "").strip()[:300],
            "fichero": f if re.fullmatch(r"[\w-]+\.[a-z0-9]{2,5}", f := str(d.get("fichero") or "")) else "",
            "subido": day(d.get("subido")) or date.today().isoformat()}


def lee_docs(carpeta=None):
    try:
        l = json.loads(((carpeta or DOCS) / "indice.json").read_text("utf-8"))
    except (OSError, ValueError):
        l = []
    return [x for x in map(limpia_doc, lst(l)) if x["id"] and x["fichero"]]


def guarda_docs(l, carpeta=None):
    (carpeta or DOCS).mkdir(parents=True, exist_ok=True)
    guarda((carpeta or DOCS) / "indice.json", json.dumps(l, ensure_ascii=False))


def tarea_doc(d):
    """La tarea de renovarlo en Pendientes, AVISO_DOC días antes (hoy, si queda menos): así sale en Hoy y en el
    resumen de la mañana sin inventar otro aviso. Las garantías no se renuevan: esas no."""
    if not d["caduca"] or d["cat"] == "garantias":
        return ""
    aviso = max(date.fromisoformat(d["caduca"]) - timedelta(days=AVISO_DOC), date.today()).isoformat()
    try:
        vault.nueva_tarea(f"Renovar {d['n']} (caduca el {d['caduca'][8:]}/{d['caduca'][5:7]}/{d['caduca'][:4]})", aviso)
    except Exception as e:   # sin vault el documento se guarda igual
        print("documentos: sin tarea:", e, flush=True)
        return ""
    return aviso


def doc_de(i):
    x = next((d for d in lee_docs() if d["id"] == i), None)
    if not x:
        raise HTTPException(404, "No existe ese documento")
    return x


@app.get("/api/documentos")
def documentos(todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    exige(todo_sesion, authorization)
    return {"docs": lee_docs(), "cats": CATS_DOC}


@app.post("/api/documentos")
async def sube_documento(request: Request, x_doc: str = Header(""), todo_sesion: str = Cookie(None),
                         authorization: str = Header(None)):
    """El fichero va tal cual en el cuerpo y lo demás en la cabecera X-Doc (JSON con encodeURIComponent):
    sin formularios multipart, y sin que el nombre del titular acabe en la URL ni en los registros."""
    exige(todo_sesion, authorization)
    try:
        meta = dct(json.loads(urllib.parse.unquote(x_doc) or "{}"))
    except ValueError:
        raise HTTPException(400, "X-Doc no es JSON")
    datos = await request.body()
    if not datos:
        raise HTTPException(400, "Falta el fichero")
    if len(datos) > 25 * 2**20:
        raise HTTPException(413, "Más de 25 MB: mándalo en PDF o una foto más pequeña")
    ext = Path(str(meta.get("nombre") or "")).suffix.lower() or ".jpg"
    if ext not in TIPOS_DOC:
        raise HTTPException(400, f"«{ext}» no: PDF o foto (jpg, png, heic, webp)")
    i = f"d{time.time_ns() % 10**10}"
    d = limpia_doc({**meta, "id": i, "fichero": i + ext, "n": meta.get("n") or Path(str(meta.get("nombre") or "")).stem})
    with cerrojo_docs:
        DOCS.mkdir(parents=True, exist_ok=True)
        tmp = DOCS / (d["fichero"] + ".tmp")
        tmp.write_bytes(datos)
        os.replace(tmp, DOCS / d["fichero"])
        guarda_docs(lee_docs() + [d])
    return {**d, "aviso": tarea_doc(d)}


@app.post("/api/documentos/{i}")
def edita_documento(i: str, cambios: dict, todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    exige(todo_sesion, authorization)
    with cerrojo_docs:
        l, x = lee_docs(), doc_de(i)
        nuevo = limpia_doc({**x, **{k: cambios[k] for k in ("n", "cat", "titular", "caduca", "notas") if k in cambios}})
        guarda_docs([nuevo if d["id"] == i else d for d in l])
    # ponytail: cambiar la fecha apunta otra tarea y la vieja se queda en Pendientes; borrarla a mano
    return {**nuevo, "aviso": tarea_doc(nuevo) if nuevo["caduca"] != x["caduca"] else ""}


@app.post("/api/documentos/{i}/borra")
def borra_documento(i: str, todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    """A la papelera (documentos/papelera), no fuera: el «Deshacer» lo devuelve."""
    exige(todo_sesion, authorization)
    with cerrojo_docs:
        x, papelera = doc_de(i), DOCS / "papelera"
        papelera.mkdir(exist_ok=True)
        if (DOCS / x["fichero"]).exists():
            os.replace(DOCS / x["fichero"], papelera / x["fichero"])
        guarda_docs(lee_docs(papelera) + [x], papelera)
        guarda_docs([d for d in lee_docs() if d["id"] != i])
    return {"ok": True}


@app.post("/api/documentos/{i}/restaura")
def restaura_documento(i: str, todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    exige(todo_sesion, authorization)
    with cerrojo_docs:
        papelera = DOCS / "papelera"
        x = next((d for d in lee_docs(papelera) if d["id"] == i), None)
        if not x:
            raise HTTPException(404, "No está en la papelera")
        if (papelera / x["fichero"]).exists():
            os.replace(papelera / x["fichero"], DOCS / x["fichero"])
        guarda_docs([d for d in lee_docs(papelera) if d["id"] != i], papelera)
        guarda_docs(lee_docs() + [x])
    return x


@app.get("/api/documentos/{i}/fichero")
def fichero_documento(i: str, todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    exige(todo_sesion, authorization)
    x = doc_de(i)
    return FileResponse(DOCS / x["fichero"], filename=x["n"] + Path(x["fichero"]).suffix, content_disposition_type="inline",
                        headers={"Cache-Control": "private, no-store"})


# ---------- registrar un entreno de una sola llamada ----------
# Un atajo de iOS no puede hacer el leer-modificar-escribir del PUT entero, así
# que esto hace todo el trabajo y devuelve ya el texto de la notificación.
DEPORTE = (
    ("correr", carrera.CORRE),
    ("gimnasio", ("strength", "gym", "weight", "pesas", "gimnasio", "funcional", "crossfit")),
    ("escalar", ("climb", "escalad", "escalar", "boulder")),
)


def que_habito(pista, habitos):
    p = str(pista or "").lower()
    for h in habitos:
        if h["id"] == p:  # por si algún día se manda el id directo
            return h
    for clave, palabras in DEPORTE:
        if any(w in p for w in palabras):
            return next((h for h in habitos if h["n"].lower().startswith(clave)), None)
    return None


@app.post("/api/entreno")
def registra_entreno(a: dict, todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    exige(todo_sesion, authorization)
    estado = clean(dct(json.loads(DB.read_text("utf-8")))) if DB.exists() else clean({})
    h = que_habito(a.get("tipo"), estado["habits"])
    if not h:
        # el mensaje se lee en la notificación del móvil: que diga qué hacer
        if not str(a.get("tipo") or "").strip():
            raise HTTPException(400, "El campo «tipo» llega vacío: en el atajo, el valor de "
                                     "«tipo» tiene que ser la variable Elemento elegido")
        raise HTTPException(400, f"«{a.get('tipo')}» no es correr, gimnasio ni escalar")

    dia = day(a.get("dia")) or date.today().isoformat()
    # Atajos de iOS manda las unidades de Salud y no siempre en lo que esperas,
    # así que se deducen por magnitud en vez de guardar un disparate en silencio.
    km = real(a.get("km"), 0, 100000) or 0
    if km > 500:  # nadie corre 500 km: son metros
        km = round(km / 1000, 2)
    crudo = real(a.get("min"), 0, 86400) or 0   # "23,5" min también vale
    seg = entero(a.get("seg"), 0, 86400, 0) or round(crudo if crudo > 600 else crudo * 60)  # >600 "min" son segundos
    mins = round(seg / 60)
    ritmo = ""
    if km >= 0.4 and seg:
        s = seg / km
        ritmo = f"{int(s // 60)}:{int(s % 60):02d} /km"

    acto = {
        "id": str(a.get("id") or f"{dia}-{h['id']}-{mins}")[:20],
        "t": str(a.get("tipo") or "")[:24], "n": str(a.get("n") or "").strip()[:60],
        "km": km, "min": mins, "seg": seg, "ritmo": ritmo, "src": str(a.get("src") or "ios")[:8],
    }
    # mismo id dos veces = el atajo se disparó repetido: se reemplaza, no se duplica
    estado["actividad"][dia] = [x for x in estado["actividad"].get(dia, [])
                                if x["id"] != acto["id"]] + [acto]
    if h["id"] not in estado["log"].get(dia, []):
        estado["log"][dia] = sorted(set(estado["log"].get(dia, []) + [h["id"]]))

    estado = clean(estado)
    guarda(DB, json.dumps(estado, ensure_ascii=False))
    trozos = [h["n"]] + [t for t in (f"{km:g} km" if km else "", f"{mins} min" if mins else "", ritmo) if t]
    if h["id"] == carrera.habito_correr(estado) and km and seg:
        # lo que se lee en la notificación al acabar de correr: cómo queda tu 5k
        trozos.append(f"5k estimado {carrera.mmss(carrera.informe(estado)['estimacion']['seg'])}")
    return {"texto": "Apuntado · " + " · ".join(trozos), "habito": h["id"], "dia": dia}


# ---------- sueño y pasos (atajo de Salud cada mañana) ----------
# Lo que llama Salud a cada fase, en inglés o en español. «En la cama» no es una fase: se ignora.
NOMBRES = (("awake", ("awake", "despierto")), ("rem", ("rem",)), ("deep", ("deep", "profundo")),
           ("core", ("core", "nucleo", "basico", "light", "ligero", "asleep", "dormido")))


def etapa(nombre):
    t = unicodedata.normalize("NFD", str(nombre).lower()).encode("ascii", "ignore").decode()
    if "bed" in t or "cama" in t:
        return None
    return next((e for e, palabras in NOMBRES if any(p in t for p in palabras)), None)


# la fecha como la escribe Atajos en español: «28.10.26, 00:43» o «28/10/2026 0:43» (día primero)
FECHA_ES = re.compile(r"(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})\D+(\d{1,2}):(\d{2})")


def inicio(texto):
    if m := INICIO.search(texto):
        return f"{m[1]}T{m[2]}:{m[3]}"
    if m := FECHA_ES.search(texto):
        anio = m[3] if len(m[3]) == 4 else "20" + m[3]
        return f"{anio}-{int(m[2]):02d}-{int(m[1]):02d}T{int(m[4]):02d}:{m[5]}"
    return None


def lee_fases(v):
    """El atajo manda un tramo por línea (o separados por ;): «Deep|28.10.26, 00:46|1380».
    La duración va en segundos (en minutos se pierde uno por tramo); si la noche entera suma menos
    de 1440, eran minutos. Devuelve [[etapa, "AAAA-MM-DDTHH:MM", segundos]] en orden; lo ilegible, fuera."""
    trozos = v if isinstance(v, list) else re.split(r"[;\n]", str(v or ""))
    out = []
    for x in trozos[:400]:
        partes = str(x).split("|")
        if len(partes) == 3 and (e := etapa(partes[0])) and (i := inicio(partes[1])) \
                and (n := real(partes[2].strip().replace(",", "."), 0, 86400)) is not None:
            out.append([e, i, n])
    if sum(n for _, _, n in out) < 1440:
        out = [[e, i, n * 60] for e, i, n in out]
    return sorted([[e, i, round(n)] for e, i, n in out if n], key=lambda f: f[1])


def noches(fases):
    """Parte los tramos en noches: más de 3 horas sin ningún tramo es otra noche."""
    out = []
    for f in fases:
        if not out or datetime.fromisoformat(f[1]) - fin_noche(out[-1]) > timedelta(hours=3):
            out.append([])
        out[-1].append(f)
    return out


def fin_noche(tramos):
    return max(datetime.fromisoformat(i) + timedelta(seconds=n) for _, i, n in tramos)


def lee_pasos(v, ayer):
    """Un número son los de ayer (el atajo de antes). Un día por línea, «29.10.26, 00:00|9078», va cada uno
    a su día y da igual cuándo corra el atajo; varias líneas del mismo día se suman."""
    if "|" not in str(v):
        n = round(real(v, 0, 200000) or 0)
        return {ayer: n} if n else {}
    out = {}
    for x in (v if isinstance(v, list) else re.split(r"[;\n]", str(v)))[:40]:
        partes = str(x).split("|")
        if len(partes) != 2:
            continue
        dia = day((inicio(partes[0] + " 0:00") or "")[:10])   # la hora da igual, y puede no venir
        n = real(re.sub(r"[.,\s](?=\d{3}(?!\d))", "", partes[1].strip()).replace(",", "."), 0, 200000)
        if dia and n:
            out[dia] = out.get(dia, 0) + round(n)
    return out


def lee_pesos(v, hoy):
    """Un número es el peso de hoy. Un peso por línea, «03.11.26, 07:55|81,2», va a su día (el último de ese
    día): la báscula pasa el peso a Salud cuando se abre su app, a veces días después de pesarte."""
    if "|" not in str(v):
        p = real(numero(v), 20, 400)
        return {hoy: round(p, 1)} if p else {}
    out = {}
    for x in (v if isinstance(v, list) else re.split(r"[;\n]", str(v)))[:60]:
        partes = str(x).split("|")
        if len(partes) == 2 and (dia := day((inicio(partes[0] + " 0:00") or "")[:10])) and (p := real(numero(partes[1]), 20, 400)):
            out[dia] = round(p, 1)
    return out


def desde_mediodia(inicio):
    """Minutos desde el mediodía anterior: las 23:30 y las 00:30 quedan seguidas."""
    return (int(inicio[11:13]) * 60 + int(inicio[14:16]) - 720) % 1440


def nota(fases, camas):
    """Puntuación 0-100 con la misma receta que Salud: duración 50, hora de acostarse 30, interrupciones 20.
    camas: hora de acostarse (desde_mediodia) de las noches anteriores, para la regularidad."""
    dormido = sum(n for e, _, n in fases if e != "awake") / 60
    despierto = sum(n for e, _, n in fases if e == "awake") / 60
    cama = desde_mediodia(next(i for e, i, _ in fases if e != "awake"))
    duracion = round(50 * min(1, dormido / 480))
    media = sum(camas) / len(camas) if camas else cama
    hora = round(30 * max(0, min(1, (120 - abs(cama - media)) / 90)))   # media hora de margen, a las 2 h ya 0
    # ponytail: calibrado con una noche (26 min despierto = 13/20 en Salud); afinar si se separa de Salud
    interrupciones = round(20 * max(0, 1 - despierto / 75))
    return {"total": duracion + hora + interrupciones, "duracion": duracion, "hora": hora, "interrupciones": interrupciones}


def informe_sueno(s, hoy, n=30):
    """Las últimas n noches (con los pasos de cada día) y los tramos de la última noche con fases."""
    camas, filas = [], {}
    for dia in sorted(d for d in s["salud"] if d <= hoy.isoformat()):
        x = s["salud"][dia]
        fila = {"dia": dia, "sueno": x.get("sueno"), "pasos": x.get("pasos"), "fases": None, "nota": None}
        fs = x.get("fases", [])
        if dormidas := [f for f in fs if f[0] != "awake"]:
            # lo despierto antes de dormirte y después de levantarte no es una interrupción
            fs = fs[fs.index(dormidas[0]):len(fs) - fs[::-1].index(dormidas[-1])]
            fin = datetime.fromisoformat(dormidas[-1][1]) + timedelta(seconds=dormidas[-1][2])
            fila.update(fases={e: round(sum(n for ee, _, n in fs if ee == e) / 60) for e in ETAPAS},
                        acostarse=dormidas[0][1][11:], levantarse=f"{fin:%H:%M}", nota=nota(fs, camas[-14:]),
                        tramos=[[e, i, round(n / 60, 1)] for e, i, n in fs])   # la página, en minutos
            camas.append(desde_mediodia(dormidas[0][1]))
        filas[dia] = fila
    dias = [(hoy - timedelta(days=i)).isoformat() for i in range(n - 1, -1, -1)]
    noches = [filas.get(d, {"dia": d, "sueno": None, "pasos": None, "fases": None, "nota": None}) for d in dias]
    ultima = next((f for f in reversed(noches) if f["fases"]), None)
    return {"noches": [{k: v for k, v in f.items() if k != "tramos"} for f in noches],
            "anoche": ultima and {k: ultima[k] for k in ("dia", "nota", "acostarse", "levantarse", "sueno", "tramos")}}


@app.get("/api/sueno")
def sueno(todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    exige(todo_sesion, authorization)
    s = clean(dct(json.loads(DB.read_text("utf-8")))) if DB.exists() else clean({})
    return {**informe_sueno(s, date.today()), "cuerpo": cuerpo(s, date.today())}


def cuerpo(s, hoy, n=120):
    desde = (hoy - timedelta(days=n - 1)).isoformat()
    return {"peso": [[d, kg] for d, kg in sorted(s["peso"].items()) if desde <= d <= hoy.isoformat()],
            "comp": [[d, *(x.get(c) for c, _, _ in COMPOSICION)] for d, x in sorted(s["salud"].items())
                     if desde <= d <= hoy.isoformat() and any(c in x for c, _, _ in COMPOSICION)]}


@app.post("/api/salud")
def registra_salud(a: dict, todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    """{"fases": los tramos de sueño, "pasos": por día o los de ayer, "peso": kilos de hoy}, cualquiera de ellos.
    Cada noche va al día en que acabó, por sus fechas y no por cuándo corra el atajo; el peso, a hoy (o a "dia"),
    o cada uno a su día si llegan como «fecha|kilos» por línea (ver lee_pesos)."""
    exige(todo_sesion, authorization)
    # lo que manda el atajo, tal cual (journalctl -u todo): para afinarlo sin adivinar
    print("salud recibido:", json.dumps({k: str(a.get(k))[:200] for k in ("sueno", "pasos", "fases", "peso", "grasa", "magra", "imc", "dia") if k in a},
                                        ensure_ascii=False), flush=True)
    estado = clean(dct(json.loads(DB.read_text("utf-8")))) if DB.exists() else clean({})
    hoy = day(a.get("dia")) or date.today().isoformat()
    ayer = (date.fromisoformat(hoy) - timedelta(days=1)).isoformat()
    trozos = []
    # con los tramos, lo dormido sale de ellos (sin lo despierto) y cada noche va al día en que acabó; si
    # no, del total que mande, a hoy. [(día, minutos, tramos)]
    if fases := lee_fases(a.get("fases")):
        camas = [(f"{fin_noche(n):%Y-%m-%d}", round(sum(s for e, _, s in n if e != "awake") / 60), n) for n in noches(fases)]
    elif crudo := real(a.get("sueno"), 0, 10 ** 6):
        # como en los entrenos: Salud suma en horas, minutos o segundos según el atajo; por magnitud
        camas = [(hoy, round(crudo * 60 if crudo <= 24 else crudo if crudo <= 1440 else crudo / 60), [])]
    else:
        camas = []
    camas = [c for c in camas if c[1]]
    if camas and (mas := max(c[1] for c in camas)) > 16 * 60:
        raise HTTPException(400, f"{mas // 60} h de sueño: Salud está sumando dos fuentes (iPhone y COROS) o el "
                                 "tiempo en la cama. En el atajo, una sola fuente y «Value is not In Bed»")
    for dia, m, tramos in camas:
        noche = estado["salud"].setdefault(dia, {})
        if not tramos or m >= noche.get("sueno", 0):   # el filtro del atajo puede cortar una noche: no pisa a la entera
            noche["sueno"] = m
            if tramos:
                noche["fases"] = tramos
    mins = camas[-1][1] if camas else 0
    if mins:
        trozos.append(f"dormido {mins // 60} h {mins % 60:02d}" + (f" en {len(camas[-1][2])} tramos" if camas[-1][2] else "")
                      + (f" ({len(camas)} noches)" if len(camas) > 1 else ""))
    # la báscula: Salud lo da en kg con coma decimal y a veces con la unidad («70,4 kg»)
    pesos = lee_pesos(a.get("peso"), hoy)
    estado["peso"].update(pesos)
    peso = bool(pesos)
    if pesos:
        u = max(pesos)
        trozos.append(f"{pesos[u]:.1f} kg".replace(".", ",") + ("" if u == hoy else f" del {int(u[8:])}/{int(u[5:7])}")
                      + (f" (y {len(pesos) - 1} día{'s' if len(pesos) > 2 else ''} más)" if len(pesos) > 1 else ""))
    comp = {}
    for c, lo, hi in COMPOSICION:
        n = numero(a.get(c))
        if c == "grasa" and n is not None and n <= 1:   # Salud la da a veces como fracción (0,225)
            n *= 100
        if (n := real(n, lo, hi)) is not None:
            comp[c] = round(n, 1)
    if comp:
        estado["salud"].setdefault(hoy, {}).update(comp)
        trozos += [f"{comp[c]:g}{u}".replace(".", ",") for c, u in (("grasa", " % grasa"), ("magra", " kg magra"), ("imc", " IMC")) if c in comp]
    if not mins:
        # que la notificación diga qué ha llegado: es la única pista para arreglar el atajo
        raro = a.get("fases") or a.get("sueno")
        if raro or not (peso or comp):
            trozos.append(f"sueño sin entender: «{str(raro)[:60]}»" if raro else "sin datos de sueño")
    pasos = lee_pasos(a.get("pasos"), ayer)
    for i, (d, n) in enumerate(sorted(pasos.items())):
        x = estado["salud"].setdefault(d, {})
        # el día más viejo de una tanda puede venir cortado por el filtro del atajo
        x["pasos"] = max(n, x.get("pasos", 0)) if i == 0 and len(pasos) > 1 else n
    trozos += [f"{pasos[d]:,} pasos {q}".replace(",", ".") for d, q in ((ayer, "ayer"), (hoy, "hoy")) if d in pasos]
    if a.get("pasos") and not pasos:
        trozos.append(f"pasos sin entender: «{str(a['pasos'])[:60]}»")
    if not (pasos or mins or peso or comp):
        raise HTTPException(400, f"No llega ni sueño, ni pasos, ni peso ({trozos[0]}): revisa las variables del atajo")
    guarda(DB, json.dumps(clean(estado), ensure_ascii=False))
    return {"texto": "Apuntado · " + " · ".join(trozos)}


# ---------- plan de carrera (carrera.py) ----------
@app.get("/api/carrera")
def plan_carrera(todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    exige(todo_sesion, authorization)
    estado = clean(dct(json.loads(DB.read_text("utf-8")))) if DB.exists() else clean({})
    return {k: v for k, v in carrera.informe(estado).items() if not k.startswith("_")}


# ---------- portada (hoy.html): lo de hoy de cada app en una sola llamada ----------
def racha(log, hid, hoy):
    """Días seguidos hechos hasta hoy; el día en curso todavía no la rompe (igual que index.html)."""
    d, n = date.fromisoformat(hoy), 0
    if hid not in log.get(hoy, []):
        d -= timedelta(days=1)
    while hid in log.get(d.isoformat(), []):
        n, d = n + 1, d - timedelta(days=1)
    return n


def trozo(fn):
    """Si una app no responde, su tarjeta lo dice y el resto de la portada sale igual."""
    try:
        return fn()
    except Exception as e:
        return {"error": str(e)[:160] or type(e).__name__}


def de_otra(nombre, ruta):
    base, _, var, _ = OTRAS[nombre]
    if not os.getenv(var):
        raise RuntimeError(f"Sin conectar: falta {var}")
    req = urllib.request.Request(f"{base}/api/{ruta}", headers={"Authorization": f"Bearer {os.getenv(var) or ''}"})
    with urllib.request.urlopen(req, timeout=8) as r:
        return json.load(r)


def hoy_habitos(s, hoy):
    plan, hecho = set(s["plan"].get(hoy, [])), set(s["log"].get(hoy, []))
    # orden: su sitio en la lista de hábitos, para que la portada reordene al marcar sin perderlo
    habitos = [{"id": h["id"], "n": h["n"], "c": h["c"], "plan": h["id"] in plan, "hecho": h["id"] in hecho,
                "racha": racha(s["log"], h["id"], hoy), "orden": i} for i, h in enumerate(s["habits"])]
    habitos.sort(key=lambda h: (not h["plan"], h["hecho"]))   # lo planificado y sin hacer, primero
    pesos = sorted(s["peso"].items())
    semana = [kg for d, kg in pesos if d > (date.fromisoformat(hoy) - timedelta(days=7)).isoformat()]
    return {"habitos": habitos,
            "peso": {"dia": pesos[-1][0], "kg": pesos[-1][1], "serie": serie(s["peso"], hoy),
                     "media": round(sum(semana) / len(semana), 1) if semana else None} if pesos else None}


def serie(por_dia, hasta, n=7):
    """Los n días que acaban en `hasta`, del más viejo al más nuevo (None donde no hay dato): las líneas de la portada."""
    d = date.fromisoformat(hasta)
    return [por_dia.get((d - timedelta(days=i)).isoformat()) for i in range(n - 1, -1, -1)]


def olvidos(s, hoy):
    """Para el fantasma de la portada: lo planificado ayer sin hacer y los días desde el último hábito marcado."""
    d = date.fromisoformat(hoy)
    ayer = (d - timedelta(days=1)).isoformat()
    con_algo = [x for x, ids in s["log"].items() if ids and x <= hoy]
    return {"ayer": [{"id": h["id"], "n": h["n"]} for h in s["habits"]
                     if h["id"] in s["plan"].get(ayer, []) and h["id"] not in s["log"].get(ayer, [])],
            "sin_venir": (d - date.fromisoformat(max(con_algo))).days if con_algo else 0}


@app.get("/api/fantasma")
def fantasma(todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    """Lo justo para el fantasma de cada página; /api/hoy pregunta a todas las apps y es más lento."""
    exige(todo_sesion, authorization)
    s = clean(dct(json.loads(DB.read_text("utf-8")))) if DB.exists() else clean({})
    hoy = date.today().isoformat()
    return {"habitos": [{k: h[k] for k in ("id", "plan", "hecho")} for h in hoy_habitos(s, hoy)["habitos"]], **olvidos(s, hoy),
            "ajustes": lee_ajustes()}


def hoy_salud(s, hoy):
    """El sueño de anoche y los pasos de ayer (lo último que hay), cada uno con su media y su línea de 7 días."""
    d = date.fromisoformat(hoy)
    ultimos = [s["salud"].get((d - timedelta(days=i)).isoformat(), {}) for i in range(8)]

    def ver(k, desde):
        xs = [x[k] for x in ultimos[desde:desde + 7] if x.get(k)]
        return {"ultimo": ultimos[desde].get(k), "media": round(sum(xs) / len(xs)) if xs else None,
                "serie": [x.get(k) for x in reversed(ultimos[desde:desde + 7])]}
    return {"sueno": ver("sueno", 0), "pasos": ver("pasos", 1)}


def hoy_anio(s, hoy):
    """Un nivel 0-3 por día desde el 1 de enero: la parte de tus hábitos que hiciste. El año en puntos."""
    d, total, out = date(int(hoy[:4]), 1, 1), max(1, len(s["habits"])), []
    while (dia := d.isoformat()) <= hoy:
        out.append(min(3, -(-len(s["log"].get(dia, [])) * 3 // total)))   # techo de hechos/total en tercios
        d += timedelta(days=1)
    return out


def hoy_carrera(s, hoy):
    c = carrera.informe(s, date.fromisoformat(hoy))
    prox = next((a for a in c["agenda"] if a["dia"] >= hoy and not a["hecho"]), None)
    return {"estimacion": c["estimacion"]["seg"], "objetivo": c["objetivo"]["seg"], "semana": c["semana"],
            "n_semanas": c["n_semanas"], "fase": c["fase"], "proxima": prox,
            "hoy_hecho": any(a["dia"] == hoy and a["hecho"] for a in c["agenda"])}


def hoy_entreno(s, hoy):
    """Lo que toca entrenar hoy, para el widget del iPhone: la rutina de la sesión de cada hábito planificado
    (o la única rutina del hábito, si no tiene sesión) y si ya está hecho."""
    rutinas, sesion = {r["id"]: r for r in s["rutinas"]}, s["sesion"].get(hoy, {})
    hecho, out = set(s["log"].get(hoy, [])), []
    for h in s["habits"]:
        suyas = [r for r in s["rutinas"] if r["hab"] == h["id"]]
        r = rutinas.get(sesion.get(h["id"])) or (suyas[0] if len(suyas) == 1 else None)
        if (h["id"] in s["plan"].get(hoy, []) or h["id"] in sesion) and (r or suyas):
            out.append({"id": h["id"], "n": r["n"] if r else h["n"], "tipo": (r or suyas[0])["tipo"],
                        "rutina": r["id"] if r else "", "hecho": h["id"] in hecho})
    return out


def hoy_comida(hoy):
    e, lista = de_otra("comida", "estado"), de_otra("comida", "lista")
    recetas = {r["id"]: r for r in e["recetas"]}
    menu = e["menu"].get(hoy) or {}
    falta = [f for f in lista["filas"] if not f["tachado"]]
    return {"menu": [{"franja": f, "n": recetas[menu[f]]["n"], "kcal": recetas[menu[f]]["kcal"]}
                     for f in ("desayuno", "comida", "cena") if menu.get(f) in recetas],
            "falta": len(falta), "total": len(lista["filas"]),
            "coste": round(sum(f["opciones"][f["barato"]]["coste"] for f in falta if f.get("barato")), 2)}


def hoy_gastos():
    r = de_otra("gastos", "resumen")
    quedan = r["dias"] - r["hechos"] + 1 if r["actual"] else 0
    return {"total": r["total"], "presu": r["presu"], "ayer": r["ayer"], "inicio": r["inicio"], "fin": r["fin"],
            "quedan": quedan, "al_dia": round((r["presu"] - r["total"]) / quedan, 2) if r["presu"] and quedan else None}


@app.get("/api/hoy")
def portada(todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    exige(todo_sesion, authorization)
    s = clean(dct(json.loads(DB.read_text("utf-8")))) if DB.exists() else clean({})
    hoy = date.today().isoformat()
    return {
        "hoy": hoy,
        "ajustes": lee_ajustes(),
        **hoy_habitos(s, hoy),
        **olvidos(s, hoy),
        "salud": hoy_salud(s, hoy),
        "pantalla": resumen_pantalla(lee_pantalla(), hoy),
        "anio": hoy_anio(s, hoy),
        "carrera": trozo(lambda: hoy_carrera(s, hoy)),
        "entreno": hoy_entreno(s, hoy),
        # lo que vence hoy o ya venció; lo sin fecha se queda en pendientes.html
        "tareas": trozo(lambda: [t for t in vault.tareas() if t["due"] and t["due"] <= hoy]),
        "leer": trozo(lambda: len(vault.lecturas())),
        "comida": trozo(lambda: hoy_comida(hoy)),
        "gastos": trozo(hoy_gastos),
    }


# ---------- Tom: Siri y el modo voz de la app de iPhone ----------
# Las frases rápidas de Siri (sin Claude) van a /api/mueve, /api/toca y /api/presupuesto, que devuelven el texto ya
# listo para leerlo en voz alta. Lo dicho en libre («Dile a Tom…») va a /api/tom, que lo reenvía al bot de Telegram
# por 127.0.0.1: allí está la interpretación con Claude de los mensajes libres, y así hay una sola.
TOM = os.getenv("TOM_URL", "http://127.0.0.1:8091/tom")
SEMANA_ES = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"]


def cuando(dia, hoy):
    """Un día dicho como se dice: hoy, mañana, el jueves, el jueves 20."""
    n = (date.fromisoformat(dia) - date.fromisoformat(hoy)).days
    if -1 <= n <= 2:
        return {-1: "ayer", 0: "hoy", 1: "mañana", 2: "pasado mañana"}[n]
    nombre = SEMANA_ES[date.fromisoformat(dia).weekday()]
    return f"el {nombre}" if 0 < n < 7 else f"el {nombre} {int(dia[8:])}"


def a_dia(dia, hoy):
    """«a mañana», «al jueves»."""
    t = cuando(dia, hoy)
    return "al" + t[2:] if t.startswith("el ") else "a " + t


def lista_es(xs):
    xs = [x for x in xs if x]
    return " y ".join([", ".join(xs[:-1]), xs[-1]]) if len(xs) > 1 else (xs[0] if xs else "")


def resumido(xs, n=4):
    """Hasta n en voz alta; del resto, cuántos."""
    return lista_es(xs) if len(xs) <= n else ", ".join(xs[:n]) + f" y {len(xs) - n} más"


def es_entreno(s, hid):
    """Gimnasio, correr o escalar: lo que tiene rutinas que no son de movilidad (la activación y el core se quedan)."""
    return any(r["hab"] == hid and r["tipo"] != "movilidad" for r in s["rutinas"])


def nombre_sesion(s, hid, rid):
    r = next((r for r in s["rutinas"] if r["id"] == rid), None)
    if r:
        return r["n"].split(" · ")[0]   # «Push A · Pecho hombro tríceps» -> «Push A»: se lee en voz alta
    return next((h["n"] for h in s["habits"] if h["id"] == hid), hid)


def mueve_entreno(s, de, a, hoy, hid=None):
    """Pasa el entreno sin hacer de `de` a `a`, con su sesión. Si `a` ya tiene ese mismo hábito, se cambian los
    dos días (nunca se pierde una sesión). Devuelve el texto para Siri; ValueError si no hay nada que mover."""
    if de == a:
        raise ValueError(f"El entreno ya es {cuando(a, hoy)}")
    plan_de, hecho_de = s["plan"].get(de, []), set(s["log"].get(de, []))
    candidatos = [h for h in plan_de if es_entreno(s, h) and h not in hecho_de and (not hid or h == hid)]
    if not candidatos:
        if any(es_entreno(s, h) and (not hid or h == hid) for h in hecho_de):
            raise ValueError(f"El entreno de {cuando(de, hoy)} ya está hecho")
        raise ValueError(f"No tienes entreno {cuando(de, hoy)}")
    ses_de, ses_a = dict(s["sesion"].get(de, {})), dict(s["sesion"].get(a, {}))
    plan_de, plan_a = list(plan_de), list(s["plan"].get(a, []))
    trozos = []
    for h in candidatos:
        uno, otro = ses_de.pop(h, None), ses_a.pop(h, None)
        if h in plan_a:
            if otro:
                ses_de[h] = otro
            if uno:
                ses_a[h] = uno
            trozos.append(f"{nombre_sesion(s, h, uno)} pasa {a_dia(a, hoy)} y {nombre_sesion(s, h, otro)} {a_dia(de, hoy)}")
        else:
            plan_de.remove(h)
            plan_a.append(h)
            if uno:
                ses_a[h] = uno
            trozos.append(f"{nombre_sesion(s, h, uno)} pasa {a_dia(a, hoy)}")
    s["plan"][de], s["plan"][a] = plan_de, plan_a
    s["sesion"][de], s["sesion"][a] = ses_de, ses_a
    texto = lista_es(trozos)
    return clean(s), texto[:1].upper() + texto[1:]


def texto_toca(s, dia, hoy, tareas):
    """Qué toca un día, para leerlo en voz alta: el entreno, lo que falta por marcar (si es hoy) y lo que vence."""
    dicho = cuando(dia, hoy).capitalize()
    items = hoy_entreno(s, dia)
    por_hacer = [x["n"].split(" · ")[0] for x in items if not x["hecho"]]
    hechos = [x["n"].split(" · ")[0] for x in items if x["hecho"]]
    frases = [f"{dicho} toca {lista_es(por_hacer)}." if por_hacer else
              f"{dicho} ya has hecho {lista_es(hechos)}." if hechos else f"{dicho} no tienes entreno."]
    if dia == hoy:
        hecho, plan, ya = set(s["log"].get(dia, [])), set(s["plan"].get(dia, [])), {x["id"] for x in items}
        faltan = [h["n"] for h in s["habits"] if h["id"] not in hecho | ya and (h["goal"] == 7 or h["id"] in plan)]
        if faltan:
            frases.append(f"Te falta {resumido(faltan)}.")
    suyas = [t for t in tareas if t.get("due") == dia]
    vencidas = [t for t in tareas if dia == hoy and t.get("due") and t["due"] < hoy]
    if suyas:
        frases.append("Pendiente: " + resumido([t["t"] + (f" a las {t['hora']}" if t.get("hora") else "") for t in suyas]) + ".")
    if vencidas:
        frases.append(f"Y {len(vencidas)} {'tarea vencida' if len(vencidas) == 1 else 'tareas vencidas'}.")
    return " ".join(frases)


def texto_presupuesto(g):
    """g es hoy_gastos(): lo que llevas en el ciclo de cobro y lo que te queda al día."""
    if not g["presu"]:
        return f"Llevas {round(g['total'])} € este ciclo."
    queda = round(g["presu"] - g["total"])
    if queda < 0:
        return f"Te has pasado {-queda} € del presupuesto de {round(g['presu'])} €."
    texto = f"Te quedan {queda} € de {round(g['presu'])} €"
    if g["quedan"]:
        texto += f" para {g['quedan']} {'día' if g['quedan'] == 1 else 'días'}, unos {round(g['al_dia'])} € al día"
    return texto + "."


@app.post("/api/mueve")
def mueve(a: dict, todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    """{a, de?, id?}: «mueve el entreno a mañana». de = hoy si no viene; id, un hábito concreto."""
    exige(todo_sesion, authorization)
    hoy = date.today().isoformat()
    destino, de = day(a.get("a")), day(a.get("de")) or hoy
    if not destino:
        raise HTTPException(400, "¿A qué día lo muevo?")
    estado = clean(dct(json.loads(DB.read_text("utf-8")))) if DB.exists() else clean({})
    try:
        estado, texto = mueve_entreno(estado, de, destino, hoy, str(a.get("id") or "") or None)
    except ValueError as e:
        raise HTTPException(400, str(e))
    guarda(DB, json.dumps(estado, ensure_ascii=False))
    return {"texto": texto}


@app.get("/api/toca")
def toca(dia: str = "", todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    exige(todo_sesion, authorization)
    hoy = date.today().isoformat()
    s = clean(dct(json.loads(DB.read_text("utf-8")))) if DB.exists() else clean({})
    try:
        tareas = vault.tareas()
    except Exception:
        tareas = []   # sin el vault, lo de hábitos sale igual
    return {"texto": texto_toca(s, day(dia) or hoy, hoy, tareas)}


@app.get("/api/presupuesto")
def presupuesto(todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    exige(todo_sesion, authorization)
    try:
        g = hoy_gastos()
    except Exception as e:
        raise HTTPException(502, f"Gastos no responde: {str(e)[:100]}")
    return {"texto": texto_presupuesto(g), **g}


@app.post("/api/tom")
async def tom(a: dict, todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    """{texto, conv?}: lo que le dices a Tom. El bot recuerda los últimos turnos de cada conv 10 minutos."""
    exige(todo_sesion, authorization)
    texto = str(a.get("texto") or "").strip()[:1000]
    if not texto:
        raise HTTPException(400, "¿Qué le digo a Tom?")
    cuerpo = json.dumps({"texto": texto, "conv": str(a.get("conv") or "iphone")[:64]}).encode()
    try:
        estado, r = await run_in_threadpool(reenvia, TOM, "POST", cuerpo, PASS)
    except Exception:
        raise HTTPException(502, "Tom no responde: el bot de Telegram está parado")
    if estado == 401:
        raise HTTPException(502, "El bot no acepta la clave de todo (TODO_PASS distinta)")
    return Response(r, status_code=estado, media_type="application/json")


# ---------- pendientes: el vault de Obsidian (vault.py) ----------
# Las tareas viven en el vault, no en data.json: así las ves en Obsidian junto a las
# que crea el cerebro, y un PUT del cliente no se las puede llevar por delante.
@app.get("/api/bandeja")
def bandeja(solo: str = "", todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    exige(todo_sesion, authorization)
    if solo == "tareas":
        return {"tareas": vault.tareas()}
    return {"tareas": vault.tareas(), "leer": vault.lecturas(), "notas": vault.recientes(),
            "revisar": vault.revisar(), "hoy": date.today().isoformat()}


def _valida(fn, *args):
    try:
        return fn(*args)
    except ValueError as e:
        raise HTTPException(400, str(e))


@app.post("/api/tarea")
def nueva_tarea(t: dict, todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    exige(todo_sesion, authorization)
    hora = str(t.get("hora") or "")[:5]
    return _valida(vault.nueva_tarea, t.get("t"), day(t.get("due")), hora if len(hora) == 5 and hora[2] == ":" else "")


@app.post("/api/tarea/edita")
def edita_tarea(t: dict, todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    exige(todo_sesion, authorization)
    hora = str(t.get("hora") or "")[:5]
    nueva = _valida(vault.edita, str(t.get("id") or ""), t.get("t"), day(t.get("due")),
                    hora if len(hora) == 5 and hora[2] == ":" else "")
    if not nueva:
        raise HTTPException(404, "Esa tarea ya no está (¿la has cambiado en Obsidian?)")
    return nueva


@app.post("/api/tarea/borra")
def borra_tarea(t: dict, todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    """Devuelve {ruta, i, linea}: con eso /api/tarea/restaura la vuelve a poner donde estaba."""
    exige(todo_sesion, authorization)
    hecho = vault.borra(str(t.get("id") or ""))
    if not hecho:
        raise HTTPException(404, "Esa tarea ya no está (¿la has cambiado en Obsidian?)")
    return hecho


@app.post("/api/tarea/restaura")
def restaura_tarea(t: dict, todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    exige(todo_sesion, authorization)
    return _valida(vault.restaura, t.get("ruta"), t.get("i", 0), t.get("linea"))


@app.post("/api/tarea/hecha")
def tarea_hecha(t: dict, todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    exige(todo_sesion, authorization)
    nuevo = vault.marca(str(t.get("id") or ""), t.get("hecha", True) is not False)
    if not nuevo:
        raise HTTPException(404, "Esa tarea ya no está (¿la has cambiado en Obsidian?)")
    return {"id": nuevo}


@app.post("/api/leer")
def nueva_lectura(d: dict, todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    exige(todo_sesion, authorization)
    x = _valida(vault.nueva_lectura, d)
    if d.get("reemplaza"):
        quita_de_cola(str(d["reemplaza"]))
    return x


# Lo que se comparte desde el iPhone (hoja de compartir de Safari): la nota se guarda al momento con lo mínimo, para
# que no se pierda aunque el bot esté parado, y queda en cola. El bot la resume con Claude en su siguiente vuelta
# (igual que un enlace por Telegram) y la nota buena sustituye a la provisional (`reemplaza` en /api/leer).
LEER_COLA = DB.parent / "leer_cola.json"
cerrojo_leer = threading.Lock()


def cola_leer():
    try:
        return [x for x in json.loads(LEER_COLA.read_text("utf-8")) if isinstance(x, dict)]
    except (OSError, json.JSONDecodeError):
        return []


def leer_pendiente(d):
    url = str(d.get("url") or "").strip()
    titulo = " ".join(str(d.get("titulo") or "").split())[:200]
    if titulo.startswith(("http://", "https://")):
        titulo = ""
    nota = " ".join(str(d.get("nota") or "").split())[:500]
    x = vault.nueva_lectura({"url": url, "titulo": titulo or urllib.parse.urlsplit(url).netloc or url, "nota": nota,
                             "source": "iphone", "resumen": "Sin resumir todavía: guardado desde el iPhone."})
    with cerrojo_leer:
        guarda(LEER_COLA, json.dumps([*cola_leer(), {"url": url, "titulo": titulo, "nota": nota, "ruta": x["ruta"],
                                                    "t": datetime.now().isoformat(timespec="seconds")}][-50:],
                                     ensure_ascii=False, indent=1))
    return {**x, "texto": "Guardado en Leer luego"}


def quita_de_cola(ruta):
    with cerrojo_leer:
        cola = cola_leer()
        if any(x.get("ruta") == ruta for x in cola):
            guarda(LEER_COLA, json.dumps([x for x in cola if x.get("ruta") != ruta], ensure_ascii=False, indent=1))


@app.post("/api/leer/pendiente")
def nueva_lectura_pendiente(d: dict, todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    exige(todo_sesion, authorization)
    return _valida(leer_pendiente, d)


@app.get("/api/leer/pendiente")
def lecturas_pendientes(todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    """Para el bot: lo compartido que falta por resumir (la nota provisional sigue en el vault)."""
    exige(todo_sesion, authorization)
    return {"cola": [x for x in cola_leer() if vault.de_leer(x.get("ruta"))]}


@app.post("/api/leido")
def marca_leido(d: dict, todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    exige(todo_sesion, authorization)
    _valida(vault.leido, str(d.get("ruta") or ""))
    return {"ok": True}


# ---------- avisos push ----------
def suscripciones():
    try:
        return [s for s in json.loads(SUBS.read_text("utf-8")) if isinstance(s, dict)]
    except (OSError, json.JSONDecodeError):
        return []


@app.get("/api/push/clave")
def clave_push(todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    exige(todo_sesion, authorization)
    return {"clave": os.getenv("VAPID_PUB") or ""}


@app.post("/api/push/sub")
def alta_push(sub: dict, todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    exige(todo_sesion, authorization)
    url = str(sub.get("endpoint") or "")
    claves = dct(sub.get("keys"))
    if not url.startswith("https://") or len(url) > 600:
        raise HTTPException(400, "endpoint no válido")
    if not all(isinstance(claves.get(k), str) for k in ("p256dh", "auth")):
        raise HTTPException(400, "faltan las claves de cifrado")
    limpia = {
        "endpoint": url,
        "keys": {"p256dh": claves["p256dh"][:120], "auth": claves["auth"][:60]},
    }
    # un navegador que se resuscribe trae el mismo endpoint: se reemplaza, no se duplica
    otras = [s for s in suscripciones() if s.get("endpoint") != url]
    guarda(SUBS, json.dumps(otras[-19:] + [limpia], ensure_ascii=False))
    return {"ok": True, "total": len(otras[-19:]) + 1}


@app.post("/api/push/baja")
def baja_push(sub: dict, todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    exige(todo_sesion, authorization)
    url = str(sub.get("endpoint") or "")
    guarda(SUBS, json.dumps([s for s in suscripciones() if s.get("endpoint") != url], ensure_ascii=False))
    return {"ok": True}


# ---------- comida y gastos dentro de todo ----------
# Sus frontales se sirven también aquí, el mismo index.html leído de su carpeta, con "/api/"
# cambiado a "/api/<app>/": un solo login (el de todo) y una sola PWA. Las llamadas se reenvían
# por 127.0.0.1 con el bearer de cada app. Sus webs propias siguen igual.
# Los gastos de Aitana son otra instancia de gastos (~/gastos-aitana, :8086): datos aparte, mismo frontal.
GASTOS = Path("/home/pi/gastos/static/index.html")
# La copia de todo de Aitana (~/todo-aitana) apunta GASTOS_URL a :8086 con su propia clave: no tiene la de Yago.
OTRAS = {"comida": ("http://127.0.0.1:8084", Path("/home/pi/comida/static/index.html"), "COMIDA_PASS", ""),
         "gastos": (os.getenv("GASTOS_URL", "http://127.0.0.1:8085"), GASTOS, "GASTOS_PASS", ""),
         "gastos-aitana": ("http://127.0.0.1:8086", GASTOS, "GASTOS_AITANA_PASS", "Aitana")}


def boton(href, texto, actual=False):
    return (f'<a class="c-btn mini" href="{href}" style="text-decoration:none;margin-left:8px"'
            + (' aria-current="true"' if actual else "") + f">{texto}</a>")


# el mismo menú de arriba a la derecha que en las páginas de todo (en la app del iPhone no hay botón
# de atrás). Si la cabecera ya tiene algo empujado a la derecha (.ciclo de gastos), va pegado a eso.
MENU = [("/", "Hoy"), ("/habitos.html", "Hábitos"), ("/pendientes.html", "Pendientes"), ("/entreno.html", "Entreno"),
        ("/salud.html", "Salud"), ("/comida.html", "Comida"), ("/gastos.html", "Gastos")]
ESTILO_MENU = ("<style>.menu-todo{margin-left:auto;display:flex;gap:6px;max-width:100%;overflow-x:auto;"
               "scrollbar-width:none}.menu-todo a{text-decoration:none}"
               "@media(min-width:920px){.ciclo~.menu-todo{margin-left:0}}</style>")   # en móvil va en su línea


def frontal(nombre):
    # también tras coma: <meta name="calma-datos" content="/api/estado,/api/lista">
    html = OTRAS[nombre][1].read_text("utf-8").replace('"/api/', f'"/api/{nombre}/').replace(',/api/', f',/api/{nombre}/')
    # entrar y salir es el de todo: la cookie de todo es la que abre el reenvío
    html = html.replace(f'"/api/{nombre}/login', '"/api/login').replace(f'"/api/{nombre}/logout', '"/api/logout')
    if quien := OTRAS[nombre][3]:
        html = html.replace("<h1>Gastos</h1>", f"<h1>Gastos · {quien}</h1>", 1)
    # entre los dos gastos se salta con un toque, junto al título
    if nombre.startswith("gastos") and os.getenv("GASTOS_AITANA_PASS"):
        botones = boton("/gastos.html", "Yago", nombre == "gastos") + boton("/gastos-aitana.html", "Aitana", nombre != "gastos")
        html = re.sub(r"(<h1>[^<]*</h1>)", lambda m: m[1] + botones, html, count=1)
    aqui = "/" + nombre.split("-")[0] + ".html"
    menu = ESTILO_MENU + '<nav class="menu-todo">' + "".join(
        f'<a class="c-btn mini" href="{h}">{t}</a>' for h, t in MENU if h != aqui) + "</nav>"
    # comida cierra la cabecera con sus pestañas, que en móvil ocupan una línea entera: el menú, antes
    ancla = '<nav class="pestanas' if '<nav class="pestanas' in html else "</header>"
    # como las páginas de todo: barra de estado translúcida en la app instalada (los avisos salen de la isla)
    html = html.replace("</title>", '</title>\n<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">'
                        '\n<link rel="manifest" href="/manifest.json" crossorigin="use-credentials">'
                        '\n<script src="/mascota.js?v=5"></script>'
                        # y la transición entre páginas de todo (calma.css, calma.js): la cabecera vuela, la barra quieta
                        '\n<style>@view-transition{navigation:auto}'
                        '@media(prefers-reduced-motion:reduce){@view-transition{navigation:none}}</style>', 1)
    html = html.replace('<html lang="es">', '<html lang="es" data-vt>', 1)
    return HTMLResponse(html.replace(ancla, menu + ancla, 1))


@app.get("/comida.html")
def frontal_comida():
    return frontal("comida")


@app.get("/gastos.html")
def frontal_gastos():
    return frontal("gastos")


@app.get("/gastos-aitana.html")
def frontal_gastos_aitana():
    return frontal("gastos-aitana")


def reenvia(url, metodo, cuerpo, clave):
    req = urllib.request.Request(url, data=cuerpo if metodo != "GET" else None, method=metodo,
                                 headers={"Authorization": f"Bearer {clave}", "Content-Type": "application/json"})
    try:
        # /api/menu de comida llama a Claude y tarda minutos
        with urllib.request.urlopen(req, timeout=900) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


@app.api_route("/api/comida/{ruta:path}", methods=["GET", "POST", "PUT"])
@app.api_route("/api/gastos/{ruta:path}", methods=["GET", "POST", "PUT"])
@app.api_route("/api/gastos-aitana/{ruta:path}", methods=["GET", "POST", "PUT"])
async def otra_app(ruta: str, request: Request, todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    exige(todo_sesion, authorization)
    nombre = request.url.path.split("/")[2]
    base, _, var, _ = OTRAS[nombre]
    clave = os.getenv(var)
    if not clave:
        raise HTTPException(503, f"Falta {var} en el .env de todo (~/bin/claves.sh lo copia)")
    url = f"{base}/api/{ruta}" + (f"?{request.url.query}" if request.url.query else "")
    estado, cuerpo = await run_in_threadpool(reenvia, url, request.method, await request.body(), clave)
    if estado == 401:   # que la página no pida la contraseña de todo en bucle
        raise HTTPException(502, f"{nombre} no acepta la clave que tiene todo: ~/bin/claves.sh")
    return Response(cuerpo, status_code=estado, media_type="application/json")


# La portada es Hoy: es lo primero que se abre (el icono del iPhone arranca en /). Hábitos, que
# era el index.html de siempre, vive en /habitos.html (y /index.html sigue sirviéndolo).
@app.get("/", include_in_schema=False)
def portada_html():
    return FileResponse(HERE / "static" / "hoy.html")


@app.get("/escalada.html", include_in_schema=False)
def escalada_vieja():
    """Fue una sección aparte un día; ahora es la tarjeta Escalada de Entreno."""
    return RedirectResponse("/entreno.html#c-esc")


@app.get("/sueno.html", include_in_schema=False)
def sueno_viejo():
    return RedirectResponse("/salud.html")


@app.get("/habitos.html", include_in_schema=False)
def habitos_html():
    return FileResponse(HERE / "static" / "index.html")


# El estático queda abierto: no lleva datos, y así la PWA puede cargar y pintar
# la pantalla de contraseña cuando /api/state responde 401.
app.mount("/", StaticFiles(directory=HERE / "static", html=True), name="static")
