"""Inversiones: cartera a mano, precios de Yahoo y la review del domingo.

Las operaciones se apuntan a mano (Trade Republic no tiene API y Yago no quiere guardar su PIN en la Pi).
Todo en euros: lo que pagaste por participación, con la comisión aparte. Los precios de lo que cotiza en otra
divisa se pasan a euros con el cambio del mismo día al bajarlos, así el cálculo no tiene que saber de divisas.

- `inversiones.json` (junto a data.json): perfil, activos y operaciones. Fuera de data.json: clean() se lo comería.
- `precios.json`: cierres diarios en euros por símbolo de Yahoo. Se puede borrar: se vuelve a bajar.
- `reviews-inversiones/AAAA-MM-DD.md`: las reviews (y una copia en el vault, `Areas/Finanzas/Reviews/`).

    python3 inversiones.py --precios        # lo que lanza inversiones-precios.timer
    python3 inversiones.py --review         # lo que lanza inversiones-review.timer (domingos)
    python3 inversiones.py --review --ver   # la review sin guardarla ni mandarla

Planes de ahorro y alertas de precio (19/11) los revisa `--precios` después de bajar los precios (`revisa()`):
- Un plan ({activo, importe, dia, comision}) apunta solo su compra cada mes, con el precio de ese día (estimado: se
  corrige a mano con el de Trade Republic). El id de la operación es `plan-<id>-<AAAA-MM>` y el mes queda en `hechos`:
  aunque la borres no vuelve, y lanzar el script dos veces no la duplica. Si el día cae en fin de semana, el lunes.
- Una alerta: «bajo» (precio ≤ valor), «sobre» (≥ valor) o «cae» (el día baja ≥ valor %; activo "*" = la cartera).
  Avisa una vez y se rearma cuando el precio vuelve un 2 % al otro lado («cae», una vez al día).
- Los avisos van por aviso.py: el push de la app primero y Telegram si no llega.
"""
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

HERE = Path(__file__).parent
DATOS = Path(os.getenv("TODO_DB", HERE / "data.json")).with_name("inversiones.json")
PRECIOS = DATOS.with_name("precios.json")
REVIEWS = DATOS.with_name("reviews-inversiones")
VAULT_REVIEWS = Path(os.getenv("VAULT", "/srv/obsidian/Yago_obsidian_vault")) / "Areas/Finanzas/Reviews"
AGENTE = "Mozilla/5.0 (X11; Linux aarch64)"   # sin navegador de verdad, Yahoo responde 429
TIPOS = ("etf", "fondo", "accion", "cripto", "bono", "liquidez", "otro")
OPERACIONES = ("compra", "venta", "dividendo")
# Bolsas en euros, por orden: Trade Republic opera en Xetra/LS Exchange, así que .DE es lo más parecido a su precio
EUROPA = (".DE", ".F", ".AS", ".PA", ".MI", ".MC", ".SG", ".MU", ".BE")
PERFIL = {"edad": None, "horizonte": "", "objetivo": "", "aportacion": 0, "estable": None, "emergencia": "",
          "tolerancia": "", "caida": "", "broker": "Trade Republic", "referencia": "VWCE.DE", "notas": "",
          "regimen": "comun", "perdidas_previas": 0, "intereses": {}}
VACIO = {"perfil": PERFIL, "activos": [], "operaciones": [], "planes": [], "alertas": []}
ALERTAS = ("bajo", "sobre", "cae")


# ---------- limpieza (como clean() de main.py: lo que no está aquí no se guarda) ----------
def _num(v, lo=0.0, hi=1e9):
    try:
        n = float(str(v).replace(",", "."))
    except (TypeError, ValueError):
        return None
    return n if lo <= n <= hi and n == n else None


def _txt(v, n=120):
    return " ".join(str(v or "").split())[:n]


def _id(v):
    return re.sub(r"[^a-z0-9-]", "", str(v or "").lower().replace(" ", "-"))[:40]


def limpia(d):
    d = d if isinstance(d, dict) else {}
    p = d.get("perfil") if isinstance(d.get("perfil"), dict) else {}
    perfil = {
        "edad": int(e) if (e := _num(p.get("edad"), 14, 100)) else None,
        "horizonte": _txt(p.get("horizonte")), "objetivo": _txt(p.get("objetivo"), 300),
        "aportacion": _num(p.get("aportacion"), 0, 1e6) or 0,
        "estable": p.get("estable") if isinstance(p.get("estable"), bool) else None,
        "emergencia": _txt(p.get("emergencia")), "tolerancia": _txt(p.get("tolerancia"), 40),
        "caida": _txt(p.get("caida"), 40), "broker": _txt(p.get("broker")) or PERFIL["broker"],
        "referencia": _txt(p.get("referencia"), 20).upper() or PERFIL["referencia"],
        "notas": _txt(p.get("notas"), 1000),
        "regimen": p.get("regimen") if p.get("regimen") in ("comun", "foral") else "comun",
        "perdidas_previas": _num(p.get("perdidas_previas"), 0, 1e8) or 0,
        # intereses de la cuenta del broker por año ({"2026": 31.2}): rendimientos del capital mobiliario
        "intereses": {k: n for k, v in (p.get("intereses") if isinstance(p.get("intereses"), dict) else {}).items()
                      if re.fullmatch(r"20\d\d", str(k)) and (n := _num(v, 0, 1e7))},
    }
    activos, vistos = [], set()
    for a in d.get("activos") or []:
        if not isinstance(a, dict) or not (i := _id(a.get("id"))) or i in vistos or not _txt(a.get("simbolo")):
            continue
        vistos.add(i)
        activos.append({"id": i, "nombre": _txt(a.get("nombre")) or a["simbolo"], "isin": _txt(a.get("isin"), 12).upper(),
                        "simbolo": _txt(a.get("simbolo"), 20).upper(), "tipo": a.get("tipo") if a.get("tipo") in TIPOS else "otro",
                        "divisa": _txt(a.get("divisa"), 3).upper() or "EUR", "ter": _num(a.get("ter"), 0, 10),
                        "papel": _txt(a.get("papel"), 200)})
    ops = []
    for o in d.get("operaciones") or []:
        if not isinstance(o, dict) or o.get("activo") not in vistos or o.get("tipo") not in OPERACIONES:
            continue
        try:
            dia = date.fromisoformat(str(o.get("fecha"))[:10]).isoformat()
        except ValueError:
            continue
        cant, precio = _num(o.get("cantidad"), 0, 1e9) or 0, _num(o.get("precio"), 0, 1e9) or 0
        if o["tipo"] != "dividendo" and not (cant and precio):
            continue
        if o["tipo"] == "dividendo" and not precio:
            continue
        ops.append({"id": _id(o.get("id")) or f"op{len(ops)}", "fecha": dia, "activo": o["activo"], "tipo": o["tipo"],
                    # dividendo: precio = importe neto cobrado, cantidad 0
                    "cantidad": cant if o["tipo"] != "dividendo" else 0, "precio": precio,
                    "comision": _num(o.get("comision"), 0, 1e6) or 0, "nota": _txt(o.get("nota"), 200),
                    # de qué plan de ahorro sale (precio estimado hasta que lo corrijas) y de dónde vino
                    "plan": _id(o.get("plan")), "src": o.get("src") if o.get("src") in ("web", "plan", "foto", "tom") else ""})
    ops.sort(key=lambda o: (o["fecha"], o["tipo"] != "compra"))
    planes = []
    for x in d.get("planes") or []:
        if not isinstance(x, dict) or x.get("activo") not in vistos or not (imp := _num(x.get("importe"), 1, 1e6)):
            continue
        try:
            desde = date.fromisoformat(str(x.get("desde"))[:10]).isoformat()
        except ValueError:
            desde = date.today().isoformat()
        planes.append({"id": _id(x.get("id")) or f"p{len(planes)}", "activo": x["activo"], "importe": imp,
                       "dia": int(_num(x.get("dia"), 1, 28) or 1), "comision": _num(x.get("comision"), 0, 100) or 0,
                       "desde": desde, "pausado": x.get("pausado") is True, "nota": _txt(x.get("nota"), 120),
                       "hechos": sorted({m for m in x.get("hechos") or [] if re.fullmatch(r"20\d\d-\d\d", str(m))})[-120:]})
    alertas = []
    for x in d.get("alertas") or []:
        if not isinstance(x, dict) or x.get("tipo") not in ALERTAS or not (v := _num(x.get("valor"), 0.0001, 1e9)):
            continue
        if x.get("activo") != "*" and x.get("activo") not in vistos or (x.get("activo") == "*" and x["tipo"] != "cae"):
            continue
        alertas.append({"id": _id(x.get("id")) or f"a{len(alertas)}", "activo": x["activo"], "tipo": x["tipo"],
                        "valor": v if x["tipo"] != "cae" else min(v, 50), "nota": _txt(x.get("nota"), 120),
                        "armada": x.get("armada") is not False, "ultima": _txt(x.get("ultima"), 10)})
    return {"perfil": perfil, "activos": activos, "operaciones": ops, "planes": planes, "alertas": alertas}


def lee():
    return limpia(json.loads(DATOS.read_text("utf-8"))) if DATOS.exists() else limpia(VACIO)


def _escribe(p, cosa):
    tmp = p.with_name(f".{p.name}.tmp")
    tmp.write_text(json.dumps(cosa, ensure_ascii=False, indent=1), "utf-8")
    tmp.replace(p)


def guarda(d):
    d = limpia(d)
    _escribe(DATOS, d)
    return d


def lee_precios():
    try:
        return json.loads(PRECIOS.read_text("utf-8"))
    except (OSError, ValueError):
        return {}


# ---------- Yahoo ----------
def _yahoo(url):
    req = urllib.request.Request(url, headers={"User-Agent": AGENTE})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read())


def busca(q):
    """ISIN, ticker o nombre → candidatos de Yahoo, primero los que cotizan en euros (Xetra antes que nada)."""
    q = _txt(q, 60)
    if not q:
        return []
    url = "https://query2.finance.yahoo.com/v1/finance/search?" + urllib.parse.urlencode({"q": q, "quotesCount": 10, "newsCount": 0})
    cands = [{"simbolo": x["symbol"], "nombre": x.get("longname") or x.get("shortname") or x["symbol"],
              "bolsa": x.get("exchDisp") or x.get("exchange") or "", "clase": x.get("quoteType") or ""}
             for x in _yahoo(url).get("quotes", []) if x.get("symbol")]
    # Buscar por ISIN suele dar solo Londres o Stuttgart (y en Xetra el ticker puede ser otro: VWRA.L es VWCE.DE);
    # buscando por el nombre largo sí aparece Xetra
    if re.fullmatch(r"[A-Z]{2}[A-Z0-9]{9}\d", q.upper()) and not any(c["simbolo"].endswith(".DE") for c in cands):
        nombre = next((c["nombre"] for c in cands if c["nombre"] != c["simbolo"]), "")
        if nombre:
            url = "https://query2.finance.yahoo.com/v1/finance/search?" + urllib.parse.urlencode({"q": nombre, "quotesCount": 10, "newsCount": 0})
            cands += [{"simbolo": x["symbol"], "nombre": x.get("longname") or x.get("shortname") or x["symbol"],
                       "bolsa": x.get("exchDisp") or x.get("exchange") or "", "clase": x.get("quoteType") or ""}
                      for x in _yahoo(url).get("quotes", []) if (x.get("longname") or "") == nombre]
    unicos = list({c["simbolo"]: c for c in cands}.values())
    orden = lambda c: next((i for i, s in enumerate(EUROPA) if c["simbolo"].endswith(s)), len(EUROPA) + (c["simbolo"].startswith(q.upper())))
    return sorted(unicos, key=orden)


def _serie(simbolo, rango):
    """Cierres diarios {dia: precio} en la divisa de cotización, la divisa y el último precio."""
    url = f"https://query1.finance.yahoo.com/v8/finance/chart/{urllib.parse.quote(simbolo)}?range={rango}&interval=1d"
    r = _yahoo(url)["chart"]["result"][0]
    m, cierres = r["meta"], r["indicators"]["quote"][0].get("close") or []
    divisa, k = m.get("currency") or "EUR", 1
    if divisa in ("GBp", "GBX", "ILA", "ZAc"):     # peniques y centavos: Yahoo da el precio en céntimos
        divisa, k = {"GBp": "GBP", "GBX": "GBP", "ILA": "ILS", "ZAc": "ZAR"}[divisa], 100
    dias = {datetime.fromtimestamp(t + (m.get("gmtoffset") or 0), timezone.utc).date().isoformat(): round(c / k, 6)
            for t, c in zip(r.get("timestamp") or [], cierres) if c}
    ultimo = m.get("regularMarketPrice")
    return dias, divisa.upper(), (round(ultimo / k, 6) if ultimo else None), m


def _a_euros(dias, cambio):
    """Pasa cada cierre a euros con el cambio de ese día (o el último conocido antes)."""
    if cambio is None:
        return dias
    claves, out, ult = sorted(cambio), {}, None
    j = 0
    for d in sorted(dias):
        while j < len(claves) and claves[j] <= d:
            ult = cambio[claves[j]]
            j += 1
        if ult := ult or (cambio[claves[0]] if claves else None):
            out[d] = round(dias[d] / ult, 6)
    return out


LS = "https://www.ls-tc.de/_rpc/json/instrument"


def _ls_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.load(r)


def precio_ls(isin, ls_id=None):
    """Precio en vivo de Lang & Schwarz (de donde saca el suyo Trade Republic; cotiza de 7:30 a 23:00) por ISIN.
    Devuelve (id, último, cierre anterior, día del último) o None. Las horas de L&S vienen en hora alemana como si fueran UTC."""
    if not ls_id:
        res = _ls_json(f"https://www.ls-tc.de/_rpc/json/.lstc/instrument/search/main?q={urllib.parse.quote(isin)}&localeId=2")
        res = [x for x in res if x.get("isin") == isin]
        if not res:
            return None
        ls_id = res[0]["instrumentId"]
    j = _ls_json(f"{LS}/chart/dataForInstrument?instrumentId={int(ls_id)}")
    datos = (j.get("series", {}).get("intraday") or {}).get("data") or []
    if not datos:
        return None
    ms, ultimo = datos[-1]
    dia = datetime.fromtimestamp(ms / 1000, timezone.utc).date().isoformat()
    previo = next((x["value"] for x in j.get("info", {}).get("plotlines", []) if x.get("id") == "previousDay"), None)
    return ls_id, float(ultimo), previo, dia


def actualiza(simbolos=None, rango=None):
    """Baja precios de los símbolos (por defecto, los de la cartera y la referencia). Devuelve los que fallaron."""
    d, p = lee(), lee_precios()
    simbolos = simbolos or sorted({a["simbolo"] for a in d["activos"]} | {d["perfil"]["referencia"]})
    cambios, fallos = {}, []
    isines = {a["simbolo"]: a["isin"] for a in d["activos"] if a.get("isin")}
    for s in simbolos:
        try:
            r = rango or ("1mo" if s in p and p[s].get("dias") else "10y")
            dias, divisa, ultimo, meta = _serie(s, r)
            if divisa != "EUR":
                if divisa not in cambios:
                    # EURUSD=X es cuántos dólares vale un euro: precio en euros = precio / cambio
                    cambios[divisa] = _serie(f"EUR{divisa}=X", r)[0]
                ult_cambio = cambios[divisa][max(cambios[divisa])] if cambios[divisa] else None
                dias = _a_euros(dias, cambios[divisa])
                ultimo = round(ultimo / ult_cambio, 6) if ultimo and ult_cambio else None
            viejo = p.get(s, {})
            p[s] = {"divisa": divisa, "nombre": meta.get("longName") or meta.get("shortName") or viejo.get("nombre") or s,
                    "dias": {**viejo.get("dias", {}), **dias}, "ultimo": ultimo, "hora": datetime.now().isoformat(timespec="minutes")}
            isin = isines.get(s)
            if isin:   # con ISIN, el precio de ahora es el de L&S (el que ves en Trade Republic); Yahoo queda para el histórico
                try:
                    ls = precio_ls(isin, viejo.get("ls_id") if viejo.get("isin") == isin else None)
                    if ls:
                        hoy = date.today().isoformat()
                        p[s].update({"isin": isin, "ls_id": ls[0], "ultimo": ls[1], "fuente": "L&S",
                                     "ayer": (ls[2] if ls[3] == hoy else ls[1]) if ls[2] else None})
                except Exception as e:
                    fallos.append(f"{s} (L&S): {e}")
        except Exception as e:   # un símbolo que falla no tumba los demás
            fallos.append(f"{s}: {e}")
        time.sleep(.3)
    _escribe(PRECIOS, p)
    return fallos


# ---------- planes de ahorro y alertas (los revisa --precios) ----------
def dia_plan(anio, mes, dia):
    """El día que se ejecuta el plan ese mes: si cae en fin de semana, el lunes siguiente."""
    d = date(anio, mes, dia)
    return d + timedelta(days=(7 - d.weekday()) % 7) if d.weekday() >= 5 else d


def proximo_plan(x, hoy=None):
    hoy = hoy or date.today()
    for n in range(0, 3):
        a, m = (hoy.year * 12 + hoy.month - 1 + n) // 12, (hoy.month - 1 + n) % 12 + 1
        d = dia_plan(a, m, x["dia"])
        if d >= hoy and f"{a}-{m:02d}" not in x["hechos"] and d.isoformat() >= x["desde"]:
            return d.isoformat()
    return None


def _precio_dia(p, simbolo, dia, hoy):
    s = p.get(simbolo) or {}
    if dia == hoy and s.get("ultimo"):
        return s["ultimo"]
    dias = s.get("dias") or {}
    if dia >= hoy:
        return dias.get(dia)
    # festivo o antes de la primera cotización bajada: la siguiente de esa semana
    despues = [k for k in dias if dia <= k <= (date.fromisoformat(dia) + timedelta(days=5)).isoformat()]
    return dias[min(despues)] if despues else _precio_en(dias, dia)


def ejecuta_planes(d, p, hoy=None):
    """Apunta en `d` las compras de los planes que ya tocaban. Devuelve [(plan, operación)]."""
    hoy = hoy or date.today()
    activos = {a["id"]: a for a in d["activos"]}
    hechas = []
    for x in d["planes"]:
        if x["pausado"]:
            continue
        ini = date.fromisoformat(x["desde"])
        a, m = ini.year, ini.month
        while (a, m) <= (hoy.year, hoy.month):
            mes, cuando = f"{a}-{m:02d}", dia_plan(a, m, x["dia"])
            if mes not in x["hechos"] and ini <= cuando <= hoy:
                precio = _precio_dia(p, activos[x["activo"]]["simbolo"], cuando.isoformat(), hoy.isoformat())
                if precio:
                    o = {"id": f"plan-{x['id']}-{mes}", "fecha": cuando.isoformat(), "activo": x["activo"], "tipo": "compra",
                         "cantidad": round((x["importe"] - x["comision"]) / precio, 6), "precio": round(precio, 4),
                         "comision": x["comision"], "nota": "Plan de ahorro · precio estimado: corrígelo con el de Trade Republic",
                         "plan": x["id"], "src": "plan"}
                    d["operaciones"] = [y for y in d["operaciones"] if y["id"] != o["id"]] + [o]
                    x["hechos"] = sorted(set(x["hechos"]) | {mes})
                    hechas.append((x, o))
            a, m = (a + 1, 1) if m == 12 else (a, m + 1)
    return hechas


def _cambio_dia(s):
    """(precio de ahora, % del día) de un símbolo de precios.json."""
    ahora = s.get("ultimo") or (s["dias"][max(s["dias"])] if s.get("dias") else None)
    ayer = s.get("ayer")
    if not ayer and s.get("dias"):
        hoy = date.today().isoformat()
        previos = [k for k in s["dias"] if k < hoy]
        ayer = s["dias"][max(previos)] if previos else None
    return ahora, (round((ahora / ayer - 1) * 100, 2) if ahora and ayer else None)


def revisa_alertas(d, p, hoy=None):
    """Las alertas que saltan ahora: [(alerta, texto)]. Marca en `d` las disparadas y rearma las que volvieron."""
    hoy = (hoy or date.today()).isoformat()
    activos = {a["id"]: a for a in d["activos"]}
    saltan = []
    for x in d["alertas"]:
        if x["activo"] == "*":
            pos = posiciones(d["operaciones"], d["activos"], p)
            valor = sum(y["valor"] or 0 for y in pos)
            dia = sum(y["dia_eur"] or 0 for y in pos)
            cambio = round(dia / (valor - dia) * 100, 2) if valor - dia > 0 else None
            nombre, precio = "Tu cartera", valor
        else:
            a = activos[x["activo"]]
            precio, cambio = _cambio_dia(p.get(a["simbolo"]) or {})
            nombre = a["nombre"]
        if precio is None:
            continue
        if x["tipo"] == "cae":
            if cambio is not None and cambio <= -x["valor"] and x["ultima"] != hoy:
                x["ultima"] = hoy
                caida = f"{abs(cambio):.1f}".replace(".", ",")
                saltan.append((x, f"{nombre} cae un {caida} % hoy" + (f" ({_e(precio)})" if x["activo"] != "*" else "")))
            continue
        cruza = precio <= x["valor"] if x["tipo"] == "bajo" else precio >= x["valor"]
        vuelve = precio > x["valor"] * 1.02 if x["tipo"] == "bajo" else precio < x["valor"] * 0.98
        if x["armada"] and cruza:
            x["armada"], x["ultima"] = False, hoy
            saltan.append((x, f"{nombre} está a {_e(precio)}: {'por debajo' if x['tipo'] == 'bajo' else 'por encima'} de {_e(x['valor'])}"))
        elif not x["armada"] and vuelve:
            x["armada"] = True
    return saltan


def revisa(hoy=None, ver=False):
    """Tras bajar precios: planes que tocan y alertas que saltan. Guarda y avisa (push de la app; si no, Telegram)."""
    import aviso
    d, p = lee(), lee_precios()
    planes = ejecuta_planes(d, p, hoy)
    alertas = revisa_alertas(d, p, hoy)
    if (planes or alertas or any(not x["armada"] for x in d["alertas"])) and not ver:
        actual = lee()   # lo último del disco (la web pudo guardar entre medias): solo se le pasan los cambios de aquí
        actual["operaciones"] = [y for y in actual["operaciones"] if y["id"] not in {o["id"] for _, o in planes}] + [o for _, o in planes]
        por_id = {x["id"]: x for x in d["planes"]}
        for x in actual["planes"]:
            if x["id"] in por_id:
                x["hechos"] = sorted(set(x["hechos"]) | set(por_id[x["id"]]["hechos"]))
        por_id = {x["id"]: x for x in d["alertas"]}
        for x in actual["alertas"]:
            if x["id"] in por_id and (x["tipo"], x["valor"]) == (por_id[x["id"]]["tipo"], por_id[x["id"]]["valor"]):
                x["armada"], x["ultima"] = por_id[x["id"]]["armada"], por_id[x["id"]]["ultima"]
        guarda(actual)
    nombres = {a["id"]: a["nombre"] for a in d["activos"]}
    for x, o in planes:
        aviso.avisa("Plan de ahorro", f"{_e(x['importe'])} en {nombres[x['activo']]}: {str(o['cantidad']).replace('.', ',')} part. a {_e(o['precio'])} "
                    "(precio estimado; corrígelo si TR dio otro)", f"plan-{x['id']}", "/inversiones.html#operaciones", ver=ver)
    for x, texto in alertas:
        aviso.avisa("Alerta de precio", texto + (f" · {x['nota']}" if x["nota"] else ""), f"alerta-{x['id']}",
                    "/inversiones.html#cartera", ver=ver)
    return planes, alertas


# ---------- cálculo ----------
def _precio_en(serie, dia):
    """Último cierre en o antes de `dia` (fines de semana y festivos arrastran el viernes)."""
    ant = [d for d in serie if d <= dia]
    return serie[max(ant)] if ant else None


def posiciones(ops, activos, precios, hoy=None):
    """FIFO por activo, como Hacienda: las primeras que compraste son las primeras que vendes."""
    hoy = (hoy or date.today()).isoformat()
    por = {a["id"]: {"lotes": [], "realizado": 0.0, "dividendos": 0.0, "comisiones": 0.0, "aportado": 0.0, "retirado": 0.0, "hoy_n": 0.0, "hoy_eur": 0.0}
           for a in activos}
    for o in ops:
        x = por.get(o["activo"])
        if x is None or o["fecha"] > hoy:
            continue
        x["comisiones"] += o["comision"]
        if o["tipo"] == "compra":
            coste = o["cantidad"] * o["precio"] + o["comision"]
            x["lotes"].append([o["cantidad"], coste / o["cantidad"]])
            if o["fecha"] == hoy:   # lo comprado hoy cuenta para «hoy» desde el precio de compra, no desde el cierre de ayer
                x["hoy_n"] += o["cantidad"]
                x["hoy_eur"] += o["cantidad"] * o["precio"]
            x["aportado"] += coste
        elif o["tipo"] == "venta":
            falta, coste = o["cantidad"], 0.0
            while falta > 1e-9 and x["lotes"]:
                n = min(falta, x["lotes"][0][0])
                coste += n * x["lotes"][0][1]
                x["lotes"][0][0] -= n
                falta -= n
                if x["lotes"][0][0] <= 1e-9:
                    x["lotes"].pop(0)
            ingreso = (o["cantidad"] - falta) * o["precio"] - o["comision"]
            x["realizado"] += ingreso - coste
            x["retirado"] += ingreso
        else:
            x["dividendos"] += o["precio"]
    salida = []
    for a in activos:
        x, serie = por[a["id"]], precios.get(a["simbolo"], {})
        cant = sum(n for n, _ in x["lotes"])
        coste = sum(n * c for n, c in x["lotes"])
        precio = serie.get("ultimo") or _precio_en(serie.get("dias", {}), hoy)
        dias = sorted(serie.get("dias", {}))
        ayer = serie["dias"][dias[-2]] if len(dias) >= 2 else None
        if serie.get("dias") and dias[-1] < hoy:   # el último cierre no es de hoy: «ayer» es ese cierre
            ayer = serie["dias"][dias[-1]]
        if serie.get("ayer"):   # con L&S, «hoy» va contra su cierre de ayer, como en Trade Republic
            ayer = serie["ayer"]
        valor = cant * precio if precio is not None else None
        n_hoy = min(x["hoy_n"], cant)
        base = (cant - n_hoy) * ayer + (x["hoy_eur"] * n_hoy / x["hoy_n"] if n_hoy else 0) if ayer or n_hoy else None
        if not ayer and n_hoy < cant:
            base = None
        dia_eur = valor - base if valor is not None and base else None
        salida.append({**a, "cantidad": round(cant, 8), "coste": round(coste, 2), "coste_medio": round(coste / cant, 4) if cant else None,
                       "precio": precio, "valor": round(valor, 2) if valor is not None else None,
                       "latente": round(valor - coste, 2) if valor is not None else None,
                       "rent": round((valor / coste - 1) * 100, 2) if valor is not None and coste else None,
                       "dia": round(dia_eur / base * 100, 2) if dia_eur is not None else None,
                       "dia_eur": round(dia_eur, 2) if dia_eur is not None else None,
                       "realizado": round(x["realizado"], 2), "dividendos": round(x["dividendos"], 2),
                       "comisiones": round(x["comisiones"], 2), "aportado": round(x["aportado"], 2), "retirado": round(x["retirado"], 2),
                       "precio_hora": serie.get("hora")})
    total = sum(p["valor"] or 0 for p in salida)
    for p in salida:
        p["peso"] = round((p["valor"] or 0) / total * 100, 2) if total else 0
    return salida


def serie_cartera(ops, activos, precios, referencia, hoy=None):
    """Día a día: valor, dinero metido (neto de ventas) y lo que tendrías si cada euro hubiera ido a la referencia."""
    hoy = hoy or date.today()
    if not ops:
        return []
    simbolo = {a["id"]: a["simbolo"] for a in activos}
    ref = precios.get(referencia, {}).get("dias", {})
    d, fin, i = date.fromisoformat(ops[0]["fecha"]), hoy, 0
    cant, metido, ref_cant, out = {}, 0.0, 0.0, []
    cache = {s: sorted(precios.get(s, {}).get("dias", {}).items()) for s in set(simbolo.values())}
    ult = {}
    while d <= fin:
        dia = d.isoformat()
        for s, filas in cache.items():   # arrastra el último cierre conocido
            while filas and filas[0][0] <= dia:
                ult[s] = filas.pop(0)[1]
        ref_hoy = _precio_en(ref, dia)
        while i < len(ops) and ops[i]["fecha"] <= dia:
            o = ops[i]
            i += 1
            if o["tipo"] == "dividendo":
                continue
            signo = 1 if o["tipo"] == "compra" else -1
            cant[o["activo"]] = cant.get(o["activo"], 0) + signo * o["cantidad"]
            dinero = o["cantidad"] * o["precio"] + signo * o["comision"]
            metido += signo * dinero
            if ref_hoy:
                ref_cant += signo * dinero / ref_hoy
        if d.weekday() < 5 or d == fin:
            valor = sum(c * ult.get(simbolo[a], 0) for a, c in cant.items() if c > 1e-9)
            out.append({"dia": dia, "valor": round(valor, 2), "metido": round(metido, 2),
                        "referencia": round(ref_cant * ref_hoy, 2) if ref_hoy and ref_cant else None})
        d += timedelta(days=1)
    return out


def proyeccion(valor, mensual, anios=20, escenarios=None):
    """Interés compuesto mensual con aportación fija. Tasas nominales anuales, explícitas a propósito."""
    escenarios = escenarios or {"pesimista": 3.0, "base": 6.0, "optimista": 8.5}
    out = {}
    for nombre, tasa in escenarios.items():
        r, v, fila = (1 + tasa / 100) ** (1 / 12) - 1, valor, [round(valor)]
        for _ in range(anios):
            for _ in range(12):
                v = v * (1 + r) + mensual
            fila.append(round(v))
        out[nombre] = {"tasa": tasa, "anios": fila}
    out["aportado"] = {"anios": [round(valor + mensual * 12 * n) for n in range(anios + 1)]}
    return out


# Caídas de pico a valle aproximadas, en euros. Supuestos para el stress test, no datos exactos.
CRISIS = {
    "2008 (crisis financiera)": {"etf": -50, "fondo": -50, "accion": -55, "cripto": -80, "bono": 5, "liquidez": 0, "otro": -40},
    "2020 (covid)": {"etf": -33, "fondo": -33, "accion": -38, "cripto": -50, "bono": -3, "liquidez": 0, "otro": -25},
    "2022 (tipos e inflación)": {"etf": -16, "fondo": -16, "accion": -25, "cripto": -75, "bono": -17, "liquidez": 0, "otro": -15},
}


def stress(pos):
    return {nombre: round(sum((p["valor"] or 0) * caida.get(p["tipo"], -40) / 100 for p in pos), 2) for nombre, caida in CRISIS.items()}


def informe(hoy=None):
    d, p = lee(), lee_precios()
    pos = posiciones(d["operaciones"], d["activos"], p, hoy)
    valor = round(sum(x["valor"] or 0 for x in pos), 2)
    coste = round(sum(x["coste"] for x in pos), 2)
    serie = serie_cartera(d["operaciones"], d["activos"], p, d["perfil"]["referencia"], hoy)
    reparto = {}
    for x in pos:
        if x["valor"]:
            reparto[x["tipo"]] = round(reparto.get(x["tipo"], 0) + x["peso"], 2)
    ter = sum((x["ter"] or 0) * x["peso"] for x in pos if x["ter"] is not None) / 100
    fz = fiscal(d, pos, hoy)
    return {
        "perfil": d["perfil"], "activos": d["activos"], "operaciones": d["operaciones"], "posiciones": pos,
        "planes": [{**x, "proximo": proximo_plan(x, hoy)} for x in d["planes"]], "alertas": d["alertas"],
        "leccion": leccion(),
        "total": {"valor": valor, "coste": coste, "latente": round(valor - coste, 2),
                  "rent": round((valor / coste - 1) * 100, 2) if coste else None,
                  "realizado": round(sum(x["realizado"] for x in pos), 2), "dividendos": round(sum(x["dividendos"] for x in pos), 2),
                  "comisiones": round(sum(x["comisiones"] for x in pos), 2), "ter_medio": round(ter, 3),
                  "dia": round(sum(x["dia_eur"] or 0 for x in pos), 2)},
        "reparto": reparto, "serie": serie,
        "historicos": {a["simbolo"]: dict(sorted(p.get(a["simbolo"], {}).get("dias", {}).items())[-1300:]) for a in d["activos"]},
        "referencia": {"simbolo": d["perfil"]["referencia"], "nombre": p.get(d["perfil"]["referencia"], {}).get("nombre")},
        "proyeccion": proyeccion(valor, d["perfil"]["aportacion"]), "stress": stress(pos), "fiscal": fz, "declaracion": declaracion(d, fz, valor, hoy),
        "reviews": reviews(),
    }


# ---------- impuestos (IRPF, base del ahorro, régimen común) ----------
# Escala estatal + autonómica del ahorro desde 2025. Es igual en todas las comunidades de régimen común;
# Navarra y País Vasco tienen la suya (perfil «foral»: se avisa de que la cifra es orientativa).
TRAMOS_AHORRO = [(6000, 19), (50000, 21), (200000, 23), (300000, 27), (None, 30)]
DOS_MESES = 61   # regla antiaplicación: comprar lo mismo 2 meses antes o después de vender con pérdida aplaza la pérdida


def cuota_ahorro(base):
    """Impuesto de una base del ahorro con la escala por tramos."""
    cuota, desde = 0.0, 0.0
    for hasta, tipo in TRAMOS_AHORRO:
        if base <= desde:
            break
        tramo = (min(base, hasta) if hasta else base) - desde
        cuota += tramo * tipo / 100
        desde = hasta or base
    return round(cuota, 2)


def tipo_marginal(base):
    return next(tipo for hasta, tipo in TRAMOS_AHORRO if hasta is None or base < hasta)


def liquida(ganancias, rendimientos, previas=0.0):
    """Integra y compensa como la renta: ganancias de ventas (G) y dividendos/intereses (R) por separado; el saldo
    negativo de uno compensa hasta el 25 % del otro; las pérdidas de años anteriores van primero contra G y luego contra
    el 25 % de R. Devuelve base, cuota y pérdidas que quedan para los 4 años siguientes."""
    g, r, sobra = ganancias, rendimientos, 0.0
    if g < 0:
        c = min(-g, .25 * max(r, 0))
        r, sobra, g = r - c, -g - c, 0.0
    elif r < 0:
        c = min(-r, .25 * g)
        g, r = g - c, 0.0
    usa = min(previas, max(g, 0))
    g, previas = g - usa, previas - usa
    usa = min(previas, .25 * max(r, 0))
    r, previas = r - usa, previas - usa
    base = max(g, 0) + max(r, 0)
    return {"base": round(base, 2), "cuota": cuota_ahorro(base), "pendientes": round(sobra + previas, 2)}


def _e(n, dec=2):
    """1234.5 → «1.234,50 €»"""
    return f"{n:,.{dec}f}".replace(",", " ").replace(".", ",").replace(" ", ".") + " €"


def fiscal(d, pos, hoy=None):
    """Lo que toca en la renta de este año y lo que te quedaría si vendieras hoy, con FIFO y fechas de cada lote."""
    hoy = hoy or date.today()
    anio, h = hoy.year, hoy.isoformat()
    activos = {a["id"]: a for a in d["activos"]}
    lotes, ventas, divid = {}, [], 0.0
    compras = {}
    for o in d["operaciones"]:
        if o["fecha"] > h:
            continue
        if o["tipo"] == "compra":
            lotes.setdefault(o["activo"], []).append([o["cantidad"], (o["cantidad"] * o["precio"] + o["comision"]) / o["cantidad"], o["fecha"]])
            compras.setdefault(o["activo"], []).append(o["fecha"])
        elif o["tipo"] == "venta":
            falta, adq, fechas, ls = o["cantidad"], 0.0, [], lotes.setdefault(o["activo"], [])
            while falta > 1e-9 and ls:
                n = min(falta, ls[0][0])
                adq += n * ls[0][1]
                fechas.append(ls[0][2])
                ls[0][0] -= n
                falta -= n
                if ls[0][0] <= 1e-9:
                    ls.pop(0)
            if o["fecha"][:4] != str(anio):
                continue
            trans = (o["cantidad"] - falta) * o["precio"] - o["comision"]
            v = {"fecha": o["fecha"], "activo": o["activo"], "nombre": activos[o["activo"]]["nombre"],
                 "isin": activos[o["activo"]]["isin"], "cantidad": round(o["cantidad"] - falta, 8),
                 "compra": min(fechas) if fechas else None, "compra_hasta": max(fechas) if fechas else None,
                 "adquisicion": round(adq, 2), "transmision": round(trans, 2), "resultado": round(trans - adq, 2), "diferida": False}
            v["_vendidas"] = set(fechas)
            ventas.append(v)
        elif o["fecha"][:4] == str(anio):
            divid += o["precio"]
    intereses = d["perfil"].get("intereses", {}).get(str(anio), 0)
    # Pérdida aplazada: compraste lo mismo 2 meses antes o después de vender (sin contar los títulos que vendiste)
    # y aún tienes títulos. Se mira al final para ver también las compras posteriores a la venta.
    quedan = {k: sum(n for n, *_ in v) for k, v in lotes.items()}
    for v in ventas:
        vendidas, dia = v.pop("_vendidas"), date.fromisoformat(v["fecha"])
        ventana = any(abs((date.fromisoformat(c) - dia).days) <= DOS_MESES for c in compras.get(v["activo"], []) if c not in vendidas)
        v["diferida"] = bool(v["resultado"] < 0 and ventana and quedan.get(v["activo"], 0) > 1e-9)
    g = sum(v["resultado"] for v in ventas if not v["diferida"])
    previas = d["perfil"].get("perdidas_previas") or 0
    ahora = liquida(g, divid + intereses, previas)
    # si vendieras hoy: cada posición sola y todas juntas, sobre lo que ya llevas este año
    # (una pérdida aplazada se recupera al vender los títulos que la aplazaron: va con su posición)
    aplazada = {}
    for v in ventas:
        if v["diferida"]:
            aplazada[v["activo"]] = aplazada.get(v["activo"], 0) + v["resultado"]
    filas, total_lat, total_val = [], 0.0, 0.0
    for p in pos:
        if not p["cantidad"] or p["valor"] is None:
            continue
        lat = p["latente"] + aplazada.get(p["id"], 0)
        extra = round(liquida(g + lat, divid + intereses, previas)["cuota"] - ahora["cuota"], 2)
        recientes = [f for *_, f in lotes.get(p["id"], []) if (hoy - date.fromisoformat(f)).days <= DOS_MESES]
        filas.append({"id": p["id"], "nombre": p["nombre"], "valor": p["valor"], "latente": p["latente"], "impuesto": extra,
                      "neto": round(p["valor"] - extra, 2), "reciente": bool(recientes),
                      "antiguedad": min((f for *_, f in lotes.get(p["id"], [])), default=None)})
        total_lat += lat
        total_val += p["valor"]
    todo = liquida(g + total_lat, divid + intereses, previas)
    imp_todo = round(todo["cuota"] - ahora["cuota"], 2)
    consejos = []
    regimen = d["perfil"].get("regimen", "comun")
    if g > 0:
        for f in sorted((f for f in filas if f["latente"] < 0), key=lambda f: f["latente"]):
            ahorro = -f["impuesto"]
            if ahorro >= 1:
                consejos.append(f"Vender {f['nombre']} (va {_e(f['latente'])}) compensaría ganancias de este año: "
                                f"pagarías unos {_e(ahorro)} menos. Si quieres seguir teniéndolo, no lo recompres en 2 meses "
                                f"o Hacienda no te deja usar esa pérdida.")
    if ahora["base"] and ahora["base"] < 6000 < ahora["base"] + max(total_lat, 0):
        consejos.append(f"Llevas {_e(ahora['base'], 0)} de base del ahorro este año. Lo que pase de 6.000 € paga el 21 % en vez del 19 %: "
                        "si vas a vender mucho, repartir las ventas entre diciembre y enero ahorra 2 puntos en lo que sobra.")
    if divid > 0:
        consejos.append(f"Este año has cobrado {_e(divid)} en dividendos y tributan ya, los reinviertas o no. "
                        "Un ETF de acumulación hace lo mismo sin pasar por Hacienda hasta que vendes.")
    if ahora["pendientes"]:
        consejos.append(f"Te quedan {_e(ahora['pendientes'])} de pérdidas por compensar. Caducan a los 4 años: "
                        "si vas a vender algo con ganancias, mejor antes de que caduquen.")
    if any(v["diferida"] for v in ventas):
        consejos.append("Alguna venta con pérdida tiene una compra del mismo valor a menos de 2 meses: esa pérdida no cuenta este año, "
                        "se aplaza hasta que vendas esos títulos.")
    return {
        "anio": anio, "regimen": regimen, "tramos": TRAMOS_AHORRO,
        "ventas": ventas, "ganancias": round(g, 2), "dividendos": round(divid, 2), "intereses": round(intereses, 2), "previas": previas,
        "renta": {**ahora, "tipo_medio": round(ahora["cuota"] / ahora["base"] * 100, 2) if ahora["base"] else 0,
                  "marginal": tipo_marginal(ahora["base"])},
        "si_vendes": {"posiciones": filas, "valor": round(total_val, 2), "latente": round(total_lat, 2), "impuesto": imp_todo,
                      "neto": round(total_val - imp_todo, 2), "ganancia_neta": round(total_lat - imp_todo, 2),
                      "tipo": round(imp_todo / total_lat * 100, 2) if total_lat > 0 else 0, "pendientes": todo["pendientes"]},
        "consejos": consejos,
    }


def declaracion(d, f_actual, valor, hoy=None):
    """La declaración en la que hay que estar: de enero a junio la del año pasado (la que se presenta ahora),
    de julio a diciembre la de este año (la que se va formando). Qué meter, dónde y con qué cifras."""
    hoy = hoy or date.today()
    ej = hoy.year - 1 if hoy.month <= 6 else hoy.year
    f = f_actual if ej == f_actual["anio"] else fiscal(d, [], date(ej, 12, 31))
    plazo = f"del 1 de abril al 30 de junio de {ej + 1} (las fechas exactas las fija Hacienda cada año)"
    if hoy.year > ej and hoy.month >= 4:
        estado = f"Toca presentarla ya: el plazo acaba el 30 de junio."
    elif hoy.year > ej:
        estado = f"Se presenta {plazo}. Ya puedes ir juntando los papeles."
    else:
        estado = f"Se va formando con lo que hagas hasta el 31 de diciembre. Se presenta {plazo}."
    g, rc = f["ganancias"], f["dividendos"] + f["intereses"]
    if f["ventas"] and g > 0:
        obligado = ("Sí, casi seguro. Vender con ganancias en Trade Republic no lleva retención en España, y eso obliga a declarar "
                    "salvo que todo lo que ganaste en el año junto (sueldo incluido) no llegue a 1.000 €.")
    elif f["ventas"]:
        obligado = ("Por las inversiones no estás obligado (vendiste con pérdidas), pero te conviene presentarla: "
                    "así la pérdida queda apuntada y compensa ganancias de los 4 años siguientes.")
    elif rc:
        obligado = ("Por dividendos e intereses solos, normalmente no (hasta 1.600 € al año con retención). "
                    "Si no te retuvieron nada en España, o tu sueldo pasa de 22.000 € de un solo pagador, sí.")
    else:
        obligado = "Por inversiones no: no vendiste ni cobraste nada. Depende de tu sueldo (más de 22.000 € de un pagador obliga)."
    lineas = []
    if f["ventas"]:
        lineas.append({"que": f"Ventas ({len(f['ventas'])})", "importe": g,
                       "donde": "Ganancias y pérdidas patrimoniales → transmisión de acciones y ETFs admitidos a negociación. "
                                "Una entrada por venta, con las cifras de la tabla de ventas."})
    if f["dividendos"]:
        lineas.append({"que": "Dividendos", "importe": f["dividendos"],
                       "donde": "Capital mobiliario → dividendos. Mete el bruto y la retención del otro país (vienen en el informe "
                                "de Trade Republic); la deducción por doble imposición te devuelve hasta el 15 %."})
    if f["intereses"]:
        lineas.append({"que": "Intereses de la cuenta", "importe": f["intereses"],
                       "donde": "Capital mobiliario → intereses de cuentas y depósitos."})
    pasos = [
        "Descarga el informe fiscal anual de Trade Republic (en la app, Perfil → Documentos; suele salir entre febrero y marzo).",
        f"Apunta en Perfil los intereses de la cuenta de {ej} que diga ese informe, para que esta cuenta salga entera.",
        "Abre el borrador en Renta WEB y mira si las ventas de Trade Republic ya vienen. Si no, añádelas a mano con la tabla de ventas.",
        "Compara lo que vaya a pagar o devolver el borrador con la cuota estimada de aquí. Si se parecen, vas bien.",
    ]
    if f["previas"] or f["renta"]["pendientes"]:
        pasos.append("Comprueba que el borrador recoge tus pérdidas de años anteriores; si no, añádelas en «saldos pendientes».")
    avisos = []
    if valor > 40000:
        avisos.append("Pasas de 40.000 € en Trade Republic. Si a 31 de diciembre tus valores fuera de España pasan de 50.000 €, "
                      "toca el modelo 720 (informativo) antes del 31 de marzo. Mira si la custodia de tu cuenta está en Alemania.")
    return {"ejercicio": ej, "estado": estado, "obligado": obligado, "lineas": lineas, "pasos": pasos, "avisos": avisos,
            "cuota": f["renta"]["cuota"], "base": f["renta"]["base"], "ventas": f["ventas"] if ej != f_actual["anio"] else None,
            "intereses": f["intereses"]}


def aviso_renta(hoy=None):
    """Telegram en las fechas clave (inversiones-renta.timer): 1/12 cierre del año, 2/4 empieza la renta, 15/6 quedan 2 semanas."""
    hoy = hoy or date.today()
    inf = informe(hoy)
    f, dc = inf["fiscal"], inf["declaracion"]
    if hoy.month == 12:
        s = f["si_vendes"]
        msg = (f"<b>Cierre de {f['anio']}: impuestos de las inversiones</b>\n"
               f"Lo vendido este año: {_e(f['ganancias'])} de resultado · cuota estimada {_e(f['renta']['cuota'])}.\n"
               f"Si vendieras todo hoy pagarías {_e(s['impuesto'])} más.\n\n"
               + ("\n".join(f"• {c}" for c in f["consejos"]) or "Nada que optimizar antes del 31: no has vendido con ganancias.")
               + "\n\nLo que vendas a partir del 1 de enero cuenta para el año que viene.")
    else:
        msg = (f"<b>Renta {dc['ejercicio']}</b>\n{dc['estado']}\n\n{dc['obligado']}\n\n"
               + "".join(f"• {l['que']}: {_e(l['importe'])}\n" for l in dc["lineas"])
               + f"Cuota estimada por inversiones: {_e(dc['cuota'])}\n\n"
               + "\n".join(f"{i}. {p}" for i, p in enumerate(dc["pasos"], 1)))
    msg += "\n\nTodo, con la tabla de ventas: https://todo.yagotg.dev/inversiones.html#impuestos"
    import aviso   # la app primero; el texto largo, por Telegram solo si el push no llega
    titulo = f"Cierre de {f['anio']}: impuestos" if hoy.month == 12 else f"Renta {dc['ejercicio']}"
    cuerpo = (f"Cuota estimada {_e(f['renta']['cuota'])}. Mira qué puedes optimizar antes del 31." if hoy.month == 12
              else f"{dc['estado']} Cuota estimada por inversiones: {_e(dc['cuota'])}.")
    aviso.avisa(titulo, cuerpo, "renta", "/inversiones.html#impuestos", largo=msg)


# ---------- reviews ----------
def reviews():
    return sorted((f.stem for f in REVIEWS.glob("*.md")), reverse=True) if REVIEWS.exists() else []


def review(fecha):
    f = REVIEWS / f"{fecha}.md"
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", fecha) or not f.exists():
        return None
    return f.read_text("utf-8")


def _md_cartera(inf):
    filas = ["| Activo | Ticker / ISIN | Tipo | Participaciones | Invertido (coste FIFO) | Valor | Rentab. | Peso | TER | Primera compra | Papel que le doy |",
             "|---|---|---|---|---|---|---|---|---|---|---|"]
    for x in inf["posiciones"]:
        if not x["cantidad"]:
            continue
        primera = next((o["fecha"] for o in inf["operaciones"] if o["activo"] == x["id"] and o["tipo"] == "compra"), "")
        filas.append(f"| {x['nombre']} | {x['simbolo']} / {x['isin'] or '?'} | {x['tipo']} | {x['cantidad']:g} | {x['coste']:.2f} € | "
                     f"{(x['valor'] or 0):.2f} € | {x['rent'] if x['rent'] is not None else '?'} % | {x['peso']} % | "
                     f"{x['ter'] if x['ter'] is not None else '?'} | {primera} | {x['papel'] or '?'} |")
    return "\n".join(filas)


def prompt_review(inf, hoy):
    p, t = inf["perfil"], inf["total"]
    sn = lambda v: "sí" if v is True else "no" if v is False else "?"
    previas = []
    for f in inf["reviews"][:4]:
        texto = review(f) or ""
        # las dos últimas enteras; las de antes, solo el resumen y el plan de acción
        if len(previas) >= 2:
            trozos = re.findall(r"(?ms)^#{2,3} *(?:1\.|9\.).*?(?=^#{2,3} *\d+\.|\Z)", texto)
            texto = "\n".join(trozos) or texto[:3000]
        previas.append(f"#### Review del {f}\n\n{texto}")
    lecciones_previas = "; ".join(l.splitlines()[0].strip("* ") for f in inf["reviews"][:12] if (l := leccion_de(review(f)))) or "(ninguna todavía)"
    proy = inf["proyeccion"]
    proy_txt = "\n".join(f"- {k} ({v['tasa']} % anual nominal): 5 años {v['anios'][5]:,} €, 10 años {v['anios'][10]:,} €, 20 años {v['anios'][20]:,} €"
                         for k, v in proy.items() if "tasa" in v)
    fz = inf["fiscal"]
    stress_txt = "\n".join(f"- {k}: {v:,.2f} €" for k, v in inf["stress"].items())
    serie = inf["serie"]
    ref = serie[-1] if serie else {}
    ops = "\n".join(f"- {o['fecha']} {o['tipo']} {o['activo']} {o['cantidad']:g} × {o['precio']:.4f} € (comisión {o['comision']:.2f} €)"
                    for o in inf["operaciones"][-40:]) or "(ninguna)"
    return f"""Actúa como analista de inversiones independiente y riguroso. Quiero un análisis profundo, honesto y visual de mi portfolio. No me des la razón por defecto: si algo está mal planteado, dilo claramente y explica por qué.

Hoy es {hoy.isoformat()} (domingo). Esta es la review semanal automática de mi app.

## Mi contexto
- Edad: {p['edad'] or '?'}
- Horizonte de inversión: {p['horizonte'] or '?'}
- Objetivo: {p['objetivo'] or '?'}
- Aportación mensual: {p['aportacion']:g} €/mes — ¿estable? {sn(p['estable'])}
- Fondo de emergencia aparte: {p['emergencia'] or '?'}
- Tolerancia al riesgo: {p['tolerancia'] or '?'} — ¿cuánto aguantaría ver caer el portfolio sin vender? {p['caida'] or '?'}
- País de residencia fiscal: España (ten en cuenta la fiscalidad española: traspasos entre fondos sin tributar, que los ETFs no tienen ese beneficio, retenciones en dividendos extranjeros, etc.)
- Broker(s): {p['broker']}
- Notas mías: {p['notas'] or '(ninguna)'}
(Un «?» es un dato que aún no he rellenado: trabaja con un supuesto explícito y pregúntamelo en la sección 10.)

## Datos
### Posiciones actuales (calculadas por la app con FIFO, precios de Yahoo Finance pasados a euros)
{_md_cartera(inf)}

Totales: valor {t['valor']:.2f} €, coste {t['coste']:.2f} €, plusvalía latente {t['latente']:.2f} € ({t['rent'] if t['rent'] is not None else '?'} %), realizado {t['realizado']:.2f} €, dividendos {t['dividendos']:.2f} €, comisiones pagadas {t['comisiones']:.2f} €, TER medio ponderado {t['ter_medio']} % (solo de los que tienen TER apuntado).

Impuestos (IRPF, base del ahorro, calculado con FIFO en la página; régimen {fz['regimen']}): este año ({fz['anio']}) llevo {fz['ganancias']:.2f} € de ganancias netas por ventas y {fz['dividendos']:.2f} € de dividendos → base {fz['renta']['base']:.2f} €, cuota estimada {fz['renta']['cuota']:.2f} €. Pérdidas de años anteriores por compensar: {fz['previas']:.2f} €. Si vendiera todo hoy pagaría {fz['si_vendes']['impuesto']:.2f} € más y me quedarían {fz['si_vendes']['neto']:.2f} €. Usa estas cifras; si propones vender algo, di cuánto impuesto supone y si conviene esperar a enero, compensar con pérdidas o respetar la regla de los 2 meses.
Comparación: si cada euro que he metido hubiera ido al mismo tiempo a {inf['referencia']['simbolo']} ({inf['referencia']['nombre'] or '?'}), hoy tendría {ref.get('referencia') or '?'} € frente a {ref.get('valor') or '?'} €.

### Últimas operaciones
{ops}

### Cálculos ya hechos con código (úsalos, no los rehagas a ojo; si cambias un supuesto, dilo)
Proyección con la cartera actual y {p['aportacion']:g} €/mes, interés compuesto mensual:
{proy_txt}
Stress test con caídas de pico a valle supuestas por tipo de activo ({json.dumps(CRISIS, ensure_ascii=False)}):
{stress_txt}
Para la cartera propuesta, calcula el stress con las mismas caídas por tipo y di el resultado en €.

### Reviews de semanas anteriores
{chr(10).join(previas) or '(Es la primera review: no hay anteriores.)'}

## Cómo quiero el análisis

Antes de empezar, busca en la web los datos actuales que necesites (precios, TER, composición de los ETFs/fondos, noticias relevantes de las empresas o sectores). No inventes cifras: si no encuentras un dato, dilo y trabaja con un supuesto explícito.

Estructúralo así (encabezados `## 1. …` a `## 11. …`, exactamente con esos números):

## 1. Resumen ejecutivo (máx. 5 líneas)
La foto general en lenguaje claro: cómo está el portfolio, el mayor problema y la acción más importante que debería hacer.

## 2. Radiografía del portfolio
- Tabla con cada posición: invertido, peso (%), rentabilidad, TER/comisiones, y qué papel cumple en la cartera.
- Gráficos de la distribución por: tipo de activo, geografía, sector, divisa y tamaño de empresa. **Mira dentro de los ETFs/fondos** (look-through), no solo la etiqueta.
- Solapamientos: qué posiciones están comprando en realidad lo mismo y la exposición real resultante a las 10 empresas más grandes.

## 3. Qué sobra
Posiciones redundantes, demasiado pequeñas para importar, demasiado caras en comisiones o que no encajan con mi objetivo. Para cada una: por qué y qué haría con ella.

## 4. Qué falta
Exposiciones o piezas ausentes según mi perfil y horizonte. Distingue entre "falta de verdad" y "opcional".

## 5. Qué cambiaría
Una propuesta concreta de cartera objetivo con pesos (%), y una tabla comparando "actual vs. propuesta". Explica cómo llegar ahí de forma eficiente: con aportaciones nuevas en lugar de vender cuando sea posible, priorizando traspasos sin coste fiscal y minimizando comisiones e impuestos.

## 6. Riesgos que estoy asumiendo (y por qué)
Para cada riesgo: qué es, cuánto me afecta en mi caso concreto, si lo estoy asumiendo conscientemente o por accidente, y cómo mitigarlo. Como mínimo: concentración, divisa (USD/EUR), valoración, liquidez, comportamiento (vender en pánico), producto (sintéticos, apalancados, cripto, domicilio) y fiscal.

## 7. Previsión a futuro
- Proyección a 5, 10 y 20 años en tres escenarios con las rentabilidades supuestas explícitas (tienes los cálculos arriba; la app dibuja sola el gráfico de líneas de la proyección, no lo repitas).
- Stress test: cuánto perdería en € con mi cartera actual en un escenario tipo 2008, 2020 y 2022, y cuánto con la propuesta.
- Deja claro que son escenarios ilustrativos, no predicciones.

## 8. Evolución respecto a reviews anteriores
Qué ha cambiado, qué recomendaciones anteriores he seguido o ignorado (compáralo con las operaciones), si estoy derivando de mi estrategia y si alguna conclusión anterior ya no se sostiene.

## 9. Plan de acción
Lista priorizada de 3 a 7 acciones concretas, cada una con: qué hacer, por qué, urgencia (ya / este mes / cuando toque) e impacto esperado.

## 10. Preguntas para mí
Si te falta información que cambiaría las conclusiones, las preguntas clave (máx. 5).

## 11. Lección de la semana
Estoy empezando y quiero aprender. Una sola idea de inversión explicada para alguien que empieza (máx. 150 palabras),
elegida a partir de algo que haya pasado esta semana en MI cartera o en el mercado (p. ej. por qué ha caído X, qué es el
TER, la regla de los 2 meses, el interés compuesto, la diversificación, el riesgo de divisa). Primero una línea en
negrita con la idea; después la explicación con un ejemplo en € con mis números; al final «Para pensar:» y una pregunta.
No repitas el tema de las lecciones anteriores: {lecciones_previas}.

## Formato de salida (importante: lo lee una página web, no un chat)
- Responde SOLO con el informe en Markdown: sin saludo, sin «aquí tienes», sin comentar tu proceso de búsqueda.
- Tablas en Markdown normal. Nada de HTML.
- Para cada gráfico, un bloque de código con lenguaje `grafica` y dentro un JSON en UNA línea, así:
```grafica
{{"tipo": "tarta", "titulo": "Geografía (look-through)", "etiquetas": ["EE. UU.", "Europa", "Emergentes"], "series": [{{"nombre": "%", "datos": [62, 16, 10]}}]}}
```
  `tipo` es `tarta`, `barras` o `lineas`; en `barras` puedes poner varias series (p. ej. actual y propuesta). Los datos, números sin unidades.
- Separa con etiquetas en negrita **Hecho:**, **Supuesto:** y **Opinión:** cuando mezcles las tres cosas.
- Sé directo y específico, con números en €. Un aviso legal breve al final, una sola vez.
"""


def grafica_proyeccion(inf):
    pr = inf["proyeccion"]
    hoy = date.today().year
    return ("```grafica\n" + json.dumps({
        "tipo": "lineas", "titulo": f"Proyección con {inf['perfil']['aportacion']:g} €/mes (ilustrativa)",
        "etiquetas": [str(hoy + n) for n in range(len(pr["aportado"]["anios"]))],
        "series": [{"nombre": f"{k} ({v['tasa']} %)", "datos": v["anios"]} for k, v in pr.items() if "tasa" in v]
                  + [{"nombre": "Lo aportado", "datos": pr["aportado"]["anios"]}]}, ensure_ascii=False) + "\n```")


def leccion_de(texto):
    m = re.search(r"(?ms)^## 11\.[^\n]*\n(.*?)(?=^## |\Z)", texto or "")
    return m.group(1).strip() if m else ""


def leccion():
    """La lección de la última review que la tenga: {fecha, texto}, o None."""
    for f in reviews():
        if (x := leccion_de(review(f))):
            return {"fecha": f, "texto": x}
    return None


def guarda_review(fecha, texto):
    REVIEWS.mkdir(exist_ok=True)
    (REVIEWS / f"{fecha}.md").write_text(texto, "utf-8")
    try:   # la copia del vault es para leerla en Obsidian; si falla, la de la app vale
        VAULT_REVIEWS.mkdir(parents=True, exist_ok=True)
        f = VAULT_REVIEWS / f"Review inversiones {fecha}.md"
        tmp = f.with_name(f".{f.name}.tmp")
        tmp.write_text(f"---\nfecha: {fecha}\ntipo: review-inversiones\n---\n\n{texto}", "utf-8")
        tmp.replace(f)
    except OSError as e:
        print("vault:", e, file=sys.stderr)


def hacer_review(ver=False):
    hoy = date.today()
    fallos = actualiza()
    if fallos:
        print("precios:", fallos, file=sys.stderr)
    inf = informe()
    if not any(x["cantidad"] for x in inf["posiciones"]):
        print("Sin posiciones: no hay nada que revisar.")
        return
    claude = os.environ.get("CLAUDE_BIN", str(Path.home() / ".local/bin/claude"))
    r = subprocess.run([claude, "-p", "--model", os.environ.get("REVIEW_MODEL", "opus"),
                        "--tools", "WebSearch,WebFetch", "--allowedTools", "WebSearch,WebFetch",
                        "--strict-mcp-config", "--no-session-persistence"],
                       input=prompt_review(inf, hoy), capture_output=True, text=True, timeout=45 * 60)
    if r.returncode or not r.stdout.strip():
        raise SystemExit(f"claude falló ({r.returncode}): {r.stderr[-1000:]}")
    texto = r.stdout.strip()
    texto = texto[texto.find("## 1."):] if "## 1." in texto else texto   # fuera cualquier preámbulo
    # el gráfico de la proyección lo pone la app (con sus números), justo debajo del encabezado 7
    texto = re.sub(r"(?m)^(## 7\..*)$", lambda m: m.group(1) + "\n\n" + grafica_proyeccion(inf), texto, count=1)
    if ver:
        print(texto)
        return
    guarda_review(hoy.isoformat(), texto)
    avisa(hoy, texto, inf)


def avisa(hoy, texto, inf):
    import html
    import aviso
    t = inf["total"]
    lec = leccion_de(texto)
    titulo = re.sub(r"\*\*(.+?)\*\*", r"\1", lec.splitlines()[0]) if lec else ""
    if aviso.push(f"Review de inversiones · {_e(t['valor'], 0)}", ("Lección: " + titulo[:120]) if titulo else "Ya tienes la review del domingo",
                  "review", f"/inversiones.html?review={hoy.isoformat()}#review"):
        return
    resumen = re.search(r"(?ms)^## 1\..*?\n(.*?)(?=^## 2\.|\Z)", texto)
    cuerpo = re.sub(r"\*\*(.+?)\*\*", r"\1", (resumen.group(1) if resumen else texto[:800]).strip())
    t = inf["total"]
    msg = (f"<b>Review de inversiones · {hoy.day}/{hoy.month}</b>\n"
           f"Cartera: {t['valor']:,.2f} € ({t['latente']:+,.2f} €)\n\n{html.escape(cuerpo[:3000])}\n\n"
           f"Entera, con gráficas: https://todo.yagotg.dev/inversiones.html?review={hoy.isoformat()}")
    _telegram(msg)


def _telegram(msg):
    if not os.environ.get("TELEGRAM_TOKEN"):
        print(msg)
        return
    req = urllib.request.Request(
        f"https://api.telegram.org/bot{os.environ['TELEGRAM_TOKEN']}/sendMessage",
        json.dumps({"chat_id": int(os.environ["TELEGRAM_USER_ID"]), "text": msg[:4096], "parse_mode": "HTML",
                    "link_preview_options": {"is_disabled": True}}).encode(), {"Content-Type": "application/json"})
    urllib.request.urlopen(req, timeout=30).close()


if __name__ == "__main__":
    if "--precios" in sys.argv:
        f = actualiza()
        print("\n".join(f) or "ok")
        try:
            planes, alertas = revisa(ver="--ver" in sys.argv)
            print(f"planes: {len(planes)}, alertas: {len(alertas)}")
        except Exception as e:   # que un fallo aquí no deje sin precios
            print("planes/alertas:", e, file=sys.stderr)
        sys.exit(1 if f and len(f) == len(lee()["activos"]) + 1 else 0)
    elif "--review" in sys.argv:
        hacer_review(ver="--ver" in sys.argv)
    elif "--aviso-renta" in sys.argv:
        aviso_renta()
    elif "--prompt" in sys.argv:
        print(prompt_review(informe(), date.today()))
    else:
        print(__doc__)
