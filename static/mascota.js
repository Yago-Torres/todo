/* El fantasma: un monigote de píxeles que cambia de cara y de forma según lo que pase.
   Para cambiarlo basta con tocar AJUSTES (son los mismos nombres que en el editor).
   Se coloca solo en la cabecera (header.top) de cada página y pide /api/fantasma; Hoy, que ya tiene
   esos datos, se los da con lee(H). refresca() vuelve a preguntar y salta si hay un hábito más hecho,
   y reacciona(estado, ms) lo cambia un momento. Con «reducir movimiento» se queda quieto. */
const fantasma = (() => {
  const AJUSTES = {semilla: 14, grumos: .2, pera: .35, cola: -12, flecos: 4, fleco: 10, ancho: 26, alto: 73,
                   ojoI: 4.5, ojoD: 4.5, sep: 14, ojosY: .38, color: "#CDE77F", px: 5};
  // cómo se deforma en cada estado: a ancho, h alto, fl flecos, ro cuánto enrojece
  const ESTADOS = {
    reposo: {a: 1, h: 1, fl: 1, ro: 0}, contento: {a: 1.06, h: .95, fl: .8, ro: 0}, feliz: {a: 1.1, h: .9, fl: .7, ro: 0},
    animo: {a: .96, h: 1.05, fl: 1, ro: 0}, enfadado: {a: 1.12, h: .94, fl: .85, ro: 1},
    dormido: {a: 1.14, h: .72, fl: .45, ro: 0}, ausente: {a: .82, h: 1.12, fl: 1.5, ro: 0},
  };
  const TINTA = "#1E211C", quieto = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const trazo = document.createElementNS("http://www.w3.org/2000/svg", "path");

  document.head.insertAdjacentHTML("beforeend", `<style>
    header.top { position: relative; min-height: 72px; padding-right: 72px; }
    #fantasma { position: absolute; right: 2px; top: 0; width: 60px; height: 72px; cursor: pointer; -webkit-tap-highlight-color: transparent; }
    #fantasma svg { display: block; width: 100%; height: 100%; overflow: visible; }
    #fantasma .flota { animation: f-flota 3.6s ease-in-out infinite; }
    #fantasma .sombra { transform-box: fill-box; transform-origin: center; animation: f-sombra 3.6s ease-in-out infinite; }
    #fantasma .mec { transform-box: fill-box; transform-origin: 50% 100%; }
    #fantasma .ojo { transform-box: fill-box; transform-origin: center; animation: f-parpadeo 5.2s infinite; }
    #fantasma .fa { animation: f-a 1.1s infinite; } #fantasma .fb { animation: f-b 1.1s infinite; }
    #fantasma .humo { animation: f-sube 3s linear infinite; opacity: 0; }
    #fantasma[data-e=feliz] .mec { animation: f-brinco 1s cubic-bezier(.3, 0, .3, 1) infinite; }
    #fantasma[data-e=animo] .mec { transform-origin: 50% 0; animation: f-meneo 1.4s ease-in-out infinite; }
    #fantasma[data-e=enfadado] .mec { animation: f-grr 2.4s infinite; }
    #fantasma[data-e=dormido] .flota, #fantasma[data-e=dormido] .sombra { animation-duration: 6.5s; }
    #fantasma[data-e=ausente] .mec { opacity: var(--o, 1); animation: f-apaga 2.8s ease-in-out infinite; }
    @keyframes f-flota { 0%, 100% { transform: translateY(0); } 50% { transform: translateY(-5px); } }
    @keyframes f-sombra { 0%, 100% { transform: scale(1); } 50% { transform: scale(.8); } }
    @keyframes f-parpadeo { 0%, 92%, 100% { transform: scaleY(1); } 95% { transform: scaleY(.1); } }
    @keyframes f-brinco { 0%, 100% { transform: translateY(0) scale(1.05, .94); } 20% { transform: translateY(0) scale(.95, 1.06); }
      50% { transform: translateY(-16px) scale(.98, 1.03); } 80% { transform: translateY(0) scale(1.05, .94); } }
    @keyframes f-meneo { 0%, 100% { transform: rotate(0); } 25% { transform: rotate(-5deg); } 75% { transform: rotate(5deg); } }
    @keyframes f-grr { 0%, 70%, 100% { transform: translateX(0); } 74%, 82%, 90% { transform: translateX(-2px); } 78%, 86% { transform: translateX(2px); } }
    @keyframes f-apaga { 0%, 100% { opacity: var(--o, 1); } 50% { opacity: calc(var(--o, 1) * .7); } }
    @keyframes f-a { 0%, 49% { opacity: 1; } 50%, 100% { opacity: 0; } }
    @keyframes f-b { 0%, 49% { opacity: 0; } 50%, 100% { opacity: 1; } }
    @keyframes f-sube { 0% { opacity: 0; transform: translate(0, 0); } 25% { opacity: 1; } 100% { opacity: 0; transform: translate(10px, -26px); } }
    @media (prefers-reduced-motion: reduce) { #fantasma * { animation: none !important; } }
  </style>`);

  const azar = a => () => {
    a = a + 0x6D2B79F5 | 0;
    let t = Math.imul(a ^ a >>> 15, 1 | a);
    t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
    return ((t ^ t >>> 14) >>> 0) / 4294967296;
  };
  const mezcla = (a, b, t) => "#" + [1, 3, 5].map(i => Math.round(parseInt(a.slice(i, i + 2), 16) * (1 - t) + parseInt(b.slice(i, i + 2), 16) * t)
    .toString(16).padStart(2, "0")).join("");

  // el contorno del cuerpo; fase 0 y 1 son los dos momentos de los flecos
  function contorno(p, fase) {
    const R = azar(p.semilla), cx = 80, yb = 122, h = p.alto, yt = yb - h, c = p.cola, g = p.grumos;
    const wt = p.ancho * (1 - p.pera * .45), wb = p.ancho * (1 + p.pera * .3), n = p.flecos, w = 2 * wb / n;
    const j = (R() - .5) * g * 30, k = (R() - .5) * g * 30, top = (R() - .5) * g * 24;
    let d = `M${cx - wb + c} ${yb} C${cx - wb + c * .2 + j} ${yt + h * .38} ${cx - wt} ${yt + Math.abs(top) * .3} ${cx + top} ${yt}
      C${cx + wt} ${yt - Math.abs(top) * .3} ${cx + wb + c * .2 + k} ${yt + h * .38} ${cx + wb + c} ${yb}`;
    let x = cx + wb + c;
    for (let i = 0; i < n; i++) {
      const hd = p.fleco * (1 + g * (R() - .5) * 3) * (1 + .38 * Math.sin(i * 1.9 + fase * Math.PI)), e = i === n - 1 ? yb : yb + (R() - .5) * g * 12;
      d += ` Q${x - w / 2 + Math.sin(fase * Math.PI + i) * 2} ${Math.min(156, yb + hd * 1.7)} ${x - w} ${e}`;
      x -= w;
    }
    return d + "Z";
  }

  // el contorno pasado a cuadraditos
  function pixeles(d, s, color) {
    trazo.setAttribute("d", d);
    const T = trazo.getTotalLength(), P = [];
    for (let i = 0; i < 240; i++) { const q = trazo.getPointAtLength(T * i / 240); P.push([q.x, q.y]); }
    const dentro = (x, y) => {
      let c = false;
      for (let i = 0, j = P.length - 1; i < P.length; j = i++) {
        const [a, b] = P[i], [u, v] = P[j];
        if ((b > y) !== (v > y) && x < (u - a) * (y - b) / (v - b) + a) c = !c;
      }
      return c;
    };
    let r = "";
    for (let y = 0; y < 160; y += s) for (let x = 0; x < 160; x += s) if (dentro(x + s / 2, y + s / 2)) r += `M${x} ${y}h${s}v${s}h${-s}z`;
    return `<path d="${r}" fill="${color}" shape-rendering="crispEdges"/>`;
  }

  function dibujo(e, m) {
    const p = {...AJUSTES, ancho: AJUSTES.ancho * m.a, alto: AJUSTES.alto * m.h, fleco: Math.min(18, AJUSTES.fleco * m.fl)};
    const s = p.px, sn = v => Math.round(v / s) * s, yt = 122 - p.alto, fx = 80 + p.cola * .2, ey = yt + p.alto * p.ojosY;
    const wb = p.ancho * (1 + p.pera * .3), color = mezcla(p.color, "#D9533A", Math.max(0, Math.min(1, m.ro)) * .55);
    const R = (x, y, w, h) => `<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="${TINTA}"/>`;
    const cuerpo = quieto ? pixeles(contorno(p, 0), s, color)
      : `<g class="fa">${pixeles(contorno(p, 0), s, color)}</g><g class="fb">${pixeles(contorno(p, 1), s, color)}</g>`;
    const sonrie = e === "feliz" || e === "contento";
    let cara = "";
    for (const [q, z] of [[-1, p.ojoI], [1, p.ojoD]]) {
      const X = sn(fx + q * p.sep / 2), Y = sn(ey), w = Math.max(s, sn(z * 1.6));
      if (sonrie) cara += R(X - s, Y, s, s) + R(X, Y - s, s, s) + R(X + s, Y, s, s);
      else if (e === "dormido") cara += R(X - s, Y, s * 3, s * .6);
      else cara += `<g class="ojo">${R(X, Y - s, w, w + s)}</g>`;
      if (e === "animo") cara += R(X - s, Y - s * 2, s * 2, s * .6);
      if (e === "ausente") cara += R(X - s, Y - s * (q < 0 ? 2 : 3), s * 2, s * .6);
      if (e === "enfadado") cara += R(X + (q < 0 ? -s : s), Y - s * 2, s, s * .7) + R(X, Y - s * 1.3, s, s * .7);
    }
    const X = sn(fx + 1), Y = sn(ey + Math.max(p.ojoI, p.ojoD) * 1.1 + 7);
    cara += sonrie ? R(X - s, Y, s * 3, s * .7) + R(X, Y + s * .7, s, s * .7)
      : e === "enfadado" ? R(X - s, Y, s, s * .7) + R(X, Y + s * .7, s, s * .7) + R(X + s, Y, s, s * .7) + R(X + s * 2, Y + s * .7, s, s * .7)
      : e === "ausente" ? R(X - s, Y + s * .7, s * 3, s * .7) + R(X, Y, s, s * .7)
      : e === "animo" || e === "dormido" ? R(X, Y, s, s) : R(X - s, Y, s * 2, s * .7);
    const humo = e === "enfadado" ? [-14, 14].map((o, i) => `<circle class="humo" cx="${fx + o}" cy="${yt - 3}" r="3.5" fill="#A3A892" style="animation-duration:1.6s;animation-delay:${i * .7}s"/>`).join("")
      : e === "dormido" ? [[0, 14], [8, 4], [14, -4]].map(([x, y], i) => `<text class="humo" x="${fx + p.ancho + 2 + x}" y="${yt + y}" font-size="${14 - i}" fill="#A3A892" style="animation-delay:${i}s">z</text>`).join("") : "";
    return `<svg viewBox="30 30 100 120" aria-hidden="true"><ellipse class="sombra" cx="${80 + p.cola * .5}" cy="148" rx="${wb * .8}" ry="3.5" fill="#000" opacity=".2"/><g class="flota"><g class="mec">${cuerpo}${cara}</g>${humo}</g></svg>`;
  }

  const enHoy = !!document.querySelector('meta[name="calma-datos"][content*="/api/hoy"]');
  let caja, actual = "reposo", base = "reposo", m = ESTADOS.reposo, tiempo, vuelta, hechos = null;
  const pinta = () => {   // es un adorno: si algo falla, desaparece y Hoy sigue
    try { caja.dataset.e = actual; caja.innerHTML = dibujo(actual, m); }
    catch (e) { clearInterval(tiempo); caja.hidden = true; }
  };
  function cambia(e) {
    actual = e;
    clearInterval(tiempo);
    if (quieto) { m = ESTADOS[e]; return pinta(); }
    const a = m, b = ESTADOS[e];
    let t = 0;
    tiempo = setInterval(() => {   // con un pequeño rebote al final
      t = Math.min(1, t + .1);
      const k = t === 1 ? 1 : 1 - Math.pow(1 - t, 3) * Math.cos(t * 6);
      m = Object.fromEntries(Object.keys(b).map(c => [c, a[c] + (b[c] - a[c]) * k]));
      pinta();
      if (t === 1) clearInterval(tiempo);
    }, 33);
  }
  function monta() {
    if (caja) return caja;
    const sitio = document.querySelector("header.top");
    if (!sitio) return null;
    caja = document.createElement("div");
    caja.id = "fantasma";
    // lo de ayer se arregla en Hoy, que es donde sale el cartel
    caja.onclick = () => (!enHoy && actual === "enfadado" ? location.assign("/") : reacciona("feliz", 900));
    sitio.append(caja);
    return caja;
  }
  function reacciona(e, ms = 1600) {
    if (!monta()) return;
    clearTimeout(vuelta);
    cambia(e);
    vuelta = setTimeout(() => { vuelta = null; cambia(base); }, ms);
  }
  function pon(e, presencia) {
    if (!monta()) return;
    base = e;
    caja.style.setProperty("--o", presencia);
    if (!caja.firstChild) { actual = e; m = ESTADOS[e]; pinta(); }   // al abrir la página, ya con su cara
    else if (!vuelta && e !== actual) cambia(e);
  }
  // d: {habitos: [{id, plan, hecho}], ayer: [{id, n}], sin_venir}. Devuelve lo de ayer que hay que enseñar.
  function lee(d) {
    const hs = d.habitos, hora = new Date().getHours(), noche = hora >= 23 || hora < 6;
    const ayer = d.ayer.filter(a => !hs.find(h => h.id === a.id)?.hecho), faltan = hs.filter(h => h.plan && !h.hecho);
    const dias = hs.some(h => h.hecho) ? 0 : d.sin_venir;   // desde 3 días sin venir se va desvaneciendo
    pon(noche ? "dormido" : dias >= 3 ? "ausente" : ayer.length ? "enfadado"
      : !faltan.length && hs.some(h => h.plan || h.hecho) ? "contento" : hora >= 18 && faltan.length ? "animo" : "reposo",
      dias >= 3 ? Math.max(.25, 1 - dias * .13) : 1);
    return noche || dias >= 3 ? [] : ayer;
  }
  async function refresca() {
    try {
      const r = await fetch("/api/fantasma", {credentials: "same-origin"});
      if (!r.ok) return;   // sin sesión no hay fantasma
      const d = await r.json(), n = d.habitos.filter(h => h.hecho).length;
      if (hechos != null && n > hechos) reacciona("feliz");
      hechos = n;
      lee(d);
    } catch { /* sin red se queda como estaba */ }
  }
  if (!enHoy) {
    document.addEventListener("DOMContentLoaded", refresca);
    document.addEventListener("visibilitychange", () => { if (!document.hidden) refresca(); });
  }
  return {lee, refresca, reacciona};
})();
