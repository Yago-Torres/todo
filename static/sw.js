// Service worker de todo: avisos y una copia para abrir la app sin red.
// Siempre va primero a la red, así que con conexión nada sale de una caché vieja. Solo si la red falla
// (o tarda más de 4 s y hay copia) sale lo último que se guardó. Las marcas sin red van por sinred.js.
// Cloudflare guarda los .js 4 h: un sw.js nuevo puede tardar eso en llegar.

const CACHE = "todo-1";
// ponytail: cada ?v= nuevo deja su copia vieja (KB); se vacía al cambiar CACHE
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", e => e.waitUntil((async () => {
  for (const k of await caches.keys()) if (k !== CACHE) await caches.delete(k);
  await self.clients.claim();
})()));

self.addEventListener("fetch", e => {
  const r = e.request;
  if (r.method !== "GET" || new URL(r.url).origin !== location.origin) return;
  // la redirección al login de Cloudflare Access no es "basic" ni "ok": esa no se guarda
  const red = fetch(r).then(async res => {
    if (res.ok && res.type === "basic" && !res.redirected) await (await caches.open(CACHE)).put(r, res.clone());
    return res;
  });
  e.waitUntil(red.catch(() => {}));
  e.respondWith((async () => {
    const copia = await caches.match(r);
    if (!copia) return red;
    // un 5xx es la Pi caída detrás de Cloudflare: para eso también está la copia
    return Promise.race([red.then(res => res.status >= 500 ? copia : res, () => copia),
                         new Promise(ok => setTimeout(() => ok(copia), 4000))]);
  })());
});

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
// marca el hábito.
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
