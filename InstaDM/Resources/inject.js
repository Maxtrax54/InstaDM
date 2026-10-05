/*
 * inject.js — InstaDM
 * ─────────────────────────────────────────────────────────────────────────────
 * Se inyecta en cada página (WKUserScript, atDocumentEnd, también en iframes).
 * Antes de este archivo, Swift inyecta window.__INSTADM__ con la configuración
 * generada desde BlockRules.swift (rutas, modo, textos). Las reglas se editan
 * ALLÁ, no acá.
 *
 * Qué hace:
 *   1. Oculta los botones de navegación a Reels / Explorar (por href, NO por clases:
 *      Instagram ofusca los nombres de clase y los cambia seguido).
 *   2. Cancela los clicks en links hacia rutas bloqueadas (fase de captura).
 *   3. Parchea history.pushState / replaceState: Instagram es una SPA y cambia de
 *      "página" sin recargar, así que WKNavigationDelegate no se entera.
 *   4. Modo "Mensajes + Inicio": oculta reels/videos del feed (best-effort).
 *   5. Dentro de un reel abierto: impide el swipe al siguiente reel (best-effort).
 *
 * ⚠️ evaluar() repite BlockRules.evaluarRuta (Swift). Si cambiás una, cambiá la otra.
 */
(function () {
  'use strict';

  var CFG = window.__INSTADM__;
  if (!CFG || window.__INSTADM_ACTIVO__) return;                              // sin config o ya inyectado
  if ((CFG.hostsInstagram || []).indexOf(location.hostname) === -1) return;   // solo dentro de Instagram
  window.__INSTADM_ACTIVO__ = true;

  var FRAME_PRINCIPAL = (window.top === window);
  var MODO_INICIO = (CFG.modo === 'mensajesEInicio');
  var ATR_OCULTO = 'data-instadm-oculto';   // marca lo que ocultamos nosotros
  var ATR_SCROLL = 'data-instadm-scroll';   // marca el contenedor de reels sin scroll


  /* ── 1. Reglas (vienen de BlockRules.swift) ─────────────────────────────── */

  function regex(patron) {
    try { return new RegExp(patron, 'i'); } catch (e) { return null; }
  }
  function compilarReglas(lista) {
    return (lista || [])
      .map(function (r) { return { re: regex(r.patron), aviso: r.aviso }; })
      .filter(function (r) { return r.re; });
  }
  function compilarPatrones(lista) {
    return (lista || []).map(regex).filter(Boolean);
  }

  var BLOQUEADAS        = compilarReglas(CFG.bloqueadas);
  var BLOQUEADAS_INICIO = compilarReglas(CFG.bloqueadasModoInicio);
  var PERMITIDAS_MSJ    = compilarPatrones(CFG.permitidasSoloMensajes);
  var OCULTAR_ENLACES   = compilarPatrones(CFG.ocultarEnlaces);
  var REEL              = regex(CFG.reelIndividual);

  function primeraRegla(reglas, path) {
    for (var i = 0; i < reglas.length; i++) if (reglas[i].re.test(path)) return reglas[i];
    return null;
  }
  function algunPatron(patrones, path) {
    for (var i = 0; i < patrones.length; i++) if (patrones[i].test(path)) return true;
    return false;
  }
  function idDeReel(path) {
    var m = (REEL && path) ? REEL.exec(path) : null;
    return m ? m[1] : null;
  }

  // null = permitido · { aviso, accion } = bloqueado.
  // accion: 'mensajes' (ir a la bandeja) | 'volver' (página anterior)
  function evaluar(path, pathAnterior) {
    var regla = primeraRegla(BLOQUEADAS, path);
    if (regla) return { aviso: regla.aviso, accion: 'mensajes' };

    var reel = idDeReel(path);
    if (reel) {
      var reelAnterior = idDeReel(pathAnterior);
      if (reelAnterior && reelAnterior !== reel) return { aviso: CFG.avisoSiguienteReel, accion: 'volver' };
      return null;
    }

    if (!MODO_INICIO) {
      return algunPatron(PERMITIDAS_MSJ, path) ? null : { aviso: CFG.avisoSoloMensajes, accion: 'mensajes' };
    }
    regla = primeraRegla(BLOQUEADAS_INICIO, path);
    return regla ? { aviso: regla.aviso, accion: 'mensajes' } : null;
  }
  window.__INSTADM_EVALUAR__ = evaluar;   // para probar rutas desde el Web Inspector

  function aURL(valor) {
    try { return new URL(String(valor), location.href); } catch (e) { return null; }
  }
  function esDeInstagram(u) {
    return !!u && CFG.hostsInstagram.indexOf(u.hostname) !== -1;
  }

  // Avisa a Swift: muestra el toast y aplica la acción.
  function avisarANativo(aviso, accion) {
    try {
      window.webkit.messageHandlers.instadm.postMessage({ tipo: 'bloqueado', aviso: aviso, accion: accion });
    } catch (e) {
      // Sin puente nativo (no debería pasar): lo resolvemos acá.
      if (accion === 'mensajes') location.replace(CFG.mensajes);
      else if (accion === 'volver') history.back();
    }
  }


  /* ── 2. Ocultar botones de Reels / Explorar ─────────────────────────────── */

  // Camino rápido con CSS para los href exactos más comunes (oculta al instante).
  // Si la política de seguridad de la página bloquea el <style>, igual actúa revisarEnlaces().
  try {
    var css = document.createElement('style');
    css.id = 'instadm-css';
    css.textContent = 'a[href="/reels/"],a[href="/reels"],a[href="/explore/"],a[href="/explore"]{display:none!important}';
    (document.head || document.documentElement).appendChild(css);
  } catch (e) { /* sin CSS rápido */ }

  // Estilos inline que tenía cada elemento antes de tocarlo, para poder restaurarlos.
  var originales = new WeakMap();

  function fijarEstilos(el, estilos) {
    var previos = originales.get(el) || {};
    for (var prop in estilos) {
      if (!(prop in previos)) previos[prop] = [el.style.getPropertyValue(prop), el.style.getPropertyPriority(prop)];
      el.style.setProperty(prop, estilos[prop], 'important');
    }
    originales.set(el, previos);
  }
  function restaurarEstilos(el, props) {
    var previos = originales.get(el) || {};
    props.forEach(function (prop) {
      var p = previos[prop];
      if (p && p[0]) el.style.setProperty(prop, p[0], p[1]);
      else el.style.removeProperty(prop);
      delete previos[prop];
    });
  }

  function ocultar(el, motivo) {
    if (el.hasAttribute(ATR_OCULTO)) return;
    el.setAttribute(ATR_OCULTO, motivo);
    fijarEstilos(el, { display: 'none' });
  }
  function mostrar(el) {
    el.removeAttribute(ATR_OCULTO);
    restaurarEstilos(el, ['display']);
  }

  function revisarEnlaces() {
    var enlaces = document.querySelectorAll('a[href]');
    for (var i = 0; i < enlaces.length; i++) {
      var a = enlaces[i];
      var u = aURL(a.getAttribute('href'));
      if (esDeInstagram(u) && algunPatron(OCULTAR_ENLACES, u.pathname)) {
        ocultar(a, 'enlace');
      } else if (a.getAttribute(ATR_OCULTO) === 'enlace') {
        mostrar(a);   // React reutilizó el nodo con otro href
      }
    }
  }


  /* ── 3. Cancelar clicks hacia rutas bloqueadas ──────────────────────────── */

  function alHacerClick(e) {
    var a = (e.target && e.target.closest) ? e.target.closest('a[href]') : null;
    if (!a) return;
    var u = aURL(a.getAttribute('href'));
    if (!esDeInstagram(u)) return;               // links externos: los resuelve Swift (Safari)
    var bloqueo = evaluar(u.pathname, location.pathname);
    if (!bloqueo) return;
    e.preventDefault();
    e.stopImmediatePropagation();                // que Instagram ni se entere del click
    avisarANativo(bloqueo.aviso, 'ninguna');     // nos quedamos donde estamos
  }


  /* ── 4. Navegación interna de la SPA (pushState / replaceState) ─────────── */

  function parchearHistorial(nombre) {
    var original = history[nombre];
    if (typeof original !== 'function') return;
    history[nombre] = function (state, title, url) {
      if (url !== undefined && url !== null) {
        var u = aURL(url);
        if (esDeInstagram(u)) {
          var bloqueo = evaluar(u.pathname, location.pathname);
          if (bloqueo) {
            avisarANativo(bloqueo.aviso, bloqueo.accion);
            return;                              // la URL no cambia; Swift redirige
          }
        }
      }
      var resultado = original.apply(this || history, arguments);
      programarRevision();
      return resultado;
    };
  }


  /* ── 5. Feed sin reels (modo Mensajes + Inicio, best-effort) ────────────── */

  // Cada post del feed es un <article>. Si adentro hay un <video> o un link a /reel/…,
  // lo ocultamos entero.
  function revisarFeed() {
    if (!MODO_INICIO || !CFG.ocultarReelsEnFeed || location.pathname !== '/') return;
    var posts = document.querySelectorAll('article');
    for (var i = 0; i < posts.length; i++) {
      if (posts[i].hasAttribute(ATR_OCULTO)) continue;
      if (posts[i].querySelector('video, a[href*="/reel/"]')) ocultar(posts[i], 'feed');
    }
  }


  /* ── 6. Reel abierto: sin swipe al siguiente (best-effort) ──────────────── */
  // La garantía real es la regla "de un reel a OTRO reel = bloqueado" (acá y en Swift).
  // Esto evita que el gesto llegue a pasar.

  function estamosEnUnReel() {
    return !!CFG.bloquearSwipeEnReel && !!idDeReel(location.pathname);
  }

  // 6a. Al contenedor con scroll que tiene el video y mide más de 1,5 pantallas
  //     (o sea, una tira de reels) le sacamos el scroll vertical.
  function revisarReel() {
    var enReel = estamosEnUnReel();
    var bloqueados = document.querySelectorAll('[' + ATR_SCROLL + ']');
    if (!enReel) {
      for (var i = 0; i < bloqueados.length; i++) {   // salimos del reel: devolver el scroll
        restaurarEstilos(bloqueados[i], ['overflow-y', 'overscroll-behavior']);
        bloqueados[i].removeAttribute(ATR_SCROLL);
      }
      return;
    }
    if (bloqueados.length) return;                    // ya está bloqueado

    // Revisamos todos los videos visibles (puede haber otros ocultos o precargados).
    var videos = document.querySelectorAll('video');
    for (var v = 0; v < videos.length; v++) {
      if (!videos[v].offsetWidth || !videos[v].offsetHeight) continue;
      var el = videos[v].parentElement;
      for (; el && el !== document.body && el !== document.documentElement; el = el.parentElement) {
        var cs = getComputedStyle(el);
        var tieneScroll = (cs.overflowY === 'auto' || cs.overflowY === 'scroll');
        if (tieneScroll && el.scrollHeight > el.clientHeight * 1.5) {
          el.setAttribute(ATR_SCROLL, '1');
          fijarEstilos(el, { 'overflow-y': 'hidden', 'overscroll-behavior': 'none' });
          return;
        }
      }
    }
  }

  // 6b. Además frenamos el gesto vertical que empieza sobre el video
  //     (por si Instagram mueve los reels con JavaScript en vez de con scroll).
  var toque = null;

  function hayVideoEn(x, y) {
    var videos = document.querySelectorAll('video');
    for (var i = 0; i < videos.length; i++) {
      var r = videos[i].getBoundingClientRect();
      if (x >= r.left && x <= r.right && y >= r.top && y <= r.bottom) return true;
    }
    return false;
  }

  function alTocar(e) {
    toque = null;
    if (!estamosEnUnReel() || e.touches.length !== 1) return;
    var t = e.touches[0];
    if (t.clientX < 30) return;                                            // borde: gesto de volver
    if (e.target.closest && e.target.closest('[role="dialog"]')) return;   // comentarios, menús
    if (hayVideoEn(t.clientX, t.clientY)) toque = { x: t.clientX, y: t.clientY };
  }

  function alMover(e) {
    if (!toque || e.touches.length !== 1) return;
    var t = e.touches[0];
    if (Math.abs(t.clientY - toque.y) >= Math.abs(t.clientX - toque.x)) {  // gesto vertical
      e.preventDefault();
      e.stopPropagation();
    }
  }

  function alSoltar() { toque = null; }


  /* ── 7. Observador del DOM (con debounce) y arranque ────────────────────── */

  // Instagram cambia el DOM todo el tiempo sin recargar. Agrupamos los cambios y
  // revisamos como mucho una vez cada 150 ms.
  var temporizador = null;
  function programarRevision() {
    if (temporizador) return;
    temporizador = setTimeout(function () {
      temporizador = null;
      revisar();
    }, 150);
  }

  function revisar() {
    try {
      revisarEnlaces();
      if (FRAME_PRINCIPAL) {
        revisarFeed();
        revisarReel();
      }
    } catch (e) { /* nunca romper la página */ }
  }

  new MutationObserver(programarRevision).observe(document.documentElement, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ['href']
  });

  if (FRAME_PRINCIPAL) {
    window.addEventListener('click', alHacerClick, true);   // true = fase de captura
    parchearHistorial('pushState');
    parchearHistorial('replaceState');
    window.addEventListener('popstate', programarRevision);
    window.addEventListener('touchstart', alTocar, { capture: true, passive: true });
    window.addEventListener('touchmove', alMover, { capture: true, passive: false });
    window.addEventListener('touchend', alSoltar, true);
    window.addEventListener('touchcancel', alSoltar, true);
  }

  revisar();
})();
