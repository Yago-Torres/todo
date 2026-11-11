/* Movimiento propio de todo con GSAP 3.13.0 (copiado en static/, sin CDN; aprobado por Yago el 11/11).
   - Marcar un hábito: el círculo se llena con una ola, el fantasma (o la flor) se convierte en ✓ con MorphSVG
     y la racha rueda dígito a dígito. Al desmarcar, al revés.
   - flip(): una lista que cambia de orden se desliza (Flip) en vez de saltar.
   - cielo(): el fondo de Hoy, el cielo según la hora, debajo del ASCII de calma.js.
   GSAP va con defer y puede no estar (sin red, o aún cargando): entonces todo sale quieto y en su estado final,
   igual que con «reducir movimiento». Este fichero va sin defer: las páginas pintan los círculos con circulo(). */
const mov = (() => {
  const navegador = typeof window !== "undefined";
  const quieto = () => navegador && matchMedia("(prefers-reduced-motion: reduce)").matches;
  let registrado = false;
  const gs = () => {
    if (!navegador || quieto() || !window.gsap) return null;
    if (!registrado) { gsap.registerPlugin(...[window.MorphSVGPlugin, window.Flip].filter(Boolean)); registrado = true; }
    return window.gsap;
  };
  let enMarcha = 0;   // animaciones de aquí en curso: mientras, el cielo no se repinta
  const ocupado = () => enMarcha > 0 || !!(navegador && window.calma?.ocupado?.());
  // cada animación suma al empezar y resta al acabar (va en su onComplete: Flip usa el suyo para limpiar)
  const empieza = () => { enMarcha++; return () => { enMarcha--; }; };

  // ---------- el círculo del hábito (viewBox de 20; el borde redondo de .bx lo recorta) ----------
  const FORMA = {
    fantasma: "M6.67 12.33Q6.67 6.33 10 6.33Q13.33 6.33 13.33 12.33L13.33 14.33L12.17 13.33L11 14.33L10 13.33L9 14.33L7.83 13.33L6.67 14.33Z",
    flor: "M10 7.2C11.6 7.2 12.8 8.4 12.8 10C12.8 11.6 11.6 12.8 10 12.8C8.4 12.8 7.2 11.6 7.2 10C7.2 8.4 8.4 7.2 10 7.2Z",
    check: "M6.33 10.33L7.67 9L9.17 10.67L12.83 6.67L14.17 8L9.17 13.33Z",
  };
  const OLA = "M-20 0Q-17.5 -1.6 -15 0T-10 0T-5 0T0 0T5 0T10 0T15 0T20 0T25 0T30 0T35 0T40 0V30H-20Z";
  const NIVEL = {vacio: "translate(0,22)", lleno: "translate(0,-2.5)"};
  const forma = () => (navegador && window.fantasma?.tipo?.() === "flor" ? FORMA.flor : FORMA.fantasma);
  const circulo = hecho => `<svg class="liq" viewBox="0 0 20 20" aria-hidden="true"><g class="nivel" transform="${hecho ? NIVEL.lleno : NIVEL.vacio}">` +
    `<path class="ola" d="${OLA}"/></g><path class="forma${hecho ? " ok" : ""}" d="${hecho ? FORMA.check : forma()}"/></svg>`;

  // ---------- la racha, como un cuentakilómetros ----------
  // pares [antes, después] por posición, alineados a la derecha («9» → «10» = [[" ", "1"], ["9", "0"]])
  function digitos(de, a) {
    const n = Math.max(de.length, a.length), A = de.padStart(n, " "), B = a.padStart(n, " ");
    return [...B].map((d, i) => [A[i], d]);
  }
  function rueda(el, de, a, sube) {
    const g = gs();
    if (!g || !el || de === a) return;
    const hueco = c => (c === " " ? " " : c);   // espacio del ancho de una cifra: no baila
    el.replaceChildren(...digitos(de, a).map(([o, d]) => {
      const col = document.createElement("span");
      const pila = o === d ? [d] : sube ? [o, d] : [d, o];
      col.append(...pila.map(c => Object.assign(document.createElement("span"), {textContent: hueco(c)})));
      if (o !== d) col.className = "r";
      return col;
    }));
    el.classList.add("odo");
    const fin = empieza();
    g.fromTo(el.querySelectorAll(".r"), {yPercent: sube ? 0 : -50}, {yPercent: sube ? -50 : 0, duration: .6, ease: "back.out(2)", stagger: .07,
      onComplete: () => { fin(); el.classList.remove("odo"); el.textContent = a; }});
  }

  // ---------- marcar ----------
  // La página ya ha repintado la fila en su estado nuevo: aquí se pone un momento como estaba y se anima hasta él.
  // Devuelve false si no ha animado (sin GSAP o quieto), por si la página quiere lo de antes.
  // fila: el botón .fila (la cifra de la racha, en su .rc); fmt: cómo se escribe la racha.
  function marca(fila, hecho, antes, ahora, fmt = String) {
    // vibración con patrón (y clic, si hay sonidos) de tom.js; el toque genérico de calma.js se queda en uno solo
    if (navegador) window.tom?.avisa(hecho ? "marcar" : "desmarcar");
    const g = gs(), svg = fila?.querySelector("svg.liq");
    if (!g || !svg) return false;
    const nivel = svg.querySelector(".nivel"), ola = svg.querySelector(".ola"), f = svg.querySelector(".forma");
    const morph = !!window.MorphSVGPlugin, fin = hecho ? FORMA.check : forma();
    nivel.setAttribute("transform", hecho ? NIVEL.vacio : NIVEL.lleno);
    f.setAttribute("d", hecho ? forma() : FORMA.check);
    f.classList.toggle("ok", !hecho);
    const tl = g.timeline({onComplete: empieza()});
    if (hecho) {
      tl.to(nivel, {attr: {transform: NIVEL.lleno}, duration: .75, ease: "power2.inOut"})
        .fromTo(ola, {x: 0}, {x: 10, duration: .75, ease: "none"}, 0)
        .call(() => f.classList.add("ok"), null, .3)
        .to(f, morph ? {morphSVG: fin, duration: .45, ease: "back.out(1.7)"} : {attr: {d: fin}, duration: 0}, .3);
    } else {
      tl.call(() => f.classList.remove("ok"), null, 0)
        .to(f, morph ? {morphSVG: fin, duration: .35, ease: "power2.out"} : {attr: {d: fin}, duration: 0}, 0)
        .to(nivel, {attr: {transform: NIVEL.vacio}, duration: .5, ease: "power2.in"}, 0)
        .fromTo(ola, {x: 0}, {x: -10, duration: .5, ease: "none"}, 0);
    }
    if (antes !== ahora) rueda(fila.querySelector(".rc"), fmt(antes), fmt(ahora), ahora > antes);
    return true;
  }

  // ---------- listas que se reordenan ----------
  // sel: los elementos (con data-flip-id, porque cambia() los vuelve a crear); cambia(): repinta la lista
  function flip(sel, cambia) {
    const g = gs();
    if (!g || !window.Flip) return cambia();
    const antes = Flip.getState(sel);
    cambia();
    Flip.from(antes, {targets: sel, duration: .55, ease: "power3.inOut", onComplete: empieza(),
      onEnter: els => g.fromTo(els, {opacity: 0, y: -8}, {opacity: 1, y: 0, duration: .35, delay: .2})});
  }
  // Hoy: lo planificado sin hacer arriba, lo hecho abajo y, dentro, el orden de los hábitos (el de main.hoy_habitos)
  const ordena = hs => hs.map((h, i) => [h, h.orden ?? i]).sort(([a, ia], [b, ib]) =>
    (!a.plan - !b.plan) || (a.hecho - b.hecho) || (ia - ib)).map(([h]) => h);

  // ---------- el cielo de Hoy ----------
  // hora, arriba, abajo, sol (las paradas del probador que eligió Yago)
  const PARADAS = [
    [0, "#0E1424", "#1B2238", "#3A4466"], [5.5, "#1F2A4A", "#5B4E6E", "#E58F6A"], [7.5, "#7FA6C9", "#F2C79A", "#FFD9A0"],
    [12, "#5D9BD3", "#BFDDF2", "#FFF4D6"], [17.5, "#6E8FC0", "#F3C08A", "#FFC27A"], [19.5, "#3B3F6E", "#D9746A", "#F09A5E"],
    [21.5, "#141B30", "#2B3150", "#4A4F7A"], [24, "#0E1424", "#1B2238", "#3A4466"]];
  const rgb = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16));
  function colores(hora) {
    hora = ((hora % 24) + 24) % 24;
    let i = 0;
    while (PARADAS[i + 1][0] < hora) i++;
    const [h0, ...c0] = PARADAS[i], [h1, ...c1] = PARADAS[i + 1], k = (hora - h0) / (h1 - h0 || 1);
    return c0.map((c, j) => { const A = rgb(c), B = rgb(c1[j]); return A.map((v, n) => Math.round(v + (B[n] - v) * k)); });
  }
  // Muy tenue: tiñe el fondo según la hora sin quitarle contraste al texto. En oscuro, apagado (más oscuro y menos).
  const TINTE = {claro: {alfa: .3, luz: 1}, oscuro: {alfa: .2, luz: .6}};
  function cielo() {
    if (!navegador || document.getElementById("cielo")) return;
    const cv = Object.assign(document.createElement("canvas"), {id: "cielo"});
    cv.setAttribute("aria-hidden", "true");
    document.body.prepend(cv);
    const cx = cv.getContext("2d"), oscuro = matchMedia("(prefers-color-scheme: dark)");
    const ESCALA = 8;   // se pinta a 1/8 y el navegador lo estira: son degradados, no se nota y cuesta casi nada
    let W, H, ultimo = 0, pedido = false;
    const medir = () => { W = cv.width = Math.ceil(innerWidth / ESCALA); H = cv.height = Math.ceil(innerHeight / ESCALA); };
    const pinta = ms => {
      const d = new Date(), hora = d.getHours() + d.getMinutes() / 60, {alfa, luz} = oscuro.matches ? TINTE.oscuro : TINTE.claro;
      const [arr, abj, sol] = colores(hora).map(c => c.map(v => Math.round(v * luz)));
      const css = (c, a) => `rgba(${c.join(",")},${a})`, t = ms / 1000 * .12;
      cx.clearRect(0, 0, W, H);
      const fondo = cx.createLinearGradient(0, 0, 0, H);
      fondo.addColorStop(0, css(arr, alfa)); fondo.addColorStop(1, css(abj, alfa));
      cx.fillStyle = fondo; cx.fillRect(0, 0, W, H);
      const k = Math.min(1, Math.max(0, (hora - 6) / 14)), sx = W * (.1 + .8 * k), sy = H * (.95 - Math.sin(Math.PI * k) * .7);
      for (const [bx, by, c, a, r] of [[sx, sy, sol, .9, H * .9],
        [W * (.3 + .1 * Math.sin(t)), H * (.8 + .05 * Math.cos(t * .7)), abj, .6, H * .8],
        [W * (.85 + .05 * Math.cos(t * .8)), H * (.25 + .05 * Math.sin(t)), arr, .5, H * .7]]) {
        const gr = cx.createRadialGradient(bx, by, 0, bx, by, r);
        gr.addColorStop(0, css(c, a * alfa)); gr.addColorStop(1, css(c, 0));
        cx.fillStyle = gr; cx.fillRect(0, 0, W, H);
      }
    };
    // como mucho 30 por segundo, nada con la pestaña oculta y nada mientras otra cosa se anima encima
    const bucle = ms => {
      if (document.visibilityState !== "visible" || quieto()) { pedido = false; return; }
      if (ms - ultimo >= 33 && !ocupado()) { ultimo = ms; pinta(ms); }
      requestAnimationFrame(bucle);
    };
    const arranca = () => { if (!pedido && !quieto() && document.visibilityState === "visible") { pedido = true; requestAnimationFrame(bucle); } };
    medir();
    pinta(performance.now());
    arranca();
    // quieto («reducir movimiento»): un cuadro fijo, que sigue a la hora cada minuto
    setInterval(() => { if (quieto() && document.visibilityState === "visible") pinta(performance.now()); }, 60000);
    let tm;
    addEventListener("resize", () => { clearTimeout(tm); tm = setTimeout(() => { medir(); pinta(performance.now()); }, 150); });
    oscuro.addEventListener("change", () => pinta(performance.now()));
    document.addEventListener("visibilitychange", () => { if (document.visibilityState === "visible") { pinta(performance.now()); arranca(); } });
  }

  return {circulo, marca, rueda, flip, ordena, digitos, colores, cielo, ocupado};
})();
if (typeof module !== "undefined") module.exports = mov;
