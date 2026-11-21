"""Freno a las contraseñas a ciegas: 10 intentos fallidos en 15 minutos desde la misma IP la bloquean 15 minutos.

Desde fuera todo pasa antes por Cloudflare Access, pero desde la wifi de casa se llega directo al puerto (8082, 8085…):
sin esto, alguien en la red podría probar contraseñas sin parar. Cuenta como intento fallido un 401 en /api/login o
en una petición que trae `Authorization` (una clave Bearer mala). Un 401 de una página sin sesión no cuenta.

Detrás del túnel todas las peticiones llegan desde la IP de cloudflared: ahí la IP de verdad es la cabecera
CF-Connecting-IP, que solo se cree si la petición viene de la propia Pi o de Docker (desde la wifi se podría falsear).
Lo usan todo y gastos (copia idéntica en cada repo): `intentos.instala(app)`.
"""
import ipaddress
import threading
import time

MAX, VENTANA = 10, 15 * 60
# de dónde llega el túnel: la propia Pi (cloudflared del sistema), Docker (el de filebrowser) y su IP de la LAN
TUNEL = [ipaddress.ip_network(n) for n in ("127.0.0.0/8", "::1/128", "172.16.0.0/12", "192.168.1.70/32")]
_fallos: dict[str, list[float]] = {}
_cerrojo = threading.Lock()


def quien(peer, cabeceras):
    """La IP que cuenta: la del socket, o la que dice Cloudflare si la petición viene del túnel."""
    try:
        ip = ipaddress.ip_address(peer)
    except ValueError:
        return peer or "?"
    if any(ip in n for n in TUNEL):
        real = str(cabeceras.get("cf-connecting-ip") or "").strip()
        if real:
            return real
    return str(ip)


def _poda(clave, ahora):
    l = [t for t in _fallos.get(clave, []) if ahora - t < VENTANA]
    if l:
        _fallos[clave] = l
    else:
        _fallos.pop(clave, None)
    return l


def bloqueada(clave, ahora=None):
    with _cerrojo:
        return len(_poda(clave, ahora or time.time())) >= MAX


def fallo(clave, ahora=None):
    with _cerrojo:
        ahora = ahora or time.time()
        _fallos[clave] = _poda(clave, ahora) + [ahora]
        if len(_fallos) > 5000:   # que nadie llene la memoria con IPs inventadas
            for k in list(_fallos)[:1000]:
                _fallos.pop(k, None)


def cuenta(ruta, con_clave, codigo):
    return codigo == 401 and (ruta.endswith("/api/login") or con_clave)


def instala(app):
    from fastapi.responses import JSONResponse

    @app.middleware("http")
    async def freno(request, call_next):
        clave = quien(request.client.host if request.client else "", request.headers)
        if bloqueada(clave):
            return JSONResponse({"detail": "Demasiados intentos fallidos: espera 15 minutos"}, status_code=429)
        r = await call_next(request)
        if cuenta(request.url.path, bool(request.headers.get("authorization")), r.status_code):
            fallo(clave)
        return r
