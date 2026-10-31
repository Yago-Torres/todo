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
    t = AVISO.sub("", OTROS.sub("", HECHA.sub("", HORA.sub("", FECHA.sub("", resto))))).strip()
    return {"t": t, "due": due, "hora": hora.zfill(5) if hora else "", "hecha": m[2] != " "}


def valida(dia):
    try:
        return bool(date.fromisoformat(dia))
    except ValueError:   # las plantillas traen cosas como 2026-09-00
        return False


def grupo(rel):
    if rel == PENDIENTES:
        return "Pendientes"
    return rel.split("/")[0] if "/" in rel else "Notas"


def tareas():
    """Las abiertas de todo el vault (sin Archivo/), con un id estable por contenido."""
    ps = [p for p in notas() if p.name not in SIN_TAREAS]
    diarias = {}
    for p in ps:
        if p.parent.name == DIARIAS:
            diarias[p.parent] = max(diarias.get(p.parent, p), p, key=lambda x: x.name)
    out, vistas = [], set()
    for p in ps:
        if p.parent.name == DIARIAS and diarias[p.parent] != p:
            continue
        rel, texto = ruta(p), lee(p)
        encontradas = (de_la_daily(texto) if p.parent.name == DIARIAS and TITULO.search(texto)
                       else [(linea, t) for linea in texto.splitlines() if (t := parsea(linea))])
        for linea, t in encontradas:
            if not t["hecha"] and t["t"] and (grupo(rel), t["t"]) not in vistas:
                vistas.add((grupo(rel), t["t"]))
                out.append({**t, "id": tid(rel, linea), "ruta": rel, "nota": p.stem, "grupo": grupo(rel),
                            "fija": rel.startswith(SOLO_LECTURA), "abrir": enlace(rel)})
    return sorted(out, key=lambda t: (t["due"] or "9999", t["hora"] or "99", t["grupo"], t["t"]))


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


def nueva_tarea(texto, due="", hora=""):
    texto = " ".join(str(texto).split())[:200]
    if not texto:
        raise ValueError("tarea vacía")
    # Tasks lee sus campos desde el final: la hora (nuestra) va antes de la fecha o no la reconoce
    linea = f"- [ ] {texto}" + (f" ⏰ {hora}" if due and hora else "") + (f" 📅 {due}" if due else "")
    p = VAULT / PENDIENTES
    previo = p.read_text("utf-8") if p.exists() else (
        f"---\ntype: area\ntags: [tareas]\ncreated: {date.today()}\nsource: claude\n---\n"
        "# Pendientes\n\nTareas sueltas que llegan por el bot de Telegram y la web de todo.\n\n")
    escribe(p, previo.rstrip("\n") + "\n" + linea + "\n")
    return {**parsea(linea), "id": tid(PENDIENTES, linea), "ruta": PENDIENTES, "nota": p.stem}


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


def edita(id_, texto, due="", hora=""):
    """Cambia el texto, el día y la hora de una tarea abierta, en su nota y en su sitio. Conserva lo
    demás del plugin Tasks (prioridad, fechas de inicio…). Devuelve la tarea como la da tareas()."""
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
                # como en nueva_tarea: Tasks lee desde el final, la hora antes de la fecha
                nueva = f"{m[1]}{m[2]}{m[3]}{texto}{otros}" + (f" ⏰ {hora}" if due and hora else "") + (f" 📅 {due}" if due else "")
                lineas[i] = nueva + ("\n" if linea.endswith("\n") else "")
                escribe(p, "".join(lineas))
                return {**parsea(nueva), "id": tid(rel, nueva), "ruta": rel, "nota": p.stem}
    return None


# ---------- leer luego ----------
def nombre_seguro(titulo):
    limpio = re.sub(r'[\\/:*?"<>|#^\[\]]', " ", str(titulo))
    return " ".join(limpio.split())[:80].strip(" .") or "Enlace"


def nueva_lectura(d):
    """Nota de «leer luego» a partir de lo que manda el bot (ya resumido por Claude)."""
    url = str(d.get("url") or "").strip()
    if not url.startswith(("http://", "https://")) or len(url) > 1000:
        raise ValueError("url no válida")
    hoy = date.today()
    titulo = nombre_seguro(d.get("titulo") or url)
    carpeta = VAULT / LEER
    carpeta.mkdir(parents=True, exist_ok=True)
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
        f"created: {hoy}", "source: telegram", f"url: {url}", f"tipo: {str(d.get('tipo') or 'articulo')[:20]}",
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
    p = (VAULT / rel).resolve()
    if p.parent != (VAULT / LEER).resolve() or p.suffix != ".md" or not p.exists():
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
