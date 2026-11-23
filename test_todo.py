import os
import time

os.environ["AGENDA_SIN_HILO"] = "1"   # que el hilo del calendario no cuadre los ficheros de verdad
from datetime import date

import main
from main import EMPTY, clean, firma, vale


def test_aparato():
    assert main.limpia_apariencia({"tema": "hardware"})["aparato"] == "hardware"
    assert main.limpia_apariencia({"tema": "hardware", "aparato": "calma"})["aparato"] == "calma"
    # la carcasa (aparato) va aparte del tema: se guarda si existe en el catálogo, si no, la de siempre
    a = main.limpia_apariencia({"tema": "propio", "acento": "#112233", "aparato": "hardware"})
    assert a["aparato"] == "hardware" and a["acento"] == "#112233" and a["tema"] == "propio"
    assert main.limpia_apariencia({"aparato": "tostadora"})["aparato"] == "calma"
    assert main.limpia_apariencia({})["aparato"] == "calma"
    assert any(t["id"] == "hardware" and t["aparato"] == "hardware" for t in main.catalogo()["temas"])


def test_clean():
    # basura entera -> estado vacío, no excepción
    assert clean({}) == EMPTY
    assert clean({"todos": None, "habits": "x", "log": 3, "plan": [], "rutinas": 7,
                  "sesion": "no", "peso": None}) == EMPTY

    s = clean(
        {
            "habits": [
                {"id": "a", "n": " Correr ", "c": "#e11d48", "goal": 3},
                {"id": "esc", "n": "Escalar", "goal": 1, "cada": 2},  # quincenal
                {"id": "b", "n": "  "},  # sin nombre: fuera
                {"n": "sin id"},  # sin id: fuera
                "ni siquiera un dict",
            ],
            "todos": [
                {"id": "t1", "t": "comprar bombillas", "due": "2026-09-30"},
                {"id": "t2", "t": "llamar", "done": 1, "on": "2026-09-28"},
                {"id": "t3", "t": "   "},  # sin texto: fuera
            ],
            "log": {
                "2026-09-28": ["a", "b", "fantasma", "a"],  # solo 'a' existe, sin duplicar
                "2026-09-27": ["fantasma"],  # se queda vacío: el día desaparece
                "27-09": ["a"],  # clave mala: fuera
            },
            "plan": {"2026-09-30": ["a", "fantasma"]},
            "rutinas": [
                {"id": "r1", "n": "Push A", "tipo": "pesas", "hab": "a", "bloques": [
                    {"ej": "Press banca", "series": 4, "repes": "8-10", "kg": 60},
                    {"ej": "  ", "series": 3},  # sin ejercicio: fuera
                ]},
                {"id": "r2", "n": "Movilidad AM", "tipo": "inventado", "hab": "fantasma", "bloques": [
                    {"ej": "Gato-camello", "seg": 45, "nota": "sin forzar"},
                ]},
                {"id": "r3", "n": "   "},  # sin nombre: fuera
            ],
            "sesion": {
                "2026-09-30": {"a": "r1", "fantasma": "r1", "a2": "no-existe"},
                "2026-09-29": {"a": "rutina-fantasma"},  # se queda vacío: el día desaparece
            },
            "peso": {"2026-09-28": "78.4", "2026-09-27": 999, "2026-09-26": "gordo"},
            "gym": {
                "2026-09-30": [{"id": "g1", "rutina": "r1", "n": "Push A", "t0": 1, "fin": 1, "ej": [
                    {"ej": "Press banca", "series": [[70, 8], ["72.5", "6"], [900, 8], [70], "x"]},
                    {"ej": "  ", "series": [[1, 1]]},  # sin ejercicio: fuera
                ]}, {"rutina": "sin id"}],
                "2026-09-29": [{"n": "sin id"}],  # sin sesiones válidas: el día desaparece
            },
        }
    )

    assert [h["id"] for h in s["habits"]] == ["a", "esc"]
    assert s["habits"][0]["cada"] == 1 and s["habits"][1]["cada"] == 2
    assert [t["id"] for t in s["todos"]] == ["t1", "t2"]
    assert s["log"] == {"2026-09-28": ["a"]}
    assert s["plan"] == {"2026-09-30": ["a"]}

    assert [r["id"] for r in s["rutinas"]] == ["r1", "r2"]
    assert len(s["rutinas"][0]["bloques"]) == 1  # el bloque sin ejercicio se cae
    assert s["rutinas"][0]["bloques"][0]["kg"] == 60
    assert s["rutinas"][1]["tipo"] == "pesas"  # tipo inventado -> por defecto
    assert s["rutinas"][0]["hab"] == "a"  # hábito que existe: se mantiene
    assert s["rutinas"][1]["hab"] == ""  # hábito fantasma: se cae
    assert s["rutinas"][1]["bloques"][0]["seg"] == 45

    # sesión: sólo pares (hábito, rutina) que existen los dos
    assert s["sesion"] == {"2026-09-30": {"a": "r1"}}
    # peso: fuera de rango o no numérico se descarta
    assert s["peso"] == {"2026-09-28": 78.4}
    # gym: cada serie [kg, repes]; kilos imposibles a 0, series mal formadas fuera
    assert list(s["gym"]) == ["2026-09-30"] and len(s["gym"]["2026-09-30"]) == 1
    g = s["gym"]["2026-09-30"][0]
    assert g["fin"] is True and g["ej"] == [{"ej": "Press banca", "series": [[70, 8], [72.5, 6], [0, 8]]}], g

    # idempotente: limpiar lo ya limpio no cambia nada
    assert clean(s) == s


def test_cookie():
    main.SECRET = b"secreto-de-prueba"
    futuro = int(time.time()) + 60
    assert vale(f"{futuro}.{firma(futuro)}")
    # caducada, manipulada, vacía o con otra clave: fuera
    pasado = int(time.time()) - 1
    assert not vale(f"{pasado}.{firma(pasado)}")
    assert not vale(f"{futuro}.{'0' * 64}")
    assert not vale("")
    assert not vale("no-es-un-numero.abc")
    mala = firma(futuro)
    main.SECRET = b"otra-clave"
    assert not vale(f"{futuro}.{mala}")


def test_entreno():
    import json, tempfile
    from pathlib import Path
    main.PASS, main.SECRET = "x", b"s"
    main.DB = Path(tempfile.mkdtemp()) / "data.json"
    main.DB.write_text(json.dumps({"habits": [{"id": "c", "n": "Correr", "goal": 3}]}))
    # minutos con decimales y segundos exactos: el 5k necesita los segundos
    main.registra_entreno({"tipo": "Running", "km": "5", "min": "23.5", "dia": "2026-11-03"}, None, "Bearer x")
    a = json.loads(main.DB.read_text())["actividad"]["2026-11-03"][0]
    assert (a["seg"], a["min"], a["ritmo"]) == (1410, 24, "4:42 /km"), a
    r = main.registra_entreno({"tipo": "correr", "km": 5000, "seg": 1395, "dia": "2026-11-04", "id": "x"}, None, "Bearer x")
    a = json.loads(main.DB.read_text())["actividad"]["2026-11-04"][0]
    assert (a["km"], a["seg"], a["ritmo"]) == (5, 1395, "4:39 /km"), a
    # la notificación al acabar de correr dice cómo queda el 5k
    assert "5k estimado" in r["texto"], r
    # el atajo de Salud: «Running» en inglés, metros, la duración en segundos y el inicio como id;
    # si la automatización se dispara dos veces, no se duplica
    for _ in range(2):
        main.registra_entreno({"tipo": "Running", "km": "6012", "min": "2100", "dia": "2026-11-05",
                               "id": "2026-11-05 07:31", "src": "salud"}, None, "Bearer x")
    acts = json.loads(main.DB.read_text())["actividad"]["2026-11-05"]
    assert len(acts) == 1 and (acts[0]["km"], acts[0]["seg"], acts[0]["src"]) == (6.01, 2100, "salud"), acts


def test_agenda():
    import os, tempfile
    from datetime import datetime, timezone
    from pathlib import Path
    os.environ["AGENDA_SIN_HILO"] = "1"
    import agenda
    agenda.FICHERO = Path(tempfile.mkdtemp()) / "calendario.json"
    agenda.GOOGLE_MODULO = Path("/no/existe/calendario.py")
    e = agenda.nuevo({"t": "  Dentista  ", "dia": "2026-11-20", "inicio": "10:00", "fin": "09:00", "cal": "nada", "aviso": "15"})
    assert e["t"] == "Dentista" and e["fin"] == "" and e["cal"] == "day-to-day" and e["aviso"] == 15 and "ext" not in e, e
    assert e["sincro"]["google"] == "sin configurar"
    for malo in ({"t": "x"}, {"dia": "2026-11-20"}):
        try:
            agenda.nuevo(malo)
            raise AssertionError("debía fallar")
        except ValueError:
            pass
    # repeticiones: semanal con fin, mensual que se salta los meses sin día 31, excepción
    s = agenda.nuevo({"t": "Ensayo", "dia": "2026-11-02", "inicio": "19:00", "repite": "semanal", "hasta": "2026-11-23", "cal": "ocio"})
    assert agenda.ocurrencias(agenda.todos()[1], "2026-11-01", "2026-12-31") == ["2026-11-02", "2026-11-09", "2026-11-16", "2026-11-23"]
    m = agenda.limpia({"t": "Pago", "dia": "2026-01-31", "repite": "mensual"})
    assert agenda.ocurrencias(m, "2026-01-01", "2026-05-31") == ["2026-01-31", "2026-03-31", "2026-05-31"]
    b = agenda.borra(s["id"], "2026-11-09")
    assert b["solo"] == "2026-11-09" and b["evento"]["excepciones"] == []
    assert [x["dia"] for x in agenda.rango("2026-11-01", "2026-11-30") if x["id"] == s["id"]] == ["2026-11-02", "2026-11-16", "2026-11-23"]
    agenda.restaura(b["evento"])
    assert len([x for x in agenda.rango("2026-11-01", "2026-11-30") if x["id"] == s["id"]]) == 4
    # varios días: sale en el rango aunque empiece antes
    v = agenda.nuevo({"t": "Viaje", "dia": "2026-10-30", "fin_dia": "2026-11-02"})
    assert any(x["id"] == v["id"] and x["fin_dia"] == "2026-11-02" for x in agenda.rango("2026-11-01", "2026-11-05"))
    # editar mantiene el id; borrar entero y deshacer
    ed = agenda.edita(e["id"], {"t": "Dentista (revisión)", "cal": "Deporte"})
    assert ed["id"] == e["id"] and ed["dia"] == "2026-11-20" and ed["cal"] == "Deporte"
    assert next(x for x in agenda.todos() if x["id"] == e["id"])["ext"].get("mover_de") == "day-to-day"
    bb = agenda.borra(e["id"])
    assert all(x["id"] != e["id"] for x in agenda.todos())
    agenda.restaura(bb["evento"])
    assert any(x["id"] == e["id"] for x in agenda.todos())
    # lo que se manda fuera
    ics = agenda.a_ics(next(x for x in agenda.todos() if x["id"] == s["id"]), datetime(2026, 11, 17, tzinfo=timezone.utc))
    assert "RRULE:FREQ=WEEKLY;UNTIL=20261123T225959Z" in ics and "DTSTART;TZID=Europe/Madrid:20261102T190000" in ics and "BEGIN:VTIMEZONE" in ics
    t = agenda.a_ics(agenda.limpia({"t": "Cumple, de Ana; ya", "dia": "2026-12-01", "aviso": 0}))
    assert "DTSTART;VALUE=DATE:20261201" in t and "DTEND;VALUE=DATE:20261202" in t and "SUMMARY:Cumple\\, de Ana\\; ya" in t and "TRIGGER:-PT0M" in t
    g = agenda.a_google(agenda.limpia({"t": "x", "dia": "2026-11-18", "inicio": "18:00", "fin": "19:30", "repite": "semanal", "excepciones": ["2026-11-25"]}))
    assert g["start"]["dateTime"].startswith("2026-11-18T18:00") and g["recurrence"][1] == "EXDATE;TZID=Europe/Madrid:20261125T180000", g
    # entrenos planeados: salen solos en «Deporte», siguen al plan y no se editan desde el calendario
    est = {"habits": [{"id": "gym", "n": "Gimnasio"}, {"id": "agua", "n": "Agua"}],
           "rutinas": [{"id": "push", "n": "Push A", "hab": "gym", "bloques": [{"ej": "Press banca", "series": 4, "repes": 8, "kg": 60}]}],
           "plan": {"2026-11-17": ["gym"], "2026-11-19": ["gym", "agua"], "2026-11-21": ["gym"]},
           "sesion": {"2026-11-19": {"gym": "push"}}}
    assert agenda.cuadra_entrenos(est, "2026-11-18") == (2, 0, 0)
    en = {x["entreno"]: x for x in agenda.todos() if x.get("entreno")}
    assert set(en) == {"2026-11-19:gym", "2026-11-21:gym"}, en
    assert en["2026-11-19:gym"]["t"] == "Push A" and "Press banca 4×8 · 60 kg" in en["2026-11-19:gym"]["nota"]
    assert en["2026-11-21:gym"]["t"] == "Gimnasio" and en["2026-11-21:gym"]["cal"] == "Deporte" and (en["2026-11-21:gym"]["inicio"], en["2026-11-21:gym"]["fin"]) == ("11:30", "12:30")
    assert agenda.cuadra_entrenos(est, "2026-11-18") == (0, 0, 0)   # idempotente
    larga = {**est, "rutinas": [{**est["rutinas"][0], "bloques": [{"ej": "x" * 90, "nota": "y" * 90}] * 30}]}
    agenda.cuadra_entrenos(larga, "2026-11-18")
    assert agenda.cuadra_entrenos(larga, "2026-11-18") == (0, 0, 0)   # una nota de más de 2000 no se resube siempre
    agenda.cuadra_entrenos(est, "2026-11-18")
    for f in (lambda: agenda.edita(en["2026-11-19:gym"]["id"], {"t": "x"}), lambda: agenda.borra(en["2026-11-19:gym"]["id"])):
        try:
            f()
            raise AssertionError("debía fallar")
        except ValueError:
            pass
    est["sesion"] = {}
    est["plan"] = {"2026-11-19": ["gym"], "2026-11-23": ["gym"]}
    assert agenda.cuadra_entrenos(est, "2026-11-18") == (1, 1, 1)
    en2 = {x["entreno"]: x for x in agenda.todos() if x.get("entreno")}
    assert set(en2) == {"2026-11-19:gym", "2026-11-23:gym"} and en2["2026-11-19:gym"]["id"] == en["2026-11-19:gym"]["id"]
    assert en2["2026-11-19:gym"]["t"] == "Gimnasio"
    # pasado el día, el de ayer se queda aunque salga del plan
    assert agenda.cuadra_entrenos({**est, "plan": {}}, "2026-11-20") == (0, 0, 1)
    assert {x["entreno"] for x in agenda.todos() if x.get("entreno")} == {"2026-11-19:gym"}
    assert agenda.a_google(en2["2026-11-19:gym"])["extendedProperties"]["private"]["todo_entreno"] == "2026-11-19:gym"


def test_vault():
    import tempfile
    from pathlib import Path
    import vault
    vault.VAULT = Path(tempfile.mkdtemp()) / "V"
    (vault.VAULT / "Proyectos").mkdir(parents=True)
    (vault.VAULT / "Archivo").mkdir()
    (vault.VAULT / "Curro").mkdir()
    (vault.VAULT / "Proyectos" / "Pi.md").write_text(
        "---\ntype: proyecto\n---\n- [ ] rotar token ⏫ 📅 2026-11-02\n- [x] hecho ✅ 2026-10-01\n", "utf-8")
    (vault.VAULT / "Archivo" / "Viejo.md").write_text("- [ ] no sale\n", "utf-8")
    (vault.VAULT / "Curro" / "Jira.md").write_text("- [ ] cosa del curro\n", "utf-8")
    (vault.VAULT / "Curro" / "Daily notes").mkdir()
    (vault.VAULT / "Curro" / "Daily notes" / "2026-09-01 Lunes.md").write_text("- [ ] arrastrada\n- [ ] ya no\n", "utf-8")
    (vault.VAULT / "Curro" / "Daily notes" / "2026-09-02 Martes.md").write_text(
        "- [ ] arrastrada\n- [ ] llamar (@2026-11-05 10:00)\n- [ ] plantilla (@2026-09-00 09:00)\n", "utf-8")
    (vault.VAULT / "Main hub.md").write_text("- [ ] Visit Japan\n", "utf-8")
    t = vault.nueva_tarea("  llamar   al dentista ", "2026-10-30", "10:00")
    assert t["t"] == "llamar al dentista" and (t["due"], t["hora"]) == ("2026-10-30", "10:00")
    ts = vault.tareas()
    # las de Curro/ son del trabajo: no salen (22/11); la bucket list del hub no es una tarea
    assert [x["t"] for x in ts] == ["llamar al dentista", "rotar token"], [x["t"] for x in ts]
    assert ts[1]["due"] == "2026-11-02"
    nuevo = vault.marca(ts[0]["id"])
    assert nuevo and "- [x] llamar al dentista ⏰ 10:00 📅 2026-10-30 ✅" in (vault.VAULT / "Pendientes.md").read_text("utf-8")
    assert vault.marca(nuevo, False) == ts[0]["id"]          # deshacer devuelve el id de antes
    # ni las de una nota del curro ni las de sus diarias
    assert not any(x["ruta"].startswith("Curro/") for x in vault.todas())
    # editar: cambia texto, día y hora en su sitio; la prioridad del plugin Tasks se queda
    e = vault.edita(ts[1]["id"], " rotar  el token ", "2026-11-03", "09:30")
    assert (e["t"], e["due"], e["hora"]) == ("rotar el token", "2026-11-03", "09:30"), e
    assert "- [ ] rotar el token ⏫ ⏰ 09:30 📅 2026-11-03\n- [x] hecho" in (vault.VAULT / "Proyectos" / "Pi.md").read_text("utf-8")
    e = vault.edita(e["id"], "rotar el token", "", "09:30")          # sin día, la hora sola no vale
    assert (e["due"], e["hora"]) == ("", "") and e["id"] in [x["id"] for x in vault.tareas()]
    assert vault.edita("noexiste", "x") is None
    # borrar quita la línea; deshacer la vuelve a poner en su sitio
    antes = (vault.VAULT / "Proyectos" / "Pi.md").read_text("utf-8")
    b = vault.borra(e["id"])
    assert b["i"] == 3 and "rotar el token" not in (vault.VAULT / "Proyectos" / "Pi.md").read_text("utf-8"), b
    vault.restaura(b["ruta"], b["i"], b["linea"])
    assert (vault.VAULT / "Proyectos" / "Pi.md").read_text("utf-8") == antes
    assert vault.borra("noexiste") is None
    for malo in [("../fuera.md", 0, "- [ ] x"), ("Proyectos/Pi.md", 0, "no es una tarea"), ("Curro/Jira.md", 0, "- [ ] x")]:
        try:
            vault.restaura(*malo)
            raise AssertionError(f"restaura dejó pasar {malo}")
        except ValueError:
            pass
    # la daily del curro: lo de «TODO's today» y «TODO's future» que no esté en «Done today»; el párrafo
    # cierra la lista (lo de debajo son apuntes), y fuera imágenes y la plantilla del Reminder
    daily = ("## Done today\n\n- AWS Curso\n- Preparar presentación del jueves para CAP\n\n"
             "## TODO's today\n\n- [ ] Reminder (@2026-09-00 09:00)\n- Llamar a Nacho (@2026-11-05 10:00)\n- AWS curso\n\n"
             "## TODO's future \n\n- Mirar docu Galileo Teams\n- ![[Pasted image.png]]\n- Preparar presentación del jueves\n"
             "  - un detalle sangrado\n\nPedido a telefonica:\n\n- Alert manager\n")
    d = [t for _, t in vault.de_la_daily(daily)]
    assert [(t["t"], t["due"], t["hora"]) for t in d] == [("Llamar a Nacho", "2026-11-05", "10:00"),
                                                       ("Mirar docu Galileo Teams", "", "")], d
    # el board: estados con etiqueta, proyecto de la nota, historias con subtareas y ciclos de 3 semanas
    (vault.VAULT / "Proyectos" / "todo.yagotg.dev.md").write_text(
        "## Pendiente\n- [ ] Board #historia #ui\n\t- [x] columnas ✅ 2026-11-17\n- [x] vieja ✅ 2026-11-10\n"
        "un párrafo\n  - [ ] suelta ⏫ 📅 2026-11-20\n", "utf-8")
    ts = {t["t"]: t for t in vault.todas()}
    b, c, s = ts["Board"], ts["columnas"], ts["suelta"]
    assert (b["historia"], b["tags"], b["progreso"], b["estado"]) == (True, ["todo", "ui"], [1, 1], "nueva"), b
    assert (c["padre"], c["tags"], c["estado"], c["hecha_el"]) == (b["id"], ["todo", "ui"], "hecha", "2026-11-17"), c
    assert s["padre"] == "" and not s["historia"] and s["tags"] == ["todo"]   # el párrafo corta la historia
    assert vault.ciclo(date(2026, 11, 16)) == vault.ciclo(date(2026, 12, 6)) == (date(2026, 11, 16), date(2026, 12, 6))
    assert vault.ciclo(date(2026, 12, 7))[0] == date(2026, 12, 7) and vault.ciclo(date(2026, 11, 15))[0] == date(2026, 10, 26)
    hoy = date(2026, 11, 20)
    assert [t["t"] for t in vault.hechas(vault.ciclo(hoy)[0]) if t["nota"] == "todo.yagotg.dev"] == ["columnas"]
    assert [(g["desde"], [t["t"] for t in g["tareas"]]) for g in vault.historial(hoy)][:1] == [("2026-10-26", ["vieja"])]
    a = vault.cambia_estado(s["id"], "bloqueada")
    linea = "  - [ ] suelta #bloqueada ⏫ 📅 2026-11-20"   # antes de los campos de Tasks, que siguen
    assert a["estado"] == "bloqueada" and linea in (vault.VAULT / "Proyectos" / "todo.yagotg.dev.md").read_text("utf-8")
    a = vault.cambia_estado(a["id"], "activa")
    a = vault.cambia_estado(a["id"], "hecha")
    assert (a["estado"], a["t"]) == ("hecha", "suelta") and "- [x] suelta ⏫ 📅 2026-11-20 ✅" in (
        vault.VAULT / "Proyectos" / "todo.yagotg.dev.md").read_text("utf-8")
    assert vault.cambia_estado(a["id"], "nueva")["estado"] == "nueva"
    e = vault.edita(b["id"], "Board de pendientes", tags=["ui", "Diseño web", "todo", "activa"])
    assert (e["tags"], e["historia"]) == (["todo", "ui", "Diseño-web"], True), e
    h = vault.nueva_tarea("filtros", tags=["ui"], padre=e["id"])
    assert (h["padre"], vault.una(e["id"])["progreso"]) == (e["id"], [1, 2]), h
    assert "\t- [x] columnas ✅ 2026-11-17\n\t- [ ] filtros #ui\n- [x] vieja" in (
        vault.VAULT / "Proyectos" / "todo.yagotg.dev.md").read_text("utf-8")
    n = vault.nueva_tarea("Mudanza", tags=["#casa"], historia=True)
    assert (n["historia"], n["tags"], n["grupo"]) == (True, ["casa"], "Pendientes"), n
    for malo in [lambda: vault.cambia_estado(ts["columnas"]["id"], "rara"), lambda: vault.nueva_tarea("x", padre="noexiste")]:
        try:
            malo()
            raise AssertionError("dejó pasar algo raro")
        except ValueError:
            pass
    l = vault.nueva_lectura({"url": "https://ejemplo.com/a#b", "titulo": "Qué/es: RAG?", "resumen": 'dice "hola"',
                             "tags": ["IA generativa"], "minutos": 6, "enlaces": ["Raspberry Pi"]})
    assert l["ruta"] == "Recursos/Leer luego/Qué es RAG.md", l
    [x] = vault.lecturas()
    assert (x["url"], x["minutos"], x["resumen"]) == ("https://ejemplo.com/a#b", 6, "dice 'hola'"), x
    assert [r["titulo"] for r in vault.revisar(date(2030, 1, 1))] == ["Qué es RAG"]
    vault.leido(l["ruta"])
    assert vault.lecturas() == [] and vault.revisar(date(2030, 1, 1)) == []
    # compartido desde el iPhone: nota provisional al momento y en cola; la del bot la sustituye y sale de la cola
    main.LEER_COLA = vault.VAULT.parent / "leer_cola.json"
    x = main.leer_pendiente({"url": "https://ejemplo.com/post", "titulo": "https://ejemplo.com/post"})
    assert x["ruta"] == "Recursos/Leer luego/ejemplo.com.md" and x["texto"] == "Guardado en Leer luego", x
    assert [c["ruta"] for c in main.cola_leer()] == [x["ruta"]] and "source: iphone" in (vault.VAULT / x["ruta"]).read_text("utf-8")
    nueva = vault.nueva_lectura({"url": "https://ejemplo.com/post", "titulo": "Un post", "resumen": "bien", "reemplaza": x["ruta"]})
    main.quita_de_cola(x["ruta"])
    assert [r["titulo"] for r in vault.lecturas()] == ["Un post"] and main.cola_leer() == [], vault.lecturas()
    assert vault.nueva_lectura({"url": "https://a.b", "reemplaza": "Proyectos/Pi.md"}) and (vault.VAULT / "Proyectos" / "Pi.md").exists()
    vault.leido(nueva["ruta"])
    vault.leido("Recursos/Leer luego/https a.b.md")
    assert vault.plano("![[a.jpg]] Hola **[[Raspberry Pi|la Pi]]** y [web](https://x.y) `code`\n- [ ] tarea") \
        == "Hola la Pi y web code tarea"
    # orden a mano: se queda al cambiar de columna y al editar el título; lo nuevo, detrás
    vault.ORDEN = vault.VAULT.parent / "orden.json"
    a, b = vault.nueva_tarea("orden uno", "2026-12-01"), vault.nueva_tarea("orden dos", "2026-12-02")
    nombres = lambda: [t["t"] for t in vault.tareas() if t["t"].startswith("orden")]
    assert nombres() == ["orden uno", "orden dos"]
    vault.reordena([b["id"], a["id"]])
    assert nombres() == ["orden dos", "orden uno"]
    b2 = vault.cambia_estado(b["id"], "activa")
    vault.nueva_tarea("orden tres", "2026-01-01")
    assert nombres() == ["orden dos", "orden uno", "orden tres"], nombres()
    vault.edita(b2["id"], "orden dos bis", "2026-12-02")
    assert nombres() == ["orden dos bis", "orden uno", "orden tres"], nombres()
    tres = next(t for t in vault.tareas() if t["t"] == "orden tres")
    vault.reordena([tres["id"], a["id"]])   # solo esas dos: la de arriba no se mueve
    assert nombres() == ["orden dos bis", "orden tres", "orden uno"], nombres()
    for t in vault.tareas():
        if t["t"].startswith("orden"):
            vault.borra(t["id"])
    # notas rápidas: no son tareas, se editan, se borran con deshacer y se pasan a Pendientes
    from datetime import datetime
    (vault.VAULT / vault.RAPIDAS).write_text("# Notas\n- a mano sin hora\n- [ ] esto sí es tarea\n", "utf-8")
    n = vault.nueva_nota("  idea   para la app ", datetime(2026, 11, 17, 10, 32))
    assert n["t"] == "idea para la app" and n["cuando"] == "2026-11-17 10:32", n
    assert [x["t"] for x in vault.notas_rapidas()] == ["idea para la app", "a mano sin hora"]
    assert "idea para la app" not in [t["t"] for t in vault.tareas()] and "esto sí es tarea" in [t["t"] for t in vault.tareas()]
    e = vault.edita_nota(n["id"], "idea mejor")
    assert e["cuando"] == "2026-11-17 10:32" and "- 2026-11-17 10:32 · idea mejor\n" in (vault.VAULT / vault.RAPIDAS).read_text("utf-8")
    antes = (vault.VAULT / vault.RAPIDAS).read_text("utf-8")
    b = vault.borra_nota(e["id"])
    vault.restaura_nota(b["i"], b["linea"])
    assert (vault.VAULT / vault.RAPIDAS).read_text("utf-8") == antes
    r = vault.nota_a_tarea(e["id"], "2026-11-20")
    assert r["tarea"]["t"] == "idea mejor" and r["tarea"]["due"] == "2026-11-20", r
    assert [x["t"] for x in vault.notas_rapidas()] == ["a mano sin hora"]
    for malo in (lambda: vault.nueva_nota("   "), lambda: vault.edita_nota("nohay", "x"), lambda: vault.restaura_nota(0, "- [ ] tarea")):
        try:
            malo()
            raise AssertionError("debía fallar")
        except ValueError:
            pass
    (vault.VAULT / vault.RAPIDAS).unlink()
    try:
        vault.leido("Proyectos/Pi.md")
        raise AssertionError("leido fuera de Leer luego")
    except ValueError:
        pass


def test_carrera():
    import carrera as c
    from datetime import timedelta
    s = clean({"habits": [{"id": "c", "n": "Correr", "goal": 3}],
               "rutinas": [{"id": "rodaje-suave", "n": "Viejo", "tipo": "carrera", "hab": "c", "bloques": [{"ej": "x"}]}]})
    assert c.N == 20 and c.ritmos(24 * 60)["suave"] == [365, 385]   # 6:05-6:25 con 24:00
    # semana 1 sin plan: base, nada que asignar
    inf = c.informe(s, date(2026, 10, 27))
    assert (inf["semana"], inf["fase"], inf["estimacion"]["seg"]) == (1, "Base", 1440)
    assert [x["tipo"] for x in inf["semanas"][1]["sesiones"]] == ["test", "largo"]        # semana 2: test
    assert [x["tipo"] for x in inf["semanas"][14]["sesiones"]] == ["series", "largo"]     # febrero: calidad
    assert inf["semanas"][-1]["sesiones"][-1]["n"].startswith("Carrera 5k")
    # semana de la carrera: martes y viernes como siempre, y el domingo 14/3 se añade solo
    r = clean({"habits": [{"id": "c", "n": "Correr", "goal": 3}],
               "plan": {"2027-03-09": ["c"], "2027-03-12": ["c"]}})
    c.aplica(r, date(2027, 3, 8))
    assert r["plan"]["2027-03-14"] == ["c"] and r["sesion"]["2027-03-14"] == {"c": "test-5k"}, r["sesion"]
    assert r["sesion"]["2027-03-09"] == {"c": "rodaje-suave"} and r["sesion"]["2027-03-12"] == {"c": "rodaje-suave"}
    # planifica martes y viernes; aplica pone el test el martes de la semana 2
    for d in ("2026-11-03", "2026-11-06"):
        s["plan"][d] = ["c"]
    cambios = c.aplica(s, date(2026, 11, 2))
    assert s["sesion"]["2026-11-03"] == {"c": "test-5k"} and s["sesion"]["2026-11-06"] == {"c": "rodaje-largo"}, cambios
    s = clean(s)
    assert c.aplica(s, date(2026, 11, 2)) == []                                            # idempotente
    # el día del test, el plan con los ritmos (de 24:00: 4:55, 4:50, 4:48, 4:45, 4:42); el día siguiente, nada
    m = c.plan_test(s, date(2026, 11, 3))
    assert "km 1 → 4:55" in m and "km 5 → 4:42" in m and "Total ≈ 24:00" in m and "marca real" in m, m
    assert c.plan_test(s, date(2026, 11, 4)) is None
    assert "Es el día. Objetivo: bajar de 22:00" in c.plan_test(r, date(2027, 3, 14))
    # corre el test en 23:00: la estimación y los ritmos bajan, y no se cuenta como fallo
    s["log"]["2026-11-03"] = ["c"]
    s["actividad"]["2026-11-03"] = [{"id": "t", "t": "Run", "km": 5, "seg": 1380, "min": 23}]
    inf = c.informe(s, date(2026, 11, 9))
    assert inf["estimacion"]["seg"] == 1380 and inf["ritmos"]["suave"] == [350, 370], inf["estimacion"]
    assert inf["notas"][0].startswith("Hiciste 1 de 2"), inf["notas"]
    # una carrera suave no empeora la estimación; un dato imposible (km mal) se ignora
    s["actividad"]["2026-11-06"] = [{"id": "l", "t": "Run", "km": 10, "seg": 3600},
                                    {"id": "e", "t": "Run", "km": 50, "seg": 3600}]
    assert c.informe(s, date(2026, 11, 9))["estimacion"]["seg"] == 1380
    # tres semanas cumpliendo -> descarga la cuarta
    s = clean({"habits": [{"id": "c", "n": "Correr", "goal": 3}]})
    for semana in range(3):
        for dd in (1, 4):
            d = (c.INICIO + timedelta(days=7 * semana + dd)).isoformat()
            s["plan"][d] = s["log"][d] = ["c"]
    w = c.informe(s, c.INICIO + timedelta(days=22))["semanas"]
    assert [x["descarga"] for x in w[:4]] == [False, False, False, True], [x["descarga"] for x in w[:4]]
    assert w[3]["estado"] == "actual" and w[3]["plan_min"] < w[2]["plan_min"]


def test_frontal():
    # la copia de Aitana no tiene la clave de los otros gastos: ni botones ni forma de saltar a ellos
    os.environ.pop("GASTOS_AITANA_PASS", None)
    assert 'href="/gastos-aitana.html" style' not in main.frontal("gastos").body.decode()
    os.environ["GASTOS_AITANA_PASS"] = "x"
    import tempfile
    from pathlib import Path
    g = Path(tempfile.mkdtemp()) / "gastos.html"
    g.write_text('<html lang="es"><title>Gastos</title><header class="top"><h1>Gastos</h1><div class="ciclo"></div></header>'
                 '<script>api("/api/estado"); api("/api/login"); fetch("/api/logout")</script>')
    main.OTRAS = {"gastos": ("http://x", g, "GASTOS_PASS", ""), "gastos-aitana": ("http://y", g, "GASTOS_AITANA_PASS", "Aitana")}
    os.environ.pop("GASTOS_AITANA_PASS")
    html = main.frontal("gastos").body.decode()
    os.environ["GASTOS_AITANA_PASS"] = "x"
    # la API va al reenvío; entrar y salir, al login de todo
    assert '"/api/gastos/estado"' in html and '"/api/login"' in html and '"/api/logout"' in html, html
    # el menú de todo a la derecha, sin la página en la que estás
    menu = html[html.index('<nav class="menu-todo">'):html.index("</header>")]
    assert [h for h in ("/", "/pendientes.html", "/entreno.html", "/gastos.html") if f'href="{h}"' in menu] == \
        ["/", "/pendientes.html", "/entreno.html"] and "/comida.html" not in menu, menu
    assert "Aitana" not in html, html
    # transición entre páginas también en gastos: la regla va en el <head>, antes de pintar nada
    assert html.startswith('<html lang="es" data-vt>') and html.index("@view-transition") < html.index("<header"), html
    # los gastos de Aitana: su nombre, su reenvío y el selector Yago / Aitana marcando dónde estás
    html = main.frontal("gastos-aitana").body.decode()
    assert '<h1>Gastos · Aitana</h1>' in html and '"/api/gastos-aitana/estado"' in html, html
    assert 'href="/gastos-aitana.html" style="text-decoration:none;margin-left:8px" aria-current="true"' in html, html
    assert html.index('<div class="ciclo">') < html.index('<nav class="menu-todo">') < html.index("</header>"), html
    assert 'href="/gastos.html">Gastos' not in html and 'href="/salud.html"' in html, html
    assert '"/api/gastos/' not in main.frontal("gastos-aitana").body.decode()


def test_version():
    import tempfile
    from pathlib import Path
    from fastapi import Response
    main.PASS, main.SECRET = "x", b"s"
    main.DB = Path(tempfile.mkdtemp()) / "data.json"
    r = Response()
    main.get_state(r, None, "Bearer x")
    v = r.headers["X-Version"]
    r2 = Response()
    main.put_state({"habits": [{"id": "a", "n": "Correr"}]}, r2, None, "Bearer x", v)   # con la versión buena, guarda
    try:   # con la de antes de ese guardado: otra pestaña ya escribió, 409
        main.put_state({}, Response(), None, "Bearer x", v)
        assert False
    except main.HTTPException as e:
        assert e.status_code == 409
    assert main.put_state({}, Response(), None, "Bearer x", r2.headers["X-Version"]) == main.EMPTY
    main.put_state({"habits": []}, Response(), None, "Bearer x", None)   # sin cabecera (bot, scripts): como siempre


def test_guarda():
    import tempfile
    from pathlib import Path
    p = Path(tempfile.mkdtemp()) / "data.json"
    main.guarda(p, '{"a": 1}')
    main.guarda(p, '{"a": 2}')
    # se reemplaza entero y no deja el temporal por ahí
    assert p.read_text() == '{"a": 2}' and [x.name for x in p.parent.iterdir()] == ["data.json"]


def test_portada():
    log = {"2026-10-24": ["a"], "2026-10-25": ["a", "b"], "2026-10-26": ["b"]}
    d = clean({"habits": [{"id": x, "n": x} for x in "abc"], "log": log, "comodines": {"al_mes": 0}})   # diarios, sin comodines
    # hoy sin hacer no rompe la racha; hecho hoy, cuenta
    assert main.racha(d, "a", "2026-10-26") == 2 and main.racha(d, "b", "2026-10-26") == 2
    assert main.racha(d, "c", "2026-10-26") == 0
    # la racha que se rompió ayer (la planta de Hoy se mustia con ella): sus días; si ayer se hizo, ninguna
    rota = lambda s, h, hoy: next(x["rota"] for x in main.rachas(s, hoy)["habitos"] if x["id"] == h)
    assert rota(d, "a", "2026-10-26") == 0 and rota(d, "a", "2026-10-27") == 2
    assert rota(d, "b", "2026-10-27") == 0 and rota(d, "a", "2026-10-28") == 0 and rota(clean({"habits": d["habits"]}), "a", "2026-10-27") == 0
    assert main.trozo(lambda: 1 / 0) == {"error": "division by zero"}
    s = clean({"habits": [{"id": "a", "n": "Correr"}, {"id": "b", "n": "Agua"}, {"id": "c", "n": "Leer"}],
               "log": log, "plan": {"2026-10-26": ["a", "b"]}, "peso": {"2026-10-20": 81, "2026-10-25": 80}})
    h = main.hoy_habitos(s, "2026-10-26")
    # el fantasma: de lo planificado ayer, lo que quedó sin hacer; y los días desde el último hábito
    o = main.olvidos(clean({"habits": [{"id": "a", "n": "A", "c": "#111111", "goal": 7}, {"id": "b", "n": "B", "c": "#222222", "goal": 7}],
                            "plan": {"2026-10-25": ["a", "b"]}, "log": {"2026-10-25": ["a"], "2026-10-27": ["a"], "2026-10-22": ["b"]}}), "2026-10-26")
    assert o == {"ayer": [{"id": "b", "n": "B"}], "sin_venir": 1}, o
    assert main.olvidos(clean({}), "2026-10-26") == {"ayer": [], "sin_venir": 0}
    # ajustes: lo que falta, por defecto; lo imposible, fuera; sin la clave de una app, esa sección no se puede activar
    a = main.limpia_ajustes({"nombre": "  Ana   Prueba ", "modulos": {"entreno": {"activo": False}, "salud": {"barra": False}, "gastos": {"activo": True}},
                             "mascota": {"ancho": 999, "alto": 60, "color": "red\"><script>", "extra": "x", "rubor": True}, "otra": 1})
    assert a["nombre"] == "Ana Prueba" and a["modulos"]["entreno"] == {"activo": False, "barra": True}, a
    assert a["modulos"]["salud"] == {"activo": True, "barra": False} and a["modulos"]["gastos"]["activo"] is bool(os.getenv("GASTOS_PASS")) and "comida" not in a["modulos"], a
    assert (a["mascota"]["ancho"], a["mascota"]["alto"], a["mascota"]["color"], a["mascota"]["extra"], a["mascota"]["rubor"]) == (26, 60, "#CDE77F", "", True), a
    assert "otra" not in a and main.limpia_ajustes(a) == a
    assert a["mascota"]["tipo"] == "fantasma" and main.limpia_ajustes({"mascota": {"tipo": "flor"}})["mascota"]["tipo"] == "flor"
    assert main.limpia_ajustes({"mascota": {"tipo": "<script>"}})["mascota"]["tipo"] == "fantasma"
    # los sonidos de la web, apagados salvo que se activen a propósito (con True, no con «sí»)
    assert main.limpia_ajustes({})["sonidos"] is False and main.limpia_ajustes({"sonidos": True})["sonidos"] is True
    assert main.limpia_ajustes({"sonidos": "si"})["sonidos"] is False
    # lo planificado y sin hacer arriba, luego lo planificado hecho, luego el resto
    assert [x["id"] for x in h["habitos"]] == ["a", "b", "c"], h
    # su sitio en la lista de hábitos, para que la portada reordene al marcar (movimiento.js → ordena)
    assert [x["orden"] for x in h["habitos"]] == [0, 1, 2], h
    assert h["peso"] == {"dia": "2026-10-25", "kg": 80, "media": 80.5,
                         "serie": [81, None, None, None, None, 80, None]}, h["peso"]   # 20 al 26, viejo -> nuevo
    # el año en puntos: un nivel por día desde el 1 de enero, según la parte de los hábitos hecha
    anio = main.hoy_anio(s, "2026-10-26")
    assert len(anio) == 299 and anio[-3:] == [1, 2, 1] and anio.count(3) == 0 and anio[0] == 0, anio[-3:]
    # el entreno de hoy: la rutina de la sesión; sin sesión, la única rutina del hábito; sin rutina, nada
    e = clean({"habits": [{"id": "g", "n": "Gym"}, {"id": "r", "n": "Correr"}, {"id": "x", "n": "Agua"}, {"id": "e", "n": "Escalar"}],
               "rutinas": [{"id": "pa", "n": "Push A", "tipo": "pesas", "hab": "g"}, {"id": "pb", "n": "Pull B", "tipo": "pesas", "hab": "g"},
                           {"id": "rs", "n": "Rodaje", "tipo": "carrera", "hab": "r"}, {"id": "es", "n": "Bloque", "tipo": "otro", "hab": "e"}],
               "plan": {"2026-10-26": ["g", "r", "x"]}, "sesion": {"2026-10-26": {"g": "pb"}}, "log": {"2026-10-26": ["r"]}})
    assert main.hoy_entreno(e, "2026-10-26") == [
        {"id": "g", "n": "Pull B", "tipo": "pesas", "rutina": "pb", "hecho": False},
        {"id": "r", "n": "Rodaje", "tipo": "carrera", "rutina": "rs", "hecho": True}], main.hoy_entreno(e, "2026-10-26")
    assert main.hoy_entreno(e, "2026-10-27") == []
    # una app caída no tumba la portada: su tarjeta trae el error
    main.OTRAS = {**main.OTRAS, "gastos": ("http://127.0.0.1:9", None, "X", "")}
    assert "error" in main.trozo(main.hoy_gastos)


def test_salud():
    import json, tempfile
    from pathlib import Path
    main.PASS, main.SECRET = "x", b"s"
    main.DB = Path(tempfile.mkdtemp()) / "data.json"
    # el sueño en horas, minutos o segundos: el mismo 7 h 30; los pasos van al día de antes
    for sueno in (7.5, 450, 27000):
        r = main.registra_salud({"sueno": sueno, "pasos": 9432.0, "dia": "2026-11-03"}, None, "Bearer x")
        assert r["texto"] == "Apuntado · dormido 7 h 30 · 9.432 pasos ayer", r
    s = clean(json.loads(main.DB.read_text()))
    assert s["salud"] == {"2026-11-03": {"sueno": 450}, "2026-11-02": {"pasos": 9432}}, s["salud"]
    # dos fuentes sumadas (iPhone + COROS) dan noches imposibles: se rechaza en vez de guardarlo
    try:
        main.registra_salud({"sueno": 15 * 3600 * 2}, None, "Bearer x")
        assert False
    except main.HTTPException as e:
        assert "dos fuentes" in e.detail
    # lo que no se entiende sale en la notificación, para poder arreglar el atajo
    # la báscula sola, con coma decimal como lo da Salud en español
    r = main.registra_salud({"peso": "70,46", "dia": "2026-11-03"}, None, "Bearer x")
    assert r["texto"] == "Apuntado · 70,5 kg" and clean(json.loads(main.DB.read_text()))["peso"] == {"2026-11-03": 70.5}, r
    assert main.registra_salud({"peso": "70,9 kg", "dia": "2026-11-04"}, None, "Bearer x")["texto"] == "Apuntado · 70,9 kg"
    # la composición de la báscula: con unidades, la grasa también como fracción; lo imposible se cae
    r = main.registra_salud({"grasa": "0,214", "magra": "61,3 kg", "imc": "24,8", "dia": "2026-11-04"}, None, "Bearer x")
    assert r["texto"] == "Apuntado · 21,4 % grasa · 61,3 kg magra · 24,8 IMC", r
    main.registra_salud({"grasa": "95 %", "peso": "70", "dia": "2026-11-05"}, None, "Bearer x")
    s = clean(json.loads(main.DB.read_text()))
    assert s["salud"]["2026-11-04"] == {"grasa": 21.4, "magra": 61.3, "imc": 24.8} and "grasa" not in s["salud"].get("2026-11-05", {}), s["salud"]
    c = main.cuerpo(s, date(2026, 11, 5))
    assert c["peso"][-1] == ["2026-11-05", 70.0] and c["comp"] == [["2026-11-04", 21.4, 61.3, 24.8]], c
    r = main.registra_salud({"sueno": "7 hr 32 min", "pasos": 100}, None, "Bearer x")
    assert r["texto"] == "Apuntado · sueño sin entender: «7 hr 32 min» · 100 pasos ayer", r
    h = main.hoy_salud(clean({"salud": {"2026-11-03": {"sueno": 400}, "2026-11-01": {"sueno": 500, "pasos": 8000},
                                        "2026-11-02": {"pasos": 10000}}}), "2026-11-03")
    assert h == {"sueno": {"ultimo": 400, "media": 450, "serie": [None] * 4 + [500, None, 400]},
                 "pasos": {"ultimo": 10000, "media": 9000, "serie": [None] * 4 + [None, 8000, 10000]}}, h


def test_sueno():
    import json, tempfile
    from datetime import date
    from pathlib import Path
    main.PASS, main.SECRET = "x", b"s"
    main.DB = Path(tempfile.mkdtemp()) / "data.json"
    # como lo manda el atajo: un tramo por línea; «In Bed» y lo ilegible se caen
    texto = ("Awake|2026-10-28T00:40:00+01:00|6\nCore|2026-10-28T00:46:00+01:00|30\nIn Bed|2026-10-28T00:40:00+01:00|431\n"
             "Deep|2026-10-28T01:16:00+01:00|80\nAwake|2026-10-28T02:36:00+01:00|26\nREM|2026-10-28T03:02:00+01:00|60\n"
             "Núcleo|2026-10-28T04:02:00+01:00|232\nAwake|2026-10-28T07:54:00+01:00|5\nbasura")
    r = main.registra_salud({"fases": texto, "sueno": 999, "dia": "2026-10-28"}, None, "Bearer x")   # fija: no depende de hoy
    assert r["texto"] == "Apuntado · dormido 6 h 42 en 7 tramos", r   # lo dormido sale de las fases, no de «sueno»
    s = clean(json.loads(main.DB.read_text()))
    assert s["salud"]["2026-10-28"]["fases"][1] == ["core", "2026-10-28T00:46", 1800], s["salud"]   # en segundos
    # como lo manda de verdad Atajos en español: fecha corta y la duración en segundos
    assert main.lee_fases("Awake|28.10.26, 00:43|170\nCore|28.10.26, 00:46|1700\nREM|28/10/2026 0:49|8450") == [
        ["awake", "2026-10-28T00:43", 170], ["core", "2026-10-28T00:46", 1700], ["rem", "2026-10-28T00:49", 8450]]
    i = main.informe_sueno(s, date(2026, 10, 28))
    a = i["anoche"]
    # despierto al principio y al final no cuenta; los 26 min de en medio sí. Salud dio 42 + 30 + 13
    assert (a["acostarse"], a["levantarse"]) == ("00:46", "07:54"), a
    assert a["nota"] == {"total": 85, "duracion": 42, "hora": 30, "interrupciones": 13}, a["nota"]
    assert i["noches"][-1]["fases"] == {"awake": 26, "rem": 60, "core": 262, "deep": 80}, i["noches"][-1]
    assert len(i["noches"]) == 30 and i["noches"][0]["fases"] is None and [t[0] for t in a["tramos"]][0] == "core"
    # dos noches en una tanda: cada una al día en que acabó, y nada al día en que corre el atajo
    r = main.registra_salud({"fases": "Core|09.11.26, 00:19|300\nCore|09.11.26, 05:19|100\nCore|09.11.26, 23:30|420", "dia": "2026-11-12"}, None, "Bearer x")
    s = clean(json.loads(main.DB.read_text()))
    assert (s["salud"]["2026-11-09"]["sueno"], s["salud"]["2026-11-10"]["sueno"]) == (400, 420), s["salud"]
    assert "2026-11-12" not in s["salud"] and "(2 noches)" in r["texto"], r
    assert len(s["salud"]["2026-11-09"]["fases"]) == 2
    # una noche que llega cortada no pisa a la entera
    main.registra_salud({"fases": "Core|09.11.26, 05:19|100"}, None, "Bearer x")
    assert clean(json.loads(main.DB.read_text()))["salud"]["2026-11-09"]["sueno"] == 400
    # pasos por día: cada uno al suyo, con los miles escritos o no; el día más viejo no baja
    main.registra_salud({"pasos": 7000, "dia": "2026-11-09"}, None, "Bearer x")
    r = main.registra_salud({"pasos": "08.11.26, 00:00|500\n09.11.26, 00:00|9.078\n10.11.26|1200", "dia": "2026-11-10"}, None, "Bearer x")
    s = clean(json.loads(main.DB.read_text()))
    assert [s["salud"][d]["pasos"] for d in ("2026-11-08", "2026-11-09", "2026-11-10")] == [7000, 9078, 1200], s["salud"]
    assert "9.078 pasos ayer · 1.200 pasos hoy" in r["texto"], r
    assert main.lee_pasos("9078", "2026-11-09") == {"2026-11-09": 9078} and main.lee_pasos("nada|x", "2026-11-09") == {}
    # acostarse dos horas más tarde de lo normal se paga entero en la hora
    assert main.nota([["core", "2026-10-29T03:00", 480]], [main.desde_mediodia("2026-10-28T01:00")])["hora"] == 0


def test_marca():
    import tempfile
    from pathlib import Path
    from fastapi import Response
    main.PASS, main.SECRET = "x", b"s"
    main.DB = Path(tempfile.mkdtemp()) / "data.json"
    main.put_state({"habits": [{"id": "a", "n": "Leer"}, {"id": "b", "n": "Correr"}]}, Response(), None, "Bearer x", None)
    v, r = main.version(), Response()
    m = main.marca_habito({"dia": "2026-11-02", "id": "a", "hecho": True}, r, None, "Bearer x")
    assert m["hechos"] == ["a"] and m["antes"] == v and m["version"] == r.headers["X-Version"] == main.version(), m
    # dice cómo queda, no lo cambia: repetida (llegó tarde, salió dos veces) no se deshace
    assert main.marca_habito({"dia": "2026-11-02", "id": "a", "hecho": True}, Response(), None, "Bearer x")["hechos"] == ["a"]
    main.marca_habito({"dia": "2026-11-02", "id": "b", "hecho": True}, Response(), None, "Bearer x")
    assert main.marca_habito({"dia": "2026-11-02", "id": "a", "hecho": False}, Response(), None, "Bearer x")["hechos"] == ["b"]
    # un hábito borrado mientras la marca esperaba sin red se cae, sin error
    assert main.marca_habito({"dia": "2026-11-03", "id": "zz", "hecho": True}, Response(), None, "Bearer x")["hechos"] == []
    try:
        main.marca_habito({"id": "a", "hecho": True}, Response(), None, "Bearer x")
        assert False
    except main.HTTPException as e:
        assert e.status_code == 400


def test_quita():
    s = main.sesion_gym({"id": "s", "quita": ["Press banca ", "", None, "Fondos"], "ej": [{"ej": "Remo", "series": []}]})
    # lo quitado de hoy se guarda; un ejercicio añadido sin series todavía, también
    assert s["quita"] == ["Press banca", "Fondos"] and s["ej"] == [{"ej": "Remo", "series": []}], s
    assert main.sesion_gym({"id": "s"})["quita"] == []


def test_pesos():
    assert main.lee_pesos("81.19999694824219", "2026-11-03") == {"2026-11-03": 81.2}
    # la báscula pasa a Salud tarde: cada peso a su día, y del mismo día el último
    l = "01.11.26, 08:10|80,9\n03.11.26, 07:55|81,4\n03.11.26, 21:00|81,2\n02.11.26|nada"
    assert main.lee_pesos(l, "2026-11-03") == {"2026-11-01": 80.9, "2026-11-03": 81.2}
    assert main.lee_pesos("", "2026-11-03") == {} and main.lee_pesos("3|4", "2026-11-03") == {}
    # la fecha «media» de Atajos en español también vale
    assert main.lee_pesos("21 nov 2026, 7:55|79,1\n22 de noviembre de 2026|80", "2026-11-23") == {"2026-11-21": 79.1, "2026-11-22": 80.0}


def test_a_mano():
    import json, tempfile
    from datetime import timedelta
    from pathlib import Path
    main.PASS, main.SECRET = "x", b"s"
    main.DB = Path(tempfile.mkdtemp()) / "data.json"
    hoy = date.today()
    d = lambda n: (hoy - timedelta(days=n)).isoformat()
    corta = lambda x: x[8:10] + "." + x[5:7] + "." + x[2:4]
    main.registra_salud({"peso": f"{corta(d(2))}, 07:55|80,1\n{corta(d(1))}, 08:00|95,3",
                         "pasos": f"{corta(d(2))}, 00:00|14463\n{corta(d(1))}, 00:00|6509"}, None, "Bearer x")
    # el 95,3 era de otra persona: se borra; el de anteayer se corrige; hoy se apunta a mano
    main.corrige_cuerpo({"dia": d(1), "peso": None}, None, "Bearer x")
    main.corrige_cuerpo({"dia": d(2), "peso": "79,8"}, None, "Bearer x")
    r = main.corrige_cuerpo({"dia": d(0), "peso": 79.6, "pasos": "1.200"}, None, "Bearer x")
    assert r["cuerpo"]["peso"][-2:] == [[d(2), 79.8], [d(0), 79.6]] and "79,6 kg · 1.200 pasos" in r["texto"], r
    # Tom vuelve a mandar la semana: lo tocado a mano no se pisa; un día acabado no baja; el de ayer sí sube
    main.registra_salud({"peso": f"{corta(d(2))}, 07:55|80,1\n{corta(d(1))}, 08:00|95,3\n{corta(d(0))}, 08:00|79,9",
                         "pasos": f"{corta(d(2))}, 00:00|9000\n{corta(d(1))}, 00:00|12000\n{corta(d(0))}, 00:00|3000"}, None, "Bearer x")
    s = clean(json.loads(main.DB.read_text()))
    assert s["peso"] == {d(2): 79.8, d(0): 79.6}, s["peso"]
    assert [s["salud"][x]["pasos"] for x in (d(2), d(1), d(0))] == [14463, 12000, 1200], s["salud"]
    # borrar el sueño se lleva sus tramos; lo imposible o de mañana no entra
    main.registra_salud({"fases": f"Core|{corta(d(0))}, 01:00|25000"}, None, "Bearer x")
    main.corrige_cuerpo({"dia": d(0), "sueno": ""}, None, "Bearer x")
    assert "sueno" not in clean(json.loads(main.DB.read_text()))["salud"][d(0)]
    for malo in ({"dia": d(0), "peso": "900"}, {"dia": (hoy + timedelta(days=1)).isoformat(), "peso": 80}, {"dia": d(0)}):
        try:
            main.corrige_cuerpo(malo, None, "Bearer x")
            assert False, malo
        except main.HTTPException:
            pass
    # lo que llega queda en salud.log; un peso con fecha ilegible lo dice en vez de callarse
    try:
        main.registra_salud({"peso": "ayer|80"}, None, "Bearer x")
        assert False
    except main.HTTPException as e:
        assert "peso sin entender" in e.detail, e.detail
    assert main.DB.with_name("salud.log").read_text().count("\n") == 4


def test_documentos():
    import asyncio
    import json
    import tempfile
    import urllib.parse
    from pathlib import Path
    main.PASS, main.SECRET = "x", b"s"
    main.DOCS = Path(tempfile.mkdtemp()) / "documentos"
    main.vault.VAULT = Path(tempfile.mkdtemp())

    class Pide:   # lo justo de una Request: el cuerpo
        def __init__(self, b): self.b = b
        async def body(self): return self.b

    meta = urllib.parse.quote(json.dumps({"nombre": "pasaporte.JPG", "n": "Pasaporte", "cat": "identidad", "titular": "Ana Prueba",
                                          "caduca": "2031-03-12", "notas": "x" * 400}))
    d = asyncio.run(main.sube_documento(Pide(b"foto"), meta, None, "Bearer x"))
    assert (d["n"], d["cat"], d["caduca"], d["aviso"], len(d["notas"])) == ("Pasaporte", "identidad", "2031-03-12", "2031-02-10", 300), d
    assert (main.DOCS / d["fichero"]).read_bytes() == b"foto" and d["fichero"].endswith(".jpg")
    assert "Renovar Pasaporte (caduca el 12/03/2031) 📅 2031-02-10" in (main.vault.VAULT / main.vault.PENDIENTES).read_text()
    # una garantía no se renueva; y un tipo de fichero raro no entra
    g = asyncio.run(main.sube_documento(Pide(b"t"), urllib.parse.quote('{"nombre": "t.pdf", "cat": "garantias", "caduca": "2029-11-03"}'), None, "Bearer x"))
    assert g["aviso"] == "" and g["n"] == "t"
    try:
        asyncio.run(main.sube_documento(Pide(b"x"), urllib.parse.quote('{"nombre": "x.exe"}'), None, "Bearer x"))
        assert False
    except main.HTTPException as e:
        assert e.status_code == 400
    # editar, borrar (a la papelera) y deshacer
    assert main.edita_documento(d["id"], {"titular": "", "cat": "nada"}, None, "Bearer x")["cat"] == "otros"
    main.borra_documento(d["id"], None, "Bearer x")
    assert [x["id"] for x in main.lee_docs()] == [g["id"]] and (main.DOCS / "papelera" / d["fichero"]).exists()
    main.restaura_documento(d["id"], None, "Bearer x")
    assert {x["id"] for x in main.lee_docs()} == {d["id"], g["id"]} and (main.DOCS / d["fichero"]).exists()


def test_pantalla():
    from datetime import datetime
    p = {"dias": {}, "abierta": None}
    t0 = datetime(2026, 11, 4, 22, 0).timestamp()
    main.apunta_pantalla(p, "Instagram", "abre", t0)
    main.apunta_pantalla(p, "Instagram", "cierra", t0 + 600)                # 10 min
    main.apunta_pantalla(p, "YouTube", "abre", t0 + 700)
    main.apunta_pantalla(p, "Instagram", "abre", t0 + 1000)                 # sin cierre de YouTube: se cierra aquí
    main.apunta_pantalla(p, "Instagram", "cierra", t0 + 1000 + 3 * 3600)    # se quedó abierta: como mucho 2 h
    main.apunta_pantalla(p, "TikTok", "vuelve", t0 + 20000)                 # de madrugada: la abrió y se fue
    main.apunta_pantalla(p, "TikTok", "cierra", t0 + 20001)                 # un cierre sin abrir no cuenta
    assert p["dias"]["2026-11-04"]["Instagram"] == {"n": 2, "s": 600 + 7200, "no": 0}, p
    assert p["dias"]["2026-11-04"]["YouTube"] == {"n": 1, "s": 300, "no": 0} and p["abierta"] is None
    assert p["dias"]["2026-11-05"]["TikTok"] == {"n": 0, "s": 0, "no": 1}
    r = main.resumen_pantalla(p, "2026-11-05")
    assert (r["ayer"]["s"], r["ayer"]["n"], r["hoy"]["no"]) == (8100, 3, 1) and r["semana"]["apps"][0]["app"] == "Instagram"
    assert r["serie"][-2:] == [8100, 0] and main.rato(8100) == "2 h 15 min" and main.rato(300) == "5 min"
    # con la pregunta «¿Entrar?», iOS manda «cierra» al abrir: se alterna, sin fiarse del evento
    p = {"dias": {}, "abierta": None}
    main.apunta_pantalla(p, "Instagram", "cierra", t0)          # abre (el aviso de cerrar que salta con la pregunta)
    main.apunta_pantalla(p, "Instagram", "abre", t0 + 3)        # si el de abrir llega a terminar: la misma visita
    main.apunta_pantalla(p, "Instagram", "cierra", t0 + 300)    # el cierre de verdad
    main.apunta_pantalla(p, "Instagram", "cierra", t0 + 1000)   # otra visita
    main.apunta_pantalla(p, "Instagram", "vuelve", t0 + 1005)   # «Volver»: esa no cuenta
    main.apunta_pantalla(p, "Instagram", "cierra", t0 + 1008)   # y el cierre de irse no abre nada
    assert p["dias"]["2026-11-04"]["Instagram"] == {"n": 1, "s": 300, "no": 1} and p["abierta"] is None, p
    # abrir y cerrar al momento (el 6/11 a las 7:52 contó 25 min hasta la siguiente apertura), en los dos órdenes
    p = {"dias": {}, "abierta": None}
    for t, e in [(0, "cierra"), (0, "abre"), (2, "cierra"),            # la pareja, y el cierre a los 2 s
                 (100, "abre"), (100, "cierra"), (101, "cierra"),      # la pareja al revés, y a 1 s
                 (200, "abre"), (200, "cierra"), (200, "cierra"),      # en el mismo segundo
                 (300, "cierra"), (900, "cierra"),                     # cierres repetidos sin nada abierto
                 (1500, "cierra"), (1500, "abre"), (1510, "cierra")]:
        main.apunta_pantalla(p, "Instagram", e, t0 + t)
    assert p["dias"]["2026-11-04"]["Instagram"] == {"n": 4, "s": 13, "no": 0} and p["abierta"] is None, p
    # el aviso al abrir, con límite: lo que queda, y al pasarse, cuánto
    x = {"n": 3, "s": 20 * 60}
    assert main.texto_pantalla("Instagram", x, 30) == "Instagram hoy: 3 veces, 20 min. Te quedan 10 min de 30 min"
    assert main.texto_pantalla("Instagram", {"n": 3, "s": 40 * 60}, 30).endswith("te has pasado 10 min de tu límite (30 min)")
    assert main.texto_pantalla("Instagram", x, None) == "Instagram hoy: 3 veces, 20 min"
    assert main.limpia_ajustes({})["limites"] == main.LIMITES and main.limpia_ajustes({"limites": {}})["limites"] == {}
    assert main.limpia_ajustes({"limites": {"Instagram": "25", "X": 0}})["limites"] == {"Instagram": 25}
    # el hábito del móvil se marca solo: hecho los días cerrados por debajo; hoy solo se pierde; sin medir, nada
    assert [main.dificultad(x) for x in ("7", "", "11", "6,5", None)] == [7, None, None, 6, None]
    hs = [{"id": "m", "n": "> 2 horas de móvil inútil"}, {"id": "y", "n": "Yoga"}]
    assert main.habitos_movil(hs) == {"m": ("> 2 horas de móvil inútil", 7200.0)}
    assert main.habitos_movil([{"id": "x", "n": "Móvil: menos de 90 min"}])["x"][1] == 5400
    p = {"dias": {"2026-11-03": {"Instagram": {"s": 9000}}, "2026-11-04": {"Instagram": {"s": 3000}},
                  "2026-11-05": {"Instagram": {"s": 600}}}}
    s = {"habits": hs, "log": {"2026-11-03": ["m"]}}
    assert main.revisa_movil(s, p, "2026-11-05") == [("2026-11-04", "m", True), ("2026-11-03", "m", False)]
    p["dias"]["2026-11-05"]["Instagram"]["s"] = 8000   # hoy se ha pasado
    s["log"]["2026-11-05"] = ["m"]
    assert ("2026-11-05", "m", False) in main.revisa_movil(s, p, "2026-11-05")
    # el 2, antes de que funcionara el atajo, no se toca aunque no llegue a 2 horas; un día sin avisos entre dos
    # días con avisos sí (no usó esas apps)
    assert not [c for c in main.revisa_movil(s, p, "2026-11-05") if c[0] == "2026-11-02"]
    p["dias"]["2026-11-05"] = p["dias"].pop("2026-11-04")
    p["dias"]["2026-11-06"] = {"Instagram": {"s": 60}}
    assert ("2026-11-04", "m", True) in main.revisa_movil({"habits": hs, "log": {}}, p, "2026-11-06")
    # de Instagram a Brawl: el cierre de Instagram llega tarde y no es una visita nueva
    p = {"dias": {}, "abierta": None}
    main.apunta_pantalla(p, "Instagram", "abre", t0)
    main.apunta_pantalla(p, "BrawlStars", "abre", t0 + 100)
    main.apunta_pantalla(p, "Instagram", "cierra", t0 + 101)
    main.apunta_pantalla(p, "BrawlStars", "cierra", t0 + 101.5)   # el que salta a la vez que el «abre»
    main.apunta_pantalla(p, "BrawlStars", "cierra", t0 + 160)
    assert p["dias"]["2026-11-04"] == {"Instagram": {"n": 1, "s": 100, "no": 0},
                                       "BrawlStars": {"n": 1, "s": 60, "no": 0}} and p["abierta"] is None, p
    assert len(p["eventos"]) == 5


def test_tom():
    hoy = "2026-11-11"   # miércoles
    assert [main.cuando(d, hoy) for d in ("2026-11-10", "2026-11-11", "2026-11-12", "2026-11-13", "2026-11-14", "2026-11-20")] == \
        ["ayer", "hoy", "mañana", "pasado mañana", "el sábado", "el viernes 20"]
    assert main.resumido(list("abcdef")) == "a, b, c, d y 2 más" and main.resumido(list("ab")) == "a y b"
    assert main.lista_es(["a"]) == "a" and main.lista_es(["a", "b", "c"]) == "a, b y c" and main.lista_es([]) == ""
    base = {"habits": [{"id": "g", "n": "Gimnasio", "goal": 4}, {"id": "r", "n": "Correr", "goal": 3},
                       {"id": "c", "n": "Core", "goal": 3}, {"id": "w", "n": "Agua", "goal": 7}],
            "rutinas": [{"id": "pa", "n": "Push A · Pecho", "tipo": "pesas", "hab": "g"},
                        {"id": "la", "n": "Legs A · Pierna", "tipo": "pesas", "hab": "g"},
                        {"id": "rs", "n": "Rodaje suave · 35 min", "tipo": "carrera", "hab": "r"},
                        {"id": "c10", "n": "Core 15 min", "tipo": "movilidad", "hab": "c"}],
            "plan": {"2026-11-11": ["g", "c"], "2026-11-12": ["r"], "2026-11-13": ["g"]},
            "sesion": {"2026-11-11": {"g": "pa", "c": "c10"}, "2026-11-12": {"r": "rs"}, "2026-11-13": {"g": "la"}}}
    # a un día sin gimnasio: se va con su sesión y el core se queda
    s, t = main.mueve_entreno(clean(base), hoy, "2026-11-12", hoy)
    assert s["plan"]["2026-11-11"] == ["c"] and s["plan"]["2026-11-12"] == ["g", "r"], s["plan"]
    assert s["sesion"]["2026-11-11"] == {"c": "c10"} and s["sesion"]["2026-11-12"] == {"r": "rs", "g": "pa"}, s["sesion"]
    assert t == "Push A pasa a mañana", t
    # a un día que ya tiene gimnasio: se cambian las dos sesiones, no se pierde ninguna
    s, t = main.mueve_entreno(clean(base), hoy, "2026-11-13", hoy)
    assert sorted(s["plan"]["2026-11-11"]) == ["c", "g"] and s["sesion"]["2026-11-11"]["g"] == "la" and s["sesion"]["2026-11-13"]["g"] == "pa", s
    assert t == "Push A pasa a pasado mañana y Legs A a hoy", t
    # un hábito concreto (el bot: «el rodaje al viernes») y un día vacío que se queda sin nada desaparece
    s, t = main.mueve_entreno(clean(base), "2026-11-12", "2026-11-14", hoy, "r")
    assert "2026-11-12" not in s["plan"] and s["plan"]["2026-11-14"] == ["r"] and s["sesion"]["2026-11-14"] == {"r": "rs"}, s
    assert t == "Rodaje suave pasa al sábado", t
    for de, a, hid, error in ((hoy, hoy, None, "El entreno ya es hoy"), ("2026-11-15", hoy, None, "No tienes entreno el domingo"),
                              (hoy, "2026-11-12", "r", "No tienes entreno hoy")):
        try:
            main.mueve_entreno(clean(base), de, a, hoy, hid)
            assert False
        except ValueError as e:
            assert str(e) == error, e
    hecho = clean({**base, "log": {hoy: ["g"]}})
    try:
        main.mueve_entreno(hecho, hoy, "2026-11-12", hoy)
        assert False
    except ValueError as e:
        assert str(e) == "El entreno de hoy ya está hecho", e
    # qué toca: entreno, lo que falta por marcar (solo hoy) y lo que vence
    tareas = [{"t": "Llamar al dentista", "due": hoy, "hora": "10:00"}, {"t": "Renovar DNI", "due": "2026-11-01", "hora": ""},
              {"t": "Comprar pan", "due": "2026-11-12", "hora": ""}]
    assert main.texto_toca(clean(base), hoy, hoy, tareas) == \
        "Hoy toca Push A y Core 15 min. Te falta Agua. Pendiente: Llamar al dentista a las 10:00. Y 1 tarea vencida.", \
        main.texto_toca(clean(base), hoy, hoy, tareas)
    assert main.texto_toca(clean(base), "2026-11-12", hoy, tareas) == "Mañana toca Rodaje suave. Pendiente: Comprar pan."
    assert main.texto_toca(hecho, "2026-11-15", hoy, []) == "El domingo no tienes entreno."
    assert main.texto_toca(clean({**base, "log": {hoy: ["g", "c", "w"]}}), hoy, hoy, []) == "Hoy ya has hecho Push A y Core 15 min."
    g = {"total": 935.29, "presu": 1402.0, "quedan": 13, "al_dia": 35.9}
    assert main.texto_presupuesto(g) == "Te quedan 467 € de 1402 € para 13 días, unos 36 € al día."
    assert main.texto_presupuesto({**g, "total": 1500}) == "Te has pasado 98 € del presupuesto de 1402 €."
    assert main.texto_presupuesto({**g, "presu": 0}) == "Llevas 935 € este ciclo."


def test_semana():
    hoy = "2026-11-11"   # miércoles: la semana va del 9 al 15, la pasada del 2 al 8
    s = clean({"habits": [{"id": "g", "n": "Gimnasio", "goal": 3}, {"id": "w", "n": "Agua", "goal": 7},
                          {"id": "e", "n": "Escalar", "goal": 1, "cada": 2}],
               "rutinas": [{"id": "pa", "n": "Push A", "tipo": "pesas", "hab": "g"}],
               "plan": {"2026-11-03": ["g"], "2026-11-05": ["g"], "2026-11-09": ["g"], "2026-11-11": ["g"], "2026-11-13": ["g"]},
               "log": {"2026-11-03": ["g", "w"], "2026-11-04": ["w"], "2026-11-09": ["g", "w"], "2026-11-10": ["w"], "2026-11-11": ["w"]},
               "salud": {"2026-11-03": {"sueno": 420, "pasos": 8000}, "2026-11-05": {"sueno": 480, "pasos": 10000},
                         "2026-11-09": {"sueno": 450, "pasos": 9000}, "2026-11-10": {"sueno": 510}},
               "peso": {"2026-11-02": 80.0, "2026-11-09": 79.6, "2026-11-11": 79.2}})
    r = main.resumen_semana(s, hoy, {"total": 900.0, "presu": 1400.0})
    a, p = r["actual"], r["pasada"]
    assert (a["desde"], a["hasta"], p["desde"], p["hasta"]) == ("2026-11-09", "2026-11-15", "2026-11-02", "2026-11-08"), r
    # solo cuentan los días que ya han llegado; Escalar (quincenal) no cuenta si no se hizo esa semana
    h = {x["id"]: x for x in a["habitos"]}
    assert (h["g"]["hechos"], h["g"]["objetivo"], h["w"]["hechos"], h["w"]["racha"], h["e"]["objetivo"]) == (1, 3, 3, 3, 0), a
    assert (a["hechos"], a["objetivo"], p["hechos"], p["objetivo"]) == (4, 10, 3, 10), (a, p)
    assert a["entrenos"] == {"hechos": 1, "planificados": 2} and p["entrenos"] == {"hechos": 1, "planificados": 2}, (a, p)
    assert a["sueno"] == {"media": 480, "noches": 2} and p["sueno"] == {"media": 450, "noches": 2}, (a, p)
    assert a["pasos"] == {"media": 9000, "dias": 1} and r["cambio"] == {"sueno": 30, "pasos": 0}, r["cambio"]
    assert a["peso"] == {"inicio": 79.6, "fin": 79.2} and p["peso"] == {"inicio": 80.0, "fin": 80.0}, (a, p)
    assert 1 <= len(r["resumen"]) <= 3 and r["resumen"][0].startswith("Esta semana llevas 4 de 10 hábitos (la pasada, 3 de 10)"), r["resumen"]
    assert any("30 min más" in f for f in r["resumen"]), r["resumen"]
    assert r["resumen"][-1] == "Del ciclo te quedan 500 € de 1400 €.", r["resumen"]
    # sin gastos conectados ni datos: no se rompe y dice algo
    vacio = main.resumen_semana(clean({}), hoy, {"error": "Sin conectar"})
    assert vacio["resumen"] == ["Aún no hay datos para resumir la semana."] and vacio["cambio"] == {"sueno": None, "pasos": None}, vacio
    assert main.semana_de(clean({}), date(2026, 11, 16), hoy)["habitos"] == []   # una semana futura, vacía


def test_rachas():
    H = [{"id": "g", "n": "Gimnasio", "goal": 3}, {"id": "w", "n": "Agua", "goal": 7}, {"id": "l", "n": "Leer", "goal": 2}]
    r = lambda s, hoy: {x["id"]: x for x in main.rachas(clean(s), hoy)["habitos"]}
    # diario: cada día cuenta; sin comodines, un día sin hacer la rompe
    base = {"habits": H, "comodines": {"al_mes": 0}, "log": {f"2026-11-0{i}": ["w"] for i in range(1, 6)}}
    assert r(base, "2026-11-05")["w"]["racha"] == 5 and r(base, "2026-11-06")["w"]["racha"] == 5
    assert r(base, "2026-11-06")["w"]["en_juego"] and r(base, "2026-11-06")["w"]["exigido"]
    assert r(base, "2026-11-07")["w"]["racha"] == 0 and r(base, "2026-11-07")["w"]["rota"] == 5
    assert r(base, "2026-11-07")["w"]["dias"]["2026-11-06"] == "fallo"
    # un descanso de ese hábito (o de todos, "*") congela: ni suma ni rompe
    des = {**base, "descansos": {"2026-11-06": ["w"]}, "log": {**base["log"], "2026-11-07": ["w"]}}
    x = r(des, "2026-11-07")["w"]
    assert x["racha"] == 6 and x["dias"]["2026-11-06"] == "descanso", x
    assert r({**des, "descansos": {"2026-11-06": ["*"]}}, "2026-11-07")["w"]["racha"] == 6
    # hoy de descanso: no está en juego y lo dice
    x = r({**base, "descansos": {"2026-11-06": ["w"]}}, "2026-11-06")["w"]
    assert (x["racha"], x["libre"], x["en_juego"], x["dias"]["2026-11-06"]) == (5, "descanso", False, "descanso"), x
    # vacaciones / enfermedad: para todos o para algunos; congelan sin romper
    vac = {**base, "vacaciones": [{"desde": "2026-11-06", "hasta": "2026-11-09", "motivo": "enfermedad", "habitos": ["w"]}],
           "log": {**base["log"], "2026-11-10": ["w"]}}
    x = r(vac, "2026-11-10")["w"]
    assert x["racha"] == 6 and x["dias"]["2026-11-08"] == "enfermedad", x
    assert r({**vac, "vacaciones": [{**vac["vacaciones"][0], "habitos": []}]}, "2026-11-10")["w"]["racha"] == 6
    assert r({**vac, "vacaciones": [{**vac["vacaciones"][0], "habitos": ["g"]}]}, "2026-11-10")["w"]["racha"] == 1
    # con plan esa semana manda el plan: lo no planificado no cuenta, lo planificado sin hacer rompe
    plan = {"habits": H, "comodines": {"al_mes": 0}, "plan": {"2026-11-09": ["g"], "2026-11-11": ["g"], "2026-11-13": ["g"]},
            "log": {"2026-11-09": ["g"], "2026-11-11": ["g"]}}
    x = r(plan, "2026-11-12")["g"]
    assert (x["racha"], x["exigido"], x["manana"]) == (2, False, True), x
    assert r(plan, "2026-11-13")["g"]["en_juego"] and r(plan, "2026-11-14")["g"]["racha"] == 0
    # sin plan esa semana: hay que hacerlo cada ventana días (2/sem → cada 4)
    assert main.ventana({"goal": 2, "cada": 1}) == 4 and main.ventana({"goal": 7, "cada": 1}) == 1 and main.ventana({"goal": 1, "cada": 2}) == 14
    libre_ = {"habits": H, "comodines": {"al_mes": 0}, "log": {"2026-11-02": ["l"], "2026-11-05": ["l"]}}
    assert r(libre_, "2026-11-08")["l"]["racha"] == 2 and not r(libre_, "2026-11-08")["l"]["exigido"]
    assert r(libre_, "2026-11-09")["l"]["en_juego"] and r(libre_, "2026-11-10")["l"]["racha"] == 0
    # comodines: se gastan solos el primer día que una racha se rompería; uno cubre todo el día; al acabarse, rompe
    com = {**base, "comodines": {"al_mes": 1}, "log": {**base["log"], "2026-11-07": ["w"]}}
    t = main.rachas(clean(com), "2026-11-07")
    assert t["habitos"][1]["racha"] == 6 and t["habitos"][1]["dias"]["2026-11-06"] == "comodin", t["habitos"][1]
    assert t["comodines"] == {"al_mes": 1, "usados": ["2026-11-06"], "quedan": 0, "hoy": False}, t["comodines"]
    assert r({**com, "log": base["log"]}, "2026-11-08")["w"]["racha"] == 0   # el segundo fallo ya no tiene comodín
    # el mes siguiente vuelven a estar
    nov = {**base, "comodines": {"al_mes": 1}, "log": {"2026-10-30": ["w"], "2026-11-01": ["w"]}}
    assert main.rachas(clean(nov), "2026-11-02")["comodines"]["quedan"] == 1 and r(nov, "2026-11-01")["w"]["racha"] == 2
    # a mano (hoy): congela hoy y cuenta en los del mes
    t = main.rachas(clean({**base, "comodines": {"al_mes": 2, "usados": ["2026-11-06"]}}), "2026-11-06")
    assert t["comodines"]["quedan"] == 1 and t["habitos"][1]["libre"] == "comodin" and not t["habitos"][1]["en_juego"]
    # hitos: el siguiente y lo que falta; el día que se llega, hito
    sem = {"habits": H, "log": {f"2026-11-0{i}": ["w"] for i in range(1, 8)}}
    x = r(sem, "2026-11-07")["w"]
    assert (x["racha"], x["hito"], x["siguiente"], x["falta"]) == (7, 7, 14, 7), x
    assert r(sem, "2026-11-06")["w"]["falta"] == 1 and r(sem, "2026-11-06")["w"]["hito"] is None
    # la llamada: la racha mayor en juego y los hábitos que la salvan hoy
    ll = {"habits": H, "plan": {"2026-11-06": ["g"], "2026-11-04": ["g"]}, "log": {**base["log"], "2026-11-04": ["g", "w"]}}
    assert main.rachas(clean(ll), "2026-11-06")["llamada"] == "Mantén tu racha de 5 días: Agua y Gimnasio"
    # el estado guarda todo limpio, y un periodo sin hábitos que existan se cae (no pasa a «todos»)
    c = clean({"habits": H, "descansos": {"2026-11-06": ["w", "x", "*"], "malo": ["w"]},
               "vacaciones": [{"desde": "2026-11-09", "hasta": "2026-11-01"}, {"desde": "2026-12-01", "hasta": "2026-12-10", "habitos": ["x"]},
                              {"desde": "2026-12-01", "hasta": "2026-12-10", "motivo": "raro", "id": "v1"}],
               "comodines": {"al_mes": 99, "usados": ["2026-11-06", "x"]}})
    assert c["descansos"] == {"2026-11-06": ["*", "w"]} and c["comodines"] == {"al_mes": 10, "usados": ["2026-11-06"]}, c
    assert c["vacaciones"] == [{"id": "v1", "desde": "2026-12-01", "hasta": "2026-12-10", "habitos": [], "motivo": "vacaciones"}], c
    assert clean(c) == c


def test_carrera_calendario():
    import agenda
    import carrera
    s = {"habits": [{"id": "c", "n": "Correr"}], "rutinas": [{"id": carrera.RUTINA["suave"], "hab": "c", "n": "x", "bloques": []}],
         "plan": {}, "log": {}, "sesion": {}, "actividad": {}}
    d = agenda.carrera_deseada(s, "2026-11-19")
    assert f"carrera:dia-d:{carrera.CARRERA.isoformat()}" in d
    assert all(v["dia"] >= "2026-11-19" and v["cal"] == "Deporte" for v in d.values())
    assert not any(k.startswith("carrera:descarga") and v["dia"] >= "2027-03-01" for k, v in d.items())
    assert agenda.carrera_deseada({**s, "rutinas": []}, "2026-11-19") == {}   # sin el plan aplicado (Aitana), nada
    assert not any(":test-" in k or ":descarga-" in k for k in d), d   # sin eventos de semana entera
    # con hora, uno detrás de otro: gimnasio a las 18:00 y el core al acabar; la movilidad de la mañana, a las 7:30
    e = {"habits": [{"id": "g", "n": "Gym"}, {"id": "k", "n": "Core"}, {"id": "m", "n": "Estirar"}],
         "rutinas": [{"id": "push", "n": "Push", "tipo": "pesas", "hab": "g", "bloques": []},
                     {"id": "core-10", "n": "Core", "tipo": "movilidad", "hab": "k", "bloques": [{"seg": 400}]},
                     {"id": "manana", "n": "Mañana", "tipo": "movilidad", "hab": "m", "bloques": [{"seg": 600}]}],
         "plan": {"2026-11-23": ["k", "g", "m"]}, "sesion": {"2026-11-23": {"g": "push", "k": "core-10", "m": "manana"}}}
    h = {k: (v["inicio"], v["fin"]) for k, v in agenda.entrenos_deseados(e, "2026-11-23").items()}
    assert h == {"2026-11-23:g": ("18:00", "19:00"), "2026-11-23:k": ("19:00", "19:10"), "2026-11-23:m": ("07:30", "07:40")}, h


def test_cubierto():
    """Un hábito de 1 vez por semana o menos, hecho hace poco, cuenta como hecho hasta que vuelve a tocar."""
    base = {"habits": [{"id": "l", "n": "Limpiar", "c": "#000", "goal": 1, "cada": 1},
                       {"id": "e", "n": "Escalar", "c": "#000", "goal": 1, "cada": 2},
                       {"id": "a", "n": "Agua", "c": "#000", "goal": 7, "cada": 1}],
            "log": {"2026-11-16": ["l", "e", "a"]}}
    r = lambda s, hoy: {x["id"]: x["cubierto"] for x in main.rachas(clean(s), hoy)["habitos"]}
    assert r(base, "2026-11-17") == {"l": "2026-11-21", "e": "2026-11-28", "a": None}
    assert r(base, "2026-11-22")["l"] is None and r(base, "2026-11-22")["e"] == "2026-11-28"   # el domingo, Limpiar toca
    assert r(base, "2026-11-16") == {"l": None, "e": None, "a": None}   # hecho hoy: es «hecho», no cubierto
    plan = {**base, "plan": {"2026-11-27": ["e"]}}   # una semana con plan manda el plan
    assert r(plan, "2026-11-24")["e"] is None
    # 3 por semana: el día de entre medias no se exige y la racha sigue viva (Hoy lo pinta «al día», no pendiente)
    tres = clean({"habits": [{"id": "c", "n": "Correr", "c": "#000", "goal": 3, "cada": 1}], "log": {"2026-11-17": ["c"], "2026-11-20": ["c"]}})
    h = main.hoy_habitos(tres, "2026-11-21")["habitos"][0]
    assert (h["exigido"], h["racha"], h["hecho"], h["libre"]) == (False, 2, False, None), h
    print("cubierto ok")


def test_explorar():
    import explorar, tempfile
    from pathlib import Path
    explorar.FICHERO = Path(tempfile.mkdtemp()) / "explorar.json"
    crudo = """Aquí va:
```json
{"resumen": "Todo en un ETF", "huecos": [{"t": "Nada en emergentes", "por_que": "0 %"}, {"x": 1}],
 "ideas": [{"tipo": "fondo", "nombre": "MSCI EM IMI", "isin": "ie00bkm4gz66", "riesgo": 9, "fuentes": ["https://a.es", "javascript:x"]},
           {"tipo": "raro", "nombre": "Uranio"}, {"nombre": ""}],
 "aprender": {"titulo": "TER", "texto": "…"}}
```"""
    x = explorar.limpia_informe(explorar.saca_json(crudo))
    assert [i["nombre"] for i in x["ideas"]] == ["MSCI EM IMI", "Uranio"] and x["ideas"][1]["tipo"] == "tema"
    i = x["ideas"][0]
    assert i["isin"] == "IE00BKM4GZ66" and i["riesgo"] == 5 and i["fuentes"] == ["https://a.es"] and len(x["huecos"]) == 1
    explorar._guarda({"informes": [{"id": "e1", "fecha": "2026-11-20", "t": 0, "estado": "listo", **x}], "reacciones": {}})
    assert explorar.reacciona(i["id"], "descarta", "muy volátil")["estado"] == "descarta"
    try:
        explorar.reacciona("nope", "interesa"); assert False
    except KeyError:
        pass
    explorar.reacciona(i["id"], "")
    assert explorar.lee()["reacciones"] == {}
    print("explorar ok")


def test_uso():
    import uso, tempfile
    from pathlib import Path
    uso.USO = Path(tempfile.mkdtemp()) / "uso.jsonl"
    assert uso.de_peticion("GET", "/api/hoy", "Mozilla/5.0", "1.1.1.1", 200) is None   # sondeo: no es uso
    assert uso.de_peticion("POST", "/api/marca", "Hoy/3 CFNetwork/1 Darwin/25", "172.20.0.3", 200) == "habitos:marcar"
    assert uso.de_peticion("POST", "/api/inversiones/explorar/reaccion", "Mozilla/5.0 (iPhone)", "x", 200) == "inversiones:explorar"
    assert uso.de_peticion("POST", "/api/marca", "Mozilla", "x", 409) is None
    uso.de_peticion("POST", "/api/salud", "Shortcuts/1", "x", 200)   # atajo: se apunta como automático
    uso.apunta("aviso:resumen", "telegram", auto=True, app="bot")
    r = uso.informe(7)
    assert [f["que"] for f in r["funciones"]] == ["habitos:marcar", "inversiones:explorar"], r["funciones"]
    assert r["clientes"] == {"tom": 1, "web-movil": 1} and r["avisos"] == {"resumen": 1}
    assert "pendientes" in r["sin_usar"] and uso.franja(7) == "mañana" and uso.franja(23) == "noche"
    print("uso ok")


def _fit_de_prueba(km=3, pausa=60):
    """Un .fit mínimo hecho a mano: un punto por segundo a 4 m/s (4:10 /km) con una pausa en medio, y la sesión."""
    import struct
    cuerpo = bytearray()
    # definición local 0 = record (20): ts, lat, lon, m, fc
    cuerpo += bytes([0x40, 0, 0]) + struct.pack("<HB", 20, 5) + bytes([253, 4, 0x86, 0, 4, 0x85, 1, 4, 0x85, 5, 4, 0x86, 3, 1, 2])
    ts, m = 1100000000, 0.0
    for i in range(int(km * 250) + 1):
        if i == 300:
            ts += pausa          # el reloj deja de grabar en la pausa
        cuerpo += bytes([0]) + struct.pack("<IiiIB", ts, int(41.65 / (180 / 2**31)) + i * 50, int(-0.88 / (180 / 2**31)), int(m * 100), 150)
        ts += 1; m += 4
    # definición local 1 = session (18): inicio, deporte, seg (timer), m, fc, sube
    cuerpo += bytes([0x41, 0, 0]) + struct.pack("<HB", 18, 6) + bytes([2, 4, 0x86, 5, 1, 0, 8, 4, 0x86, 9, 4, 0x86, 16, 1, 2, 22, 2, 0x84])
    cuerpo += bytes([1]) + struct.pack("<IBIIBH", 1100000000, 1, int(km * 250) * 1000, int(km * 1000 * 100), 150, 12)
    cab = struct.pack("<BBHI4s", 12, 0x20, 2100, len(cuerpo), b".FIT")
    return cab + bytes(cuerpo) + b"\0\0"


def test_fit():
    import json, tempfile, fit
    from pathlib import Path
    r = fit.resume(fit.lee(_fit_de_prueba()))
    a = r["actividad"]
    assert (a["t"], a["km"], a["seg"], a["ritmo"], a["fc"], a["sube"]) == ("Correr", 3, 750, "4:10 /km", 150, 12), a
    # la pausa no cuenta en el parcial: los tres km a 4:10
    assert all(249 <= x["seg"] <= 251 for x in a["parciales"]) and len(a["parciales"]) == 3, a["parciales"]
    assert r["traza"]["puntos"][1][1] and len(r["traza"]["puntos"]) < 200
    try:
        fit.lee(b"no soy un fit en absoluto")
        assert False
    except fit.ErrorFit:
        pass
    # por la API: marca el hábito, sustituye a la del atajo de ese día y guarda la traza aparte
    main.PASS, main.SECRET = "x", b"s"
    d = Path(tempfile.mkdtemp())
    main.DB, main.TRAZAS = d / "data.json", d / "actividades"
    dia = r["dia"]
    main.DB.write_text(json.dumps({"habits": [{"id": "c", "n": "Correr", "goal": 3}],
                                   "actividad": {dia: [{"id": "atajo", "t": "Correr", "km": 3.1, "seg": 760, "src": "ios"}]}}))
    out = main.apunta_fit(_fit_de_prueba())
    s = json.loads(main.DB.read_text())
    assert [x["id"] for x in s["actividad"][dia]] == [out["id"]] and "c" in s["log"][dia] and "sustituye" in out["texto"], out
    assert s["actividad"][dia][0]["parciales"][0]["fc"] == 150          # clean() no se come lo nuevo
    assert main.una_actividad(out["id"], None, "Bearer x")["traza"]["puntos"]
    assert main.apunta_fit(_fit_de_prueba())["nueva"] is False            # subirla dos veces no la duplica
    print("fit ok")


def _traza(vel, km=3, dia="2026-11-20", lon=-0.88, pausa=0, al_reves=False):
    """Una traza como las de actividades/: en línea recta hacia el norte (o hacia el sur) a `vel` m/s, punto cada 5 s."""
    pts, t, m = [], 0, 0.0
    while m <= km * 1000:
        lat = 41.65 + ((km * 1000 - m) if al_reves else m) / 110540
        pts.append([t, round(lat, 6), lon, round(m), 200.0, 150, vel, 170])
        t += 5; m += vel * 5
        if pausa and len(pts) == 50:
            t += pausa
    return {"dia": dia, "campos": ["t", "lat", "lon", "m", "alt", "fc", "vel", "cad"], "puntos": pts}


def test_rutas():
    import rutas
    vieja, hoy = _traza(4.0, dia="2026-11-20"), _traza(4.0 * 250 / 245, dia="2026-11-27", pausa=90)
    assert rutas.misma_ruta(hoy, vieja) and rutas.misma_ruta(vieja, hoy)
    assert not rutas.misma_ruta(_traza(4, al_reves=True), vieja)              # al revés no es la misma
    assert not rutas.misma_ruta(_traza(4, lon=-0.85), vieja)                   # 2,5 km al este
    assert not rutas.misma_ruta(_traza(4, km=6), vieja)                        # el doble de larga
    f = rutas.fantasma(hoy, vieja)
    # 5 s por km más rápido, y la pausa de 90 s no cuenta
    assert [k["km"] for k in f["km"]] == [1, 2, 3] and all(-6 <= k["dif"] * 1 / k["km"] <= -4 for k in f["km"]), f["km"]
    otras = [("fit-202611200800", vieja), ("fit-202611230800", _traza(3.8, dia="2026-11-23")),
             ("fit-202612010800", _traza(5, dia="2026-12-01")), ("fit-202611210800", _traza(4, lon=-0.85))]
    b = rutas.busca("fit-202611270800", hoy, otras)
    assert b["veces"] == 2 and b["ultima"]["dia"] == "2026-11-23" and b["mejor"]["dia"] == "2026-11-20", b
    assert "más rápido que el 23/11" in rutas.frase(b) and "mejor vez" in rutas.frase(b), rutas.frase(b)
    assert rutas.busca("fit-202611270800", _traza(4, lon=-0.80), otras) is None
    g = rutas.gpx(vieja, "3 km <prueba>")
    assert g.count("<trkpt") == len(vieja["puntos"]) and "&lt;prueba&gt;" in g
    # biblioteca: forma y nombre, agrupar, sugerir
    ida_vuelta = _traza(4, km=2)
    vuelta = _traza(4, km=2, al_reves=True)["puntos"]
    ida_vuelta["puntos"] += [[p[0] + ida_vuelta["puntos"][-1][0] + 5, p[1], p[2], p[3] + 2005, *p[4:]] for p in vuelta]
    assert rutas.forma(vieja) == "Solo ida" and rutas.forma(ida_vuelta) == "Ida y vuelta", rutas.forma(ida_vuelta)
    assert rutas.nombre_auto(vieja) == "Solo ida de 3,0 km"
    trazas = {"fit-1": vieja, "fit-2": hoy, "fit-3": _traza(4, lon=-0.85), "fit-4": ida_vuelta}
    bib = []
    for i, tr in trazas.items():
        rutas.clasifica(bib, i, tr, trazas.get)
    assert [r["fits"] for r in bib] == [["fit-1", "fit-2"], ["fit-3"], ["fit-4"]], bib
    assert rutas.clasifica(bib, "fit-2", hoy, trazas.get) == (bib[0], False)          # repetir no duplica
    assert [r["id"] for r in rutas.sugeridas(bib, 3.2)] == ["r1", "r2"] and rutas.sugeridas(bib, 10) == []
    # segmentos: del metro 500 al 1500 de la vieja
    s = rutas.segmento(vieja, 500, 1500, "Recta del parque")
    assert 990 <= s["m"] <= 1000 and s["nombre"] == "Recta del parque"
    p = rutas.pasos(s, hoy)
    assert len(p) == 1 and 240 <= p[0]["seg"] <= 250 and 480 <= p[0]["m"] <= 520, p
    assert rutas.pasos(s, _traza(4, al_reves=True)) == [] and rutas.pasos(s, _traza(4, lon=-0.85)) == []
    assert len(rutas.pasos(s, ida_vuelta)) == 1                                         # a la vuelta va al revés: no cuenta
    s["intentos"] = [{"fit": "a", "seg": 250}, {"fit": "b", "seg": 240}, {"fit": "b", "seg": 260}, {"fit": "c", "seg": 255}]
    assert (rutas.puesto(s, "b"), rutas.puesto(s, "a"), rutas.puesto(s, "c"), rutas.puesto(s, "z")) == (1, 2, 3, None)
    try:
        rutas.segmento(vieja, 500, 550, "")
        assert False
    except ValueError:
        pass
    # por la API: dos carreras por la misma ruta, un segmento, la segunda mejora
    import json, tempfile
    from pathlib import Path
    main.PASS, main.SECRET = "x", b"s"
    d = Path(tempfile.mkdtemp())
    main.DB, main.TRAZAS = d / "data.json", d / "actividades"
    main.TRAZAS.mkdir()
    main.DB.write_text(json.dumps({"habits": [{"id": "c", "n": "Correr", "goal": 3}], "actividad": {
        "2026-11-20": [{"id": "fit-202611200800", "t": "Correr", "km": 3, "seg": 750}],
        "2026-11-27": [{"id": "fit-202611270800", "t": "Correr", "km": 3, "seg": 735}]}}))
    (main.TRAZAS / "fit-202611200800.json").write_text(json.dumps(vieja))
    assert main.rutas_y_segmentos("fit-202611200800", vieja) == []
    seg = main.crea_segmento({"fit": "fit-202611200800", "desde": 500, "hasta": 1500, "nombre": "Recta"}, None, "Bearer x")
    assert seg["veces"] == 1 and seg["mejor"]["fit"] == "fit-202611200800"
    (main.TRAZAS / "fit-202611270800.json").write_text(json.dumps(hoy))
    fr = main.rutas_y_segmentos("fit-202611270800", hoy)
    assert fr and "mejor marca en «Recta»" in fr[0], fr
    L = main.lista_rutas(3, None, "Bearer x")
    assert L["rutas"][0]["veces"] == 2 and L["rutas"][0]["mejor"]["seg"] == 735 and L["sugeridas"] == ["r1"], L
    main.renombra_ruta("r1", {"nombre": "Vuelta al Ebro"}, None, "Bearer x")
    assert "<name>Vuelta al Ebro</name>" in main.gpx_ruta("r1", None, "Bearer x").body.decode()
    A = main.una_actividad("fit-202611270800", None, "Bearer x")
    assert A["ruta"]["nombre"] == "Vuelta al Ebro" and A["segmentos"][0]["puesto"] == 1 and A["segmentos"][0]["aqui"]
    main.cambia_segmento(seg["id"], {"borrar": True}, None, "Bearer x")
    assert main.lista_segmentos(None, "Bearer x") == []
    print("rutas ok")


def test_guias():
    import guias, json, tempfile
    from datetime import date
    from pathlib import Path
    core = {"id": "core", "n": "Core", "tipo": "movilidad", "hab": "c", "pausa": 5, "adapta": True,
            "bloques": [{"ej": "Plancha", "seg": 40}, {"ej": "Dead bug", "seg": 40}]}
    s = clean({"habits": [{"id": "c", "n": "Core", "goal": 3}], "rutinas": [core]})
    assert s["rutinas"][0]["adapta"] is True and s["guias"] == {}
    # a medias: 1 paso y medio de 2 → 75 %; luego otra peor el mismo día no la pisa
    assert guias.apunta(s, "2026-11-10", "core", 60, 80, 1, 2) == 75
    assert guias.apunta(s, "2026-11-10", "core", 20, 80, 0, 2) == 75
    s = clean(s)
    assert s["guias"]["2026-11-10"]["core"]["hecho"] == 60
    # el lunes 23: la semana del 16 sin datos pero hubo antes → «no la hiciste», sin cambios
    assert guias.adapta(s, date(2026, 11, 10)) == []            # semana del 9: sin datos de antes del 9 → nada aún
    c = guias.adapta(s, date(2026, 11, 17))                     # semana del 9 al 15: un 75 % → igual
    assert "75 %" in c[0] and [b["seg"] for b in s["rutinas"][0]["bloques"]] == [40, 40], c
    s["guias"]["2026-11-18"] = {"core": {"hecho": 80, "total": 80, "pasos": 2, "de": 2}}
    s["guias"]["2026-11-20"] = {"core": {"hecho": 80, "total": 80, "pasos": 2, "de": 2}}
    c = guias.adapta(s, date(2026, 11, 23))
    r = s["rutinas"][0]
    assert [b["seg"] for b in r["bloques"]] == [45, 45] and r["ajuste"]["pct"] == 100 and "+5 s" in c[0], c
    assert guias.adapta(s, date(2026, 11, 25)) == []             # una vez por semana
    s["guias"]["2026-11-24"] = {"core": {"hecho": 45, "total": 90, "pasos": 1, "de": 2}}
    guias.adapta(s, date(2026, 11, 30))
    assert [b["seg"] for b in r["bloques"]] == [25, 25] and r["ajuste"]["pct"] == 50, r   # 45 × 60 % ≈ 25
    assert clean(s)["rutinas"][0]["ajuste"]["texto"].startswith("La semana pasada hiciste de media un 50 %")
    # por la API
    main.PASS, main.SECRET = "x", b"s"
    d = Path(tempfile.mkdtemp())
    main.DB = d / "data.json"
    main.DB.write_text(json.dumps(clean({"habits": [{"id": "c", "n": "Core", "goal": 3}], "rutinas": [core]})))
    out = main.apunta_guia({"dia": "2026-11-21", "rutina": "core", "hecho": 50, "total": 80, "pasos": 1, "de": 2}, None, "Bearer x")
    assert out["pct"] == 62 and out["guia"]["pasos"] == 1, out
    try:
        main.apunta_guia({"dia": "2026-11-21", "rutina": "nada", "hecho": 1, "total": 2}, None, "Bearer x")
        assert False
    except main.HTTPException:
        pass
    print("guias ok")


def test_comunidad():
    import comunidad as c
    assert c.nombre_tema("NVIDIA Corporation") == "NVIDIA" and c.nombre_tema("Apple Inc.") == "Apple"
    assert c.nombre_tema("Vanguard FTSE All-World UCITS ETF USD Accumulation") == "Vanguard FTSE All-World"
    gordo = {"source": "reddit", "title": "Jensen Huang resigns as Nvidia CEO", "url": "https://www.reddit.com/r/stocks/comments/1/x/",
             "engagement": {"score": 1161, "num_comments": 294}, "published_at": "2026-11-12"}
    hn = {"source": "hackernews", "title": "SEC's Nvidia probe <accounting>", "url": "https://example.com/sec",
          "engagement": {"points": 298, "comments": 162}, "published_at": "2026-11-20"}
    flojo = {**gordo, "url": "https://www.reddit.com/r/stocks/comments/2/y/", "engagement": {"score": 40, "num_comments": 12}}
    otro = {**gordo, "url": "https://www.reddit.com/r/stocks/comments/3/z/", "title": "Intel plunges 16%"}
    assert c.fuerte(gordo) and c.fuerte(hn) and not c.fuerte(flojo)
    assert c.habla_de(gordo, "NVIDIA") and not c.habla_de(otro, "NVIDIA")
    d = {"results": [flojo, otro, gordo, hn]}
    assert [x["url"] for x in c.nuevos(d, "NVIDIA", {})] == [gordo["url"], hn["url"]]   # lo de más repercusión primero
    assert c.nuevos(d, "NVIDIA", {hn["url"]: "2026-11-20", gordo["url"]: "2026-11-12"}) == []   # ya avisado
    m = c.mensaje("NVIDIA", [gordo, hn])
    assert "r/stocks · 1.161 votos, 294 comentarios (12/11)" in m and "&lt;accounting&gt;" in m and "Hacker News · 298 puntos" in m
    assert c.recorta("a\nFree fixes:\n  - YouTube: video transcripts...\nb\n\n\n\nc") == "a\nb\n\nc"
    assert c.recorta("x" * 50 + "\n" + "y" * 50, tope=60).endswith("(… cortado)")
    pm = "### 1. US recession (score 45)\n## Polymarket Markets\n\n- 📊 Polymarket · US recession by end of 2026: 3.0% (down 4 pts this month) — https://polymarket.com/x\n✅ All agents reported back!\n└─ 📊 Polymarket: 5 markets"
    assert c.solo_polymarket(pm).splitlines()[0] == "- 📊 Polymarket · US recession by end of 2026: 3.0% (down 4 pts this month) — https://polymarket.com/x"
    assert c.solo_polymarket("nada") == "(no hay mercados de Polymarket sobre esto)"
    print("comunidad ok")


def test_intentos():
    import intentos as i
    i._fallos.clear()
    assert i.quien("192.168.1.50", {"cf-connecting-ip": "8.8.8.8"}) == "192.168.1.50"     # desde la wifi no se cree
    assert i.quien("127.0.0.1", {"cf-connecting-ip": "81.0.0.1"}) == "81.0.0.1"           # desde el túnel, sí
    assert i.quien("172.18.0.5", {}) == "172.18.0.5"
    assert i.cuenta("/api/login", False, 401) and i.cuenta("/api/state", True, 401)
    assert not i.cuenta("/api/state", False, 401) and not i.cuenta("/api/login", False, 200)
    t0 = 1_000_000.0
    for n in range(9):
        i.fallo("1.2.3.4", t0 + n)
    assert not i.bloqueada("1.2.3.4", t0 + 10)
    i.fallo("1.2.3.4", t0 + 10)
    assert i.bloqueada("1.2.3.4", t0 + 11) and not i.bloqueada("5.6.7.8", t0 + 11)
    assert not i.bloqueada("1.2.3.4", t0 + 10 + i.VENTANA + 1)                              # a los 15 min, libre
    i._fallos.clear()
    print("intentos ok")


def test_cache_vault():
    """Tachar desde el móvil (Remotely Save puede conservar la fecha; [ ]→[x] no cambia el tamaño) se tiene que ver."""
    import os, tempfile, time, vault
    from pathlib import Path
    notas, ruta = vault.notas, vault.ruta
    try:
        f = Path(tempfile.mkdtemp()) / "Nota.md"
        f.write_text("- [ ] comprar pies de gato\n")
        vault.notas, vault.ruta = (lambda: iter([f])), (lambda p: p.name)
        assert [t["hecha"] for t in vault.todas()] == [False]
        time.sleep(0.05)
        st = f.stat()
        f.write_text("- [x] comprar pies de gato\n")
        os.utime(f, ns=(st.st_atime_ns, st.st_mtime_ns))
        assert (f.stat().st_mtime_ns, f.stat().st_size) == (st.st_mtime_ns, st.st_size)
        assert [t["hecha"] for t in vault.todas()] == [True]
    finally:
        vault.notas, vault.ruta = notas, ruta
        vault._cache_todas["huella"] = None
    print("caché del vault ok")


def test_observa():
    import tempfile, time, metricas, observa
    from pathlib import Path
    db = Path(tempfile.mkdtemp()) / "observa.db"
    metricas.DB, observa.DB = db, db
    observa.ESTADO = db.with_name("estado.json")
    assert metricas.grupo("/api/inversiones/precios") == "/api/inversiones" and metricas.grupo("/carrera.html") == "páginas"
    assert metricas.grupo("/calma.css") == "estáticos" and metricas.grupo("/api/state") == "/api/state"
    for ms, codigo in ((20, 200), (40, 200), (1500, 200), (30, 500), (5, 401)):
        metricas.apunta("/api/state", codigo, ms)
    metricas.vuelca("todo")
    metricas.apunta("/api/state", 200, 10)
    metricas.vuelca("todo")                                       # el mismo minuto se suma, no se pisa
    c = observa.conecta()
    c.execute("INSERT INTO muestra VALUES (?,?,?)", (int(time.time()), "pi:temperatura", 61.5))
    c.execute("INSERT INTO evento VALUES (?,?,?,?)", (int(time.time()), "reinicio", "todo-bot", "se ha reiniciado 1 vez/veces"))
    c.commit(); c.close()
    p = observa.panel(1)
    a = p["ahora"]
    assert a["peticiones_24h"] == 6 and a["fallos_5xx_24h"] == 1 and a["temperatura"] == 61.5, a
    r = next(x for x in p["rutas"] if x["grupo"] == "/api/state")
    assert r["n"] == 6 and r["e5"] == 1 and r["max"] == 1500 and r["ms"] == round(1605 / 6)
    assert p["eventos"][0]["quien"] == "todo-bot" and a["eventos_24h"] == 1
    assert observa._caido({"ActiveState": "failed"}) and observa._caido({"ActiveState": "inactive", "Restart": "always"})
    assert not observa._caido({"ActiveState": "inactive", "Restart": "no"})   # los de una vez al arrancar
    assert observa.PINTA_ERROR.search("Traceback (most recent call last):") and observa.PINTA_ERROR.search("No he podido con la foto")
    assert not observa.PINTA_ERROR.search("Apuntado: 12 € en Mercadona")
    print("observa ok")


def test_cobro_y_anio():
    import cobro, anio
    from datetime import date
    g = {"ajustes": {"dia_cobro": 28, "ingreso": 1600, "inversion": 100},
         "ingresos": [{"dia": "2026-11-10", "importe": 1500, "tipo": "extra"}, {"dia": "2026-11-11", "importe": 900, "tipo": "devuelve"}]}
    assert cobro.toca(g, date(2026, 11, 28))[0] and not cobro.toca(g, date(2026, 11, 27))[0]
    assert cobro.toca(g, date(2026, 11, 10))[0] and not cobro.toca(g, date(2026, 11, 11))[0]   # un reembolso no es el sueldo
    assert cobro.dia_de_cobro({"dia_cobro": 31}, date(2027, 2, 10)) == date(2027, 2, 28)
    m = [{"dia": "2026-10-27", "euros": 5}, {"dia": "2026-10-28", "euros": 1}, {"dia": "2026-11-27", "euros": 2}]
    assert cobro.multas_del_ciclo(m, date(2026, 11, 28), g["ajustes"]) == 3
    assert anio._racha_max(["2026-01-01", "2026-01-02", "2026-01-04", "2026-01-05", "2026-01-06"], 1) == 3
    assert anio._racha_max(["2026-01-01", "2026-01-08", "2026-01-14"], 7) == 3
    s = clean({"habits": [{"id": "a", "n": "Agua", "c": "#000", "goal": 7}], "log": {"2026-03-01": ["a"], "2026-03-02": ["a"]},
               "peso": {"2026-03-01": 80, "2026-03-09": 79.2}})
    d = anio.calcula(s, {"gastos": [{"dia": "2026-03-01", "importe": 10, "cat": "super", "comercio": "MERCADONA X"}]}, {}, {}, None,
                     2026, hoy=date(2026, 12, 31))
    assert d["habitos"]["marcas"] == 2 and d["cuerpo"]["peso"]["cambio"] == -0.8 and d["dinero"]["comercio_favorito"] == ("Mercadona", 1)
    assert "Tu 2026" in anio.texto(d, {"titular": "Bien", "frases": ["a", "b", "c"]})
    print("cobro y año ok")


def test_multas():
    """Cada falta multa `fallo`; romper una racha de `racha_min` o más, `racha` además; el comodín salva; «aportar» no multa."""
    H = [{"id": "w", "n": "Agua", "goal": 7}, {"id": "aportar", "n": "Aportar", "goal": 1, "cada": 5}]
    s = clean({"habits": H, "comodines": {"al_mes": 0}, "log": {f"2026-11-0{i}": ["w"] for i in range(1, 5)}})
    conf = {"activo": True, "fallo": 1, "racha": 5, "racha_min": 3, "desde": "2026-11-01"}
    m = main.multas(s, conf, "2026-11-08")
    # el 5 rompe la racha de 4 (1 + 5), el 6 y el 7 son faltas sueltas (1 cada una)
    assert [(x["dia"], x["euros"]) for x in m] == [("2026-11-05", 6), ("2026-11-06", 1), ("2026-11-07", 1)], m
    assert m[0]["motivo"] == "rompe una racha de 4 días" and all(x["id"] == "w" for x in m)
    assert main.multas(s, {**conf, "desde": "2026-11-07"}, "2026-11-08") == [m[2]]
    assert main.multas(s, {**conf, "activo": False}, "2026-11-08") == []
    con_comodin = clean({**s, "comodines": {"al_mes": 2}})
    assert [x["dia"] for x in main.multas(con_comodin, conf, "2026-11-08")][0] != "2026-11-05"
    # los aportes: «aportar» los días con compra, y fuera de los que ya no
    s["log"]["2026-10-01"] = ["aportar"]
    assert main.aportes_en_log(s, [{"fecha": "2026-11-02", "tipo": "compra"}, {"fecha": "2026-11-03", "tipo": "venta"}])
    assert "aportar" in s["log"]["2026-11-02"] and "w" in s["log"]["2026-11-02"] and "aportar" not in s["log"].get("2026-10-01", [])
    assert not main.aportes_en_log(s, [{"fecha": "2026-11-02", "tipo": "compra"}])
    # exento hasta un día (incluido) y una multa perdonada
    assert [x["dia"] for x in main.multas(s, {**conf, "exentos": {"w": "2026-11-06"}}, "2026-11-08")] == ["2026-11-07"]
    assert [x["dia"] for x in main.multas(s, {**conf, "perdonadas": ["2026-11-06|w"]}, "2026-11-08")] == ["2026-11-05", "2026-11-07"]
    import inversiones
    limpio = inversiones._multas({**conf, "exentos": {"w": "2027-01-01", "x": "mal"}, "perdonadas": ["2026-11-06|w", "basura"]})
    assert limpio["exentos"] == {"w": "2027-01-01"} and limpio["perdonadas"] == ["2026-11-06|w"]


def test_descansos_api():
    import tempfile
    from pathlib import Path
    from fastapi import Response
    main.PASS, main.SECRET = "x", b"s"
    main.DB = Path(tempfile.mkdtemp()) / "data.json"
    hoy = date.today().isoformat()
    main.put_state({"habits": [{"id": "a", "n": "Leer"}]}, Response(), None, "Bearer x", None)
    # descanso de hoy: se pone y se quita, idempotente (puede llegar dos veces desde la cola)
    for _ in range(2):
        r = main.post_descanso({"id": "a"}, None, "Bearer x")
    assert r["descansos"] == ["a"] and r["habitos"][0]["libre"] == "descanso", r
    assert main.post_descanso({"id": "a", "quita": True}, None, "Bearer x")["descansos"] == []
    try:
        main.post_descanso({"id": "zz"}, None, "Bearer x")
        assert False
    except main.HTTPException as e:
        assert e.status_code == 404
    # comodines: cuántos al mes, gastar hoy (no más de los que quedan) y devolverlo
    assert main.post_comodin({"al_mes": 1}, None, "Bearer x")["comodines"]["quedan"] == 1
    c = main.post_comodin({}, None, "Bearer x")["comodines"]
    assert c["hoy"] and c["quedan"] == 0, c
    assert main.post_comodin({}, None, "Bearer x")["comodines"]["quedan"] == 0   # repetido: no gasta otro
    try:
        main.post_comodin({"dia": "2026-01-01"}, None, "Bearer x")
        assert False
    except main.HTTPException as e:
        assert e.status_code in (400, 409)
    assert main.post_comodin({"quita": True}, None, "Bearer x")["comodines"]["quedan"] == 1
    # vacaciones: crear, cambiar (mismo id) y borrar
    v = main.post_vacaciones({"desde": hoy, "hasta": hoy, "motivo": "enfermedad"}, None, "Bearer x")["vacaciones"]
    assert len(v) == 1 and v[0]["motivo"] == "enfermedad", v
    v2 = main.post_vacaciones({**v[0], "habitos": ["a"]}, None, "Bearer x")["vacaciones"]
    assert len(v2) == 1 and v2[0]["habitos"] == ["a"], v2
    try:
        main.post_vacaciones({"desde": hoy}, None, "Bearer x")
        assert False
    except main.HTTPException as e:
        assert e.status_code == 400
    # un PUT de un cliente que no conoce los descansos no los borra
    main.post_descanso({}, None, "Bearer x")
    s = main.put_state({"habits": [{"id": "a", "n": "Leer"}]}, Response(), None, "Bearer x", None)
    assert s["descansos"] == {hoy: ["*"]} and len(s["vacaciones"]) == 1, s
    assert main.post_vacaciones({"id": v[0]["id"], "quita": True}, None, "Bearer x")["vacaciones"] == []


def test_movimiento():
    """movimiento.js (GSAP) y tom.js: el orden de Hoy, el cuentakilómetros, el cielo, la planta y las cifras, con node."""
    import shutil
    import subprocess
    from pathlib import Path
    st = Path(__file__).parent / "static"
    for f in ("gsap-3.13.0.min.js", "MorphSVGPlugin-3.13.0.min.js", "Flip-3.13.0.min.js"):
        assert (st / f).stat().st_size > 10000, f
    for pag in st.glob("*.html"):
        html = pag.read_text("utf-8")
        # GSAP siempre con defer (si no llega, la página va igual) y la transición, solo donde se pide
        for linea in html.splitlines():
            if "3.13.0.min.js" in linea:
                assert "<script defer " in linea, (pag.name, linea)
        assert ("data-vt" in html) == ("@view-transition" in html), pag.name
    if not shutil.which("node"):
        print("(sin node: movimiento.js sin probar)")
        return
    js = """
    const m = require(process.argv[1]), ok = (c, x) => { if (!c) { console.error(JSON.stringify(x)); process.exit(1); } };
    const hs = [{id: "a", plan: true, hecho: true, orden: 0}, {id: "b", plan: true, hecho: false, orden: 1},
                {id: "c", plan: false, hecho: true, orden: 2}, {id: "d", plan: false, hecho: false, orden: 3},
                {id: "e", plan: true, hecho: false, orden: 4}];
    // planificado sin hacer arriba (en su orden), luego lo hecho, y lo que no toca al final
    const o = m.ordena(hs).map(h => h.id).join("");
    ok(o === "beadc", o);
    // desmarcar devuelve cada uno a su sitio: sin orden del servidor, el de la lista
    ok(m.ordena([{id: "x", plan: true, hecho: false}, {id: "y", plan: true, hecho: false}]).map(h => h.id).join("") === "xy", "sin orden");
    ok(JSON.stringify(m.digitos("9", "10")) === JSON.stringify([[" ", "1"], ["9", "0"]]), m.digitos("9", "10"));
    ok(JSON.stringify(m.digitos("10", "9")) === JSON.stringify([["1", " "], ["0", "9"]]), m.digitos("10", "9"));
    ok(JSON.stringify(m.digitos("07", "08")) === JSON.stringify([["0", "0"], ["7", "8"]]), m.digitos("07", "08"));
    // el cielo: en una parada, su color; entre dos, a medio camino; y medianoche igual a las 24
    ok(JSON.stringify(m.colores(12)[0]) === JSON.stringify([0x5D, 0x9B, 0xD3]), m.colores(12));
    ok(JSON.stringify(m.colores(0)) === JSON.stringify(m.colores(24)), "medianoche");
    const medio = m.colores(9.75)[0];
    ok(medio[0] === Math.round((0x7F + 0x5D) / 2), medio);
    ok(m.colores(23.9).flat().every(v => v >= 0 && v <= 255), m.colores(23.9));
    """
    r = subprocess.run(["node", "-e", js, str(st / "movimiento.js")], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    # tom.js: la planta de la racha, las cifras que se descifran, la inclinación del navegador y los patrones
    js = """
    const t = require(process.argv[1]), ok = (c, x) => { if (!c) { console.error(JSON.stringify(x)); process.exit(1); } };
    const h = (racha, rota = 0, hecho = false) => ({n: "x", racha, rota, hecho});
    ok(JSON.stringify(t.planta([])) === JSON.stringify({etapa: 0, mustia: false, de: null}), t.planta([]));
    ok(t.planta([h(3), h(12)]).etapa === 7 && !t.planta([h(3), h(12)]).mustia, "crece hasta 7");
    // ayer se rompió una de 5 y la mejor viva es de 2: mustia, del tamaño de la perdida
    let p = t.planta([h(0, 5), h(2)]);
    ok(p.mustia && p.etapa === 5, p);
    // hecha hoy otra vez (racha 1): vuelve a crecer desde abajo; y una rota de 1 día no cuenta
    p = t.planta([h(1, 5, true), h(2)]);
    ok(!p.mustia && p.etapa === 2, p);
    ok(!t.planta([h(0, 1)]).mustia, "rota de un día");
    ok(!t.planta([h(0, 4), h(6)]).mustia, "la viva es más larga");
    // solo cambian los dígitos que faltan por fijar; el resto (y el largo) se queda
    const r = t.revuelve("7 h 12", 2, () => .5);
    ok(r === "7 h 55" && r.length === 6, r);
    ok(t.revuelve("8.432", 5) === "8.432" && t.revuelve("8.432", 0, () => 0) === "0.000", "8.432");
    ok(JSON.stringify(t.deOrientacion(0, 0)) === JSON.stringify({x: 0, y: 0}), t.deOrientacion(0, 0));
    ok(t.deOrientacion(90, 0).y === 1 && t.deOrientacion(-120, 200).y >= -1 && t.deOrientacion(0, 90).x === 1, "orientación");
    for (const k of ["marcar", "desmarcar", "serie", "record", "descanso", "error", "dia"]) ok(t.PATRONES[k] && t.SUENA[k] !== undefined, k);
    """
    r = subprocess.run(["node", "-e", js, str(st / "tom.js")], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr


def test_escalada():
    import asyncio
    import json
    import tempfile
    from pathlib import Path
    main.PASS, main.SECRET = "x", b"s"
    main.ESCALADA = Path(tempfile.mkdtemp())

    class Pide:   # lo justo de una Request: cabeceras y el cuerpo por trozos
        def __init__(self, b, tipo="application/json"): self.b, self.headers = b, {"content-type": tipo}
        async def stream(self):
            for i in range(0, len(self.b), 1000):
                yield self.b[i:i + 1000]

    def falla(f, codigo):
        try:
            f()
            assert False, "tenía que fallar"
        except main.HTTPException as e:
            assert e.status_code == codigo, (e.status_code, e.detail)

    punto = [0.5, 0.25, 0.9]
    previa = {"fps": 5, "ancho": 1080, "alto": 1920, "meta": {"color": "Blue", "nombre": "  El  techo ", "quien": "Yago"},
              "fotogramas": [[0, 0.5, 0.6, [punto] * 19], [0.2, None, None, [[0, 0, 0]] * 19]], "primero": "data:image/jpeg;base64,AAAA"}
    sube = lambda i, d: asyncio.run(main.sube_previa(i, Pide(json.dumps(d).encode()), None, "Bearer x"))
    assert "2 fotogramas" in sube("20261111-183000", previa)["texto"]
    guardada = json.loads(main.lee_previa("20261111-183000", None, "Bearer x").path.read_text())
    assert guardada["meta"] == {"color": "azul", "nombre": "El techo", "quien": "Yago", "resultado": "probando"}, guardada["meta"]
    assert guardada["fotogramas"][1][:3] == [0.2, None, None] and guardada["fotogramas"][0][3][0] == punto and guardada["primero"]
    # sin la forma de siempre, de más de 2 MB, sin intento o sin sesión: fuera
    falla(lambda: sube("20261111-183000", {**previa, "fotogramas": [[0, 0.5, 0.5, [punto] * 18]]}), 400)
    falla(lambda: sube("20261111-183000", {**previa, "fps": "rápido"}), 400)
    falla(lambda: asyncio.run(main.sube_previa("20261111-183000", Pide(b"[" * (3 * 2**20)), None, "Bearer x")), 413)
    falla(lambda: sube("../..", previa), 400)
    falla(lambda: asyncio.run(main.sube_previa("20261111-183000", Pide(b"{}"), None, "Bearer mala")), 401)
    falla(lambda: main.lee_previa("20261111-190000", None, "Bearer x"), 404)
    # en la lista: subiendo (solo la previa), analizando (ya está el vídeo en entrada/) y, ya en historial/, fuera
    lista = lambda: main.lista_escalada(None, "Bearer x")
    r = lista()
    assert r["colores"][0] == "amarillo" and len(r["colores"]) == 9 and r["quien"]
    assert [(x["intento"], x["estado"], x["previa"], x["color"]) for x in r["pendientes"]] == [("20261111-183000", "subiendo", True, "azul")]
    t = asyncio.run(main.sube_escalada(Pide(b"video" * 10, "video/quicktime"), "20261111-183000", 1, "Yago", "azul", "", "hecho", "", None, "Bearer x"))
    assert "Recibido" in t["texto"] and (main.ESCALADA / "entrada" / "20261111-183000" / "1.mov").exists()
    assert [(x["estado"], x["previa"], x["resultado"]) for x in lista()["pendientes"]] == [("analizando", True, "hecho")]
    (main.ESCALADA / "entrada" / "20261111-183000" / "error").write_text("sin escalador")
    assert lista()["pendientes"][0]["estado"] == "error" and lista()["pendientes"][0]["error"] == "sin escalador"
    h = main.ESCALADA / "historial" / "20261111-183000"
    h.mkdir(parents=True)
    (h / "intento.json").write_text(json.dumps({"quien": "Yago", "color": "azul", "nombre": "", "resultado": "hecho"}))
    r = lista()
    assert r["pendientes"] == [] and [x["intento"] for x in r["intentos"]] == ["20261111-183000"]
    assert main.lee_previa("20261111-183000", None, "Bearer x")   # la previa sigue ahí, por si se quiere


def test_inversiones():
    """FIFO como Hacienda, limpieza que tira lo roto, serie con la referencia y proyección. Sin red: precios a mano."""
    import tempfile
    from pathlib import Path
    import inversiones as inv
    d = Path(tempfile.mkdtemp())
    inv.DATOS, inv.PRECIOS, inv.REVIEWS, inv.VAULT_REVIEWS = d / "i.json", d / "p.json", d / "r", d / "v"
    datos = inv.guarda({"activos": [{"id": "A", "simbolo": "aaa.de", "tipo": "etf"}, {"id": "b", "simbolo": ""}],
                        "operaciones": [
                            {"id": "1", "fecha": "2026-01-05", "activo": "a", "tipo": "compra", "cantidad": "10", "precio": "10", "comision": 1},
                            {"id": "2", "fecha": "2026-02-02", "activo": "a", "tipo": "compra", "cantidad": 10, "precio": 20, "comision": 1},
                            {"id": "3", "fecha": "2026-03-02", "activo": "a", "tipo": "venta", "cantidad": 15, "precio": 30, "comision": 1},
                            {"id": "4", "fecha": "2026-03-03", "activo": "a", "tipo": "dividendo", "precio": 2},
                            {"id": "5", "fecha": "mal", "activo": "a", "tipo": "compra", "cantidad": 1, "precio": 1},
                            {"id": "6", "fecha": "2026-03-03", "activo": "zzz", "tipo": "compra", "cantidad": 1, "precio": 1},
                            {"id": "7", "fecha": "2026-03-03", "activo": "a", "tipo": "compra", "cantidad": 0, "precio": 1}]})
    assert [a["id"] for a in datos["activos"]] == ["a"] and datos["activos"][0]["simbolo"] == "AAA.DE"   # sin símbolo, fuera
    assert [o["id"] for o in datos["operaciones"]] == ["1", "2", "3", "4"]
    assert inv.limpia(datos) == datos   # idempotente
    precios = {"AAA.DE": {"dias": {"2026-01-05": 10, "2026-02-02": 20, "2026-03-02": 30, "2026-03-06": 40}, "ultimo": 40},
               "REF": {"dias": {"2026-01-05": 5, "2026-03-06": 10}}}
    p, = inv.posiciones(datos["operaciones"], datos["activos"], precios, date(2026, 3, 7))
    # FIFO: se venden los 10 a 10,1 y 5 de los de 20,1; quedan 5 a 20,1
    assert p["cantidad"] == 5 and p["coste"] == 100.5 and p["valor"] == 200 and p["latente"] == 99.5
    assert p["realizado"] == round(15 * 30 - 1 - (101 + 5 * 20.1), 2) and p["dividendos"] == 2 and p["comisiones"] == 3
    assert p["dia"] == round((40 / 40 - 1) * 100, 2) and p["peso"] == 100
    # planes de ahorro: el día que toca (fin de semana → lunes), con el precio de ese día, una vez por mes
    assert inv.dia_plan(2026, 3, 7) == date(2026, 3, 9) and inv.dia_plan(2026, 3, 2) == date(2026, 3, 2)
    pl = inv.limpia({**datos, "planes": [{"id": "p", "activo": "a", "importe": 51, "comision": 1, "dia": 2, "desde": "2026-01-01"},
                                          {"id": "q", "activo": "zzz", "importe": 5}, {"id": "r", "activo": "a", "importe": 0}]})
    assert [x["id"] for x in pl["planes"]] == ["p"] and inv.limpia(pl) == pl
    hechas = inv.ejecuta_planes(pl, precios, date(2026, 3, 7))
    assert [o["fecha"] for _, o in hechas] == ["2026-01-02", "2026-02-02", "2026-03-02"], hechas
    assert hechas[1][1]["cantidad"] == 2.5 and hechas[1][1]["id"] == "plan-p-2026-02" and pl["planes"][0]["hechos"] == ["2026-01", "2026-02", "2026-03"]
    assert hechas[0][1]["precio"] == 10   # el 2/1 no hay cotización: la siguiente de esa semana
    assert inv.ejecuta_planes(pl, precios, date(2026, 3, 7)) == []   # una vez
    pl["operaciones"] = [o for o in pl["operaciones"] if o["id"] != "plan-p-2026-02"]
    assert inv.ejecuta_planes(pl, precios, date(2026, 3, 7)) == []   # borrada a mano: no vuelve
    assert inv.proximo_plan(pl["planes"][0], date(2026, 3, 7)) == "2026-04-02"
    # alertas: avisan una vez y se rearman al volver un 2 %
    al = inv.limpia({**datos, "alertas": [{"id": "x", "activo": "a", "tipo": "bajo", "valor": 45}, {"id": "y", "activo": "a", "tipo": "cae", "valor": 3},
                                           {"id": "z", "activo": "*", "tipo": "bajo", "valor": 1}, {"id": "w", "activo": "*", "tipo": "cae", "valor": 3}]})
    assert [x["id"] for x in al["alertas"]] == ["x", "y", "w"]
    pr = {"AAA.DE": {"dias": {"2026-03-05": 50}, "ultimo": 44, "ayer": 50}}
    s = inv.revisa_alertas(al, pr, date(2026, 3, 6))
    assert [x["id"] for x, _ in s] == ["x", "y", "w"] and s[0][1] == "aaa.de está a 44,00 €: por debajo de 45,00 €" and s[1][1] == "aaa.de cae un 12,0 % hoy (44,00 €)" and al["alertas"][0]["armada"] is False, s
    assert inv.revisa_alertas(al, pr, date(2026, 3, 6)) == []
    pr["AAA.DE"].update(ultimo=46.5, ayer=46.5)
    assert inv.revisa_alertas(al, pr, date(2026, 3, 7)) == [] and al["alertas"][0]["armada"] is True
    assert inv.leccion_de("## 10. x\nhola\n## 11. Lección de la semana\n**Idea**\nTexto\n") == "**Idea**\nTexto"
    s = inv.serie_cartera(datos["operaciones"], datos["activos"], precios, "REF", date(2026, 3, 7))
    assert s[0] == {"dia": "2026-01-05", "valor": 100, "metido": 101, "referencia": 101}
    assert s[-1]["dia"] == "2026-03-07" and s[-1]["valor"] == 200 and s[-1]["metido"] == round(101 + 201 - 449, 2)
    pr = inv.proyeccion(1000, 100, 2, {"cero": 0})
    assert pr["cero"]["anios"] == [1000, 2200, 3400] and pr["aportado"]["anios"] == [1000, 2200, 3400]
    assert inv.review("../etc") is None and inv.reviews() == []
    inv.guarda_review("2026-03-08", "## 1. Resumen\nTodo bien")
    assert inv.reviews() == ["2026-03-08"] and "Todo bien" in inv.review("2026-03-08")
    assert (d / "v" / "Review inversiones 2026-03-08.md").exists()
    # impuestos: escala del ahorro, compensación y regla de los 2 meses
    assert inv.cuota_ahorro(6000) == 1140 and inv.cuota_ahorro(10000) == 1980 and inv.cuota_ahorro(-5) == 0
    assert inv.liquida(-1000, 400) == {"base": 300, "cuota": 57, "pendientes": 900}
    assert inv.liquida(3000, 100, 500)["base"] == 2600
    A = [{"id": "y", "nombre": "Y", "simbolo": "Y", "tipo": "accion"}]
    ops = [{"id": "1", "fecha": "2026-01-10", "activo": "y", "tipo": "compra", "cantidad": 10, "precio": 50},
           {"id": "2", "fecha": "2026-06-01", "activo": "y", "tipo": "venta", "cantidad": 5, "precio": 40},
           {"id": "3", "fecha": "2026-06-20", "activo": "y", "tipo": "compra", "cantidad": 1, "precio": 40}]
    dd = inv.limpia({"activos": A, "operaciones": ops})
    hoy = date(2026, 11, 18)
    pos = inv.posiciones(dd["operaciones"], dd["activos"], {"Y": {"ultimo": 50}}, hoy)
    f = inv.fiscal(dd, pos, hoy)
    assert f["ventas"][0]["resultado"] == -50 and f["ventas"][0]["diferida"] and f["ganancias"] == 0
    assert f["si_vendes"]["latente"] == -40   # quedan +10 € latentes; al venderlo todo vuelve la pérdida aplazada (-50)
    assert inv.limpia({"perfil": {"intereses": {"2026": "12,5", "x": 3, "2025": 0}}})["perfil"]["intereses"] == {"2026": 12.5}
    dc = inv.declaracion(dd, inv.fiscal(dd, pos, date(2027, 5, 1)), 300, date(2027, 5, 1))   # en mayo, la del año pasado con sus ventas
    assert dc["ejercicio"] == 2026 and dc["ventas"] and "pérdidas" in dc["obligado"] and "ya" in dc["estado"]
    assert inv.declaracion(dd, f, 300, hoy)["ventas"] is None   # en noviembre, la de este año


if __name__ == "__main__":
    test_movimiento()
    test_sueno()
    test_salud()
    test_frontal()
    test_clean()
    test_cookie()
    test_entreno()
    test_agenda()
    test_vault()
    test_carrera()
    test_portada()
    test_guarda()
    test_version()
    test_marca()
    test_quita()
    test_pesos()
    test_a_mano()
    test_documentos()
    test_pantalla()
    test_tom()
    test_semana()
    test_rachas()
    test_descansos_api()
    test_escalada()
    test_aparato()
    test_inversiones()
    test_cubierto()
    test_explorar()
    test_uso()
    test_cobro_y_anio()
    test_fit()
    test_multas()
    test_carrera_calendario()
    test_rutas()
    test_guias()
    test_comunidad()
    test_intentos()
    test_cache_vault()
    test_observa()
    print("ok")
