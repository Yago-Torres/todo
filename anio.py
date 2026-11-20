"""Tu año en números (lo pidió Yago el 20/11): el 31/12 por Telegram, y en la web (/anio.html) y en Tom cuando quieras.

Todo sale de lo que ya guardan las apps: hábitos y rachas, gimnasio (kilos levantados, mejoras), carreras, escalada, peso,
sueño y pasos, móvil, gastos e ingresos, inversión, lo que usas y lo que ha currado Claude. Las cuentas son aquí; Claude
solo pone el titular y tres frases (`lectura`, se guarda en `anio-AAAA.json` junto a data.json para no pedirlo dos veces).

    python3 anio.py            # lo que lanza anio.timer el 31/12 a las 20:00: genera la lectura y lo manda
    python3 anio.py --ver      # lo mismo por pantalla, sin mandar
"""
import json
import os
import subprocess
import sys
import urllib.request
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta
from pathlib import Path

HERE = Path(__file__).parent
DATOS = Path(os.getenv("TODO_DB", HERE / "data.json"))
MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"]
FIJOS = {"casa", "suscripciones"}


def _e1rm(kg, r):
    return kg * (1 + r / 30)


def _racha_max(dias_hechos, ventana):
    """La racha más larga con la regla sencilla de las rachas: no pasar más de `ventana` días sin hacerlo."""
    mejor = n = 0
    previo = None
    for d in sorted(dias_hechos):
        x = date.fromisoformat(d)
        n = n + 1 if previo and (x - previo).days <= ventana else 1
        mejor, previo = max(mejor, n), x
    return mejor


def habitos(s, desde, hasta):
    log = {d: v for d, v in s["log"].items() if desde <= d <= hasta}
    out = []
    for h in s["habits"]:
        dias = [d for d, v in log.items() if h["id"] in v]
        ventana = -(-7 * h.get("cada", 1) // h["goal"])
        out.append({"n": h["n"], "veces": len(dias), "racha_max": _racha_max(dias, ventana)})
    por_mes = Counter(d[:7] for d, v in log.items() for _ in v)
    semanas = defaultdict(int)
    for d, v in log.items():
        x = date.fromisoformat(d)
        semanas[(x - timedelta(days=x.weekday())).isoformat()] += len(v)
    mejor_mes = por_mes.most_common(1)[0] if por_mes else None
    return {"marcas": sum(len(v) for v in log.values()), "dias_con_algo": len(log),
            "top": sorted(out, key=lambda x: -x["veces"])[:5], "mejor_racha": max(out, key=lambda x: x["racha_max"], default=None),
            "mejor_mes": {"mes": MESES[int(mejor_mes[0][5:]) - 1], "marcas": mejor_mes[1]} if mejor_mes else None,
            "mejor_semana": max(semanas.items(), key=lambda x: x[1])[0] if semanas else None,
            "olvidados": [x["n"] for x in out if x["veces"] <= 2]}


def gimnasio(s, desde, hasta):
    sesiones = [x for d, l in s.get("gym", {}).items() if desde <= d <= hasta for x in (l if isinstance(l, list) else [l])
                if isinstance(x, dict)]
    kilos, mejor = 0.0, {}
    for d in sorted(s.get("gym", {})):
        if not desde <= d <= hasta:
            continue
        l = s["gym"][d]
        for x in (l if isinstance(l, list) else [l]):
            for e in (x.get("ej") or []) if isinstance(x, dict) else []:
                for serie in e.get("series") or []:
                    if len(serie) >= 2 and serie[0] and serie[1]:
                        kilos += serie[0] * serie[1]
                        m = mejor.setdefault(e["ej"], {"primero": None, "mejor": 0})
                        v = _e1rm(serie[0], serie[1])
                        m["primero"] = m["primero"] or v
                        m["mejor"] = max(m["mejor"], v)
    subidas = sorted(((n, round((m["mejor"] / m["primero"] - 1) * 100)) for n, m in mejor.items() if m["primero"]),
                     key=lambda x: -x[1])
    return {"sesiones": len(sesiones), "minutos": sum(x.get("min") or 0 for x in sesiones), "toneladas": round(kilos / 1000, 1),
            "mas_mejora": [{"ej": n, "pct": p} for n, p in subidas[:3] if p > 0]}


def actividad(s, desde, hasta):
    acts = [a for d, l in s.get("actividad", {}).items() if desde <= d <= hasta for a in l]
    carreras = [a for a in acts if a.get("km")]
    ritmo = [a for a in carreras if a.get("seg") and a["km"] >= 2]
    mejor = min(ritmo, key=lambda a: a["seg"] / a["km"], default=None)
    return {"carreras": len(carreras), "km": round(sum(a["km"] for a in carreras), 1),
            "mas_larga": max((a["km"] for a in carreras), default=0),
            "mejor_ritmo": f"{int(mejor['seg'] / mejor['km'] // 60)}:{int(mejor['seg'] / mejor['km'] % 60):02d} /km" if mejor else None,
            "escalada": sum(1 for a in acts if "escal" in (a.get("t") or "").lower())}


def cuerpo(s, desde, hasta):
    p = sorted((d, kg) for d, kg in s.get("peso", {}).items() if desde <= d <= hasta)
    sal = {d: v for d, v in s.get("salud", {}).items() if desde <= d <= hasta}
    sueno = [v["sueno"] for v in sal.values() if v.get("sueno")]
    pasos = [(d, v["pasos"]) for d, v in sal.items() if v.get("pasos")]
    return {"peso": {"inicio": p[0][1], "fin": p[-1][1], "min": min(kg for _, kg in p), "cambio": round(p[-1][1] - p[0][1], 1)} if p else None,
            "sueno_medio": round(sum(sueno) / len(sueno)) if sueno else None, "noches": len(sueno),
            "pasos": sum(x for _, x in pasos), "pasos_medios": round(sum(x for _, x in pasos) / len(pasos)) if pasos else None,
            "mejor_dia_pasos": max(pasos, key=lambda x: x[1]) if pasos else None}


def movil(pantalla, desde, hasta):
    dias = {d: v for d, v in (pantalla.get("dias") or {}).items() if desde <= d <= hasta}
    apps = Counter()
    for v in dias.values():
        for a, x in v.items():
            apps[a] += x.get("s", 0)
    total = sum(apps.values())
    return {"horas": round(total / 3600), "dias_medidos": len(dias), "media_min": round(total / 60 / len(dias)) if dias else None,
            "top": [{"app": a, "horas": round(s_ / 3600, 1)} for a, s_ in apps.most_common(3)]}


def dinero(g, desde, hasta):
    gs = [x for x in g.get("gastos") or [] if desde <= x["dia"] <= hasta]
    ins = [x for x in g.get("ingresos") or [] if desde <= x["dia"] <= hasta and x.get("tipo") != "devuelve"]
    cats, comercios, meses = Counter(), Counter(), Counter()
    for x in gs:
        cats[x["cat"]] += x["importe"]
        meses[x["dia"][:7]] += x["importe"]
        if x.get("comercio"):
            comercios[x["comercio"].split(" ")[0].title()] += 1
    total = sum(x["importe"] for x in gs)
    variable = sum(x["importe"] for x in gs if x["cat"] not in FIJOS)
    primero = min((x["dia"] for x in gs), default=desde)   # desde que hay datos, no desde el 1 de enero
    dias = max(1, (date.fromisoformat(hasta) - date.fromisoformat(primero)).days + 1)
    caro = meses.most_common(1)[0] if meses else None
    return {"gastado": round(total, 2), "ingresado": round(sum(x["importe"] for x in ins), 2), "tickets": len(gs),
            "al_dia_variable": round(variable / dias, 2), "top_cats": [{"cat": c, "eur": round(v, 2)} for c, v in cats.most_common(3)],
            "comercio_favorito": comercios.most_common(1)[0] if comercios else None,
            "mes_mas_caro": {"mes": MESES[int(caro[0][5:]) - 1], "eur": round(caro[1], 2)} if caro else None}


def inversion(inf, desde, hasta):
    ops = [o for o in inf.get("operaciones") or [] if desde <= (o.get("fecha") or o.get("dia") or "") <= hasta]
    compras = sum(o.get("cantidad", 0) * o.get("precio", 0) + o.get("comision", 0) for o in ops if o.get("tipo") == "compra")
    out = {"operaciones": len(ops), "aportado": round(compras, 2), "posiciones": len([p for p in inf.get("posiciones") or [] if p["cantidad"] > 0])}
    if inf.get("mirar"):
        out.update(valor=inf["total"]["valor"], rent=inf["total"].get("rent"))
    return out


def claude_uso(desde, hasta):
    f = Path.home() / ".local/state/claude-uso.jsonl"
    n, quien = 0, Counter()
    try:
        for l in f.read_text().splitlines():
            x = json.loads(l)
            if desde <= x["t"][:10] <= hasta:
                n += 1
                quien[x["quien"]] += 1
    except (OSError, ValueError):
        pass
    return {"llamadas": n, "para": quien.most_common(3)}


def calcula(s, gastos, pantalla, inf, uso_inf, anio, hoy=None):
    hoy = (hoy or date.today()).isoformat()
    desde, hasta = f"{anio}-01-01", min(f"{anio}-12-31", hoy)
    primero = min([d for d in s["log"] if d >= desde] + [x["dia"] for x in gastos.get("gastos") or [] if x["dia"] >= desde],
                  default=desde)
    trozos = {"habitos": lambda: habitos(s, desde, hasta), "gimnasio": lambda: gimnasio(s, desde, hasta),
              "actividad": lambda: actividad(s, desde, hasta), "cuerpo": lambda: cuerpo(s, desde, hasta),
              "movil": lambda: movil(pantalla, desde, hasta), "dinero": lambda: dinero(gastos, desde, hasta),
              "inversion": lambda: inversion(inf, desde, hasta), "claude": lambda: claude_uso(desde, hasta)}
    out = {"anio": anio, "desde": primero, "hasta": hasta}
    for k, fn in trozos.items():
        try:
            out[k] = fn()
        except Exception as e:
            out[k] = {"error": str(e)[:160]}
    out["uso"] = {"dias_activos": uso_inf.get("dias_activos"), "favorita": (uso_inf.get("funciones") or [{}])[0].get("que"),
                  "acciones": uso_inf.get("acciones")} if uso_inf else None
    return out


# ---------- la lectura de Claude ----------
def fichero_lectura(anio):
    return DATOS.with_name(f"anio-{anio}.json")


def lectura_guardada(anio):
    try:
        return json.loads(fichero_lectura(anio).read_text("utf-8"))
    except (OSError, ValueError):
        return None


PROMPT = """Este es mi año {anio} en números (empecé a apuntarlo todo el {desde}), sacado de mis apps:
{datos}

Escribe, en español y de tú, como un amigo que me conoce y no me dora la píldora:
1. Un titular de mi año en menos de 10 palabras.
2. Tres frases: lo mejor (con una cifra), lo que más me ha costado (con una cifra) y una cosa concreta para el año
   que viene, que salga de estos datos.
Devuelve SOLO un JSON en una línea: {{"titular": "...", "frases": ["...", "...", "..."]}}"""


def lectura(datos, forzar=False):
    previa = lectura_guardada(datos["anio"])
    if previa and not forzar:
        return previa
    claude = os.environ.get("CLAUDE_BIN", str(Path.home() / ".local/bin/claude"))
    r = subprocess.run([claude, "-p", "--model", os.environ.get("ANIO_MODEL", "sonnet"), "--tools", "", "--strict-mcp-config",
                        "--no-session-persistence"],
                       input=PROMPT.format(anio=datos["anio"], desde=datos["desde"], datos=json.dumps(datos, ensure_ascii=False)),
                       capture_output=True, text=True, timeout=180)
    t = r.stdout
    x = json.loads(t[t.find("{"):t.rfind("}") + 1])
    out = {"titular": str(x.get("titular") or "")[:120], "frases": [str(f)[:400] for f in (x.get("frases") or [])[:3]],
           "cuando": datetime.now().isoformat(timespec="minutes")}
    tmp = fichero_lectura(datos["anio"]).with_suffix(".tmp")
    tmp.write_text(json.dumps(out, ensure_ascii=False), "utf-8")
    tmp.replace(fichero_lectura(datos["anio"]))
    return out


# ---------- el mensaje del 31/12 ----------
def _n(x, dec=0):
    return f"{x:,.{dec}f}".replace(",", "_").replace(".", ",").replace("_", ".")


def _pl(n, uno, varios):
    return f"{_n(n)} {uno if n == 1 else varios}"


def texto(d, lec):
    h, g, a, c, m, din, inv = (d.get(k) or {} for k in ("habitos", "gimnasio", "actividad", "cuerpo", "movil", "dinero", "inversion"))
    l = [f"🎆 Tu {d['anio']} en números", ""]
    if lec:
        l += [f"«{lec['titular']}»", *lec["frases"], ""]
    if h.get("marcas"):
        r = h.get("mejor_racha") or {}
        l.append(f"✅ {_pl(h['marcas'], 'hábito hecho', 'hábitos hechos')} en {_pl(h['dias_con_algo'], 'día', 'días')}. Mejor racha: {r.get('racha_max')} en «{r.get('n')}». "
                 f"Tu mejor mes, {h['mejor_mes']['mes']}." if h.get("mejor_mes") else "")
    if g.get("sesiones"):
        l.append(f"🏋️ {_pl(g['sesiones'], 'sesión', 'sesiones')} de gimnasio, {_n(g['toneladas'], 1)} toneladas levantadas"
                 + (f"; lo que más ha subido: {g['mas_mejora'][0]['ej']} (+{g['mas_mejora'][0]['pct']} %)" if g.get("mas_mejora") else "") + ".")
    if a.get("carreras"):
        l.append(f"🏃 {_pl(a['carreras'], 'carrera', 'carreras')}, {_n(a['km'], 1)} km; la más larga, {_n(a['mas_larga'], 1)} km"
                 + (f"; mejor ritmo {a['mejor_ritmo']}" if a.get("mejor_ritmo") else "") + ".")
    if a.get("escalada"):
        l.append(f"🧗 {_pl(a['escalada'], 'día', 'días')} de escalada.")
    if c.get("peso"):
        l.append(f"⚖️ De {_n(c['peso']['inicio'], 1)} a {_n(c['peso']['fin'], 1)} kg ({c['peso']['cambio']:+.1f})".replace(".", ","))
    if c.get("sueno_medio"):
        l.append(f"😴 Dormiste {c['sueno_medio'] // 60} h {c['sueno_medio'] % 60:02d} de media; {_n(c['pasos'])} pasos en total.")
    if m.get("horas"):
        l.append(f"📱 {m['horas']} h en las apps que vigilas" + (f", sobre todo {m['top'][0]['app']}" if m.get("top") else "") + ".")
    if din.get("gastado"):
        l.append(f"💶 {_n(din['gastado'], 2)} € gastados en {din['tickets']} compras; sobre todo en {din['top_cats'][0]['cat']}"
                 + (f"; mes más caro, {din['mes_mas_caro']['mes']}" if din.get("mes_mas_caro") else "") + ".")
    if inv.get("operaciones"):
        l.append(f"📈 {_pl(inv['operaciones'], 'operación', 'operaciones')}, {_n(inv['aportado'], 2)} € invertidos.")
    if (d.get("claude") or {}).get("llamadas"):
        l.append(f"🤖 Claude ha trabajado para ti {_pl(d['claude']['llamadas'], 'vez', 'veces')}.")
    l += ["", f"Entero: https://todo.yagotg.dev/anio.html"]
    return "\n".join(x for x in l if x is not None)


def main():
    env = os.environ
    req = urllib.request.Request(f"http://127.0.0.1:8082/api/anio?anio={date.today().year}",
                                 headers={"Authorization": f"Bearer {env.get('TODO_PASS', '')}"})
    with urllib.request.urlopen(req, timeout=60) as r:
        d = json.load(r)
    lec = d.get("lectura")
    try:
        lec = lectura(d["datos"], forzar=True)
    except Exception as e:
        print("lectura:", e, file=sys.stderr)
    t = texto(d["datos"], lec)
    print(t)
    if "--ver" in sys.argv:
        return
    import aviso
    import html
    aviso.telegram(html.escape(t, quote=False))
    try:
        import uso
        uso.apunta("aviso:anio", "telegram", auto=True, app="aviso")
    except Exception:
        pass


if __name__ == "__main__":
    main()
