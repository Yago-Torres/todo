/* Fondos con textura (probador 3, elegidos el 11/11): rejilla de plano y curvas de nivel.
   - <body data-fondo="plano">: cuadrícula de papel milimetrado fija detrás de todo. Solo CSS.
   - <body data-fondo="curvas">: líneas topográficas que se mueven muy despacio (WebGL a media resolución, 15 fps).
   - Cualquier elemento con data-fondo="curvas" (una tarjeta) lleva las curvas dentro, con el color de la tarjeta.
   Se apagan en Ajustes («Fondos con textura», se guarda en este dispositivo). Con «reducir movimiento» las
   curvas se pintan una vez y se quedan quietas. Sin WebGL, no hay curvas y queda el fondo liso. */
(() => {
  const apagado = (() => { try { return localStorage.getItem("tom-fondos") === "no"; } catch { return false; } })();
  if (apagado) return;

  const css = document.createElement("style");
  css.textContent = `
body[data-fondo="plano"]::before { content: ""; position: fixed; inset: 0; z-index: -1; pointer-events: none;
  --rej: color-mix(in srgb, var(--acento) 9%, transparent); --rej-f: color-mix(in srgb, var(--acento) 20%, transparent);
  background-image: linear-gradient(var(--rej-f) 1px, transparent 1px), linear-gradient(90deg, var(--rej-f) 1px, transparent 1px),
                    linear-gradient(var(--rej) 1px, transparent 1px), linear-gradient(90deg, var(--rej) 1px, transparent 1px);
  background-size: 80px 80px, 80px 80px, 16px 16px, 16px 16px; background-position: -1px -1px; }
body[data-fondo="curvas"] > canvas.fondo-curvas { position: fixed; inset: 0; z-index: -1; }
[data-fondo="curvas"]:not(body) { position: relative; isolation: isolate; }
[data-fondo="curvas"]:not(body) > canvas.fondo-curvas { position: absolute; inset: 0; z-index: -1; border-radius: inherit; }
canvas.fondo-curvas { width: 100%; height: 100%; pointer-events: none; }`;
  document.head.append(css);

  const quieto = matchMedia("(prefers-reduced-motion: reduce)");
  const rgb = c => { const m = c.trim().match(/^#([0-9a-f]{6})$/i); if (!m) return [0.95, 0.96, 0.94];
    const n = parseInt(m[1], 16); return [(n >> 16 & 255) / 255, (n >> 8 & 255) / 255, (n & 255) / 255]; };
  const variable = (k, el) => getComputedStyle(el).getPropertyValue(k) || getComputedStyle(document.documentElement).getPropertyValue(k);

  const FS = `#extension GL_OES_standard_derivatives : enable
precision mediump float;uniform vec2 r;uniform float t,k,s;uniform vec3 f,a;
float h(vec2 p){p=fract(p*vec2(123.34,456.21));p+=dot(p,p+45.32);return fract(p.x*p.y);}
float n(vec2 p){vec2 i=floor(p),q=fract(p);q=q*q*(3.-2.*q);return mix(mix(h(i),h(i+vec2(1,0)),q.x),mix(h(i+vec2(0,1)),h(i+vec2(1,1)),q.x),q.y);}
float fbm(vec2 p){float v=0.,m=.5;for(int i=0;i<5;i++){v+=m*n(p);p=p*2.02+vec2(1.7,9.2);m*=.5;}return v;}
void main(){vec2 q=gl_FragCoord.xy/s;
float v=fbm(q+vec2(t*.02,t*.015))*9.;float w=max(fwidth(v),1e-4);
float lin=1.-smoothstep(.6,1.4,abs(fract(v+.5)-.5)/w);
float fu=(1.-smoothstep(.6,1.4,abs(fract(v/5.+.5)-.5)*5./w))*.8;
gl_FragColor=vec4(mix(f,a,lin*k+fu*.22),1.);}`;

  function curvas(host) {
    const c = document.createElement("canvas"); c.className = "fondo-curvas"; c.setAttribute("aria-hidden", "true");
    const gl = c.getContext("webgl", { antialias: false, alpha: false });
    if (!gl || !gl.getExtension("OES_standard_derivatives")) return;
    const sh = (tipo, s) => { const o = gl.createShader(tipo); gl.shaderSource(o, s); gl.compileShader(o); return o; };
    const pr = gl.createProgram();
    gl.attachShader(pr, sh(gl.VERTEX_SHADER, "attribute vec2 p;void main(){gl_Position=vec4(p,0,1);}"));
    gl.attachShader(pr, sh(gl.FRAGMENT_SHADER, FS)); gl.linkProgram(pr);
    if (!gl.getProgramParameter(pr, gl.LINK_STATUS)) return;
    gl.useProgram(pr);
    gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    const lp = gl.getAttribLocation(pr, "p"); gl.enableVertexAttribArray(lp); gl.vertexAttribPointer(lp, 2, gl.FLOAT, false, 0, 0);
    const U = {}; for (const k of ["r", "t", "k", "s", "f", "a"]) U[k] = gl.getUniformLocation(pr, k);
    host.prepend(c);

    const esBody = host === document.body;
    let colores = null, escala = 190;
    const leeColores = () => {
      const oscuro = rgb(variable("--fondo", host))[0] < .5;
      colores = { f: rgb(variable(esBody ? "--fondo" : "--carta", host)), a: rgb(variable("--acento", host)), k: esBody ? (oscuro ? .3 : .34) : (oscuro ? .2 : .22) };
    };
    const ajusta = () => { const b = (esBody ? { width: innerWidth, height: innerHeight } : host.getBoundingClientRect()), d = Math.min(2, devicePixelRatio || 1) * .5;
      c.width = Math.max(1, b.width * d | 0); c.height = Math.max(1, b.height * d | 0); escala = 380 * d; };
    const pinta = t => { if (!colores) leeColores();
      gl.viewport(0, 0, c.width, c.height); gl.uniform2f(U.r, c.width, c.height); gl.uniform1f(U.t, t); gl.uniform1f(U.s, escala);
      gl.uniform1f(U.k, colores.k); gl.uniform3fv(U.f, colores.f); gl.uniform3fv(U.a, colores.a); gl.drawArrays(gl.TRIANGLES, 0, 3); };
    ajusta();
    new ResizeObserver(() => { ajusta(); pinta(t); }).observe(esBody ? document.documentElement : host);
    // cambio de tema (sistema o data-theme): se releen los colores
    matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => { colores = null; pinta(t); });
    new MutationObserver(() => { colores = null; pinta(t); }).observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });

    let visible = true, t = 3 + Math.random() * 40, antes = 0;
    if (!esBody) new IntersectionObserver(es => { visible = es[0].isIntersecting; }).observe(host);
    pinta(t);
    (function paso(ahora) {
      requestAnimationFrame(paso);
      if (quieto.matches || document.hidden || !visible || (typeof calma !== "undefined" && calma.ocupado()) || ahora - antes < 66) return;   // ~15 fps: se mueve muy despacio
      t += Math.min(.2, (ahora - antes) / 1000); antes = ahora; pinta(t);
    })(0);
  }

  const arranca = () => document.querySelectorAll('[data-fondo="curvas"]').forEach(curvas);
  document.readyState === "loading" ? document.addEventListener("DOMContentLoaded", arranca) : arranca();
})();
