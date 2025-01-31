//
//  NoCodesViewsAssembly.swift
//  NoCodes
//
//  Created by Suren Sarkisyan on 23.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation

final class NoCodesViewsAssembly {
  
  private let miscAssembly: MiscAssembly
  private let servicesAssembly: ServicesAssembly
  
  init(miscAssembly: MiscAssembly, servicesAssembly: ServicesAssembly) {
    self.miscAssembly = miscAssembly
    self.servicesAssembly = servicesAssembly
  }
  
  func viewController(with screen: NoCodes.Screen, delegate: NoCodesViewControllerDelegate) -> NoCodesViewController {
    return NoCodesViewController(screen: screen, delegate: delegate, noCodesMapper: miscAssembly.noCodesMapper(), noCodesService: servicesAssembly.noCodesService(), viewsAssembly: self)
  }
  
}
