//
//  ViewsAssembly.swift
//  NoCodes
//
//  Created by Suren Sarkisyan on 23.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation

#if os(iOS)

final class ViewsAssembly {
  
  private let miscAssembly: MiscAssembly
  private let servicesAssembly: ServicesAssembly
  
  init(miscAssembly: MiscAssembly, servicesAssembly: ServicesAssembly) {
    self.miscAssembly = miscAssembly
    self.servicesAssembly = servicesAssembly
  }

  func viewController(with screenId: String, delegate: NoCodesViewControllerDelegate, purchaseDelegate: NoCodesPurchaseDelegate?, presentationConfiguration: NoCodesPresentationConfiguration, customLocale: String? = nil, theme: NoCodesTheme = .auto) -> NoCodesViewController {
      return NoCodesViewController(screenId: screenId, contextKey: nil, delegate: delegate, purchaseDelegate: purchaseDelegate, noCodesMapper: miscAssembly.noCodesMapper(), noCodesService: servicesAssembly.noCodesService(), screenEventsService: servicesAssembly.screenEventsService(), viewsAssembly: self, logger: miscAssembly.loggerWrapper(), presentationConfiguration: presentationConfiguration, customLocale: customLocale, theme: theme)
  }

  func viewController(withContextKey contextKey: String, delegate: NoCodesViewControllerDelegate, purchaseDelegate: NoCodesPurchaseDelegate?, presentationConfiguration: NoCodesPresentationConfiguration, customLocale: String? = nil, theme: NoCodesTheme = .auto) -> NoCodesViewController {
      return NoCodesViewController(screenId: nil, contextKey: contextKey, delegate: delegate, purchaseDelegate: purchaseDelegate, noCodesMapper: miscAssembly.noCodesMapper(), noCodesService: servicesAssembly.noCodesService(), screenEventsService: servicesAssembly.screenEventsService(), viewsAssembly: self, logger: miscAssembly.loggerWrapper(), presentationConfiguration: presentationConfiguration, customLocale: customLocale, theme: theme)
  }
}

#endif
