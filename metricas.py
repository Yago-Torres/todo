"""Métricas de las webs: cada petición, sumada por minuto y por grupo de ruta, en observa.db (tabla `http`).

    {minuto, app, grupo, n, e5 (5xx), e4 (4xx), ms_sum, ms_max, lentas (> 1 s)}

Se apunta en memoria y un hilo lo vuelca cada minuto (una escritura por minuto, no por petición). Lo lee observa.py
para el panel de /sistema.html. Lo usan todo, todo-aitana, gastos y gastos-aitana (copia idéntica en cada repo):
`metricas.instala(app, "todo")`. Si la base no se puede escribir, la web sigue igual: las métricas son un extra.
"""
import os
import sqlite3
import threading
import time
from pathlib import Path

DB = Path(os.getenv("OBSERVA_DB", "/home/pi/todo/observa.db"))
LENTA_MS = 1000
_buf: dict[tuple[str, str], list[float]] = {}
_cerrojo = threading.Lock()
ESQUEMA = """CREATE TABLE IF NOT EXISTS http (minuto TEXT, app TEXT, grupo TEXT, n INTEGER, e5 INTEGER, e4 INTEGER,
             ms_sum REAL, ms_max REAL, lentas INTEGER, PRIMARY KEY (minuto, app, grupo))"""


def grupo(ruta):
    """/api/inversiones/precios → /api/inversiones; /carrera.html → páginas; /calma.css → estáticos."""
    if ruta.startswith("/api/"):
        partes = ruta.split("/")
        return "/".join(partes[:3]) if len(partes) > 2 else ruta
    if ruta in ("/", "") or ruta.endswith(".html"):
        return "páginas"
    return "estáticos"


def conecta():
    c = sqlite3.connect(DB, timeout=5)
    c.execute("PRAGMA journal_mode=WAL")
    c.execute(ESQUEMA)
    return c


def apunta(ruta, codigo, ms):
    k = (time.strftime("%Y-%m-%dT%H:%M"), grupo(ruta))
    with _cerrojo:
        b = _buf.setdefault(k, [0, 0, 0, 0.0, 0.0, 0])
        b[0] += 1
        b[1] += codigo >= 500
        b[2] += 400 <= codigo < 500
        b[3] += ms
        b[4] = max(b[4], ms)
        b[5] += ms > LENTA_MS


def vuelca(app):
    with _cerrojo:
        filas = list(_buf.items())
        _buf.clear()
    if not filas:
        return
    try:
        c = conecta()
    except sqlite3.Error as e:
        print("métricas:", e, flush=True)
        return
    try:
        with c:
            c.executemany("""INSERT INTO http VALUES (?,?,?,?,?,?,?,?,?) ON CONFLICT (minuto, app, grupo) DO UPDATE SET
                             n = n + excluded.n, e5 = e5 + excluded.e5, e4 = e4 + excluded.e4, ms_sum = ms_sum + excluded.ms_sum,
                             ms_max = max(ms_max, excluded.ms_max), lentas = lentas + excluded.lentas""",
                          [(m, app, g, int(b[0]), int(b[1]), int(b[2]), round(b[3], 1), round(b[4], 1), int(b[5]))
                           for (m, g), b in filas])
    except sqlite3.Error as e:
        print("métricas:", e, flush=True)
    finally:
        c.close()


def instala(app_fastapi, nombre):
    @app_fastapi.middleware("http")
    async def mide(request, call_next):
        t0 = time.perf_counter()
        codigo = 500
        try:
            r = await call_next(request)
            codigo = r.status_code
            return r
        finally:
            apunta(request.url.path, codigo, (time.perf_counter() - t0) * 1000)

    def bucle():
        while True:
            time.sleep(60)
            vuelca(nombre)
    threading.Thread(target=bucle, daemon=True).start()

