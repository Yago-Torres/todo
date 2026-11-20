"""Pregúntale a Claude (la sección «Claude» de Tom): un Claude que sabe todo lo tuyo y al que le preguntas lo que sea.

Lo pidió Yago (20/11): «un claude en Tom que tenga todo el contexto sobre mí y le pueda preguntar cosas».
- El contexto lo junta main.py (`contexto_yo()`): hábitos y rachas, plan y entrenos, carrera, peso, sueño y pasos,
  móvil, gastos del ciclo, cartera, calendario, pendientes, lo que usas y `yo.md` (quién eres, objetivos; junto a
  data.json, fuera del repo, lo editas tú). Además puede LEER el vault de Obsidian (Read, Grep, Glob, solo lectura)
  y buscar en la web. No puede cambiar nada: para hacer cosas, la voz de Tom o el bot.
- Conversaciones: cada mensaje va en un hilo; Claude ve los últimos turnos del suyo. «Nueva conversación» empieza otro.
- Como la Pregunta de Inversiones: se guarda «pensando» y se contesta en un hilo (Cloudflare corta a los 100 s); Tom
  mira la lista cada 3 s mientras algo piensa. `charla.json` junto a data.json, fuera del repo.
"""
import json
import os
import subprocess
import threading
import time
from datetime import date, datetime
from pathlib import Path

import inversiones

FICHERO = inversiones.DATOS.with_name("charla.json")
YO = inversiones.DATOS.with_name("yo.md")
VAULT = Path(os.getenv("VAULT", "/srv/obsidian/Yago_obsidian_vault"))
TURNOS = 6
_cerrojo = threading.Lock()

PROMPT = """Eres Claude, el asistente personal de quien te escribe. Lo sabes todo de su día a día porque tienes sus datos
(abajo, de hoy, {hoy}, {hora}) y puedes leer su vault de Obsidian (está en el directorio de trabajo: notas, diario,
proyectos, curro; búscalo con Grep/Glob y léelo con Read cuando la pregunta lo pida). Puedes buscar en la web si hace
falta un dato de fuera. No puedes cambiar nada: si te pide hacer algo (apuntar, mover, marcar), dile que se lo diga a
la voz de Tom o al bot y cómo decirlo.

Quién es (lo escribe él):
{yo}

Sus datos ahora (JSON):
{datos}

La conversación hasta ahora:
{previas}

Su mensaje: {q}

Contesta en español, de tú, directo y útil, como un amigo que lo sabe todo de él y no le dora la píldora: primero la
respuesta, luego el porqué con SUS números (fechas, cifras, rachas) cuando vengan al caso. Si los datos no bastan, dilo
y di qué faltaría. Si ves algo relevante que no ha preguntado (una racha a punto de romperse, un gasto raro, un
entreno que no cuadra con cómo duerme), dilo en una línea al final. Markdown sencillo, sin HTML, unas 250 palabras como
mucho salvo que pida más. Nada de consejos médicos o financieros tajantes: explica opciones y riesgos."""


def lee():
    try:
        l = json.loads(FICHERO.read_text("utf-8"))
    except (OSError, ValueError):
        return []
    ahora = time.time()
    for m in l:   # un reinicio a mitad deja uno «pensando» huérfano
        if m.get("estado") == "pensando" and ahora - m.get("t", ahora) > 10 * 60:
            m.update(estado="error", r="Se cortó mientras pensaba (¿reinicio?). Vuelve a preguntar.")
    return l


def _actualiza(id_, **cambios):
    with _cerrojo:
        l = lee()
        for m in l:
            if m["id"] == id_:
                m.update(cambios)
        inversiones._escribe(FICHERO, l)


def yo():
    try:
        return YO.read_text("utf-8").strip()[:4000] or "(vacío)"
    except OSError:
        return "(todavía no hay yo.md)"


def prompt(q, hilo, datos, ahora=None):
    ahora = ahora or datetime.now()
    previas = [m for m in reversed(lee()) if m.get("hilo") == hilo and m.get("estado") == "lista"][-TURNOS:]
    texto_previas = "\n".join(f"Él: {m['q']}\nTú: {m['r'][:1200]}" for m in previas) or "(empieza ahora)"
    return PROMPT.format(hoy=ahora.date().isoformat(), hora=ahora.strftime("%H:%M"), yo=yo(),
                         datos=json.dumps(datos, ensure_ascii=False, separators=(",", ":"), default=str)[:40000],
                         previas=texto_previas, q=q)


def _contesta(id_, texto):
    try:
        claude = os.environ.get("CLAUDE_BIN", str(Path.home() / ".local/bin/claude"))
        herramientas = "Read,Grep,Glob,WebSearch,WebFetch"
        r = subprocess.run([claude, "-p", "--model", os.environ.get("CHARLA_MODEL", "sonnet"),
                            "--tools", herramientas, "--allowedTools", herramientas, "--add-dir", str(VAULT),
                            "--strict-mcp-config", "--no-session-persistence"],
                           input=texto, capture_output=True, text=True, timeout=5 * 60,
                           cwd=str(VAULT) if VAULT.exists() else None, env={**os.environ, "CLAUDE_QUIEN": "charla"})
        if r.returncode or not r.stdout.strip():
            raise RuntimeError((r.stderr or r.stdout or "sin respuesta")[-300:])
        _actualiza(id_, estado="lista", r=r.stdout.strip()[:12000])
    except Exception as e:
        _actualiza(id_, estado="error", r=f"No he podido contestar: {str(e)[:300]}")


def pregunta(q, hilo, contexto):
    """`contexto`: función sin argumentos que devuelve los datos (main.contexto_yo). Devuelve el mensaje «pensando»."""
    q = " ".join(str(q or "").split())[:2000]
    if not q:
        raise ValueError("¿Qué le pregunto?")
    hilo = "".join(c for c in str(hilo or "") if c.isalnum())[:20] or "h" + str(time.time_ns())[-10:]
    with _cerrojo:
        l = lee()
        if sum(1 for m in l if m.get("estado") == "pensando") >= 2:
            raise ValueError("Ya hay dos mensajes pensándose: espera a que acaben")
        m = {"id": "c" + str(time.time_ns())[-12:], "hilo": hilo, "q": q, "r": "", "estado": "pensando", "t": time.time(),
             "cuando": datetime.now().isoformat(timespec="minutes")}
        inversiones._escribe(FICHERO, ([m] + l)[:200])
    try:
        datos = contexto()
    except Exception as e:
        datos = {"error": f"no se pudieron juntar los datos: {e}"}
    texto = prompt(q, hilo, datos)
    threading.Thread(target=_contesta, args=(m["id"], texto), daemon=True).start()
    return m


def borra(id_="", hilo=""):
    with _cerrojo:
        inversiones._escribe(FICHERO, [m for m in lee() if not (m["id"] == id_ or (hilo and m.get("hilo") == hilo))])


def hilos():
    """Los mensajes agrupados por conversación, la más reciente primero."""
    out = {}
    for m in lee():
        out.setdefault(m["hilo"], []).append(m)
    return [{"hilo": h, "mensajes": list(reversed(ms)), "cuando": ms[0]["cuando"]} for h, ms in out.items()]
