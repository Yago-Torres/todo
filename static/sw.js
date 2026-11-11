// Service worker de todo: avisos, y que la app abra al momento (y sin red).
// - Lo que no cambia nunca (con versión en la URL, o de las webs de fuentes y librerías): de la copia, sin preguntar.
// - Las páginas: de la copia al momento, y por detrás la nueva para la próxima vez (un despliegue se ve en la
//   segunda visita). Si Cloudflare Access pide entrar, se borra la copia: la próxima vez va a la red y al login.
// - Los datos (/api): de la red si contesta en 400 ms; si no, la copia ya, y cuando llega la respuesta, si es
//   distinta, se avisa a la página para que recargue (calma.js). Sin red, la copia. Las marcas sin red, sinred.js.

const CACHE = "todo-4";
const FUERA = /^https:\/\/(fonts\.googleapis\.com|fonts\.gstatic\.com|cdnjs\.cloudflare\.com|cdn\.jsdelivr\.net)\//;
// ?v= (aplica.sh), o la versión en el nombre (anime-4.5.0, Chart.js/4.4.1): si cambia, cambia la URL
const fijo = u => FUERA.test(u.href) || u.searchParams.has("v") || /\d+\.\d+\.\d+/.test(u.pathname);
const vale = res => res.ok && res.type === "basic" && !res.redirected;   // la redirección al login de Access, no

self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", e => e.waitUntil((async () => {
  for (const k of await caches.keys()) if (k !== CACHE) await caches.delete(k);
  await self.clients.claim();
})()));

self.addEventListener("fetch", e => {
  const r = e.request, u = new URL(r.url), mio = u.origin === location.origin;
  if (r.method !== "GET" || !(mio || FUERA.test(r.url))) return;
  if (r.headers.has("range") || r.destination === "video") return;   // vídeo: directo a la red, por trozos
  if (fijo(u)) e.respondWith(deLaCopia(r));
  else if (r.mode === "navigate") e.respondWith(pagina(e));
  else if (mio) e.respondWith(datos(e));
});

async function deLaCopia(r) {
  const copia = await caches.match(r);
  if (copia) return copia;
  const res = await fetch(r);
  // las de fuera llegan opacas (sin CORS): también valen
  if (res.ok || res.type === "opaque") await (await caches.open(CACHE)).put(r, res.clone());
  return res;
}

async function pagina(e) {
  const r = e.request, cache = await caches.open(CACHE), copia = await cache.match(r);
  const red = fetch(r).then(async res => {
    if (vale(res)) await cache.put(r, res.clone());
    else if (res.type === "opaqueredirect") await cache.delete(r);
    return res;
  });
  e.waitUntil(red.catch(() => {}));
  return copia || red;
}

async function datos(e) {
  const r = e.request, cache = await caches.open(CACHE), copia = await cache.match(r);
  const red = fetch(r).then(async res => {
    if (!vale(res)) return [res, null];
    const nueva = res.clone();
    await cache.put(r, nueva.clone());
    return [res, nueva];
  });
  e.waitUntil(red.catch(() => {}));
  if (!copia) return red.then(([res]) => res);
  // un 5xx es la Pi caída detrás de Cloudflare: para eso también está la copia
  const ya = await Promise.race([red.then(([res]) => (res.status >= 500 ? null : res), () => null),
                                 new Promise(ok => setTimeout(() => ok("tarde"), 400))]);
  if (ya && ya !== "tarde") return ya;
  if (ya === null) return copia;
  const antes = copia.clone();
  e.waitUntil(red.then(async ([, nueva]) => {
    if (!nueva || (await nueva.text()) === (await antes.text())) return;
    const c = await self.clients.get(e.clientId);
    if (c) c.postMessage({tipo: "fresco", url: r.url});
  }).catch(() => {}));
  return copia;
}

self.addEventListener("push", e => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (err) { d = {}; }
  const titulo = d.titulo || "TODO";
  e.waitUntil(self.registration.showNotification(titulo, {
    body: d.cuerpo || "",
    icon: "/apple-touch-icon.png",
    badge: "/apple-touch-icon.png",
    tag: d.tag || "todo",          // un aviso nuevo del mismo tipo reemplaza al viejo
    renotify: true,
    data: {url: d.url || "/"},
  }));
});

// En iOS no existen los botones de acción en la notificación, así que el único
// gesto posible es tocarla: abre la app en la URL que trae, y es esa URL la que
// marca el hábito. (Los botones de verdad van por Telegram: avisos.py.)
self.addEventListener("notificationclick", e => {
  e.notification.close();
  const destino = (e.notification.data && e.notification.data.url) || "/";
  e.waitUntil((async () => {
    const abiertas = await self.clients.matchAll({type: "window", includeUncontrolled: true});
    for (const c of abiertas) {
      if (new URL(c.url).origin === self.location.origin) {
        await c.navigate(destino);
        return c.focus();
      }
    }
    return self.clients.openWindow(destino);
  })());
});
