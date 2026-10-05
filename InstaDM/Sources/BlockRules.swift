//
//  BlockRules.swift
//  InstaDM
//
//  ⚙️ TODA la configuración de bloqueo está ARRIBA de este archivo.
//
//  Los patrones son expresiones regulares que se comparan contra el PATH de la URL
//  (ej. "/direct/inbox/"), sin distinguir mayúsculas. Se usan igual en Swift y en
//  inject.js (Swift se los pasa como JSON), así que usá sintaxis simple que entiendan
//  los dos:  ^  $  ?  *  +  .  [a-z]  [^/]  (a|b)
//

import Foundation

struct BlockRules {

    // MARK: - ⚙️ CONFIGURACIÓN ────────────────────────────────────────────────

    /// Pantalla principal (bandeja de mensajes) y destino de las redirecciones.
    static let urlMensajes = URL(string: "https://www.instagram.com/direct/inbox/")!

    /// Feed de Inicio (solo en modo "Mensajes + Inicio").
    static let urlInicio = URL(string: "https://www.instagram.com/")!

    /// Hosts de Instagram que se abren DENTRO de la app (con las reglas de abajo).
    static let hostsInstagram: Set<String> = ["instagram.com", "www.instagram.com", "m.instagram.com"]

    /// Redirector de links externos (l.instagram.com/?u=<url real>): se abre la URL real en Safari.
    static let hostRedirector = "l.instagram.com"

    /// Dominios que se abren dentro de la app SIN reglas (login con Facebook, Centro de cuentas).
    /// Incluye sus subdominios. Cualquier otro dominio se abre en Safari.
    static let dominiosDeLogin = ["facebook.com", "accountscenter.instagram.com", "meta.com"]

    /// 🚫 Bloqueadas SIEMPRE, en los dos modos (patrón + aviso que se muestra).
    static let bloqueadas: [Regla] = [
        Regla(#"^/reels/?$"#,        "Reels bloqueados"),     // feed de Reels (sin ID)
        Regla(#"^/reels/audio/"#,    "Reels bloqueados"),     // reels que usan un audio
        Regla(#"^/[^/]+/reels/?$"#,  "Reels bloqueados"),     // pestaña Reels de un perfil
        Regla(#"^/explore(/.*)?$"#,  "Explorar bloqueado"),   // Explorar, búsqueda, hashtags, lugares
    ]

    /// ✅ Reel individual (el que te mandan por DM): /reel/<id>/ o /reels/<id>/.
    /// Los paréntesis capturan el ID. Abrir UN reel está permitido; pasar de un reel
    /// a OTRO distinto (el swipe al siguiente) se bloquea.
    static let reelIndividual = #"^/reels?/([A-Za-z0-9_-]+)"#

    /// ✅ Modo "Solo mensajes": únicamente estas rutas (además del reel individual).
    static let permitidasSoloMensajes: [String] = [
        #"^/direct(/.*)?$"#,    // bandeja de entrada y chats
        #"^/accounts/"#,        // login, "¿guardar datos?", recuperar contraseña
        #"^/challenge/"#,       // verificaciones de seguridad
        #"^/auth_platform/"#,   // códigos de verificación
        #"^/two_factor"#,       // verificación en dos pasos
        #"^/oauth/"#,
        // #"^/p/[A-Za-z0-9_-]+"#,   // ← descomentá para abrir posts que te mandan por DM
        // #"^/stories/"#,           // ← descomentá para abrir historias que te mandan por DM
    ]

    /// 🚫 Modo "Mensajes + Inicio": se permite todo lo demás (perfiles, posts…) salvo esto.
    static let bloqueadasModoInicio: [Regla] = [
        // Regla(#"^/stories/"#, "Historias bloqueadas"),   // ejemplo
    ]

    /// Links que se OCULTAN de la interfaz de Instagram (botones de navegación).
    static let ocultarEnlaces: [String] = [
        #"^/reels/?$"#,
        #"^/explore/?$"#,
        #"^/explore/search/?$"#,
    ]

    /// Ocultar posts que sean reels/videos en el feed de Inicio (best-effort).
    static let ocultarReelsEnFeed = true

    /// Impedir el scroll/swipe al siguiente reel dentro de un reel abierto (best-effort).
    static let bloquearSwipeEnReel = true

    /// Textos de los avisos.
    static let avisoSoloMensajes = "Bloqueado en modo Solo mensajes"
    static let avisoSiguienteReel = "Solo podés ver el reel que te mandaron"

    /// User-Agent de Safari en iPhone con la versión real de iOS (para recibir la web móvil).
    static var userAgent: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(v.majorVersion)_\(v.minorVersion) like Mac OS X) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(v.majorVersion).\(v.minorVersion) "
            + "Mobile/15E148 Safari/604.1"
    }

    // MARK: - FIN DE LA CONFIGURACIÓN ─────────────────────────────────────────
}

// MARK: - Tipos

/// Los dos modos de la app (se guardan en UserDefaults).
enum ModoApp: String {
    case soloMensajes       // por defecto: solo DMs
    case mensajesEInicio    // DMs + feed de Inicio, perfiles y posts
}

/// Qué hacer después de bloquear. El rawValue es el mismo texto que usa inject.js.
enum AccionBloqueo: String {
    case irAMensajes = "mensajes"   // cargar la bandeja de entrada
    case volverAtras = "volver"     // volver a la página anterior (ej. el chat de donde vino el reel)
    case ninguna     = "ninguna"    // quedarse donde está; solo mostrar el aviso
}

/// Resultado de evaluar una navegación.
enum DecisionNavegacion {
    case permitir
    case bloquear(aviso: String, accion: AccionBloqueo)
    case abrirAfuera(URL)   // Safari integrado o app del sistema
    case ignorar            // cancelar sin hacer nada
}

// MARK: - Lógica (normalmente no hace falta tocarla)

extension BlockRules {

    struct Regla: Encodable {
        let patron: String
        let aviso: String

        init(_ patron: String, _ aviso: String) {
            self.patron = patron
            self.aviso = aviso
        }
    }

    /// Decide qué hacer con una navegación de la página principal.
    /// `anterior` es la URL donde está el WebView (sirve para detectar el swipe de un reel a otro).
    static func decidir(_ url: URL, anterior: URL?, modo: ModoApp) -> DecisionNavegacion {
        switch url.scheme?.lowercased() ?? "" {
        case "http", "https":
            break
        case "about", "blob", "data":
            return .permitir
        case "instagram":
            return .ignorar                 // nunca abrir la app oficial
        default:
            return .abrirAfuera(url)        // mailto:, tel:, itms-apps:, etc.
        }

        let host = url.host?.lowercased() ?? ""

        if host == hostRedirector {
            return .abrirAfuera(destinoDelRedirector(url) ?? url)
        }

        if hostsInstagram.contains(host) {
            let pathAnterior = anterior.flatMap { pathDeInstagram($0) }
            if let bloqueo = evaluarRuta(path(de: url), anterior: pathAnterior, modo: modo) {
                return .bloquear(aviso: bloqueo.aviso, accion: bloqueo.accion)
            }
            return .permitir
        }

        if dominiosDeLogin.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return .permitir
        }

        return .abrirAfuera(url)
    }

    /// Reglas de rutas de Instagram. Devuelve nil si la ruta está permitida.
    /// ⚠️ inject.js repite esta lógica en evaluar(). Si cambiás una, cambiá la otra.
    static func evaluarRuta(_ path: String, anterior: String?, modo: ModoApp)
        -> (aviso: String, accion: AccionBloqueo)? {

        // 1. Bloqueadas siempre
        if let regla = bloqueadas.first(where: { coincide($0.patron, path) }) {
            return (aviso: regla.aviso, accion: .irAMensajes)
        }

        // 2. Reel individual: permitido, salvo que vengas de OTRO reel (= swipe al siguiente)
        if let id = idDeReel(path) {
            if let idAnterior = anterior.flatMap({ idDeReel($0) }), idAnterior != id {
                return (aviso: avisoSiguienteReel, accion: .volverAtras)
            }
            return nil
        }

        // 3. Según el modo
        switch modo {
        case .soloMensajes:
            if permitidasSoloMensajes.contains(where: { coincide($0, path) }) {
                return nil
            }
            return (aviso: avisoSoloMensajes, accion: .irAMensajes)

        case .mensajesEInicio:
            if let regla = bloqueadasModoInicio.first(where: { coincide($0.patron, path) }) {
                return (aviso: regla.aviso, accion: .irAMensajes)
            }
            return nil
        }
    }

    /// ID del reel si el path es /reel/<id>/ o /reels/<id>/ (si no, nil).
    static func idDeReel(_ path: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: reelIndividual, options: .caseInsensitive),
              let match = regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)),
              match.numberOfRanges > 1,
              let rango = Range(match.range(at: 1), in: path)
        else { return nil }
        return String(path[rango])
    }

    /// Path tal cual, con la barra final (igual que location.pathname en JavaScript).
    static func path(de url: URL) -> String {
        let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? url.path
        return path.isEmpty ? "/" : path
    }

    /// Path solo si la URL es de Instagram (si no, nil).
    static func pathDeInstagram(_ url: URL) -> String? {
        hostsInstagram.contains(url.host?.lowercased() ?? "") ? path(de: url) : nil
    }

    /// Configuración para inject.js. Se inyecta como `window.__INSTADM__ = {...}`
    /// antes que el script, así las reglas viven en un solo lugar (este archivo).
    static func scriptDeConfiguracion(modo: ModoApp) -> String {
        struct ConfigJS: Encodable {
            let modo: String
            let mensajes: String
            let hostsInstagram: [String]
            let bloqueadas: [Regla]
            let reelIndividual: String
            let permitidasSoloMensajes: [String]
            let bloqueadasModoInicio: [Regla]
            let ocultarEnlaces: [String]
            let ocultarReelsEnFeed: Bool
            let bloquearSwipeEnReel: Bool
            let avisoSoloMensajes: String
            let avisoSiguienteReel: String
        }

        let config = ConfigJS(
            modo: modo.rawValue,
            mensajes: path(de: urlMensajes),
            hostsInstagram: hostsInstagram.sorted(),
            bloqueadas: bloqueadas,
            reelIndividual: reelIndividual,
            permitidasSoloMensajes: permitidasSoloMensajes,
            bloqueadasModoInicio: bloqueadasModoInicio,
            ocultarEnlaces: ocultarEnlaces,
            ocultarReelsEnFeed: ocultarReelsEnFeed,
            bloquearSwipeEnReel: bloquearSwipeEnReel,
            avisoSoloMensajes: avisoSoloMensajes,
            avisoSiguienteReel: avisoSiguienteReel
        )
        let json = (try? JSONEncoder().encode(config)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
        return "window.__INSTADM__ = \(json);"
    }

    // MARK: Ayudantes privados

    private static func coincide(_ patron: String, _ texto: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: patron, options: .caseInsensitive) else {
            return false
        }
        return regex.firstMatch(in: texto, range: NSRange(texto.startIndex..., in: texto)) != nil
    }

    /// l.instagram.com/?u=https%3A%2F%2Fejemplo.com → https://ejemplo.com
    private static func destinoDelRedirector(_ url: URL) -> URL? {
        guard let valor = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "u" })?.value,
              let destino = URL(string: valor),
              ["http", "https"].contains(destino.scheme?.lowercased() ?? "")
        else { return nil }
        return destino
    }
}
