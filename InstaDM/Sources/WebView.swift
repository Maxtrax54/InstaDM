//
//  WebView.swift
//  InstaDM
//
//  El WKWebView y toda su lógica:
//   • bloqueo de navegación (decidePolicyFor + vigilante de URL para la SPA)
//   • links externos y target="_blank" → Safari integrado (SFSafariViewController)
//   • puente con inject.js (avisos de bloqueo)
//   • sesión persistente, pull-to-refresh, permisos de cámara/micrófono, alert/confirm
//
//  La subida de fotos/videos (<input type="file">) la resuelve WKWebView solo:
//  muestra el menú Fototeca / Cámara / Archivos usando los permisos del Info.plist.
//

import SwiftUI
import UIKit
import WebKit
import SafariServices
import Combine

// MARK: - Vista SwiftUI

/// Envoltorio SwiftUI del WKWebView. El WKWebView vive en el modelo, así no se recrea.
/// (Se llama InstagramWebView para no chocar con el `WebView` que trae iOS 26.)
struct InstagramWebView: UIViewRepresentable {
    let modelo: NavegadorModelo

    func makeUIView(context: Context) -> WKWebView { modelo.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - Modelo

@MainActor
final class NavegadorModelo: NSObject, ObservableObject {

    // Estado que muestra la interfaz
    @Published private(set) var puedeVolver = false
    @Published private(set) var cargando = false
    @Published private(set) var progreso: Double = 0
    @Published private(set) var pathActual = "/"
    @Published private(set) var cargaInicialLista = false
    @Published private(set) var aviso: String?          // texto del toast

    /// Modo de la app. Se guarda en UserDefaults y al cambiar se recarga la página.
    @Published var modo: ModoApp {
        didSet { if modo != oldValue { modoCambio() } }
    }

    let webView: WKWebView

    private static let claveModo = "modoApp"
    private let contenido: WKUserContentController
    private let refresco: UIRefreshControl
    private var suscripciones = Set<AnyCancellable>()
    private var ultimaURLPermitida: URL?
    private var redireccionesRecientes: [Date] = []
    private var tareaAviso: Task<Void, Never>?

    override init() {
        let guardado = UserDefaults.standard.string(forKey: Self.claveModo) ?? ""
        modo = ModoApp(rawValue: guardado) ?? .soloMensajes

        contenido = WKUserContentController()
        refresco = UIRefreshControl()

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()                 // cookies y login persistentes
        config.userContentController = contenido
        config.allowsInlineMediaPlayback = true              // videos dentro de la página
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.defaultWebpagePreferences.preferredContentMode = .mobile
        webView = WKWebView(frame: .zero, configuration: config)

        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.customUserAgent = BlockRules.userAgent
        webView.allowsBackForwardNavigationGestures = true   // swipe desde el borde para volver
        webView.isOpaque = false                             // sin destello blanco en modo oscuro
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        if #available(iOS 16.4, *) {
            webView.isInspectable = true                     // depurable desde Safari en un Mac
        }

        refresco.addTarget(self, action: #selector(refrescar), for: .valueChanged)
        webView.scrollView.refreshControl = refresco

        contenido.add(ManejadorDebil(self), name: "instadm") // inject.js → Swift
        instalarScripts()
        observarWebView()

        cargar(BlockRules.urlMensajes)
    }

    // MARK: Acciones de la interfaz

    func irAMensajes() { cargar(BlockRules.urlMensajes) }
    func irAInicio() { cargar(BlockRules.urlInicio) }
    func volver() { if webView.canGoBack { webView.goBack() } }

    /// "Cerrar sesión": borra cookies, caché, localStorage, etc.
    func borrarDatos() {
        Task {
            await WKWebsiteDataStore.default().removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: .distantPast)
            HTTPCookieStorage.shared.removeCookies(since: .distantPast)
            cargar(BlockRules.urlMensajes)
            mostrarAviso("Sesión cerrada y datos borrados")
        }
    }

    /// Toast breve en la parte de abajo.
    func mostrarAviso(_ texto: String) {
        aviso = texto
        tareaAviso?.cancel()
        tareaAviso = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            self?.aviso = nil
        }
    }

    // MARK: Carga y bloqueo

    private func cargar(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    @objc private func refrescar() {
        if webView.url == nil {
            cargar(BlockRules.urlMensajes)
        } else {
            webView.reload()
        }
    }

    /// Muestra el aviso y hace la acción del bloqueo.
    private func aplicarBloqueo(aviso: String, accion: AccionBloqueo) {
        mostrarAviso(aviso)
        switch accion {
        case .ninguna:
            break
        case .irAMensajes:
            cargar(BlockRules.urlMensajes)
        case .volverAtras:
            if webView.canGoBack { webView.goBack() } else { cargar(BlockRules.urlMensajes) }
        }
    }

    /// Anti-bucle: si redirigimos 4 veces en 10 s, algo cambió en Instagram y dejamos de insistir.
    private func puedeRedirigir() -> Bool {
        let ahora = Date()
        redireccionesRecientes = redireccionesRecientes.filter { ahora.timeIntervalSince($0) < 10 }
        guard redireccionesRecientes.count < 4 else { return false }
        redireccionesRecientes.append(ahora)
        return true
    }

    /// Bloqueo pedido por inject.js o detectado por el vigilante de URL.
    private func bloquear(aviso: String, accion: AccionBloqueo) {
        guard accion == .ninguna || puedeRedirigir() else {
            mostrarAviso("Demasiadas redirecciones: revisá BlockRules.swift")
            return
        }
        aplicarBloqueo(aviso: aviso, accion: accion)
    }

    /// Vigilante de URL (red de seguridad). Instagram es una SPA: cambia de "página" con
    /// history.pushState sin pasar por decidePolicyFor. inject.js ya lo frena, pero si
    /// algo se le escapa (o Instagram cambia su código) lo agarramos acá.
    private func urlCambio(_ url: URL?) {
        guard let url else { return }
        if let path = BlockRules.pathDeInstagram(url) { pathActual = path }

        if case .bloquear(let aviso, let accion) = BlockRules.decidir(url, anterior: ultimaURLPermitida, modo: modo) {
            bloquear(aviso: aviso, accion: accion)
        } else {
            ultimaURLPermitida = url
        }
    }

    // MARK: Modo y scripts

    private func modoCambio() {
        UserDefaults.standard.set(modo.rawValue, forKey: Self.claveModo)
        instalarScripts()                                    // la config del JS depende del modo

        guard let url = webView.url else {
            cargar(BlockRules.urlMensajes)
            return
        }
        if case .bloquear = BlockRules.decidir(url, anterior: nil, modo: modo) {
            cargar(BlockRules.urlMensajes)                   // la página actual ya no se permite
        } else {
            webView.reload()
        }
    }

    /// Inyecta 1) la config generada desde BlockRules.swift y 2) inject.js.
    private func instalarScripts() {
        contenido.removeAllUserScripts()
        contenido.addUserScript(WKUserScript(
            source: BlockRules.scriptDeConfiguracion(modo: modo),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false))

        guard let archivo = Bundle.main.url(forResource: "inject", withExtension: "js"),
              let js = try? String(contentsOf: archivo, encoding: .utf8) else {
            assertionFailure("Falta inject.js en el bundle")
            return
        }
        contenido.addUserScript(WKUserScript(
            source: js,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false))
    }

    /// Pasa a la interfaz el estado del WebView (KVO) y vigila los cambios de URL.
    private func observarWebView() {
        webView.publisher(for: \.canGoBack).assign(to: &$puedeVolver)
        webView.publisher(for: \.isLoading).assign(to: &$cargando)
        webView.publisher(for: \.estimatedProgress).assign(to: &$progreso)
        webView.publisher(for: \.url)
            .sink { [weak self] url in self?.urlCambio(url) }
            .store(in: &suscripciones)
    }
}

// MARK: - Navegación (WKNavigationDelegate)

extension NavegadorModelo: WKNavigationDelegate {

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        // Solo controlamos la página principal. Los iframes pasan, y las ventanas nuevas
        // (target="_blank", sin frame destino) se resuelven en createWebViewWith.
        guard let frame = navigationAction.targetFrame, frame.isMainFrame else {
            decisionHandler(.allow)
            return
        }

        switch BlockRules.decidir(url, anterior: webView.url, modo: modo) {
        case .permitir:
            decisionHandler(.allow)

        case .bloquear(let aviso, let accion):
            // Al cancelar una carga completa nos quedamos en la página actual:
            // si era "el siguiente reel" alcanza con eso; si no, vamos a Mensajes.
            let accionFinal: AccionBloqueo = (accion == .volverAtras) ? .ninguna : .irAMensajes
            if accionFinal == .irAMensajes && !puedeRedirigir() {
                // Bucle de redirecciones (ej. un login raro): dejamos pasar para no trabar la app.
                mostrarAviso("Demasiadas redirecciones: se permitió la página")
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            aplicarBloqueo(aviso: aviso, accion: accionFinal)

        case .abrirAfuera(let destino):
            decisionHandler(.cancel)
            abrirAfuera(destino)

        case .ignorar:
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refresco.endRefreshing()
        cargaInicialLista = true
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        refresco.endRefreshing()
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        refresco.endRefreshing()
        cargaInicialLista = true
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code != NSURLErrorCancelled {
            mostrarAviso("No se pudo cargar. ¿Tenés conexión?")
        }
    }

    /// Si iOS mata el proceso web (falta de memoria), recargamos en vez de quedar en blanco.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        refrescar()
    }
}

// MARK: - Ventanas, permisos y diálogos (WKUIDelegate)

extension NavegadorModelo: WKUIDelegate {

    /// target="_blank" y window.open: nunca abrimos ventanas nuevas.
    /// Instagram → en esta misma vista · externos → Safari integrado.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }

        switch BlockRules.decidir(url, anterior: webView.url, modo: modo) {
        case .permitir:
            if ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                webView.load(navigationAction.request)
            }
        case .bloquear(let aviso, _):
            mostrarAviso(aviso)
        case .abrirAfuera(let destino):
            abrirAfuera(destino)
        case .ignorar:
            break
        }
        return nil
    }

    /// Cámara/micrófono pedidos por la web (ej. grabar un audio): se conceden a Instagram
    /// sin el diálogo extra de WebKit. iOS igual pide su permiso la primera vez.
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let esInstagram = BlockRules.hostsInstagram.contains(origin.host.lowercased())
        decisionHandler(esInstagram ? .grant : .prompt)
    }

    /// alert() de JavaScript.
    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let alerta = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alerta.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        presentar(alerta, siNoSePuede: completionHandler)
    }

    /// confirm() de JavaScript (ej. "¿Anular el envío?").
    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let alerta = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alerta.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in completionHandler(false) })
        alerta.addAction(UIAlertAction(title: "Aceptar", style: .default) { _ in completionHandler(true) })
        presentar(alerta, siNoSePuede: { completionHandler(false) })
    }
}

// MARK: - Mensajes desde inject.js (WKScriptMessageHandler)

extension NavegadorModelo: WKScriptMessageHandler {

    /// inject.js manda { tipo: "bloqueado", aviso: "...", accion: "mensajes" | "volver" | "ninguna" }.
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              BlockRules.hostsInstagram.contains(message.frameInfo.securityOrigin.host.lowercased()),
              let datos = message.body as? [String: Any],
              (datos["tipo"] as? String) == "bloqueado"
        else { return }

        let aviso = datos["aviso"] as? String ?? "Bloqueado"
        let accion = AccionBloqueo(rawValue: datos["accion"] as? String ?? "") ?? .ninguna
        bloquear(aviso: aviso, accion: accion)
    }
}

// MARK: - Safari y alertas

extension NavegadorModelo {

    /// Links externos: Safari integrado (http/https) o la app del sistema (mailto:, tel:, …).
    private func abrirAfuera(_ url: URL) {
        let esWeb = ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        if esWeb, let visible = controladorVisible() {
            visible.present(SFSafariViewController(url: url), animated: true)
        } else {
            UIApplication.shared.open(url)
        }
    }

    private func presentar(_ controlador: UIViewController, siNoSePuede alternativa: () -> Void) {
        if let visible = controladorVisible() {
            visible.present(controlador, animated: true)
        } else {
            alternativa()
        }
    }

    /// El view controller que está arriba de todo (para presentar encima).
    private func controladorVisible() -> UIViewController? {
        var actual = webView.window?.rootViewController
        while let presentado = actual?.presentedViewController {
            actual = presentado
        }
        return actual
    }
}

// MARK: - Intermediario débil

/// WKUserContentController retiene a su handler; este intermediario evita el ciclo
/// de retención (sin él, el modelo nunca se liberaría).
private final class ManejadorDebil: NSObject, WKScriptMessageHandler {
    weak var destino: WKScriptMessageHandler?

    init(_ destino: WKScriptMessageHandler) {
        self.destino = destino
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        destino?.userContentController(userContentController, didReceive: message)
    }
}
