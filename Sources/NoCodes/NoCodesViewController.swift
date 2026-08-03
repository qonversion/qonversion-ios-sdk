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
import Qonversion

enum Constants: String {
  case url
  case deeplink
  case screenId
  case productId
  case setProducts
  case setContext
  case value
}

/// WKUserContentController retains its message handlers, and the controller is
/// reachable from the web view the screen owns. Registering the view controller
/// directly would close the cycle
/// (controller -> web view -> configuration -> user content controller -> controller)
/// and leak every presented screen together with its inlined HTML, so the
/// registered handler is this proxy, which only points back weakly.
final class NoCodesScriptMessageProxy: NSObject, WKScriptMessageHandler {

  weak var target: WKScriptMessageHandler?

  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    target?.userContentController(userContentController, didReceive: message)
  }
}

@MainActor
protocol NoCodesViewControllerDelegate {

  func noCodesHasShownScreen(id: String)

  func noCodesStartsExecuting(action: NoCodesAction)
  
  func noCodesFailedToExecute(action: NoCodesAction, error: Error?)
  
  func noCodesFinishedExecuting(action: NoCodesAction)

  func noCodesReceivedCustomAction(value: String)

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
  private weak var purchaseDelegate: NoCodesPurchaseDelegate?
  private weak var screenCustomizationDelegate: NoCodesScreenCustomizationDelegate?
  private weak var customVariablesDelegate: NoCodesCustomVariablesDelegate?
  private var customLocale: String?
  private var theme: NoCodesTheme!
  private var screenSession = NoCodesScreenSession()
  private var didReportFinished = false
  // The navigation controller this screen was presented in, captured while it
  // still has one.
  private weak var flowNavigationController: UINavigationController?
  private var hasWebPurchaseLoader = false
  private var screenProductIds: [String] = []
  private var contextBuilder: NoCodesContextBuilderInterface!
  private var htmlInjector: NoCodesHTMLInjectorInterface!
  // Held here because the user content controller is the only other owner and
  // it must not keep the screen alive through it.
  private let scriptMessageProxy = NoCodesScriptMessageProxy()
  // Kept so that leaving the screen can cancel a load still in flight.
  private var screenLoadTask: Task<Void, Never>?

  init(screenId: String?, contextKey: String?, delegate: NoCodesViewControllerDelegate, purchaseDelegate: NoCodesPurchaseDelegate?, screenCustomizationDelegate: NoCodesScreenCustomizationDelegate?, customVariablesDelegate: NoCodesCustomVariablesDelegate?, noCodesMapper: NoCodesMapperInterface, noCodesService: NoCodesServiceInterface, screenEventsService: ScreenEventsServiceInterface, viewsAssembly: ViewsAssembly, logger: LoggerWrapper, presentationConfiguration: NoCodesPresentationConfiguration, contextBuilder: NoCodesContextBuilderInterface, htmlInjector: NoCodesHTMLInjectorInterface, customLocale: String? = nil, theme: NoCodesTheme = .auto) {
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
    self.customVariablesDelegate = customVariablesDelegate
    self.customLocale = customLocale
    self.theme = theme
    self.contextBuilder = contextBuilder
    self.htmlInjector = htmlInjector

    super.init(nibName: nil, bundle: nil)

    if let customLoadingView = screenCustomizationDelegate?.noCodesCustomLoadingView() {
      loadingView = customLoadingView
    } else {
      let interfaceStyle: UIUserInterfaceStyle = theme.resolveInterfaceStyle(traitCollection: traitCollection)
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
    scriptMessageProxy.target = self
    userContentController.add(scriptMessageProxy, name: "noCodesMessageHandler")

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
    
    screenLoadTask = Task { [weak self] in
      await self?.loadAndRenderScreen()
    }
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    // Kept while the screen is on screen: once it is popped, UIKit has already
    // detached it and the stack behind it can no longer be inspected.
    flowNavigationController = navigationController
    trackScreenShownIfNeeded()
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)

    let leave: NoCodesScreenLeave = NoCodesScreenLifecycle.leave(isBeingDismissed: isBeingDismissed, isMovingFromParent: isMovingFromParent)

    switch leave {
    case .permanent:
      // Nothing that is still loading can matter now, and its side effects
      // would land on a screen the user has already left.
      cancelScreenLoad()

      trackScreenClosedIfNeeded()

      // A host-driven pop or dismiss ends the flow just like the SDK-driven
      // close; without this the coordinator keeps believing a screen is up.
      if NoCodesScreenLifecycle.reportsFinished(leave: leave, hasRemainingFlowScreen: hasRemainingFlowScreen()) {
        reportFinished()
      }
    case .temporary:
      // Covered by another screen of the flow. UIKit sends no second
      // `viewDidDisappear` once the flow is torn down, so the viewing session
      // has to be closed here; a re-appearance opens a new one.
      trackScreenClosedIfNeeded()
    }
  }

  deinit {
    // Fallback for a flow torn down without a `viewDidDisappear` — a dismissed
    // parent navigation controller, for one. Late for the flow's own flush, but
    // a later one still carries it.
    if let screenId = screenId, screenSession.trackClosed() {
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

    // Resolved through the configured theme, never straight off the trait: a
    // host that forced .light or .dark keeps it across a system change.
    let resolvedTheme: NoCodesResolvedTheme = theme.resolveTheme(traitCollection: traitCollection)
    webView?.evaluateJavaScript(NoCodesJavaScript.themeUpdateScript(resolvedTheme: resolvedTheme), completionHandler: nil)
  }

}

extension NoCodesViewController: WKScriptMessageHandler {
  
  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard let body = message.body as? [String: Any] else { return }

    let action: NoCodesAction = noCodesMapper.map(rawAction: body)
    
    if action.type == .showScreen {
      injectCustomVariables { [weak self] in
        self?.removeLoadingView()
      }
      return
    }
    
    if NoCodesScreenLifecycle.announcesExecution(actionType: action.type) {
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
    case .getContext:
      handle(getContextAction: action)
    case .purchaseLoaderPresent:
      hasWebPurchaseLoader = true
    case .custom:
      handle(customAction: action)
    default:
      // The host was told this one started, so it owes an outcome even though
      // the SDK has nothing to carry out for it.
      logger.error("Received an action the SDK cannot handle")
      report(failureOf: action, error: NoCodesError(type: .unknown))
    }
  }
  
}

extension NoCodesViewController {

  /// Loads the screen this controller was created for and renders it.
  ///
  /// Every side effect is gated on the load not having been cancelled: the user
  /// can leave while a slow screen is still loading, and announcing it then
  /// would report a screen after the flow already reported itself finished,
  /// count a `screen_shown` for a screen nobody saw and render markup into a
  /// web view that is no longer on screen.
  private func loadAndRenderScreen() async {
    do {
      let screen: NoCodesScreen = try await loadScreen()

      guard NoCodesScreenLifecycle.shouldApplyLoadedScreen(isCancelled: Task.isCancelled) else { return }

      screenId = screen.id
      contextKey = screen.contextKey
      delegate.noCodesHasShownScreen(id: screen.id)
      trackScreenShownIfNeeded()

      var htmlToLoad: String = htmlInjector.injectCustomLocale(into: screen.html, locale: customLocale)
      htmlToLoad = htmlInjector.injectTheme(into: htmlToLoad, theme: theme)

      webView.loadHTMLString(htmlToLoad, baseURL: nil)
    } catch {
      guard NoCodesScreenLifecycle.shouldApplyLoadedScreen(isCancelled: Task.isCancelled) else { return }

      delegate.noCodesFailedToLoadScreen(error: error)
      logger.error(LoggerInfoMessages.screenLoadingFailed.rawValue)
    }
  }

  private func loadScreen() async throws -> NoCodesScreen {
    if let screenId: String = screenId {
      return try await noCodesService.loadScreen(with: screenId)
    }

    if let contextKey: String = contextKey {
      return try await noCodesService.loadScreen(withContextKey: contextKey)
    }

    logger.error(LoggerInfoMessages.screenLoadingFailed.rawValue)

    throw NoCodesError(type: .screenLoadingFailed, message: "No screen id or context key provided")
  }

  private func cancelScreenLoad() {
    screenLoadTask?.cancel()
    screenLoadTask = nil
  }

  private func trackScreenShownIfNeeded() {
    guard let screenId: String = screenId, screenSession.trackShown() else { return }

    let event = ScreenEvent(data: [
      "type": ScreenEventType.screenShown.rawValue,
      "screen_uid": screenId,
      "happened_at": Int(Date().timeIntervalSince1970)
    ])
    screenEventsService.track(event: event)
  }

  private func trackScreenClosedIfNeeded() {
    guard let screenId: String = screenId, screenSession.trackClosed() else { return }

    let event = ScreenEvent(data: [
      "type": ScreenEventType.screenClosed.rawValue,
      "screen_uid": screenId,
      "happened_at": Int(Date().timeIntervalSince1970)
    ])
    screenEventsService.track(event: event)
  }

  /// Closes the viewing session of every flow screen this close takes off
  /// screen, this one included.
  ///
  /// The flow flushes its events as soon as the close reports finished, which
  /// on the pop route happens before the animation ends — long before UIKit
  /// sends `viewDidDisappear` to the screens the pop removed.
  private func trackClosedForRemovedScreens() {
    trackScreenClosedIfNeeded()

    guard let viewControllers: [UIViewController] = navigationController?.viewControllers else { return }

    for viewController: UIViewController in viewControllers {
      guard let screen = viewController as? NoCodesViewController, screen !== self else { continue }

      screen.trackScreenClosedIfNeeded()
    }
  }

  private func injectCustomVariables(completion: @escaping () -> Void) {
    let key: String = contextKey ?? ""
    guard let variables: [String: String] = customVariablesDelegate?.customVariables(for: key),
          !variables.isEmpty else {
      completion()
      return
    }

    let setVariableCalls: String = NoCodesJavaScript.setCustomVariablesScript(for: variables)

    webView?.evaluateJavaScript(setVariableCalls) { _, _ in
      completion()
    }
  }

  private func loadUserProperties() async -> [String: String] {
    do {
      let properties: Qonversion.UserProperties = try await Qonversion.shared.userProperties()

      return properties.flatPropertiesMap
    } catch {
      logger.error("Failed to load user properties: \(error.localizedDescription)")
      return [:]
    }
  }

  private func handle(getContextAction: NoCodesAction) {
    Task {
      let variables = getContextAction.parameters?["variables"] as? [String] ?? []
      let requestedProductIds = extractProductIds(from: variables)
      let checkEligibility = requiresIntroEligibility(variables: variables)
      // Intro conditions need entries for every screen product, not only the ones
      // referenced by three-part variables: hasAnyIntro aggregates over all of
      // them, and slot variables (vars.products.{slot}) are resolved by the
      // runtime against ctx.products by the bound product id.
      let contextProductIds = checkEligibility
        ? Array(Set(requestedProductIds).union(screenProductIds))
        : requestedProductIds
      if variables.contains(IntroConditionVariable.hasAnyIntro) && contextProductIds.isEmpty {
        logger.warning("products.hasAnyIntro is used in conditions, but the screen has no known products — the condition will evaluate to false")
      }

      async let entitlementsResult = loadActiveEntitlementIds()
      async let productsResult = loadProductsContext(productIds: contextProductIds, checkEligibility: checkEligibility)
      async let userPropsResult = loadUserProperties()

      let activeEntitlementIds = await entitlementsResult
      let productsContext = await productsResult
      let userProperties = await userPropsResult

      let resolvedTheme: NoCodesResolvedTheme = theme.resolveTheme(traitCollection: traitCollection)
      guard let jsString = contextBuilder.buildContextJSON(resolvedTheme: resolvedTheme, activeEntitlementIds: activeEntitlementIds, productsContext: productsContext, userProperties: userProperties) else { return }

      await send(event: Constants.setContext.rawValue, data: jsString)
    }
  }

  private func extractProductIds(from variables: [String]) -> [String] {
    var ids: Set<String> = []
    for variable in variables {
      let parts = variable.split(separator: ".")
      guard parts.count == 3, parts[0] == "products" else { continue }
      let id = String(parts[1])
      if id != "hasAnyIntro" && id != "selected" {
        ids.insert(id)
      }
    }
    return Array(ids)
  }

  // Names of the builder's intro condition variables (conditionalLogicVariables.ts
  // in dash-mono). Must stay in sync with the builder: a variable missing here
  // silently skips the eligibility request for screens that use it.
  private enum IntroConditionVariable {
    static let productsPrefix = "products."
    static let slotProductsPrefix = "vars.products."
    static let hasAnyIntro = "products.hasAnyIntro"
    static let hasIntroSuffix = ".hasIntro"
    static let introTypeSuffix = ".introType"
  }

  private func requiresIntroEligibility(variables: [String]) -> Bool {
    return variables.contains { variable in
      guard variable.hasPrefix(IntroConditionVariable.productsPrefix)
              || variable.hasPrefix(IntroConditionVariable.slotProductsPrefix) else { return false }
      return variable == IntroConditionVariable.hasAnyIntro
        || variable.hasSuffix(IntroConditionVariable.hasIntroSuffix)
        || variable.hasSuffix(IntroConditionVariable.introTypeSuffix)
    }
  }

  private func loadActiveEntitlementIds() async -> [String] {
    do {
      let entitlements: [String: Qonversion.Entitlement] = try await Qonversion.shared.checkEntitlements()

      return entitlements.filter { $0.value.active }.map { $0.key }
    } catch {
      logger.error("Failed to load entitlements for context: \(error.localizedDescription)")
      return []
    }
  }

  private func loadProductsContext(productIds: [String], checkEligibility: Bool) async -> [String: any Sendable] {
    // An explicit false keeps products.hasAnyIntro defined even when the screen
    // has no known products, matching the evaluator's missing-variable → false.
    guard !productIds.isEmpty else { return ["hasAnyIntro": "false"] }

    do {
      let products: [String: Qonversion.Product] = try await loadProductsByQonversionId()
      let eligibilities: [String: Qonversion.IntroEligibilityStatus] = checkEligibility ? await loadIntroEligibility(productIds: productIds.filter { products[$0] != nil }) : [:]
      var context: [String: any Sendable] = [:]
      var hasAnyIntro = false

      for id in productIds {
        guard let product = products[id] else { continue }
        let introOffer: Qonversion.Product.SubscriptionOffer? = product.subscription?.introductoryOffer
        let hasIntro: Bool = introOffer != nil && isIntroEligible(eligibilities[id])
        if hasIntro { hasAnyIntro = true }

        var introType = ""
        if hasIntro, let introOffer {
          switch introOffer.paymentMode {
          case .freeTrial: introType = "free_trial"
          case .payUpFront: introType = "pay_up_front"
          case .payAsYouGo: introType = "pay_as_you_go"
          case .unknown: break
          }
        }

        context[id] = [
          "hasIntro": hasIntro ? "true" : "false",
          "introType": introType
        ]
      }

      context["hasAnyIntro"] = hasAnyIntro ? "true" : "false"
      return context
    } catch {
      logger.error("Failed to load products for context: \(error.localizedDescription)")
      return [:]
    }
  }

  private func loadIntroEligibility(productIds: [String]) async -> [String: Qonversion.IntroEligibilityStatus] {
    guard !productIds.isEmpty else { return [:] }

    do {
      return try await Qonversion.shared.checkTrialIntroEligibility(productIds)
    } catch {
      logger.error("Failed to load intro eligibility: \(error.localizedDescription)")
      return [:]
    }
  }

  /// The SDK returns a flat product list; the screen logic addresses products
  /// by their Qonversion id.
  private func loadProductsByQonversionId() async throws -> [String: Qonversion.Product] {
    let products: [Qonversion.Product] = try await Qonversion.shared.products()

    return products.reduce(into: [String: Qonversion.Product]()) { result, product in
      result[product.qonversionId] = product
    }
  }

  // Only an explicit ineligible status hides the intro: unknown and
  // nonIntroOrTrialProduct statuses, missing entries, and eligibility loading
  // failures all fall back to eligible to keep the pre-eligibility behavior
  // of the intro conditions. Store presence still gates hasIntro.
  private func isIntroEligible(_ eligibility: Qonversion.IntroEligibilityStatus?) -> Bool {
    guard let eligibility else { return true }
    return eligibility != .ineligible
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
      // Only this screen leaves, and the flush that may follow runs before the
      // pop animation ends.
      trackScreenClosedIfNeeded()
      navigationController?.popViewController(animated: true)
      delegate.noCodesFinishedExecuting(action: closeAction)
      if let firstExternalViewController: UIViewController = firstExternalViewController(),
         let externalIndex: Int = navigationController?.viewControllers.firstIndex(of: firstExternalViewController),
         let viewControllersCount: Int = navigationController?.viewControllers.count,
         externalIndex == viewControllersCount - 1 {
        reportFinished()
      }
    } else {
      finishAndClose(action: closeAction)
    }
  }
  
  private func handle(loadProductsAction: NoCodesAction) {
    // Captured synchronously: when the screen has products, the runtime sends
    // getProducts before getContext in the same tick, and hasAnyIntro must
    // cover all screen products, not only the ones referenced by three-part
    // condition variables. Screens without product bindings never send
    // getProducts, leaving this empty.
    if let productIds = loadProductsAction.parameters?["productIds"] as? [String] {
      screenProductIds = productIds
    }
    Task {
      guard let productIds: [String] = loadProductsAction.parameters?["productIds"] as? [String],
            let products: [String: Qonversion.Product] = try? await loadProductsByQonversionId()
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
    }
  }

  private func handle(urlAction: NoCodesAction) {
    let urlString: String? = urlAction.parameters?[Constants.url.rawValue] as? String

    switch NoCodesURLRouter.route(urlString: urlString) {
    case let .inAppBrowser(url):
      let safariViewController = SFSafariViewController(url: url)
      // A screen presented as a popover has no navigation controller, and
      // presenting on `nil` used to drop the browser while reporting a success.
      let presenter: UIViewController = navigationController ?? self
      presenter.present(safariViewController, animated: true)
      delegate.noCodesFinishedExecuting(action: urlAction)
    case let .system(url):
      open(url, reporting: urlAction)
    case .unopenable:
      logger.error(LoggerInfoMessages.urlHandlingFailed.rawValue)
      report(failureOf: urlAction, error: nil)
    }
  }

  /// Hands a URL the in-app browser cannot show to the system and reports what
  /// came of it.
  private func open(_ url: URL, reporting action: NoCodesAction) {
    UIApplication.shared.open(url, options: [:]) { [weak self] opened in
      guard let self else { return }

      guard opened else {
        logger.error(LoggerInfoMessages.urlHandlingFailed.rawValue)
        report(failureOf: action, error: nil)

        return
      }

      delegate.noCodesFinishedExecuting(action: action)
    }
  }

  private func handle(deepLinkAction: NoCodesAction) {
    guard let deepLinkString: String = deepLinkAction.parameters?[Constants.deeplink.rawValue] as? String,
          let url = URL(string: deepLinkString) else {
      logger.error(LoggerInfoMessages.deeplingHandlingFailed.rawValue)
      return report(failureOf: deepLinkAction, error: nil)
    }

    if UIApplication.shared.canOpenURL(url) {
      open(url, reporting: deepLinkAction)
    } else {
      report(failureOf: deepLinkAction, error: nil)
      logger.error(LoggerInfoMessages.deeplingHandlingFailed.rawValue)
      close(action: deepLinkAction)
    }
  }

  private func handle(customAction: NoCodesAction) {
    let value: String = customAction.parameters?[Constants.value.rawValue] as? String ?? ""

    delegate.noCodesReceivedCustomAction(value: value)
    delegate.noCodesFinishedExecuting(action: customAction)
  }

  private func handle(purchaseAction: NoCodesAction) {
    guard let productId: String = purchaseAction.parameters?[Constants.productId.rawValue] as? String else {
      logger.error(NoCodesErrorType.productNotFound.message())
      report(failureOf: purchaseAction, error: NoCodesError(type: .productNotFound, message: "The purchase action carries no product id"))

      return
    }

    if !hasWebPurchaseLoader { activityIndicator.startAnimating() }
    Task {
      do {
        let products: [String: Qonversion.Product] = try await loadProductsByQonversionId()
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
          // The screen uid rides along with the purchase report so the backend
          // can attribute the revenue to the No-Codes screen.
          let options = Qonversion.PurchaseOptions(screenUid: screenId)

          do {
            try await Qonversion.shared.purchase(product, options: options)
            activityIndicator.stopAnimating()
            await sendSuccessEvent(action: purchaseAction)
          } catch {
            activityIndicator.stopAnimating()
            logger.error(error.localizedDescription)
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
    if !hasWebPurchaseLoader { activityIndicator.startAnimating() }
    
    Task {
      do {
        if let purchaseDelegate = purchaseDelegate {
          try await purchaseDelegate.restore()
        } else {
          try await Qonversion.shared.restore()
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
    Qonversion.shared.presentCodeRedemptionSheet()
    delegate.noCodesFinishedExecuting(action: redeemPromoCodeAction)
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

  /// Pairs a start the host already heard with the outcome of an action the SDK
  /// could not carry out. Every announced action owes the host one of these.
  private func report(failureOf action: NoCodesAction, error: Error?) {
    switch NoCodesScreenLifecycle.failureReport(actionType: action.type) {
    case .host:
      delegate.noCodesFailedToExecute(action: action, error: error)
    case .hostAndScreen:
      Task { await sendFailureEvent(action: action, error: error) }
    }
  }

  private func handle(navigationAction: NoCodesAction) {
    guard let screenId: String = navigationAction.parameters?[Constants.screenId.rawValue] as? String else {
      logger.error(NoCodesErrorType.screenNotFound.message())
      report(failureOf: navigationAction, error: NoCodesError(type: .screenNotFound, message: "The navigation action carries no screen id"))

      return
    }

    guard NoCodesScreenLifecycle.canPushFollowUpScreen(hasNavigationController: navigationController != nil) else {
      logger.error(NoCodesErrorType.screenPresentationFailed.message())
      report(failureOf: navigationAction, error: NoCodesError(type: .screenPresentationFailed))

      return
    }

    let viewController = viewsAssembly.viewController(with: screenId, delegate: delegate, purchaseDelegate: purchaseDelegate, screenCustomizationDelegate: screenCustomizationDelegate, customVariablesDelegate: customVariablesDelegate, presentationConfiguration: presentationConfiguration, customLocale: customLocale, theme: theme)
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

    // A non-string type fails the backend's typed decoder and takes the whole
    // batch with it, valid events included.
    guard params["type"] is String else {
      logger.warning("screenAnalytics action missing a string 'type' parameter")
      return
    }

    var eventData: [String: Any] = params
    eventData["screen_uid"] = screenId
    let event = ScreenEvent(rawData: eventData)
    screenEventsService.track(event: event)
  }

  private func finishAndClose(action: NoCodesAction) {
    delegate.noCodesFinishedExecuting(action: action)
    close(action: action)
  }
  
  private func close(action: NoCodesAction?) {
    // The screen is going away, so a load still in flight has nothing left to
    // render and no one left to report to.
    cancelScreenLoad()
    trackClosedForRemovedScreens()

    if isModalPresentation {
      dismiss(animated: true) { [weak self] in
        self?.reportFinished()
      }
    } else {
      guard let externalVC = firstExternalViewController() else {
        // Fallback: dismiss anyway
        dismiss(animated: true) { [weak self] in
          self?.reportFinished()
        }
        return
      }
      navigationController?.popToViewController(externalVC, animated: true)
      reportFinished()
    }
  }

  /// The single funnel for the flow-finished callback: every route out of the
  /// screen goes through it, and the host hears it exactly once.
  private func reportFinished() {
    guard !didReportFinished else { return }

    didReportFinished = true
    delegate?.noCodesFinished()
  }

  private func hasRemainingFlowScreen() -> Bool {
    // A dismissal takes the whole navigation stack with it; only a pop leaves
    // the screens below this one on screen.
    guard !isBeingDismissed else { return false }

    guard let viewControllers: [UIViewController] = flowNavigationController?.viewControllers else { return false }

    return viewControllers.contains { $0 !== self && $0 is NoCodesViewController }
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
