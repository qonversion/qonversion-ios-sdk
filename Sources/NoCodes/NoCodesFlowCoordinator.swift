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

final class NoCodesFlowCoordinator {
  
  private var delegate: NoCodesDelegate?
  private var screenCustomizationDelegate: NoCodesScreenCustomizationDelegate?
  private let noCodesService: NoCodesServiceInterface
  private let viewsAssembly: ViewsAssembly
  private let servicesAssembly: ServicesAssembly
  private var currentVC: NoCodesViewController?
  private var logger: LoggerWrapper!
  
  init(delegate: NoCodesDelegate?, screenCustomizationDelegate: NoCodesScreenCustomizationDelegate?, noCodesService: NoCodesServiceInterface, viewsAssembly: ViewsAssembly, servicesAssembly: ServicesAssembly, logger: LoggerWrapper) {
    self.delegate = delegate
    self.screenCustomizationDelegate = screenCustomizationDelegate
    self.noCodesService = noCodesService
    self.viewsAssembly = viewsAssembly
    self.servicesAssembly = servicesAssembly
    self.logger = logger
  }
  
  func set(delegate: NoCodesDelegate) {
    self.delegate = delegate
  }
  
  func set(screenCustomizationDelegate: NoCodesScreenCustomizationDelegate) {
    self.screenCustomizationDelegate = screenCustomizationDelegate
  }
  
  func close() {
    currentVC?.close()
  }
  
  @MainActor
  func showScreen(with id: String) {
    let presentationConfiguration: NoCodesPresentationConfiguration = screenCustomizationDelegate?.presentationConfigurationForScreen(id: id) ?? NoCodesPresentationConfiguration.defaultConfiguration()
    
    let viewController: NoCodesViewController = viewsAssembly.viewController(with: id, delegate: self, presentationConfiguration: presentationConfiguration)
    currentVC = viewController
    
    showScreen(viewController, presentationConfiguration)
  }
  
  @MainActor
  func showScreen(withContextKey contextKey: String) {
    let presentationConfiguration: NoCodesPresentationConfiguration = screenCustomizationDelegate?.presentationConfigurationForScreen(contextKey: contextKey) ?? NoCodesPresentationConfiguration.defaultConfiguration()
    
    let viewController: NoCodesViewController = viewsAssembly.viewController(withContextKey: contextKey, delegate: self, presentationConfiguration: presentationConfiguration)
    currentVC = viewController
    
    showScreen(viewController, presentationConfiguration)
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
  
  func noCodesFinished() {
    delegate?.noCodesFinished()
  }
  
  func noCodesFailedToLoadScreen(error: Error?) {
    delegate?.noCodesFailedToLoadScreen(error: error)
  }
  
}

// MARK: - Private

extension NoCodesFlowCoordinator {
  
  private func topLevelViewController() -> UIViewController? {
      var controller = UIApplication.shared.windows.filter {$0.isKeyWindow}.first?.rootViewController
    while controller?.presentedViewController != nil {
      controller = controller?.presentedViewController
    }
    
    return controller
  }
  
}

#endif
