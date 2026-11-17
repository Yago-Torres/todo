# todo para el escritorio (Windows y Omarchy)

La web de todo.yagotg.dev dentro de una ventana propia, con lo que el navegador no hace:

- **Bandeja** con lo que queda hoy («2 hábitos y 1 tarea por hoy»). Cerrar la ventana la deja ahí; para salir, «Salir».
- **Apuntar desde cualquier sitio**: Ctrl+Alt+N en Windows, Super+Alt+N en Omarchy. Una caja flotante para una
  **nota rápida**, una **tarea** (va a Pendientes) o un **gasto** («12,50 comida»). Intro guarda, Esc cierra.
- **Mini widget** siempre encima (bandeja › «Mini widget», o `--mini`; en Omarchy, Super+Alt+M): una ventanita
  que no se cierra al guardar, para ir apuntando notas y tareas, con lo último debajo. Si lo dejas abierto, vuelve al arrancar.
- **Avisos del sistema** a la hora de las tareas de hoy que llevan ⏰.
- **Arranque al encender** (en Windows se activa la primera vez y se quita en la bandeja; en Omarchy va por `exec-once`).
- **Sin red**: enseña lo último que llegó y los hábitos marcados se mandan al volver (eso ya lo hace la web, con `sinred.js`).
- **Módulo de Waybar** en Omarchy: `todo-escritorio --waybar`.

Las **notas rápidas** son una sección de la web (`/notas.html`, con un botón en Pendientes) y viven en
`Notas rápidas.md` del vault. No son tareas: cada una tiene «→ Pendiente» para cuando lo acabe siendo.

## Cómo va por dentro

Es [Tauri 2](https://tauri.app): la ventana usa el navegador del sistema (WebView2 en Windows, WebKitGTK en Linux).
No lleva una copia de la web: carga `http://127.0.0.1:47821`, un proxy que va dentro de la app (`src-tauri/src/proxy.rs`) y
reenvía cada petición a todo.yagotg.dev con las cabeceras de Cloudflare Access y el bearer de todo. Así la web sale
siempre al día, sin pantalla de contraseña, y no hay que tocar nada en Cloudflare.

- Las **claves** (las tres de Tom) van al llavero del sistema: el Administrador de credenciales de Windows o el Secret
  Service en Linux. Sin llavero, a `~/.config/todo-escritorio/claves.json` con permisos 600.
- El proxy **solo atiende a la ventana**: cada arranque estrena una llave que va en la primera URL y se queda en una cookie.
  Comprueba también el `Host`, para que una web que apunte su dominio a 127.0.0.1 no entre.
- El puerto es fijo para que el origen no cambie, porque la cola de `sinred.js` y el perfil viven en localStorage.
- **Sin red**: cada GET que llega bien se guarda en la carpeta de caché (`%LOCALAPPDATA%` o `~/.cache/todo-escritorio/copia`)
  y se sirve si no hay conexión.
- La ventana es contenido remoto **sin acceso a Tauri** (no hay capabilities): la web no puede llamar a nada nativo.
  Lo nativo (bandeja, atajo, avisos) va en Rust y lee `/api/hoy` por su cuenta.

| Fichero | Qué |
|---|---|
| `src-tauri/src/main.rs` | ventanas, bandeja, atajo, avisos, arranque y argumentos (`--oculta`, `--apuntar`, `--notas`, `--waybar`) |
| `src-tauri/src/proxy.rs` | el proxy local, la copia para cuando no hay red y las páginas `/_escritorio/*` |
| `src-tauri/src/claves.rs` | dónde se guardan las claves |
| `src-tauri/src/resumen.rs` | lo que queda hoy (bandeja, avisos y Waybar) |
| `src-tauri/paginas/` | configurar las claves, la caja de apuntar y el mini widget (las sirve el proxy) |

Todas las ventanas llevan `disable_drag_drop_handler()`: el gestor de Tauri para soltar ficheros se queda el
arrastre de WebView2 en Windows, y sin eso no se podían arrastrar las tarjetas del board.
| `omarchy/instalar.sh` | instala o actualiza en Omarchy |
| `icono.png` | de `static/icon.svg`; los iconos de cada tamaño los saca `tauri icon` en Actions |

## Compilar

Ni en la Pi ni en el PC hay Rust. Lo compila GitHub Actions (`.github/workflows/escritorio.yml`), como Tom:
una rama `escritorio/**` solo compila y `main` publica en la release
[`escritorio`](https://github.com/Yago-Torres/todo/releases/tag/escritorio):

- `todo-escritorio-instalador.exe`: el instalador de Windows. Instala para tu usuario, sin pedir administrador.
- `todo-escritorio-portable.exe`: el mismo programa sin instalar, para llevarlo en una carpeta.
- `todo-escritorio-linux-x86_64`: el binario para Omarchy (lo baja `instalar.sh`).

## Instalar

**Windows**: baja el instalador y ábrelo. SmartScreen avisará de que no está firmado («Más información» → «Ejecutar de
todas formas»). La primera vez pide las claves.

**Omarchy**:

```
curl -fsSL https://raw.githubusercontent.com/Yago-Torres/todo/main/escritorio/omarchy/instalar.sh | bash
```

Instala `webkit2gtk-4.1` y `libayatana-appindicator`, deja el binario en `~/.local/bin`, lo pone en el lanzador y escribe
`~/.config/hypr/todo.conf` (arranque, Super+Alt+N y la regla para que la caja de apuntar flote). Al final dice qué
pegar en Waybar. Para actualizar, se vuelve a ejecutar.

Si la ventana sale en blanco en Hyprland, la app ya pone `WEBKIT_DISABLE_DMABUF_RENDERER=1`. Si aun así pasa, prueba con
`GDK_BACKEND=x11 todo-escritorio`. Si las reglas de ventana de `todo.conf` dan error, es que tu Hyprland usa otra
sintaxis de `windowrule`: ajústalas a la de los `.conf` de Omarchy.

## En el PC del trabajo

Funciona si el PC te deja ejecutar programas: el instalador no pide administrador y el portable ni se instala. Antes:

- **Mira la política de la empresa.** Hay PCs de empresa que bloquean los programas sin firma (AppLocker o WDAC). Si no
  abre, no lo fuerces. En ese caso, todo.yagotg.dev en el navegador, con el login de Access, hace lo mismo menos la
  bandeja y el atajo.
- **Las claves dan acceso a todo** (hábitos, salud, gastos, el vault). En un PC que administra otro, lo que guardas se
  puede leer. En el menú de la bandeja, «Cambiar las claves…» las sustituye.
- **Proxy con inspección TLS**: la app usa los certificados del sistema, como el navegador, así que conecta aunque la
  empresa abra el tráfico HTTPS (antes daba `UnknownIssuer`). Pero entonces **la empresa ve lo que pasa**, claves
  incluidas: el secreto de Access y la contraseña de todo viajan en cada petición. `HTTPS_PROXY` también se respeta.
- WebView2 viene con Windows 10 y 11. Si faltara, el instalador lo baja.
