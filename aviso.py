"""Un aviso desde el servidor: primero el push de la app (la PWA de todo, subs.json); si no llega a ningún sitio, Telegram.

Lo pidió Yago (19/11): la app antes que Telegram. Tom no puede recibir push del servidor (sin cuenta de pago de Apple no
hay APNs), así que lo que se sabe de antemano (un plan de ahorro, el domingo de la review) lo programa Tom como aviso
local; lo que pasa de repente (una alerta de precio) llega por el push de la web y, si no hay suscripción viva, por Telegram.

    avisa("Título", "Cuerpo", "etiqueta", "/inversiones.html")   -> "push" | "telegram" | "nada"

Sin pywebpush (scripts lanzados con /usr/bin/python3) se salta el push y va por Telegram.
"""
import json
import os
import urllib.request
from pathlib import Path

HERE = Path(__file__).parent
SUBS = Path(os.getenv("TODO_SUBS", HERE / "subs.json"))
BOT_ENV = Path("/home/pi/bots/todo-bot/.env")
CONTACTO = "mailto:avisos@yagotg.dev"   # VAPID pide un contacto por si hay abusos


def _env(p):
    try:
        return {k.strip(): v.strip().strip('"') for k, v in (l.split("=", 1) for l in p.read_text().splitlines() if "=" in l)}
    except OSError:
        return {}


def push(titulo, cuerpo, tag, url="/"):
    """Cuántas suscripciones lo han recibido. Las caducadas (404/410) se quitan de subs.json."""
    try:
        from pywebpush import WebPushException, webpush
    except ImportError:
        return 0
    priv = os.getenv("VAPID_PRIV") or _env(HERE / ".env").get("VAPID_PRIV")
    if not priv:
        return 0
    try:
        subs = [s for s in json.loads(SUBS.read_text("utf-8")) if isinstance(s, dict)]
    except (OSError, ValueError):
        return 0
    carga = json.dumps({"titulo": titulo, "cuerpo": cuerpo, "tag": tag, "url": url}, ensure_ascii=False)
    ok, vivas = 0, []
    for s in subs:
        try:
            webpush(subscription_info=s, data=carga, vapid_private_key=priv, vapid_claims={"sub": CONTACTO}, ttl=6 * 3600)
            ok += 1
            vivas.append(s)
        except WebPushException as e:
            if getattr(e.response, "status_code", None) not in (404, 410):
                vivas.append(s)
        except Exception:
            vivas.append(s)
    if len(vivas) != len(subs):
        tmp = SUBS.with_name(SUBS.name + ".tmp")
        tmp.write_text(json.dumps(vivas, ensure_ascii=False), "utf-8")
        os.replace(tmp, SUBS)
    return ok


def telegram(texto, botones=None):
    e = {**_env(BOT_ENV), **{k: v for k, v in os.environ.items() if k in ("TELEGRAM_TOKEN", "TELEGRAM_USER_ID")}}
    if not e.get("TELEGRAM_TOKEN") or not e.get("TELEGRAM_USER_ID"):
        return False
    cuerpo = {"chat_id": int(e["TELEGRAM_USER_ID"]), "text": texto[:4096], "parse_mode": "HTML",
              "link_preview_options": {"is_disabled": True}}
    if botones:
        cuerpo["reply_markup"] = {"inline_keyboard": botones}
    try:
        req = urllib.request.Request(f"https://api.telegram.org/bot{e['TELEGRAM_TOKEN']}/sendMessage",
                                     json.dumps(cuerpo).encode(), {"Content-Type": "application/json"})
        urllib.request.urlopen(req, timeout=20).close()
        return True
    except Exception as ex:
        print("telegram:", ex, flush=True)
        return False


def avisa(titulo, cuerpo, tag, url="/", largo=None, ver=False):
    """`largo` (HTML) es lo que va por Telegram si hace falta; por defecto, título y cuerpo."""
    import html
    if ver:
        print(f"[aviso {tag}] {titulo} — {cuerpo} -> {url}")
        return "nada"
    if push(titulo, cuerpo, tag, url):
        return "push"
    enlace = f"https://todo.yagotg.dev{url}" if url.startswith("/") else url
    texto = largo or f"<b>{html.escape(titulo)}</b>\n{html.escape(cuerpo)}\n{enlace}"
    return "telegram" if telegram(texto) else "nada"
