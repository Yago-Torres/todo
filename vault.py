"""Lo que todo lee y escribe en el vault de Obsidian: tareas, «leer luego» y notas recientes.

El vault es la fuente de la verdad y Obsidian lo sincroniza con Remotely Save, así que
aquí solo se cambian líneas sueltas y se escribe de forma atómica (tmp + replace).
Las tareas van en el formato del plugin Tasks: `- [ ] texto ⏰ 10:00 📅 2026-10-30`.
"""
import hashlib
import os
import re
import unicodedata
import urllib.parse
from datetime import date, datetime, timedelta
from pathlib import Path

VAULT = Path(os.getenv("VAULT", "/srv/obsidian/Yago_obsidian_vault"))
PENDIENTES = "Pendientes.md"          # donde caen las tareas sueltas (bot y web)
LEER = "Recursos/Leer luego"
RAPIDAS = "Notas rápidas.md"          # ideas sueltas: no son tareas (sin casilla), pueden llegar a serlo o no
FUERA = {"Archivo", "_plantillas", "templates", "_adjuntos", ".obsidian", ".trash", "Inbox"}
SOLO_LECTURA = ("Curro/",)            # lo escribe el portátil del trabajo: se tacha, pero no se edita ni se borra
# el hub lleva la bucket list ("Visit Japan"): son sueños, no pendientes
SIN_TAREAS = {"Main hub.md", "Tareas.md", "CLAUDE.md"}
# las notas diarias del curro copian las tareas abiertas al día siguiente: solo vale la última
DIARIAS = "Daily notes"

TAREA = re.compile(r"^(\s*[-*] \[)([ xX])(\] )(.+)$")
FECHA = re.compile("\\s*📅\ufe0f?\\s*(\\d{4}-\\d{2}-\\d{2})")
HORA = re.compile("\\s*⏰\ufe0f?\\s*(\\d{1,2}:\\d{2})")
HECHA = re.compile("\\s*✅\ufe0f?\\s*\\d{4}-\\d{2}-\\d{2}")
# prioridad (sola) y fechas de inicio/programada/creada del plugin Tasks: fuera del texto
OTROS = re.compile("\\s*(?:[🔺⏫🔼🔽⏬]\ufe0f?|[🛫⏳➕]\ufe0f?\\s*\\d{4}-\\d{2}-\\d{2})")
# plugin Reminder, el que usa en el curro: (@2026-10-30 10:00)
AVISO = re.compile(r"\s*\(@(\d{4}-\d{2}-\d{2})(?: (\d{1,2}:\d{2}))?\)")
HECHA_EL = re.compile("✅\ufe0f?\\s*(\\d{4}-\\d{2}-\\d{2})")
CAMPOS = (FECHA, HORA, HECHA, OTROS, AVISO)

# ---------- el board ----------
# Las etiquetas de Obsidian (#algo, con alguna letra) son los proyectos; las de Proyectos/X.md llevan X sin
# escribirla. Tres son del board: #activa y #bloqueada (el estado; «hecha» es la casilla de siempre) y #historia.
# Una historia es una tarea con subtareas sangradas debajo (o con #historia, aunque aún no tenga).
MARCA = re.compile(r"\s*(?:^|(?<=\s))#([\w/-]*[^\W\d][\w/-]*)")
ESTADOS = ("nueva", "activa", "bloqueada", "hecha")
RESERVADAS = {"activa", "bloqueada", "historia"}
# Cada 3 semanas, contando desde este lunes, la columna «Hecha» se vacía: lo de antes queda en historial()
CICLO0, CICLO = date(2026, 11, 16), 21


def escribe(p, texto):
    tmp = p.with_name(f".{p.name}.tmp")
    tmp.write_text(texto, "utf-8")
    tmp.replace(p)


def ruta(p):
    return p.relative_to(VAULT).as_posix()


def enlace(rel):
    """obsidian:// abre la nota en la app del iPhone o del ordenador."""
    q = urllib.parse.urlencode({"vault": VAULT.name, "file": rel.removesuffix(".md")}, quote_via=urllib.parse.quote)
    return f"obsidian://open?{q}"


def notas():
    # os.walk podando lo que no cuenta (Archivo, .obsidian…): rglob lo recorría entero en cada petición
    for raiz, dirs, archivos in os.walk(VAULT):
        dirs[:] = [d for d in dirs if d not in FUERA and not d.startswith(".")]
        for f in archivos:
            if f.endswith(".md") and not f.startswith("."):
                yield Path(raiz) / f


_TEXTOS = {}   # ruta -> ((mtime, tamaño), texto): solo se relee lo que ha cambiado (la bandeja leía 200 notas 3 veces)


def lee(p):
    st = p.stat()
    m = (st.st_mtime_ns, st.st_size)   # con el tamaño: ext4 no distingue dos escrituras en el mismo tic
    if (c := _TEXTOS.get(p)) and c[0] == m:
        return c[1]
    texto = p.read_text("utf-8", errors="ignore")
    _TEXTOS[p] = (m, texto)
    return texto


def cabecera(texto):
    """Frontmatter simple: `clave: valor` de una línea. Lo demás se ignora."""
    if not texto.startswith("---"):
        return {}, texto
    fin = texto.find("\n---", 3)
    if fin < 0:
        return {}, texto
    datos = {}
    for linea in texto[3:fin].splitlines():
        k, sep, v = linea.partition(":")
        if sep and k.strip() and not k.startswith(" "):
            datos[k.strip()] = re.split(r"\s+#", v)[0].strip().strip('"')
    return datos, texto[fin + 4:].lstrip("\n")


def tid(rel, linea):
    return hashlib.sha1(f"{rel}\n{linea.strip()}".encode()).hexdigest()[:12]


def parsea(linea):
    m = TAREA.match(linea)
    if not m:
        return None
    resto = m[4]
    due = (FECHA.search(resto) or [None, ""])[1]
    hora = (HORA.search(resto) or [None, ""])[1]
    if not due and (r := AVISO.search(resto)) and valida(r[1]):
        due, hora = r[1], r[2] or ""
    marcas = [x[1] for x in MARCA.finditer(resto)]
    bajas = {x.lower() for x in marcas}
    t = " ".join(MARCA.sub("", AVISO.sub("", OTROS.sub("", HECHA.sub("", HORA.sub("", FECHA.sub("", resto)))))).split())
    hecha = m[2] != " "
    return {"t": t, "due": due, "hora": hora.zfill(5) if hora else "", "hecha": hecha,
            "estado": "hecha" if hecha else "bloqueada" if "bloqueada" in bajas else "activa" if "activa" in bajas else "nueva",
            "tags": list(dict.fromkeys(x for x in marcas if x.lower() not in RESERVADAS)),
            "historia": "historia" in bajas, "hecha_el": (HECHA_EL.search(resto) or [None, ""])[1]}


def valida(dia):
    try:
        return bool(date.fromisoformat(dia))
    except ValueError:   # las plantillas traen cosas como 2026-09-00
        return False


def grupo(rel):
    if rel == PENDIENTES:
        return "Pendientes"
    return rel.split("/")[0] if "/" in rel else "Notas"


def etiqueta(x):
    """Lo que se puede escribir tras # en Obsidian (sin espacios ni puntos), o "" si no vale."""
    x = re.sub(r"[^\w/-]+", "-", str(x).strip().lstrip("#").removesuffix(".yagotg.dev")).strip("-")[:30]
    return x if re.search(r"[^\W\d]", x) else ""


def proyecto(rel):
    """Las de Proyectos/X.md son del proyecto X (todo.yagotg.dev → todo)."""
    return etiqueta(Path(rel).stem) if rel.startswith("Proyectos/") else ""


def sangria(linea):
    return len(linea.expandtabs(4)) - len(linea.expandtabs(4).lstrip())


def todas():
    """Todas las tareas del vault (sin Archivo/), abiertas y hechas, con un id estable por contenido, sus proyectos
    y su historia (`padre`: la tarea con menos sangría justo encima, de la que hereda los proyectos)."""
    ps = [p for p in notas() if p.name not in SIN_TAREAS]
    diarias = {}
    for p in ps:
        if p.parent.name == DIARIAS:
            diarias[p.parent] = max(diarias.get(p.parent, p), p, key=lambda x: x.name)
    out = []
    for p in ps:
        if p.parent.name == DIARIAS and diarias[p.parent] != p:
            continue
        rel, texto = ruta(p), lee(p)
        base = {"ruta": rel, "nota": p.stem, "grupo": grupo(rel), "fija": rel.startswith(SOLO_LECTURA), "abrir": enlace(rel)}
        if p.parent.name == DIARIAS and TITULO.search(texto):
            out += [{"estado": "nueva", "tags": [], "historia": False, "hecha_el": "", **t, **base,
                     "id": tid(rel, linea), "padre": ""} for linea, t in de_la_daily(texto)]
            continue
        pila, pro = [], proyecto(rel)
        for linea in texto.splitlines():
            t = parsea(linea)
            if not t:
                if linea.strip() and not linea[:1].isspace():
                    pila = []   # un título o un párrafo: lo de debajo ya no cuelga de la de arriba
                continue
            s = sangria(linea)
            while pila and pila[-1][0] >= s:
                pila.pop()
            padre = pila[-1][1] if pila else None
            x = {**t, **base, "id": tid(rel, linea), "padre": padre["id"] if padre else ""}
            x["tags"] = list(dict.fromkeys(([pro] if pro else []) + (padre["tags"] if padre else []) + t["tags"]))
            if padre:
                padre["historia"] = True
            pila.append((s, x))
            out.append(x)
    hijas = {}
    for x in out:
        if x["padre"]:
            h = hijas.setdefault(x["padre"], [0, 0])
            h[0] += x["hecha"]
            h[1] += 1
    for x in out:
        if x["historia"]:
            x["progreso"] = hijas.get(x["id"], [0, 0])   # [hechas, total] de sus subtareas, también las de otros ciclos
    return out


def una(id_):
    return next((t for t in todas() if t["id"] == id_), None)


def tareas():
    """Las abiertas de todo el vault (las nuevas, activas y bloqueadas del board): la web, el bot y los widgets."""
    out, vistas = [], set()
    for t in todas():
        if not t["hecha"] and t["t"] and (t["grupo"], t["t"]) not in vistas:
            vistas.add((t["grupo"], t["t"]))
            out.append(t)
    return sorted(out, key=lambda t: (t["due"] or "9999", t["hora"] or "99", t["grupo"], t["t"]))


def ciclo(hoy=None):
    """El ciclo de 3 semanas en que cae hoy: (primer día, último día)."""
    hoy = hoy or date.today()
    desde = CICLO0 + timedelta(days=(hoy - CICLO0).days // CICLO * CICLO)
    return desde, desde + timedelta(days=CICLO - 1)


def hechas(desde=None, hasta=None):
    """Las hechas con su ✅ entre esos días (incluidos), de la última a la primera."""
    d, h = desde.isoformat() if desde else "0000", hasta.isoformat() if hasta else "9999"
    return sorted((t for t in todas() if t["hecha"] and t["t"] and valida(t["hecha_el"]) and d <= t["hecha_el"] <= h),
                  key=lambda t: t["hecha_el"], reverse=True)


def historial(hoy=None):
    """Lo que ya salió de la columna «Hecha», por ciclos, el más reciente primero."""
    desde, _ = ciclo(hoy)
    grupos = {}
    for t in hechas(None, desde - timedelta(days=1)):
        a, b = ciclo(date.fromisoformat(t["hecha_el"]))
        grupos.setdefault(a, {"desde": a.isoformat(), "hasta": b.isoformat(), "tareas": []})["tareas"].append(t)
    return list(grupos.values())


def limpia_tags(tags, rel=""):
    """Las etiquetas que manda la web o Tom: válidas, sin las del board ni el proyecto que ya da la nota."""
    fuera = RESERVADAS | {proyecto(rel).lower()}
    return list(dict.fromkeys(e for x in list(tags or [])[:8] if (e := etiqueta(x)) and e.lower() not in fuera))


def pon_marcas(resto, quita, pon):
    """Quita las etiquetas `quita` (en minúsculas) y pone `pon` justo tras el texto, antes de los campos de Tasks
    (que los lee desde el final de la línea)."""
    resto = MARCA.sub(lambda m: "" if m[1].lower() in quita else m[0], resto)
    corte = min([r.start() for c in CAMPOS if (r := c.search(resto))] + [len(resto)])
    campos = resto[corte:].strip()
    return resto[:corte].rstrip() + "".join(f" #{x}" for x in pon) + (f" {campos}" if campos else "")


def cambia_estado(id_, estado):
    """Mueve la tarea en el board: «hecha» es la casilla (marca()); «activa» y «bloqueada», una etiqueta. Lo del
    curro solo se tacha. Devuelve la tarea como la da todas(), con su id nuevo."""
    if estado not in ESTADOS:
        raise ValueError("el estado es nueva, activa, bloqueada o hecha")
    t = una(id_)
    if not t:
        return None
    if t["fija"] and estado in ("activa", "bloqueada"):
        raise ValueError("lo del curro solo se puede tachar")
    if t["hecha"] != (estado == "hecha"):
        id_ = marca(id_, estado == "hecha")
    if not t["fija"]:
        pon = [estado] if estado in ("activa", "bloqueada") else []
        id_ = reescribe(id_, lambda resto: pon_marcas(resto, {"activa", "bloqueada"}, pon))
    return una(id_)


def reescribe(id_, fn):
    """Cambia lo que va tras la casilla de una tarea (fuera de Curro). Devuelve el id nuevo, o None."""
    for p in notas():
        rel = ruta(p)
        if rel.startswith(SOLO_LECTURA):
            continue
        lineas = p.read_text("utf-8").splitlines(keepends=True)
        for i, linea in enumerate(lineas):
            if (m := TAREA.match(linea.rstrip("\n"))) and tid(rel, linea) == id_:
                nueva = f"{m[1]}{m[2]}{m[3]}{fn(m[4])}"
                if nueva != linea.rstrip("\n"):
                    lineas[i] = nueva + ("\n" if linea.endswith("\n") else "")
                    escribe(p, "".join(lineas))
                return tid(rel, nueva)
    return None


# ---------- la daily del curro ----------
# Tres apartados: «Done today», «TODO's today» y «TODO's future». Las tareas son viñetas sueltas
# (sin casilla) y la lista acaba donde empieza un párrafo: lo de debajo son apuntes, no tareas.
TITULO = re.compile(r"^#+\s*todo", re.I | re.M)
VINETA = re.compile(r"^[-*] (?:\[([ xX])\] )?(.+)$")


def plano_tarea(s):
    """Para comparar una tarea con lo hecho: minúsculas, sin tildes ni signos."""
    s = unicodedata.normalize("NFD", s.lower()).encode("ascii", "ignore").decode()
    return " ".join(re.sub(r"[^a-z0-9]+", " ", s).split())


def de_la_daily(texto):
    """Lo pendiente de una daily: lo de «TODO's today» (para hoy) y «TODO's future» (sin fecha) que no
    esté en «Done today» ni marcado. Devuelve [(línea, tarea)] como parsea()."""
    seccion, hechas, pendientes = None, [], []
    for linea in texto.splitlines():
        s = linea.strip()
        if s.startswith("#"):
            nombre = plano_tarea(s)
            seccion = ("hecho" if nombre.startswith("done") else "hoy" if nombre.startswith("todo") and "today" in nombre
                       else "futuro" if nombre.startswith("todo") else None)
            continue
        if not seccion or not s:
            continue
        if linea[:1].isspace() and s[:1] in "-*":
            continue              # sangrada: un detalle de la de arriba, no otra tarea
        m = VINETA.match(linea)
        if not m:
            seccion = None        # un párrafo cierra la lista
            continue
        cuerpo = m[2].strip()
        if seccion == "hecho" or (m[1] or " ") != " ":
            hechas.append(plano_tarea(cuerpo))
        elif not cuerpo.startswith("!["):   # imágenes pegadas, no tareas
            pendientes.append((seccion, linea, cuerpo))
    hoy = date.today().isoformat()
    out = []
    for seccion, linea, cuerpo in pendientes:
        due, hora = "", ""
        if r := AVISO.search(cuerpo):
            if not valida(r[1]):
                continue          # la plantilla «Reminder (@2026-09-00 09:00)»
            due, hora = r[1], r[2] or ""
        t = AVISO.sub("", cuerpo).strip()
        p = plano_tarea(t)
        # hecha si está en «Done today» tal cual, o una contiene a la otra (y no es una palabra suelta)
        if not p or any(p == h or (min(len(p), len(h)) >= 12 and (p in h or h in p)) for h in hechas):
            continue
        out.append((linea, {"t": t, "due": due or (hoy if seccion == "hoy" else ""), "hora": hora.zfill(5) if hora else "",
                            "hecha": False}))
    return out


def borra(id_):
    """Quita la línea de la tarea de su nota. Devuelve {ruta, i, linea} para poder deshacerlo."""
    for p in notas():
        rel = ruta(p)
        if rel.startswith(SOLO_LECTURA):
            continue
        lineas = p.read_text("utf-8").splitlines(keepends=True)
        for i, linea in enumerate(lineas):
            if TAREA.match(linea.rstrip("\n")) and tid(rel, linea) == id_:
                del lineas[i]
                escribe(p, "".join(lineas))
                return {"ruta": rel, "i": i, "linea": linea.rstrip("\n")}
    return None


def restaura(rel, i, linea):
    """Deshacer de borra(): vuelve a poner la línea donde estaba. Solo una tarea, dentro del vault."""
    p = (VAULT / str(rel)).resolve()
    if (VAULT.resolve() not in p.parents or p.suffix != ".md" or not p.exists() or str(rel).startswith(SOLO_LECTURA)
            or not TAREA.match(str(linea)) or "\n" in str(linea)):
        raise ValueError("no se puede restaurar eso")
    lineas = p.read_text("utf-8").splitlines(keepends=True)
    i = max(0, min(int(i or 0), len(lineas)))
    if i == len(lineas) and lineas and not lineas[-1].endswith("\n"):
        lineas[-1] += "\n"
    lineas.insert(i, str(linea) + "\n")
    escribe(p, "".join(lineas))
    return {"id": tid(ruta(p), str(linea))}


# ---------- notas rápidas ----------
# Una viñeta sin casilla por nota, con la hora delante: «- 2026-11-17 10:32 · texto». Sin casilla, Tasks y
# tareas() no las cuentan. Las que Yago escriba a mano en Obsidian (sin hora) también valen.
RAPIDA = re.compile(r"^[-*] (?!\[[ xX]\] )(?:(\d{4}-\d{2}-\d{2} \d{2}:\d{2}) · )?(.+)$")


def _rapidas():
    p = VAULT / RAPIDAS
    return p, (p.read_text("utf-8").splitlines(keepends=True) if p.exists() else [])


def _rapida(linea, i):
    m = RAPIDA.match(linea.rstrip("\n"))
    return m and {"id": tid(RAPIDAS, linea), "t": m[2].strip(), "cuando": m[1] or "", "i": i}


def notas_rapidas():
    """Las más nuevas primero (en el fichero van en orden de llegada)."""
    _, lineas = _rapidas()
    return [n for n in (_rapida(x, i) for i, x in enumerate(lineas)) if n][::-1]


def _texto_nota(texto):
    texto = " ".join(str(texto or "").split())[:1000]
    if not texto:
        raise ValueError("nota vacía")
    return texto


def nueva_nota(texto, cuando=None):
    texto = _texto_nota(texto)
    linea = f"- {(cuando or datetime.now()).strftime('%Y-%m-%d %H:%M')} · {texto}"
    p, lineas = _rapidas()
    previo = "".join(lineas) if lineas else (
        f"---\ntype: area\ntags: [notas]\ncreated: {date.today()}\nsource: claude\n---\n"
        "# Notas rápidas\n\nIdeas sueltas de la web y la app de escritorio de todo. No son tareas: "
        "las que lo acaben siendo se pasan a Pendientes.\n\n")
    escribe(p, previo.rstrip("\n") + "\n" + linea + "\n")
    return _rapida(linea, previo.count("\n"))


def _busca_nota(id_):
    p, lineas = _rapidas()
    for i, x in enumerate(lineas):
        if RAPIDA.match(x.rstrip("\n")) and tid(RAPIDAS, x) == id_:
            return p, lineas, i
    raise ValueError("esa nota ya no está (¿la has cambiado en Obsidian?)")


def edita_nota(id_, texto):
    p, lineas, i = _busca_nota(id_)
    viejo = _rapida(lineas[i], i)
    linea = f"- {viejo['cuando'] + ' · ' if viejo['cuando'] else ''}{_texto_nota(texto)}"
    lineas[i] = linea + "\n"
    escribe(p, "".join(lineas))
    return _rapida(linea, i)


def borra_nota(id_):
    """Devuelve {i, linea} para deshacer con restaura_nota()."""
    p, lineas, i = _busca_nota(id_)
    linea = lineas.pop(i).rstrip("\n")
    escribe(p, "".join(lineas))
    return {"i": i, "linea": linea}


def restaura_nota(i, linea):
    linea = str(linea)
    if "\n" in linea or not RAPIDA.match(linea):
        raise ValueError("no se puede restaurar eso")
    p, lineas = _rapidas()
    i = max(0, min(int(i or 0), len(lineas)))
    if lineas and not lineas[-1].endswith("\n"):
        lineas[-1] += "\n"
    lineas.insert(i, linea + "\n")
    escribe(p, "".join(lineas))
    return _rapida(linea, i)


def nota_a_tarea(id_, due="", hora="", tags=()):
    """La nota se va de Notas rápidas y aparece en Pendientes. Devuelve la tarea y cómo deshacerlo."""
    _, lineas, i = _busca_nota(id_)
    tarea = nueva_tarea(_rapida(lineas[i], i)["t"][:200], due, hora, tags)
    return {"tarea": tarea, "nota": borra_nota(id_)}


def nueva_tarea(texto, due="", hora="", tags=(), historia=False, padre=""):
    """En Pendientes.md, o debajo de su historia (`padre`, en la nota de esta) si es una subtarea."""
    texto = " ".join(str(texto).split())[:200]
    if not texto:
        raise ValueError("tarea vacía")
    h = una(padre) if padre else None
    if padre and (not h or h["fija"] or h["hecha"]):
        raise ValueError("esa historia ya no está abierta (¿la has cambiado en Obsidian?)")
    marcas = limpia_tags(tags, h["ruta"] if h else "") + (["historia"] if historia else [])
    # Tasks lee sus campos desde el final: la hora (nuestra) va antes de la fecha o no la reconoce
    cuerpo = f"[ ] {texto}" + "".join(f" #{x}" for x in marcas) + (f" ⏰ {hora}" if due and hora else "") + (f" 📅 {due}" if due else "")
    if h:
        p = VAULT / h["ruta"]
        lineas = p.read_text("utf-8").splitlines(keepends=True)
        i = next(i for i, x in enumerate(lineas) if TAREA.match(x.rstrip("\n")) and tid(h["ruta"], x) == padre)
        j, s = i + 1, sangria(lineas[i])
        while j < len(lineas) and lineas[j].strip() and sangria(lineas[j]) > s:
            j += 1   # al final de las subtareas que ya tiene
        linea = lineas[i][:len(lineas[i]) - len(lineas[i].lstrip())] + "\t- " + cuerpo
        if not lineas[j - 1].endswith("\n"):
            lineas[j - 1] += "\n"
        lineas.insert(j, linea + "\n")
        escribe(p, "".join(lineas))
        return una(tid(h["ruta"], linea))
    linea = f"- {cuerpo}"
    p = VAULT / PENDIENTES
    previo = p.read_text("utf-8") if p.exists() else (
        f"---\ntype: area\ntags: [tareas]\ncreated: {date.today()}\nsource: claude\n---\n"
        "# Pendientes\n\nTareas sueltas que llegan por el bot de Telegram y la web de todo.\n\n")
    escribe(p, previo.rstrip("\n") + "\n" + linea + "\n")
    return una(tid(PENDIENTES, linea))


def marca(id_, hecha=True):
    """Marca (o desmarca) la tarea con ese id. Devuelve el id nuevo, que cambia con el texto."""
    hoy = date.today().isoformat()
    for p in notas():
        rel = ruta(p)
        # lee() no falla con lo que no es UTF-8: en Curro hay de todo y aquí solo se busca
        for i, linea in enumerate(lee(p).splitlines(keepends=True)):
            fila = linea.rstrip("\n")
            # en las diarias del curro las tareas pueden ser viñetas sin casilla: al tacharlas se les pone
            if p.parent.name == DIARIAS and re.match(r"[-*] (?!\[[ xX]\] )", fila):
                fila = f"{fila[:2]}[ ] {fila[2:]}"
            if (m := TAREA.match(fila)) and tid(rel, linea) == id_:
                resto = HECHA.sub("", m[4]).rstrip()
                nueva = f"{m[1]}{'x' if hecha else ' '}{m[3]}{resto}" + (f" ✅ {hoy}" if hecha else "")
                lineas = p.read_text("utf-8").splitlines(keepends=True)
                lineas[i] = nueva + ("\n" if linea.endswith("\n") else "")
                escribe(p, "".join(lineas))
                return tid(rel, nueva)
    return None


def edita(id_, texto, due="", hora="", tags=None):
    """Cambia el texto, el día, la hora y (si llegan) los proyectos de una tarea, en su nota y en su sitio. Conserva
    el estado del board y lo demás del plugin Tasks (prioridad, fechas de inicio…). Devuelve la tarea como todas()."""
    texto = " ".join(str(texto).split())[:200]
    if not texto:
        raise ValueError("tarea vacía")
    for p in notas():
        rel = ruta(p)
        if rel.startswith(SOLO_LECTURA):
            continue
        lineas = p.read_text("utf-8").splitlines(keepends=True)
        for i, linea in enumerate(lineas):
            m = TAREA.match(linea.rstrip("\n"))
            if m and tid(rel, linea) == id_:
                otros = "".join(OTROS.findall(m[4]))
                marcas = [x[1] for x in MARCA.finditer(m[4])]
                marcas = ([x for x in marcas if x.lower() in RESERVADAS] + limpia_tags(tags, rel) if tags is not None
                          else marcas)
                el = HECHA_EL.search(m[4])
                # como en nueva_tarea: Tasks lee desde el final, la hora antes de la fecha
                nueva = (f"{m[1]}{m[2]}{m[3]}{texto}" + "".join(f" #{x}" for x in marcas) + otros
                         + (f" ⏰ {hora}" if due and hora else "") + (f" 📅 {due}" if due else "") + (f" ✅ {el[1]}" if el else ""))
                lineas[i] = nueva + ("\n" if linea.endswith("\n") else "")
                escribe(p, "".join(lineas))
                return una(tid(rel, nueva))
    return None


# ---------- leer luego ----------
def nombre_seguro(titulo):
    limpio = re.sub(r'[\\/:*?"<>|#^\[\]]', " ", str(titulo))
    return " ".join(limpio.split())[:80].strip(" .") or "Enlace"


def de_leer(rel):
    """La ruta de una nota de Leer luego que existe, o None: lo de fuera de esa carpeta no se toca."""
    p = (VAULT / str(rel or "")).resolve()
    return p if p.parent == (VAULT / LEER).resolve() and p.suffix == ".md" and p.exists() else None


def nueva_lectura(d):
    """Nota de «leer luego» a partir de lo que manda el bot (ya resumido por Claude).
    Con `reemplaza` (la ruta de la nota provisional que dejó el iPhone) la nota buena ocupa su sitio."""
    url = str(d.get("url") or "").strip()
    if not url.startswith(("http://", "https://")) or len(url) > 1000:
        raise ValueError("url no válida")
    hoy = date.today()
    titulo = nombre_seguro(d.get("titulo") or url)
    carpeta = VAULT / LEER
    carpeta.mkdir(parents=True, exist_ok=True)
    vieja = de_leer(d.get("reemplaza")) if d.get("reemplaza") else None
    if vieja:
        vieja.unlink()
    p, n = carpeta / f"{titulo}.md", 2
    while p.exists():
        p, n = carpeta / f"{titulo} {n}.md", n + 1
    review = str(d.get("review") or "")
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", review):
        review = (hoy + timedelta(days=7)).isoformat()
    etiquetas = [re.sub(r"[^\w-]", "", str(t).lower().replace(" ", "-"))[:30] for t in d.get("tags") or []][:6]
    resumen = " ".join(str(d.get("resumen") or "").split())[:400]
    puntos = [" ".join(str(x).split())[:300] for x in d.get("puntos") or []][:8]
    relacionadas = [nombre_seguro(x) for x in d.get("enlaces") or []][:4]
    cuerpo = [
        "---", "type: recurso", f"tags: [leer-luego{''.join(', ' + t for t in etiquetas if t)}]",
        f"created: {hoy}", f"source: {'iphone' if d.get('source') == 'iphone' else 'telegram'}", f"url: {url}", f"tipo: {str(d.get('tipo') or 'articulo')[:20]}",
        f"minutos: {int(d.get('minutos') or 0)}", "leido: false", f"review: {review}",
        f'resumen: "{resumen.replace(chr(34), chr(39))}"', "---", f"# {titulo}", "", f"[Abrir el original]({url})", "",
        "## Resumen", resumen, "",
    ]
    if puntos:
        cuerpo += ["## Ideas clave", *[f"- {x}" for x in puntos], ""]
    if d.get("nota"):
        cuerpo += ["## Por qué lo guardé", " ".join(str(d["nota"]).split())[:500], ""]
    if relacionadas:
        cuerpo += ["## Relacionado", " · ".join(f"[[{x}]]" for x in relacionadas), ""]
    escribe(p, "\n".join(cuerpo))
    return {"ruta": ruta(p), "titulo": titulo, "review": review, "abrir": enlace(ruta(p))}


def lecturas():
    out = []
    carpeta = VAULT / LEER
    for p in sorted(carpeta.glob("*.md")) if carpeta.exists() else []:
        fm, _ = cabecera(lee(p))
        if fm.get("leido", "false").lower() == "true":
            continue
        out.append({"ruta": ruta(p), "titulo": p.stem, "url": fm.get("url", ""), "resumen": fm.get("resumen", ""),
                    "minutos": int(fm["minutos"]) if fm.get("minutos", "").isdigit() else 0,
                    "tipo": fm.get("tipo", ""), "guardado": fm.get("created", ""), "review": fm.get("review", ""),
                    "abrir": enlace(ruta(p))})
    return sorted(out, key=lambda x: x["guardado"], reverse=True)


def leido(rel):
    """Solo dentro de Leer luego: leido: true y fuera el review, para que no vuelva a avisar."""
    p = de_leer(rel)
    if not p:
        raise ValueError("no es una nota de leer luego")
    texto = p.read_text("utf-8")
    texto = re.sub(r"^leido:.*$", "leido: true", texto, count=1, flags=re.M)
    texto = re.sub(r"^review:.*\n", "", texto, count=1, flags=re.M)
    escribe(p, texto)


# ---------- notas recientes y revisión ----------
def plano(md):
    """Markdown de Obsidian a texto para un extracto: sin incrustados, enlaces con su texto."""
    md = re.sub(r"!\[\[[^\]]*\]\]|!\[[^\]]*\]\([^)]*\)", "", md)
    md = re.sub(r"\[\[(?:[^\]|]*\|)?([^\]]*)\]\]", r"\1", md)
    md = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", md)
    return " ".join(re.sub(r"[*_`]{1,3}|^- \[.\] |^[-*] ", "", md, flags=re.M).split())


def recientes(dias=14, n=20):
    """Lo que ha entrado al vault hace poco: lo que mandas al cerebro, ideas, diario."""
    desde = (datetime.now() - timedelta(days=dias)).timestamp()
    out = []
    for p in notas():
        rel = ruta(p)
        if rel.startswith(("Proyectos/", "Curro/", LEER)) or p.name in SIN_TAREAS or p.stat().st_mtime < desde:
            continue
        fm, cuerpo = cabecera(lee(p))
        texto = plano("\n".join(l for l in cuerpo.splitlines() if l.strip() and not l.startswith(("#", ">", "```", "|"))))
        out.append({"ruta": rel, "titulo": p.stem, "tipo": fm.get("type", ""), "created": fm.get("created", "")[:10],
                    "cambio": datetime.fromtimestamp(p.stat().st_mtime).isoformat(timespec="minutes"),
                    "extracto": texto[:180], "abrir": enlace(rel)})
    return sorted(out, key=lambda x: x["cambio"], reverse=True)[:n]


def revisar(hoy=None):
    hoy = (hoy or date.today()).isoformat()
    out = []
    for p in notas():
        fm, _ = cabecera(lee(p)[:2000])
        if re.fullmatch(r"\d{4}-\d{2}-\d{2}", fm.get("review", "")) and fm["review"] <= hoy:
            out.append({"ruta": ruta(p), "titulo": p.stem, "review": fm["review"], "tipo": fm.get("type", ""),
                        "abrir": enlace(ruta(p))})
    return sorted(out, key=lambda x: x["review"])
