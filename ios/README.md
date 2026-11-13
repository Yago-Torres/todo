# Tom para iPhone, gratis con SideStore

«Tom» (antes «Hoy») es todo.yagotg.dev hecho app nativa (SwiftUI, sin web dentro: la web sigue para el ordenador, con los mismos datos). Añade lo que la web no puede: sueño, pasos, peso y entrenos que se mandan solos desde Salud, widgets, avisos locales, Siri y un modo voz para hablar con Tom como con el bot de Telegram.

Por dentro sigue llamándose `Hoy` (bundle `dev.yagotg.hoy`, targets y app group): cambiarlo gastaría App IDs nuevos en SideStore. Solo cambia el nombre que se ve.

Se instala sin Mac, sin cuenta de desarrollador de pago y con un PC Windows. Lo único que necesitas del PC es el primer día.

## Qué es y por qué así

Apple firma las apps gratis durante **7 días**. Pasado ese tiempo, la app deja de abrir. SideStore la renueva sola desde el propio iPhone, con LocalDevVPN conectado.

Los límites de la cuenta gratis:

- **3 apps activas** como máximo, contando SideStore. Tom cuenta como una app (el widget y «Leer luego» van dentro).
- **10 App IDs por semana**. Tom usa 3: la app (`dev.yagotg.hoy`), el widget (`dev.yagotg.hoy.widget`) y la extensión de compartir «Leer luego» (`dev.yagotg.hoy.compartir`). Al actualizar a la versión que trae «Leer luego», SideStore registra el ID nuevo: gasta uno de los 10 de esa semana.
- **Sin notificaciones push nativas.** Los avisos son locales: los programa la app en el propio iPhone.
- **Sin iCloud ni dominios asociados.** No hacen falta.

Fuentes: [FAQ de SideStore](https://docs.sidestore.io/docs/faq).

## Instalar SideStore (una vez, con el PC)

Esto se hace una vez. Lo necesitas otra vez solo si reseteas o actualizas el iPhone (ver [Primera vez](#primera-vez)).

**Requisitos del PC:** Windows 8 o superior, 64 bits. No sirve Windows 10 en ARM ni 32 bits. Conexión Wi-Fi (no datos móviles). Fuente: [requisitos](https://docs.sidestore.io/docs/installation/prerequisites).

1. Instala **iTunes** desde [la web de Apple](https://www.apple.com/itunes/) (recomendado) o desde Microsoft Store. Si no funciona, prueba la app Apple Devices.
2. Descarga **iloader** desde [github.com/nab138/iloader](https://github.com/nab138/iloader/releases), el instalador **MSI** (recomendado). Ejecútalo.
3. Conecta el iPhone al PC con el cable USB.
4. Abre iloader e inicia sesión con tu Apple ID. Es sensible a mayúsculas.
5. Elige tu iPhone y pulsa **Install SideStore (Stable)**.
6. En el iPhone, ve a **Ajustes > General > VPN y gestión de dispositivos**, en «App para desarrolladores» toca tu Apple ID y pulsa **Confiar**. En iOS 16 o superior, activa también **Modo de desarrollador** en Privacidad y seguridad; el iPhone se reinicia.

Fuentes: [instalación con iloader](https://docs.sidestore.io/docs/installation/install), [README de iloader](https://github.com/nab138/iloader).

## Instalar Tom

Haz todo esto en el iPhone.

1. Abre Safari y entra en `https://github.com/Yago-Torres/todo/releases/download/ios/Tom.ipa`. Se descarga el archivo. (Unas semanas seguirá también `Hoy.ipa`, el mismo archivo con el nombre de antes.)
2. Abre **SideStore** y ve a **Mis apps** (My Apps).
3. Pulsa **+** y elige el archivo `Tom.ipa` de la app Archivos.
4. Espera a que termine la instalación. Si se queda parada, cierra SideStore, vuelve a abrirla y repite.

> Nota: el paso del **+** viene de guías de terceros. La documentación oficial no lo detalla, así que si la pantalla es distinta en tu versión, busca el botón de añadir y el IPA en su lugar.

Fuente: [FAQ de SideStore](https://docs.sidestore.io/docs/faq).

## Primera vez

Abre **Tom** y pega estas tres claves. Son las mismas que usa el atajo del iPhone.

| Campo | Qué pegas |
|---|---|
| CF-Access-Client-Id | El `Client ID` de Cloudflare Access |
| CF-Access-Client-Secret | El `Client Secret` de Cloudflare Access |
| Contraseña | La contraseña de todo (`TODO_PASS`) |

Sácalas desde el PC:

```
ssh pi@192.168.1.70 'sudo cat /etc/cloudflare-access/todo-bot.json'
```

Después, en la pantalla de **Configuración** (la primera vez sale sola; luego, en **Ajustes › Ajustes de la app**, manteniendo pulsado el icono → **Ajustes de Tom** o con el enlace `hoy://configurar`), activa:

- **Salud**, para que la app lea sueño, pasos, peso y entrenos.
- **Avisos**, para los recordatorios locales.
- **Face ID**, si quieres que pida huella o cara al abrir.

## Qué sustituye

| Antes | Ahora |
|---|---|
| Atajos de Salud y de entreno que mandaban datos a la web | La app manda sueño, pasos, peso y entrenos sola. **Desactiva esas automatizaciones** para no duplicar registros. |
| Widget de Scriptable | Widget nativo de Tom. Añádelo desde la pantalla de inicio. |
| Icono web (PWA) en la pantalla de inicio | Puedes borrarlo. Telegram sigue avisando igual. |
| Scriptable en la pantalla de bloqueo | Widget **Un dato**: al añadirlo eliges pasos, sueño, hábitos, pendientes, gastos (lo que queda del ciclo), entreno, carrera o peso. Sirve en la pantalla de bloqueo y en StandBy (el pequeño). |
| Atajo de apuntar gastos | «Oye Siri, apunta un gasto en Tom» (o la acción **Apuntar un gasto** en Atajos, con nota y categoría). Contesta lo mismo que la notificación del atajo. El atajo de Apple Pay sigue igual. |
| Mandar un enlace al bot para leer luego | Compartir > **Leer luego** desde Safari. El bot lo resume igual y te lo manda por Telegram. |

El atajo manual de entreno de la web sigue sirviendo. No hace falta tocarlo.

## Siri, toque posterior y centro de control

El iPhone 15 (sin Apple Intelligence) no entiende frases libres: Siri solo reconoce las frases que declara la app, y siempre con «Tom» dentro. Hay dos tipos.

**Frases rápidas** (no pasan por Claude, contestan en un segundo):

| Dices | Hace |
|---|---|
| «Mueve el entreno a mañana en Tom» (o «al sábado», «a pasado mañana»…) | El entreno de hoy que falta por hacer pasa a ese día con su sesión. Si ese día ya hay gimnasio, se cambian las dos sesiones. |
| «Qué toca hoy en Tom», «Qué me toca mañana en Tom», «Qué toca el jueves en Tom» | Entreno, hábitos que faltan (si es hoy) y lo que vence. |
| «Marca creatina en Tom», «He hecho Core en Tom», «Marca un hábito en Tom» | Marca el hábito de hoy. |
| «Apunta una tarea en Tom» | Pregunta cuál y la apunta en Pendientes. |
| «Apunta un gasto en Tom» | Pregunta cuánto y lo apunta en el ciclo de Gastos. |
| «Cuánto me queda en Tom», «Cómo voy de dinero en Tom» | Lo que queda de presupuesto y a cuánto sale al día. |
| «Apunta el peso en Tom» | Pregunta cuánto pesas y lo apunta hoy. |
| «Abre pendientes en Tom», «Empieza el entreno en Tom» | Abre la app en esa sección (el entreno, en su página). |

**Dile a Tom** (texto libre, con Claude, como un mensaje al bot de Telegram): «Dile a Tom», «Pregunta a Tom» o «Pregúntale a Tom». Siri pregunta «¿Qué le digo a Tom?» y le dices lo que quieras: «mueve el de pierna al sábado», «recuérdame llamar al dentista el jueves a las 10», «he gastado 12 en la cena», «¿cuánto llevo de proteína?». Tarda unos 10 segundos. Lo que reorganiza la semana te lo propone y pregunta «¿Lo aplico?»: contesta «vale» o «no». Tom se acuerda de lo último que le has dicho durante 10 minutos, así que después puedes decir «y el de pierna al sábado».

**Habla con Tom** (modo voz): «Habla con Tom» abre la app en una pantalla que escucha, contesta en voz alta y vuelve a escuchar, como una llamada. Para con el botón **Parar** o quedándote callado unos segundos. La primera vez pide permiso para el micrófono y el reconocimiento de voz.

Si una frase no la pilla, mira en la app **Atajos > Tom**: ahí salen todas, y desde ahí se pueden lanzar o añadir a la pantalla de inicio.

### Toque posterior (dos toques en la espalda del iPhone)

1. Abre **Atajos**, pulsa **+** para crear un atajo y añade la acción **Habla con Tom** (búscala por «Tom»). Si prefieres que Siri te pregunte en vez del modo voz, usa **Decirle algo a Tom**.
2. Ponle de nombre «Tom» y guárdalo.
3. Ve a **Ajustes > Accesibilidad > Tocar > Toque posterior**, elige **Doble toque** (o Triple toque) y, en la sección Atajos, elige el atajo **Tom**.

Desde entonces, dos toques en la espalda del iPhone abren Tom escuchando.

### Centro de control y botón de acción (iOS 18)

Abre el centro de control, mantén pulsado un hueco, toca **Añadir un control** y busca **Tom**: el control **Habla con Tom** abre el modo voz. El mismo control se puede poner en la pantalla de bloqueo (en lugar de la linterna o la cámara). El iPhone 15 no Pro no tiene botón de acción; en un modelo con botón, también se puede asignar ahí.

## Actualizar

Cada cambio en `ios/` compila una nueva versión en GitHub Actions. Para actualizar:

1. Descarga el IPA nuevo como en [Instalar Tom](#instalar-tom).
2. Instálalo encima en SideStore. Tus datos se conservan.

Si ya tienes Hoy o Tom en SideStore, la instalación del IPA nuevo la reemplaza. No hace falta borrarla antes.

## Cómo se compila

- **XcodeGen** genera el proyecto desde `ios/project.yml`. No hay `.xcodeproj` en el repo.
- **GitHub Actions** (`.github/workflows/ios.yml`) compila en una máquina `macos-15` con Xcode 16. No firma el código.
- **ldid** mete los permisos (entitlements) dentro del `.app`, del widget y de la extensión de compartir. SideStore los lee de ahí al firmar.
- El resultado es `Tom.ipa` (y una copia `Hoy.ipa` para el enlace viejo), publicado en la release `ios`.

Si la compilación falla, el registro de errores queda descargable sin iniciar sesión: https://github.com/Yago-Torres/todo/releases/download/ios-log/errores.txt

## Si algo falla

| Síntoma | Qué hacer |
|---|---|
| Tom deja de abrir (la app caducó) | Abre **LocalDevVPN** y pulsa **Connect**. Abre SideStore, ve a **Mis apps** y toca el contador **7 DAYS**. Necesitas Wi-Fi. |
| SideStore no refresca o da error de conexión | Usa LocalDevVPN, no StosVPN ni WireGuard. Reinicia LocalDevVPN y SideStore. Si sigue, vuelve a sacar el archivo de emparejamiento con iloader. |
| «App ID limit» o demasiados App IDs | Apple da 10 IDs por semana y cada instalación de Tom necesita 3 (app, widget y «Leer luego»). Espera a la semana siguiente y vuelve a instalar. No hay atajo. |
| Pide código 2FA y no entra | Comprueba que el código es el último que llegó. En iOS 18.1 o superior: apaga Wi-Fi y datos, ve a **Ajustes > tu nombre > Inicio de sesión y seguridad > Obtener código de verificación** y escribe el código en SideStore. Si sigue, cambia el servidor Anisette en los ajustes de SideStore. |
| SideStore se queda colgada al instalar o actualizar | Ve al escritorio del iPhone para que termine. Cambia el servidor Anisette y reinicia el iPhone. |
| Salud no tiene datos | Ajustes > Salud > Acceso a datos > Tom: activa las categorías. Luego abre Tom y espera unos segundos. |
| Tom no sale al añadir widgets | Abre Tom una vez después de instalar (iOS registra los widgets al abrirla) y, si sigue sin salir, reinicia el iPhone. Si al instalar SideStore preguntó por las extensiones (o el límite de App IDs), elige **conservarlas**: sin `dev.yagotg.hoy.widget` el IPA se instala sin widget. En SideStore → Mis apps → Tom → App IDs deben verse los tres. |
| Widget vacío | Abre Tom una vez con Wi-Fi y espera a que cargue. Luego vuelve a la pantalla de inicio. |
| El widget «Un dato» enseña otra cosa | Mantenlo pulsado, **Editar widget** y elige el dato. En la pantalla de bloqueo: mantén pulsado el fondo, **Personalizar** y toca el widget. |
| Siri dice que no encuentra la app o no entiende la frase | Abre Tom una vez después de instalar o actualizar: es cuando iOS registra las frases. Di siempre «en Tom» al final (o «Dile a Tom» al principio). Los hábitos para «Marca … en Tom» se actualizan cada vez que abres la app. |
| «Dile a Tom» dice que Tom no responde | El bot de Telegram (todo-bot) está parado en la Pi: `sudo systemctl restart todo-bot`. Las frases rápidas siguen funcionando sin él. |
| El modo voz no escucha | Ajustes > Tom: activa Micrófono y Reconocimiento de voz. |
| «Leer luego» no sale al compartir | En la hoja de compartir, desliza la fila de apps hasta **Más** y activa **Leer luego** (puedes subirlo arriba). |
| «Leer luego» dice que faltan las claves | Abre Tom una vez: las claves se guardan en el contenedor compartido y la extensión las lee de ahí. Si sigue, reinstala el IPA con SideStore para que renueve el app group de las tres partes. |
| Lo guardado sale «Sin resumir todavía» | La nota se guarda al momento y el bot la resume en un minuto o dos (te llega por Telegram). Si no llega, el bot está parado: la nota se queda con el enlace. |
| Tras actualizar o resetear el iPhone, nada funciona | El archivo de emparejamiento caduca. Repite la sección [Instalar SideStore](#instalar-sidestore-una-vez-con-el-pc) con iloader. Tus datos siguen en el servidor. |

Si nada de esto funciona, mira el [registro de errores](#cómo-se-compila) o el servidor de Discord de iloader, que es donde atienden los problemas de iloader.

## Pantallas nativas y tema

Todas las secciones son SwiftUI (`Hoy/Nativo/`, una línea cada una en `Registro.swift`), con la barra de abajo también
nativa (`Dock.swift`, la gota lima que se desliza con muelle). Ya no hay WKWebView: cualquier ruta que llegue (widgets,
controles, avisos, accesos del icono, Siri, `hoy://ruta?r=…`) abre su pantalla nativa con `Navegador.abre`, y una ruta
desconocida abre Hoy. `/carrera.html` abre la pantalla de Carrera con Entreno marcado en la barra; `?hecho=id` marca el
hábito y `/pendientes.html?nueva=1` enfoca el campo de apuntar.

**Arranque instantáneo** (`Hoy/Arranque.swift`): cada modelo pinta al crearse su copia de Local, sin esperar a la red ni a
Face ID (el bloqueo tapa, pero debajo ya está pintado). El tema sale de una instantánea guardada (`TemaGuardado`, sin
decodificar el catálogo de 60 KB hasta después del primer fotograma), las letras se registran al usarlas (`Letras.swift`,
ya no en `UIAppFonts`), y la sesión de audio, las Live Activities, las subidas, CoreMotion (1,5 s), los atajos, Salud y
los avisos van detrás. Después, `Precarga` crea los modelos de las demás secciones de la barra, uno a uno: al cambiar de
pestaña no hay «Cargando…». Lo que llega de la red sustituye a la copia con el muelle de pantalla.

**Modo noche** (`Compartido/Noche.swift`, `Hoy/ModoNoche.swift`; Configurar → Apariencia → Modo noche): por horas (23:00 a
7:00 por defecto) o de la puesta a la salida del sol (calculadas con la hora de Madrid o de Canarias, sin ubicación).
Fuerza oscuro y pasa cada token del tema por un filtro cálido (menos brillo, menos azul, el acento más apagado). Entra y
sale con un fundido de un segundo (`TransicionFundido`). El widget y las Live Activities lo aplican al leer
`ColoresGuardados` (la próxima vez que iOS los repinte).

- `Datos.swift`: lee `/api/hoy` y `/api/state` (sin red, la copia de Local) y marca al momento; sin red, a la cola.
- `PantallaHoy.swift`: anillos del día, hábitos de hoy, entreno, «Para hoy», salud, carrera y gastos.
- `PantallaHabitos.swift`: la semana de cada hábito; tocar un día lo marca (desliza para ver semanas anteriores).
  «Editar» (`Habitos/EditorHabitos.swift`, `GestorHabitos.swift`): crear, cambiar (nombre, color, días por semana, cada
  cuántas semanas), ordenar, borrar y planificar la semana. Cada cambio es una operación de la cola (ver «Sin red» abajo):
  funciona igual sin conexión. Para campos nuevos de un hábito: `GestorHabitos.edita(id, cambios: [...])` / `crea(campos:)`.
- `Ajustes/`: `/ajustes.html` nativo (`PantallaAjustes`) y las mismas secciones dentro de Configurar
  (`SeccionAjustesTom`): nombre, sonidos, secciones (módulos activo/en la barra), límites del móvil y mascota
  (`EditorMascota`). `ModeloAjustes` lee y guarda `/api/ajustes` (sin apariencia ni disposición: el servidor las
  conserva; sin red, a la cola). La vista previa de la mascota es `HuecoVistaMascota`: cambiar su cuerpo por la mascota
  nativa cuando exista.
- `PantallaEditable.swift`: ver «Pantallas editables» abajo.
- `FondoCalma.swift`: el plasma de caracteres de calma.js en Canvas (15 fps, quieto con «reducir movimiento»), con la
  intensidad del fondo elegido en Configurar → Apariencia.

**El tema está en un solo sitio: `Hoy/Tema.swift`.** Paleta «Hormigón» (grises) + acento «Salvia», letra Instrument
Sans (variable, `Hoy/InstrumentSans.ttf`, registrada al usarla), esquinas suaves (12/8/pastilla). Colores claro/oscuro, radios,
espacios, muelles y letra. Las vistas nativas solo usan `Tema.*`. Para cambiar la letra: empaqueta el `.ttf` en
`Hoy/`, añade su línea en `Letras.swift` (familia → ficheros) y pon su nombre de familia en `Fuentes` (`texto`, `titulo`,
`cifras`); sin familia, SF Pro (`diseno` elige `.rounded`, `.serif`…). Otro tema = otra `Paleta`/`Fuentes` en
`Tema.actual`.

### Pantallas editables (orden y ocultos de los bloques)

Cada pantalla nativa puede dejar que se ordenen y escondan sus bloques con `PantallaEditable`
(`Hoy/Nativo/PantallaEditable.swift`). Pinta la cabecera, los bloques en el orden guardado, el modo «Editar» en la
propia pantalla y el menú de mantener pulsado un bloque. Se guarda en la disposición `app-<seccion>` (la misma clave que
la barra de abajo: `app-hoy`, `app-entreno`…), que el servidor ya guarda y sincroniza.

```swift
PantallaEditable(pantalla: "app-entreno", titulo: "Entreno",
                 bloques: Self.bloques,                  // [("plan", "Plan de hoy"), ("series", "Series")]
                 recarga: { await datos.recarga() }) { editar in
    Cabecera(editar: editar)                              // `editar` abre el modo edición (botón propio)
} bloque: { id in
    switch id {
    case "plan": Plan()
    case "series": Series()
    default: EmptyView()
    }
}
```

- **Los ids de bloque son estables**: lo que se guarda en el servidor es el id, no el nombre ni la posición. No los
  cambies nunca; un bloque nuevo se añade al final de la lista sin tocar los demás. Un bloque que decide no pintar nada
  (sin datos) devuelve `EmptyView()`.
- Para que Configurar → Pantallas la muestre editable, añade su línea en `PantallasEditables.bloques`
  (`clave: bloques`). Las pantallas del registro que no estén ahí salen allí desactivadas, con «pronto».
- `pie:` (opcional) pinta algo tras el último bloque, `recarga:` activa tirar para recargar, y
  `@Environment(\.editarPantalla)` permite abrir la edición desde dentro de un bloque.

### Entreno y Carrera nativos (`Hoy/Nativo/Entreno/`, `Hoy/Nativo/Carrera/`)

- **Datos**: `DatosEntreno` lee `/api/state` y guarda con un PUT del estado entero con `X-Version`, como la web. Un 409 se
  junta con `Fusion` a partir de lo último del servidor; sin red, el PUT va a la cola de `Local` (con su base) y la copia
  local se queda con lo cambiado. Solo reescribe `rutinas`, `log`, `plan`, `sesion`, `gym` y `peso`; lo demás va tal cual.
- **Modo entreno** (`SesionEnCurso`, `VistaSesion`): serie a serie en `gym` de hoy, marcar manteniendo 0,6 s, descanso
  a pantalla completa (−15/+15/Terminar, pitidos y vibración), récords y doble progresión como entreno.html. La pantalla no
  se apaga. Lo que está en marcha (y una copia de la sesión) va en `UserDefaults` «entreno.enMarcha»: si iOS mata la app,
  `Entreno.init` vuelve a Entreno y la sesión se reabre. La rutina guiada (`GuiaEnCurso`) igual, «entreno.guiaEnMarcha».
- **Isla**: la sesión nativa alimenta la Live Activity (`Entreno.muestraNativo`) y el «Serie hecha» de la isla la marca
  la propia pantalla nativa (`Entreno.nativo`), también en segundo plano.
- **Monigotes y cuerpo**: `monigotes.json` y `cuerpo.json` salen de `static/monigotes.js` y del `CUERPO` de
  entreno.html (un script de node que los evalúa). Si cambian en la web, hay que regenerarlos.
- `/carrera.html` abre su pantalla (`PantallaCarrera`) con Entreno marcado en la barra; desde Entreno, la tarjeta de
  Carrera la abre en hoja.

## Sin red: la cola de operaciones

Todo lo de Tom funciona sin conexión y se sincroniza solo al volver (`Compartido/Operaciones.swift`, `Hoy/Sincro.swift`).

- **Operaciones con intención**, no copias del estado: `{op: "habito.edita", id, cambios}`, `habito.crea/borra/ordena`,
  `plan.pon`, `gasto.edita/borra/restaura`, `presupuesto.pon`, `regla.pon/borra/ordena/rechaza/aplica` y `recurrente.marca`
  (Gastos, `Compartido/OperacionesGastos.swift`), y también `viaje.pon/borra/asigna`, `ajustes.pon` (ingreso, día de
  cobro, hucha) e `ingreso.edita/borra/restaura`. Van a la cola de Local (método `OP`, ruta = el estado que
  tocan) junto a las peticiones de siempre (marcas, tareas, gastos, documentos), en un único orden.
- **Al apuntarlas** se pintan ya: la copia que se ve es «lo último del servidor (`BASE GET …`) + lo pendiente encima», y se
  rehace al bajar datos frescos, al mandar o al descartar. Sigue ahí aunque se cierre la app.
- **Al salir**: GET del estado fresco → operación encima → PUT (con `X-Version` en `/api/state`); en un 409, otra vuelta.
  Nunca pisa lo que hizo el bot o la web. Un 400/404/422 es un rechazo: se avisa con su texto y queda para descartarlo.
  Otros fallos, reintento con espera creciente (y la app vuelve a probar sola a esa hora).
- **Ids provisionales**: una tarea o un documento creados sin red llevan `tmp:…` (cabecera `x-tom-tmp`); al llegar se
  apunta el id real (`Local.alias`, también las tareas que cambian de id al editarlas) y lo de detrás sale con el bueno.
  Los documentos subidos sin red se abren desde la copia del iPhone.
- **Cuándo sale**: al volver la red (`Red`), al volver a primer plano, en la tarea de fondo (`Avisos`) y en cuanto se
  apunta algo con red (`Hoy/Nativo/Cola/EstadoCola.swift`).
- **Indicador**: encima de la barra, «N cambios por enviar» (`IndicadorCola`); tocarlo abre la lista con reintentar y descartar.
- Prueba de la lógica pura: `Pruebas/PruebaOperaciones.swift` (fuera de los targets).

## Gastos: flujo, reglas y recurrentes (`Hoy/Nativo/Gastos/`)

- **Flujo** (`FlujoGastos.swift`, bloque `flujo`, el primero): de lo que entra (sueldo + extras) a cada categoría, la hucha
  y lo que queda, con bandas bezier (`BandaFlujo`) que se dibujan al cargar (quietas con «reducir movimiento»). Sin
  ingreso, o gastando más de lo que entra, sale de lo gastado. Las pequeñas van en «Otros». Tocar una banda la resalta y
  filtra los movimientos. Las etiquetas tienen un hueco mínimo que crece con Dynamic Type: no se pisan.
- **Reglas** (`ReglasGastos.swift`, bloque `reglas`): «si el concepto contiene "mercadona" → Súper». Las propone el
  servidor (`GET /reglas`) y Tom al corregir la categoría de un gasto (tarjeta «¿Siempre así?»); aceptar, editar, rechazar,
  ordenar, borrar y «aplicar a N anteriores» son operaciones de la cola: sin red también. Las aplica el servidor a lo que
  entra por `/gasto` (bot, banco, tickets, Apple Pay). Regla en `~/gastos/CLAUDE.md`.
- **Recurrentes** (bloque `suscripciones`, ahora «Recurrentes»): semana, mes o año, con el próximo cargo, total al mes y al
  año; confirmar o ignorar (`recurrente.marca`). Aviso local el día antes (`AvisosRecurrentes.swift`; Configurar →
  Gastos recurrentes, por instancia).
- **Viajes y hucha** (`ViajesGastos.swift`, `DatosGastosViajes.swift`): crear, cambiar y borrar viajes (nombre, fechas,
  presupuesto, moneda con el cambio de hoy del BCE por `/cambio`, compartido con la pareja). Al crear uno se lleva los
  gastos que ya eran suyos (la misma regla que `que_viaje()` del servidor, en `OpsGastos.queViaje`) y se pueden devolver
  al ciclo con «Deshacer». La hoja del viaje enseña el desglose, las cuentas con la pareja, «Saldar» (un gasto
  `reparto: pago|cobro`) y sus gastos. La hucha: lo que apartas cada ciclo, las sugerencias 3/4/6 y el plan ciclo a ciclo.
- **Ajustes del ciclo** (`AjustesGastos.swift`, en «Presupuestos»): cuánto cobras y el día de cobro (vuelve al ciclo de
  hoy). Sin red se guardan, pero las cuentas del ciclo (las calcula el servidor) no cambian hasta que llegan.
- **Ingresos** (`IngresosGastos.swift`): editar y borrar (con deshacer). Apuntar lleva día y, en un viaje en otra moneda,
  la moneda; tras apuntar sale «Deshacer» (una operación `gasto.borra`/`ingreso.borra`). El editor de un gasto de un viaje
  compartido elige el reparto.
- Todo por instancia: Yago y Aitana nunca se mezclan.

## Apariencia, gestos e isla

**Temas al estilo monkeytype + colores libres.** Catálogo v2 (`GET /apariencia.json`, copia en `Hoy/apariencia.json`):
`temas` (base, acento, letra, títulos, esquinas, fondo, modo, con su «vibra») y `sugerencias` de base y acento.
Lo elegido (`GET/POST /api/apariencia`): `{tema (id o "propio"), modo, base, acento (hex), fuente, titulos, esquinas,
fondo}`. Elegir un tema copia sus valores; tocar cualquiera después lo deja en «propio».
- `Compartido/Oklch.swift`: la fórmula de calma.js `genera()` cifra a cifra (OKLCH de Ottosson): base + acento →
  todos los tokens de claro y oscuro, la gota y el ascii. #F2F2F2 + #4E7A62 → oscuro fondo #131313, acento #87B098.
- `Hoy/Aspecto.swift` construye `Tema.actual` (@Observable: se repinta todo con un fundido), lo guarda en el app group,
  sincroniza al arrancar y al volver, y manda cada cambio (sin red, a la próxima sin pisarlo). Widget y Live
  Activities leen los colores resueltos (`ColoresGuardados`, en oscuro).
- Letras (variables o regular+bold, registradas al usarlas: `Letras.swift`): Instrument Sans, Inter, Manrope, Geist, IBM Plex Sans, DM Sans,
  Space Grotesk, JetBrains Mono, Fraunces, Shippori Mincho, Zen Kaku Gothic New; «sistema» = SF Pro. `titulos` es la
  letra de los títulos.
- Configurar → Apariencia: vista previa, rejilla de temas (nombre en su letra, claro/oscuro, vibra) y «Personalizar»
  (fondo y acento con ColorPicker y sugerencias, letra, títulos, esquinas, fondo de caracteres, modo, Restablecer).
- Configurar → Pantallas: orden y ocultos de la barra (`app-dock`) y de todas las pantallas nativas del registro (`app-hoy`…;
  las que aún no usan `PantallaEditable` salen con «pronto»); en Hoy también el botón de editar o mantener pulsado un bloque.

**Gestos.** Deslizar a los lados cambia a la sección siguiente/anterior según el orden de la barra (con paso de página;
en Pendientes, Docs y Gastos, solo desde los bordes, porque sus filas se deslizan). En la barra, arrastrar el dedo mueve
la gota con él (vibra al pasar por cada sección) y al soltar va a la de debajo; tocar sigue igual.

**Modo voz desde la app**: el botón de micro en la cabecera de Hoy, mantener pulsada la barra de abajo o `hoy://voz`. El micro crea un `AVAudioEngine` nuevo en cada escucha, después de activar la sesión
`.playAndRecord` (si no, el inputNode nace sin entrada: 0 Hz); si aun así no hay entrada, reintenta a los 0,3 s y el
error dice Hz, canales y categoría de la sesión.

**Isla dinámica** (`Hoy/Isla.swift`, `Compartido/AvisoActividad.swift`, `HoyWidget/AvisoLiveActivity.swift`), además
del entreno serie a serie. Las cuentas atrás son `Text(timerInterval:)`: no despiertan la app; caducan solas y se
terminan al acabar o al volver a la app.
- Descanso: va en la actividad del entreno serie a serie.
- Freno: al «Entrar N min», «Instagram» con la cuenta atrás del pase.
- Escalada: comprimiendo / subiendo % y «listo» (o el error) al acabar.
- «Día en la isla» (Configurar, apagado por defecto): anillos de hábitos, pasos y sueño hasta las 22:00.

## Decoración por tema, sonidos y mascota

- **Fondo de cada tema** (`Hoy/Nativo/Decoracion/FondoTema.swift`, detrás de todas las pantallas nativas desde
  Pestanas): la clave `decoracion` de cada tema del catálogo (~/estilo/herramientas/catalogo.py; la web la ignora).
  Washi con olas (Shibuya), kintsugi (Kioto), pétalos (Sakura), barrido (Terminal), papel (Prensa), rejilla neón (Miami),
  formas (Bauhaus), curvas de nivel (Bosque, Fiordo), manchas (Matcha, Lavanda, Arena, Café), estrellas (Medianoche),
  rejilla fina (Braun) y el ASCII de siempre (Hormigón, Calma, Grafito). Canvas a 8–24 fps; los quietos solo se
  repintan mientras se mueve el dedo o el iPhone (`Movimiento.swift`: CoreMotion a 15 Hz y un reconocedor que solo mira).
  Respeta la intensidad del fondo y «reducir movimiento». Un tema «propio» usa la decoración del tema con su misma base.
- **Cambio de tema con círculo** (`CambioTema.swift`): foto de la pantalla encima y un agujero que crece desde el toque.
- **Icono a juego** (`Assets.xcassets/Icono-<tema>.appiconset`, `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` en
  project.yml): al cambiar de tema, `setAlternateIconName` (interruptor en Configurar → Apariencia; iOS avisa siempre).
  Se generan en la Pi con PIL (fondo = acento, visto = base): ver el commit que los añade.
- **Sonidos** (`Sonidos.swift`): sintetizados con AVAudioEngine (madera, bambú, 8bit, campanas, clic, sintetizador; clave
  `sonido` del catálogo). Suenan con cada `Haptica.shared.toca` si «sonidos» está encendido en Ajustes. Sesión `.ambient`.
- **Mascota** (`Hoy/Nativo/Mascota/`): mascota.js portado a Canvas (mismo azar: misma forma que en la web).
  `MascotaVista(ajustes:estado:presencia:reaccion:pasea:)` es reutilizable (vista previa de Ajustes); `MascotaHoy` la pone
  en la cabecera de Hoy con el estado de los datos y se alegra al marcar.
- **Completar el día** (`CelebracionDia`): confeti con los colores del tema, háptica «día» y su sonido.

## Freno de apps

Tom no puede leer el Tiempo de uso (Apple solo lo deja con cuenta de pago), así que el freno va con Atajos. Una vez por app:

1. **Atajos → Automatización → Nueva → App**. Elige la app (Instagram, TikTok…), marca **Se abre** y **Ejecutar inmediatamente**.
2. Añade la acción **Frenar app** de Tom (búscala por nombre: no cabe entre los 10 recuadros) y escribe el nombre de la app. Las conocidas (Instagram, TikTok, YouTube, Brawl Stars, Clash Royale…) van solas; para otra, pon su esquema de URL en **Enlace** (p. ej. `brawlstars://`).
3. Añade **Abrir URL** (la acción de Atajos). Coge sola el resultado de la anterior.

Para medir el **uso real** (y poder ponerle un límite diario en Configurar → Freno de apps), otra automatización por app: la misma app, solo **Se cierra** y **Ejecutar inmediatamente**, con la acción **App cerrada** de Tom y el mismo nombre. Tom cuenta de abrir a cerrar; pasado el límite del día, la espera es de 30 s y no quedan aperturas libres.

**«¿Sigues?»**: iOS no deja que una app te saque de otra a la fuerza (eso es la API de Tiempo de uso, de pago), así que Tom hace lo máximo posible. Al **Entrar**, programa avisos locales a los 5, 10 y 15 min (en **Configurar → Freno de apps**: «Cada N min» y «Hasta N avisos») con «Llevas 5 min en Instagram. ¿Sigues?» y dos botones: **Salir** (abre Tom en la pantalla de freno con `hoy://freno?app=X&revision=1`: sin espera, enseña cuánto llevas y ofrece **Mejor lo dejo** o **Seguir N min más**) y **N min más** (amplía el pase sin abrir la app). Van como «urgentes» solo si el entitlement time-sensitive está disponible; con cuenta gratis, avisos normales. Se cancelan al cerrar la app (acción **App cerrada**) o al decir **Mejor no**. La isla dinámica / pantalla de bloqueo hace lo mismo sin despertar la app: la actividad del pase caduca (`staleDate`) en cada aviso y pasa a «¿Sigues?» con lo que llevas y un botón **Salir** (un `Link` a esa URL; un `Button(intent:)` obligaría a un intent con `openAppWhenRun`, más frágil). Si el pase acaba y la app sigue abierta, la próxima vez que se abra (**Se abre**) ya no hay pase y salta el freno, con la espera por hora de siempre (5 s, 8 s, 11 s…). Como refuerzo que sí corta: **Ajustes de iOS → Tiempo de uso → Límites de apps** (bloquea la app al llegar al límite).

Sin pase, se abre Tom: respiras unos segundos y eliges **Mejor no** o **Entrar 5 min**. Entrar abre la app con un pase de esos minutos; la espera depende de cuántas veces has entrado en esa app en la hora de reloj en curso: la primera, 5 s; luego +3 s cada vez (8, 11…, tope 30), y al cambiar la hora vuelve a 5. Pasado el límite diario, 30 s. El pase, la **espera inicial**, lo que crece **cada vez más** y las aperturas libres al día se cambian en **Ajustes de Tom → Freno de apps**. Lo que abres no sale del iPhone.

Conocidas (sin Enlace): Instagram, TikTok, YouTube, X, Facebook, Reddit, WhatsApp, Twitch, Threads, BeReal, Telegram, Snapchat, Pinterest, Discord, LinkedIn, Netflix, Spotify, Tinder, Brawl Stars, Clash Royale y Clash of Clans.

## Ajustes de Tom desde el icono

Mantén pulsado el icono de Tom → **Ajustes de Tom**. Ahí están las claves, Salud, los avisos, el freno y **Diagnóstico → Comprobar conexión**: la firma (app group, Salud), las claves y si el servidor contesta (con qué código y en cuánto). Si algo sale con ✗, manda una captura.

## Trabajar en paralelo (ramas nativo/*)

- Cada bloque de trabajo va en su rama `nativo/<tema>`. Un push a `nativo/**` compila en Actions **sin publicar**; si
  falla, el registro queda en la release `ios-log-nativo-<tema>` (descargable sin sesión). Solo `main` publica `Tom.ipa`.
- Una sección nueva en nativo: su vista en `Hoy/Nativo/<Seccion>/` y **una línea** en `Hoy/Nativo/Registro.swift`.
  `Navegador.nativas` se rellena desde ahí al arrancar; Pestanas y la barra no hay que tocarlas.
- Los colores, letras, esquinas y muelles salen de `Tema` (Hoy/Tema.swift y Aspecto.swift); ninguna vista pone colores a mano.
- Las peticiones van por `API` (Compartido/API.swift) con las claves de siempre; lo que deba funcionar sin red, por la
  cola de `Local`/`Sincro` como Hoy y Hábitos.

## Rachas: descansos, vacaciones, comodines y avisos (`Hoy/Nativo/Rachas/`)

La racha la cuenta **solo el servidor** (`rachas()` en main.py, regla en `CLAUDE.md` → «Rachas»): Tom no cuenta nada, solo
suma el «hecho» de hoy a `base` para que marcar se vea al momento (también sin red).
- `DatosRachas`: `GET /api/rachas` (sin red, la copia de Local) y `POST /api/descanso`, `/api/comodin`, `/api/vacaciones`
  por la cola (idempotentes; el id de un periodo lo pone el iPhone).
- `BloqueRachas`: el bloque «Rachas» de Hoy (id `rachas`): «Mantén tu racha de 12 días» con un botón por hábito que la
  salva, «Descansar hoy», «Usar comodín», rachas vivas y lo que falta para el siguiente hito (7, 14, 30…).
- `HojaDescansos`: descansar hoy (por hábito o todos), comodines al mes y periodos de vacaciones/enfermedad. Desde Hoy,
  Hábitos (menú Editar) y el editor de hábitos. En la semana de Hábitos, los días libres llevan su icono (hoja, cama,
  sombrilla, copo) y la racha congelada sale con un copo.
- `AvisosRacha`: a media tarde y última llamada (Configurar → Avisos de racha: activar, horas, hitos), dos como mucho al
  día; la última llamada se come el repaso de las 22:00. Botones Hecho / Usar comodín / Descansar hoy. Lo programa
  `Avisos.programa()`.
- `CelebracionHito`: `.celebraHitos()` en Hoy y Hábitos: llama que crece, número que sube y el confeti de `CelebracionDia`.

## Paridad con la web

Repaso función a función de cada página web contra su pantalla de Tom (13/11). Hecho en nativo en esta tanda:

| Web | Faltaba en Tom | Ahora |
|---|---|---|
| Gastos | Crear, editar y borrar viajes (moneda y cambio, compartido, saldar, gastos del viaje) | Hecho (`ViajesGastos.swift`) |
| Gastos | Hucha de viajes: lo que apartas, sugerencias y plan ciclo a ciclo | Hecho |
| Gastos | Cuánto cobras y día de cobro | Hecho (`AjustesGastos.swift`) |
| Gastos | Editar y borrar ingresos | Hecho (`IngresosGastos.swift`) |
| Gastos | Día y moneda al apuntar, deshacer lo apuntado, reparto en el editor | Hecho |
| Hoy | Tarjeta «Comida» (menú de hoy y compra) y «Tu año» (mapa del año) | Hecho (`BloquesHoyWeb.swift`, bloques `comida` y `anio`) |
| Hábitos | Calendario del mes (mapa de calor, marcar y planificar cualquier día) | Hecho (`Habitos/CalendarioHabitos.swift`) |
| Comida | Lista de la compra del menú (tachar, dónde sale más barato) y Cuentas (por cadena, apagar cadenas, ahorro) | Hecho (`Comida/CompraMenu.swift`), refrescar precios incluido |

Ya estaban a la par: Pendientes, Documentos, Ajustes (la apariencia y las pantallas están en Configurar), Entreno
(el aviso push de la web no aplica: Tom avisa en local), Carrera y Salud (solo lectura en la web).

Segunda tanda (también hecho):

| Web | Ahora en Tom |
|---|---|
| Comida → Ingredientes | `Comida/IngredientesComida.swift` (desde el Menú): buscar, crear, macros por 100 g, unidad, g/ud, fuente, «Rellenar» con Open Food Facts y variantes (predeterminada, borrar). POST `/ingrediente` y `/variante`; sin red, a la cola |
| Comida → fijar producto (pin) | Mantener pulsado un ingrediente en la lista de la compra → «Elegir el producto en …» (`/candidatos`; fijar es la operación `comida.pin`) |
| Comida → variante en la receta | En la ficha de una receta del menú, el selector junto a cada ingrediente con variantes (operación `comida.variante`) |
| Hábitos → tira de 28 días | Tarjeta «Rachas» bajo los hábitos (`Habitos/TiraRachas.swift`): 28 días (o 4 semanas si es semanal), racha y constancia a 30 días |

Tachar la compra, fijar un producto y cambiar la variante son operaciones de la cola sobre `/api/comida/estado`
(`Compartido/OperacionesComida.swift`, `comida.tacha/pin/variante`): se ven al momento y salen solas al volver la red.

Lo que queda:

| Web | Falta | Esfuerzo |
|---|---|---|
| Gastos | Sin red, cambiar ingreso, día de cobro, hucha o viajes no recalcula las cuentas del ciclo hasta que llega (las calcula el servidor) | Medio: recalcular `resumen()` en el iPhone |
