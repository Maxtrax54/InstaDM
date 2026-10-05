# InstaDM

App iOS personal (iPhone, iOS 16+) que envuelve la web de Instagram en un `WKWebView` para usarla **solo para mensajes directos**:

- Abre directo en **Mensajes** (`/direct/inbox/`) y mantiene la sesión.
- **Bloquea** el feed de Reels, Explorar (búsqueda y hashtags incluidos), los reels por audio y la pestaña Reels de los perfiles.
- **Deja ver los reels que te mandan por DM** (`/reel/<id>/`, `/reels/<id>/`), **de a uno**: el swipe al siguiente reel se bloquea.
- Los links externos se abren en Safari integrado.
- Tiene dos modos (en Ajustes): **Solo mensajes** (por defecto) y **Mensajes + Inicio** (suma el feed sin reels, perfiles y posts).
- Pull-to-refresh, gesto de volver desde el borde, modo oscuro, y envío de fotos, videos y audios por DM.

---

## Estructura

```
project.yml                     ← proyecto XcodeGen (nombre, bundle ID, versión)
InstaDM/
├─ Info.plist                   ← permisos (cámara, micrófono, fotos), solo vertical
├─ Sources/
│  ├─ App.swift                 ← @main
│  ├─ ContentView.swift         ← pantalla principal, barra inferior, toast, progreso
│  ├─ SettingsView.swift        ← ajustes: modo + cerrar sesión
│  ├─ WebView.swift             ← WKWebView, bloqueo de navegación, Safari, puente JS
│  └─ BlockRules.swift          ← ⚙️ TODAS las reglas de bloqueo (arriba de todo)
└─ Resources/
   ├─ inject.js                 ← oculta botones, intercepta clicks y la navegación de la SPA
   └─ Assets.xcassets           ← ícono
.github/workflows/build.yml     ← compila un .ipa sin firmar en GitHub Actions
```

### Cómo funciona el bloqueo (3 capas)

1. **`decidePolicyFor`** (Swift): frena las cargas completas de página hacia rutas bloqueadas y redirige a Mensajes.
2. **`inject.js`**: Instagram es una SPA y cambia de "página" con `history.pushState` sin recargar, así que el punto 1 no se entera. El script cancela los clicks hacia rutas bloqueadas, parchea `pushState`/`replaceState` y oculta los botones de Reels y Explorar.
3. **Vigilante de URL** (KVO sobre `webView.url`, en Swift): si algo se le escapa al JS (por ejemplo, porque Instagram cambió su código), lo detecta al cambiar la URL y redirige.

Las regex viven **solo** en `BlockRules.swift`. Swift se las pasa a `inject.js` como JSON (`window.__INSTADM__`), así que no hay que editarlas en dos lugares.

---

## Personalizar

| Qué | Dónde |
|---|---|
| Nombre bajo el ícono | `APP_DISPLAY_NAME` en `project.yml` |
| Bundle ID | `PRODUCT_BUNDLE_IDENTIFIER` en `project.yml` |
| Tu equipo de firma (Mac) | `DEVELOPMENT_TEAM` en `project.yml` |
| Rutas bloqueadas o permitidas, textos de los avisos | sección **CONFIGURACIÓN** de `BlockRules.swift` |
| Ver posts o historias que te mandan por DM en modo Solo mensajes | descomentá las líneas `^/p/` y `^/stories/` en `permitidasSoloMensajes` |
| Ícono | reemplazá `InstaDM/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (1024×1024, sin transparencia) |

Después de editar `project.yml`, regenerá el proyecto con `xcodegen generate`. En la opción B no hace falta: GitHub Actions lo regenera en cada compilación.

---

## Instalación

### Opción A: con Mac (Xcode)

1. Instalá Xcode (App Store) y XcodeGen:
   ```bash
   brew install xcodegen
   ```
2. En la carpeta del proyecto:
   ```bash
   xcodegen generate
   ```
   ```bash
   open InstaDM.xcodeproj
   ```
3. En Xcode: **Settings → Accounts →** agregá tu Apple ID (sirve uno gratuito).
4. Target **InstaDM → Signing & Capabilities → Team**: elegí tu Apple ID.
   Si dice que el Bundle ID ya está en uso, cambialo (ej. `com.maximo.instadm2`).
   *Tip:* copiá tu Team ID a `DEVELOPMENT_TEAM` en `project.yml` para no tener que elegirlo cada vez que regenerás.
5. Conectá el iPhone por cable, activá el **Modo Desarrollador** (ver abajo), elegilo como destino y tocá ▶︎ **Run**.
6. En el iPhone: **Ajustes → General → VPN y gestión de dispositivos →** tu Apple ID **→ Confiar**.

> ⏳ **Con cuenta gratuita, la app vence a los 7 días.** Para renovarla, volvé a darle ▶︎ Run (tus datos y tu sesión se conservan). Con la cuenta paga de desarrollador (USD 99/año) dura 1 año. La cuenta gratuita permite hasta 3 apps instaladas así.

### Opción B: sin Mac (GitHub Actions + Sideloadly o AltStore)

**1. Compilar el .ipa en GitHub**

1. Creá un repositorio en GitHub (puede ser privado) y subí esta carpeta completa, incluida `.github/`. Sin git instalado, lo más fácil es [GitHub Desktop](https://desktop.github.com/), o arrastrar la carpeta en *Add file → Upload files*.
2. Pestaña **Actions → Build IPA → Run workflow**. También corre solo con cada push a `main`.
3. Cuando termine (~3–6 min), abrí la ejecución y bajá **Artifacts → InstaDM-ipa**. Es un `.zip`: adentro está `InstaDM-unsigned.ipa`.

> En repos **privados**, los minutos de macOS cuentan ×10 contra los 2.000 minutos gratis por mes (≈200 min reales de Mac, unas 30–60 compilaciones). En repos públicos son gratis.

**2. Firmar e instalar con Sideloadly (recomendado en Windows)**

1. Instalá **iTunes** e **iCloud** en la versión que se descarga del sitio de Apple, *no* la de Microsoft Store. Sideloadly las necesita para comunicarse con el iPhone.
2. Instalá [Sideloadly](https://sideloadly.io/).
3. Conectá el iPhone por cable y aceptá **"Confiar en esta computadora"**.
4. En Sideloadly: arrastrá el `.ipa`, poné tu Apple ID y tocá **Start**. Te va a pedir la contraseña y el código de doble factor.
   *Recomendado:* usar un Apple ID secundario para firmar con herramientas de terceros.
5. En el iPhone: activá el **Modo Desarrollador** si te lo pide y confiá en el perfil (**Ajustes → General → VPN y gestión de dispositivos**).
6. **Renovación:** con Apple ID gratuito vence a los 7 días. Repetí el paso 4 o activá el *auto-refresh* de Sideloadly, que renueva por Wi-Fi si la PC está prendida.

**Alternativa: AltStore**

1. Instalá **AltServer** para Windows desde [altstore.io](https://altstore.io/), con iTunes e iCloud de la web de Apple.
2. Desde el ícono de AltServer en la bandeja del sistema: **Install AltStore →** tu iPhone.
3. Pasá el `.ipa` al iPhone (Archivos o iCloud Drive), abrí AltStore → **My Apps → +** y elegilo.
4. AltStore renueva solo cada 7 días si AltServer está corriendo en la misma red Wi-Fi.

### Activar el Modo Desarrollador (iOS 16+)

1. Intentá instalar la app una vez (con Xcode, Sideloadly o AltStore). Recién ahí aparece la opción.
2. **Ajustes → Privacidad y seguridad → Modo de desarrollador →** activarlo.
3. El iPhone se reinicia. Al volver, confirmá con **Activar** y tu código.
4. Si al abrir la app dice "Desarrollador no confiable": **Ajustes → General → VPN y gestión de dispositivos →** tu Apple ID **→ Confiar**.

---

## Depurar y ajustar selectores

- La app tiene `isInspectable = true`. Desde un Mac: **Safari → Desarrollo → [tu iPhone] → InstaDM** abre el Web Inspector sobre la web de Instagram.
- En la consola del inspector:
  - `__INSTADM__` muestra la configuración que llegó desde Swift.
  - `__INSTADM_EVALUAR__('/reels/')` dice si una ruta está bloqueada y por qué.
  - `document.querySelectorAll('[data-instadm-oculto]')` lista lo que el script ocultó.
- Si aparece el aviso **"Demasiadas redirecciones"**, Instagram cambió alguna ruta (por ejemplo, la del login) y entró en bucle. La app deja de redirigir para no trabarse. Ajustá `BlockRules.swift`.

---

## Puntos frágiles (lo que Instagram puede cambiar) y dónde ajustarlo

| Punto frágil | Síntoma si cambia | Dónde ajustarlo |
|---|---|---|
| Ruta del feed de Reels `/reels/` y de reels individuales `/reel/<id>/`, `/reels/<id>/` | Se puede entrar a Reels, o no abren los reels de DM | `bloqueadas` y `reelIndividual` en `BlockRules.swift` |
| Rutas de Explorar `/explore/…`, audio `/reels/audio/…` y pestaña de perfil `/<usuario>/reels/` | Aparece Explorar o una lista de reels | `bloqueadas` en `BlockRules.swift` |
| Rutas de login y verificación (`/accounts/`, `/challenge/`, `/auth_platform/`, `/two_factor`) | No podés iniciar sesión en modo Solo mensajes | `permitidasSoloMensajes` en `BlockRules.swift` |
| Bandeja de DMs en `/direct/inbox/` | Pantalla en blanco o bucle al abrir | `urlMensajes` en `BlockRules.swift` |
| Redirector de links externos `l.instagram.com/?u=` | Los links externos abren una página intermedia | `hostRedirector` en `BlockRules.swift` |
| Dominios de login con Facebook o Centro de cuentas | El login con Facebook se abre en Safari y no vuelve | `dominiosDeLogin` en `BlockRules.swift` |
| Los botones de navegación son `<a href="/reels/">` y `<a href="/explore/">` | El botón vuelve a aparecer (igual se bloquea al tocarlo) | `ocultarEnlaces` en `BlockRules.swift` y el CSS rápido en `inject.js` (sección 2) |
| Posts del feed como `<article>` y reels detectados por `<video>` o un link a `/reel/` | Aparecen reels en Inicio | `revisarFeed()` en `inject.js` (sección 5) |
| El visor de reels es un contenedor con scroll vertical, y los comentarios usan `role="dialog"` | Se puede deslizar al siguiente reel: igual se bloquea por URL y vuelve al chat | `revisarReel()`, `alTocar()` y `alMover()` en `inject.js` (sección 6) |
| Instagram navega con `history.pushState` | Se ve un instante la sección bloqueada antes de redirigir (lo ataja el vigilante de URL) | sección 4 de `inject.js` y `urlCambio()` en `WebView.swift` |
| Instagram respeta un User-Agent de Safari móvil | Aparece la web de escritorio o un "abrí la app" | `userAgent` en `BlockRules.swift` |

---

## Limitaciones

- Sin notificaciones push (fuera de alcance).
- Instagram puede pedir una verificación la primera vez que inicies sesión desde la app, porque la ve como un navegador nuevo.
- Las funciones que la web móvil de Instagram no tiene (por ejemplo, algunas llamadas) tampoco van a estar acá.
- Ocultar reels del feed y frenar el swipe son *best-effort*. El bloqueo por URL es el que da la garantía.
