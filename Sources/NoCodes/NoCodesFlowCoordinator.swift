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
  
  // Weak: host objects, and the coordinator lives for the whole process.
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
    // Detached so preloading never blocks the main thread, even when called from it.
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
    apply(presentationGate.closeRequested())
  }

  @MainActor
  func showScreen(withContextKey contextKey: String) {
    presentationGate.presentationStarted()
    Task { @MainActor in
      // Screen conditions are evaluated server-side, so pending properties must
      // land first. Bounded only by the request itself — worst case roughly two
      // minutes (60s property send plus the user-creation round trip).
      await Qonversion.shared.forceSendProperties()

      let outcome: NoCodesPresentationOutcome = presentationGate.presentationReady()
      if case let .cancelled(effects) = outcome {
        logger.info("The screen was closed before it could be presented")
        apply(effects)

        return
      }

      let presentationConfiguration: NoCodesPresentationConfiguration = screenCustomizationDelegate?.presentationConfigurationForScreen(contextKey: contextKey) ?? NoCodesPresentationConfiguration.defaultConfiguration()

      let viewController: NoCodesViewController = viewsAssembly.viewController(withContextKey: contextKey, delegate: self, purchaseDelegate: purchaseDelegate, screenCustomizationDelegate: screenCustomizationDelegate, customVariablesDelegate: customVariablesDelegate, presentationConfiguration: presentationConfiguration, customLocale: customLocale, theme: theme)

      showScreen(viewController, presentationConfiguration)
    }
  }

  // Pure data load: deliberately skips forceSendProperties, nothing is displayed yet.
  func loadScreen(withContextKey contextKey: String) async throws -> NoCodesScreen {
    return try await noCodesService.loadScreen(withContextKey: contextKey)
  }

  private func showScreen(_ viewController: NoCodesViewController, _ presentationConfiguration: NoCodesPresentationConfiguration) {
    let host: UIViewController? = delegate?.controllerForNavigation() ?? topLevelViewController()
    let hostNavigationController: UINavigationController? = host.flatMap { navigationController(of: $0) }
    let target: NoCodesPresentationTarget? = NoCodesScreenLifecycle.presentationTarget(style: presentationConfiguration.presentationStyle, hasHost: host != nil, hostHasNavigationController: hostNavigationController != nil, hostIsAlreadyPresenting: host?.presentedViewController != nil)

    guard let target, let host else {
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

    // Arm only after the push or present ran: earlier leaves a close acting on
    // a screen that was never presented.
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
      // No dismissal will come back, so report the flow over here instead.
      logger.error("Closing the No-Codes flow without a screen to dismiss")
      finishFlow()

      return
    }

    // Both routes come back through `noCodesFinished()`.
    currentVC.close()
  }

  private func finishFlow() {
    // The coordinator outlives the flow; holding the screen would keep its web
    // view and inlined markup alive with it.
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
    // UIApplication.windows is undefined for multi-scene apps.
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
