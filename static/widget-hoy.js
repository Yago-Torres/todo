// Widget de Hoy (todo.yagotg.dev) para la app Scriptable del iPhone.
// Anillos del día (hábitos, pasos de ayer, sueño de anoche), la próxima tarea y el 5k estimado.
//
// Primera vez: ábrelo dentro de Scriptable y pega las tres claves que te pide (las mismas que lleva el
// atajo de todo). Se guardan en el llavero de este iPhone; el script no lleva ninguna.
// Tamaños: pequeño (anillos), mediano (campo para apuntar una tarea y lo pendiente), grande (anillos, pendiente
// y los hábitos) y pantalla de bloqueo
// (redondo: los anillos; rectangular: tres líneas; en línea: una).
const WEB = "https://todo.yagotg.dev";
const CLAVES = [["todo_cf_id", "CF-Access-Client-Id (el del atajo)"], ["todo_cf_secret", "CF-Access-Client-Secret (el del atajo)"],
                ["todo_pass", "Contraseña de todo"]];
const OBJ = {pasos: 10000, sueno: 480};   // los anillos se cierran aquí (igual que en la portada)
const C = {hab: new Color("#1baf7a"), pas: new Color("#eb6834"), sue: new Color("#3987e5"),
           fondo: new Color("#171A16"), campo: new Color("#2B3028"), texto: new Color("#EEF0E8"), suave: new Color("#A3A892"), aviso: new Color("#E8B04A")};

const hm = m => `${Math.floor(m / 60)} h ${String(Math.round(m) % 60).padStart(2, "0")}`;
const miles = n => Math.round(n).toLocaleString("es-ES");
const hayClaves = () => CLAVES.every(([k]) => Keychain.contains(k));

async function pideClaves() {
  const a = new Alert();
  a.title = "Widget de Hoy";
  a.message = "Pega los datos del atajo de todo. Se guardan en el llavero de este iPhone.";
  for (const [k, n] of CLAVES) a.addSecureTextField(n, Keychain.contains(k) ? Keychain.get(k) : "");
  a.addAction("Guardar");
  a.addCancelAction("Cancelar");
  if (await a.present() === -1) return;
  CLAVES.forEach(([k], i) => { const v = a.textFieldValue(i).trim(); if (v) Keychain.set(k, v); });
}

const cabeceras = () => ({"CF-Access-Client-Id": Keychain.get("todo_cf_id"), "CF-Access-Client-Secret": Keychain.get("todo_cf_secret"),
                          "Authorization": "Bearer " + Keychain.get("todo_pass")});

async function datos() {
  const r = new Request(WEB + "/api/hoy");
  r.headers = cabeceras();
  r.timeoutInterval = 20;
  const d = await r.loadJSON();
  if (!d || !Array.isArray(d.habitos)) throw new Error(d && d.detail ? d.detail : "respuesta rara (¿claves?)");
  return d;
}

// ---------- los anillos, dibujados a mano (Scriptable no tiene arcos: un arco son muchos segmentos) ----------
function arco(dc, c, r, p, color, grosor) {
  const n = Math.max(2, Math.ceil(120 * p)), path = new Path();
  const punto = i => { const a = -Math.PI / 2 + 2 * Math.PI * p * i / n; return new Point(c + r * Math.cos(a), c + r * Math.sin(a)); };
  for (let i = 0; i <= n; i++) i ? path.addLine(punto(i)) : path.move(punto(i));
  dc.addPath(path);
  dc.setStrokeColor(color);
  dc.setLineWidth(grosor);
  dc.strokePath();
  if (p < 1) {   // puntas redondas
    dc.setFillColor(color);
    for (const pt of [punto(0), punto(n)]) dc.fillEllipse(new Rect(pt.x - grosor / 2, pt.y - grosor / 2, grosor, grosor));
  }
}
function anillos(lado, valores, grosor) {
  const dc = new DrawContext();
  dc.size = new Size(lado, lado);
  dc.opaque = false;
  dc.respectScreenScale = true;
  valores.forEach(([p, color], i) => {
    const r = lado / 2 - grosor / 2 - i * (grosor + 3);
    arco(dc, lado / 2, r, 1, new Color(color.hex, .2), grosor);
    if (p > 0) arco(dc, lado / 2, r, Math.min(1, p), color, grosor);
  });
  return dc.getImage();
}

function texto(sitio, s, tam, color, negrita) {
  const t = sitio.addText(s);
  t.font = negrita ? Font.boldSystemFont(tam) : Font.systemFont(tam);
  t.textColor = color;
  t.lineLimit = 1;
  t.minimumScaleFactor = .7;
  return t;
}

async function construye(familia) {
  const w = new ListWidget();
  const bloqueo = familia.startsWith("accessory");
  if (!bloqueo) { w.backgroundColor = C.fondo; w.setPadding(14, 14, 14, 14); }
  w.url = WEB + "/";
  w.refreshAfterDate = new Date(Date.now() + 15 * 60 * 1000);   // iOS decide; esto es lo que pedimos
  if (!hayClaves()) { texto(w, "Abre el script en Scriptable para configurarlo", 12, C.texto); return w; }
  let H;
  try { H = await datos(); }
  catch (e) { texto(w, "Hoy", 14, C.texto, true); texto(w, `Sin datos: ${e.message}`, 11, C.suave); return w; }

  const hs = H.habitos, hechos = hs.filter(h => h.hecho).length;
  const pa = (H.salud && H.salud.pasos.ultimo) || 0, su = (H.salud && H.salud.sueno.ultimo) || 0;
  const valores = [[hs.length ? hechos / hs.length : 0, C.hab], [pa / OBJ.pasos, C.pas], [su / OBJ.sueno, C.sue]];
  const tareas = Array.isArray(H.tareas) ? H.tareas : [];
  const enJuego = new Date().getHours() >= 20 && hs.some(h => !h.hecho && h.racha >= 2);
  const lineaTarea = t => t.t + (t.hora ? ` · ${t.hora}` : "");

  if (familia === "accessoryInline") {
    texto(w, `${hechos}/${hs.length} hábitos · ${pa ? miles(pa) : "—"} pasos · ${su ? hm(su) : "—"}`, 12, C.texto);
    return w;
  }
  if (familia === "accessoryCircular") {
    w.addAccessoryWidgetBackground = true;
    const img = w.addImage(anillos(60, valores, 6));
    img.centerAlignImage();
    return w;
  }
  if (familia === "accessoryRectangular") {
    texto(w, `${hechos}/${hs.length} hábitos${enJuego ? " · racha en juego" : ""}`, 13, C.texto, true);
    texto(w, `${pa ? miles(pa) : "—"} pasos · ${su ? hm(su) : "—"} dormido`, 12, C.texto);
    texto(w, tareas[0] ? lineaTarea(tareas[0]) : "Nada que venza hoy", 12, C.texto);
    return w;
  }

  // pequeño: solo los anillos
  if (familia === "small") {
    w.addSpacer();
    const img = w.addImage(anillos(130, valores, 12));
    img.centerAlignImage();
    w.addSpacer();
    return w;
  }

  const pendiente = (sitio, cuantas, tam) => {
    texto(sitio, tareas.length ? `Pendiente · ${tareas.length}` : "Pendiente", 12, C.suave, true);
    sitio.addSpacer(4);
    if (!tareas.length) texto(sitio, "Nada que venza hoy", tam, C.texto);
    for (const t of tareas.slice(0, cuantas)) { texto(sitio, "→ " + lineaTarea(t), tam, C.texto); sitio.addSpacer(2); }
    if (tareas.length > cuantas) texto(sitio, `y ${tareas.length - cuantas} más`, 11, C.suave);
  };

  // mediano: el «campo» para apuntar algo y, debajo, lo pendiente de hoy
  if (familia === "medium") {
    w.url = WEB + "/pendientes.html";
    // un widget no deja escribir: el campo abre este script en Scriptable, que pide el texto y lo manda
    const campo = w.addStack();
    campo.url = `scriptable:///run/${encodeURIComponent(Script.name())}?nueva=1`;
    campo.backgroundColor = C.campo;
    campo.cornerRadius = 12;
    campo.setPadding(10, 12, 10, 12);
    campo.centerAlignContent();
    texto(campo, "＋  Añadir tarea o recordatorio", 14, C.suave);
    campo.addSpacer();
    w.addSpacer(10);
    pendiente(w, 3, 13);
    w.addSpacer();
    return w;
  }

  // grande: anillos y lo pendiente arriba; debajo, los hábitos de hoy
  w.url = WEB + "/habitos.html";
  const fila = w.addStack();
  fila.layoutHorizontally();
  fila.topAlignContent();
  fila.addImage(anillos(84, valores, 8));
  fila.addSpacer(14);
  const col = fila.addStack();
  col.layoutVertically();
  col.url = WEB + "/pendientes.html";
  pendiente(col, 4, 13);
  fila.addSpacer();
  w.addSpacer(10);
  texto(w, `Hábitos · ${hechos}/${hs.length}${enJuego ? " · racha en juego" : ""}`, 12, enJuego ? C.aviso : C.suave, true);
  w.addSpacer(4);
  for (const h of hs.slice(0, 10)) {
    const l = w.addStack();
    l.centerAlignContent();
    // tocar uno sin hacer lo marca (Hábitos lee ?hecho= y deja deshacer)
    if (!h.hecho) l.url = `${WEB}/habitos.html?hecho=${encodeURIComponent(h.id)}`;
    texto(l, h.hecho ? "✓ " : "○ ", 13, h.hecho ? new Color(h.c) : C.suave, true);
    texto(l, h.n, 13, h.hecho ? C.suave : C.texto, !h.hecho && h.plan);
    l.addSpacer();
    if (h.racha) texto(l, `${h.racha} d`, 12, h.racha >= 2 && !h.hecho && enJuego ? C.aviso : C.suave);
    w.addSpacer(2);
  }
  w.addSpacer();
  return w;
}

// lo que abre el campo del widget mediano: texto, hora si quieres y para cuándo
async function nuevaTarea() {
  const a = new Alert();
  a.title = "Nueva tarea";
  a.message = "Con hora, te llega el recordatorio por Telegram.";
  a.addTextField("Llamar al dentista");
  a.addTextField("Hora (opcional: 10:30)");
  ["Para hoy", "Para mañana", "Sin fecha"].forEach(x => a.addAction(x));
  a.addCancelAction("Cancelar");
  const i = await a.present();
  const t = a.textFieldValue(0).trim();
  if (i === -1 || !t) return;
  let hora = a.textFieldValue(1).trim().replace(/[.h]/, ":");
  if (/^\d{1,2}$/.test(hora)) hora += ":00";
  if (/^\d:\d\d$/.test(hora)) hora = "0" + hora;
  if (!/^\d\d:\d\d$/.test(hora)) hora = "";
  const d = new Date();
  if (i === 1) d.setDate(d.getDate() + 1);
  const due = i === 2 && !hora ? "" : `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  const r = new Request(WEB + "/api/tarea");
  r.method = "POST";
  r.headers = {...cabeceras(), "Content-Type": "application/json"};
  r.body = JSON.stringify({t, due, hora});
  const n = new Notification();
  try {
    await r.loadString();
    if (r.response.statusCode >= 300) throw new Error("error " + r.response.statusCode);
    n.title = "Apuntada";
    n.body = t + (hora ? ` · ${hora}` : "") + (due ? (i === 1 ? " · mañana" : " · hoy") : "");
  } catch (e) {
    n.title = "No se pudo apuntar";
    n.body = `${t} (${e.message})`;
  }
  await n.schedule();
}

if (config.runsInWidget) {
  Script.setWidget(await construye(config.widgetFamily || "medium"));
} else if (args.queryParameters.nueva) {
  if (!hayClaves()) await pideClaves();
  await nuevaTarea();
} else {
  if (!hayClaves()) await pideClaves();
  const m = new Alert();
  m.title = "Widget de Hoy";
  ["Ver mediano", "Ver pequeño", "Ver grande", "Cambiar las claves"].forEach(x => m.addAction(x));
  m.addCancelAction("Salir");
  const i = await m.present();
  if (i === 3) await pideClaves();
  else if (i >= 0) {
    const fam = ["medium", "small", "large"][i];
    const w = await construye(fam);
    await (fam === "small" ? w.presentSmall() : fam === "large" ? w.presentLarge() : w.presentMedium());
  }
}
Script.complete();
