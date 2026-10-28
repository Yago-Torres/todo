import time
from datetime import date

import main
from main import EMPTY, clean, firma, vale


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
    # de las diarias del curro solo cuenta la última; la bucket list del hub no es una tarea
    assert [x["t"] for x in ts] == ["llamar al dentista", "rotar token", "llamar", "arrastrada", "cosa del curro",
                                    "plantilla"], [x["t"] for x in ts]
    assert ts[1]["due"] == "2026-11-02" and (ts[2]["due"], ts[2]["hora"]) == ("2026-11-05", "10:00") and ts[4]["fija"]
    nuevo = vault.marca(ts[0]["id"])
    assert nuevo and "- [x] llamar al dentista ⏰ 10:00 📅 2026-10-30 ✅" in (vault.VAULT / "Pendientes.md").read_text("utf-8")
    assert vault.marca(nuevo, False) == ts[0]["id"]          # deshacer devuelve el id de antes
    assert vault.marca(ts[4]["id"]) is None                  # Curro no se toca
    # editar: cambia texto, día y hora en su sitio; la prioridad del plugin Tasks se queda
    e = vault.edita(ts[1]["id"], " rotar  el token ", "2026-11-03", "09:30")
    assert (e["t"], e["due"], e["hora"]) == ("rotar el token", "2026-11-03", "09:30"), e
    assert "- [ ] rotar el token ⏫ ⏰ 09:30 📅 2026-11-03\n- [x] hecho" in (vault.VAULT / "Proyectos" / "Pi.md").read_text("utf-8")
    e = vault.edita(e["id"], "rotar el token", "", "09:30")          # sin día, la hora sola no vale
    assert (e["due"], e["hora"]) == ("", "") and e["id"] in [x["id"] for x in vault.tareas()]
    assert vault.edita(ts[4]["id"], "x") is None and vault.edita("noexiste", "x") is None
    # borrar quita la línea; deshacer la vuelve a poner en su sitio
    antes = (vault.VAULT / "Proyectos" / "Pi.md").read_text("utf-8")
    b = vault.borra(e["id"])
    assert b["i"] == 3 and "rotar el token" not in (vault.VAULT / "Proyectos" / "Pi.md").read_text("utf-8"), b
    vault.restaura(b["ruta"], b["i"], b["linea"])
    assert (vault.VAULT / "Proyectos" / "Pi.md").read_text("utf-8") == antes
    assert vault.borra(ts[4]["id"]) is None   # Curro no se toca
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
    l = vault.nueva_lectura({"url": "https://ejemplo.com/a#b", "titulo": "Qué/es: RAG?", "resumen": 'dice "hola"',
                             "tags": ["IA generativa"], "minutos": 6, "enlaces": ["Raspberry Pi"]})
    assert l["ruta"] == "Recursos/Leer luego/Qué es RAG.md", l
    [x] = vault.lecturas()
    assert (x["url"], x["minutos"], x["resumen"]) == ("https://ejemplo.com/a#b", 6, "dice 'hola'"), x
    assert [r["titulo"] for r in vault.revisar(date(2030, 1, 1))] == ["Qué es RAG"]
    vault.leido(l["ruta"])
    assert vault.lecturas() == [] and vault.revisar(date(2030, 1, 1)) == []
    assert vault.plano("![[a.jpg]] Hola **[[Raspberry Pi|la Pi]]** y [web](https://x.y) `code`\n- [ ] tarea") \
        == "Hola la Pi y web code tarea"
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
    import tempfile
    from pathlib import Path
    f = Path(tempfile.mkdtemp()) / "index.html"
    f.write_text('<header class="top"><h1>Comida</h1><nav class="pestanas c-seg"></nav></header>'
                 '<script>api("/api/estado"); api("/api/login"); fetch("/api/logout")</script>')
    g = f.with_name("gastos.html")
    g.write_text('<header class="top"><h1>Gastos</h1><div class="ciclo"></div></header><script>api("/api/estado")</script>')
    main.OTRAS = {"comida": ("http://x", f, "COMIDA_PASS", ""), "gastos": ("http://x", g, "GASTOS_PASS", ""),
                  "gastos-aitana": ("http://y", g, "GASTOS_AITANA_PASS", "Aitana")}
    html = main.frontal("comida").body.decode()
    # la API va al reenvío; entrar y salir, al login de todo
    assert '"/api/comida/estado"' in html and '"/api/login"' in html and '"/api/logout"' in html, html
    # el menú de todo a la derecha, sin la página en la que estás, y antes de las pestañas de comida
    menu = html[html.index('<nav class="menu-todo">'):html.index('<nav class="pestanas')]
    assert [h for h in ("/", "/pendientes.html", "/entreno.html", "/gastos.html") if f'href="{h}"' in menu] == \
        ["/", "/pendientes.html", "/entreno.html", "/gastos.html"] and "/comida.html" not in menu, menu
    assert "Aitana" not in html, html
    # los gastos de Aitana: su nombre, su reenvío y el selector Yago / Aitana marcando dónde estás
    html = main.frontal("gastos-aitana").body.decode()
    assert html.startswith('<header class="top"><h1>Gastos · Aitana</h1>') and '"/api/gastos-aitana/estado"' in html, html
    assert 'href="/gastos-aitana.html" style="text-decoration:none;margin-left:8px" aria-current="true"' in html, html
    assert html.index('<div class="ciclo">') < html.index('<nav class="menu-todo">') < html.index("</header>"), html
    assert 'href="/gastos.html">Gastos' not in html and 'href="/comida.html"' in html, html
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
    # hoy sin hacer no rompe la racha; hecho hoy, cuenta
    assert main.racha(log, "a", "2026-10-26") == 2 and main.racha(log, "b", "2026-10-26") == 2
    assert main.racha(log, "c", "2026-10-26") == 0
    assert main.trozo(lambda: 1 / 0) == {"error": "division by zero"}
    s = clean({"habits": [{"id": "a", "n": "Correr"}, {"id": "b", "n": "Agua"}, {"id": "c", "n": "Leer"}],
               "log": log, "plan": {"2026-10-26": ["a", "b"]}, "peso": {"2026-10-20": 81, "2026-10-25": 80}})
    h = main.hoy_habitos(s, "2026-10-26")
    # lo planificado y sin hacer arriba, luego lo planificado hecho, luego el resto
    assert [x["id"] for x in h["habitos"]] == ["a", "b", "c"], h
    assert h["peso"] == {"dia": "2026-10-25", "kg": 80, "media": 80.5,
                         "serie": [81, None, None, None, None, 80, None]}, h["peso"]   # 20 al 26, viejo -> nuevo
    # el año en puntos: un nivel por día desde el 1 de enero, según la parte de los hábitos hecha
    anio = main.hoy_anio(s, "2026-10-26")
    assert len(anio) == 299 and anio[-3:] == [1, 2, 1] and anio.count(3) == 0 and anio[0] == 0, anio[-3:]
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
    r = main.registra_salud({"fases": texto, "sueno": 999}, None, "Bearer x")
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
    # acostarse dos horas más tarde de lo normal se paga entero en la hora
    assert main.nota([["core", "2026-10-29T03:00", 480]], [main.desde_mediodia("2026-10-28T01:00")])["hora"] == 0


if __name__ == "__main__":
    test_sueno()
    test_salud()
    test_frontal()
    test_clean()
    test_cookie()
    test_entreno()
    test_vault()
    test_carrera()
    test_portada()
    test_guarda()
    test_version()
    print("ok")
