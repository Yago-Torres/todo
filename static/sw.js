// Service worker de todo.yagotg.dev: sólo avisos.
// No cachea nada a propósito: la app es un único HTML servido por FastAPI y una
// caché mal invalidada daría más guerra que el ahorro que supone.

self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", e => e.waitUntil(self.clients.claim()));

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
