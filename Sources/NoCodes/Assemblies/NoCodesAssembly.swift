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
  let servicesAssembly: ServicesAssembly
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
    let coordinator = NoCodesFlowCoordinator(delegate: configuration.delegate, screenCustomizationDelegate: configuration.screenCustomizationDelegate, noCodesService: noCodesService, viewsAssembly: viewsAssembly(), servicesAssembly: servicesAssembly, logger: miscAssembly.loggerWrapper())
    flowCoordinatorInstance = coordinator
    
    return coordinator
  }
  
  func viewsAssembly() -> ViewsAssembly {
    return ViewsAssembly(miscAssembly: miscAssembly, servicesAssembly: servicesAssembly)
  }
  
}

#endif
