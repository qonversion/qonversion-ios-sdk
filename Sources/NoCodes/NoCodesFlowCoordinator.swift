//
//  NoCodesFlowCoordinator.swift
//  NoCodes
//
//  Created by Suren Sarkisyan on 17.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation

#if os(iOS)
import UIKit
import Qonversion

@MainActor
final class NoCodesFlowCoordinator {
  
  // All four are weak: they are host objects (usually view controllers) and
  // the coordinator lives for the whole process.
  private weak var delegate: NoCodesDelegate?
  private weak var screenCustomizationDelegate: NoCodesScreenCustomizationDelegate?
  private weak var purchaseDelegate: NoCodesPurchaseDelegate?
  private weak var customVariablesDelegate: NoCodesCustomVariablesDelegate?
  private let noCodesService: NoCodesServiceInterface
  private let screenEventsService: ScreenEventsServiceInterface
  private let viewsAssembly: ViewsAssembly
  private var currentVC: NoCodesViewController?
  private var presentationGate = NoCodesPresentationGate()
  private var logger: LoggerWrapper!
  private var customLocale: String?
  private var theme: NoCodesTheme

  init(delegate: NoCodesDelegate?, screenCustomizationDelegate: NoCodesScreenCustomizationDelegate?, purchaseDelegate: NoCodesPurchaseDelegate?, customVariablesDelegate: NoCodesCustomVariablesDelegate?, noCodesService: NoCodesServiceInterface, screenEventsService: ScreenEventsServiceInterface, viewsAssembly: ViewsAssembly, logger: LoggerWrapper, customLocale: String? = nil, theme: NoCodesTheme = .auto) {
    self.delegate = delegate
    self.screenCustomizationDelegate = screenCustomizationDelegate
    self.purchaseDelegate = purchaseDelegate
    self.customVariablesDelegate = customVariablesDelegate
    self.noCodesService = noCodesService
    self.screenEventsService = screenEventsService
    self.viewsAssembly = viewsAssembly
    self.logger = logger
    self.customLocale = customLocale
    self.theme = theme
  }
  
  func set(delegate: NoCodesDelegate) {
    self.delegate = delegate
  }
  
  func set(screenCustomizationDelegate: NoCodesScreenCustomizationDelegate) {
    self.screenCustomizationDelegate = screenCustomizationDelegate
  }
  
  func set(purchaseDelegate: NoCodesPurchaseDelegate) {
    self.purchaseDelegate = purchaseDelegate
  }

  func set(customVariablesDelegate: NoCodesCustomVariablesDelegate) {
    self.customVariablesDelegate = customVariablesDelegate
  }
  
  func setLocale(_ locale: String?) {
    self.customLocale = locale
  }
  
  func setTheme(_ theme: NoCodesTheme) {
    self.theme = theme
  }
  
  func preloadScreens() {
    // Use Task.detached to ensure preloading runs on a background thread
    // and doesn't block the main thread even if called from main
    let noCodesService = self.noCodesService
    let logger = self.logger!
    Task.detached(priority: .utility) {
      do {
        let _ = try await noCodesService.preloadScreens()
        logger.info("Successfully preloaded screens")
      } catch {
        logger.error("Failed to preload screens: \(error.localizedDescription)")
      }
    }
  }
  
  func close() {
    // There is no view controller to close until the presentation is well under
    // way, so a close arriving before that is remembered by the gate and takes
    // the presentation down instead of being dropped. A presentation started on
    // top of a screen the user is still looking at raises the same in-flight
    // state, and that screen has to be dismissed all the same.
    apply(presentationGate.closeRequested())
  }

  @MainActor
  func showScreen(withContextKey contextKey: String) {
    presentationGate.presentationStarted()
    Task { @MainActor in
      // The screen conditions are evaluated against the server-side user, so
      // any property set just before the call has to reach the backend first.
      //
      // Nothing bounds this wait but the request itself: properties go out over
      // `URLSession.shared`, whose default request timeout is 60 seconds, and a
      // stalled send can take the user-creation round trip with it — worst case
      // roughly two minutes before the screen is either presented or reported
      // cancelled. A close arriving inside that window is remembered by the
      // gate and reported the moment the await returns, never dropped, but the
      // host does wait that long for the answer.
      await Qonversion.shared.forceSendProperties()

      let outcome: NoCodesPresentationOutcome = presentationGate.presentationReady()
      if case let .cancelled(effects) = outcome {
        logger.info("The screen was closed before it could be presented")
        // A host that gates its UI on the finish callback waits forever
        // otherwise. When the same close also dismissed a visible screen, that
        // dismissal reports the flow finished and this one stays quiet — the
        // gate decides which of the two it is.
        apply(effects)

        return
      }

      let presentationConfiguration: NoCodesPresentationConfiguration = screenCustomizationDelegate?.presentationConfigurationForScreen(contextKey: contextKey) ?? NoCodesPresentationConfiguration.defaultConfiguration()

      let viewController: NoCodesViewController = viewsAssembly.viewController(withContextKey: contextKey, delegate: self, purchaseDelegate: purchaseDelegate, screenCustomizationDelegate: screenCustomizationDelegate, customVariablesDelegate: customVariablesDelegate, presentationConfiguration: presentationConfiguration, customLocale: customLocale, theme: theme)

      showScreen(viewController, presentationConfiguration)
    }
  }

  // Pure data load, no presentation. Deliberately skips forceSendProperties (unlike showScreen)
  // since nothing is displayed yet.
  func loadScreen(withContextKey contextKey: String) async throws -> NoCodesScreen {
    return try await noCodesService.loadScreen(withContextKey: contextKey)
  }

  private func showScreen(_ viewController: NoCodesViewController, _ presentationConfiguration: NoCodesPresentationConfiguration) {
    let host: UIViewController? = delegate?.controllerForNavigation() ?? topLevelViewController()
    let hostNavigationController: UINavigationController? = host.flatMap { navigationController(of: $0) }
    let target: NoCodesPresentationTarget? = NoCodesScreenLifecycle.presentationTarget(style: presentationConfiguration.presentationStyle, hasHost: host != nil, hostHasNavigationController: hostNavigationController != nil, hostIsAlreadyPresenting: host?.presentedViewController != nil)

    guard let target, let host else {
      // The screen is ready and there is nowhere to put it. The gate was never
      // armed, so nothing believes a screen is up, but the host asked for one
      // and would otherwise wait for a flow that never starts and never ends.
      logger.error("Failed to present the No-Codes screen: no view controller available to present it on")
      apply(presentationGate.presentationUnavailable())

      return
    }

    switch target {
    case .push:
      hostNavigationController?.pushViewController(viewController, animated: presentationConfiguration.animated)
    case .popover:
      present(popover: viewController, on: host, animated: presentationConfiguration.animated)
    case .modal:
      let navigationController = NoCodesNavigationController(rootViewController: viewController)
      navigationController.isNavigationBarHidden = true
      navigationController.modalPresentationStyle = .fullScreen
      host.present(navigationController, animated: presentationConfiguration.animated)
    }

    // Only now is there a screen to dismiss and a view controller worth holding
    // on to. Arming either one earlier leaves a close acting on a screen that
    // was never presented, whose dismissal — the only thing that reports the
    // flow finished on that route — never happens.
    presentationGate.screenPresented()
    currentVC = viewController
  }

  private func present(popover viewController: NoCodesViewController, on host: UIViewController, animated: Bool) {
    viewController.modalPresentationStyle = .popover
    let sourceView: UIView? = screenCustomizationDelegate?.viewForPopoverPresentation()

    if let sourceView {
      viewController.popoverPresentationController?.sourceView = sourceView
      viewController.popoverPresentationController?.sourceRect = sourceView.bounds
    } else {
      viewController.popoverPresentationController?.permittedArrowDirections = .up
      viewController.popoverPresentationController?.sourceRect = CGRect(x: CGRectGetMidX(host.view.bounds), y: CGRectGetMidY(host.view.bounds), width: 0, height: 0)
      viewController.popoverPresentationController?.sourceView = host.view
    }

    host.present(viewController, animated: animated)
  }

  private func navigationController(of viewController: UIViewController) -> UINavigationController? {
    return viewController as? UINavigationController ?? viewController.navigationController
  }

  /// Carries out what the gate decided. Every host callback the flow sends goes
  /// through here, so the accounting the gate does is the accounting the host
  /// sees.
  private func apply(_ effects: [NoCodesFlowEffect]) {
    for effect: NoCodesFlowEffect in effects {
      switch effect {
      case .dismissVisibleScreen:
        dismissVisibleScreen()
      case .reportFinished:
        finishFlow()
      case .reportFailedToPresent:
        delegate?.noCodesFailedToLoadScreen(error: NoCodesError(type: .screenPresentationFailed))
      }
    }
  }

  private func dismissVisibleScreen() {
    guard let currentVC else {
      // The gate has a screen up and the coordinator has none to dismiss, so
      // nothing would ever come back to report the flow over. The finish
      // callback is the one thing a host may be blocking its own UI on, so it
      // is reported here rather than left to a dismissal that cannot happen.
      logger.error("Closing the No-Codes flow without a screen to dismiss")
      finishFlow()

      return
    }

    // Both of its routes come back through `noCodesFinished()`: a dismissal
    // completion for a presented screen, a synchronous call for a pushed one.
    currentVC.close()
  }

  /// The single place the flow reports itself over.
  private func finishFlow() {
    // The flow is over and the coordinator lives for the whole process, so
    // holding on to the screen would keep its web view, and the screen markup
    // inlined into it, alive for just as long.
    currentVC = nil
    screenEventsService.flush()
    delegate?.noCodesFinished()
  }
}

// MARK: - NoCodesViewControllerDelegate

extension NoCodesFlowCoordinator: NoCodesViewControllerDelegate {
  
  func noCodesHasShownScreen(id: String) {
    delegate?.noCodesHasShownScreen(id: id)
  }
  
  func noCodesStartsExecuting(action: NoCodesAction) {
    delegate?.noCodesStartsExecuting(action: action)
  }
  
  func noCodesFailedToExecute(action: NoCodesAction, error: Error?) {
    delegate?.noCodesFailedToExecute(action: action, error: error)
  }
  
  func noCodesFinishedExecuting(action: NoCodesAction) {
    delegate?.noCodesFinishedExecuting(action: action)
  }

  func noCodesReceivedCustomAction(value: String) {
    delegate?.noCodesReceivedCustomAction(value: value)
  }

  func noCodesFinished() {
    apply(presentationGate.screenFinished())
  }
  
  func noCodesFailedToLoadScreen(error: Error?) {
    delegate?.noCodesFailedToLoadScreen(error: error)
  }
  
}

// MARK: - Private

extension NoCodesFlowCoordinator {
  
  private func topLevelViewController() -> UIViewController? {
    // UIApplication.windows is deprecated and undefined for multi-scene apps —
    // walk the connected foreground scenes instead.
    let scenes: [UIWindowScene] = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let activeScene: UIWindowScene? = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    let keyWindow: UIWindow? = activeScene?.windows.first { $0.isKeyWindow } ?? activeScene?.windows.first

    var controller: UIViewController? = keyWindow?.rootViewController
    while controller?.presentedViewController != nil {
      controller = controller?.presentedViewController
    }

    return controller
  }
  
}

#endif
