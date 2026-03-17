//
//  NoCodesViewController.swift
//  NoCodes
//
//  Created by Suren Sarkisyan on 23.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation

#if os(iOS)
import UIKit
import WebKit
import SafariServices
@_exported import Qonversion

enum Constants: String {
  case url
  case deeplink
  case screenId
  case productId
  case setProducts
}

protocol NoCodesViewControllerDelegate {
  
  func noCodesHasShownScreen(id: String)
  
  func noCodesStartsExecuting(action: NoCodesAction)
  
  func noCodesFailedToExecute(action: NoCodesAction, error: Error?)
  
  func noCodesFinishedExecuting(action: NoCodesAction)
  
  func noCodesFinished()
  
  func noCodesFailedToLoadScreen(error: Error?)
  
}

final class NoCodesViewController: UIViewController {
  
  private var webView: WKWebView!
  private var activityIndicator: UIActivityIndicatorView!
  private var screenId: String?
  private var contextKey: String?
  private var screen: NoCodesScreen?
  private var noCodesService: NoCodesServiceInterface!
  private var screenEventsService: ScreenEventsServiceInterface!
  private var noCodesMapper: NoCodesMapperInterface!
  private var viewsAssembly: ViewsAssembly!
  private var delegate: NoCodesViewControllerDelegate!
  private var logger: LoggerWrapper!
  private var loadingView: NoCodesLoadingView!
  private var presentationConfiguration: NoCodesPresentationConfiguration!
  private var purchaseDelegate: NoCodesPurchaseDelegate?
  private var screenCustomizationDelegate: NoCodesScreenCustomizationDelegate?
  private var customLocale: String?
  private var theme: NoCodesTheme!
  private var didTrackScreenShown = false
  private var didTrackScreenClosed = false
  private var contextBuilder: NoCodesContextBuilderInterface!
  private var htmlInjector: NoCodesHTMLInjectorInterface!

  init(screenId: String?, contextKey: String?, delegate: NoCodesViewControllerDelegate, purchaseDelegate: NoCodesPurchaseDelegate?, screenCustomizationDelegate: NoCodesScreenCustomizationDelegate?, noCodesMapper: NoCodesMapperInterface, noCodesService: NoCodesServiceInterface, screenEventsService: ScreenEventsServiceInterface, viewsAssembly: ViewsAssembly, logger: LoggerWrapper, presentationConfiguration: NoCodesPresentationConfiguration, contextBuilder: NoCodesContextBuilderInterface, htmlInjector: NoCodesHTMLInjectorInterface, customLocale: String? = nil, theme: NoCodesTheme = .auto) {
    self.screenId = screenId
    self.contextKey = contextKey
    self.noCodesMapper = noCodesMapper
    self.noCodesService = noCodesService
    self.screenEventsService = screenEventsService
    self.viewsAssembly = viewsAssembly
    self.delegate = delegate
    self.logger = logger
    self.presentationConfiguration = presentationConfiguration
    self.purchaseDelegate = purchaseDelegate
    self.screenCustomizationDelegate = screenCustomizationDelegate
    self.customLocale = customLocale
    self.theme = theme
    self.contextBuilder = contextBuilder
    self.htmlInjector = htmlInjector

    super.init(nibName: nil, bundle: nil)

    if let customLoadingView = screenCustomizationDelegate?.noCodesCustomLoadingView() {
      loadingView = customLoadingView
    } else {
      let interfaceStyle = contextBuilder.resolveInterfaceStyle(theme: theme, traitCollection: traitCollection)
      loadingView = SkeletonView(frame: view.frame, interfaceStyle: interfaceStyle)
    }
    addLoadingView()
  }
  
  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }
  
  override var prefersStatusBarHidden: Bool {
    return presentationConfiguration.statusBarHidden
  }
    
  override func viewDidLoad() {
    super.viewDidLoad()
    
    let userContentController = WKUserContentController()
    userContentController.add(self, name: "noCodesMessageHandler")

    let contextScript = contextBuilder.buildContextScript(theme: theme, traitCollection: traitCollection)
    let userScript = WKUserScript(
      source: contextScript,
      injectionTime: .atDocumentStart,
      forMainFrameOnly: true
    )
    userContentController.addUserScript(userScript)

    let configuration = WKWebViewConfiguration()
    configuration.userContentController = userContentController
    
    configuration.allowsInlineMediaPlayback = true
    configuration.allowsAirPlayForMediaPlayback = true
    configuration.mediaTypesRequiringUserActionForPlayback = []
    configuration.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
    
    webView = WKWebView(frame: .zero, configuration: configuration)
    webView.scrollView.contentInsetAdjustmentBehavior = .never
    
    webView.scrollView.showsHorizontalScrollIndicator = false
    webView.scrollView.delegate = self
    view.addSubview(webView)
    
    activityIndicator = UIActivityIndicatorView(style: .large)
    activityIndicator.color = .lightGray
    activityIndicator.hidesWhenStopped = true
    view.addSubview(activityIndicator)
    
    view.setNeedsLayout()
    view.layoutIfNeeded()
    view.layoutSubviews()
    webView.setNeedsLayout()
    webView.layoutIfNeeded()
    
    Task {
      do {
        let screen: NoCodesScreen
        if let screenId = screenId {
          screen = try await noCodesService.loadScreen(with: screenId)
        } else if let contextKey = contextKey {
          screen = try await noCodesService.loadScreen(withContextKey: contextKey)
        } else {
          logger.error(LoggerInfoMessages.screenLoadingFailed.rawValue)
          throw NoCodesError(type: .screenLoadingFailed, message: "No screen id or context key provided")
        }

        self.screenId = screen.id
        self.contextKey = screen.contextKey
        delegate.noCodesHasShownScreen(id: screen.id)
        trackScreenShownIfNeeded()

        var htmlToLoad = htmlInjector.injectCustomLocale(into: screen.html, locale: customLocale)
        htmlToLoad = htmlInjector.injectTheme(into: htmlToLoad, theme: theme)
        webView.loadHTMLString(htmlToLoad, baseURL: nil)

        await injectUserEntitlements()
      } catch {
        delegate.noCodesFailedToLoadScreen(error: nil)
        logger.error(LoggerInfoMessages.screenLoadingFailed.rawValue)
      }
    }
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    trackScreenShownIfNeeded()
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)

    guard let screenId = screenId else { return }

    if isBeingDismissed || isMovingFromParent {
      // Permanently leaving: track screen_closed
      trackScreenClosedIfNeeded(screenId: screenId)
    } else {
      // Temporarily hidden (e.g. a new screen was pushed on top):
      // reset the flag so screen_shown fires again when this view re-appears
      didTrackScreenShown = false
    }
  }

  deinit {
    // Fallback: if the entire flow was dismissed (e.g. parent nav controller dismissed),
    // viewDidDisappear may not detect it via isBeingDismissed. Track screen_closed here
    // if it wasn't already tracked.
    if let screenId = screenId, !didTrackScreenClosed {
      let event = ScreenEvent(data: [
        "type": ScreenEventType.screenClosed.rawValue,
        "screen_uid": screenId,
        "happened_at": Int(Date().timeIntervalSince1970)
      ])
      screenEventsService?.track(event: event)
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    
    activityIndicator.center = view.center
    webView.frame = view.frame
  }
  
  func close() {
    close(action: nil)
  }
  
  func addLoadingView() {
    loadingView.frame = view.frame
    loadingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(loadingView)
    loadingView.startAnimating()
  }

  func removeLoadingView() {
    loadingView.removeFromSuperview()
    loadingView.stopAnimating()
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)

    guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }

    let newTheme = traitCollection.userInterfaceStyle == .dark ? "dark" : "light"
    let js = """
    if (window.noCodesContext && window.noCodesContext.device) {
        window.noCodesContext.device.theme = "\(newTheme)";
        window.dispatchEvent(new Event("noCodesContextUpdate"));
    }
    """
    webView?.evaluateJavaScript(js, completionHandler: nil)
  }

}

extension NoCodesViewController: WKScriptMessageHandler {
  
  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard let body = message.body as? [String: Any] else { return }
    
    let action: NoCodesAction = noCodesMapper.map(rawAction: body)
    
    if action.type == .showScreen {
      return removeLoadingView()
    }
    
    if action.type != .loadProducts && action.type != .screenAnalytics {
      delegate.noCodesStartsExecuting(action: action)
    }
    
    switch action.type {
    case .loadProducts:
      handle(loadProductsAction: action)
    case .close:
      handle(closeAction: action)
    case .closeAll:
      finishAndClose(action: action)
    case .url:
      handle(urlAction: action)
    case .deeplink:
      handle(deepLinkAction: action)
    case .navigation:
      handle(navigationAction: action)
    case .purchase:
      handle(purchaseAction: action)
    case .restore:
      handle(restoreAction: action)
    case .redeemPromoCode:
      handle(redeemPromoCodeAction: action)
    case .screenAnalytics:
      handle(screenAnalyticsAction: action)
    default: break
    }
  }
  
}

extension NoCodesViewController {

  private func trackScreenShownIfNeeded() {
    guard !didTrackScreenShown, let screenId = screenId else { return }
    didTrackScreenShown = true
    let event = ScreenEvent(data: [
      "type": ScreenEventType.screenShown.rawValue,
      "screen_uid": screenId,
      "happened_at": Int(Date().timeIntervalSince1970)
    ])
    screenEventsService.track(event: event)
  }

  private func trackScreenClosedIfNeeded(screenId: String) {
    guard !didTrackScreenClosed else { return }
    didTrackScreenClosed = true
    let event = ScreenEvent(data: [
      "type": ScreenEventType.screenClosed.rawValue,
      "screen_uid": screenId,
      "happened_at": Int(Date().timeIntervalSince1970)
    ])
    screenEventsService.track(event: event)
  }

  private func injectUserEntitlements() async {
    do {
      let entitlements = try await Qonversion.shared().checkEntitlements()
      let activeIds = entitlements.filter { $0.value.isActive }.map { $0.key }
      let hasAny = !activeIds.isEmpty
      let idsArrayJS = "[" + activeIds.map { "\"\($0)\"" }.joined(separator: ", ") + "]"
      let js = """
      if (window.noCodesContext && window.noCodesContext.user) {
          window.noCodesContext.user.entitlements = \(idsArrayJS);
          window.noCodesContext.user.hasAnyEntitlement = \(hasAny);
          window.dispatchEvent(new Event("noCodesContextUpdate"));
      }
      """
      await MainActor.run {
        webView?.evaluateJavaScript(js, completionHandler: nil)
      }
    } catch {
      logger.error("Failed to load entitlements for noCodesContext: \(error.localizedDescription)")
    }
  }

  private func injectProductsContext(products: [String: Qonversion.Product]) async {
    var productEntries: [String] = []
    var hasAnyIntro = false

    for (id, product) in products {
      let hasIntro = product.skProduct?.introductoryPrice != nil
      if hasIntro { hasAnyIntro = true }

      var introType = "null"
      if let introPrice = product.skProduct?.introductoryPrice {
        introType = "\"\(noCodesMapper.map(introPricePaymentType: introPrice.paymentMode))\""
      }

      productEntries.append("\"\(id)\": { hasIntro: \(hasIntro), introType: \(introType) }")
    }

    let productsJS = "{ " + productEntries.joined(separator: ", ") + " }"
    let js = """
    if (window.noCodesContext) {
        window.noCodesContext.products = \(productsJS);
        window.noCodesContext.products.hasAnyIntro = \(hasAnyIntro);
        window.dispatchEvent(new Event("noCodesContextUpdate"));
    }
    """
    await MainActor.run {
      webView?.evaluateJavaScript(js, completionHandler: nil)
    }
  }

  private var isModalPresentation: Bool {
    if let navigationController = navigationController, navigationController.viewControllers.count > 1 {
      return false
    }
    
    return modalPresentationStyle != .none || presentingViewController != nil
  }
  
  private func send(event: String, data: String) async {
    let _ = try? await webView.evaluateJavaScript("window.dispatchEvent(new CustomEvent(\"\(event)\",  {detail: \(data)} ))")
  }
  
  private func handle(closeAction: NoCodesAction) {
    if self.navigationController?.viewControllers.count ?? 0 > 1 {
      navigationController?.popViewController(animated: true)
      delegate.noCodesFinishedExecuting(action: closeAction)
      if let firstExternalViewController: UIViewController = firstExternalViewController(),
         let externalIndex: Int = navigationController?.viewControllers.firstIndex(of: firstExternalViewController),
         let viewControllersCount: Int = navigationController?.viewControllers.count,
         externalIndex == viewControllersCount - 1 {
        delegate.noCodesFinished()
      }
    } else {
      finishAndClose(action: closeAction)
    }
  }
  
  private func handle(loadProductsAction: NoCodesAction) {
    Task {
      guard let productIds: [String] = loadProductsAction.parameters?["productIds"] as? [String],
            let products: [String: Qonversion.Product] = try? await Qonversion.shared().products()
      else {
        logger.error(LoggerInfoMessages.productsLoadingFailed.rawValue)
        return delegate.noCodesFailedToLoadScreen(error: NoCodesError(type: .productsLoadingFailed))
      }
      
      let filteredProducts: [String: Qonversion.Product] = products.filter { productIds.contains($0.key) }
      guard !filteredProducts.isEmpty else {
        return delegate.noCodesFailedToLoadScreen(error: NoCodesError(type: .productsLoadingFailed))
      }
      
      let productsInfo: [String: Any] = noCodesMapper.map(products: filteredProducts)
      
      guard let data = try? JSONSerialization.data(withJSONObject: productsInfo, options: []),
            let jsString = String(data: data, encoding: .utf8)
      else {
        logger.error(LoggerInfoMessages.productsLoadingFailed.rawValue)
        return delegate.noCodesFailedToLoadScreen(error: NoCodesError(type: .productsLoadingFailed))
      }
      await send(event: Constants.setProducts.rawValue, data: jsString)
      await injectProductsContext(products: filteredProducts)
    }
  }

  private func handle(urlAction: NoCodesAction) {
    guard let urlString: String = urlAction.parameters?[Constants.url.rawValue] as? String,
          let url = URL(string: urlString) else {
      logger.error(LoggerInfoMessages.urlHandlingFailed.rawValue)
      return delegate.noCodesFailedToExecute(action: urlAction, error: nil)
    }
    
    let safariVC = SFSafariViewController(url: url)
    navigationController?.present(safariVC, animated: true)
    delegate.noCodesFinishedExecuting(action: urlAction)
  }
  
  private func handle(deepLinkAction: NoCodesAction) {
    guard let deepLinkString: String = deepLinkAction.parameters?[Constants.deeplink.rawValue] as? String,
          let url = URL(string: deepLinkString) else {
      logger.error(LoggerInfoMessages.deeplingHandlingFailed.rawValue)
      return delegate.noCodesFailedToExecute(action: deepLinkAction, error: nil)
    }
    
    if UIApplication.shared.canOpenURL(url) {
      UIApplication.shared.open(url)
    } else {
      delegate.noCodesFailedToExecute(action: deepLinkAction, error: nil)
      logger.error(LoggerInfoMessages.deeplingHandlingFailed.rawValue)
      close(action: deepLinkAction)
    }
  }
  
  private func handle(purchaseAction: NoCodesAction) {
    guard let productId: String = purchaseAction.parameters?[Constants.productId.rawValue] as? String else { return }

    activityIndicator.startAnimating()
    Task {
      do {
        let products = try await Qonversion.shared().products()
        guard let product = products[productId] else {
          throw NoCodesError(type: .productNotFound, message: "Product with id \(productId) not found")
        }
        
        if let purchaseDelegate {
          do {
            try await purchaseDelegate.purchase(product: product)
            activityIndicator.stopAnimating()
            await sendSuccessEvent(action: purchaseAction)
          } catch {
            activityIndicator.stopAnimating()
            let noCodesError = NoCodesError.fromClientError(error)
            logger.error(noCodesError.message)
            await sendFailureEvent(action: purchaseAction, error: noCodesError)
          }
        } else {
          let options = Qonversion.PurchaseOptions()
          options.screenUid = screenId
          
          let result = await Qonversion.shared().purchase(product, options: options)
          activityIndicator.stopAnimating()
          
          if result.isSuccessful {
            await sendSuccessEvent(action: purchaseAction)
          } else {
            let error = result.error
            logger.error(error?.localizedDescription ?? "Purchase failed")
            await sendFailureEvent(action: purchaseAction, error: error)
          }
        }
      } catch {
        activityIndicator.stopAnimating()
        logger.error(error.localizedDescription)
        await sendFailureEvent(action: purchaseAction, error: error)
      }
    }
  }
  
  private func handle(restoreAction: NoCodesAction) {
    activityIndicator.startAnimating()
    
    Task {
      do {
        if let purchaseDelegate = purchaseDelegate {
          try await purchaseDelegate.restore()
        } else {
          try await Qonversion.shared().restore()
        }
        activityIndicator.stopAnimating()
        await sendSuccessEvent(action: restoreAction)
      } catch {
        logger.error(error.localizedDescription)
        activityIndicator.stopAnimating()
        let errorToReport = purchaseDelegate == nil ? error : NoCodesError.fromClientError(error)
        await sendFailureEvent(action: restoreAction, error: errorToReport)
      }
    }
  }
  
  private func handle(redeemPromoCodeAction: NoCodesAction) {
    if #available(iOS 14.0, *) {
      Qonversion.shared().presentCodeRedemptionSheet()
      delegate.noCodesFinishedExecuting(action: redeemPromoCodeAction)
    } else {
      delegate.noCodesFailedToExecute(action: redeemPromoCodeAction, error: nil)
    }
  }

  // MARK: - Success/Failure Event Sending
  
  /// Sends successEvent to WebView. WebView will handle executing the configured success action.
  private func sendSuccessEvent(action: NoCodesAction) async {
    delegate.noCodesFinishedExecuting(action: action)
    await send(event: "successEvent", data: "{}")
  }
  
  /// Sends failureEvent to WebView. WebView will handle executing the configured failure action.
  private func sendFailureEvent(action: NoCodesAction, error: Error?) async {
    delegate.noCodesFailedToExecute(action: action, error: error)
    await send(event: "failureEvent", data: "{}")
  }
  
  private func handle(navigationAction: NoCodesAction) {
    guard let screenId: String = navigationAction.parameters?[Constants.screenId.rawValue] as? String else { return }

    let viewController = viewsAssembly.viewController(with: screenId, delegate: delegate, purchaseDelegate: purchaseDelegate, screenCustomizationDelegate: screenCustomizationDelegate, presentationConfiguration: presentationConfiguration, customLocale: customLocale, theme: theme)
    navigationController?.pushViewController(viewController, animated: true)
    delegate.noCodesFinishedExecuting(action: navigationAction)
  }

  /// Handles screen analytics events forwarded from the JS layer.
  /// Pass-through design: JS events are forwarded as-is without type validation
  /// against ScreenEventType. The SDK only injects screen_uid (which JS doesn't know)
  /// and forwards the event to the backend. Event types are defined by JS, not the SDK.
  private func handle(screenAnalyticsAction: NoCodesAction) {
    guard let params = screenAnalyticsAction.parameters,
          let screenId = screenId else { return }

    guard params["type"] != nil else {
      logger.warning("screenAnalytics action missing 'type' parameter")
      return
    }

    var eventData = params
    eventData["screen_uid"] = screenId
    let event = ScreenEvent(data: eventData)
    screenEventsService.track(event: event)
  }

  private func finishAndClose(action: NoCodesAction) {
    delegate.noCodesFinishedExecuting(action: action)
    close(action: action)
  }
  
  private func close(action: NoCodesAction?) {
    if isModalPresentation {
      dismiss(animated: true) { [weak self] in
        self?.delegate?.noCodesFinished()
      }
    } else {
      guard let externalVC = firstExternalViewController() else {
        // Fallback: dismiss anyway
        dismiss(animated: true) { [weak self] in
          self?.delegate?.noCodesFinished()
        }
        return
      }
      navigationController?.popToViewController(externalVC, animated: true)
      delegate?.noCodesFinished()
    }
  }
  
  private func firstExternalViewController() -> UIViewController? {
    let currentViewControllers: [UIViewController]? = navigationController?.viewControllers
    let firstExternalVC: UIViewController? = currentViewControllers?.last(where: { !$0.isKind(of: Self.self) })
    
    return firstExternalVC
  }
  
}

extension NoCodesViewController: UIScrollViewDelegate {
  func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
    scrollView.pinchGestureRecognizer?.isEnabled = false
  }
}

#endif
