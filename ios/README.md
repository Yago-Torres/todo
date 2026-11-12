# Tom para iPhone, gratis con SideStore

«Tom» (antes «Hoy») es la misma web de todo.yagotg.dev dentro de una app nativa. Añade lo que la web no puede: sueño, pasos, peso y entrenos que se mandan solos desde Salud, widgets, avisos locales, Siri y un modo voz para hablar con Tom como con el bot de Telegram.

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

Después, en la pantalla de **Configuración** (la primera vez sale sola; luego, en la web, **Ajustes › Ajustes de la app**; si la web no carga, el botón **Ajustes de la app** de la pantalla «Sin conexión» o el enlace `hoy://configurar`), activa:

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

## Freno de apps

Tom no puede leer el Tiempo de uso (Apple solo lo deja con cuenta de pago), así que el freno va con Atajos. Una vez por app:

1. **Atajos → Automatización → Nueva → App**. Elige la app (Instagram, TikTok…), marca **Se abre** y **Ejecutar inmediatamente**.
2. Añade la acción **Frenar app** de Tom (búscala por nombre: no cabe entre los 10 recuadros) y escribe el nombre de la app. Las conocidas (Instagram, TikTok, YouTube, Brawl Stars, Clash Royale…) van solas; para otra, pon su esquema de URL en **Enlace** (p. ej. `brawlstars://`).
3. Añade **Abrir URL** (la acción de Atajos). Coge sola el resultado de la anterior.

Sin pase, se abre Tom: respiras unos segundos y eliges **Mejor no** o **Entrar 5 min**. Entrar abre la app con un pase de esos minutos; cada vez que entras en el día, la espera crece 4 s. El pase, la espera y las aperturas libres al día se cambian en **Ajustes de Tom → Freno de apps**. Lo que abres no sale del iPhone.

Apps: Instagram, TikTok, YouTube, X, Facebook, Reddit, WhatsApp, Twitch, Threads y BeReal.

## Ajustes de Tom sin pasar por la web

Mantén pulsado el icono de Tom → **Ajustes de Tom**. Ahí están las claves, Salud, los avisos, el freno y **Diagnóstico → Comprobar conexión** (si la web sale con la pantalla de Cloudflare, manda una captura de eso).
