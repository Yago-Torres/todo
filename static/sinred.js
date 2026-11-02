/* Marcar hábitos sin red. Cada marca dice cómo queda el hábito ese día (hecho o no), no «cámbialo»:
   se puede mandar tarde o dos veces sin estropear nada. Se apunta aquí, se manda en cuanto hay red y,
   mientras tanto, las páginas la pintan encima de lo que llegue del servidor o de la copia de sw.js. */
const sinred = (() => {
  const K = "marcas-sin-enviar";
  const lee = () => { try { return JSON.parse(localStorage.getItem(K)) || []; } catch { return []; } };
  const pon = l => { try { localStorage.setItem(K, JSON.stringify(l)); } catch { /* sin almacenamiento: solo se pierde lo de sin red */ } };
  let fila = Promise.resolve(200);   // de una en una y en orden

  // 200 = todo enviado; 0 = sin red; 401 = hay que entrar otra vez. Lo que no sale se queda para la próxima
  async function manda(cola) {
    for (const m of lee()) {
      const r = await fetch("/api/marca", {method: "POST", headers: {"Content-Type": "application/json"}, body: JSON.stringify(m)}).catch(() => null);
      if (!r || r.status === 401 || r.status >= 500) return r ? r.status : 0;
      pon(lee().filter(x => x.t !== m.t));   // un 4xx tampoco se reintenta: no se va a arreglar solo
      if (r.ok) dispatchEvent(new CustomEvent("marca-enviada", {detail: {...await r.json(), cola}}));
    }
    return 200;
  }
  const envia = cola => (fila = fila.then(() => manda(cola)).catch(() => 0));

  function marca(dia, id, hecho) {
    pon([...lee().filter(x => x.dia !== dia || x.id !== id), {dia, id, hecho, t: Date.now() + Math.random()}]);
    return envia(false);
  }

  const hecho = (dia, id, servidor) => { const m = lee().find(x => x.dia === dia && x.id === id); return m ? m.hecho : servidor; };
  function aplica(log) {
    for (const m of lee()) {
      const l = new Set(log[m.dia] || []);
      m.hecho ? l.add(m.id) : l.delete(m.id);
      if (l.size) log[m.dia] = [...l]; else delete log[m.dia];
    }
    return log;
  }

  // lo apuntado sin red sale al volver la red, al volver a la app o al abrirla
  const intenta = () => lee().length ? envia(true) : fila;
  addEventListener("online", intenta);
  document.addEventListener("visibilitychange", () => document.visibilityState === "visible" && intenta());
  intenta();
  // la copia para abrir la app sin red la guarda el service worker
  if ("serviceWorker" in navigator) navigator.serviceWorker.register("/sw.js").catch(() => {});
  return {marca, hecho, aplica, envia: intenta};
})();
