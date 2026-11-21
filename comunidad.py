"""Lo que se dice (Reddit, Hacker News, Polymarket, la web) sobre lo que tienes y sobre el mercado.

Usa el motor del skill last30days (https://github.com/mvanhorn/last30days-skill, v4.5.0, MIT), instalado fijo en
~/opt/last30days (enlace a ~/opt/last30days-4.5.0; se instala a mano, ver docs/funciones.md). Sin claves ni cookies:
Reddit público, Hacker News, Polymarket, GitHub y una búsqueda web sin clave. Solo manda el tema buscado.

- `evidencia(tema)`: el informe del motor en texto, para pasárselo a Claude como material (opinión de la gente, sin
  verificar), en el informe de mercado del sábado (mercado.py) y la review del domingo (inversiones.py).
- `avisos()`: lo lanza comunidad-avisos.timer (09:00 y 19:00). Mira los últimos 3 días de cada acción o cripto que
  tienes y, si algo tiene mucha repercusión (miles de votos en Reddit, cientos de puntos en Hacker News) y no te lo
  había contado, te lo manda por Telegram con su enlace. `comunidad-vistos.json` recuerda lo ya avisado (30 días).

    python comunidad.py --avisos [--ver]     # --ver: lo que avisaría, sin mandar ni apuntar
    python comunidad.py --mercado            # el bloque que recibe el informe del sábado
    python comunidad.py "tema"               # el informe del motor sobre un tema, en texto
"""
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import date, timedelta
from pathlib import Path

import inversiones

MOTOR = Path(os.getenv("LAST30DAYS_MOTOR", str(Path.home() / "opt/last30days/scripts/last30days.py")))
PY = os.getenv("LAST30DAYS_PYTHON", "/usr/bin/python3")   # el motor pide Python 3.12 o más
SUBS = "stocks,investing,StockMarket,Bogleheads,eupersonalfinance,SpainFIRE"
VISTOS = inversiones.DATOS.with_name("comunidad-vistos.json")
# lo que es «mucha repercusión»: sin esto, cada hilo con 40 votos sería un aviso
FUERTE = {"reddit": (("score", 1000), ("num_comments", 300)), "hackernews": (("points", 150), ("comments", 80))}
SOBRANTE = re.compile(r"(?i)^(\s*-\s*)?(free fixes|bonus:|youtube: video transcripts|tiktok and instagram|install yt-dlp)")


def _corre(tema, *extra, timeout=420):
    """El motor en una carpeta vacía, aislado (-I), sin cookies del navegador ni guardar nada."""
    if not MOTOR.exists():
        raise RuntimeError(f"no encuentro el motor de last30days en {MOTOR}")
    with tempfile.TemporaryDirectory(prefix="last30days-") as d:
        r = subprocess.run([PY, "-I", str(MOTOR), tema, "--auto-resolve", "--no-browser-cookies", "--save-dir", "", *extra],
                           capture_output=True, text=True, timeout=timeout, cwd=d,
                           env={**os.environ, "LAST30DAYS_LIBRARY_CONTEXT": "off"})
    if r.returncode or not r.stdout.strip():
        raise RuntimeError((r.stderr or r.stdout or "sin salida")[-300:])
    return r.stdout


def recorta(texto, tope=6000):
    """El informe del motor sin los consejos de instalación ni las líneas vacías de más, y con un tope."""
    lineas = [l for l in texto.splitlines() if not SOBRANTE.match(l)]
    t = re.sub(r"\n{3,}", "\n\n", "\n".join(lineas)).strip()
    return t if len(t) <= tope else t[:tope].rsplit("\n", 1)[0] + "\n(… cortado)"


def solo_polymarket(texto):
    """De un informe del motor, las líneas de los mercados («📊 Polymarket · US recession by end of 2026: 3.0% (down 4 pts
    this month) — url — closes …»): van al final del informe y un recorte normal se las comería."""
    l = [x.strip().lstrip("-").strip() for x in texto.splitlines() if x.strip().lstrip("-").strip().startswith("📊")]
    return "\n".join(f"- {x}" for x in l[:8]) or "(no hay mercados de Polymarket sobre esto)"


def evidencia(tema, dias=30, subreddits=SUBS, fuentes=None, tope=6000):
    extra = ["--emit=compact", "--days", str(dias), "--subreddits", subreddits]
    if fuentes:
        extra += ["--search", fuentes]
    salida = _corre(tema, *extra)
    if fuentes == "polymarket":
        return solo_polymarket(salida)
    return recorta(salida, tope)


def nombre_tema(nombre):
    """«NVIDIA Corporation» → «NVIDIA»; «Vanguard FTSE All-World UCITS ETF» → «Vanguard FTSE All-World»."""
    n = re.sub(r"(?i)\b(UCITS|ETF|Acc(umulating)?|Dist(ributing)?|USD|EUR|\(.*?\))\b.*$", "", nombre or "")
    n = re.sub(r"(?i)[,.]?\s*\b(corporation|corp|incorporated|inc|plc|ltd|s\.?a\.?|n\.?v\.?|ag|se|group|holdings?)\b\.?", "", n)
    return " ".join(n.split()).strip(" ,.-") or (nombre or "").strip()


def temas_cartera(solo_apuestas=False):
    """[(tema, tipo)] de lo que tienes ahora. solo_apuestas: acciones y cripto (lo que da noticias de un día)."""
    inf = inversiones.informe()
    out = []
    for x in inf["posiciones"]:
        if x["cantidad"] <= 0 or (solo_apuestas and x["tipo"] not in ("accion", "cripto")):
            continue
        out.append((nombre_tema(x["nombre"]), x["tipo"]))
    return out


def bloque_mercado(dias=30):
    """Lo que recibe el informe del sábado: lo que se dice de lo que tienes, del mercado y las apuestas de Polymarket."""
    partes = []
    pedidos = [(t, f"Lo que se dice de {t}", {}) for t, _ in temas_cartera()]
    pedidos += [("stock market", "El mercado en general", {}),
                ("AI stocks", "Las acciones de IA", {}),
                ("recession", "Polymarket: recesión", {"fuentes": "polymarket", "tope": 1500}),
                ("Fed rate cut", "Polymarket: tipos de la Fed", {"fuentes": "polymarket", "tope": 1500})]
    for tema, titulo, kw in pedidos:
        try:
            partes.append(f"#### {titulo} («{tema}», últimos {dias} días)\n\n" + evidencia(tema, dias=dias, **kw))
        except Exception as e:   # un tema que falla no deja sin informe
            partes.append(f"#### {titulo}\n\n(no disponible: {str(e)[:150]})")
    return "\n\n".join(partes)


def bloque_review(dias=7):
    """Lo que recibe la review del domingo: solo lo que tienes, la última semana."""
    partes = []
    for tema, _ in temas_cartera():
        try:
            partes.append(f"#### {tema}\n\n" + evidencia(tema, dias=dias, tope=4000))
        except Exception as e:
            partes.append(f"#### {tema}\n\n(no disponible: {str(e)[:150]})")
    return "\n\n".join(partes) or "(no tienes posiciones)"


# ---------- avisos de noticias gordas ----------
def fuerte(x):
    eng = x.get("engagement") or {}
    return any((eng.get(k) or 0) >= n for k, n in FUERTE.get(x.get("source"), ()))


def habla_de(x, tema):
    """Que el hilo hable de verdad de esa empresa (el motor también devuelve lo de alrededor)."""
    texto = f"{x.get('title') or ''} {x.get('summary') or ''}".lower()
    palabras = [p for p in re.split(r"\W+", tema.lower()) if len(p) >= 3]
    return bool(palabras) and all(p in texto for p in palabras[:2])


def _donde(x):
    if x.get("source") == "reddit":
        m = re.search(r"reddit\.com/r/([^/]+)", x.get("url") or "")
        return f"r/{m.group(1)}" if m else "Reddit"
    return {"hackernews": "Hacker News"}.get(x.get("source"), x.get("source") or "")


def _cuanto(x):
    e = x.get("engagement") or {}
    trozos = []
    for k, nombre in (("score", "votos"), ("points", "puntos"), ("num_comments", "comentarios"), ("comments", "comentarios")):
        if e.get(k):
            trozos.append(f"{int(e[k]):,} {nombre}".replace(",", "."))
    return ", ".join(trozos)


def mensaje(tema, items):
    import html
    lineas = [f"📰 <b>Se habla mucho de {html.escape(tema)}</b>"]
    for x in items:
        d = x.get("published_at") or ""
        cuando = f" ({int(d[8:10])}/{int(d[5:7])})" if len(d) >= 10 else ""
        lineas.append(f"• <a href=\"{html.escape(x.get('url') or '', quote=True)}\">{html.escape((x.get('title') or '')[:160])}</a>"
                      f"\n  {html.escape(_donde(x))} · {_cuanto(x)}{cuando}")
    lineas.append("\nEs lo que se comenta, sin verificar. Tu plan es a largo plazo: una noticia no es una orden.")
    return "\n".join(lineas)


def _vistos():
    try:
        return json.loads(VISTOS.read_text("utf-8"))
    except (OSError, ValueError):
        return {}


def nuevos(d, tema, vistos, tope=3):
    """Lo fuerte, que hable del tema y que no se haya avisado ya, lo más comentado primero."""
    l = [x for x in d.get("results", []) if fuerte(x) and habla_de(x, tema)
         and (x.get("url") or x.get("candidate_id")) not in vistos]
    peso = lambda x: max((v for v in (x.get("engagement") or {}).values() if isinstance(v, (int, float))), default=0)
    return sorted(l, key=peso, reverse=True)[:tope]


def avisos(ver=False, hoy=None):
    hoy = hoy or date.today()
    vistos = {k: v for k, v in _vistos().items() if v >= (hoy - timedelta(days=30)).isoformat()}
    mandados = []
    for tema, _ in temas_cartera(solo_apuestas=True):
        try:
            d = json.loads(_corre(tema, "--emit=json", "--days", "3", "--subreddits", SUBS))
        except Exception as e:
            print(f"{tema}: {e}", file=sys.stderr)
            continue
        l = nuevos(d, tema, vistos)
        if not l:
            continue
        msg = mensaje(tema, l)
        if ver:
            print(msg, "\n")
            continue
        inversiones._telegram(msg)
        for x in l:
            vistos[x.get("url") or x.get("candidate_id")] = hoy.isoformat()
        mandados.append(tema)
    if not ver:
        inversiones._escribe(VISTOS, vistos)
    return mandados


if __name__ == "__main__":
    if "--avisos" in sys.argv:
        print("avisado:", avisos(ver="--ver" in sys.argv) or "nada")
    elif "--mercado" in sys.argv:
        print(bloque_mercado())
    elif len(sys.argv) > 1 and not sys.argv[1].startswith("-"):
        print(evidencia(" ".join(sys.argv[1:])))
    else:
        print(__doc__)
