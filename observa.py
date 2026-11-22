"""Observabilidad de la Pi: qué pasa, cuánto se usa, cuánto consume y cuántas veces falla. Lo pidió Yago el 22/11.

`recoge()` (observa.timer, cada 5 min) apunta en observa.db (junto a data.json, fuera del repo):
- `muestra(t, clave, valor)`: la Pi (carga, memoria, temperatura, disco, bajones de tensión), servicios en marcha,
  latencia de las webs (las locales y las públicas de sites-check), Docker, errores en los logs por servicio, horas
  desde la última copia al pendrive.
- `evento(t, tipo, quien, detalle)`: lo que falla: un servicio que se reinicia o cae, un timer que acaba mal, un
  contenedor que se reinicia o deja de estar sano.
Las webs apuntan solas sus peticiones (metricas.py → tabla `http`). El gasto de Claude sale de claude-uso.jsonl
(claude-medido) y el uso de uso.jsonl (uso.py): se leen al pedir el panel, no se copian.

`panel(dias)` lo junta todo para GET /api/sistema y la página /sistema.html.

    python observa.py --recoge      # lo que lanza el timer
    python observa.py --panel       # el JSON del panel (7 días)
"""
import json
import os
import re
import sqlite3
import subprocess
import sys
import time
import urllib.request
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path

HERE = Path(__file__).parent
DB = Path(os.getenv("OBSERVA_DB", str(HERE / "observa.db")))
ESTADO = DB.with_name("observa-estado.json")
CLAUDE_USO = Path.home() / ".local/state/claude-uso.jsonl"
USO = Path(os.getenv("TODO_USO") or HERE / "uso.jsonl")
SITES = Path("/var/lib/pistatus/sites.json")
ULTIMA_COPIA = Path("/mnt/backups/ULTIMA.txt")
GUARDA_DIAS = 90
# las webs que se miden desde dentro (lo de fuera lo mide sites-check.py cada hora)
WEBS = {"todo": "http://127.0.0.1:8082/", "todo-aitana": "http://127.0.0.1:8087/", "gastos": "http://127.0.0.1:8085/",
        "gastos-aitana": "http://127.0.0.1:8086/", "home-assistant": "http://127.0.0.1:8123/manifest.json",
        "filebrowser": "http://127.0.0.1:3002/health", "pistatus": "http://192.168.1.70:8099/"}
# lo que no es nuestro aunque viva en /etc/systemd/system
AJENOS = re.compile(r"^(dbus-|display-manager|sshd|ip6?tables|userconfig|wayvnc)")
PINTA_ERROR = re.compile(r"Traceback \(most recent call last\)|\b(Error|Exception)\b|\berror:|\bfall[oó]\b|no he podido|"
                         r"se ha roto|\bfailed\b|HTTP Error [45]\d\d|Connection refused|timed out", re.I)


def sh(*cmd, tiempo=60):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=tiempo)
        return r.stdout
    except Exception:
        return ""


def conecta():
    c = sqlite3.connect(DB, timeout=10)
    c.execute("PRAGMA journal_mode=WAL")
    c.execute("CREATE TABLE IF NOT EXISTS muestra (t INTEGER, clave TEXT, valor REAL)")
    c.execute("CREATE INDEX IF NOT EXISTS muestra_t ON muestra (clave, t)")
    c.execute("CREATE TABLE IF NOT EXISTS evento (t INTEGER, tipo TEXT, quien TEXT, detalle TEXT)")
    c.execute("CREATE INDEX IF NOT EXISTS evento_t ON evento (t)")
    c.execute("""CREATE TABLE IF NOT EXISTS http (minuto TEXT, app TEXT, grupo TEXT, n INTEGER, e5 INTEGER, e4 INTEGER,
                 ms_sum REAL, ms_max REAL, lentas INTEGER, PRIMARY KEY (minuto, app, grupo))""")
    return c


def _estado():
    try:
        return json.loads(ESTADO.read_text("utf-8"))
    except (OSError, ValueError):
        return {}


# ---------- lo que se recoge ----------
def unidades():
    """Nuestros servicios y timers: los ficheros de verdad de /etc/systemd/system (no los enlaces del sistema)."""
    d = Path("/etc/systemd/system")
    srv, tim = [], []
    for f in sorted(d.iterdir()):
        if f.is_symlink() or not f.is_file() or AJENOS.match(f.name) or "@" in f.name:
            continue
        (srv if f.suffix == ".service" else tim if f.suffix == ".timer" else []).append(f.stem)
    return srv, tim


def propiedades(unidad, *props):
    out = sh("systemctl", "show", unidad, "--timestamp=unix", *[f"-p{p}" for p in props])
    return dict(l.split("=", 1) for l in out.splitlines() if "=" in l)


def _ts(v):
    m = re.search(r"@(\d+)", v or "")
    return int(m.group(1)) if m else 0


def _caido(p):
    """Caído: ha fallado, o está parado uno que debería seguir en marcha (los que se reinician solos). Uno que se
    ejecuta una vez al arrancar y termina bien (mantenimiento-arranque) no está caído."""
    return p.get("ActiveState") == "failed" or (p.get("ActiveState") != "active" and p.get("Restart") not in ("no", "", None))


def pi():
    m = {}
    try:
        m["carga"] = float(Path("/proc/loadavg").read_text().split()[0])
        info = dict(l.split(":", 1) for l in Path("/proc/meminfo").read_text().splitlines() if ":" in l)
        m["memoria_libre_mb"] = int(info["MemAvailable"].split()[0]) // 1024
    except (OSError, ValueError, KeyError):
        pass
    t = re.search(r"temp=([\d.]+)", sh("vcgencmd", "measure_temp"))
    if t:
        m["temperatura"] = float(t.group(1))
    g = re.search(r"throttled=(0x[0-9a-f]+)", sh("vcgencmd", "get_throttled"))
    if g:
        v = int(g.group(1), 16)
        m["tension_baja_ahora"] = float(bool(v & 0x1))
        m["frenada_ahora"] = float(bool(v & 0x6))
    st = os.statvfs("/")
    m["disco_libre_gb"] = round(st.f_bavail * st.f_frsize / 2**30, 1)
    return m


def latencias():
    out = {}
    for n, u in WEBS.items():
        t0 = time.perf_counter()
        try:
            with urllib.request.urlopen(urllib.request.Request(u), timeout=10) as r:
                codigo = r.status
        except urllib.error.HTTPError as e:
            codigo = e.code
        except Exception:
            codigo = 0
        out[n] = (round((time.perf_counter() - t0) * 1000), codigo)
    try:   # las públicas (pasando por Cloudflare): las mide sites-check.py
        for n, v in json.loads(SITES.read_text("utf-8")).items():
            if m := re.search(r"(\d{3}) · (\d+) ms", str(v)):
                out[f"fuera:{n}"] = (int(m.group(2)), int(m.group(1)))
    except (OSError, ValueError):
        pass
    return out


def recoge(ahora=None):
    ahora = int(ahora or time.time())
    st = _estado()
    desde = st.get("t", ahora - 300)
    muestras, eventos = [], []
    for k, v in pi().items():
        muestras.append((ahora, f"pi:{k}", v))
    # los bajones de tensión del kernel desde la última vuelta
    bajones = sh("journalctl", "-k", "--since", f"@{desde}", "--no-pager", "-o", "cat", "-g", "Undervoltage detected").count("Undervoltage")
    muestras.append((ahora, "pi:bajones", bajones))

    # servicios: en marcha, reinicios (NRestarts sube) y caídas
    srv, tim = unidades()
    reinicios = st.get("reinicios", {})
    abajo = []
    timers_activados = set()
    for t in tim:
        p = propiedades(f"{t}.timer", "Unit")
        timers_activados.add((p.get("Unit") or f"{t}.service").removesuffix(".service"))
    for s in srv:
        p = propiedades(f"{s}.service", "ActiveState", "SubState", "Result", "NRestarts", "Type", "Restart",
                        "ExecMainStartTimestamp", "ExecMainExitTimestamp", "UnitFileState")
        n = int(p.get("NRestarts") or 0)
        if s in reinicios and n > reinicios[s]:
            eventos.append((ahora, "reinicio", s, f"se ha reiniciado {n - reinicios[s]} vez/veces solo (tras un fallo)"))
        reinicios[s] = n
        de_timer = s in timers_activados or p.get("Type") == "oneshot"
        if not de_timer and p.get("UnitFileState") == "enabled" and _caido(p):
            abajo.append(s)
            if s not in st.get("caidos", []):
                eventos.append((ahora, "caido", s, f"no está en marcha ({p.get('ActiveState')}/{p.get('SubState')})"))
        # un timer que acabó mal desde la última vuelta
        fin = _ts(p.get("ExecMainExitTimestamp"))
        if de_timer and p.get("Result") not in ("success", "", None) and fin > desde:
            eventos.append((ahora, "timer", s, f"acabó mal ({p.get('Result')})"))
    st["caidos"] = abajo
    st["reinicios"] = reinicios
    muestras.append((ahora, "servicios:caidos", len(abajo)))
    muestras.append((ahora, "servicios:total", len([s for s in srv if s not in timers_activados])))

    # errores en los logs por servicio desde la última vuelta: lo marcado como error (cualquier servicio) y, en los
    # nuestros, las líneas con pinta de error: Python escribe sus tracebacks por la salida normal y systemd los guarda
    # como información, no como error
    errores, vistos = defaultdict(int), set()
    nuestros = [f"{s}.service" for s in srv]
    salidas = (sh("journalctl", "-p", "err", "--since", f"@{desde}", "--no-pager", "-o", "json", tiempo=120),
               sh("journalctl", *[a for u in nuestros for a in ("-u", u)], "--since", f"@{desde}", "--no-pager", "-o", "json",
                  tiempo=120))
    for i, salida in enumerate(salidas):
        for l in salida.splitlines():
            try:
                j = json.loads(l)
            except ValueError:
                continue
            if j.get("__CURSOR") in vistos:
                continue
            msg = j.get("MESSAGE") if isinstance(j.get("MESSAGE"), str) else ""
            if i == 1 and (not PINTA_ERROR.search(msg) or j.get("_COMM") == "systemd"):
                continue
            vistos.add(j.get("__CURSOR"))
            quien = (j.get("_SYSTEMD_UNIT") or j.get("SYSLOG_IDENTIFIER") or "?").removesuffix(".service")
            errores[quien] += 1
    for quien, n in errores.items():
        muestras.append((ahora, f"errores:{quien}", n))

    # docker: sanos y reinicios
    dk = st.get("docker", {})
    sanos = total = 0
    for linea in sh("docker", "ps", "-a", "--format", "{{.Names}}|{{.Status}}").splitlines():
        n, _, estado = linea.partition("|")
        if estado.startswith("Exited (0)"):
            continue   # los de una vez (migraciones)
        total += 1
        sano = estado.startswith("Up") and "unhealthy" not in estado
        sanos += sano
        rc = int((sh("docker", "inspect", "-f", "{{.RestartCount}}", n).strip() or 0))
        if n in dk and rc > dk[n]:
            eventos.append((ahora, "docker", n, f"se ha reiniciado {rc - dk[n]} vez/veces"))
        if not sano and n not in st.get("docker_mal", []):
            eventos.append((ahora, "docker", n, f"no está sano: {estado[:60]}"))
        dk[n] = rc
    st["docker"] = dk
    st["docker_mal"] = [l.split("|")[0] for l in sh("docker", "ps", "-a", "--format", "{{.Names}}|{{.Status}}").splitlines()
                        if not l.split("|")[1].startswith(("Up", "Exited (0)")) or "unhealthy" in l]
    muestras += [(ahora, "docker:sanos", sanos), (ahora, "docker:total", total)]

    for n, (ms, codigo) in latencias().items():
        muestras.append((ahora, f"web:{n}", ms if 0 < codigo < 500 else -1))   # -1 = no contesta

    try:
        dia = datetime.fromisoformat(ULTIMA_COPIA.read_text().split()[0] + "T" + ULTIMA_COPIA.read_text().split()[1])
        muestras.append((ahora, "copia:horas", round((datetime.now() - dia).total_seconds() / 3600, 1)))
    except (OSError, ValueError, IndexError):
        pass

    c = conecta()
    try:
        with c:
            c.executemany("INSERT INTO muestra VALUES (?,?,?)", muestras)
            c.executemany("INSERT INTO evento VALUES (?,?,?,?)", eventos)
            limite = ahora - GUARDA_DIAS * 86400
            c.execute("DELETE FROM muestra WHERE t < ?", (limite,))
            c.execute("DELETE FROM evento WHERE t < ?", (limite,))
            c.execute("DELETE FROM http WHERE minuto < ?", (time.strftime("%Y-%m-%dT%H:%M", time.localtime(limite)),))
    finally:
        c.close()
    st["t"] = ahora
    tmp = ESTADO.with_suffix(".tmp")
    tmp.write_text(json.dumps(st, ensure_ascii=False), "utf-8")
    tmp.replace(ESTADO)
    return len(muestras), eventos


# ---------- el panel ----------
def _hora(ts):
    return datetime.fromtimestamp(ts).strftime("%Y-%m-%dT%H:00")


def timers():
    """Cada timer nuestro: cuándo fue la última vez, cómo acabó, cuánto tardó y cuándo toca la próxima."""
    out = []
    try:
        lista = {x["unit"].removesuffix(".timer"): x for x in json.loads(sh("systemctl", "list-timers", "--all", "-o", "json") or "[]")}
    except ValueError:
        lista = {}
    _, tim = unidades()
    for t in tim:
        x = lista.get(t, {})
        svc = (x.get("activates") or f"{t}.service").removesuffix(".service")
        p = propiedades(f"{svc}.service", "Result", "ExecMainStartTimestamp", "ExecMainExitTimestamp", "ExecMainStatus")
        ini, fin = _ts(p.get("ExecMainStartTimestamp")), _ts(p.get("ExecMainExitTimestamp"))
        ultima = max(int(x["last"] / 1e6) if x.get("last") else 0, ini)   # lo lanzó el timer o se lanzó a mano
        out.append({"timer": t, "servicio": svc, "ultima": ultima or None,
                    "proxima": int(x["next"] / 1e6) if x.get("next") else None,
                    "resultado": (p.get("Result") or "") if ultima else "", "codigo": p.get("ExecMainStatus") or "",
                    "segundos": fin - ini if fin >= ini > 0 else None})
    return sorted(out, key=lambda x: x["proxima"] or 9e12)


def servicios(c, desde):
    srv, tim = unidades()
    activados = set()
    for t in tim:
        activados.add((propiedades(f"{t}.timer", "Unit").get("Unit") or f"{t}.service").removesuffix(".service"))
    err = dict(c.execute("SELECT substr(clave, 9), SUM(valor) FROM muestra WHERE clave LIKE 'errores:%' AND t >= ? GROUP BY 1",
                         (desde,)).fetchall())
    rein = defaultdict(int)
    for quien, n in c.execute("SELECT quien, COUNT(*) FROM evento WHERE tipo = 'reinicio' AND t >= ? GROUP BY quien", (desde,)):
        rein[quien] = n
    out = []
    for s in srv:
        if s in activados:
            continue
        p = propiedades(f"{s}.service", "ActiveState", "ActiveEnterTimestamp", "UnitFileState", "Type", "Restart")
        if p.get("Type") == "oneshot" or (p.get("ActiveState") != "active" and (not _caido(p) or p.get("UnitFileState") != "enabled")):
            continue   # los de una vez (al arrancar, o a mano) y los desactivados a propósito no son servicios que vigilar
        out.append({"servicio": s, "estado": p.get("ActiveState"), "desde": _ts(p.get("ActiveEnterTimestamp")) or None,
                    "activado": p.get("UnitFileState") == "enabled", "errores": int(err.get(s, 0)), "reinicios": rein.get(s, 0)})
    return out


def claude(desde):
    por_dia, por_quien = defaultdict(lambda: defaultdict(float)), defaultdict(lambda: [0, 0.0])
    try:
        for l in CLAUDE_USO.read_text("utf-8").splitlines():
            try:
                x = json.loads(l)
            except ValueError:
                continue
            t = datetime.fromisoformat(str(x.get("t"))[:19])
            if t.timestamp() < desde:
                continue
            q, usd = x.get("quien") or "?", float(x.get("usd") or 0)
            por_dia[t.date().isoformat()][q] += usd
            por_quien[q][0] += 1
            por_quien[q][1] += usd
    except OSError:
        pass
    return ({d: {q: round(v, 3) for q, v in qs.items()} for d, qs in sorted(por_dia.items())},
            [{"quien": q, "llamadas": n, "usd": round(u, 2)} for q, (n, u) in sorted(por_quien.items(), key=lambda kv: -kv[1][1])])


def uso_dias(desde):
    """Lo que hiciste tú (sin lo automático), por día y por canal: Tom, web, Telegram…"""
    por = defaultdict(lambda: defaultdict(int))
    try:
        for l in USO.read_text("utf-8").splitlines():
            try:
                x = json.loads(l)
            except ValueError:
                continue
            if x.get("auto") or str(x.get("que", "")).startswith("aviso:"):
                continue
            t = datetime.fromisoformat(str(x.get("t"))[:19])
            if t.timestamp() >= desde:
                por[t.date().isoformat()][x.get("cli") or "?"] += 1
    except OSError:
        pass
    return {d: dict(v) for d, v in sorted(por.items())}


def panel(dias=7, ahora=None):
    ahora = int(ahora or time.time())
    desde = ahora - dias * 86400
    dia_atras = ahora - 86400
    c = conecta()
    try:
        # peticiones por hora y app
        http = defaultdict(lambda: defaultdict(lambda: [0, 0, 0, 0.0, 0.0]))
        grupos = defaultdict(lambda: [0, 0, 0.0, 0.0])
        min_desde = time.strftime("%Y-%m-%dT%H:%M", time.localtime(desde))
        for minuto, app, grupo, n, e5, e4, ms_sum, ms_max, lentas in c.execute(
                "SELECT minuto, app, grupo, n, e5, e4, ms_sum, ms_max, lentas FROM http WHERE minuto >= ?", (min_desde,)):
            h = http[minuto[:13] + ":00"][app]
            h[0] += n; h[1] += e5; h[2] += e4; h[3] += ms_sum; h[4] = max(h[4], ms_max)
            g = grupos[(app, grupo)]
            g[0] += n; g[1] += e5; g[2] += ms_sum; g[3] = max(g[3], ms_max)
        serie_http = {hora: {app: {"n": v[0], "e5": v[1], "e4": v[2], "ms": round(v[3] / v[0]) if v[0] else 0, "max": round(v[4])}
                             for app, v in apps.items()} for hora, apps in sorted(http.items())}
        lentos = sorted(({"app": a, "grupo": g, "n": v[0], "e5": v[1], "ms": round(v[2] / v[0]) if v[0] else 0, "max": round(v[3])}
                         for (a, g), v in grupos.items()), key=lambda x: -x["ms"])[:12]
        # muestras por hora (media; los errores y bajones, suma)
        serie = defaultdict(dict)
        for clave, hora, v in c.execute(
                """SELECT clave, strftime('%Y-%m-%dT%H:00', t, 'unixepoch', 'localtime') AS h,
                   CASE WHEN clave LIKE 'errores:%' OR clave = 'pi:bajones' THEN SUM(valor) ELSE AVG(valor) END
                   FROM muestra WHERE t >= ? GROUP BY clave, h""", (desde,)):
            serie[clave][hora] = round(v, 2)
        ultimo = dict(c.execute("""SELECT clave, valor FROM muestra m WHERE t = (SELECT MAX(t) FROM muestra WHERE clave = m.clave)
                                   AND t >= ?""", (ahora - 3600,)).fetchall())
        eventos = [{"t": t, "tipo": tipo, "quien": q, "detalle": d}
                   for t, tipo, q, d in c.execute("SELECT * FROM evento WHERE t >= ? ORDER BY t DESC LIMIT 200", (desde,))]
        tabla_servicios = servicios(c, dia_atras)
        hoy_http = c.execute("SELECT SUM(n), SUM(e5), SUM(ms_sum) FROM http WHERE minuto >= ?",
                             (time.strftime("%Y-%m-%dT%H:%M", time.localtime(dia_atras)),)).fetchone()
        errores_24 = c.execute("SELECT COALESCE(SUM(valor), 0) FROM muestra WHERE clave LIKE 'errores:%' AND t >= ?",
                               (dia_atras,)).fetchone()[0]
        bajones = c.execute("SELECT COALESCE(SUM(valor), 0) FROM muestra WHERE clave = 'pi:bajones' AND t >= ?", (desde,)).fetchone()[0]
    finally:
        c.close()
    tabla_timers = timers()
    claude_dia, claude_quien = claude(desde)
    mes = claude(ahora - 30 * 86400)[1]
    n24, e5_24, ms24 = hoy_http or (0, 0, 0)
    return {
        "generado": ahora, "dias": dias,
        "ahora": {
            "servicios": {"total": len(tabla_servicios), "en_marcha": sum(1 for s in tabla_servicios if s["estado"] == "active")},
            "timers": {"total": len(tabla_timers), "mal": sum(1 for t in tabla_timers if t["resultado"] not in ("success", ""))},
            "peticiones_24h": int(n24 or 0), "fallos_5xx_24h": int(e5_24 or 0),
            "ms_medio_24h": round((ms24 or 0) / n24) if n24 else None,
            "errores_logs_24h": int(errores_24), "eventos_24h": sum(1 for e in eventos if e["t"] >= dia_atras),
            "claude_30d_usd": round(sum(x["usd"] for x in mes), 2),
            "temperatura": ultimo.get("pi:temperatura"), "memoria_libre_mb": ultimo.get("pi:memoria_libre_mb"),
            "disco_libre_gb": ultimo.get("pi:disco_libre_gb"), "carga": ultimo.get("pi:carga"),
            "copia_horas": ultimo.get("copia:horas"), "bajones_periodo": int(bajones),
            "docker": {"sanos": ultimo.get("docker:sanos"), "total": ultimo.get("docker:total")},
            "webs": {k[4:]: v for k, v in ultimo.items() if k.startswith("web:")},
        },
        "http": serie_http, "rutas": lentos, "serie": serie, "eventos": eventos,
        "servicios": tabla_servicios, "timers": tabla_timers,
        "claude": {"por_dia": claude_dia, "por_quien": claude_quien}, "uso": uso_dias(desde),
    }


if __name__ == "__main__":
    if "--recoge" in sys.argv:
        n, ev = recoge()
        print(f"{n} muestras, {len(ev)} eventos", *[f"\n  {e[1]} {e[2]}: {e[3]}" for e in ev])
    elif "--panel" in sys.argv:
        print(json.dumps(panel(), ensure_ascii=False, indent=1)[:6000])
    else:
        print(__doc__)
