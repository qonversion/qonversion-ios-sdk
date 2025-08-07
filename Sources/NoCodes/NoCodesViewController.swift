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
  private var noCodesMapper: NoCodesMapperInterface!
  private var viewsAssembly: ViewsAssembly!
  private var delegate: NoCodesViewControllerDelegate!
  private var logger: LoggerWrapper!
  private var skeletonView: SkeletonView!
  private var presentationConfiguration: NoCodesPresentationConfiguration!
  
  init(screenId: String?, contextKey: String?, delegate: NoCodesViewControllerDelegate, noCodesMapper: NoCodesMapperInterface, noCodesService: NoCodesServiceInterface, viewsAssembly: ViewsAssembly, logger: LoggerWrapper, presentationConfiguration: NoCodesPresentationConfiguration) {
    self.screenId = screenId
    self.contextKey = contextKey
    self.noCodesMapper = noCodesMapper
    self.noCodesService = noCodesService
    self.viewsAssembly = viewsAssembly
    self.delegate = delegate
    self.logger = logger
    self.presentationConfiguration = presentationConfiguration
    
    super.init(nibName: nil, bundle: nil)
    
    skeletonView = SkeletonView(frame: view.frame, interfaceStyle: traitCollection.userInterfaceStyle)
    addSkeleton()
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
        
        webView.loadHTMLString(screen.html, baseURL: nil)
      } catch {
        delegate.noCodesFailedToLoadScreen(error: nil)
        logger.error(LoggerInfoMessages.screenLoadingFailed.rawValue)
      }
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
  
  func addSkeleton() {
    view.addSubview(skeletonView)
    skeletonView.startAnimation()
  }
  
  func removeSkeleton() {
    skeletonView.removeFromSuperview()
    skeletonView.stopAnimation()
  }
  
}

extension NoCodesViewController: WKScriptMessageHandler {
  
  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard let body = message.body as? [String: Any] else { return }
    
    let action: NoCodesAction = noCodesMapper.map(rawAction: body)
    
    if action.type == .showScreen {
      return removeSkeleton()
    }
    
    if action.type != .loadProducts {
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
    default: break
    }
  }
  
}

extension NoCodesViewController {
  
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

        let options = Qonversion.PurchaseOptions()
        options.screenUid = screenId

        try await Qonversion.shared().purchaseProduct(product, options: options)
        activityIndicator.stopAnimating()
        finishAndClose(action: purchaseAction)
      } catch {
        logger.error(error.localizedDescription)
        activityIndicator.stopAnimating()
        delegate.noCodesFailedToExecute(action: purchaseAction, error: error)
      }
    }
  }
  
  private func handle(restoreAction: NoCodesAction) {
    activityIndicator.startAnimating()
    Task {
      do {
        let _ = try await Qonversion.shared().restore()
        finishAndClose(action: restoreAction)
        activityIndicator.stopAnimating()
      } catch {
        logger.error(error.localizedDescription)
        activityIndicator.stopAnimating()
        delegate.noCodesFailedToExecute(action: restoreAction, error: error)
      }
    }
  }
  
  private func handle(navigationAction: NoCodesAction) {
    guard let screenId: String = navigationAction.parameters?[Constants.screenId.rawValue] as? String else { return }
    
    let viewController = viewsAssembly.viewController(with: screenId, delegate: delegate, presentationConfiguration: presentationConfiguration)
    navigationController?.pushViewController(viewController, animated: true)
    delegate.noCodesFinishedExecuting(action: navigationAction)
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
