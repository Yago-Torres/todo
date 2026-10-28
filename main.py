import hashlib
import hmac
import json
import os
import re
import time
import unicodedata
import urllib.error
import urllib.request
from datetime import date, datetime, timedelta
from pathlib import Path

from fastapi import Body, Cookie, FastAPI, Header, HTTPException, Request, Response
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import FileResponse, HTMLResponse
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


def dia_salud(v):
    v = dct(v)
    d = {c: n for c, hi in (("sueno", 1440), ("pasos", 200000)) if (n := entero(v.get(c), 0, hi, 0))}
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
    return informe_sueno(s, date.today())


@app.post("/api/salud")
def registra_salud(a: dict, todo_sesion: str = Cookie(None), authorization: str = Header(None)):
    """{"sueno": lo dormido anoche, "pasos": los de ayer}. El sueño va al día en que te levantas."""
    exige(todo_sesion, authorization)
    # lo que manda el atajo, tal cual (journalctl -u todo): para afinarlo sin adivinar
    print("salud recibido:", json.dumps({k: str(a.get(k))[:200] for k in ("sueno", "pasos", "fases", "dia") if k in a},
                                        ensure_ascii=False), flush=True)
    estado = clean(dct(json.loads(DB.read_text("utf-8")))) if DB.exists() else clean({})
    hoy = day(a.get("dia")) or date.today().isoformat()
    ayer = (date.fromisoformat(hoy) - timedelta(days=1)).isoformat()
    trozos = []
    # con los tramos de la noche, lo dormido sale de ellos (sin lo despierto); si no, del total que mande
    fases = lee_fases(a.get("fases"))
    if fases:
        mins = round(sum(n for e, _, n in fases if e != "awake") / 60)
    elif crudo := real(a.get("sueno"), 0, 10 ** 6):
        # como en los entrenos: Salud suma en horas, minutos o segundos según el atajo; por magnitud
        mins = round(crudo * 60 if crudo <= 24 else crudo if crudo <= 1440 else crudo / 60)
    else:
        mins = 0
    if mins > 16 * 60:
        raise HTTPException(400, f"{mins // 60} h de sueño: Salud está sumando dos fuentes (iPhone y COROS) o el "
                                 "tiempo en la cama. En el atajo, una sola fuente y «Value is not In Bed»")
    if mins:
        noche = estado["salud"].setdefault(hoy, {})
        noche["sueno"] = mins
        if fases:
            noche["fases"] = fases
        trozos.append(f"dormido {mins // 60} h {mins % 60:02d}" + (f" en {len(fases)} tramos" if fases else ""))
    else:
        # que la notificación diga qué ha llegado: es la única pista para arreglar el atajo
        raro = a.get("fases") or a.get("sueno")
        trozos.append(f"sueño sin entender: «{str(raro)[:60]}»" if raro else "sin datos de sueño")
    if pasos := round(real(a.get("pasos"), 0, 200000) or 0):
        estado["salud"].setdefault(ayer, {})["pasos"] = pasos
        trozos.append(f"{pasos:,} pasos ayer".replace(",", "."))
    if not pasos and "dormido" not in trozos[0]:
        raise HTTPException(400, f"No llega ni sueño ni pasos ({trozos[0]}): revisa las variables del atajo")
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
    req = urllib.request.Request(f"{base}/api/{ruta}", headers={"Authorization": f"Bearer {os.getenv(var) or ''}"})
    with urllib.request.urlopen(req, timeout=8) as r:
        return json.load(r)


def hoy_habitos(s, hoy):
    plan, hecho = set(s["plan"].get(hoy, [])), set(s["log"].get(hoy, []))
    habitos = [{"id": h["id"], "n": h["n"], "c": h["c"], "plan": h["id"] in plan, "hecho": h["id"] in hecho,
                "racha": racha(s["log"], h["id"], hoy)} for h in s["habits"]]
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
        **hoy_habitos(s, hoy),
        "salud": hoy_salud(s, hoy),
        "anio": hoy_anio(s, hoy),
        "carrera": trozo(lambda: hoy_carrera(s, hoy)),
        # lo que vence hoy o ya venció; lo sin fecha se queda en pendientes.html
        "tareas": trozo(lambda: [t for t in vault.tareas() if t["due"] and t["due"] <= hoy]),
        "leer": trozo(lambda: len(vault.lecturas())),
        "comida": trozo(lambda: hoy_comida(hoy)),
        "gastos": trozo(hoy_gastos),
    }


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
    return _valida(vault.nueva_lectura, d)


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
OTRAS = {"comida": ("http://127.0.0.1:8084", Path("/home/pi/comida/static/index.html"), "COMIDA_PASS", ""),
         "gastos": ("http://127.0.0.1:8085", GASTOS, "GASTOS_PASS", ""),
         "gastos-aitana": ("http://127.0.0.1:8086", GASTOS, "GASTOS_AITANA_PASS", "Aitana")}


def boton(href, texto, actual=False):
    return (f'<a class="c-btn mini" href="{href}" style="text-decoration:none;margin-left:8px"'
            + (' aria-current="true"' if actual else "") + f">{texto}</a>")


# el mismo menú de arriba a la derecha que en las páginas de todo (en la app del iPhone no hay botón
# de atrás). Si la cabecera ya tiene algo empujado a la derecha (.ciclo de gastos), va pegado a eso.
MENU = [("/", "Hoy"), ("/habitos.html", "Hábitos"), ("/pendientes.html", "Pendientes"), ("/entreno.html", "Entreno"),
        ("/sueno.html", "Sueño"), ("/comida.html", "Comida"), ("/gastos.html", "Gastos")]
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
    if nombre.startswith("gastos"):
        botones = boton("/gastos.html", "Yago", nombre == "gastos") + boton("/gastos-aitana.html", "Aitana", nombre != "gastos")
        html = re.sub(r"(<h1>[^<]*</h1>)", lambda m: m[1] + botones, html, count=1)
    aqui = "/" + nombre.split("-")[0] + ".html"
    menu = ESTILO_MENU + '<nav class="menu-todo">' + "".join(
        f'<a class="c-btn mini" href="{h}">{t}</a>' for h, t in MENU if h != aqui) + "</nav>"
    # comida cierra la cabecera con sus pestañas, que en móvil ocupan una línea entera: el menú, antes
    ancla = '<nav class="pestanas' if '<nav class="pestanas' in html else "</header>"
    # como las páginas de todo: barra de estado translúcida en la app instalada (los avisos salen de la isla)
    html = html.replace("</title>", '</title>\n<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">'
                        '\n<link rel="manifest" href="/manifest.json" crossorigin="use-credentials">', 1)
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


@app.get("/habitos.html", include_in_schema=False)
def habitos_html():
    return FileResponse(HERE / "static" / "index.html")


# El estático queda abierto: no lleva datos, y así la PWA puede cargar y pintar
# la pantalla de contraseña cuando /api/state responde 401.
app.mount("/", StaticFiles(directory=HERE / "static", html=True), name="static")
