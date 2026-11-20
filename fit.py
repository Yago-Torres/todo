"""Lector de ficheros .fit (lo que exporta la app del COROS), sin dependencias.

El formato es binario y público (Garmin FIT SDK). Solo nos interesan tres mensajes:
  18 session  → el resumen (deporte, distancia, tiempo, FC, desnivel, calorías...)
  19 lap      → las vueltas que marca el reloj (en el COROS, una por km si no tocas nada)
  20 record   → un punto por segundo (posición, FC, altitud, velocidad, cadencia, potencia)

`lee(bytes)` devuelve {"sesion", "vueltas", "puntos"} con unidades normales (m, s, m/s, grados).
`resume(lee(...))` lo deja en lo que se guarda: el resumen para `actividad` y la traza aparte.
"""
import struct
from datetime import datetime, timezone

EPOCA = 631065600  # 31/12/1989 en segundos Unix: el cero de los tiempos FIT

# tipo base (5 bits bajos) → (formato struct, valor "no hay dato")
BASE = {
    0: ("B", 0xFF), 1: ("b", 0x7F), 2: ("B", 0xFF), 3: ("h", 0x7FFF), 4: ("H", 0xFFFF),
    5: ("i", 0x7FFFFFFF), 6: ("I", 0xFFFFFFFF), 7: (None, None), 8: ("f", None), 9: ("d", None),
    10: ("B", 0), 11: ("H", 0), 12: ("I", 0), 13: (None, None),
    14: ("q", 0x7FFFFFFFFFFFFFFF), 15: ("Q", 0xFFFFFFFFFFFFFFFF), 16: ("Q", 0),
}

# número de campo → (nombre, escala, desfase) por mensaje
CAMPOS = {
    18: {253: ("ts", 1, 0), 2: ("inicio", 1, 0), 5: ("deporte", 1, 0), 6: ("subdeporte", 1, 0),
         7: ("total", 1000, 0), 8: ("seg", 1000, 0), 9: ("m", 100, 0), 11: ("kcal", 1, 0),
         14: ("vel", 1000, 0), 15: ("vel_max", 1000, 0), 124: ("vel", 1000, 0), 125: ("vel_max", 1000, 0),
         16: ("fc", 1, 0), 17: ("fc_max", 1, 0), 18: ("cad", 1, 0), 19: ("cad_max", 1, 0),
         20: ("pot", 1, 0), 21: ("pot_max", 1, 0), 22: ("sube", 1, 0), 23: ("baja", 1, 0),
         24: ("efecto", 10, 0), 137: ("efecto_ana", 10, 0)},
    19: {253: ("ts", 1, 0), 2: ("inicio", 1, 0), 7: ("total", 1000, 0), 8: ("seg", 1000, 0),
         9: ("m", 100, 0), 13: ("vel", 1000, 0), 110: ("vel", 1000, 0), 15: ("fc", 1, 0),
         16: ("fc_max", 1, 0), 17: ("cad", 1, 0), 21: ("sube", 1, 0), 22: ("baja", 1, 0)},
    20: {253: ("ts", 1, 0), 0: ("lat", 1, 0), 1: ("lon", 1, 0), 2: ("alt", 5, 500), 78: ("alt", 5, 500),
         3: ("fc", 1, 0), 4: ("cad", 1, 0), 5: ("m", 100, 0), 6: ("vel", 1000, 0), 73: ("vel", 1000, 0),
         7: ("pot", 1, 0), 13: ("temp", 1, 0)},
}
NOMBRE = {18: "sesion", 19: "vueltas", 20: "puntos"}
SEMI = 180 / 2 ** 31  # semicírculos → grados

# deporte FIT → el tipo que ya usamos en `actividad` (que_habito lo entiende)
DEPORTES = {1: "Correr", 2: "Bici", 5: "Nadar", 10: "Gimnasio", 11: "Caminar", 17: "Senderismo",
            31: "Escalar", 4: "Gimnasio"}


class ErrorFit(ValueError):
    pass


def lee(datos: bytes) -> dict:
    if len(datos) < 14 or datos[8:12] != b".FIT":
        raise ErrorFit("no es un fichero .fit")
    cab = datos[0]
    tam = struct.unpack_from("<I", datos, 4)[0]
    pos, fin = cab, min(len(datos), cab + tam)
    defs, ult_ts = {}, 0
    out = {"sesion": [], "vueltas": [], "puntos": []}
    while pos < fin:
        h = datos[pos]; pos += 1
        if h & 0x80:  # cabecera de tiempo comprimido
            local, comp = (h >> 5) & 3, h & 0x1F
            ult_ts = (ult_ts & ~0x1F) + comp + (0x20 if comp < (ult_ts & 0x1F) else 0)
            ts_comp = ult_ts
        else:
            local, ts_comp = h & 0x0F, None
            if h & 0x40:  # definición
                arq = datos[pos + 1]
                end = ">" if arq else "<"
                glob = struct.unpack_from(end + "H", datos, pos + 2)[0]
                n = datos[pos + 4]; pos += 5
                campos = [tuple(datos[pos + 3 * i: pos + 3 * i + 3]) for i in range(n)]
                pos += 3 * n
                dev = 0
                if h & 0x20:
                    nd = datos[pos]; pos += 1
                    dev = sum(datos[pos + 3 * i + 1] for i in range(nd))
                    pos += 3 * nd
                defs[local] = (glob, end, campos, dev)
                continue
        if local not in defs:
            raise ErrorFit("fichero roto: datos sin definición")
        glob, end, campos, dev = defs[local]
        mapa = CAMPOS.get(glob)
        reg = {}
        for num, size, base in campos:
            crudo = datos[pos: pos + size]; pos += size
            if not mapa or num not in mapa:
                if num == 253 and size == 4:
                    ult_ts = struct.unpack(end + "I", crudo)[0]
                continue
            fmt, nulo = BASE.get(base & 0x1F, (None, None))
            if not fmt or struct.calcsize(fmt) > size:
                continue
            v = struct.unpack_from(end + fmt, crudo)[0]
            if v == nulo:
                continue
            nombre, esc, desf = mapa[num]
            if nombre in ("lat", "lon"):
                v = v * SEMI
            elif esc != 1 or desf:
                v = v / esc - desf
            reg[nombre] = v
        pos += dev
        if "ts" in reg:
            ult_ts = int(reg["ts"])
        elif ts_comp is not None:
            reg["ts"] = ts_comp
        if glob in NOMBRE:
            out[NOMBRE[glob]].append(reg)
    return out


def _hora(ts):
    return datetime.fromtimestamp(ts + EPOCA, timezone.utc)


def ritmo(seg, km):
    if not km or km < 0.2 or not seg:
        return ""
    s = seg / km
    return f"{int(s // 60)}:{int(s % 60):02d} /km"


def _km_parciales(puntos):
    """Un parcial por km completo a partir de los puntos, con tiempo en movimiento: el COROS deja de grabar en las
    pausas (un salto en el reloj), y contar ese hueco convertía un km a 5:10 en uno a 8:40."""
    out, sig, mov, ini_m, ini_alt, ant, fcs = [], 1000, 0.0, None, None, None, []
    for p in puntos:
        if "m" not in p or "ts" not in p:
            continue
        if ini_m is None:
            ini_m = p["m"]
        if ini_alt is None:
            ini_alt = p.get("alt")
        if ant is not None and 0 < p["ts"] - ant <= 5:
            mov += p["ts"] - ant
        ant = p["ts"]
        if "fc" in p:
            fcs.append(p["fc"])
        if p["m"] >= sig:
            alt = p.get("alt")
            out.append({"km": len(out) + 1, "seg": int(round(mov)), "ritmo": ritmo(mov, (p["m"] - ini_m) / 1000),
                        "fc": round(sum(fcs) / len(fcs)) if fcs else None,
                        "dalt": round(alt - ini_alt) if alt is not None and ini_alt is not None else None})
            mov, ini_m, ini_alt, fcs, sig = 0.0, p["m"], alt, [], sig + 1000
    return out


def resume(f: dict, zona=None) -> dict:
    """De lo leído a lo que se guarda: {"dia", "actividad": {...}, "traza": {...}}."""
    s = f["sesion"][-1] if f["sesion"] else {}
    pts = f["puntos"]
    if not s and not pts:
        raise ErrorFit("el .fit no trae ni resumen ni puntos")
    ini = s.get("inicio") or s.get("ts") or (pts[0].get("ts") if pts else 0)
    hora = _hora(ini).astimezone(zona)
    m = s.get("m") or max((p.get("m", 0) for p in pts), default=0)
    seg = int(round(s.get("seg") or s.get("total") or (pts[-1]["ts"] - pts[0]["ts"] if len(pts) > 1 else 0)))
    km = round(m / 1000, 2)
    fc = [p["fc"] for p in pts if "fc" in p]
    act = {
        "id": "fit-" + hora.strftime("%Y%m%d%H%M"),
        "t": DEPORTES.get(int(s.get("deporte", -1)), "Correr" if km else "Entreno"),
        "n": "", "km": km, "min": round(seg / 60), "seg": seg, "ritmo": ritmo(seg, km), "src": "coros",
        "hora": hora.strftime("%H:%M"),
        "total": int(round(s.get("total") or seg)),
        "fc": int(s.get("fc") or (sum(fc) / len(fc) if fc else 0)) or None,
        "fc_max": int(s.get("fc_max") or max(fc, default=0)) or None,
        "cad": int(s["cad"] * 2) if s.get("cad") else None,  # FIT guarda zancadas por pierna: pasos/min = ×2
        "sube": int(s["sube"]) if s.get("sube") is not None else None,
        "baja": int(s["baja"]) if s.get("baja") is not None else None,
        "kcal": int(s["kcal"]) if s.get("kcal") else None,
        "pot": int(s["pot"]) if s.get("pot") else None,
        "efecto": round(s["efecto"], 1) if s.get("efecto") else None,
        "efecto_ana": round(s["efecto_ana"], 1) if s.get("efecto_ana") else None,
        "vel_max": round(s["vel_max"], 2) if s.get("vel_max") else None,
    }
    act = {k: v for k, v in act.items() if v is not None}
    parciales = _km_parciales(pts)
    if parciales:
        act["parciales"] = [{k: v for k, v in p.items() if v is not None} for p in parciales]
    # traza: un punto cada 5 s basta para el mapa y las gráficas (y pesa 5 veces menos)
    t0 = pts[0]["ts"] if pts else 0
    traza, ult = [], -10
    for p in pts:
        if p.get("ts", 0) - ult < 5 and p is not pts[-1]:
            continue
        ult = p.get("ts", 0)
        traza.append([int(p.get("ts", 0) - t0),
                      round(p["lat"], 6) if "lat" in p else None, round(p["lon"], 6) if "lon" in p else None,
                      round(p["m"]) if "m" in p else None, round(p["alt"], 1) if "alt" in p else None,
                      p.get("fc"), round(p["vel"], 2) if "vel" in p else None,
                      int(p["cad"] * 2) if "cad" in p else None])
    return {"dia": hora.date().isoformat(), "actividad": act,
            "traza": {"campos": ["t", "lat", "lon", "m", "alt", "fc", "vel", "cad"], "puntos": traza}}


if __name__ == "__main__":
    import json, sys
    r = resume(lee(open(sys.argv[1], "rb").read()))
    print(r["dia"], json.dumps(r["actividad"], ensure_ascii=False, indent=1))
    print(len(r["traza"]["puntos"]), "puntos en la traza;", r["traza"]["puntos"][:3])
