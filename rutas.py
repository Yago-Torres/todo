"""Rutas de las carreras del COROS: reconocer que repites recorrido, correr contra tu fantasma y sacar el GPX.

Trabaja sobre las trazas de actividades/<id>.json ({"dia", "campos", "puntos": [[t, lat, lon, m, alt, fc, vel, cad]]},
un punto cada 5 s). Sin dependencias: distancias planas (en 10 km la Tierra es plana de sobra).

- `misma_ruta(a, b)`: el mismo recorrido y en el mismo sentido (la salida cerca, la distancia parecida y cada tramo
  pasando por donde pasó el otro a la misma altura de la carrera).
- `fantasma(nueva, vieja)`: cuánto ibas por delante o por detrás en cada km (negativo = más rápido hoy).
- `busca(id, traza, otras)`: la última vez que hiciste esa ruta y tu mejor vez en ella.
- `gpx(traza, nombre)`: para importarla como ruta en la app del COROS y llevarla en el reloj.
"""
from math import cos, radians
from xml.sax.saxutils import escape

T, LAT, LON, M = 0, 1, 2, 3
CERCA = 60          # m: dos pasos por el mismo sitio (el GPS baila 10-20 m; las calles de al lado están a más)
ACIERTO = 0.85      # parte de la ruta que tiene que coincidir


def _xy(lat0):
    k = cos(radians(lat0))
    return lambda p: (p[LON] * 111320 * k, p[LAT] * 110540)


def _km(traza):
    ms = [p[M] for p in traza["puntos"] if p[M] is not None]
    return ms[-1] if ms else 0


def _geo(traza):
    return [p for p in traza["puntos"] if p[LAT] is not None and p[M] is not None]


def muestras(traza, cada=200):
    """Un punto cada `cada` metros de carrera: con eso basta para comparar recorridos."""
    out, sig = [], 0
    for p in _geo(traza):
        if p[M] >= sig:
            out.append(p)
            sig = p[M] + cada
    return out


def misma_ruta(a, b):
    ka, kb = _km(a), _km(b)
    if not ka or not kb or abs(ka - kb) > max(300, 0.12 * max(ka, kb)):
        return False
    ga, gb = muestras(a), _geo(b)
    if len(ga) < 5 or len(gb) < 5:
        return False
    xy = _xy(ga[0][LAT])
    (ax, ay), (bx, by) = xy(ga[0]), xy(gb[0])
    if (ax - bx) ** 2 + (ay - by) ** 2 > 300 ** 2:    # salidas lejos: ni la miro entera
        return False
    pb = [(xy(p), p[M]) for p in gb]
    bien = 0
    for p in ga:
        x, y = xy(p)
        # cerca en el mapa y a una altura de la carrera parecida: así un recorrido al revés o una vuelta distinta
        # que pisa las mismas calles no cuentan como la misma ruta
        margen = 400 + 0.1 * p[M]
        if any((x - bx) ** 2 + (y - by) ** 2 <= CERCA ** 2 and abs(m - p[M]) <= margen for (bx, by), m in pb):
            bien += 1
    return bien >= ACIERTO * len(ga)


def tiempos(traza):
    """[(m, segundos en movimiento)]: un hueco de más de 15 s en los puntos es una pausa del reloj y no cuenta."""
    out, mov, ant = [], 0.0, None
    for p in traza["puntos"]:
        if p[M] is None:
            continue
        if ant is not None:
            dt = p[T] - ant
            mov += dt if 0 < dt <= 15 else 5 if dt > 15 else 0
        ant = p[T]
        if not out or p[M] >= out[-1][0]:
            out.append((p[M], mov))
    return out


def _en(ts, d):
    """Segundos en movimiento al pasar por el metro d (interpolado)."""
    lo, hi = 0, len(ts) - 1
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if ts[mid][0] < d:
            lo = mid
        else:
            hi = mid
    (m0, t0), (m1, t1) = ts[lo], ts[hi]
    return t0 if m1 == m0 else t0 + (t1 - t0) * (d - m0) / (m1 - m0)


def fantasma(nueva, vieja):
    """Diferencia acumulada con la vieja: en cada km, al final y cada 100 m (para la gráfica). < 0 = vas por delante."""
    tn, tv = tiempos(nueva), tiempos(vieja)
    if len(tn) < 5 or len(tv) < 5:
        return None
    fin = min(tn[-1][0], tv[-1][0])
    dif = lambda d: round(_en(tn, d) - _en(tv, d))
    return {"km": [{"km": k, "dif": dif(k * 1000)} for k in range(1, int(fin // 1000) + 1)],
            "final": dif(fin), "m": round(fin), "seg": round(_en(tv, fin)),
            "serie": [[d, dif(d)] for d in range(100, int(fin) + 1, 100)]}


def busca(id_nuevo, traza, otras):
    """otras: [(id, traza)]. Solo las anteriores (los id fit-AAAAMMDDHHMM ordenan por fecha).
    Devuelve {"ultima": {...}, "mejor": {...} si es otra vez distinta, "veces": n} o None si la ruta es nueva."""
    iguales = sorted(((i, t) for i, t in otras if i < id_nuevo and misma_ruta(traza, t)), key=lambda x: x[0])
    if not iguales:
        return None
    out = {"veces": len(iguales)}
    ult_id, ult = iguales[-1]
    f = fantasma(traza, ult)
    if not f:
        return None
    out["ultima"] = {"id": ult_id, "dia": ult.get("dia"), **f}
    # la mejor: la que menos tardó en la distancia común con hoy
    fin = f["m"]
    mejor_id, mejor = min(iguales, key=lambda x: _en(tiempos(x[1]), min(fin, _km(x[1]))))
    if mejor_id != ult_id:
        g = fantasma(traza, mejor)
        if g:
            out["mejor"] = {"id": mejor_id, "dia": mejor.get("dia"), **g}
    return out


def frase(f):
    """«12 s más rápido que el 20/11» para el bot y la notificación."""
    if not f or "ultima" not in f:
        return ""
    u = f["ultima"]
    d = u["dia"] or ""
    cuando = f"el {int(d[8:])}/{int(d[5:7])}" if len(d) == 10 else "la última vez"
    s = abs(u["final"])
    cuanto = f"{s // 60}:{s % 60:02d}" if s >= 60 else f"{s} s"
    txt = (f"misma ruta que {cuando}, igual de rápido" if s < 3 else
           f"{cuanto} {'más rápido' if u['final'] < 0 else 'más lento'} que {cuando} en la misma ruta")
    if "mejor" in f:
        m = f["mejor"]["final"]
        txt += f" ({abs(m)} s {'mejor' if m < 0 else 'peor'} que tu mejor vez)" if m else " (igual que tu mejor vez)"
    return txt


def gpx(traza, nombre="Ruta"):
    """GPX de ruta (un <trk>): la app del COROS lo importa en Rutas y lo manda al reloj para seguirla."""
    pts = "".join(f'<trkpt lat="{p[LAT]:.6f}" lon="{p[LON]:.6f}">' + (f"<ele>{p[4]:.1f}</ele>" if p[4] is not None else "")
                  + "</trkpt>" for p in _geo(traza))
    n = escape(nombre)
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<gpx version="1.1" creator="todo.yagotg.dev" xmlns="http://www.topografix.com/GPX/1/1">'
            f"<metadata><name>{n}</name></metadata><trk><name>{n}</name><trkseg>{pts}</trkseg></trk></gpx>\n")


# ---------- la biblioteca: cada recorrido distinto que has corrido, con nombre ----------
def forma(traza):
    """«Circular», «Ida y vuelta» o «Solo ida», mirando dónde acaba y si la vuelta pisa la ida."""
    g = muestras(traza, 100)
    if len(g) < 6:
        return "Ruta"
    xy = _xy(g[0][LAT])
    d2 = lambda a, b: (xy(a)[0] - xy(b)[0]) ** 2 + (xy(a)[1] - xy(b)[1]) ** 2
    mitad = len(g) // 2
    ida, vuelta = g[:mitad], g[mitad:]
    pisa = sum(1 for p in vuelta if any(d2(p, q) <= CERCA ** 2 for q in ida))
    # volver por donde fuiste es ida y vuelta aunque acabes unos cientos de metros más allá (o más acá)
    if pisa >= 0.6 * len(vuelta) and d2(g[0], g[-1]) <= 1000 ** 2:
        return "Ida y vuelta"
    return "Circular" if d2(g[0], g[-1]) <= 300 ** 2 else "Solo ida"


def nombre_auto(traza):
    return f"{forma(traza)} de {_km(traza) / 1000:.1f} km".replace(".", ",")


def clasifica(biblio, fid, traza, carga):
    """Mete el fit en su ruta de la biblioteca (o crea una). biblio: [{id, nombre, km, ref, fits}]; carga(fid) → traza.
    Devuelve (ruta, nueva). La referencia es la primera vez: así una ruta no «se desplaza» con el tiempo."""
    for r in biblio:
        if fid in r["fits"]:
            return r, False
    for r in biblio:
        ref = carga(r["ref"])
        if ref and misma_ruta(traza, ref):
            r["fits"] = sorted(set(r["fits"]) | {fid})
            return r, False
    usados = {r["id"] for r in biblio}
    n = len(biblio) + 1
    while f"r{n}" in usados:
        n += 1
    r = {"id": f"r{n}", "nombre": nombre_auto(traza), "km": round(_km(traza) / 1000, 2), "ref": fid, "fits": [fid]}
    biblio.append(r)
    return r, True


def sugeridas(biblio, km, n=2):
    """Las n rutas que más se acercan a km (sin pasarse de un 25 % ni quedarse a menos del 75 %)."""
    ok = [r for r in biblio if 0.75 * km <= r["km"] <= 1.25 * km]
    return sorted(ok, key=lambda r: (abs(r["km"] - km), -len(r["fits"])))[:n]


# ---------- segmentos: un tramo con nombre y tu tiempo cada vez que pasas ----------
PUERTA = 40   # m: pasar por la salida o la llegada del segmento


def segmento(traza, desde, hasta, nombre):
    """Un segmento sacado de una traza entre los metros `desde` y `hasta`."""
    pts = [p for p in _geo(traza) if desde <= p[M] <= hasta]
    if len(pts) < 3:
        raise ValueError("Ese tramo es demasiado corto")
    m = pts[-1][M] - pts[0][M]
    if m < 100:
        raise ValueError("Un segmento tiene que tener al menos 100 m")
    return {"nombre": nombre.strip()[:60] or f"Segmento de {round(m)} m", "m": round(m),
            "puntos": [[round(p[LAT], 6), round(p[LON], 6)] for p in pts], "intentos": []}


def pasos(seg, traza):
    """Cada vez que la traza recorre el segmento, de salida a llegada: [{"seg", "m"}] (m = dónde empezó en la carrera)."""
    sp = seg["puntos"]
    xy = _xy(sp[0][0])
    sx = [xy((None, a, b)) for a, b in sp]
    S, E, L = sx[0], sx[-1], seg["m"]
    # 1 de cada ~50 m del segmento: para ver que la traza sigue el tramo, no que solo pasa por los dos extremos
    paso = max(1, len(sx) // max(2, L // 50))
    control = sx[::paso] + [E]
    P = [(*xy(p), p[M]) for p in _geo(traza)]
    if len(P) < 3:
        return []
    d2 = lambda a, b: (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2
    ts = tiempos(traza)
    out, i = [], 0
    while i < len(P):
        if d2(P[i], S) > PUERTA ** 2:
            i += 1
            continue
        # la salida: el punto más cerca mientras sigo dentro de la puerta
        while i + 1 < len(P) and d2(P[i + 1], S) < d2(P[i], S):
            i += 1
        mejor = None
        for j in range(i + 1, len(P)):
            hecho = P[j][2] - P[i][2]
            if hecho > 1.3 * L + 60:
                break
            if hecho >= 0.8 * L - 60 and d2(P[j], E) <= PUERTA ** 2 and (mejor is None or d2(P[j], E) < d2(P[mejor], E)):
                mejor = j
        if mejor is not None:
            tramo = P[i:mejor + 1]
            sigue = sum(1 for c in control if any(d2(c, q) <= PUERTA ** 2 for q in tramo))
            if sigue >= 0.8 * len(control):
                out.append({"seg": round(_en(ts, P[mejor][2]) - _en(ts, P[i][2])), "m": round(P[i][2])})
                i = mejor + 1
                continue
        i += 1
    return out


def puesto(seg, fid):
    """Cómo quedó el mejor paso de este fit entre todos los intentos: 1 = tu mejor marca."""
    mios = [x for x in seg["intentos"] if x["fit"] == fid]
    if not mios:
        return None
    mejor = min(x["seg"] for x in mios)
    return 1 + len({x["fit"] for x in seg["intentos"] if x["seg"] < mejor and x["fit"] != fid})
