import os
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
    # lo del curro se tacha (y se destacha), pero no se edita ni se borra
    n = vault.marca(ts[4]["id"])
    assert "- [x] cosa del curro ✅" in (vault.VAULT / "Curro" / "Jira.md").read_text("utf-8")
    assert vault.marca(n, False) == ts[4]["id"]
    # una viñeta sin casilla de la última daily: al tacharla se le pone
    diaria = vault.VAULT / "Curro" / "Daily notes" / "2026-12-01 Martes.md"
    diaria.write_text("## TODO's today\n\n- revisar PR\n- [ ] otra\n\nun apunte\n", "utf-8")
    t = next(x for x in vault.tareas() if x["t"] == "revisar PR")
    n = vault.marca(t["id"])
    assert diaria.read_text("utf-8").startswith("## TODO's today\n\n- [x] revisar PR ✅") and "un apunte" in diaria.read_text("utf-8")
    assert "revisar PR" not in [x["t"] for x in vault.tareas()]
    assert vault.marca(n, False) and "revisar PR" in [x["t"] for x in vault.tareas()]
    diaria.unlink()
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
    # la copia de Aitana no tiene la clave de los otros gastos: ni botones ni forma de saltar a ellos
    os.environ.pop("GASTOS_AITANA_PASS", None)
    assert 'href="/gastos-aitana.html" style' not in main.frontal("gastos").body.decode()
    os.environ["GASTOS_AITANA_PASS"] = "x"
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
    # transición entre páginas también en comida y gastos: la regla va en el <head>, antes de pintar nada
    f.write_text('<html lang="es"><title>Comida</title><header class="top"><h1>Comida</h1><nav class="pestanas c-seg"></nav></header>')
    html = main.frontal("comida").body.decode()
    assert html.startswith('<html lang="es" data-vt>') and html.index("@view-transition") < html.index("<header"), html
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
    # la racha que se rompió ayer (la planta de Hoy se mustia con ella): sus días; si ayer se hizo, ninguna
    assert main.rota(log, "a", "2026-10-26") == 0 and main.rota(log, "a", "2026-10-27") == 2
    assert main.rota(log, "b", "2026-10-27") == 0 and main.rota(log, "a", "2026-10-28") == 0 and main.rota({}, "a", "2026-10-27") == 0
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
    a = main.limpia_ajustes({"nombre": "  Ana   Prueba ", "modulos": {"entreno": {"activo": False}, "salud": {"barra": False}, "comida": {"activo": True}},
                             "mascota": {"ancho": 999, "alto": 60, "color": "red\"><script>", "extra": "x", "rubor": True}, "otra": 1})
    assert a["nombre"] == "Ana Prueba" and a["modulos"]["entreno"] == {"activo": False, "barra": True}, a
    assert a["modulos"]["salud"] == {"activo": True, "barra": False} and a["modulos"]["comida"]["activo"] is bool(os.getenv("COMIDA_PASS")), a
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


if __name__ == "__main__":
    test_movimiento()
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
    test_marca()
    test_quita()
    test_pesos()
    test_documentos()
    test_pantalla()
    test_tom()
    test_escalada()
    print("ok")
