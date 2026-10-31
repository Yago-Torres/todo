/* La mascota: un fantasma de píxeles o la flor de boli que dibujó Aitana. Cambia de cara y de forma según lo
   que pase, hace cosas por su cuenta y a veces se da un paseo por la página. Cuál es y cómo es sale de Ajustes.
   Se coloca solo en la cabecera (header.top) de cada página y pide /api/fantasma; Hoy, que ya tiene esos
   datos, se los da con ajusta(H.ajustes) y lee(H). refresca() vuelve a preguntar y salta si hay un hábito
   más hecho; reacciona(estado, ms) lo cambia un momento; emote(nombre) le hace hacer algo.
   Lo animado va con anime.js (ya está en todas las páginas): nada se repinta entero, así que un gesto
   empieza siempre desde donde está el fantasma. Sin anime.js o con «reducir movimiento» se queda quieto. */
const fantasma = (() => {
  const POR_DEFECTO = {tipo: "fantasma", semilla: 14, grumos: .2, pera: .35, cola: -12, flecos: 4, fleco: 10, ancho: 26, alto: 73,
                       ojoI: 4.5, ojoD: 4.5, sep: 14, ojosY: .38, color: "#CDE77F", extra: "", rubor: false, paseo: true, px: 5};
  // cómo se deforma en cada estado: a ancho, h alto, fl flecos, ro cuánto enrojece
  const ESTADOS = {
    reposo: {a: 1, h: 1, fl: 1, ro: 0}, contento: {a: 1.06, h: .95, fl: .8, ro: 0}, feliz: {a: 1.1, h: .9, fl: .7, ro: 0},
    animo: {a: .96, h: 1.05, fl: 1, ro: 0}, enfadado: {a: 1.12, h: .94, fl: .85, ro: 1},
    dormido: {a: 1.14, h: .72, fl: .45, ro: 0}, ausente: {a: .82, h: 1.12, fl: 1.5, ro: 0},
  };
  // la flor no se deforma: p pétalos abiertos o recogidos, bi y bd cuánto suben los brazos, pi y pd las piernas, ro enrojece
  const ESTADOS_FLOR = {
    reposo: {p: 1, bi: 0, bd: 0, pi: 0, pd: 0, ro: 0}, contento: {p: 1.05, bi: 11, bd: -11, pi: 0, pd: 0, ro: 0},
    feliz: {p: 1.1, bi: 30, bd: -30, pi: 12, pd: -8, ro: 0}, animo: {p: .98, bi: 0, bd: -34, pi: 0, pd: 0, ro: 0},
    enfadado: {p: 1.06, bi: -24, bd: 24, pi: -6, pd: 6, ro: 1}, dormido: {p: .88, bi: -38, bd: 38, pi: 8, pd: -8, ro: 0},
    ausente: {p: .8, bi: -52, bd: 52, pi: 4, pd: -4, ro: 0},
  };
  const esFlor = () => A.tipo === "flor", estado = e => (esFlor() ? ESTADOS_FLOR : ESTADOS)[e];
  const TINTA = "#1E211C", HUMO = "#A3A892", BLANCO = "#F7F8F2";
  const mov = () => !!window.anime && !matchMedia("(prefers-reduced-motion: reduce)").matches;
  const entre = (a, b) => a + Math.random() * (b - a);
  const uno = xs => xs[Math.floor(Math.random() * xs.length)];

  document.head.insertAdjacentHTML("beforeend", `<style>
    header.top { position: relative; min-height: 72px; padding-right: 72px; }
    #fantasma { position: absolute; right: 2px; top: 0; width: 60px; height: 72px; cursor: pointer; -webkit-tap-highlight-color: transparent; }
    #fantasma.pasea { position: fixed; right: auto; z-index: 140; pointer-events: none; }
    #fantasma svg { display: block; width: 100%; height: 100%; overflow: visible; transition: transform .25s; }
    #fantasma.izq svg { transform: scaleX(-1); }
    #fantasma .flota { animation: f-flota 3.6s ease-in-out infinite; }
    #fantasma .sombra { transform-box: fill-box; transform-origin: center; animation: f-sombra 3.6s ease-in-out infinite; }
    #fantasma .vaiven { transform-box: fill-box; transform-origin: 50% 0; }
    #fantasma .mec { transform-box: fill-box; transform-origin: 50% 100%; transition: opacity .8s; }
    #fantasma .gesto, #fantasma .ojo { transform-box: fill-box; transform-origin: center; }
    #fantasma .fa { animation: f-a 1.1s infinite; } #fantasma .fb { animation: f-b 1.1s infinite; }
    header.top.con-flor { padding-right: 126px; }
    #fantasma.flor { width: 120px; height: 66px; }
    #fantasma.flor .mec { fill: none; stroke: currentColor; stroke-width: .72; stroke-linecap: round; stroke-linejoin: round; }
    #fantasma.flor .brazo, #fantasma.flor .pierna { transform-box: view-box; }
    #fantasma.flor .mano { transform-box: fill-box; transform-origin: center; }
    #fantasma.flor .fa { animation-duration: .5s; } #fantasma.flor .fb { animation-duration: .5s; }
    @keyframes f-flota { 0%, 100% { transform: translateY(0); } 50% { transform: translateY(-5px); } }
    @keyframes f-sombra { 0%, 100% { transform: scale(1); } 50% { transform: scale(.8); } }
    @keyframes f-a { 0%, 49% { opacity: 1; } 50%, 100% { opacity: 0; } }
    @keyframes f-b { 0%, 49% { opacity: 0; } 50%, 100% { opacity: 1; } }
    @media (prefers-reduced-motion: reduce) { #fantasma * { animation: none !important; } #fantasma .fb { display: none; } }
  </style>`);

  const azar = a => () => {
    a = a + 0x6D2B79F5 | 0;
    let t = Math.imul(a ^ a >>> 15, 1 | a);
    t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
    return ((t ^ t >>> 14) >>> 0) / 4294967296;
  };
  const mezcla = (a, b, t) => "#" + [1, 3, 5].map(i => Math.round(parseInt(a.slice(i, i + 2), 16) * (1 - t) + parseInt(b.slice(i, i + 2), 16) * t)
    .toString(16).padStart(2, "0")).join("");

  // un punto de una curva de Bézier de cualquier grado, y n puntos de ella
  const punto = (c, t) => { let q = c; while (q.length > 1) q = q.slice(1).map((b, i) => [q[i][0] + (b[0] - q[i][0]) * t, q[i][1] + (b[1] - q[i][1]) * t]); return q[0]; };
  const tramo = (c, n) => Array.from({length: n}, (_, i) => punto(c, i / n));

  // el contorno del cuerpo como lista de puntos; fase 0 y 1 son los dos momentos de los flecos
  function contorno(p, fase) {
    const R = azar(p.semilla), cx = 80, yb = 122, h = p.alto, yt = yb - h, c = p.cola, g = p.grumos;
    const wt = p.ancho * (1 - p.pera * .45), wb = p.ancho * (1 + p.pera * .3), n = Math.round(p.flecos), w = 2 * wb / n;
    const j = (R() - .5) * g * 30, k = (R() - .5) * g * 30, top = (R() - .5) * g * 24;
    const out = [...tramo([[cx - wb + c, yb], [cx - wb + c * .2 + j, yt + h * .38], [cx - wt, yt + Math.abs(top) * .3], [cx + top, yt]], 24),
                 ...tramo([[cx + top, yt], [cx + wt, yt - Math.abs(top) * .3], [cx + wb + c * .2 + k, yt + h * .38], [cx + wb + c, yb]], 24)];
    let x = cx + wb + c, y = yb;
    for (let i = 0; i < n; i++) {
      const hd = p.fleco * (1 + g * (R() - .5) * 3) * (1 + .38 * Math.sin(i * 1.9 + fase * Math.PI)), e = i === n - 1 ? yb : yb + (R() - .5) * g * 12;
      out.push(...tramo([[x, y], [x - w / 2 + Math.sin(fase * Math.PI + i) * 2, Math.min(156, yb + hd * 1.7)], [x - w, e]], 8));
      x -= w; y = e;
    }
    return out;
  }

  // el contorno pasado a cuadraditos
  function pixeles(P, s) {
    const dentro = (x, y) => {
      let c = false;
      for (let i = 0, j = P.length - 1; i < P.length; j = i++) {
        const [a, b] = P[i], [u, v] = P[j];
        if ((b > y) !== (v > y) && x < (u - a) * (y - b) / (v - b) + a) c = !c;
      }
      return c;
    };
    let r = "";
    for (let y = 0; y < 165; y += s) for (let x = 10; x < 155; x += s) if (dentro(x + s / 2, y + s / 2)) r += `M${x} ${y}h${s}v${s}h${-s}z`;
    return r;
  }

  // ---------- la flor: garabatos de boli con las medidas de su dibujo (píxeles de la foto / 10) ----------
  const CENTRO = [104, 34], n1 = v => v.toFixed(1);
  // una línea suave por una lista de puntos
  const linea = P => P.slice(1, -1).reduce((d, p, i) => `${d}Q${n1(p[0])} ${n1(p[1])} ${n1((p[0] + P[i + 2][0]) / 2)} ${n1((p[1] + P[i + 2][1]) / 2)}`, `M${n1(P[0][0])} ${n1(P[0][1])}`);
  // el trazo básico del dibujo: un óvalo a mano que va de un punto a otro. J pone el pulso, distinto en cada fotograma
  function ovillo(J, [x0, y0], [x1, y1], b, vueltas = 1) {
    const cx = (x0 + x1) / 2, cy = (y0 + y1) / 2, a = Math.hypot(x1 - x0, y1 - y0) / 2, u = (x1 - x0) / (2 * a || 1), v = (y1 - y0) / (2 * a || 1);
    const pts = [], n = Math.ceil(11 * vueltas), giro = J() * 6.3;
    for (let i = 0; i <= n; i++) {
      const t = giro + i / n * vueltas * 2 * Math.PI, k = 1 + (J() - .5) * .14, x = a * Math.cos(t) * k, y = b * Math.sin(t) * k;
      pts.push([cx + x * u - y * v, cy + x * v + y * u]);
    }
    return linea(pts);
  }
  const raya = (a, b) => `M${n1(a[0])} ${n1(a[1])}L${n1(b[0])} ${n1(b[1])}`;
  function petalos(R, J) {
    let d = "";
    for (let i = 0, n = 34; i < n; i++) {
      const g = i / n * 2 * Math.PI + (R() - .5) * .24, c = Math.cos(g), s = Math.sin(g), abajo = s > .45 ? .78 : 1, ri = 1 + (R() - .5) * .3, ro = (.78 + R() * .4) * abajo;
      const dentro = [CENTRO[0] + c * 19 * ri, CENTRO[1] + s * 14 * ri], fuera = [CENTRO[0] + c * 47 * ro, CENTRO[1] + s * 35 * ro];
      const b = 2 + R() * 2.2, lazos = 3 + Math.floor(R() * 2.4);
      for (let k = 0; k < lazos; k++) {
        const o = (R() - .5) * 7, largo = .62 + R() * .42;   // cada vuelta acaba en un sitio: los pétalos se pisan
        d += ovillo(J, [dentro[0] + (R() - .5) * 3, dentro[1] + (R() - .5) * 2.5], [dentro[0] + (fuera[0] - dentro[0]) * largo / .85 - s * o, dentro[1] + (fuera[1] - dentro[1]) * largo / .85 + c * o * .7], b * (.6 + R() * .7));
      }
      if (R() < .28) d += raya([dentro[0] + c * 5, dentro[1] + s * 4], [CENTRO[0] + c * 53 * ro, CENTRO[1] + s * 39 * ro]);
    }
    return d;
  }
  function manita(R, J, [cx, cy], r) {
    let d = ovillo(J, [cx - 2.6, cy - .8], [cx + 2.6, cy + .8], 2.4, 5) + ovillo(J, [cx - 1.4, cy + 1], [cx + 1.6, cy - 1], 1.6, 4);
    for (let i = 0, n = 9; i < n; i++) {
      const g = i / n * 2 * Math.PI + (R() - .5) * .6, l = r * (.65 + R() * .55), f = [cx + Math.cos(g) * l, cy + Math.sin(g) * l];
      d += ovillo(J, [cx, cy], f, r * (.13 + R() * .13)) + ovillo(J, [cx, cy], [f[0] + (R() - .5) * 3, f[1] + (R() - .5) * 3], r * (.1 + R() * .12));
      if (R() < .4) d += raya([cx, cy], [cx + Math.cos(g) * l * 1.35, cy + Math.sin(g) * l * 1.35]);
    }
    return d;
  }
  // el brazo: un tallo rayado de ida y vuelta, más grueso o más fino
  function tallo(R, J, a, b, w, n) {
    const l = Math.hypot(b[0] - a[0], b[1] - a[1]), nx = -(b[1] - a[1]) / l, ny = (b[0] - a[0]) / l;
    const P = Array.from({length: n + 1}, (_, i) => {
      const t = i / n, o = (i % 2 ? 1 : -1) * w * (.5 + J() * .5) * (.4 + .6 * t);
      return [a[0] + (b[0] - a[0]) * t + nx * o, a[1] + (b[1] - a[1]) * t + ny * o];
    });
    return linea(P) + raya(a, b);
  }
  // las partes de la flor en un fotograma: R es el dibujo, siempre igual; J, el pulso de ese fotograma
  function trazos(frame) {
    const s = A.semilla, R = azar(s), J = azar(s * 31 + frame * 7 + 1);
    return {
      petalos: petalos(R, J),
      bi: tallo(R, J, [85, 37.5], [31, 44.5], 2.2, 46) + tallo(R, J, [66, 39], [36, 44], 1.2, 22), mi: manita(R, J, [25, 45], 15),
      bd: tallo(R, J, [115.5, 42], [168, 37], 1, 26), md: manita(R, J, [175, 36.5], 12.5),
      pi: ovillo(J, [90, 59], [73, 79], 3.8, 2) + ovillo(J, [88, 62], [76, 77], 2.6, 2) + ovillo(J, [80, 74], [66, 86], 3.6, 2) + ovillo(J, [74, 79], [41, 84.5], 2.2, 2) + ovillo(J, [72, 82], [50, 83.5], 2.8, 2),
      pd: ovillo(J, [109, 56], [105, 79], 3.4, 3) + ovillo(J, [107, 62], [104, 74], 2.2, 2) + ovillo(J, [106, 72], [103, 88], 2.8, 2) + ovillo(J, [103, 90], [76, 91.5], 2.5, 3) + ovillo(J, [100, 88.5], [84, 92], 2.2, 2),
    };
  }
  function pintaFlor() {
    const [a, b] = [trazos(0), trazos(1)], tinta = (k, nudo) => `<path class="fa" d="${a[k]}"/><path class="fb" d="${b[k]}"/>${nudo || ""}`;
    const nudo = (x0, x1, y) => `<path d="M${x0} ${y}L${x1} ${y}" stroke-width="2.2"/>`;
    const parte = (cls, x, y, html) => `<g class="${cls}" style="transform-origin:${x}px ${y}px">${html}</g>`;
    mec.innerHTML = `<ellipse class="disco" cx="104" cy="34" rx="48" ry="35" fill="var(--fondo)" opacity=".82" stroke="none"/>
      ${parte("pierna pi", 90, 59, tinta("pi", nudo(54, 62, 82.5)))}${parte("pierna pd", 109, 56, tinta("pd", nudo(93, 97, 91.5)))}
      <g class="petalos">${tinta("petalos")}</g>
      ${parte("brazo bi", 85, 37.5, `${tinta("bi")}<g class="mano">${tinta("mi")}</g>`)}${parte("brazo bd", 115.5, 42, `${tinta("bd")}<g class="mano">${tinta("md")}</g>`)}
      <g class="cara"><g class="gesto"></g></g>`;
    [cara, gestoEl] = [".cara", ".gesto"].map(c => caja.querySelector(c));
  }
  // la cara: ojos de óvalos dentro de óvalos (uno redondeado, otro en punta) y la sonrisa torcida con su manchón
  function rostroFlor(e) {
    const J = azar(A.semilla + 5), sonrie = e === "feliz" || e === "contento", cerrados = e === "dormido" || e === "bostezo";
    const ojoI = () => `<g class="ojo"><path d="${ovillo(J, [89.5, 32.3], [101.5, 32.1], 3)}${ovillo(J, [92.5, 32.4], [98.5, 32], 1.7)}"/><path d="M95 31.6L96 31.6" stroke-width="1.8"/></g>`;
    const ojoD = () => `<g class="ojo"><path d="M105.5 33.2Q113 28.8 123 33Q113 36 105.5 33.2Z"/><path d="${ovillo(J, [109, 33.2], [118, 33], 1.1)}"/></g>`;
    const arco = (x, a) => `<path d="M${x - 5.5} 33.5Q${x} ${a} ${x + 5.5} 33.5" stroke-width="1.1"/>`;
    let ojos, sobre = "";
    if (sonrie) ojos = arco(95.5, 27.5) + arco(114, 27.5);
    else if (cerrados) ojos = arco(95.5, 36) + arco(114, 36);
    else if (e === "guino") ojos = ojoI() + arco(114, 36);
    else ojos = ojoI() + ojoD();
    if (e === "enfadado") sobre = '<path d="M88 25.5L100 30M122 26L108 30.2" stroke-width="1.5"/>';
    if (e === "animo" || e === "sorpresa") sobre = '<path d="M90 26.5Q95 24.5 100 26.5M109 26.5Q114 24.5 119 26.5" stroke-width="1"/>';
    if (e === "ausente") sobre = '<path d="M90 29L100 26M109 26L119 29" stroke-width="1"/>';
    const manchon = `<path d="M98.6 41.2L100.4 42.6" stroke-width="2.3"/>`;
    const boca = sonrie ? `${manchon}<path d="M99 42Q103 50.5 111 42Q106 44 99 42Z" fill="currentColor"/>`
      : e === "enfadado" ? `<path d="M98 45.5L100.5 43L103 45.5L105.5 43L108 45.5L110.5 43" stroke-width="1"/>`
      : e === "ausente" ? `<path d="M99 46.5Q104 41.5 110 46.5" stroke-width="1"/>`
      : e === "bostezo" ? `<path d="${ovillo(J, [101, 41], [108, 50], 3.4, 2)}"/>`
      : e === "guino" ? `${manchon}<path d="M99.5 42.5Q103 46.5 108 42" stroke-width="1"/>`
      : e === "animo" || e === "dormido" || e === "sorpresa" ? `<path d="${ovillo(J, [103, 42.5], [106, 45.5], 1.5, 2)}"/>`
      : `${manchon}<path d="M99.5 42.8Q101 46 105 46Q107.8 45.8 109.3 42.2" stroke-width=".95"/><path d="M104 45.4L105.4 43.4M106 45.1L107.2 43.2M107.6 44.4L108.5 42.8" stroke-width=".55"/>`;
    return `<g class="ojos">${ojos}</g>${sobre}${boca}`;
  }

  let A = {...POR_DEFECTO}, firma = "", caja, sitio, enAjustes = false;
  let mec, vaiven, fa, fb, sombra, cara, gestoEl, adorno, aire;
  let actual = "reposo", base = "reposo", vista = "", m = {...ESTADOS.reposo}, vuelta, bucle, tiempoCara, ultima = 0, libre = 0, repetido = "", hechos = null, paseando = false;

  const sn = v => Math.round(v / A.px) * A.px;
  const R = (x, y, w, h, c = TINTA) => `<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="${c}"/>`;
  const mapa = (filas, x, y, c) => filas.flatMap((f, j) => [...f].map((v, i) => (v === "x" ? R(x + i * A.px, y + j * A.px, A.px, A.px, c) : ""))).join("");

  // la cara, dibujada para el cuerpo en reposo: al deformarse, forma() solo la sube o la baja
  function rostro(e) {
    if (esFlor()) return rostroFlor(e);
    const s = A.px, yt = 122 - A.alto, fx = 80 + A.cola * .2, ey = yt + A.alto * A.ojosY;
    const sonrie = e === "feliz" || e === "contento", cerrados = e === "dormido" || e === "bostezo";
    let ojos = "", sobre = "";
    for (const [q, z] of [[-1, A.ojoI], [1, A.ojoD]]) {
      const X = sn(fx + q * A.sep / 2), Y = sn(ey), w = Math.max(s, sn(z * 1.6));
      if (sonrie) ojos += R(X - s, Y, s, s) + R(X, Y - s, s, s) + R(X + s, Y, s, s);
      else if (cerrados || (e === "guino" && q > 0)) ojos += R(X - s, Y, s * 3, s * .6);
      else ojos += `<g class="ojo">${R(X, Y - s, w, w + s)}</g>`;
      if (e === "animo" || e === "sorpresa") sobre += R(X - s, Y - s * 2, s * 2, s * .6);
      if (e === "ausente") sobre += R(X - s, Y - s * (q < 0 ? 2 : 3), s * 2, s * .6);
      if (e === "enfadado") sobre += R(X + (q < 0 ? -s : s), Y - s * 2, s, s * .7) + R(X, Y - s * 1.3, s, s * .7);
      if (A.extra === "gafas") sobre += `<rect x="${X + w / 2 - s * 1.4}" y="${Y - s * 2}" width="${s * 2.8}" height="${s * 3.6}" fill="none" stroke="${TINTA}" stroke-width="1.6"/>`;
      if (A.rubor) sobre += `<rect x="${X + q * s}" y="${Y + s * 2}" width="${s * 2}" height="${s}" fill="#E8927C" opacity=".7"/>`;
    }
    if (A.extra === "gafas") sobre += R(sn(fx - A.sep / 2), sn(ey) - s, sn(A.sep), 1.6);
    const X = sn(fx + 1), Y = sn(ey + Math.max(A.ojoI, A.ojoD) * 1.1 + 7);
    const boca = sonrie ? R(X - s, Y, s * 3, s * .7) + R(X, Y + s * .7, s, s * .7)
      : e === "enfadado" ? R(X - s, Y, s, s * .7) + R(X, Y + s * .7, s, s * .7) + R(X + s, Y, s, s * .7) + R(X + s * 2, Y + s * .7, s, s * .7)
      : e === "ausente" ? R(X - s, Y + s * .7, s * 3, s * .7) + R(X, Y, s, s * .7)
      : e === "bostezo" ? R(X - s, Y, s * 2, s * 3)
      : e === "guino" ? R(X, Y, s * 2, s * .7) + R(X + s * 2, Y - s * .7, s, s * .7)
      : e === "animo" || e === "dormido" || e === "sorpresa" ? R(X, Y, s, s) : R(X - s, Y, s * 2, s * .7);
    return `<g class="ojos">${ojos}</g>${sobre}${boca}`;
  }

  function pintaAdorno() {
    if (esFlor()) return pintaFlor();
    const s = A.px, y = sn(122 - A.alto), x = sn(80 + A.cola * .2);
    adorno.innerHTML = A.extra === "lazo" ? mapa(["x.x", "xxx", "x.x"], x - s * 4, y + s, "#E8556F")
      : A.extra === "gorro" ? mapa(["...x...", "..xxx..", ".xxxxx.", "xxxxxxx"], x - s * 3, y - s * 3, "#6C8EF5") : "";
  }

  // el cuerpo con la deformación que toque; lo único que se repinta mientras cambia de estado
  function forma(ya) {
    const t = performance.now();
    if (!caja || (!ya && t - ultima < 50)) return;
    ultima = t;
    if (esFlor()) {
      const q = caja.querySelector.bind(caja), mas = Math.round(Math.max(0, Math.min(1, m.ro)) * 62);
      q(".petalos").setAttribute("transform", `translate(104 34) scale(${m.p}) translate(-104 -34)`);
      q(".bi").style.rotate = `${m.bi}deg`; q(".bd").style.rotate = `${m.bd}deg`;
      q(".pi").style.rotate = `${m.pi}deg`; q(".pd").style.rotate = `${m.pd}deg`;
      mec.style.color = mas ? `color-mix(in srgb, #D9533A ${mas}%, var(--texto))` : "var(--texto)";
      return;
    }
    const p = {...A, ancho: A.ancho * m.a, alto: A.alto * m.h, fleco: Math.min(18, A.fleco * m.fl)};
    const color = mezcla(A.color, "#D9533A", Math.max(0, Math.min(1, m.ro)) * .55);
    fa.setAttribute("d", pixeles(contorno(p, 0), A.px));
    fa.setAttribute("fill", color);
    if (mov()) { fb.setAttribute("d", pixeles(contorno(p, 1), A.px)); fb.setAttribute("fill", color); }
    sombra.setAttribute("cx", 80 + A.cola * .5);
    sombra.setAttribute("rx", p.ancho * (1 + A.pera * .3) * .8);
    cara.setAttribute("transform", `translate(0 ${sn(A.alto * (1 - m.h) * (1 - A.ojosY))})`);
    adorno.setAttribute("transform", `translate(0 ${sn(A.alto * (1 - m.h))})`);
  }

  // cambiar de cara es un parpadeo: se cierra, se cambia y se abre
  function expresion(e, ya) {
    if (e === vista && !ya) return;
    vista = e;
    if (!mov() || ya) { gestoEl.innerHTML = rostro(e); return; }
    anime.animate(gestoEl, {scaleY: .15, duration: 80, ease: "inQuad", onComplete: () => {
      gestoEl.innerHTML = rostro(vista);
      anime.animate(gestoEl, {scaleY: 1, duration: 170, ease: "outBack(2)"});
    }});
  }
  const rato = (e, ms) => { expresion(e); clearTimeout(tiempoCara); tiempoCara = setTimeout(() => expresion(actual), ms); };

  // ---------- gestos: [milisegundos, posturas]; siempre acaban en la postura de reposo ----------
  const REPOSO = {x: 0, y: 0, rotate: 0, scaleX: 1, scaleY: 1};
  const GESTOS = {
    salto: [620, [{scaleX: 1.1, scaleY: .86}, {y: -18, scaleX: .93, scaleY: 1.1}, {y: 0, scaleX: 1.1, scaleY: .88}]],
    saltito: [420, [{scaleX: 1.05, scaleY: .93}, {y: -8, scaleX: .97, scaleY: 1.04}]],
    doble: [1000, [{scaleX: 1.1, scaleY: .86}, {y: -18, scaleX: .93, scaleY: 1.1}, {y: 0, scaleX: 1.1, scaleY: .88}, {y: -11, scaleX: .95, scaleY: 1.06}, {y: 0, scaleX: 1.06, scaleY: .92}]],
    voltereta: [860, [{scaleX: 1.1, scaleY: .84}, {y: -24, rotate: 180, scaleX: 1, scaleY: 1}, {y: 0, rotate: 360, scaleX: 1.1, scaleY: .88}], true],
    baile: [1300, [{rotate: -11, y: -3}, {rotate: 11, y: 0}, {rotate: -11, y: -3}, {rotate: 11, y: 0}, {rotate: -6, y: -2}]],
    meneo: [900, [{rotate: -7}, {rotate: 7}, {rotate: -5}, {rotate: 4}]],
    estira: [950, [{scaleX: 1.06, scaleY: .92}, {y: -4, scaleX: .88, scaleY: 1.2}, {y: -4, scaleX: .88, scaleY: 1.2}, {scaleX: 1.04, scaleY: .95}]],
    giro: [700, [{scaleX: .1}, {scaleX: -1}, {scaleX: .1}]],
    escondite: [1500, [{scaleX: 1.25, scaleY: .14}, {scaleX: 1.25, scaleY: .14}, {scaleX: 1.25, scaleY: .14}, {y: -8, scaleX: .92, scaleY: 1.14}]],
    estornudo: [800, [{rotate: -5, scaleY: 1.1}, {rotate: -8, scaleY: 1.13}, {rotate: 11, x: 5, scaleY: .84}]],
    empujon: [620, [{x: -5, rotate: -5}, {x: 8, rotate: 8}]],
    pataleta: [760, [{y: -6, rotate: -5}, {y: 0, scaleX: 1.08, scaleY: .92}, {y: -6, rotate: 5}, {y: 0, scaleX: 1.08, scaleY: .92}]],
    temblor: [520, [{x: -2}, {x: 2}, {x: -2}, {x: 2}, {x: -2}, {x: 2}]],
    resopla: [760, [{scaleX: 1.1, scaleY: 1.06}, {scaleX: 1.1, scaleY: 1.06}, {scaleX: .96, scaleY: .94}]],
    ronquido: [2000, [{scaleX: 1.06, scaleY: .9}, {scaleX: .98, scaleY: 1.05}]],
    vuelta: [1000, [{scaleY: .85}, {scaleX: -1, scaleY: .85}, {scaleX: 1}]],
    suspiro: [1500, [{y: -3, scaleY: 1.05}, {y: 3, scaleY: .92}]],
  };
  function gesto(n) {
    if (!mov()) return;
    const [ms, posturas, vueltaEntera] = GESTOS[n];
    libre = performance.now() + ms + 500;
    anime.animate(mec, {keyframes: vueltaEntera ? posturas : [...posturas, REPOSO], duration: ms, ease: "inOutSine",
                        onComplete: vueltaEntera ? () => anime.utils.set(mec, REPOSO) : undefined});
  }
  // lo que flota por el aire y se va: un corazón, una nota, humo, una zeta
  function suelta(html, {x = 10, y = -28, ms = 1600} = {}) {
    if (!mov()) return;
    aire.insertAdjacentHTML("beforeend", html);
    const e = aire.lastElementChild;
    anime.animate(e, {x, y, opacity: [1, 0], duration: ms, ease: "outQuad", onComplete: () => e.remove()});
  }
  const arriba = () => (esFlor() ? [104, 2] : [80 + A.cola * .2, 122 - A.alto * m.h]);
  const letra = (c, color = HUMO, tam = 14) => {
    const [x, y] = arriba();
    return `<text x="${x + (esFlor() ? 40 : A.ancho * .7)}" y="${y + 8}" font-size="${tam}" font-weight="700" fill="${color}">${c}</text>`;
  };
  const humo = () => { const [x, y] = arriba(); suelta(`<circle cx="${x + uno([-14, 14])}" cy="${y - 3}" r="3.5" fill="${HUMO}"/>`, {x: uno([-8, 8]), y: -18, ms: 1000}); };
  const anima = (sel, props) => { libre = performance.now() + (props.duration || 1000) + 400; anime.animate(caja.querySelectorAll(sel), {ease: "inOutSine", ...props}); };

  // ---------- lo que hace por su cuenta ----------
  const EMOTES = {
    mira() {
      const ojos = gestoEl.querySelector(".ojos");
      libre = performance.now() + 2200;
      const d = esFlor() ? 2.5 : 5;
      anime.animate(ojos, {keyframes: [{x: -d}, {x: -d}, {x: d}, {x: d}, {x: 0}], duration: 1900, ease: "inOutSine"});
    },
    // solo de la flor: las manos, los brazos y los pétalos se mueven por su cuenta
    saluda() { anima(".bd", {keyframes: [{rotate: -32}, {rotate: -14}, {rotate: -36}, {rotate: -14}, {rotate: -30}, {rotate: 0}], duration: 1500}); rato("contento", 1500); },
    molinillo() { anima(".mano", {rotate: 360, duration: 1400, onComplete: () => anime.utils.set(caja.querySelectorAll(".mano"), {rotate: 0})}); },
    aletea() { anima(".bi", {keyframes: [{rotate: 26}, {rotate: -8}, {rotate: 24}, {rotate: 0}], duration: 1100}); anima(".bd", {keyframes: [{rotate: -26}, {rotate: 8}, {rotate: -24}, {rotate: 0}], duration: 1100}); },
    patadita() { anima(".pi", {keyframes: [{rotate: 32}, {rotate: -4}, {rotate: 24}, {rotate: 0}], duration: 900}); },
    respira() { anima(".petalos", {keyframes: [{scale: 1.1}, {scale: 1.1}, {scale: 1}], duration: 1800}); },
    petalo() {
      const x = 62 + Math.random() * 84;
      suelta(`<path d="${ovillo(azar(9), [x, 56], [x + 9, 60], 2.2)}" fill="none" stroke="currentColor" stroke-width=".7"/>`, {x: uno([-14, 12]), y: 34, ms: 2400});
    },
    guino() { rato("guino", 700); gesto("saltito"); },
    bostezo() { rato("bostezo", 1600); gesto("estira"); },
    saltito() { gesto("saltito"); },
    salto() { gesto("salto"); },
    giro() { gesto("giro"); },
    voltereta() { rato("feliz", 1000); gesto("voltereta"); },
    baile() { rato("feliz", 1400); gesto("baile"); suelta(letra("♪", A.color)); },
    escondite() { rato("sorpresa", 1500); gesto("escondite"); },
    tararea() { gesto("meneo"); suelta(letra("♪", A.color)); setTimeout(() => suelta(letra("♫", A.color, 12), {x: 16}), 500); },
    estornudo() { rato("bostezo", 450); gesto("estornudo"); setTimeout(() => suelta(letra("!", HUMO, 16), {x: 14, y: -10, ms: 700}), 500); },
    estira() { gesto("estira"); },
    corazon() { rato("contento", 900); gesto("saltito"); suelta(letra("♥", "#E8556F", 15)); },
    meneo() { gesto("meneo"); },
    empujon() { gesto("empujon"); suelta(letra("!", A.color, 16), {x: 6, y: -14, ms: 900}); },
    pataleta() { gesto("pataleta"); humo(); },
    temblor() { gesto("temblor"); },
    resopla() { gesto("resopla"); setTimeout(humo, 300); setTimeout(humo, 500); },
    ronquido() { gesto("ronquido"); suelta(letra("Z", HUMO, 18), {x: 14, y: -26, ms: 2000}); },
    vuelta() { gesto("vuelta"); },
    suspiro() { gesto("suspiro"); },
    difumina() { libre = performance.now() + 2600; anime.animate(vaiven, {keyframes: [{opacity: .1}, {opacity: .1}, {opacity: 1}], duration: 2200, ease: "inOutSine"}); },
  };
  const POR_ESTADO = {
    reposo: ["mira", "mira", "guino", "bostezo", "saltito", "giro", "escondite", "tararea", "estornudo", "estira"],
    contento: ["corazon", "corazon", "tararea", "baile", "guino", "voltereta", "giro", "mira"],
    animo: ["mira", "meneo", "empujon", "empujon", "saltito"],
    enfadado: ["pataleta", "resopla", "temblor", "mira"],
    dormido: ["ronquido", "ronquido", "vuelta"],
    ausente: ["suspiro", "difumina", "mira"],
  };
  const FIESTAS = ["doble", "voltereta", "baile", "salto", "estira"];
  const DE_FLOR = {reposo: ["saluda", "saluda", "molinillo", "aletea", "patadita", "respira"], contento: ["saluda", "molinillo", "aletea", "respira"],
                   animo: ["saluda", "saluda"], enfadado: ["patadita", "aletea"], dormido: ["respira"], ausente: ["petalo", "petalo", "petalo"]};
  const SIN_ESTO_LA_FLOR = ["estira", "escondite"];   // estirarse o aplastarse deforma el garabato

  function solo() {
    if (!mov() || document.hidden || !caja?.firstChild || performance.now() < libre || vuelta) return;
    const xs = (POR_ESTADO[actual] || POR_ESTADO.reposo).filter(n => n !== repetido && !(esFlor() && SIN_ESTO_LA_FLOR.includes(n)))
      .concat(esFlor() ? DE_FLOR[actual] || [] : []);
    repetido = uno(xs);
    EMOTES[repetido]();
  }
  function pulso() {
    if (!mov() || document.hidden || !caja?.firstChild) return;
    if (actual === "enfadado") humo();
    if (actual === "dormido") suelta(letra("z"), {x: 12, y: -24, ms: 2400});
  }
  (function vivo() { setTimeout(() => { solo(); vivo(); }, entre(11000, 34000)); })();
  (function paseos() { setTimeout(() => { pasea(); paseos(); }, entre(70000, 200000)); })();
  setInterval(pulso, 1700);
  // el parpadeo, a ratos irregulares y a veces doble
  (function parpadea() {
    setTimeout(() => {
      const ojos = gestoEl?.querySelectorAll(".ojo");
      if (ojos?.length && mov() && !document.hidden)
        anime.animate(ojos, {keyframes: [{scaleY: .1}, {scaleY: 1}].concat(Math.random() < .2 ? [{scaleY: .1}, {scaleY: 1}] : []), duration: 170, ease: "inOutSine"});
      parpadea();
    }, entre(2200, 6500));
  })();

  // ---------- el paseo: sale de la cabecera, da una vuelta por la pantalla y vuelve ----------
  function vuela(x, y, luego) {
    const r = caja.getBoundingClientRect(), dx = x - r.left, dy = y - r.top;
    caja.classList.toggle("izq", dx < 0);
    const [ax, ay] = [anime.utils.get(caja, "x", false) || 0, anime.utils.get(caja, "y", false) || 0];
    anime.animate(caja, {x: ax + dx, y: ay + dy, duration: 500 + Math.hypot(dx, dy) * 7, ease: "inOutSine", onComplete: luego});
  }
  function pasea() {
    if (!mov() || !A.paseo || enAjustes || paseando || document.hidden || !caja?.firstChild || vuelta
        || !["reposo", "contento", "animo"].includes(actual)) return;
    const r = caja.getBoundingClientRect();
    if (r.bottom < 0 || r.top > innerHeight) return;   // la cabecera está fuera de la pantalla
    paseando = true;
    document.body.append(caja);
    caja.classList.add("pasea");
    Object.assign(caja.style, {left: r.left + "px", top: r.top + "px"});
    const sitioLibre = () => [entre(8, innerWidth - r.width - 8), entre(70, innerHeight - r.height - 110)];
    const vuelve = () => {
      const t = sitio.getBoundingClientRect();
      vuela(t.right - r.width - 2, t.top, () => {
        caja.classList.remove("pasea", "izq");
        anime.utils.set(caja, {x: 0, y: 0});
        Object.assign(caja.style, {left: "", top: ""});
        sitio.append(caja);
        paseando = false;
      });
    };
    vuela(...sitioLibre(), () => {
      solo();
      setTimeout(() => vuela(...sitioLibre(), () => { solo(); setTimeout(vuelve, entre(1500, 3000)); }), entre(1800, 3500));
    });
  }

  // ---------- estados ----------
  function cambia(e) {
    actual = e;
    expresion(e);
    bucle?.pause();
    bucle = null;
    if (!mov()) { m = {...estado(e)}; return forma(true); }
    anime.animate(m, {...estado(e), duration: 700, ease: "outElastic(1, .65)", onUpdate: () => forma(), onComplete: () => forma(true)});
    if (e === "animo") bucle = anime.animate(vaiven, {keyframes: [{rotate: -4}, {rotate: 4}, {rotate: 0}], duration: 2600, ease: "inOutSine", loop: true});
    else anime.animate(vaiven, {rotate: 0, duration: 300, ease: "outQuad"});
  }
  function monta() {
    if (caja) return caja;
    const pequeno = document.querySelector("#sitio-fantasma");
    sitio = pequeno || document.querySelector("header.top");
    if (!sitio) return null;
    enAjustes = !!pequeno;
    caja = document.createElement("div");
    caja.id = "fantasma";
    caja.onclick = () => {
      if (!enHoy() && !enAjustes && actual === "enfadado") return location.assign("/");   // lo de ayer se arregla en Hoy
      if (performance.now() < libre) return;
      rato(actual === "enfadado" ? "enfadado" : "feliz", 900);
      EMOTES[uno(["salto", "voltereta", "giro", "baile", "estornudo", "saltito"])]();
    };
    sitio.append(caja);
    return caja;
  }
  const enHoy = () => !!document.querySelector('meta[name="calma-datos"][content*="/api/hoy"]');

  function esqueleto() {
    const flor = esFlor();
    caja.classList.toggle("flor", flor);
    sitio.classList.toggle("con-flor", flor);
    caja.innerHTML = flor
      ? `<svg viewBox="6 -8 190 106" aria-hidden="true"><ellipse class="sombra" cx="82" cy="97" rx="46" ry="2" fill="#000" opacity=".2"/>
        <g class="flota"><g class="vaiven"><g class="mec"></g></g><g class="aire"></g></g></svg>`
      : `<svg viewBox="30 30 100 120" aria-hidden="true"><ellipse class="sombra" cy="148" ry="3.5" fill="#000" opacity=".2"/>
        <g class="flota"><g class="vaiven"><g class="mec"><path class="fa" shape-rendering="crispEdges"/><path class="fb" shape-rendering="crispEdges"/>
        <g class="adorno"></g><g class="cara"><g class="gesto"></g></g></g></g><g class="aire"></g></g></svg>`;
    [mec, vaiven, fa, fb, sombra, cara, gestoEl, adorno, aire] = [".mec", ".vaiven", ".fa", ".fb", ".sombra", ".cara", ".gesto", ".adorno", ".aire"].map(c => caja.querySelector(c));
  }
  // repinta lo que depende del aspecto, sin tocar lo que se esté moviendo
  function redibuja() {
    pintaAdorno();
    expresion(vista || actual, true);
    forma(true);
  }
  function pon(e, presencia) {
    if (!monta()) return;
    if (enAjustes) e = "reposo";
    base = e;
    if (!caja.firstChild) {
      esqueleto();
      actual = e;
      m = {...estado(e)};
      redibuja();
      if (mov()) anime.animate(mec, {scaleX: [.3, 1], scaleY: [.3, 1], opacity: [0, 1], duration: 480, ease: "outBack(2.2)"});
    } else if (!vuelta && e !== actual) cambia(e);
    mec.style.opacity = e === "ausente" ? presencia : 1;
  }
  function reacciona(e, ms = 1600) {
    if (!monta() || !caja.firstChild) return;
    clearTimeout(vuelta);
    cambia(e);
    if (e === "feliz") {
      gesto(uno(FIESTAS));
      suelta(letra("✦", A.color), {x: 14, y: -22, ms: 1100});
    }
    vuelta = setTimeout(() => { vuelta = null; cambia(base); }, ms);
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
  // lo que llega de Ajustes: el aspecto del fantasma y, para calma.js, el nombre y la barra de abajo
  function ajusta(aj) {
    const barra = Object.entries(aj.modulos).filter(([, v]) => v.activo && v.barra).map(([k]) => `/${k}.html`);
    calma.ponPerfil({nombre: aj.nombre, barra});
    previa(aj.mascota);
  }
  function previa(mascota) {
    const f = JSON.stringify(mascota);
    if (f === firma) return;
    firma = f;
    const otro = A.tipo !== (mascota.tipo || "fantasma");
    A = {...POR_DEFECTO, ...mascota};
    if (!caja?.firstChild) return;
    if (otro) { esqueleto(); m = {...estado(actual)}; }
    redibuja();
  }
  async function refresca() {
    try {
      const r = await fetch("/api/fantasma", {credentials: "same-origin"});
      if (!r.ok) return;   // sin sesión no hay fantasma
      const d = await r.json(), n = d.habitos.filter(h => h.hecho).length;
      ajusta(d.ajustes);
      lee(d);
      if (hechos != null && n > hechos) reacciona("feliz");
      hechos = n;
    } catch { /* sin red se queda como estaba */ }
  }
  if (!enHoy()) {
    document.addEventListener("DOMContentLoaded", refresca);
    document.addEventListener("visibilitychange", () => { if (!document.hidden) refresca(); });
  }
  return {lee, ajusta, previa, refresca, reacciona, emote: n => EMOTES[n]?.(), emotes: Object.keys(EMOTES), pasea};
})();
