/* Lo que la web comparte con Tom, la app de iPhone, y que funciona igual en el navegador sin ella:
   - vibra(patrón) (también window.tomVibra): dentro de la app, la vibración con patrón de Core Haptics; fuera, vibrate().
   - suena(nombre): sonidos sutiles con Web Audio, sin ficheros. Solo con «Sonidos» activado en Ajustes (por defecto, no).
   - escucha(fn): la inclinación del móvil, {x, y} de -1 a 1 (x a la derecha, y hacia abajo). La da la app a ~30 Hz;
     en el navegador, la orientación del aparato, y solo después de que se toque el fantasma (permiso()).
   - descifra()/cifra(): las cifras que se descifran al cargar; planta(): cómo está la planta de la racha.
   - profundidad(): las tarjetas que se inclinan un poco con el móvil (Hoy).
   Todo es adorno: si algo falta (sin app, sin sensores, sin audio, «reducir movimiento») la página va igual. */
const tom = (() => {
  const navegador = typeof window !== "undefined";
  const quieto = () => navegador && matchMedia("(prefers-reduced-motion: reduce)").matches;
  const app = () => navegador && !!(window.HoyApp && window.webkit?.messageHandlers?.hoy);
  const manda = m => { try { window.webkit.messageHandlers.hoy.postMessage(m); } catch { /* app vieja o sin puente */ } };
  const lee = k => { try { return localStorage.getItem(k); } catch { return null; } };
  const pon = (k, v) => { try { v == null ? localStorage.removeItem(k) : localStorage.setItem(k, v); } catch { /* sin almacenamiento */ } };
  const entre = (v, a, b) => Math.max(a, Math.min(b, v));

  // ---------- vibraciones ----------
  // [vibra, pausa, vibra, …] en ms, para vibrate(); la app tiene su versión de cada uno en Core Haptics
  const PATRONES = {marcar: [12, 40, 18], desmarcar: [8], serie: [20, 50, 20], record: [15, 30, 15, 30, 15, 30, 60],
                    descanso: [40, 120, 40, 120, 80], error: [80, 60, 80], dia: [20, 60, 20, 60, 40, 100, 90]};
  // lo que ya hace vibrar calma.js al tocarlo (su selector): en iOS sin app no se repite el toque
  const TOCA_CALMA = ".fila, .bx, .c-dock a, .c-h-pie button, .c-pil, .c-cal-rej button, .mas-tarea, [data-toque]";
  let calmaToco = -1e9, generico = null, espera = 0;
  if (navegador) {
    addEventListener("click", e => { if (e.target.closest?.(TOCA_CALMA)) calmaToco = performance.now(); }, true);
    // Dentro de la app, vibrate() (el toque genérico de calma.js) llega por otro canal: se deja para el final del
    // gesto y, si en ese mismo gesto hay una vibración con patrón, se queda solo ella. Si no, nada cambia.
    if (window.HoyApp && navigator.vibrate) {
      const original = navigator.vibrate.bind(navigator);
      generico = p => { clearTimeout(espera); espera = setTimeout(() => original(p), 0); return true; };
      try { navigator.vibrate = generico; } catch { generico = null; }
    }
  }
  function vibra(patron) {
    if (!navegador || !PATRONES[patron]) return;
    clearTimeout(espera);
    if (app()) return manda({accion: "haptica", patron});
    if (navigator.vibrate) return void navigator.vibrate(PATRONES[patron]);
    // Safari no vibra; calma.js tiene el truco del interruptor (un solo toque), salvo que ya lo haya dado
    if (performance.now() - calmaToco > 250) window.calma?.vibra?.();
  }

  // ---------- sonidos ----------
  let sonidos = lee("tom-sonidos") === "1", ac = null;
  function contexto() {
    if (!ac) {
      const C = window.AudioContext || window.webkitAudioContext;
      if (!C) return null;
      // «ambient»: respeta el interruptor de silencio del iPhone y no corta la música (iOS 17+)
      try { if (navigator.audioSession) navigator.audioSession.type = "ambient"; } catch { /* sin audioSession */ }
      try { ac = new C(); } catch { return null; }
    }
    if (ac.state === "suspended") ac.resume().catch(() => {});
    return ac;
  }
  // el AudioContext nace en un gesto (si no, iOS lo deja mudo); así el fin del descanso, que no lo es, ya suena
  if (navegador) for (const t of ["pointerdown", "keydown"]) addEventListener(t, () => { if (sonidos) contexto(); }, {capture: true, passive: true});
  function tono(a, f, t0, dur, tipo = "sine", vol = .15) {
    const o = a.createOscillator(), g = a.createGain(), t = a.currentTime + t0;
    o.type = tipo;
    o.frequency.value = f;
    g.gain.setValueAtTime(0, t);
    g.gain.linearRampToValueAtTime(vol, t + .005);
    g.gain.exponentialRampToValueAtTime(.0001, t + dur);
    o.connect(g).connect(a.destination);
    o.start(t);
    o.stop(t + dur + .05);
  }
  // los del probador que eligió Yago: clic de madera, campanita de dos notas, el error grave y el fin del descanso
  const SONIDOS = {
    clic: a => { tono(a, 1800, 0, .03, "triangle", .2); tono(a, 900, .005, .05, "sine", .1); },
    suelta: a => { tono(a, 1200, 0, .03, "triangle", .12); },
    campana: a => { tono(a, 1046.5, 0, .9, "sine", .14); tono(a, 2093, 0, .5, "sine", .035); tono(a, 1318.5, .14, 1.1, "sine", .14); tono(a, 2637, .14, .6, "sine", .035); },
    error: a => { tono(a, 220, 0, .18, "triangle", .18); tono(a, 185, .16, .25, "triangle", .18); },
    descanso: a => { tono(a, 784, 0, .25, "sine", .14); tono(a, 784, .22, .25, "sine", .14); tono(a, 1175, .44, .7, "sine", .15); },
  };
  function suena(nombre) {
    if (!navegador || !sonidos || !SONIDOS[nombre]) return false;
    // sin contexto aún, solo si estamos dentro de un gesto (acaban de activarlos en Ajustes, por ejemplo)
    const a = ac ? contexto() : navigator.userActivation?.isActive ? contexto() : null;
    if (!a) return false;
    try { SONIDOS[nombre](a); return true; } catch { return false; }
  }
  // lo que pasa, en vibración y (si está activado) en sonido, de una vez
  const SUENA = {marcar: "clic", desmarcar: "suelta", serie: "clic", record: "campana", descanso: "descanso", error: "error", dia: "campana"};
  function avisa(patron) { vibra(patron); return suena(SUENA[patron]); }
  function ponAjustes(aj) {
    sonidos = aj?.sonidos === true;
    pon("tom-sonidos", sonidos ? "1" : null);
  }

  // ---------- inclinación ----------
  const oyentes = new Set();
  let activa = false, ultima = -1e9, enNavegador = false;
  const hay = () => navegador && performance.now() - ultima < 700;
  if (navegador) addEventListener("tom-inclinacion", e => {
    const d = e.detail || {};
    if (!Number.isFinite(d.x) || !Number.isFinite(d.y)) return;
    ultima = performance.now();
    const g = {x: entre(d.x, -1, 1), y: entre(d.y, -1, 1)};
    for (const f of oyentes) f(g);
  });
  // beta (adelante/atrás) y gamma (a los lados) del navegador → la gravedad en la pantalla, como la manda la app
  const deOrientacion = (beta, gamma) => ({x: entre(Math.sin(gamma * Math.PI / 180), -1, 1), y: entre(Math.sin(beta * Math.PI / 180), -1, 1)});
  const orienta = e => {
    if (e.beta == null || e.gamma == null) return;
    dispatchEvent(new CustomEvent("tom-inclinacion", {detail: deOrientacion(e.beta, e.gamma)}));
  };
  // La app apaga los sensores en cada carga: se piden al cargar y cada vez que la página vuelve a verse.
  function sincroniza(forzar) {
    if (!navegador) return;
    const quiere = oyentes.size > 0 && document.visibilityState === "visible" && !quieto();
    if (quiere === activa && !forzar) return;
    activa = quiere;
    if (app()) manda({accion: "inclinacion", activa});
    else if (enNavegador) (quiere ? addEventListener : removeEventListener)("deviceorientation", orienta);
  }
  function escucha(fn) {
    oyentes.add(fn);
    sincroniza();
    return () => { oyentes.delete(fn); sincroniza(); };
  }
  // En el navegador, solo si se toca el fantasma: iOS pide permiso y tiene que ser dentro de ese toque
  async function permiso() {
    if (!navegador || app() || enNavegador || !("DeviceOrientationEvent" in window)) return;
    try {
      if (typeof DeviceOrientationEvent.requestPermission === "function" && await DeviceOrientationEvent.requestPermission() !== "granted") return;
    } catch { return; }
    enNavegador = true;
    pon("tom-inclinacion", "1");
    activa = false;
    sincroniza();
  }
  if (navegador) {
    document.addEventListener("visibilitychange", () => sincroniza(document.visibilityState === "visible"));
    addEventListener("pagehide", () => { if (activa) { activa = false; if (app()) manda({accion: "inclinacion", activa: false}); } });
    addEventListener("pageshow", e => { if (e.persisted) sincroniza(true); });
    // ya dio permiso otro día: en Android basta; en iOS, si Safari lo recuerda, contesta sin preguntar
    if (!window.HoyApp && lee("tom-inclinacion") === "1" && "DeviceOrientationEvent" in window) {
      const pide = DeviceOrientationEvent.requestPermission;
      (typeof pide === "function" ? pide.call(DeviceOrientationEvent).catch(() => "no") : Promise.resolve("granted"))
        .then(r => { if (r === "granted") { enNavegador = true; activa = false; sincroniza(); } });
    }
  }

  // ---------- tarjetas con profundidad (Hoy) ----------
  // La raíz lleva --inc-rot (para `rotate`) y --inc-x/--inc-y (de -1 a 1, para las capas). Mide contra una
  // postura que se adapta despacio: lo que mueve las tarjetas es inclinar, no cómo sueles sujetar el móvil.
  // Nada mientras se hace scroll o se toca: vuelven a su sitio.
  function profundidad(raiz, grados = 5) {
    if (!navegador || !raiz) return;
    let base = null, objetivo = {x: 0, y: 0}, ahora = {x: 0, y: 0}, parado = 0, tocando = false, pedido = false;
    const para = ms => { parado = Math.max(parado, performance.now() + ms); objetivo = {x: 0, y: 0}; pide(); };
    addEventListener("scroll", () => para(450), {passive: true, capture: true});
    addEventListener("pointerdown", () => { tocando = true; para(0); }, {passive: true, capture: true});
    for (const t of ["pointerup", "pointercancel"]) addEventListener(t, () => { tocando = false; para(400); }, {passive: true, capture: true});
    const pinta = () => {
      const m = Math.hypot(ahora.x, ahora.y);
      raiz.style.setProperty("--inc-x", ahora.x.toFixed(3));
      raiz.style.setProperty("--inc-y", ahora.y.toFixed(3));
      raiz.style.setProperty("--inc-rot", m < .002 ? "none" : `${(-ahora.y / m).toFixed(3)} ${(ahora.x / m).toFixed(3)} 0 ${(Math.min(1, m) * grados).toFixed(2)}deg`);
    };
    const paso = () => {
      ahora = {x: ahora.x + (objetivo.x - ahora.x) * .15, y: ahora.y + (objetivo.y - ahora.y) * .15};
      if (Math.abs(objetivo.x - ahora.x) + Math.abs(objetivo.y - ahora.y) < .002) ahora = {...objetivo};
      pinta();
      if (ahora.x !== objetivo.x || ahora.y !== objetivo.y) requestAnimationFrame(paso); else pedido = false;
    };
    function pide() { if (!pedido) { pedido = true; requestAnimationFrame(paso); } }
    escucha(g => {
      if (quieto()) return;
      raiz.classList.add("inclina");
      base = base ? {x: base.x + (g.x - base.x) * .02, y: base.y + (g.y - base.y) * .02} : {...g};
      if (tocando || performance.now() < parado) return;
      objetivo = {x: entre((g.x - base.x) / .35, -1, 1), y: entre((g.y - base.y) / .35, -1, 1)};
      pide();
    });
  }

  // ---------- cifras que se descifran ----------
  // los dígitos que aún no se han fijado, al azar; lo demás (puntos, «h», «kg») queda quieto: el ancho no baila
  const revuelve = (fin, fijos, azar = Math.random) => [...fin].map((c, i) => (i < fijos || !/\d/.test(c) ? c : String(azar() * 10 | 0))).join("");
  function descifra(el, texto, ms = 650) {
    if (!el) return;
    const nodo = el.firstChild?.nodeType === 3 ? el.firstChild : null, escribe = t => { if (nodo) nodo.data = t; else el.textContent = t; };
    clearInterval(el._descifra);
    if (quieto()) return escribe(texto);
    const t0 = performance.now(), n = texto.length;
    const tic = () => {
      const fijos = Math.floor((performance.now() - t0) / ms * n * 1.15);
      if (fijos >= n) { clearInterval(el._descifra); return escribe(texto); }
      escribe(revuelve(texto, fijos));
    };
    tic();
    el._descifra = setInterval(tic, 35);
  }
  // la primera vez de cada cifra en esta carga, descifrándose; después, contando como siempre (calma.cuenta)
  const vistas = new Set();
  function cifra(el, valor, fmt = String, clave = el?.id) {
    if (!el) return;
    if (!vistas.has(clave)) {
      vistas.add(clave);
      el.dataset.valor = valor;
      return descifra(el, fmt(valor));
    }
    if (window.calma?.cuenta) calma.cuenta(el, valor, fmt, 700); else el.textContent = fmt(valor);
  }

  // ---------- la planta de la racha (Hoy) ----------
  // Crece con la mejor racha (etapas 0 a 7). Se mustia si ayer se rompió una racha de 2 días o más, más larga
  // que la mejor que sigue viva, y aún no se ha vuelto a hacer hoy: marcarlo la hace crecer otra vez.
  // hs: [{n, racha, rota, hecho}] como los manda /api/hoy
  function planta(hs) {
    const mejor = hs.reduce((a, h) => (h.racha > (a?.racha ?? -1) ? h : a), null);
    const perdida = hs.filter(h => !h.hecho && (h.rota || 0) >= 2).sort((a, b) => b.rota - a.rota)[0];
    if (perdida && perdida.rota > (mejor?.racha || 0)) return {etapa: Math.min(7, perdida.rota), mustia: true, de: perdida};
    return {etapa: Math.min(7, mejor?.racha || 0), mustia: false, de: mejor};
  }
  const ETAPAS = ["Semilla", "Brote", "Dos hojas", "Tallo", "Cuatro hojas", "Capullo", "Flor", "En plena flor"];
  // pixel art en una rejilla de 14 × 18 (la del probador); k va de .6 a 1 mientras crece
  function pintaPlanta(cv, {etapa, mustia}, k = 1) {
    const P = 6, W = 14, Hh = 18, d = navegador ? devicePixelRatio || 1 : 1;
    if (cv.width !== W * P * d) { cv.width = W * P * d; cv.height = Hh * P * d; }
    const x = cv.getContext("2d");
    x.setTransform(d, 0, 0, d, 0, 0);
    x.clearRect(0, 0, W * P, Hh * P);
    const px = (i, j, c) => { x.fillStyle = c; x.fillRect(i * P, j * P, P, P); };
    const cx = 7, base = Hh - 4, caer = mustia ? 1 : 0;
    const tallo = mustia ? "#B8B07A" : "#CDE77F", hoja = mustia ? "#CFC48C" : "#E6F5B0", flor = mustia ? "#C9A3A3" : etapa >= 6 ? "#F4A6C0" : "#F1F7C8";
    for (let i = -4; i <= 4; i++) for (let j = 0; j < 3; j++) px(cx + i, base + j, j === 0 ? "#C77B4E" : "#A35F38");
    const alto = Math.round([0, 1, 3, 5, 6, 7, 8, 8][etapa] * (1 - .15 * caer) * k), lad = j => (caer ? Math.round(j * j * .03) : 0);
    for (let j = 1; j <= alto; j++) px(cx + lad(j), base - j, tallo);
    const l = lad(alto);
    if (etapa === 0) px(cx, base - 1, "#C77B4E");
    if (etapa >= 2 && k > .7) { px(cx - 1, base - 2, hoja); px(cx - 2, base - 3 + caer, hoja); px(cx + 1, base - 2, hoja); px(cx + 2, base - 3 + caer, hoja); }
    if (etapa >= 4 && k > .8) { px(cx - 1 + l, base - 5, hoja); px(cx - 2 + l, base - 6 + caer, hoja); px(cx + 1 + l, base - 5, hoja); px(cx + 2 + l, base - 6 + caer, hoja); }
    if (etapa >= 5 && k > .9) {
      px(cx + l, base - alto - 1, flor);
      if (etapa >= 6) { px(cx - 1 + l, base - alto - 1, flor); px(cx + 1 + l, base - alto - 1, flor); px(cx + l, base - alto - 2, flor); px(cx + l, base - alto, mustia ? "#B39A55" : "#FFD166"); }
      if (etapa >= 7) { px(cx - 2 + l, base - alto - 1, flor); px(cx + 2 + l, base - alto - 1, flor); px(cx + l, base - alto - 3, flor); px(cx - 1 + l, base - alto - 2, flor); px(cx + 1 + l, base - alto - 2, flor); }
    }
  }
  // repinta la planta; si ha cambiado (o es la primera vez), crece con un rebote
  function ponPlanta(cv, estado) {
    if (!cv) return;
    const firma = `${estado.etapa}${estado.mustia}`;
    if (cv.dataset.firma === firma) return;
    cv.dataset.firma = firma;
    cv.setAttribute("aria-label", `Planta de la racha: ${estado.mustia ? "mustia" : ETAPAS[estado.etapa].toLowerCase()}`);
    if (quieto()) return pintaPlanta(cv, estado);
    const t0 = performance.now(), ms = 800, rebote = p => 1 + 2.70158 * (p - 1) ** 3 + 1.70158 * (p - 1) ** 2;
    const paso = t => {
      const p = Math.min(1, (t - t0) / ms);
      pintaPlanta(cv, estado, .6 + .4 * Math.min(1.05, rebote(p)));
      if (p < 1) requestAnimationFrame(paso);
    };
    requestAnimationFrame(paso);
  }

  return {vibra, suena, avisa, ponAjustes, escucha, hay, permiso, profundidad, descifra, revuelve, cifra, planta, ponPlanta,
          deOrientacion, PATRONES, SUENA, app, sonidos: () => sonidos};
})();
if (typeof window !== "undefined") window.tomVibra = tom.vibra;
if (typeof module !== "undefined") module.exports = tom;
