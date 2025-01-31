//
//  NoCodesFlowCoordinator.swift
//  NoCodes
//
//  Created by Suren Sarkisyan on 17.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation
import UIKit

final class NoCodesFlowCoordinator {
  
  var delegate: NoCodes.Delegate?
  var screenCustomizationDelegate: NoCodes.ScreenCustomizationDelegate?
  let noCodesService: NoCodesServiceInterface
  let viewsAssembly: NoCodesViewsAssembly
  var currentVC: NoCodesViewController?
  
  init(delegate: NoCodes.Delegate?, screenCustomizationDelegate: NoCodes.ScreenCustomizationDelegate?, noCodesService: NoCodesServiceInterface, viewsAssembly: NoCodesViewsAssembly) {
    self.delegate = delegate
    self.screenCustomizationDelegate = screenCustomizationDelegate
    self.noCodesService = noCodesService
    self.viewsAssembly = viewsAssembly
  }
  
  func set(delegate: NoCodes.Delegate) {
    self.delegate = delegate
  }
  
  func set(screenCustomizationDelegate: NoCodes.ScreenCustomizationDelegate) {
    self.screenCustomizationDelegate = screenCustomizationDelegate
  }
  
  func close() {
    currentVC?.close()
  }
  
  @MainActor
  func showNoCode(with id: String) async throws {
    let screen: NoCodes.Screen = try await noCodesService.loadScreen(with: id)
    
    let viewController: NoCodesViewController = viewsAssembly.viewController(with: screen, delegate: self)
    currentVC = viewController
    
    guard let presentationViewController: UIViewController = delegate?.controllerForNavigation() ?? topLevelViewController() else { return }
    
    let presentationConfiguration: NoCodes.PresentationConfiguration = screenCustomizationDelegate?.presentationConfigurationForScreen(id: id) ?? NoCodes.PresentationConfiguration.defaultConfiguration()
    
    if presentationConfiguration.presentationStyle == .push {
      presentationViewController.navigationController?.pushViewController(viewController, animated: presentationConfiguration.animated)
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
  
  func noCodesShownScreen(id: String) {
    delegate?.noCodesShownScreen(id: id)
  }
  
  func noCodesStartsExecuting(action: NoCodes.Action) {
    delegate?.noCodesStartsExecuting(action: action)
  }
  
  func noCodesFailedExecuting(action: NoCodes.Action, error: Error?) {
    delegate?.noCodesFailedExecuting(action: action, error: error)
  }
  
  func noCodesFinishedExecuting(action: NoCodes.Action) {
    delegate?.noCodesFinishedExecuting(action: action)
  }
  
  func noCodesFinished() {
    delegate?.noCodesFinished()
  }
  
}

// MARK: - Private

extension NoCodesFlowCoordinator {
  
  private func topLevelViewController() -> UIViewController? {
    var controller = UIApplication.shared.keyWindow?.rootViewController
    while controller?.presentedViewController != nil {
      controller = controller?.presentedViewController
    }
    
    return controller
  }
  
}
