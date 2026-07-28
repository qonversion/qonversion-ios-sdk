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
    let outcome: NoCodesCloseOutcome = presentationGate.closeRequested()

    guard outcome.closesVisibleScreen else { return }

    currentVC?.close()
  }

  @MainActor
  func showScreen(withContextKey contextKey: String) {
    presentationGate.presentationStarted()
    Task { @MainActor in
      // The screen conditions are evaluated against the server-side user, so
      // any property set just before the call has to reach the backend first.
      await Qonversion.shared.forceSendProperties()

      let outcome: NoCodesPresentationOutcome = presentationGate.presentationReady()
      if case let .cancelled(reportsFinished) = outcome {
        logger.info("The screen was closed before it could be presented")
        // A host that gates its UI on the finish callback waits forever
        // otherwise. When the same close also dismissed a visible screen, that
        // dismissal reports the flow finished and this one must stay quiet.
        if reportsFinished {
          noCodesFinished()
        }

        return
      }

      let presentationConfiguration: NoCodesPresentationConfiguration = screenCustomizationDelegate?.presentationConfigurationForScreen(contextKey: contextKey) ?? NoCodesPresentationConfiguration.defaultConfiguration()

      let viewController: NoCodesViewController = viewsAssembly.viewController(withContextKey: contextKey, delegate: self, purchaseDelegate: purchaseDelegate, screenCustomizationDelegate: screenCustomizationDelegate, customVariablesDelegate: customVariablesDelegate, presentationConfiguration: presentationConfiguration, customLocale: customLocale, theme: theme)
      currentVC = viewController

      showScreen(viewController, presentationConfiguration)
    }
  }

  // Pure data load, no presentation. Deliberately skips forceSendProperties (unlike showScreen)
  // since nothing is displayed yet.
  func loadScreen(withContextKey contextKey: String) async throws -> NoCodesScreen {
    return try await noCodesService.loadScreen(withContextKey: contextKey)
  }

  private func showScreen(_ viewController: NoCodesViewController, _ presentationConfiguration: NoCodesPresentationConfiguration) {
    guard let presentationViewController: UIViewController = delegate?.controllerForNavigation() ?? topLevelViewController() else { return }
    
    if presentationConfiguration.presentationStyle == .push {
      var navigationController: UINavigationController? = presentationViewController.navigationController
      if presentationViewController.isKind(of: UINavigationController.self) {
        navigationController = presentationViewController as? UINavigationController
      }
      navigationController?.pushViewController(viewController, animated: presentationConfiguration.animated)
    } else {
      let presentationStyle: UIModalPresentationStyle = presentationConfiguration.presentationStyle == .popover ? .popover : .fullScreen
      if presentationStyle == .popover {
        viewController.modalPresentationStyle = presentationStyle
        let sourceView: UIView? = screenCustomizationDelegate?.viewForPopoverPresentation()
        
        if let sourceView {
          viewController.popoverPresentationController?.sourceView = sourceView
          viewController.popoverPresentationController?.sourceRect = sourceView.bounds
        } else {
          viewController.popoverPresentationController?.permittedArrowDirections = .up
          viewController.popoverPresentationController?.sourceRect = CGRect(x: CGRectGetMidX(presentationViewController.view.bounds), y: CGRectGetMidY(presentationViewController.view.bounds), width: 0, height: 0)
          viewController.popoverPresentationController?.sourceView = presentationViewController.view
        }
        
        presentationViewController.present(viewController, animated: presentationConfiguration.animated)
      } else {
        let navigationController = NoCodesNavigationController(rootViewController: viewController)
        navigationController.isNavigationBarHidden = true
        navigationController.modalPresentationStyle = presentationStyle
        presentationViewController.present(navigationController, animated: presentationConfiguration.animated)
      }
    }
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
    // The flow is over and the coordinator lives for the whole process, so
    // holding on to the screen would keep its web view, and the screen markup
    // inlined into it, alive for just as long.
    currentVC = nil
    presentationGate.screenFinished()
    screenEventsService.flush()
    delegate?.noCodesFinished()
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
