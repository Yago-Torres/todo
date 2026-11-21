"""Rutinas guiadas (el core, la movilidad): cuánto hiciste de cada una y el ajuste de la semana siguiente.

    state["guias"] = {día: {rutina: {"hecho": s, "total": s, "pasos": n, "de": n}}}

- Al salir a medias del reproductor (web o Tom) se apunta lo hecho: los pasos completos y lo que llevabas del que
  estaba en marcha, en segundos. Al acabarla, el total. Varias veces el mismo día: se queda la que más.
- «Hecho» marca el hábito como siempre; si ese día hubo una a medias, queda «Hecho · 62 %».
- Cada lunes, `adapta()` mira la semana anterior de cada rutina con `adapta: true` (el core) y la ajusta:
  media ≥ 95 % → +5 s por ejercicio (hasta 90 s); 70-95 % → igual; < 70 % → la acorta hasta lo que hiciste más un
  poco (nunca menos de 20 s por ejercicio), para que la termines. El porqué queda en `rutina.ajuste`.
"""
from datetime import date, timedelta

SUBE, TOPE, SUELO = 5, 90, 20


def _r5(x):
    return int(5 * round(x / 5))


def total_seg(r):
    return sum(b.get("seg") or 30 for b in r.get("bloques", []))


def pct(x):
    return min(100, round(100 * x["hecho"] / x["total"])) if x and x.get("total") else 0


def limpia(v):
    """La forma fija de state["guias"] (clean() la usa)."""
    out = {}
    if not isinstance(v, dict):
        return out
    for dia, rs in list(v.items())[-400:]:
        if len(str(dia)) != 10 or not isinstance(rs, dict):
            continue
        d = {}
        for rid, x in list(rs.items())[:10]:
            if not isinstance(x, dict):
                continue
            try:
                total = max(1, min(7200, int(x.get("total") or 0)))
                hecho = max(0, min(total, int(x.get("hecho") or 0)))
                de = max(0, min(30, int(x.get("de") or 0)))
                pasos = max(0, min(de, int(x.get("pasos") or 0)))
            except (TypeError, ValueError):
                continue
            d[str(rid)[:24]] = {"hecho": hecho, "total": total, "pasos": pasos, "de": de}
        if d:
            out[str(dia)] = d
    return out


def apunta(s, dia, rid, hecho, total, pasos, de):
    """Lo hecho de una rutina un día (se queda la vez que más). Devuelve el % que queda."""
    g = s.setdefault("guias", {}).setdefault(dia, {})
    nuevo = {"hecho": int(hecho), "total": int(total), "pasos": int(pasos), "de": int(de)}
    if rid not in g or nuevo["hecho"] >= g[rid]["hecho"]:
        g[rid] = nuevo
    return pct(g[rid])


def adapta(s, hoy=None):
    """El ajuste del lunes. Idempotente: cada rutina guarda la semana que ya ajustó. Devuelve los textos cambiados."""
    hoy = hoy or date.today()
    lunes = hoy - timedelta(days=hoy.weekday())
    dias = [(lunes - timedelta(days=7 - i)).isoformat() for i in range(7)]
    cambios = []
    for r in s.get("rutinas", []):
        if not r.get("adapta") or (r.get("ajuste") or {}).get("semana") == lunes.isoformat():
            continue
        # sin ningún dato de antes de esta semana (recién activado): nada que comparar todavía
        if not any(r["id"] in v for d, v in s.get("guias", {}).items() if d < lunes.isoformat()):
            continue
        hechas = [s.get("guias", {}).get(d, {}).get(r["id"]) for d in dias]
        hechas = [x for x in hechas if x]
        antes = total_seg(r)
        if not hechas:
            ajuste = {"pct": None, "cambio": 0, "texto": "La semana pasada no la hiciste: se queda igual."}
        else:
            media = round(sum(pct(x) for x in hechas) / len(hechas))
            veces = f"{len(hechas)} {'vez' if len(hechas) == 1 else 'veces'}"
            if media >= 95:
                for b in r["bloques"]:
                    b["seg"] = min(TOPE, (b.get("seg") or 30) + SUBE)
                texto = f"La semana pasada la completaste ({veces}, {media} % de media): +{SUBE} s por ejercicio."
            elif media >= 70:
                texto = f"La semana pasada hiciste de media un {media} % ({veces}): se queda igual hasta que la acabes."
            else:
                f = (media + 10) / 100
                for b in r["bloques"]:
                    b["seg"] = max(SUELO, _r5((b.get("seg") or 30) * f))
                texto = (f"La semana pasada hiciste de media un {media} % ({veces}): la acorto para que la termines. "
                         "Cuando la completes, vuelve a subir.")
            ajuste = {"pct": media, "cambio": total_seg(r) - antes, "texto": texto}
        r["ajuste"] = {"semana": lunes.isoformat(), **ajuste}
        cambios.append(f"{r['n']}: {ajuste['texto']}")
    return cambios
