"""El día de cobro (lo pidió Yago el 20/11): «cuando cobre, que me avise de invertir: cuánto, qué opciones, un informe
de lo que me faltaría y por dónde tirar o qué investigar».

- Cuándo: el día de cobro de Gastos (Ajustes de Gastos, `dia_cobro`; si el mes es más corto, el último día), o antes si
  entra un ingreso de al menos el 60 % de tu sueldo. Una vez al mes (`cobro-avisados.json`). Lo lanza cobro.timer cada
  día a las 09:30 y no hace nada si no toca.
- Cuánto: lo que tienes puesto para invertir cada mes en Gastos (`inversion`) más las multas por hábitos del ciclo que
  acaba (inversiones multas). Las cuentas, aquí; Claude no se inventa la cifra.
- Por dónde: Claude (con la web) mira tu cartera, tu perfil, lo último de Explorar (huecos, ideas y lo que respondiste)
  y propone dónde poner ESTE mes el dinero, qué te falta y qué investigar. Se guarda como una Pregunta de tipo «cobro»
  (Inversiones → Pregunta, en la web y en Tom) y por Telegram va el resumen.

    python3 cobro.py            # lo del timer
    python3 cobro.py --forzar   # aunque no sea el día (y aunque ya se mandara este mes)
    python3 cobro.py --ver      # lo calcula y lo enseña, sin guardar ni mandar
"""
import calendar
import html
import json
import os
import re
import subprocess
import sys
import time
import urllib.request
from datetime import date, datetime, timedelta
from pathlib import Path

import inversiones

AVISADOS = inversiones.DATOS.with_name("cobro-avisados.json")
GASTOS = os.getenv("GASTOS_URL", "http://127.0.0.1:8085")
TODO = "http://127.0.0.1:8082"
MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"]

PROMPT = """Hoy {hoy} he cobrado. Eres mi asesor de inversiones de confianza (no regulado; dilo en una línea al final).
Empiezo a invertir (broker {broker}, horizonte {horizonte}, tolerancia {tolerancia}). Vivo en España.

Este mes toca invertir {total} €: {desglose}. Mi colchón (hucha de Gastos): {hucha} €. Cobro unos {sueldo} € al mes y
gasto de media {gasto_mes} € al mes (últimos 90 días, todo incluido).
Mi cartera ahora:
{cartera}
Planes de ahorro: {planes}
{mirar}
Lo último de Explorar (lo que le falta a mi cartera y las ideas que me propusiste, con lo que respondí):
{explorar}

Busca en la web lo que necesites de HOY (precios, comisiones de mi broker, TER) y di de dónde sale cada dato.
Escribe en Markdown sencillo, de tú, claro y para alguien que empieza, con estos apartados (`##`):
## Cuánto
La cifra de este mes y si tiene sentido con mi colchón (si el colchón es flojo, dilo y propone repartir).
## Dónde ponerlo este mes
2 o 3 opciones concretas (nombre e ISIN, coste, por qué ESTE mes), la que tú elegirías y por qué, y cómo hacerlo en mi
broker en dos pasos. Ten en cuenta comisiones mínimas: si una compra pequeña sale cara, dilo.
## Lo que le falta a tu cartera
En 3 viñetas, con datos.
## Para investigar este mes
1 a 3 cosas concretas (pueden ser ideas de Explorar), con qué mirar de cada una.
Sin órdenes tajantes: opciones, la tuya razonada y sus riesgos. Unas 350 palabras."""


def _json(url, clave):
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {clave}"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def dia_de_cobro(ajustes, hoy):
    d = int(ajustes.get("dia_cobro") or 0)
    return date(hoy.year, hoy.month, min(d, calendar.monthrange(hoy.year, hoy.month)[1])) if d else None


def toca(g, hoy):
    """(toca hoy, por qué)."""
    a = g.get("ajustes") or {}
    dc = dia_de_cobro(a, hoy)
    if dc and hoy == dc:
        return True, "es tu día de cobro"
    sueldo = float(a.get("ingreso") or 0)
    grande = [x for x in g.get("ingresos") or [] if x["dia"] == hoy.isoformat() and x.get("tipo") != "devuelve"
              and sueldo and x["importe"] >= 0.6 * sueldo]
    if grande:
        return True, f"ha entrado {grande[0]['importe']:.2f} €".replace(".", ",")
    return False, ""


def multas_del_ciclo(multas, hoy, ajustes):
    """Las multas desde el cobro anterior (un mes antes del día de cobro)."""
    dc = dia_de_cobro(ajustes, hoy) or hoy
    antes = (dc.replace(day=1) - timedelta(days=1))
    previo = date(antes.year, antes.month, min(int(ajustes.get("dia_cobro") or dc.day), calendar.monthrange(antes.year, antes.month)[1]))
    return round(sum(m["euros"] for m in multas if previo.isoformat() <= m["dia"] < hoy.isoformat()), 2)


def explorar_txt():
    try:
        import explorar
        d = explorar.lee()
        inf = next((x for x in d["informes"] if x.get("estado") == "listo"), None)
        if not inf:
            return "(todavía no hay)"
        r = d["reacciones"]
        nombres = {"interesa": "me interesa", "descarta": "descartada", "tengo": "ya la tengo"}
        huecos = "; ".join(h["t"] for h in inf.get("huecos") or [])
        ideas = "\n".join(f"- {i['nombre']} ({i['tipo']}{', ' + i['isin'] if i['isin'] else ''}): {i['gancho']}"
                          + (f" [{nombres[r[i['id']]['estado']]}]" if i["id"] in r else "") for i in inf.get("ideas") or [])
        return f"Del {inf['fecha']}. Huecos: {huecos}\n{ideas}"
    except Exception as e:
        return f"(no disponible: {e})"


def prompt(hoy, total, desglose, hucha, sueldo, gasto_mes):
    inf = inversiones.informe(hoy)
    p = inf["perfil"]
    cartera = "\n".join(f"- {x['nombre']} ({x['simbolo']}, {x['tipo']}): {x['peso']} %" for x in inf["posiciones"] if x["cantidad"] > 0) or "(vacía)"
    planes = ", ".join(f"{x['activo']} {x['importe']} €/mes" for x in inf["planes"] if x.get("activo") is not False) or "ninguno"
    mirar = "" if inf["mirar"] else "Modo «no mires»: no me digas cuánto vale ni cuánto se ha movido lo que ya tengo.\n"
    return PROMPT.format(hoy=hoy.isoformat(), broker=p["broker"] or "?", horizonte=p["horizonte"] or "?", tolerancia=p["tolerancia"] or "?",
                         total=f"{total:.2f}".replace(".", ","), desglose=desglose, hucha=f"{hucha:.2f}".replace(".", ","),
                         sueldo=f"{sueldo:.0f}", gasto_mes=f"{gasto_mes:.0f}",
                         cartera=cartera, planes=planes, mirar=mirar, explorar=explorar_txt())


def claude(texto):
    c = os.environ.get("CLAUDE_BIN", str(Path.home() / ".local/bin/claude"))
    r = subprocess.run([c, "-p", "--model", os.environ.get("COBRO_MODEL", "sonnet"), "--tools", "WebSearch,WebFetch",
                        "--allowedTools", "WebSearch,WebFetch", "--strict-mcp-config", "--no-session-persistence"],
                       input=texto, capture_output=True, text=True, timeout=10 * 60)
    if r.returncode or not r.stdout.strip():
        raise RuntimeError((r.stderr or r.stdout or "sin respuesta")[-300:])
    t = r.stdout.strip()
    return t[t.find("## "):] if "## " in t else t


def para_telegram(cabeza, md):
    """Lo esencial del informe para Telegram: la cabecera y «Dónde ponerlo», sin marcas de Markdown."""
    m = re.search(r"(?ms)^## *Dónde[^\n]*\n(.*?)(?=^## |\Z)", md)
    cuerpo = (m.group(1) if m else md).strip()
    cuerpo = re.sub(r"\*\*(.+?)\*\*", r"\1", cuerpo)
    cuerpo = re.sub(r"\[([^\]]+)\]\((https?://[^)]+)\)", r"\1", cuerpo)
    if len(cuerpo) > 1800:
        cuerpo = cuerpo[:1800].rsplit("\n", 1)[0] + "\n…"
    return (f"{html.escape(cabeza)}\n\n<b>Dónde ponerlo este mes</b>\n{html.escape(cuerpo)}\n\n"
            "Entero (lo que te falta y qué investigar): https://todo.yagotg.dev/inversiones.html#pregunta")


def main():
    hoy = date.today()
    forzar, ver = "--forzar" in sys.argv, "--ver" in sys.argv
    mes = hoy.strftime("%Y-%m")
    avisados = json.loads(AVISADOS.read_text()) if AVISADOS.exists() else []
    if mes in avisados and not (forzar or ver):
        return
    g = _json(f"{GASTOS}/api/estado", os.environ.get("GASTOS_PASS", ""))
    si, por_que = toca(g, hoy)
    if not si and not (forzar or ver):
        print("Hoy no toca")
        return
    a = g.get("ajustes") or {}
    base = float(a.get("inversion") or 0)
    try:
        multas = multas_del_ciclo(_json(f"{TODO}/api/multas", os.environ.get("TODO_PASS", ""))["multas"], hoy, a)
    except Exception:
        multas = 0.0
    total = round(base + multas, 2)
    eur = lambda x: f"{x:.2f}".replace(".", ",")
    desglose = f"{eur(base)} € de lo que te pusiste al mes" + (f" + {eur(multas)} € de multas por hábitos" if multas else "")
    hace90 = (hoy - timedelta(days=90)).isoformat()
    gasto_mes = sum(x["importe"] for x in g.get("gastos") or [] if x["dia"] >= hace90) / 3
    md = claude(prompt(hoy, total, desglose, float(a.get("hucha") or 0), float(a.get("ingreso") or 0), gasto_mes))
    cabeza = f"💶 Día de cobro ({por_que or 'a mano'}): este mes tocaría invertir {eur(total)} € ({desglose})."
    if ver:
        print(cabeza, "\n\n", md)
        return
    inversiones.apunta_pregunta(f"Día de cobro de {MESES[hoy.month - 1]}: ¿cuánto invierto y dónde?", md, tipo="cobro",
                                titulo=f"Día de cobro · {MESES[hoy.month - 1]} · {eur(total)} €")
    import aviso
    aviso.telegram(para_telegram(cabeza, md))
    try:
        import uso
        uso.apunta("aviso:cobro", "telegram", auto=True, app="aviso")
    except Exception:
        pass
    tmp = AVISADOS.with_suffix(".tmp")
    tmp.write_text(json.dumps((avisados + [mes])[-24:]))
    tmp.replace(AVISADOS)


if __name__ == "__main__":
    main()
