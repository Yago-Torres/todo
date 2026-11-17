"""El calendario de todo: eventos propios (calendario.json) que se COPIAN a Google Calendar y a iCloud.

Solo de ida: lo que se apunta aquí se escribe allí (y se cambia o se borra allí si se cambia o se borra aquí), pero
lo que se crea en Google o en el iPhone no vuelve. Las tareas y los recordatorios con fecha no viven aquí: son
tareas del vault (vault.py) y la página las enseña en su día.

- calendario.json va aparte de data.json: clean() se lo llevaría en el siguiente PUT.
- La copia va en un hilo (`sincroniza`): la API contesta al momento y cada evento lleva su estado en `sincro`
  ("ok", "pendiente", "error: …", "sin configurar"). Lo que falla se reintenta cada 10 minutos.
- Google: la cuenta de servicio del bot (~/bots/todo-bot/google.json y su calendario.py, que se carga por ruta).
- iCloud: CalDAV con el Apple ID y una contraseña específica de app (ICLOUD_USER e ICLOUD_PASS en el .env).
  Cada calendario de todo va al de iCloud con el mismo nombre; si no hay, al primero (o ICLOUD_CALENDARIO).
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
GOOGLE_MODULO = Path(os.getenv("GOOGLE_CALENDARIO", "/home/pi/bots/todo-bot/calendario.py"))
ZONA = ZoneInfo("Europe/Madrid")
# id (el mismo nombre que en el bot y en Google) -> nombre y color
CALENDARIOS = {"day-to-day": ("Día a día", "#3B82F6"), "Deporte": ("Deporte", "#16A34A"),
               "universidad": ("Universidad", "#9333EA"), "musica": ("Música", "#EA580C"),
               "ensayos": ("Ensayos", "#DB2777")}
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


def icloud_destino(cal):
    cals = icloud_calendarios()
    if not cals:
        raise RuntimeError("no encuentro calendarios en iCloud")
    defecto = os.getenv("ICLOUD_CALENDARIO", "").lower()
    for nombre in (cal.lower(), CALENDARIOS[cal][0].lower(), defecto):
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


def _copia(e):
    """Escribe (o reescribe) un evento en Google y en iCloud. Devuelve (ext, sincro)."""
    ext, sincro = dict(e.get("ext") or {}), {}
    g = google()
    if g is None:
        sincro["google"] = "sin configurar"
    else:
        try:
            cid = urllib.parse.quote(g.CALENDARIOS[e["cal"]])
            viejo = ext.get("mover_de")
            if viejo and ext.get("google"):
                try:
                    g._api("DELETE", f"calendars/{urllib.parse.quote(g.CALENDARIOS[viejo])}/events/{ext['google']}")
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
    if g and ext.get("google"):
        try:
            g._api("DELETE", f"calendars/{urllib.parse.quote(g.CALENDARIOS[e['cal']])}/events/{ext['google']}")
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

