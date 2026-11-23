"""El calendario de todo: eventos propios (calendario.json) que se COPIAN a Google Calendar y a iCloud.

Solo de ida: lo que se apunta aquí se escribe allí (y se cambia o se borra allí si se cambia o se borra aquí), pero
lo que se crea en Google o en el iPhone no vuelve. Las tareas y los recordatorios con fecha no viven aquí: son
tareas del vault (vault.py) y la página las enseña en su día.

- calendario.json va aparte de data.json: clean() se lo llevaría en el siguiente PUT.
- La copia va en un hilo (`sincroniza`): la API contesta al momento y cada evento lleva su estado en `sincro`
  ("ok", "pendiente", "error: …", "sin configurar"). Lo que falla se reintenta cada 10 minutos.
- Google: la cuenta de servicio del bot (~/bots/todo-bot/google.json y su calendario.py, que se carga por ruta).
- iCloud: CalDAV con el Apple ID y una contraseña específica de app (ICLOUD_USER e ICLOUD_PASS en el .env).
  Cada calendario va al de iCloud que se llame igual (o empiece igual), si no ALIAS_ICLOUD, si no "calendar".
  ICLOUD_MAPA="cal=nombre,..." en el .env lo fuerza.
- Los entrenos planeados (plan + sesion de data.json, de hoy en adelante) son eventos de «Deporte» con `entreno`
  ("dia:idHabito"). Los cuadra `cuadra_entrenos` cada vez que cambia data.json: se crean, se cambian y se borran
  solos, y por eso no se editan desde el calendario (se cambian en Entreno). Los de días pasados se quedan como fueron.
  Desde el 23/11 (lo pidió Yago: en el iPhone salían dos veces y todo el día) van **solo a iCloud** y **con hora**
  (`HORA_ENTRENO`, lo que dura la rutina, uno detrás de otro); del plan de carrera ya no van las semanas enteras.
"""
import base64
import importlib.util
import json
import os
import queue
import re
import secrets
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

FICHERO = Path(os.getenv("TODO_CALENDARIO", Path(__file__).with_name("calendario.json")))
ESTADO = Path(os.getenv("TODO_DB", Path(__file__).with_name("data.json")))   # de donde salen los entrenos
GOOGLE_MODULO = Path(os.getenv("GOOGLE_CALENDARIO", "/home/pi/bots/todo-bot/calendario.py"))
ZONA = ZoneInfo("Europe/Madrid")
# id (el mismo nombre que en el bot y en Google) -> nombre y color
CALENDARIOS = {"day-to-day": ("Día a día", "#3B82F6"), "Deporte": ("Deporte", "#16A34A"),
               "universidad": ("Universidad", "#9333EA"), "musica": ("Música", "#EA580C"),
               "ocio": ("Ocio", "#F59E0B"), "trabajo": ("Trabajo", "#475569"),
               "vacaciones": ("Vacaciones", "#0891B2"), "cumples": ("Cumpleaños", "#DB2777")}
REPITE = {"", "diario", "semanal", "mensual", "anual"}
DIA = re.compile(r"^\d{4}-\d{2}-\d{2}$")
HORA = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")
_cerrojo = threading.RLock()


# ---------- guardar ----------
def todos():
    try:
        d = json.loads(FICHERO.read_text("utf-8"))
        return d if isinstance(d, list) else []
    except (OSError, ValueError):
        return []


def _guarda(evs):
    tmp = FICHERO.with_name(f".{FICHERO.name}.tmp")
    tmp.write_text(json.dumps(evs, ensure_ascii=False, indent=1), "utf-8")
    tmp.replace(FICHERO)


def limpia(d, previo=None):
    """Un evento con forma fija; lo que no se entiende, fuera (ValueError si falta lo básico)."""
    p = previo or {}
    g = lambda k, defecto="": d.get(k, p.get(k, defecto))
    t = " ".join(str(g("t") or "").split())[:200]
    dia = str(g("dia") or "")
    if not t:
        raise ValueError("falta el título")
    if not DIA.match(dia):
        raise ValueError("falta el día")
    fin_dia = str(g("fin_dia") or dia)
    fin_dia = fin_dia if DIA.match(fin_dia) and fin_dia >= dia else dia
    inicio = str(g("inicio") or "")[:5]
    inicio = inicio if HORA.match(inicio) else ""
    fin = str(g("fin") or "")[:5]
    fin = fin if inicio and HORA.match(fin) else ""
    if inicio and fin and fin_dia == dia and fin <= inicio:
        fin = ""
    try:
        aviso = int(g("aviso", -1))
    except (TypeError, ValueError):
        aviso = -1
    repite = str(g("repite") or "")
    hasta = str(g("hasta") or "")
    exc = [x for x in (g("excepciones", []) or []) if isinstance(x, str) and DIA.match(x)]
    return {"id": p.get("id") or d.get("id") or "e" + secrets.token_hex(6),
            "t": t, "dia": dia, "fin_dia": fin_dia, "inicio": inicio, "fin": fin,
            "cal": c if (c := str(g("cal") or "")) in CALENDARIOS else next(iter(CALENDARIOS)),
            "nota": str(g("nota") or "").strip()[:2000], "lugar": str(g("lugar") or "").strip()[:200],
            "aviso": aviso if -1 <= aviso <= 40320 else -1,
            "repite": repite if repite in REPITE else "",
            "hasta": hasta if repite and DIA.match(hasta) and hasta >= dia else "",
            "excepciones": sorted(set(exc))[:200],
            "entreno": str(g("entreno") or "")[:60],
            # dónde está copiado (ids de Google y de iCloud) y cómo fue la última vez
            "ext": p.get("ext") or d.get("ext") or {}, "sincro": p.get("sincro") or {}}


def publico(e):
    return {k: v for k, v in e.items() if k != "ext"}


def nuevo(d):
    with _cerrojo:
        evs = todos()
        e = limpia(d)
        e["sincro"] = estado_inicial()
        evs.append(e)
        _guarda(evs)
    encola(e["id"])
    return publico(e)


def edita(id_, d):
    with _cerrojo:
        evs = todos()
        i = next((i for i, e in enumerate(evs) if e["id"] == id_), None)
        if i is None:
            raise ValueError("ese evento ya no está")
        viejo = evs[i]
        if viejo.get("entreno"):
            raise ValueError("es un entreno: cámbialo en Entreno y el calendario se pone al día solo")
        e = limpia({k: v for k, v in d.items() if k not in ("id", "ext", "sincro")}, viejo)
        if e["cal"] != viejo["cal"]:
            e["ext"] = {**e["ext"], "mover_de": viejo["cal"]}
        e["sincro"] = estado_inicial()
        evs[i] = e
        _guarda(evs)
    encola(e["id"])
    return publico(e)


def borra(id_, dia=""):
    """Sin `dia`, el evento entero (devuelve el evento, para restaura()). Con `dia`, solo esa repetición."""
    with _cerrojo:
        evs = todos()
        e = next((e for e in evs if e["id"] == id_), None)
        if e is None:
            raise ValueError("ese evento ya no está")
        if e.get("entreno"):
            raise ValueError("es un entreno: quítalo del plan en Entreno")
        if dia and e["repite"]:
            antes = publico(e)
            e["excepciones"] = sorted(set(e["excepciones"]) | {dia})
            e["sincro"] = estado_inicial()
            _guarda(evs)
            encola(id_)
            return {"evento": antes, "solo": dia}
        _guarda([x for x in evs if x["id"] != id_])
    _borrados.put(e)
    _avisa()
    return {"evento": publico(e)}


def restaura(e):
    if not isinstance(e, dict) or not e.get("id"):
        raise ValueError("no se puede restaurar eso")
    with _cerrojo:
        evs = todos()
        # deshacer «solo esta»: el evento sigue ahí y vuelve a la versión de antes, con sus copias de fuera;
        # deshacer un borrado entero: las copias de fuera ya se borraron, se crean de nuevo
        ext = next((x.get("ext") or {} for x in evs if x["id"] == e["id"]), {})
        evs = [x for x in evs if x["id"] != e["id"]]
        r = limpia({**e, "ext": ext}, None)
        r["id"], r["sincro"] = e["id"], estado_inicial()
        evs.append(r)
        _guarda(evs)
    encola(r["id"])
    return publico(r)


# ---------- repeticiones ----------
def _mas_meses(d, n):
    m = d.month - 1 + n
    a, m = d.year + m // 12, m % 12 + 1
    try:
        return d.replace(year=a, month=m)
    except ValueError:
        return None   # el 31 en un mes de 30: ese mes no hay


def ocurrencias(e, desde, hasta):
    """Los días en que empieza cada repetición que toca [desde, hasta] (fechas ISO)."""
    d0 = date.fromisoformat(e["dia"])
    largo = (date.fromisoformat(e["fin_dia"]) - d0).days
    d_desde, d_hasta = date.fromisoformat(desde), date.fromisoformat(hasta)
    tope = min(d_hasta, date.fromisoformat(e["hasta"])) if e["hasta"] else d_hasta
    out, n = [], 0
    while n < 5000:
        if e["repite"] == "diario":
            d = d0 + timedelta(days=n)
        elif e["repite"] == "semanal":
            d = d0 + timedelta(weeks=n)
        elif e["repite"] == "mensual":
            d = _mas_meses(d0, n)
        elif e["repite"] == "anual":
            d = _mas_meses(d0, 12 * n)
        else:
            d = d0 if n == 0 else None
            if n:
                break
        n += 1
        if d is None:
            continue
        if d > tope:
            break
        if d + timedelta(days=largo) >= d_desde and d.isoformat() not in e["excepciones"]:
            out.append(d.isoformat())
    return out


def rango(desde, hasta):
    out = []
    for e in todos():
        largo = (date.fromisoformat(e["fin_dia"]) - date.fromisoformat(e["dia"])).days
        for d in ocurrencias(e, desde, hasta):
            out.append({**publico(e), "origen": e["dia"], "dia": d,
                        "fin_dia": (date.fromisoformat(d) + timedelta(days=largo)).isoformat()})
    return sorted(out, key=lambda x: (x["dia"], x["inicio"] or "", x["t"]))


# ---------- entrenos planeados ----------
def _bloques(r):
    l = []
    for b in r.get("bloques") or []:
        x = b.get("ej") or ""
        if b.get("series") and b.get("repes"):
            x += f" {b['series']}×{b['repes']}"
        elif b.get("seg"):
            x += f" {round(b['seg'] / 60)} min" if b["seg"] >= 60 else f" {b['seg']} s"
        if b.get("kg"):
            x += f" · {b['kg']} kg"
        l.append(f"- {x.strip()}" + (f" ({b['nota']})" if b.get("nota") else ""))
    return "\n".join(l)


# a qué hora entrena: unos 45 min después de avisos-antes (17:15 L-J, 14:45 V, 11:00 findes). La movilidad de la mañana, a las 7:30
HORA_ENTRENO = {0: "18:00", 1: "18:00", 2: "18:00", 3: "18:00", 4: "15:30", 5: "11:30", 6: "11:30"}
HORA_MANANA = "07:30"


def _minutos(r):
    """Lo que dura una rutina: lo cronometrado (carrera, movilidad) por sus bloques; las pesas, 1 h; lo demás, 1 h 30."""
    if r and r.get("tipo") in ("carrera", "movilidad"):
        s = sum(int(b.get("seg") or 0) for b in r.get("bloques") or [])
        if s:
            return max(10, round(s / 300) * 5)
    return 60 if not r or r.get("tipo") == "pesas" else 90


def _suma(hora, minutos):
    m = min(int(hora[:2]) * 60 + int(hora[3:]) + minutos, 23 * 60 + 59)
    return f"{m // 60:02d}:{m % 60:02d}"


def entrenos_deseados(estado, hoy):
    """{"dia:idHabito": {t, dia, cal, nota}} de lo planeado desde `hoy`. Un hábito es de entreno si tiene rutinas."""
    habs = {h.get("id"): h.get("n") for h in estado.get("habits") or []}
    rutinas = {r.get("id"): r for r in estado.get("rutinas") or []}
    deporte = {r.get("hab") for r in rutinas.values()}
    out = {}
    pie = "Del plan de Entreno (todo.yagotg.dev/entreno.html)"
    for dia, ids in (estado.get("plan") or {}).items():
        if not DIA.match(dia) or dia < hoy:
            continue
        del_dia = [(hid, rutinas.get(((estado.get("sesion") or {}).get(dia) or {}).get(hid)))
                   for hid in ids if hid in deporte and hid in habs]
        # el gimnasio o la carrera primero y el core detrás; la movilidad de la mañana, por la mañana
        manana = lambda r: bool(r) and r.get("tipo") == "movilidad" and "ma" in str(r.get("id"))[:3]
        del_dia.sort(key=lambda x: bool(x[1]) and x[1].get("tipo") == "movilidad")
        hora = HORA_ENTRENO[date.fromisoformat(dia).weekday()]
        for hid, r in del_dia:
            ini = HORA_MANANA if manana(r) else hora
            fin = _suma(ini, _minutos(r))
            if not manana(r):
                hora = fin
            # ya recortados como los dejará limpia(): si no, cada pasada los vería cambiados y los volvería a subir
            out[f"{dia}:{hid}"] = {"t": " ".join(str(r["n"] if r else habs[hid]).split())[:200], "dia": dia, "cal": "Deporte",
                                   "inicio": ini, "fin": fin,
                                   "nota": (_bloques(r)[:2000 - len(pie) - 2] + "\n\n" + pie) if r else pie}
    return out


def carrera_deseada(estado, hoy):
    """{"carrera:qué:día": evento} del plan de 5k (carrera.py) desde `hoy`: el día de la carrera, los tests y las
    fases. Van como los entrenos (los pone el plan, no se editan a mano). Solo si el plan está aplicado en este
    data.json (tiene sus rutinas): la copia de Aitana no lo tiene."""
    import carrera
    if not any(r.get("id") == carrera.RUTINA["suave"] for r in estado.get("rutinas") or []) or not carrera.habito_correr(estado):
        return {}
    try:
        inf = carrera.informe(estado, date.fromisoformat(hoy))
    except Exception:   # un data.json a medias: ya se cuadrará en la próxima pasada
        return {}
    pie = "Del plan de carrera (todo.yagotg.dev/carrera.html)"
    out = {}

    def pon(que, dia, t, nota, fin_dia=""):
        if dia >= hoy:
            out[f"carrera:{que}:{dia}"] = {"t": t[:200], "dia": dia, "fin_dia": fin_dia or dia, "cal": "Deporte",
                                         "nota": (nota + "\n\n" + pie)[:2000]}

    obj, est, proy = inf["objetivo"], inf["estimacion"]["seg"], inf["proyeccion"]
    pon("dia-d", obj["dia"], f"🏁 Carrera 5k · objetivo {carrera.mmss(obj['seg'])}",
        f"El 5k objetivo: bajar de {carrera.mmss(obj['seg'])}. Ahora estás en {carrera.mmss(est)} ({inf['estimacion']['fuente']})."
        + (f" {proy['texto']}." if proy.get("texto") else ""))
    fase_antes = None
    for w in inf["semanas"]:
        lun = date.fromisoformat(w["lunes"])
        dom = (lun + timedelta(days=6)).isoformat()
        if w["fase"] != fase_antes and fase_antes is not None:
            pon(f"fase-{w['fase'].lower()}", w["lunes"], f"🏃 Empieza la fase «{w['fase']}»",
                {"Específico": "Llegan las series y los tempos: se entrena el ritmo de carrera.",
                 "Afinar": "Menos volumen y algo de ritmo de carrera: llegar fresco al día D."}.get(w["fase"], ""))
        fase_antes = w["fase"]
        # las semanas de test y de descarga ya no van (23/11: eventos de semana entera, todo el día). El test sale en su
        # día como entreno («Test 5k») cuando carrera.py lo asigna
    return out


def cuadra_entrenos(estado=None, hoy=None):
    """Deja los eventos con `entreno` igual que el plan. Devuelve (creados, cambiados, borrados)."""
    hoy = hoy or date.today().isoformat()
    if estado is None:
        if ESTADO.parent != FICHERO.parent:   # un calendario de otra copia (la de Aitana sin TODO_CALENDARIO): no se toca
            return 0, 0, 0
        try:
            estado = json.loads(ESTADO.read_text("utf-8"))
        except (OSError, ValueError):
            return 0, 0, 0
    quiero = {**entrenos_deseados(estado, hoy), **carrera_deseada(estado, hoy)}
    encolar, fuera, n_nuevos = [], [], 0
    with _cerrojo:
        evs, quedan = todos(), []
        for e in evs:
            k = e.get("entreno")
            if not k or e["dia"] < hoy:
                quedan.append(e)
                continue
            d = quiero.pop(k, None)
            if d is None:   # quitado del plan (o repetido: el primero ya se llevó su sitio)
                fuera.append(e)
                continue
            if (e["t"], e["nota"], e["cal"], e["fin_dia"], e["inicio"], e["fin"]) != (
                    d["t"], d["nota"], d["cal"], d.get("fin_dia", e["dia"]), d.get("inicio", ""), d.get("fin", "")):
                e.update(t=d["t"], nota=d["nota"], cal=d["cal"], fin_dia=d.get("fin_dia", e["dia"]),
                         inicio=d.get("inicio", ""), fin=d.get("fin", ""), sincro=estado_inicial())
                encolar.append(e["id"])
            quedan.append(e)
        for k, d in sorted(quiero.items()):
            e = limpia({**d, "entreno": k})
            e["sincro"] = estado_inicial()
            quedan.append(e)
            encolar.append(e["id"])
            n_nuevos += 1
        if encolar or fuera:
            _guarda(quedan)
    for e in fuera:
        _borrados.put(e)
    for i in encolar:
        _cola.put(i)
    if encolar or fuera:
        _avisa()
    return n_nuevos, len(encolar) - n_nuevos, len(fuera)


_estado_visto = {"mtime": None}


def _mira_entrenos():
    """Desde el hilo: si data.json cambió (la web, Tom, el bot…) o cambió el día, cuadra los entrenos."""
    try:
        m = (ESTADO.stat().st_mtime, date.today().isoformat())
    except OSError:
        return
    if m != _estado_visto["mtime"]:
        _estado_visto["mtime"] = m
        cuadra_entrenos()


def avisa_estado():
    """main.py la llama al guardar data.json: el calendario se pone al día en segundos, no al minuto."""
    _avisa()


def calendarios():
    return [{"id": k, "n": n, "color": c} for k, (n, c) in CALENDARIOS.items()]


# ---------- la copia: Google e iCloud ----------
_google = None


def google():
    """El calendario.py del bot (cuenta de servicio de Google), cargado por ruta. None si no hay google.json."""
    global _google
    if _google is None and GOOGLE_MODULO.exists():
        spec = importlib.util.spec_from_file_location("calendario_google", GOOGLE_MODULO)
        _google = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(_google)
    return _google if _google and _google.hay() else None


def icloud_hay():
    return bool(os.getenv("ICLOUD_USER") and os.getenv("ICLOUD_PASS"))


def estado_inicial():
    return {"google": "pendiente" if GOOGLE_MODULO.with_name("google.json").exists() else "sin configurar",
            "icloud": "pendiente" if icloud_hay() else "sin configurar"}


def _fechas(e, dia=None):
    """Inicio y fin (datetime con zona, o date si es de todo el día) de la primera repetición."""
    d = date.fromisoformat(dia or e["dia"])
    fin_d = d + (date.fromisoformat(e["fin_dia"]) - date.fromisoformat(e["dia"]))
    if not e["inicio"]:
        return d, fin_d + timedelta(days=1)
    ini = datetime.fromisoformat(f"{d}T{e['inicio']}").replace(tzinfo=ZONA)
    if e["fin"]:
        fin = datetime.fromisoformat(f"{fin_d}T{e['fin']}").replace(tzinfo=ZONA)
    else:
        fin = (ini + timedelta(hours=1)) if fin_d == d else datetime.fromisoformat(f"{fin_d}T23:59").replace(tzinfo=ZONA)
    return ini, max(fin, ini + timedelta(minutes=15))


FREQ = {"diario": "DAILY", "semanal": "WEEKLY", "mensual": "MONTHLY", "anual": "YEARLY"}


def rrule(e):
    if not e["repite"]:
        return ""
    r = f"RRULE:FREQ={FREQ[e['repite']]}"
    if e["hasta"]:
        r += ";UNTIL=" + (e["hasta"].replace("-", "") if not e["inicio"] else
                          datetime.fromisoformat(f"{e['hasta']}T23:59:59").replace(tzinfo=ZONA)
                          .astimezone(timezone.utc).strftime("%Y%m%dT%H%M%SZ"))
    return r


def a_google(e):
    ini, fin = _fechas(e)
    cuando = (lambda x: {"date": x.isoformat()}) if not e["inicio"] else (lambda x: {"dateTime": x.isoformat(), "timeZone": str(ZONA)})
    cuerpo = {"summary": e["t"], "description": e["nota"], "location": e["lugar"], "start": cuando(ini), "end": cuando(fin),
              "reminders": {"useDefault": False, "overrides": [{"method": "popup", "minutes": e["aviso"]}] if e["aviso"] >= 0 else []}}
    rec = [rrule(e)] if e["repite"] else []
    if e["repite"] and e["excepciones"]:
        rec.append("EXDATE" + (";VALUE=DATE:" + ",".join(x.replace("-", "") for x in e["excepciones"]) if not e["inicio"] else
                               f";TZID={ZONA}:" + ",".join(x.replace("-", "") + "T" + e["inicio"].replace(":", "") + "00" for x in e["excepciones"])))
    if rec:
        cuerpo["recurrence"] = rec
    if e.get("entreno"):   # el resumen de la mañana ya los cuenta en «Hoy toca»: así los reconoce y no los repite
        cuerpo["extendedProperties"] = {"private": {"todo_entreno": e["entreno"]}}
    return cuerpo


def _esc(s):
    return str(s).replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\n", "\\n")


VTIMEZONE = """BEGIN:VTIMEZONE
TZID:Europe/Madrid
BEGIN:DAYLIGHT
TZOFFSETFROM:+0100
TZOFFSETTO:+0200
TZNAME:CEST
DTSTART:19700329T020000
RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU
END:DAYLIGHT
BEGIN:STANDARD
TZOFFSETFROM:+0200
TZOFFSETTO:+0100
TZNAME:CET
DTSTART:19701025T030000
RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU
END:STANDARD
END:VTIMEZONE"""


def a_ics(e, ahora=None):
    ini, fin = _fechas(e)
    fecha = (lambda k, x: f"{k};VALUE=DATE:{x:%Y%m%d}") if not e["inicio"] else (lambda k, x: f"{k};TZID=Europe/Madrid:{x:%Y%m%dT%H%M%S}")
    l = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//yagotg.dev//todo//ES", "CALSCALE:GREGORIAN"]
    if e["inicio"]:
        l.append(VTIMEZONE)
    l += ["BEGIN:VEVENT", f"UID:{e['id']}@todo.yagotg.dev",
          f"DTSTAMP:{(ahora or datetime.now(timezone.utc)):%Y%m%dT%H%M%SZ}", fecha("DTSTART", ini), fecha("DTEND", fin),
          f"SUMMARY:{_esc(e['t'])}"]
    if e["nota"]:
        l.append(f"DESCRIPTION:{_esc(e['nota'])}")
    if e["lugar"]:
        l.append(f"LOCATION:{_esc(e['lugar'])}")
    if e["repite"]:
        l.append(rrule(e))
        for x in e["excepciones"]:
            l.append(f"EXDATE;VALUE=DATE:{x.replace('-', '')}" if not e["inicio"] else
                     f"EXDATE;TZID=Europe/Madrid:{x.replace('-', '')}T{e['inicio'].replace(':', '')}00")
    if e["aviso"] >= 0:
        l += ["BEGIN:VALARM", "ACTION:DISPLAY", f"DESCRIPTION:{_esc(e['t'])}", f"TRIGGER:-PT{e['aviso']}M", "END:VALARM"]
    l += ["END:VEVENT", "END:VCALENDAR"]
    return "\r\n".join(l) + "\r\n"


# ---- CalDAV de iCloud: descubrir los calendarios una vez y luego PUT/DELETE de cada evento .ics ----
_icloud = {"cals": None}
NS = {"d": "DAV:", "c": "urn:ietf:params:xml:ns:caldav", "a": "http://apple.com/ns/ical/"}


def _dav(metodo, url, cuerpo=None, prof=None, tipo="application/xml; charset=utf-8"):
    h = {"Authorization": "Basic " + base64.b64encode(f"{os.getenv('ICLOUD_USER')}:{os.getenv('ICLOUD_PASS')}".encode()).decode(),
         "Content-Type": tipo}
    if prof is not None:
        h["Depth"] = str(prof)
    req = urllib.request.Request(url, data=cuerpo.encode() if isinstance(cuerpo, str) else cuerpo, method=metodo, headers=h)
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.status, r.read(), r.geturl()


def _href(xml_, ruta):
    el = ET.fromstring(xml_).find(ruta, NS)
    return el.text.strip() if el is not None and el.text else ""


def icloud_calendarios():
    """{nombre en minúsculas: url} de los calendarios de eventos de iCloud (se descubre la primera vez)."""
    if _icloud["cals"] is not None:
        return _icloud["cals"]
    base = "https://caldav.icloud.com"
    _, x, _ = _dav("PROPFIND", base + "/", '<d:propfind xmlns:d="DAV:"><d:prop><d:current-user-principal/></d:prop></d:propfind>', 0)
    principal = _href(x, ".//d:current-user-principal/d:href")
    _, x, _ = _dav("PROPFIND", base + principal, '<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
                   '<d:prop><c:calendar-home-set/></d:prop></d:propfind>', 0)
    casa = _href(x, ".//c:calendar-home-set/d:href")
    casa = casa if casa.startswith("http") else base + casa
    _, x, _ = _dav("PROPFIND", casa, '<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop><d:displayname/>'
                   '<d:resourcetype/><c:supported-calendar-component-set/></d:prop></d:propfind>', 1)
    cals = {}
    raiz = casa.split("/", 3)[:3]
    for r in ET.fromstring(x).findall("d:response", NS):
        if r.find(".//d:resourcetype/c:calendar", NS) is None:
            continue
        comps = [c.get("name") for c in r.findall(".//c:supported-calendar-component-set/c:comp", NS)]
        if comps and "VEVENT" not in comps:
            continue   # los de recordatorios (VTODO) no
        href = r.find("d:href", NS).text.strip()
        nombre = (r.find(".//d:displayname", NS).text or "").strip() if r.find(".//d:displayname", NS) is not None else ""
        cals[nombre.lower() or href] = href if href.startswith("http") else "/".join(raiz) + href
    _icloud["cals"] = cals
    return cals


# Lo dijo Yago (17/11): ocio a «ocio !!», trabajo a «trabajo yaguito», vacaciones a «vacations»,
# cumpleaños a «calendar». Nombres exactos de iCloud; mandan sobre el parecido.
ALIAS_ICLOUD = {"day-to-day": "daytoday yago", "universidad": "estudio", "ocio": "ocio !!", "musica": "ocio !!",
                "trabajo": "trabajo yaguito", "vacaciones": "vacations", "cumples": "calendar"}   # «Deporte»: el de iCloud que se llame así, o el de por defecto


def icloud_destino(cal):
    cals = icloud_calendarios()
    if not cals:
        raise RuntimeError("no encuentro calendarios en iCloud")
    # ICLOUD_MAPA="universidad=estudio,musica=ocio !!" manda; luego el mismo nombre (sin guiones ni
    # espacios, y vale que el de iCloud lo contenga: day-to-day -> «daytoday yago»), luego un alias,
    # luego ICLOUD_CALENDARIO y por último el calendario por defecto de iCloud («calendar»).
    mapa = dict(par.split("=", 1) for par in os.getenv("ICLOUD_MAPA", "").split(",") if "=" in par)
    if mapa.get(cal, "").strip().lower() in cals:
        return cals[mapa[cal].strip().lower()]
    if ALIAS_ICLOUD.get(cal) in cals:
        return cals[ALIAS_ICLOUD[cal]]
    plano = lambda s: re.sub(r"[^a-z0-9áéíóúñ]", "", s.lower())
    for nombre in (cal, CALENDARIOS[cal][0]):
        if not plano(nombre):
            continue
        for suyo, url in cals.items():
            if plano(suyo) == plano(nombre) or plano(suyo).startswith(plano(nombre)):
                return url
    for nombre in (os.getenv("ICLOUD_CALENDARIO", "").lower(), "calendar", "calendario"):
        if nombre and nombre in cals:
            return cals[nombre]
    return next(iter(cals.values()))


# ---- el hilo que copia ----
_cola = queue.Queue()
_borrados = queue.Queue()
_hay_trabajo = threading.Event()


def encola(id_):
    _cola.put(id_)
    _avisa()


def _avisa():
    _hay_trabajo.set()
    _arranca()


def _error(ex):
    if isinstance(ex, urllib.error.HTTPError):
        pista = {401: "las credenciales no valen", 403: "sin permiso para escribir (compártelo con «Hacer cambios en eventos»)",
                 404: "no encuentro el calendario (¿está compartido con la cuenta de servicio?)"}.get(ex.code, "")
        return f"error: {ex.code} {pista}".strip()
    return f"error: {str(ex)[:120]}"


def _gcal(g, cal):
    """El id del calendario de Google; los que no tienen uno propio allí (ocio, trabajo…) van al de day-to-day."""
    return urllib.parse.quote(g.CALENDARIOS.get(cal) or g.CALENDARIOS["day-to-day"])


def _copia(e):
    """Escribe (o reescribe) un evento en Google y en iCloud. Devuelve (ext, sincro)."""
    ext, sincro = dict(e.get("ext") or {}), {}
    g = google()
    if e.get("entreno"):
        # los entrenos y el plan de carrera, solo a iCloud (23/11: en el iPhone salían dos veces, Google e iCloud);
        # si tenía copia en Google, se borra
        try:
            if g is not None and ext.get("google"):
                try:
                    g._api("DELETE", f"calendars/{_gcal(g, e['cal'])}/events/{ext['google']}")
                except urllib.error.HTTPError as ex:
                    if ex.code not in (404, 410):
                        raise
            ext.pop("google", None)
            sincro["google"] = "solo iCloud"
        except Exception as ex:
            sincro["google"] = _error(ex)
    elif g is None:
        sincro["google"] = "sin configurar"
    else:
        try:
            cid = _gcal(g, e["cal"])
            viejo = ext.get("mover_de")
            if viejo and ext.get("google") and _gcal(g, viejo) != cid:
                try:
                    g._api("DELETE", f"calendars/{_gcal(g, viejo)}/events/{ext['google']}")
                except urllib.error.HTTPError:
                    pass
                ext.pop("google", None)
            if ext.get("google"):
                g._api("PUT", f"calendars/{cid}/events/{ext['google']}", a_google(e))
            else:
                ext["google"] = g._api("POST", f"calendars/{cid}/events", a_google(e))["id"]
            sincro["google"] = "ok"
        except Exception as ex:
            sincro["google"] = _error(ex)
    if not icloud_hay():
        sincro["icloud"] = "sin configurar"
    else:
        try:
            destino = icloud_destino(e["cal"])
            href = destino.rstrip("/") + f"/{e['id']}.ics"
            if ext.get("icloud") and ext["icloud"] != href:
                try:
                    _dav("DELETE", ext["icloud"])
                except urllib.error.HTTPError:
                    pass
            _dav("PUT", href, a_ics(e), tipo="text/calendar; charset=utf-8")
            ext["icloud"] = href
            sincro["icloud"] = "ok"
        except Exception as ex:
            sincro["icloud"] = _error(ex)
    ext.pop("mover_de", None)
    return ext, sincro


def _quita(e):
    ext = e.get("ext") or {}
    g = google()
    if g and ext.get("google"):   # (un entreno de antes del 23/11 aún puede tenerla)
        try:
            g._api("DELETE", f"calendars/{_gcal(g, e['cal'])}/events/{ext['google']}")
        except urllib.error.HTTPError as ex:
            if ex.code not in (404, 410):
                raise
    if icloud_hay() and ext.get("icloud"):
        try:
            _dav("DELETE", ext["icloud"])
        except urllib.error.HTTPError as ex:
            if ex.code != 404:
                raise


def sincroniza_una(id_):
    with _cerrojo:
        e = next((x for x in todos() if x["id"] == id_), None)
    if e is None:
        return
    ext, sincro = _copia(e)
    with _cerrojo:   # se guarda sobre lo último: entre tanto pudo cambiar otra cosa del fichero
        evs = todos()
        for x in evs:
            if x["id"] == id_:
                x["ext"], x["sincro"] = ext, sincro
        _guarda(evs)


def _bucle():
    ultimo_reintento = 0
    while True:
        _hay_trabajo.wait(timeout=60)
        _hay_trabajo.clear()
        try:
            _mira_entrenos()
        except Exception as ex:
            print("agenda: entrenos", ex, flush=True)
        while not _borrados.empty():
            e = _borrados.get()
            try:
                _quita(e)
            except Exception as ex:
                print("agenda: no se pudo borrar fuera", e["id"], ex, flush=True)
        vistos = set()
        while not _cola.empty():
            id_ = _cola.get()
            if id_ not in vistos:
                vistos.add(id_)
                try:
                    sincroniza_una(id_)
                except Exception as ex:
                    print("agenda:", id_, ex, flush=True)
        if time.time() - ultimo_reintento > 600:   # lo que falló o quedó pendiente (sin red, la Pi reiniciada…)
            ultimo_reintento = time.time()
            for e in todos():
                if any(v == "pendiente" or v.startswith("error") for v in (e.get("sincro") or {}).values()):
                    _cola.put(e["id"])
            if not _cola.empty():
                _hay_trabajo.set()


_hilo = None


def _arranca():
    global _hilo
    if _hilo is None and not os.getenv("AGENDA_SIN_HILO"):
        _hilo = threading.Thread(target=_bucle, daemon=True)
        _hilo.start()

