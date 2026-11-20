"""Explorar (pestaña de Inversiones en la web y en Tom): ideas nuevas que mirar —temas, fondos y empresas— pensadas
para MI cartera y MI perfil, con el porqué, el mejor argumento en contra y cómo se compraría si interesara.

Lo pidió Yago (20/11). Es distinto del informe de mercado (que cuenta el mercado) y de la review (que juzga la cartera):
esto busca lo que falta y lo que merece la pena estudiar, y aprende de lo que respondes a cada idea:
- «Me interesa» → la próxima vez se profundiza (qué ha pasado desde entonces, y si sigue en pie).
- «Descartar» (con un motivo si quieres) → no vuelve, y se evita lo parecido.
- «Ya lo tengo» → cuenta como parte de la cartera.
El comparador de dos fondos o acciones va por la Pregunta de siempre (inversiones.pregunta), con tipo «compara».

- Un informe al mes (explorar.timer, primer sábado a las 11:00) o cuando lo pidas (como mucho uno cada 3 días).
  `claude -p` con WebSearch y WebFetch solamente (como la review): el texto de la web no puede ejecutar nada.
- `explorar.json` junto a data.json (fuera del repo): {informes: [...12 últimos], reacciones: {id: {...}}}.

    python3 explorar.py          # lo que lanza el timer (genera y avisa)
    python3 explorar.py --ver    # genera y lo enseña, sin guardar ni avisar
"""
import hashlib
import json
import os
import re
import subprocess
import sys
import threading
import time
from datetime import date, datetime
from pathlib import Path

import inversiones

FICHERO = inversiones.DATOS.with_name("explorar.json")
TIPOS = ("tema", "fondo", "empresa")
REACCIONES = ("interesa", "descarta", "tengo")
MIN_DIAS = 3
_cerrojo = threading.Lock()

PROMPT = """Eres mi analista de inversiones de confianza y tu trabajo hoy es ampliarme el mapa: proponerme cosas que
merece la pena ESTUDIAR, no decirme qué comprar. Tengo {edad} años, empiezo a invertir (broker {broker}, horizonte
{horizonte}, tolerancia {tolerancia}, aporto unos {aportacion} € al mes, objetivo: {objetivo}). Vivo en España (IRPF:
base del ahorro; los traspasos sin tributar solo valen entre fondos, no entre ETFs). Hoy es {hoy}.

Mi cartera ahora:
{cartera}
{mirar}
Lo que respondí a ideas de otros meses (aprende de esto: profundiza en lo que me interesa, no repitas lo descartado ni
lo muy parecido, y lo que ya tengo cuenta como cartera):
{reacciones}

Ideas que ya te pedí otras veces (no las repitas salvo en «seguimiento»):
{previas}

Tendencias del último informe de mercado (para no quedarte solo en eso, pero úsalo si encaja):
{mercado}

Antes de escribir, busca en la web datos de HOY para cada idea (valoraciones, TER y tamaño del fondo, noticias, cifras
del sector) y di de dónde sale cada dato. No inventes: si un dato no lo encuentras, dilo.

Qué quiero:
- De 5 a 6 ideas, variadas: al menos 1 tema (una tendencia o sector), 2 fondos o ETFs concretos (UCITS, que se puedan
  comprar desde España; con ISIN), 1 o 2 empresas cotizadas, y 1 idea «aburrida» o a contracorriente que equilibre
  (renta fija, value, dividendo, un mercado olvidado…) para no ir solo detrás de lo que está de moda.
- Que cada una tenga sentido PARA MÍ: o cubre un hueco de mi cartera, o encaja con mi horizonte y mi aportación. Si una
  idea no encaja con mi tolerancia al riesgo, no la pongas.
- El mejor argumento en contra de cada una, en serio (lo que diría alguien listo que no la compraría).
- Cómo se tendría exposición: el vehículo concreto (ETF/fondo con ISIN, TER, acumulación o distribución, domicilio) y
  qué parte de la cartera sería sensata si me interesara (en %, pequeña para empresas sueltas).
- Qué señales mirar para saber si la tesis va bien o se rompe.
- En «huecos», lo que le falta a mi cartera tal como está (geografías, sectores, tipos de activo, divisas), con datos.
- En «seguimiento», para cada idea que marqué «me interesa»: qué ha pasado desde entonces y si sigue en pie.
- Un concepto para aprender a evaluar ideas como estas (PER, moat, TER, solapamiento, sesgo de narrativa…), con ejemplo.

Contesta SOLO con un bloque de código ```json y dentro UN objeto con esta forma (textos en español, claros, para alguien
que empieza; cifras con coma decimal; cada campo de texto en 1-3 frases salvo «tesis» y «contra», que pueden ser 4):
```json
{{"resumen": "2-3 frases: cómo veo tu cartera y por dónde merece la pena mirar este mes",
  "huecos": [{{"t": "Nada en emergentes", "por_que": "…con datos…"}}],
  "ideas": [{{"tipo": "tema|fondo|empresa", "nombre": "…", "ticker": "", "isin": "",
             "gancho": "una línea que lo resume", "por_que_tu": "por qué encaja con tu perfil y tu cartera",
             "tesis": "qué tiene que pasar para que salga bien", "contra": "el mejor argumento en contra",
             "riesgos": ["…", "…"], "como": "vehículo concreto: nombre, ISIN, TER, acumulación, domicilio",
             "encaje": "cómo cambiaría tu cartera (solapamiento con lo que tienes) y qué % sería sensato",
             "senales": "qué mirar para saber si va bien o se rompe", "riesgo": 3, "horizonte": "5-10 años",
             "dato": "un dato verificable de hoy", "fuentes": ["https://…"]}}],
  "seguimiento": [{{"nombre": "…", "que_ha_pasado": "…", "sigue": true}}],
  "aprender": {{"titulo": "…", "texto": "…"}}}}
```
`riesgo` de 1 (muy bajo) a 5 (muy alto). Nada de HTML."""


# ---------- datos ----------
def lee():
    try:
        d = json.loads(FICHERO.read_text("utf-8"))
    except (OSError, ValueError):
        d = {}
    d = d if isinstance(d, dict) else {}
    informes = [x for x in d.get("informes") or [] if isinstance(x, dict)]
    ahora = time.time()
    for x in informes:   # un reinicio a mitad deja uno «generando» huérfano
        if x.get("estado") == "generando" and ahora - x.get("t", ahora) > 30 * 60:
            x.update(estado="error", error="Se cortó mientras pensaba (¿reinicio?). Vuelve a pedirlo.")
    return {"informes": informes, "reacciones": d.get("reacciones") if isinstance(d.get("reacciones"), dict) else {}}


def _guarda(d):
    d["informes"] = d["informes"][:12]
    inversiones._escribe(FICHERO, d)


def _t(v, n=600):
    return " ".join(str(v or "").split())[:n]


def limpia_informe(x):
    """Lo que devuelve Claude, con forma fija (lo que no está aquí no se guarda)."""
    x = x if isinstance(x, dict) else {}
    ideas = []
    for i in x.get("ideas") or []:
        if not isinstance(i, dict) or not _t(i.get("nombre")):
            continue
        nombre = _t(i.get("nombre"), 120)
        try:
            riesgo = min(5, max(1, int(i.get("riesgo") or 3)))
        except (TypeError, ValueError):
            riesgo = 3
        ideas.append({
            "id": "x" + hashlib.md5(nombre.lower().encode()).hexdigest()[:10],
            "tipo": i.get("tipo") if i.get("tipo") in TIPOS else "tema", "nombre": nombre,
            "ticker": _t(i.get("ticker"), 20), "isin": _t(i.get("isin"), 12).upper(),
            "gancho": _t(i.get("gancho"), 200), "por_que_tu": _t(i.get("por_que_tu")), "tesis": _t(i.get("tesis"), 900),
            "contra": _t(i.get("contra"), 900), "riesgos": [_t(r, 200) for r in (i.get("riesgos") or [])[:5] if _t(r)],
            "como": _t(i.get("como")), "encaje": _t(i.get("encaje")), "senales": _t(i.get("senales")),
            "riesgo": riesgo, "horizonte": _t(i.get("horizonte"), 40), "dato": _t(i.get("dato"), 300),
            "fuentes": [u for u in (_t(f, 300) for f in (i.get("fuentes") or [])[:5]) if u.startswith("https://")],
        })
    ap = x.get("aprender") if isinstance(x.get("aprender"), dict) else {}
    return {
        "resumen": _t(x.get("resumen"), 800),
        "huecos": [{"t": _t(h.get("t"), 120), "por_que": _t(h.get("por_que"))} for h in (x.get("huecos") or [])[:6]
                   if isinstance(h, dict) and _t(h.get("t"))],
        "ideas": ideas[:8],
        "seguimiento": [{"nombre": _t(s.get("nombre"), 120), "que_ha_pasado": _t(s.get("que_ha_pasado"), 900),
                         "sigue": s.get("sigue") is not False}
                        for s in (x.get("seguimiento") or [])[:8] if isinstance(s, dict) and _t(s.get("nombre"))],
        "aprender": {"titulo": _t(ap.get("titulo"), 120), "texto": _t(ap.get("texto"), 1500)} if _t(ap.get("titulo")) else None,
    }


def saca_json(texto):
    m = re.search(r"```json\s*(\{.*\})\s*```", texto, re.S) or re.search(r"(\{.*\})", texto, re.S)
    if not m:
        raise ValueError("Claude no ha devuelto el JSON")
    return json.loads(m.group(1))


# ---------- el prompt ----------
def _todas_las_ideas(d):
    return {i["id"]: i for inf in reversed(d["informes"]) for i in inf.get("ideas") or []}


def prompt(hoy=None, d=None):
    hoy = hoy or date.today()
    d = d or lee()
    inf = inversiones.informe(hoy)
    p = inf["perfil"]
    cartera = "\n".join(f"- {x['nombre']} ({x['simbolo']}, {x['tipo']}" + (f", ISIN {x['isin']}" if x.get("isin") else "")
                        + f"): {x['peso']} %" for x in inf["posiciones"] if x["cantidad"] > 0) or "(todavía vacía)"
    ideas = _todas_las_ideas(d)
    nombres = {"interesa": "me interesa", "descarta": "descartada", "tengo": "ya la tengo"}
    reacciones = "\n".join(f"- {ideas[i]['nombre']} ({ideas[i]['tipo']}): {nombres[r['estado']]}"
                           + (f". Motivo: {r['nota']}" if r.get("nota") else "")
                           for i, r in d["reacciones"].items() if i in ideas and r.get("estado") in nombres) or "(ninguna todavía)"
    previas = ", ".join(sorted({i["nombre"] for i in ideas.values()})) or "(es la primera vez)"
    try:
        import mercado
        l = mercado.lista()
        t = mercado.informe(l[0]) if l else ""
        merc = "\n".join(re.findall(r"(?ms)^## *5\..*?(?=^## *\d+\.|\Z)", t or ""))[:2500] or "(no hay)"
    except Exception:
        merc = "(no disponible)"
    mirar = "" if inf["mirar"] else ("Tengo activo el modo «no mires»: no me digas cuánto ha subido o bajado lo que ya tengo "
                                     "(ni su precio de hoy); de las ideas nuevas, sí.\n")
    return PROMPT.format(mirar=mirar, edad=p["edad"] or "?", broker=p["broker"] or "?", horizonte=p["horizonte"] or "?",
                         tolerancia=p["tolerancia"] or "?", aportacion=p["aportacion"], objetivo=p.get("objetivo") or "?",
                         hoy=hoy.isoformat(), cartera=cartera, reacciones=reacciones, previas=previas, mercado=merc)


# ---------- generar ----------
def _claude(texto):
    claude = os.environ.get("CLAUDE_BIN", str(Path.home() / ".local/bin/claude"))
    r = subprocess.run([claude, "-p", "--model", os.environ.get("EXPLORAR_MODEL", "opus"),
                        "--tools", "WebSearch,WebFetch", "--allowedTools", "WebSearch,WebFetch",
                        "--strict-mcp-config", "--no-session-persistence"],
                       input=texto, capture_output=True, text=True, timeout=25 * 60)
    if r.returncode or not r.stdout.strip():
        raise RuntimeError((r.stderr or r.stdout or "sin respuesta")[-300:])
    return r.stdout


def _hace(id_, avisar):
    try:
        x = limpia_informe(saca_json(_claude(prompt())))
        if not x["ideas"]:
            raise ValueError("Sin ideas en la respuesta")
        cambios = {**x, "estado": "listo"}
    except Exception as e:
        cambios = {"estado": "error", "error": f"No ha salido: {str(e)[:300]}"}
    with _cerrojo:
        d = lee()
        for inf in d["informes"]:
            if inf["id"] == id_:
                inf.update(cambios)
        _guarda(d)
    if avisar and cambios["estado"] == "listo":
        try:
            import aviso
            nombres = ", ".join(i["nombre"] for i in cambios["ideas"][:3])
            aviso.avisa("Explorar: ideas del mes", f"{len(cambios['ideas'])} ideas para estudiar: {nombres}…", "explorar",
                        "/inversiones.html#explorar")
        except Exception as e:
            print("explorar, aviso:", e, flush=True)


def genera(en_hilo=True, avisar=False, forzar=False):
    """Empieza un informe nuevo. En hilo (lo que pide la web) devuelve al momento con estado «generando»."""
    with _cerrojo:
        d = lee()
        if any(x.get("estado") == "generando" for x in d["informes"]):
            raise ValueError("Ya está pensando uno: tarda unos minutos")
        ultimo = next((x for x in d["informes"] if x.get("estado") == "listo"), None)
        if ultimo and not forzar and time.time() - ultimo.get("t", 0) < MIN_DIAS * 86400:
            raise ValueError(f"El último es del {ultimo['fecha']}: como mucho uno cada {MIN_DIAS} días")
        inf = {"id": "e" + str(time.time_ns())[-12:], "fecha": date.today().isoformat(), "t": time.time(),
               "cuando": datetime.now().isoformat(timespec="minutes"), "estado": "generando"}
        d["informes"].insert(0, inf)
        _guarda(d)
    if en_hilo:
        threading.Thread(target=_hace, args=(inf["id"], avisar), daemon=True).start()
    else:
        _hace(inf["id"], avisar)
    return inf


def reacciona(id_, estado, nota=""):
    """estado: interesa, descarta, tengo, o "" para quitar la reacción."""
    with _cerrojo:
        d = lee()
        if id_ not in _todas_las_ideas(d):
            raise KeyError(id_)
        if estado in REACCIONES:
            d["reacciones"][id_] = {"estado": estado, "nota": _t(nota, 300), "dia": date.today().isoformat()}
        elif not estado:
            d["reacciones"].pop(id_, None)
        else:
            raise ValueError("Reacción desconocida")
        _guarda(d)
        return d["reacciones"].get(id_)


def borra(id_):
    with _cerrojo:
        d = lee()
        d["informes"] = [x for x in d["informes"] if x["id"] != id_]
        _guarda(d)


# ---------- comparador (por la Pregunta de siempre) ----------
COMPARA = """Compara {a} y {b} para mí, como si tuviera que elegir uno para mi cartera. Busca los datos de hoy.
Para cada uno: qué es (índice que sigue o negocio), TER o costes, tamaño, acumulación o distribución, domicilio y
retención de dividendos, réplica (física o sintética), número de posiciones y las 5 mayores, reparto por países y
sectores, y rentabilidad y caída máxima a 5 años si existe. Después: cuánto se solapan entre sí y con mi cartera (en %
aproximado y en qué), qué diferencia hay en impuestos para mí en España (fondo traspasable o ETF), y cuál encajaría
mejor conmigo y por qué, en 3 frases. Usa listas (no tablas) y hasta unas 600 palabras."""


def compara(a, b):
    a, b = _t(a, 80), _t(b, 80)
    if not a or not b:
        raise ValueError("Pon los dos: nombre, ticker o ISIN")
    return inversiones.pregunta(COMPARA.format(a=a, b=b), tipo="compara", titulo=f"{a} frente a {b}")


if __name__ == "__main__":
    if "--ver" in sys.argv:
        print(json.dumps(limpia_informe(saca_json(_claude(prompt()))), ensure_ascii=False, indent=1))
    else:
        genera(en_hilo=False, avisar=True, forzar=True)
