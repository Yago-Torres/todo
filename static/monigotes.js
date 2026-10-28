/* Monigotes de cada ejercicio: un palitos en SVG que va y viene entre la posición de inicio (a) y la de final (b),
   del color del texto y sin fondo. Lienzo de 60×40 con el suelo en y = 38.
   Articulaciones: h cabeza, n hombros, p cadera, e/w codo y mano, k/f rodilla y pie; las de "2" son el otro lado
   (en las vistas de perfil, `lado`, se pintan más tenues: es el brazo o la pierna de detrás).
   Extras: eq = líneas fijas (banco, barra, máquina); cable = [x, y, articulación]; peso = {articulación: radio}. */
(() => {
  // de pie de perfil, mirando a la derecha
  const PIE = {h: [30, 6], n: [30, 11], p: [30, 23], e: [31, 17], w: [32, 23], e2: [29, 17], w2: [30, 23],
               k: [31, 31], f: [31, 38], k2: [29, 31], f2: [29, 38]};
  // de pie de frente
  const FRENTE = {h: [30, 6], n: [30, 11], p: [30, 23], e: [26, 17], w: [25, 23], e2: [34, 17], w2: [35, 23],
                  k: [28, 31], f: [27, 38], k2: [32, 31], f2: [33, 38]};
  // sentado de frente
  const SENTADO = {h: [30, 12], n: [30, 16], p: [30, 28], e: [25, 22], w: [25, 28], e2: [35, 22], w2: [35, 28],
                   k: [26, 32], f: [26, 38], k2: [34, 32], f2: [34, 38]};
  const sube = (pose, dy) => Object.fromEntries(Object.entries(pose).map(([j, [x, y]]) => [j, [x, y - dy]]));
  const BANCO = [[12, 28, 46, 28], [15, 28, 15, 38], [43, 28, 43, 38]];

  const M = {
    "Press banca": {lado: 1, eq: BANCO, peso: {w: 3}, a: {h: [13, 24], n: [18, 25], p: [33, 25], e: [17, 31], w: [19, 21], e2: [17, 31], w2: [19, 21],
      k: [39, 25], f: [41, 37], k2: [38, 26], f2: [39, 37]}, b: {e: [19, 18], w: [19, 10], e2: [19, 18], w2: [19, 10]}},
    "Press inclinado asistido (máquina)": {lado: 1, eq: [[21, 33, 12, 14], [20, 32, 31, 32]], peso: {w: 2.5},
      a: {h: [14, 12], n: [17, 17], p: [24, 30], e: [17, 24], w: [21, 17], e2: [17, 24], w2: [21, 17], k: [32, 30], f: [33, 38], k2: [31, 31], f2: [31, 38]},
      b: {e: [23, 13], w: [29, 8], e2: [23, 13], w2: [29, 8]}},
    "Flies en máquina": {eq: [[23, 28, 37, 28]], a: {...SENTADO, e: [22, 16], w: [16, 13], e2: [38, 16], w2: [44, 13]},
      b: {e: [24, 17], w: [29, 14], e2: [36, 17], w2: [31, 14]}},
    "Press militar máquina": {peso: {w: 2, w2: 2}, eq: [[23, 28, 37, 28]], a: {...SENTADO, e: [23, 21], w: [23, 14], e2: [37, 21], w2: [37, 14]},
      b: {e: [25, 10], w: [26, 3], e2: [35, 10], w2: [34, 3]}},
    "Elevaciones laterales": {peso: {w: 2, w2: 2}, a: {...FRENTE, e: [27, 17], w: [26, 23], e2: [33, 17], w2: [34, 23]},
      b: {e: [23, 12], w: [17, 12], e2: [37, 12], w2: [43, 12]}},
    "Tríceps pulldown en polea": {lado: 1, cable: [[42, 1, "w"]], a: {...PIE, e: [32, 18], w: [37, 12], e2: [31, 18], w2: [36, 12]},
      b: {w: [33, 25], w2: [32, 25]}},
    "Flies en polea": {cable: [[4, 2, "w"], [56, 2, "w2"]], a: {...FRENTE, e: [22, 10], w: [16, 8], e2: [38, 10], w2: [44, 8]},
      b: {e: [25, 15], w: [29, 19], e2: [35, 15], w2: [31, 19]}},
    "Fondos en paralelas": {lado: 1, eq: [[24, 21, 42, 21], [40, 21, 40, 38]],
      a: {h: [31, 7], n: [31, 12], p: [30, 25], e: [31, 16], w: [32, 21], e2: [31, 16], w2: [32, 21], k: [28, 31], f: [33, 34], k2: [28, 31], f2: [33, 34]},
      b: {h: [32, 13], n: [31, 18], p: [30, 30], e: [24, 17], e2: [24, 17], k: [28, 36], f: [33, 38], k2: [28, 36], f2: [33, 38]}},
    "Dominadas": {eq: [[14, 3, 46, 3]],
      a: {h: [30, 10], n: [30, 14], p: [30, 26], e: [26, 9], w: [23, 3], e2: [34, 9], w2: [37, 3], k: [29, 32], f: [28, 37], k2: [31, 32], f2: [32, 37]},
      b: {h: [30, 3], n: [30, 8], p: [30, 20], e: [21, 9], e2: [39, 9], k: [29, 26], f: [28, 31], k2: [31, 26], f2: [32, 31]}},
    "Remo bajo (máquina)": {lado: 1, eq: [[42, 26, 42, 36], [14, 33, 30, 33]], cable: [[50, 30, "w"]],
      a: {h: [26, 14], n: [25, 19], p: [22, 32], e: [32, 21], w: [38, 23], e2: [32, 21], w2: [38, 23], k: [31, 27], f: [40, 31], k2: [30, 28], f2: [40, 33]},
      b: {h: [23, 14], n: [22, 19], e: [15, 23], w: [23, 24], e2: [15, 23], w2: [23, 24]}},
    "Face pull en polea": {lado: 1, cable: [[56, 6, "w"]], a: {...PIE, e: [36, 12], w: [42, 10], e2: [35, 12], w2: [41, 10]},
      b: {e: [24, 9], w: [32, 7], e2: [25, 9], w2: [33, 7]}},
    "Preacher con barra Z": {lado: 1, eq: [[31, 19, 40, 29]], peso: {w: 1.6},
      a: {h: [27, 10], n: [28, 15], p: [25, 29], e: [36, 23], w: [42, 30], e2: [36, 23], w2: [42, 30], k: [33, 30], f: [34, 38], k2: [32, 31], f2: [32, 38]},
      b: {w: [34, 15], w2: [34, 15]}},
    "Curl martillo": {lado: 1, peso: {w: 2}, a: {...PIE, e: [31, 17], w: [32, 24]}, b: {w: [35, 11]}},
    "Remo alto": {lado: 1, cable: [[52, 1, "w"]],
      a: {h: [28, 8], n: [29, 13], p: [27, 27], e: [36, 11], w: [42, 7], e2: [35, 11], w2: [41, 7], k: [34, 28], f: [35, 37], k2: [33, 29], f2: [33, 37]},
      b: {e: [22, 17], w: [29, 13], e2: [23, 17], w2: [30, 13]}},
    "Pull al pecho en polea": {lado: 1, cable: [[52, 1, "w"]],
      a: {...PIE, h: [32, 7], n: [31, 12], e: [36, 7], w: [41, 3], e2: [35, 7], w2: [40, 3]}, b: {e: [33, 17], w: [34, 23], e2: [32, 17], w2: [33, 23]}},
    "Curl inclinado con mancuernas": {lado: 1, eq: [[13, 9, 26, 33], [24, 32, 34, 32]], peso: {w: 2},
      a: {h: [15, 11], n: [19, 16], p: [27, 29], e: [19, 23], w: [19, 30], e2: [19, 23], w2: [19, 30], k: [34, 29], f: [36, 38], k2: [33, 30], f2: [34, 38]},
      b: {w: [24, 17]}},
    "Prensa de piernas": {lado: 1, eq: [[8, 18, 22, 36], [22, 36, 32, 36]],
      a: {h: [12, 22], n: [15, 26], p: [25, 33], e: [19, 30], w: [23, 33], e2: [19, 30], w2: [23, 33], k: [30, 22], f: [38, 25], k2: [29, 23], f2: [37, 26]},
      b: {k: [34, 26], f: [43, 20], k2: [33, 27], f2: [42, 21]}, placa: ["f"]},
    "Curl femoral en máquina": {lado: 1, eq: [[10, 27, 46, 27], [13, 27, 13, 38], [43, 27, 43, 38]], peso: {f: 2},
      a: {h: [12, 21], n: [17, 24], p: [32, 24], e: [14, 29], w: [18, 31], e2: [14, 29], w2: [18, 31], k: [40, 24], f: [48, 25], k2: [40, 24], f2: [48, 25]},
      b: {f: [38, 15], f2: [38, 15]}},
    "Extensión de cuádriceps": {lado: 1, eq: [[17, 29, 32, 29], [17, 29, 16, 11]], peso: {f: 2},
      a: {h: [21, 9], n: [21, 14], p: [22, 28], e: [24, 21], w: [27, 27], e2: [23, 21], w2: [26, 27], k: [32, 28], f: [33, 37], k2: [32, 28], f2: [33, 37]},
      b: {f: [40, 27], f2: [40, 27]}},
    "Zancadas con mancuernas": {lado: 1, peso: {w: 2}, a: {...PIE, e: [30, 17], w: [30, 23], k: [33, 31], f: [34, 38], k2: [27, 31], f2: [25, 38]},
      b: {h: [29, 11], n: [29, 16], p: [29, 28], e: [29, 22], w: [29, 28], e2: [28, 22], w2: [28, 28], k: [36, 29], f: [37, 38], k2: [24, 36], f2: [19, 38]}},
    "Peso muerto rumano con mancuernas": {lado: 1, peso: {w: 2},
      a: {...PIE, e: [30, 17], w: [31, 23]},
      b: {h: [43, 18], n: [38, 20], p: [25, 22], e: [38, 26], w: [38, 32], e2: [37, 26], w2: [37, 32], k: [28, 30], f: [29, 38], k2: [27, 30], f2: [28, 38]}},
    "Elevación de gemelos": {lado: 1, eq: [[22, 38, 40, 38]], a: PIE, b: {...sube(PIE, 3), f: [32, 38], f2: [30, 38]}},
    "Dead bug": {lado: 1,
      a: {h: [12, 31], n: [17, 32], p: [31, 32], e: [17, 25], w: [17, 18], e2: [17, 25], w2: [17, 18], k: [31, 24], f: [38, 24], k2: [31, 24], f2: [38, 24]},
      b: {e: [12, 30], w: [6, 29], k: [38, 30], f: [46, 32]}},
    "Plancha frontal": {lado: 1,
      a: {h: [47, 26], n: [42, 29], p: [27, 30], e: [42, 36], w: [48, 37], e2: [42, 36], w2: [48, 37], k: [19, 32], f: [11, 35], k2: [19, 32], f2: [11, 35]},
      b: {p: [27, 31]}},
    "Plancha lateral izquierda": {
      a: {h: [49, 19], n: [44, 23], p: [30, 28], e: [44, 31], w: [50, 37], e2: [46, 16], w2: [48, 10], k: [20, 32], f: [10, 36], k2: [20, 31], f2: [10, 35]},
      b: {p: [30, 31], k: [20, 34], k2: [20, 33]}},
    "Bird dog": {lado: 1,
      a: {h: [45, 23], n: [40, 26], p: [22, 27], e: [41, 32], w: [42, 38], e2: [41, 32], w2: [42, 38], k: [22, 38], f: [13, 38], k2: [22, 38], f2: [13, 38]},
      b: {e2: [47, 25], w2: [54, 23], k2: [14, 26], f2: [6, 25]}},
    "Hollow hold": {lado: 1,
      a: {h: [16, 32], n: [20, 34], p: [31, 35], e: [14, 32], w: [8, 31], e2: [14, 32], w2: [8, 31], k: [39, 34], f: [47, 32], k2: [39, 34], f2: [47, 32]},
      b: {h: [16, 29], n: [20, 31], e: [14, 28], w: [8, 26], e2: [14, 28], w2: [8, 26], k: [39, 32], f: [47, 28], k2: [39, 32], f2: [47, 28]}},
    "Elevaciones de piernas": {lado: 1,
      a: {h: [11, 33], n: [15, 35], p: [29, 35], e: [21, 36], w: [27, 36], e2: [21, 36], w2: [27, 36], k: [37, 34], f: [45, 33], k2: [37, 34], f2: [45, 33]},
      b: {k: [31, 27], f: [33, 19], k2: [31, 27], f2: [33, 19]}},
    // la rutina de la mañana
    "Respiración profunda con brazos": {a: FRENTE, b: {e: [24, 9], w: [21, 3], e2: [36, 9], w2: [39, 3]}},
    "Saltos linfáticos suaves": {a: FRENTE, b: sube(FRENTE, 2)},
    "Giros de tronco sueltos": {a: {...FRENTE, e: [24, 15], w: [19, 18], e2: [28, 17], w2: [24, 20]},
      b: {e: [32, 17], w: [36, 20], e2: [36, 15], w2: [41, 18]}},
    "Marcha con rodillas altas": {lado: 1, a: {...PIE, e: [28, 16], w: [31, 21], e2: [33, 16], w2: [36, 12], k: [37, 22], f: [37, 30]},
      b: {e: [33, 16], w: [36, 12], e2: [28, 16], w2: [31, 21], k: [31, 31], f: [31, 38], k2: [37, 22], f2: [37, 30]}},
    "Círculos grandes de brazos": {a: {...FRENTE, e: [23, 11], w: [16, 11], e2: [37, 11], w2: [44, 11]},
      b: {e: [24, 6], w: [20, 0], e2: [36, 6], w2: [40, 0]}},
    "Jumping jacks": {a: FRENTE, b: {...sube(FRENTE, 1), e: [24, 7], w: [21, 1], e2: [36, 7], w2: [39, 1], k: [25, 30], f: [21, 37], k2: [35, 30], f2: [39, 37]}},
    "Inclinaciones laterales con brazo arriba": {a: {...FRENTE, h: [27, 7], n: [28, 12], e: [27, 18], w: [27, 23], e2: [32, 6], w2: [27, 1]},
      b: {h: [33, 7], n: [32, 12], e: [28, 6], w: [33, 1], e2: [33, 18], w2: [33, 23]}},
    "Balanceo de piernas": {lado: 1, eq: [[46, 2, 46, 38]], a: {...PIE, e: [37, 12], w: [44, 12], e2: [36, 13], w2: [44, 13], k: [37, 28], f: [43, 33]},
      b: {k: [25, 30], f: [19, 35]}},
    "Sentadillas con brazos arriba": {lado: 1, a: {...PIE, e: [34, 6], w: [37, 0], e2: [33, 6], w2: [36, 0]},
      b: {h: [33, 14], n: [31, 19], p: [23, 29], e: [37, 18], w: [43, 18], e2: [36, 18], w2: [42, 18], k: [32, 30], f: [30, 38], k2: [31, 30], f2: [29, 38]}},
    "Saltos linfáticos con brazos": {a: FRENTE, b: {...sube(FRENTE, 2), e: [24, 7], w: [21, 1], e2: [36, 7], w2: [39, 1]}},
    "Elevaciones de talones respirando": {lado: 1, a: PIE, b: {...sube(PIE, 3), f: [32, 38], f2: [30, 38], e: [34, 4], w: [37, -2], e2: [33, 4], w2: [36, -2]}},
  };
  const IGUAL = {"Elevaciones laterales en máquina": "Elevaciones laterales", "Plancha lateral derecha": "Plancha lateral izquierda"};

  const NS = "http://www.w3.org/2000/svg";
  const nodo = (t, at) => { const e = document.createElementNS(NS, t); for (const k in at) e.setAttribute(k, at[k]); return e; };
  // un atributo que va de a a b y vuelve, con una pausa en cada punta y arranque y frenada suaves
  const va = (el, attr, x, y) => {
    if (x === y) return;
    el.append(nodo("animate", {attributeName: attr, values: `${x};${y};${y};${x};${x}`, keyTimes: "0;.4;.5;.9;1",
      calcMode: "spline", keySplines: ".45 0 .55 1;0 0 1 1;.45 0 .55 1;0 0 1 1", dur: "2.4s", repeatCount: "indefinite"}));
  };
  const linea = (g, a, b, j1, j2, extra = {}) => {
    const l = nodo("line", {x1: a[j1][0], y1: a[j1][1], x2: a[j2][0], y2: a[j2][1], ...extra});
    va(l, "x1", a[j1][0], b[j1][0]); va(l, "y1", a[j1][1], b[j1][1]);
    va(l, "x2", a[j2][0], b[j2][0]); va(l, "y2", a[j2][1], b[j2][1]);
    g.append(l);
  };

  // quieto = "a" o "b": la postura sola, sin moverse (para revisar los dibujos)
  window.monigote = (nombre, quieto) => {
    const m = M[IGUAL[nombre] || nombre];
    if (!m) return null;
    const b = {...m.a, ...m.b}, a = quieto === "b" ? b : m.a;
    if (quieto) Object.assign(b, a);
    const svg = nodo("svg", {viewBox: "0 -4 60 44", class: "mono", "aria-hidden": "true"});
    const g = nodo("g", {fill: "none", stroke: "currentColor", "stroke-width": "2.2", "stroke-linecap": "round", "stroke-linejoin": "round"});
    for (const l of m.eq || []) g.append(nodo("line", {x1: l[0], y1: l[1], x2: l[2], y2: l[3], opacity: ".35", "stroke-width": "1.6"}));
    for (const [x, y, j] of m.cable || []) {
      const l = nodo("line", {x1: x, y1: y, x2: a[j][0], y2: a[j][1], opacity: ".35", "stroke-width": "1"});
      va(l, "x2", a[j][0], b[j][0]); va(l, "y2", a[j][1], b[j][1]);
      g.append(l);
    }
    // lo de detrás primero y más tenue
    const lejos = m.lado ? {opacity: ".4"} : {};
    linea(g, a, b, "n", "e2", lejos); linea(g, a, b, "e2", "w2", lejos);
    linea(g, a, b, "p", "k2", lejos); linea(g, a, b, "k2", "f2", lejos);
    linea(g, a, b, "n", "p"); linea(g, a, b, "p", "k"); linea(g, a, b, "k", "f");
    linea(g, a, b, "n", "e"); linea(g, a, b, "e", "w");
    for (const j of m.placa || []) {
      const l = nodo("line", {x1: a[j][0] + 1, y1: a[j][1] - 5, x2: a[j][0] + 3, y2: a[j][1] + 4, opacity: ".5"});
      va(l, "x1", a[j][0] + 1, b[j][0] + 1); va(l, "y1", a[j][1] - 5, b[j][1] - 5);
      va(l, "x2", a[j][0] + 3, b[j][0] + 3); va(l, "y2", a[j][1] + 4, b[j][1] + 4);
      g.append(l);
    }
    // la cabeza, rellena; los pesos, discos rellenos
    const cab = nodo("circle", {cx: a.h[0], cy: a.h[1], r: 3.4, fill: "currentColor", stroke: "none"});
    va(cab, "cx", a.h[0], b.h[0]); va(cab, "cy", a.h[1], b.h[1]);
    g.append(cab);
    for (const [j, r] of Object.entries(m.peso || {})) {
      const c = nodo("circle", {cx: a[j][0], cy: a[j][1], r, fill: "currentColor", stroke: "none"});
      va(c, "cx", a[j][0], b[j][0]); va(c, "cy", a[j][1], b[j][1]);
      g.append(c);
    }
    svg.append(g);
    return svg;
  };
  window.monigote.nombres = [...Object.keys(M), ...Object.keys(IGUAL)];
})();
