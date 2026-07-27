//
//  NoCodesAssembly.swift
//  NoCodes
//
//  Created by Suren Sarkisyan on 17.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation

#if os(iOS)

final class NoCodesAssembly {
  
  let configuration: NoCodesConfiguration
  private let miscAssembly: MiscAssembly
  private let servicesAssembly: ServicesAssembly
  private var flowCoordinatorInstance: NoCodesFlowCoordinator?
  
  required init(configuration: NoCodesConfiguration) {
    self.configuration = configuration
    miscAssembly = MiscAssembly(projectKey: configuration.projectKey)
    servicesAssembly = ServicesAssembly(miscAssembly: miscAssembly, fallbackFileName: configuration.fallbackFileName, proxyURL: configuration.proxyURL)
    miscAssembly.servicesAssembly = servicesAssembly
  }
  
  func flowCoordinator() -> NoCodesFlowCoordinator {
    if let flowCoordinatorInstance {
      return flowCoordinatorInstance
    }
    
    let noCodesService: NoCodesServiceInterface = servicesAssembly.noCodesService()
    let screenEventsService: ScreenEventsServiceInterface = servicesAssembly.screenEventsService()
    let coordinator = NoCodesFlowCoordinator(delegate: configuration.delegate, screenCustomizationDelegate: configuration.screenCustomizationDelegate, purchaseDelegate: configuration.purchaseDelegate, customVariablesDelegate: configuration.customVariablesDelegate, noCodesService: noCodesService, screenEventsService: screenEventsService, viewsAssembly: viewsAssembly(), logger: miscAssembly.loggerWrapper(), customLocale: configuration.locale, theme: configuration.theme)
    flowCoordinatorInstance = coordinator
    
    return coordinator
  }
  
  func viewsAssembly() -> ViewsAssembly {
    return ViewsAssembly(miscAssembly: miscAssembly, servicesAssembly: servicesAssembly)
  }
  
}

#endif
