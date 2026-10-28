"""Plan de 5k que se ajusta solo: de ahora al domingo 14 de marzo, objetivo bajar de 22:00.

No guarda estado propio: todo sale de data.json (plan, log, sesion, actividad).
`informe()` vuelve a jugar las semanas desde INICIO, así que lo que corres (o no)
cambia el plan sin migraciones. `aplica()` reescribe las rutinas de carrera y qué
sesión toca cada día de carrera de esta semana y la siguiente.

    uv run python carrera.py            # qué haría, sin guardar
    uv run python carrera.py --aplica   # lo que lanza carrera.timer cada madrugada
"""
import json
import sys
from datetime import date, timedelta

INICIO = date(2026, 10, 26)          # lunes de la semana 1
CARRERA = date(2027, 3, 14)          # domingo: el 5k objetivo (fecha que dio Yago el 26/10)
OBJETIVO = 22 * 60
MARCA = (date(2026, 10, 20), 24 * 60, "tu marca aproximada")
FIN_BASE = date(2027, 1, 31)         # hasta aquí manda perder grasa: base aeróbica
FIN_ESPECIFICO = date(2027, 2, 28)   # luego una semana de afinar y la de la carrera
TESTS = {2, 8, 14}                   # un test de 5k cada 6 semanas
N = (CARRERA - timedelta(days=CARRERA.weekday()) - INICIO).days // 7 + 1
CORRE = ("run", "correr", "carrera", "trail")
RUTINA = {"suave": "rodaje-suave", "largo": "rodaje-largo", "series": "b2-series-1k",
          "tempo": "b2-tempo", "test": "test-5k"}
TIPO = {v: k for k, v in RUTINA.items()}


def r5(s):
    return int(5 * round(s / 5))


def mmss(s):
    s = round(s)
    return f"{s // 60}:{s % 60:02d}"


def ritmos(est):
    """Segundos por km, sacados del 5k estimado. Con 24:00 salen los de las rutinas viejas."""
    p = est / 5
    return {"suave": [r5(p + 75), r5(p + 95)], "tempo": [r5(p + 22), r5(p + 32)],
            "series": r5(p - 12), "objetivo": r5(OBJETIVO / 5)}


def rango(r):
    return f"{mmss(r[0])}-{mmss(r[1])} /km"


def fase(lunes):
    return "Base" if lunes <= FIN_BASE else "Específico" if lunes <= FIN_ESPECIFICO else "Afinar"


# ---------- sesiones (bloques con la forma de todo: ej, series, repes, kg, seg, nota) ----------
def b(ej, seg=0, nota="", series=1, repes=""):
    return {"ej": ej, "series": series, "repes": repes, "kg": 0, "seg": int(seg), "nota": nota}


def suave(mins, r, rectas=0):
    bl = [b("Caminar y movilidad", 300, "No arranques en frío. Tobillos, cadera y unos trotes cortos."),
          b(f"Rodaje a {rango(r['suave'])}", (mins - 10) * 60,
            "Ritmo de conversación: si no puedes hablar, vas rápido. Aquí se construye la base."),
          b("Vuelta a la calma", 300, "Trote muy suave y caminar.")]
    if rectas:
        bl.insert(2, b(f"{rectas} rectas de 80 m", 0, "Acelera progresivo hasta casi tope y vuelve andando. "
                                                     "Es técnica y zancada, no cansancio.", series=rectas, repes="80 m"))
    return {"tipo": "suave", "n": f"Rodaje suave · {mins} min", "min": mins, "bloques": bl}


def largo(mins, r, final="suave"):
    resto = mins - 10 - (10 if final == "tempo" else 5)
    bl = [b("Calentamiento", 300, "Movilidad y trote progresivo."),
          b(f"Rodaje a {rango(r['suave'])}", resto * 60,
            "Deliberadamente lento. Tu limitante no es la velocidad, es aguantar sin desfondarte.")]
    if final == "tempo":
        bl.append(b(f"Últimos 10 min a {rango(r['tempo'])}", 600, "Apretar cansado: justo lo que te faltó en la media."))
    else:
        bl.append(b(f"Últimos 5 min a {mmss(r['suave'][0] - 25)} /km", 300, "Sin llegar a sufrir."))
    bl.append(b("Vuelta a la calma", 300, "Caminar 5 minutos. Bebe aunque no tengas sed."))
    return {"tipo": "largo", "n": f"Rodaje largo · {mins} min", "min": mins, "bloques": bl}


def series(reps, ritmo, r, nota="Las series iguales: si la primera sale mucho más rápida, has fallado."):
    mins = round(15 + reps * (ritmo / 60 + 2) - 2 + 10)
    return {"tipo": "series", "n": f"Series · {reps}×1000 a {mmss(ritmo)}", "min": mins, "reps": reps, "bloques": [
        b("Calentamiento + 4 progresivos", 900, "12 min de trote y 4 rectas acelerando. Sin esto las series salen mal."),
        b(f"{reps} × 1000 m a {mmss(ritmo)} /km", ritmo, nota, series=reps, repes="1000 m"),
        b("Trote de recuperación entre series", 120, "2 min muy suaves. No pares del todo.", series=reps - 1),
        b("Vuelta a la calma", 600, "10 min de trote suave.")]}


def tempo(mins, r):
    return {"tipo": "tempo", "n": f"Tempo · {mins} min a {mmss(r['tempo'][0])}", "min": 25 + mins, "bloques": [
        b("Calentamiento", 900, "15 min progresivos hasta notar las piernas sueltas."),
        b(f"Tempo continuo a {rango(r['tempo'])}", mins * 60,
          "Cómodamente duro: podrías decir una frase corta, no charlar. El tempo es lo que arregla desfondarte."),
        b("Vuelta a la calma", 600, "10 min suaves.")]}


def test(est, final=False):
    salida = mmss(est / 5 + 3)
    return {"tipo": "test", "n": "Carrera 5k · a por 22:00" if final else "Test 5k", "min": round(25 + est / 60),
            "bloques": [
                b("Calentamiento largo", 900, "15 min de trote y 4 progresivos. Un test en frío no mide nada."),
                b("5000 m a tope", 0, f"Sal a {salida} /km y aprieta desde el km 3: salir fuerte es tu patrón "
                                      "y te cuesta el minuto final. Mismo recorrido siempre.", repes="5000 m"),
                b("Vuelta a la calma", 600, "Apunta el tiempo con el atajo: de aquí salen tus ritmos nuevos.")]}


def menos(m, f=.75):
    return max(20, r5(m * f))


def semana(n, lunes, nivel, descarga, est, k):
    """Las carreras de la semana n: [la del martes, la del viernes]. k = calidades ya hechas.
    La semana de la carrera lleva una tercera con "dia": va ese día aunque no esté en el calendario."""
    r = ritmos(est)
    f = fase(lunes)
    if n == N:
        activacion = suave(20, r, rectas=3)
        activacion["n"] = "Activación · 20 min"
        return [suave(30, r, rectas=4), activacion, {**test(est, final=True), "dia": CARRERA.isoformat()}]
    if n == N - 1:
        return [series(4, r["objetivo"], r, "Ritmo de carrera: que el cuerpo lo reconozca el día D."), largo(50, r)]
    if f == "Base":
        a = suave(35 + 5 * min(nivel // 2, 2), r, rectas=6 if nivel >= 2 else 0)
        bb = largo(60 + 5 * min(nivel // 2, 3), r)
    else:
        a = series(5 if k < 2 else 6, r["series"], r) if k % 2 == 0 else tempo(20 + 5 * min(k // 2, 2), r)
        bb = largo(65 + 5 * min(nivel // 4, 1), r, final="tempo")
    if descarga:
        a = {"suave": lambda: suave(menos(a["min"]), r), "tempo": lambda: tempo(15, r),
             "series": lambda: series(max(3, a["reps"] - 2), r["series"], r)}[a["tipo"]]()
        bb = largo(menos(bb["min"]), r)
    if n in TESTS:
        a, bb = test(est), largo(menos(bb["min"], .8), r)
    return [a, bb]


# ---------- lo que ha pasado de verdad ----------
def habito_correr(s):
    return next((h["id"] for h in s["habits"] if h["n"].lower().startswith("correr")), None)


def carreras(s):
    out = []
    for dia, acts in sorted(s["actividad"].items()):
        ses = s["sesion"].get(dia, {})
        rutina = next((r for r in ses.values() if r in TIPO), "")
        for a in acts:
            if not any(w in str(a.get("t") or "").lower() for w in CORRE):
                continue
            seg = a.get("seg") or a.get("min", 0) * 60
            km = a.get("km") or 0
            out.append({"dia": dia, "km": km, "seg": seg, "n": a.get("n") or "",
                        "ritmo": round(seg / km) if km >= .4 and seg else None, "tipo": TIPO.get(rutina, "libre")})
    return out


def t5(c):
    """Riegel: lo que esa carrera dice de tu 5k. Fuera lo imposible (atajo con unidades raras)."""
    if c["km"] < 3 or not c["seg"] or not 180 <= c["seg"] / c["km"] <= 540:
        return None
    t = c["seg"] * (5 / c["km"]) ** 1.06
    return t if t >= 15 * 60 else None


def informe(s, hoy=None):
    hoy = hoy or date.today()
    correr = habito_correr(s)
    runs = carreras(s)
    est, est_dia, fuente = MARCA[1], MARCA[0], MARCA[2]
    historial = [{"dia": MARCA[0].isoformat(), "seg": MARCA[1], "fuente": MARCA[2]}]
    pendientes = list(runs)

    def actualiza(hasta):
        nonlocal est, est_dia, fuente
        while pendientes and pendientes[0]["dia"] < hasta.isoformat():
            c = pendientes.pop(0)
            t = t5(c)
            if t is None:
                continue
            d = date.fromisoformat(c["dia"])
            if c["tipo"] == "test":
                est, fuente = t, f"test del {d.day}/{d.month}"
            elif t < est - 5 and t > est * .9:   # una carrera normal solo puede demostrar que vas más rápido
                est, fuente = t, f"carrera del {d.day}/{d.month}"
            else:
                continue
            est_dia = d
            historial.append({"dia": c["dia"], "seg": round(est), "fuente": fuente})

    nivel = subidas = k = 0
    descarga = False
    semanas, specs, notas, actual = [], [], [], None
    for i in range(N):
        n, lun = i + 1, INICIO + timedelta(days=7 * i)
        dom = lun + timedelta(days=6)
        actualiza(lun)
        ses = semana(n, lun, nivel, descarga, est, k)
        specs.append(ses)
        dias =[(lun + timedelta(days=j)).isoformat() for j in range(7)]
        hechas = sum(1 for d in dias if correr and correr in s["log"].get(d, []))
        suyas = [c for c in runs if dias[0] <= c["dia"] <= dias[-1]]
        estado = "pasada" if dom < hoy else "actual" if lun <= hoy else "futura"
        semanas.append({
            "n": n, "lunes": lun.isoformat(), "fase": fase(lun), "descarga": descarga, "test": n in TESTS,
            "sesiones": [{"rutina": RUTINA[x["tipo"]], "n": x["n"], "min": x["min"], "tipo": x["tipo"]} for x in ses],
            "plan_min": sum(x["min"] for x in ses), "objetivo": len(ses), "hechas": hechas,
            "hecho_min": round(sum(c["seg"] for c in suyas) / 60), "hecho_km": round(sum(c["km"] for c in suyas), 1),
            "estado": estado, "nivel": nivel,
        })
        if estado == "actual":
            actual = i
        if estado != "pasada":
            hechas = max(hechas, len(ses))   # lo que queda se proyecta como si lo cumplieras
        if any(x["tipo"] in ("series", "tempo") for x in ses) and n not in TESTS:
            k += 1
        # progresión: cumplir sube un escalón; cada 3 subidas, una semana de descarga
        if descarga:
            descarga, motivo = False, "Vengo de descarga: retomo donde estabas."
        elif hechas >= len(ses):
            nivel, subidas = nivel + 1, subidas + 1
            motivo = "Hiciste todas las carreras: subo un poco."
            if subidas >= 3:
                descarga, subidas = True, 0
                motivo = "Tres semanas subiendo: esta toca descarga para asimilar."
        elif hechas == 0:
            nivel, subidas = max(0, nivel - 1), 0
            motivo = "La semana pasada no corriste: bajo un escalón para no volver de golpe."
        else:
            motivo = f"Hiciste {hechas} de {len(ses)}: mantengo la carga."
        if estado == "pasada":
            notas = [motivo]   # se queda la de la última semana cerrada
    actualiza(hoy + timedelta(days=1))

    r = ritmos(est)
    ultima = [c for c in runs if c["dia"] >= (hoy - timedelta(days=7)).isoformat()]
    rapidos = [c for c in ultima if c["tipo"] in ("suave", "largo") and c["ritmo"] and c["ritmo"] < r["suave"][0] - 10]
    if rapidos:
        notas.append(f"Tu rodaje del {rapidos[-1]['dia'][8:]}/{rapidos[-1]['dia'][5:7]} fue a {mmss(rapidos[-1]['ritmo'])} "
                     f"/km: más rápido de la cuenta. Los suaves, a {rango(r['suave'])}.")
    if len(historial) > 1 and historial[-1]["dia"] >= (hoy - timedelta(days=7)).isoformat():
        notas.append(f"Con el {historial[-1]['fuente']} ({mmss(historial[-1]['seg'])}) he recalculado tus ritmos.")
    if not runs:
        notas.append("Aún no hay carreras con distancia y tiempo: apúntalas con el atajo o dile al bot "
                     "«he corrido 6 km en 36 min» y el plan se ajusta a lo que hagas.")

    # proyección: recta por las estimaciones si hay al menos dos separadas 3 semanas
    pts = [(date.fromisoformat(h["dia"]).toordinal(), h["seg"]) for h in historial]
    proy = None
    if len(pts) >= 2 and pts[-1][0] - pts[0][0] >= 21:
        mx, my = sum(x for x, _ in pts) / len(pts), sum(y for _, y in pts) / len(pts)
        den = sum((x - mx) ** 2 for x, _ in pts)
        pend = sum((x - mx) * (y - my) for x, y in pts) / den if den else 0
        proy = round(my + pend * (CARRERA.toordinal() - mx))
        proy = max(proy, round(est * .9))   # una recta con dos puntos promete milagros
    proximo = next((w for w in semanas if w["test"] and w["lunes"] >= (hoy - timedelta(days=hoy.weekday())).isoformat()), None)
    if proy:
        texto = f"A este ritmo llegas al {CARRERA.day} de marzo en {mmss(proy)}" + (" 🎯" if proy < OBJETIVO else "")
    elif proximo:
        texto = f"El test de la semana {proximo['n']} dirá dónde estás de verdad."
    else:
        texto = ""

    def camino(d):
        t = (d - MARCA[0]).days / (CARRERA - MARCA[0]).days
        return round(MARCA[1] + (OBJETIVO - MARCA[1]) * min(1, max(0, t)))

    for w in semanas:
        fin = date.fromisoformat(w["lunes"]) + timedelta(days=6)
        w["camino"] = camino(fin)
        w["est"] = next((h["seg"] for h in reversed(historial) if h["dia"] <= fin.isoformat()), MARCA[1]) \
            if fin <= hoy + timedelta(days=6) else None

    # los días de carrera de esta semana y la que viene, como están ahora en todo
    rut = {x["id"]: x["n"] for x in s["rutinas"]}
    lunes_hoy = hoy - timedelta(days=hoy.weekday())
    agenda = []
    for j in range(14):
        d = (lunes_hoy + timedelta(days=j)).isoformat()
        if correr and (correr in s["plan"].get(d, []) or correr in s["log"].get(d, [])):
            rid = s["sesion"].get(d, {}).get(correr, "")
            agenda.append({"dia": d, "rutina": rid, "n": rut.get(rid, "Correr"), "tipo": TIPO.get(rid, "libre"),
                           "hecho": correr in s["log"].get(d, [])})

    i = actual if actual is not None else (0 if hoy < INICIO else N - 1)
    return {
        "hoy": hoy.isoformat(), "agenda": agenda,
        "objetivo": {"dia": CARRERA.isoformat(), "seg": OBJETIVO}, "inicio": INICIO.isoformat(), "n_semanas": N,
        "semana": i + 1 if actual is not None else 0, "fase": semanas[i]["fase"],
        "estimacion": {"seg": round(est), "dia": est_dia.isoformat(), "fuente": fuente},
        "historial": historial, "ritmos": r, "semanas": semanas, "carreras": runs, "notas": notas,
        "proyeccion": {"seg": proy, "texto": texto}, "_specs": specs,
    }


# ---------- escribirlo en todo ----------
def asignaciones(s, hoy, inf):
    """(día, sesión) de las carreras planificadas desde hoy hasta el domingo que viene.
    El primer día de carrera de la semana lleva la sesión de calidad; el segundo, el largo."""
    correr = habito_correr(s)
    out = []
    lunes = hoy - timedelta(days=hoy.weekday())
    for semana_lunes in (lunes, lunes + timedelta(days=7)):
        idx = (semana_lunes - INICIO).days // 7
        if not correr or not 0 <= idx < N:
            continue
        fijas = {x["dia"]: x for x in inf["_specs"][idx] if x.get("dia")}
        specs = [x for x in inf["_specs"][idx] if not x.get("dia")]
        dias = [(semana_lunes + timedelta(days=j)).isoformat() for j in range(7)]
        corre = [d for d in dias if d not in fijas and (correr in s["plan"].get(d, []) or correr in s["log"].get(d, []))]
        pares = [(d, specs[j] if j < len(specs) else suave(35, inf["ritmos"])) for j, d in enumerate(corre)]
        for d, spec in sorted(pares + list(fijas.items())):
            if d >= hoy.isoformat() and correr not in s["log"].get(d, []):
                out.append((d, spec))
    return out


def aplica(s, hoy=None):
    """Mete en el estado de todo las sesiones y rutinas. Devuelve la lista de cambios."""
    hoy = hoy or date.today()
    correr = habito_correr(s)
    inf = informe(s, hoy)
    cambios, escritas = [], set()
    rutinas = {r["id"]: r for r in s["rutinas"]}
    for d, spec in asignaciones(s, hoy, inf):
        rid = RUTINA[spec["tipo"]]
        if rid not in escritas:   # la rutina lleva el contenido de su próxima sesión
            escritas.add(rid)
            nueva = {"id": rid, "n": spec["n"], "tipo": "carrera", "hab": correr, "bloques": spec["bloques"]}
            if rutinas.get(rid) != nueva:
                if rid in rutinas:
                    rutinas[rid].update(nueva)
                else:
                    s["rutinas"].append(nueva)
                    rutinas[rid] = nueva
                cambios.append(f"rutina {spec['n']}")
        if correr not in s["plan"].get(d, []):   # el día de la carrera no está en la semana tipo
            s["plan"][d] = s["plan"].get(d, []) + [correr]
        if s["sesion"].get(d, {}).get(correr) != rid:
            s["sesion"][d] = {**s["sesion"].get(d, {}), correr: rid}
            cambios.append(f"{d}: {spec['n']}")
    return cambios


def main():
    import urllib.request
    from pathlib import Path
    clave = next(l.split("=", 1)[1].strip() for l in (Path(__file__).parent / ".env").read_text().splitlines()
                 if l.startswith("TODO_PASS="))
    cab = {"Authorization": f"Bearer {clave}", "Content-Type": "application/json"}

    def pide(metodo, cuerpo=None):
        req = urllib.request.Request("http://127.0.0.1:8082/api/state", method=metodo, headers=cab,
                                     data=json.dumps(cuerpo).encode() if cuerpo is not None else None)
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r)

    s = pide("GET")
    inf = informe(s)
    print(f"Semana {inf['semana']}/{inf['n_semanas']} · {inf['fase']} · 5k estimado {mmss(inf['estimacion']['seg'])}")
    for x in inf["semanas"][max(0, inf["semana"] - 1)]["sesiones"]:
        print("  ", x["n"])
    for x in inf["notas"]:
        print("  -", x)
    cambios = aplica(s)
    for c in cambios:
        print("  +", c)
    if "--aplica" in sys.argv and cambios:
        pide("PUT", s)
        print("guardado")
    elif cambios:
        print("[seco] sin guardar; --aplica para escribirlo")


if __name__ == "__main__":
    main()
