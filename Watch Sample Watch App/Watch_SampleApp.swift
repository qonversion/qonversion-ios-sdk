//
//  Watch_SampleApp.swift
//  Watch Sample Watch App
//
//  Created by Suren Sarkisyan on 21.07.2025.
//  Copyright © 2025 Qonversion Inc. All rights reserved.
//

import SwiftUI
import Qonversion

@main
struct Watch_Sample_Watch_AppApp: App {
  init() {
      setupQonversion()
    }
    
    var body: some Scene {
      WindowGroup {
        ContentView()
      }
    }
    
    private func setupQonversion() {
      let configuration = Qonversion.Configuration(projectKey: "PV77YHL7qnGvsdmpTs7gimsxUvY-Znl2", launchMode: .subscriptionManagement)
      configuration.setEnvironment(.sandbox)
      
      Qonversion.initWithConfig(configuration)
      
      Qonversion.shared().syncHistoricalData()
    }
}
