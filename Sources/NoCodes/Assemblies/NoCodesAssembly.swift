//
//  NoCodesAssembly.swift
//  NoCodes
//
//  Created by Suren Sarkisyan on 17.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation
@_spi(QonversionInternal) import Qonversion

#if os(iOS)

@MainActor
final class NoCodesAssembly {
  
  let configuration: NoCodesConfiguration
  let miscAssembly: MiscAssembly
  private let servicesAssembly: ServicesAssembly
  private var flowCoordinatorInstance: NoCodesFlowCoordinator?
  
  required init(configuration: NoCodesConfiguration, isFirstLaunch: Bool) {
    self.configuration = configuration
    let userDefaults = QonversionDefaults.resolve(configuration.userDefaults)
    miscAssembly = MiscAssembly(projectKey: configuration.projectKey, userDefaults: userDefaults, isFirstLaunch: isFirstLaunch)
    servicesAssembly = ServicesAssembly(miscAssembly: miscAssembly, fallbackFileName: configuration.fallbackFileName, proxyURL: configuration.proxyURL)
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
