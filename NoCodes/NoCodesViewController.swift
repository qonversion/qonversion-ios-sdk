//
//  NoCodesViewController.swift
//  NoCodes
//
//  Created by Suren Sarkisyan on 23.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation
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
  case cancelActionTitle = "Ok"
  case errorTitle = "Error"
}

protocol NoCodesViewControllerDelegate {
  
  func noCodesShownScreen(id: String)
  
  func noCodesStartsExecuting(action: NoCodes.Action)
  
  func noCodesFailedExecuting(action: NoCodes.Action, error: Error?)

  func noCodesFinishedExecuting(action: NoCodes.Action)

  func noCodesFinished()
}

final class NoCodesViewController: UIViewController {
  
  private var webView: WKWebView!
  private var activityIndicator: UIActivityIndicatorView!
  private var screen: NoCodes.Screen?
  private var noCodesService: NoCodesServiceInterface!
  private var noCodesMapper: NoCodesMapperInterface!
  private var viewsAssembly: NoCodesViewsAssembly!
  private var delegate: NoCodesViewControllerDelegate!
  
  init(screen: NoCodes.Screen, delegate: NoCodesViewControllerDelegate, noCodesMapper: NoCodesMapperInterface, noCodesService: NoCodesServiceInterface, viewsAssembly: NoCodesViewsAssembly) {
    self.screen = screen
    self.noCodesMapper = noCodesMapper
    self.noCodesService = noCodesService
    self.viewsAssembly = viewsAssembly
    self.delegate = delegate
    
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    
    guard let screen else { return }
    
    let userContentController = WKUserContentController()
    userContentController.add(self, name: "noCodesMessageHandler")
    let configuration = WKWebViewConfiguration()
    configuration.userContentController = userContentController;
    
    configuration.allowsInlineMediaPlayback = true
    configuration.allowsAirPlayForMediaPlayback = true
    configuration.mediaTypesRequiringUserActionForPlayback = []
    configuration.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
    
    webView = WKWebView(frame: .zero, configuration: configuration)
    
    webView.scrollView.bounces = false
    webView.scrollView.isScrollEnabled = false
    webView.scrollView.contentInsetAdjustmentBehavior = .never
//    webView.isInspectable = true
    
    webView.scrollView.showsHorizontalScrollIndicator = false
    webView.scrollView.delegate = self
    view.addSubview(webView)
    
    //  [self.delegate automationsDidShowScreen:self.screen.screenID];
    
    activityIndicator = UIActivityIndicatorView(style: .large)
    activityIndicator.color = .lightGray
    activityIndicator.hidesWhenStopped = true
    view.addSubview(activityIndicator)
    
    guard let path: String = Bundle.main.path(forResource: "index", ofType: "html") else { return }
    let localHTMLUrl = URL(fileURLWithPath: path, isDirectory: false)
    webView.loadFileURL(localHTMLUrl, allowingReadAccessTo: localHTMLUrl)
//    webView.loadHTMLString(screen.html, baseURL: nil)
    
    view.layoutSubviews()
    webView.setNeedsLayout()
    webView.layoutIfNeeded()
    
    let htmlString = "\n        <!DOCTYPE html>\n        <html lang=\"en\">\n        <head>\n          <meta charset=\"UTF-8\">\n          <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n          <title>Generated Page</title>\n          <style>\n            * { box-sizing: border-box; } body {margin: 0;}#iw11{padding-top:32px;padding-bottom:32px;padding-left:20px;padding-right:20px;font-family:'Roboto', sans-serif;overflow-x:hidden;}#iunl{text-align:center;}[data-gjs-type=\"Container\"]{height:200px;}[data-gjs-type=\"Container\"]:has(> *){height:100%;}#itrm{display:flex;width:100%;}#i3795{text-align:center;}#ikfuj{display:flex;width:100%;}#ie7al{text-align:center;}#ix8n4{text-align:center;}#iep5c{display:flex;width:100%;}#iy3rh{text-align:center;}#i3dgi{display:flex;width:100%;}#iyuyg{text-align:center;}#iapbi{text-align:center;}#ixo4t{display:flex;width:100%;}#i85ii{display:flex;width:100%;}#iosyh{display:flex;width:100%;}#i4wyh{text-align:center;}#is2kf{display:flex;width:100%;}#iunxf{text-align:center;}#i6w6k{text-align:center;}#iqo7r{display:flex;width:100%;}#ib1lo{display:flex;width:100%;}#i34yh{border:1px solid #e0e0e0;border-radius:8px;padding:8px 12px;cursor:pointer;text-decoration:none;display:flex;align-items:center;justify-content:center;background-color:#ffffff;box-shadow:0 2px 8px rgba(0, 0, 0, 0.05);}#il8gh{text-align:center;}#iidwe{display:flex;width:100%;}#i8e2f{display:flex;width:100%;}#ig3nn{display:flex;width:100%;}#i6c8k{width:100%;}@media (max-width: 100vw){#iw11{background-repeat:no-repeat;background-position:center top;background-attachment:scroll;background-size:cover;background-image:url('https://imagedelivery.net/t0YS8XuDQ4jaX81WlOyrmA/8d703d08-f6b2-48a0-771e-3bc098abef00/public');background-image-color:unset;background-image-gradient:unset;background-image-gradient-dir:unset;background-image-gradient-type:unset;padding-top:40px;padding-right:20px;padding-bottom:40px;padding-left:20px;font-family:'Roboto', sans-serif;}#iunl{color:#ffffff;}#itrm{flex-wrap:nowrap;justify-content:flex-start;align-items:flex-start;align-content:center;background-repeat:repeat;background-position:left top;background-attachment:scroll;background-size:auto;background-image:linear-gradient(#1D1929 0%, #1D1929 100%);border-radius:24px 24px 24px 24px;flex-direction:row;padding:20px 20px 20px 20px;margin:0px 0px 10px 0px;}#i3795{color:#616161;font-family:'Nunito', sans-serif;font-size:16px;align-self:flex-start;font-weight:300;display:block;text-align:left;}#ikfuj{flex-direction:column;flex-wrap:wrap;display:inline;}#ie7al{color:#ffffff;font-family:'Inter', sans-serif;font-size:18px;align-self:flex-start;display:inline;text-align:left;}#ix8n4{display:inline;font-size:25px;}#iep5c{display:inline;flex-direction:row;width:10%;}#iy3rh{display:inline;font-size:25px;}#i3dgi{display:inline;flex-direction:row;width:10%;}#iyuyg{color:#ffffff;font-family:'Inter', sans-serif;font-size:18px;align-self:flex-start;display:inline;text-align:left;}#iapbi{color:#616161;font-family:'Nunito', sans-serif;font-size:16px;align-self:flex-start;font-weight:300;display:block;text-align:left;}#ixo4t{flex-direction:column;flex-wrap:wrap;display:inline;}#i85ii{flex-wrap:nowrap;justify-content:flex-start;align-items:flex-start;align-content:center;background-repeat:repeat;background-position:left top;background-attachment:scroll;background-size:auto;background-image:linear-gradient(#1D1929 0%, #1D1929 100%);border-radius:24px 24px 24px 24px;flex-direction:row;padding:20px 20px 20px 20px;margin:0px 0px 10px 0px;}#iosyh{flex-direction:column;display:block;flex-wrap:nowrap;justify-content:space-around;margin:0 0px 0px 0px;}#i4wyh{display:inline;font-size:25px;}#is2kf{display:inline;flex-direction:row;width:10%;}#iunxf{color:#ffffff;font-family:'Inter', sans-serif;font-size:18px;align-self:flex-start;display:inline;text-align:left;}#i6w6k{color:#616161;font-family:'Nunito', sans-serif;font-size:16px;align-self:flex-start;font-weight:300;display:block;text-align:left;}#iqo7r{flex-direction:column;flex-wrap:wrap;display:inline;}#ib1lo{flex-wrap:nowrap;justify-content:flex-start;align-items:flex-start;align-content:center;background-repeat:repeat;background-position:left top;background-attachment:scroll;background-size:auto;background-image:linear-gradient(#1D1929 0%, #1D1929 100%);border-radius:24px 24px 24px 24px;flex-direction:row;padding:20px 20px 20px 20px;}#i34yh{background-color:#9B51E0;font-family:'Inter', sans-serif;font-weight:500;color:#ffffff;padding:16px 12px 16px 12px;border-radius:20px 20px 20px 20px;border:0 solid #e0e0e0;}#il8gh{font-family:'Inter', sans-serif;font-size:12px;font-weight:300;color:#9b51df;}#iidwe{flex-direction:column;margin:48px 0px 0px 0px;}#i8e2f{flex-direction:column;float:none;position:relative;display:flex;margin:190px 0px 0px 0px;}#ig3nn{float:none;display:inline;}#i6c8k{width:32px;height:31px;float:right;display:inline;align-self:center;}}\n          </style>\n        </head>\n        <body>\n          <div data-gjs-type=\"wrapper\" id=\"iw11\" class=\"wrapper\"><div href=\"qon-scheme://automation?action=close\" id=\"ig3nn\"><img id=\"i6c8k\" src=\"https://imagedelivery.net/t0YS8XuDQ4jaX81WlOyrmA/de021308-9fca-49c5-5de6-ee8ebe5e3100/public\"/></div><div href=\"qon-scheme://automation?\" id=\"i8e2f\"><h1 data-gjs-type=\"heading\" id=\"iunl\">Vimeo Plus</h1><div href=\"qon-scheme://automation?\" id=\"iosyh\"><div href=\"qon-scheme://automation?\" id=\"itrm\"><div href=\"qon-scheme://automation?\" id=\"iep5c\"><h1 data-gjs-type=\"heading\" id=\"ix8n4\">💡</h1></div><div href=\"qon-scheme://automation?\" id=\"ikfuj\"><h1 data-gjs-type=\"heading\" id=\"ie7al\">Priority access</h1><h1 data-gjs-type=\"heading\" id=\"i3795\">Plus subscribers have access to GPT-4 and our latest beta features.</h1></div></div><div href=\"qon-scheme://automation?\" id=\"i85ii\"><div href=\"qon-scheme://automation?\" id=\"i3dgi\"><h1 data-gjs-type=\"heading\" id=\"iy3rh\">🔥</h1></div><div href=\"qon-scheme://automation?\" id=\"ixo4t\"><h1 data-gjs-type=\"heading\" id=\"iyuyg\">Always available</h1><h1 data-gjs-type=\"heading\" id=\"iapbi\">You'll be able to use ChatGPT even when demand is high.</h1></div></div><div href=\"qon-scheme://automation?\" id=\"ib1lo\"><div href=\"qon-scheme://automation?\" id=\"is2kf\"><h1 data-gjs-type=\"heading\" id=\"i4wyh\">🏃‍♀</h1></div><div href=\"qon-scheme://automation?\" id=\"iqo7r\"><h1 data-gjs-type=\"heading\" id=\"iunxf\">Ultra-fast</h1><h1 data-gjs-type=\"heading\" id=\"i6w6k\">Enjoy even faster response speeds when using ChatGPT 3.5.</h1></div></div></div><div href=\"qon-scheme://automation?\" id=\"iidwe\"><div href=\"qon-scheme://automation?action=purchase\" id=\"i34yh\"><span data-gjs-type=\"text\" id=\"i10ae\">Start my free trial</span></div><h1 data-gjs-type=\"heading\" id=\"il8gh\">Auto-renews for  {{products.selected.price_per_month}} until canceled</h1></div></div></div><script>var props = {\"ig3nn\":{\"action\":\"closethescreen\",\"actionValue\":\"\"},\"i8e2f\":{\"action\":\"url\",\"actionValue\":\"\"},\"iosyh\":{\"action\":\"url\",\"actionValue\":\"\"},\"itrm\":{\"action\":\"url\",\"actionValue\":\"\"},\"iep5c\":{\"action\":\"url\",\"actionValue\":\"\"},\"ikfuj\":{\"action\":\"url\",\"actionValue\":\"\"},\"i85ii\":{\"action\":\"url\",\"actionValue\":\"\"},\"i3dgi\":{\"action\":\"url\",\"actionValue\":\"\"},\"ixo4t\":{\"action\":\"url\",\"actionValue\":\"\"},\"ib1lo\":{\"action\":\"url\",\"actionValue\":\"\"},\"is2kf\":{\"action\":\"url\",\"actionValue\":\"\"},\"iqo7r\":{\"action\":\"url\",\"actionValue\":\"\"},\"iidwe\":{\"action\":\"url\",\"actionValue\":\"\"}};\n          var ids = Object.keys(props).map(function(id) { return '#'+id }).join(',');\n          var els = document.querySelectorAll(ids);\n          for (var i = 0, len = els.length; i < len; i++) {\n            var el = els[i];\n            (function At(e){var t=e.action,n=e.actionValue,r=this;\"selectproduct\"===t&&(document.addEventListener(\"selectPoduct\",(function(e){e.detail.product===n?r.classList.add(\"select-product\"):r.classList.remove(\"select-product\")})),r.addEventListener(\"click\",(function(e){document.dispatchEvent(new CustomEvent(\"selectPoduct\",{detail:{product:n}}))})))}.bind(el))(props[el.id]);\n          }\n          var props = {\"iunl\":{},\"ix8n4\":{},\"ie7al\":{},\"i3795\":{},\"iy3rh\":{},\"iyuyg\":{},\"iapbi\":{},\"i4wyh\":{},\"iunxf\":{},\"i6w6k\":{},\"il8gh\":{}};\n          var ids = Object.keys(props).map(function(id) { return '#'+id }).join(',');\n          var els = document.querySelectorAll(ids);\n          for (var i = 0, len = els.length; i < len; i++) {\n            var el = els[i];\n            (function Wt(e){var t=e.action,n=e.actionValue,r=this;\"selectproduct\"===t&&document.addEventListener(\"selectPoduct\",(function(e){e.detail.product===n?r.classList.add(\"select-product\"):r.classList.remove(\"select-product\")}))}.bind(el))(props[el.id]);\n          }\n          var props = {\"i34yh\":{\"action\":\"makeapurchase\",\"actionValue\":\"\"}};\n          var ids = Object.keys(props).map(function(id) { return '#'+id }).join(',');\n          var els = document.querySelectorAll(ids);\n          for (var i = 0, len = els.length; i < len; i++) {\n            var el = els[i];\n            (function At(e){var t=e.action,n=e.actionValue,r=this;\"selectproduct\"===t&&(document.addEventListener(\"selectPoduct\",(function(e){e.detail.product===n?r.classList.add(\"select-product\"):r.classList.remove(\"select-product\")})),r.addEventListener(\"click\",(function(e){document.dispatchEvent(new CustomEvent(\"selectPoduct\",{detail:{product:n}}))})))}.bind(el))(props[el.id]);\n          }\n          var props = {\"i10ae\":{}};\n          var ids = Object.keys(props).map(function(id) { return '#'+id }).join(',');\n          var els = document.querySelectorAll(ids);\n          for (var i = 0, len = els.length; i < len; i++) {\n            var el = els[i];\n            (function Wt(e){var t=e.action,n=e.actionValue,r=this;\"selectproduct\"===t&&document.addEventListener(\"selectPoduct\",(function(e){e.detail.product===n?r.classList.add(\"select-product\"):r.classList.remove(\"select-product\")}))}.bind(el))(props[el.id]);\n          }</script>\n        <script>var props = {\"ig3nn\":{\"action\":\"closethescreen\",\"actionValue\":\"\"},\"i8e2f\":{\"action\":\"url\",\"actionValue\":\"\"},\"iosyh\":{\"action\":\"url\",\"actionValue\":\"\"},\"itrm\":{\"action\":\"url\",\"actionValue\":\"\"},\"iep5c\":{\"action\":\"url\",\"actionValue\":\"\"},\"ikfuj\":{\"action\":\"url\",\"actionValue\":\"\"},\"i85ii\":{\"action\":\"url\",\"actionValue\":\"\"},\"i3dgi\":{\"action\":\"url\",\"actionValue\":\"\"},\"ixo4t\":{\"action\":\"url\",\"actionValue\":\"\"},\"ib1lo\":{\"action\":\"url\",\"actionValue\":\"\"},\"is2kf\":{\"action\":\"url\",\"actionValue\":\"\"},\"iqo7r\":{\"action\":\"url\",\"actionValue\":\"\"},\"iidwe\":{\"action\":\"url\",\"actionValue\":\"\"}};\n          var ids = Object.keys(props).map(function(id) { return '#'+id }).join(',');\n          var els = document.querySelectorAll(ids);\n          for (var i = 0, len = els.length; i < len; i++) {\n            var el = els[i];\n            (function At(e){var t=e.action,n=e.actionValue,r=this;\"selectproduct\"===t&&(document.addEventListener(\"selectPoduct\",(function(e){e.detail.product===n?r.classList.add(\"select-product\"):r.classList.remove(\"select-product\")})),r.addEventListener(\"click\",(function(e){document.dispatchEvent(new CustomEvent(\"selectPoduct\",{detail:{product:n}}))})))}.bind(el))(props[el.id]);\n          }\n          var props = {\"iunl\":{},\"ix8n4\":{},\"ie7al\":{},\"i3795\":{},\"iy3rh\":{},\"iyuyg\":{},\"iapbi\":{},\"i4wyh\":{},\"iunxf\":{},\"i6w6k\":{},\"il8gh\":{}};\n          var ids = Object.keys(props).map(function(id) { return '#'+id }).join(',');\n          var els = document.querySelectorAll(ids);\n          for (var i = 0, len = els.length; i < len; i++) {\n            var el = els[i];\n            (function Wt(e){var t=e.action,n=e.actionValue,r=this;\"selectproduct\"===t&&document.addEventListener(\"selectPoduct\",(function(e){e.detail.product===n?r.classList.add(\"select-product\"):r.classList.remove(\"select-product\")}))}.bind(el))(props[el.id]);\n          }\n          var props = {\"i34yh\":{\"action\":\"makeapurchase\",\"actionValue\":\"\"}};\n          var ids = Object.keys(props).map(function(id) { return '#'+id }).join(',');\n          var els = document.querySelectorAll(ids);\n          for (var i = 0, len = els.length; i < len; i++) {\n            var el = els[i];\n            (function At(e){var t=e.action,n=e.actionValue,r=this;\"selectproduct\"===t&&(document.addEventListener(\"selectPoduct\",(function(e){e.detail.product===n?r.classList.add(\"select-product\"):r.classList.remove(\"select-product\")})),r.addEventListener(\"click\",(function(e){document.dispatchEvent(new CustomEvent(\"selectPoduct\",{detail:{product:n}}))})))}.bind(el))(props[el.id]);\n          }\n          var props = {\"i10ae\":{}};\n          var ids = Object.keys(props).map(function(id) { return '#'+id }).join(',');\n          var els = document.querySelectorAll(ids);\n          for (var i = 0, len = els.length; i < len; i++) {\n            var el = els[i];\n            (function Wt(e){var t=e.action,n=e.actionValue,r=this;\"selectproduct\"===t&&document.addEventListener(\"selectPoduct\",(function(e){e.detail.product===n?r.classList.add(\"select-product\"):r.classList.remove(\"select-product\")}))}.bind(el))(props[el.id]);\n          }</script>\n        </body>\n\n        </html>\n      "
  }
  
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    
    activityIndicator.center = view.center
    webView.frame = view.frame
  }
  
  func close() {
    close(action: nil)
  }
  
}

extension NoCodesViewController: WKScriptMessageHandler {
  
  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard let body = message.body as? [String: Any] else { return }
    
    let action: NoCodes.Action = noCodesMapper.map(rawAction: body)
    
    switch action.type {
    case .loadProducts: // +++
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
    case .purchase: // +++
      handle(purchaseAction: action)
    case .restore:
      handle(restoreAction: action)
    default: break
    }
  }
  
}

extension NoCodesViewController {
  
  private func send(event: String, data: String) async {
    let _ = try? await webView.evaluateJavaScript("window.dispatchEvent(new CustomEvent(\"\(event)\",  {detail: \(data)} ))")
  }
  
  private func handle(closeAction: NoCodes.Action) {
    if self.navigationController?.viewControllers.count ?? 0 > 1 {
      navigationController?.popViewController(animated: true)
      delegate.noCodesFinishedExecuting(action: closeAction)
      if let firstExternalViewController: UIViewController = firstExternalViewController(),
         let externalIndex: Int = navigationController?.viewControllers.firstIndex(of: firstExternalViewController),
         let viewControllersCount: Int = navigationController?.viewControllers.count,
         externalIndex == viewControllersCount - 2 {
        delegate.noCodesFinished()
      }
      // delegate finished ?
    } else {
      finishAndClose(action: closeAction)
    }
  }
  
  private func handle(loadProductsAction: NoCodes.Action) {
    Task {
      guard let productIds: [String] = loadProductsAction.parameters?["productIds"] as? [String],
            let products: [String: Qonversion.Product] = try? await Qonversion.shared().products()
      else { return }
      
      let filteredProducts: [String: Qonversion.Product] = products.filter { productIds.contains($0.key) }
      guard !filteredProducts.isEmpty else { return }
      
      let productsInfo: [String: Any] = noCodesMapper.map(products: filteredProducts)
      
      guard let data = try? JSONSerialization.data(withJSONObject: productsInfo, options: []),
            let jsString = String(data: data, encoding: .utf8)
      else { return }
      await send(event: Constants.setProducts.rawValue, data: jsString)
    }
  }
  
  private func handle(urlAction: NoCodes.Action) {
    guard let urlString: String = urlAction.parameters?[Constants.url.rawValue] as? String,
          let url = URL(string: urlString) else {
      return delegate.noCodesFailedExecuting(action: urlAction, error: nil)
    }
    
    let safariVC = SFSafariViewController(url: url)
    navigationController?.present(safariVC, animated: true)
    delegate.noCodesFinishedExecuting(action: urlAction)
  }
  
  private func handle(deepLinkAction: NoCodes.Action) {
    guard let deepLinkString: String = deepLinkAction.parameters?[Constants.deeplink.rawValue] as? String,
          let url = URL(string: deepLinkString) else {
      return delegate.noCodesFailedExecuting(action: deepLinkAction, error: nil)
    }
    
    if UIApplication.shared.canOpenURL(url) {
      UIApplication.shared.open(url)
    } else {
      delegate.noCodesFailedExecuting(action: deepLinkAction, error: nil)
      close(action: deepLinkAction)
    }
  }
  
  private func handle(purchaseAction: NoCodes.Action) {
    guard let productId: String = purchaseAction.parameters?[Constants.productId.rawValue] as? String else { return }
    activityIndicator.startAnimating()
    Task {
      do {
        try await Qonversion.shared().purchase(productId)
        activityIndicator.stopAnimating()
        finishAndClose(action: purchaseAction)
      } catch {
        activityIndicator.stopAnimating()
        delegate.noCodesFailedExecuting(action: purchaseAction, error: error)
        showAlert(title: Constants.errorTitle.rawValue, message: error.localizedDescription)
      }
    }
  }
  
  private func handle(restoreAction: NoCodes.Action) {
    activityIndicator.startAnimating()
    Task {
      do {
        let _ = try await Qonversion.shared().restore()
        finishAndClose(action: restoreAction)
        activityIndicator.stopAnimating()
      } catch {
        activityIndicator.stopAnimating()
        delegate.noCodesFailedExecuting(action: restoreAction, error: error)
        showAlert(title: Constants.errorTitle.rawValue, message: error.localizedDescription)
      }
    }
  }
  
  private func handle(navigationAction: NoCodes.Action) {
    guard let screenId: String = navigationAction.parameters?[Constants.screenId.rawValue] as? String else { return }
    
    activityIndicator.startAnimating()
    Task {
      do {
        let screen: NoCodes.Screen = try await noCodesService.loadScreen(with: screenId)
        activityIndicator.stopAnimating()
        let viewController = viewsAssembly.viewController(with: screen, delegate: delegate)
        navigationController?.pushViewController(viewController, animated: true)
        delegate.noCodesFinishedExecuting(action: navigationAction)
      } catch {
        activityIndicator.stopAnimating()
        delegate.noCodesFailedExecuting(action: navigationAction, error: error)
        showAlert(title: Constants.errorTitle.rawValue, message: error.localizedDescription)
      }
    }
  }
  
  private func finishAndClose(action: NoCodes.Action) {
    delegate.noCodesFinishedExecuting(action: action)
    close(action: action)
  }
  
  private func close(action: NoCodes.Action?) {
    if navigationController?.presentingViewController != nil {
      dismiss(animated: true) {
        self.delegate.noCodesFinished()
      }
    } else {
      guard let vcToPop: UIViewController = firstExternalViewController() else { return }
      navigationController?.popToViewController(vcToPop, animated: true)
      delegate.noCodesFinished()
    }
  }
  
  private func showAlert(title: String, message: String, handler: ((UIAlertAction) -> Void)? = nil) {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    let action = UIAlertAction(title: Constants.cancelActionTitle.rawValue, style: .cancel, handler: handler)
    alert.addAction(action)
    
    navigationController?.present(alert, animated: true)
  }
  
  private func firstExternalViewController() -> UIViewController? {
    let currentViewControllers: [UIViewController]? = navigationController?.viewControllers
    let firstExternalVC: UIViewController? = currentViewControllers?.first(where: { !$0.isKind(of: Self.self) })
    
    return firstExternalVC
  }
  
}

extension NoCodesViewController: UIScrollViewDelegate {
  func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
    scrollView.pinchGestureRecognizer?.isEnabled = false
  }
}
