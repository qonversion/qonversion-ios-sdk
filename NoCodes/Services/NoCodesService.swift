//
//  NoCodesService.swift
//  NoCodes
//
//  Created by Suren Sarkisyan on 18.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation

class NoCodesService: NoCodesServiceInterface {
  
  private let requestProcessor: RequestProcessorInterface
  
  init(requestProcessor: RequestProcessorInterface) {
    self.requestProcessor = requestProcessor
  }
  
  func loadScreen(with id: String) async throws -> NoCodes.Screen {
    do {
      let request = Request.getScreen(id: id)
      let screen: NoCodes.Screen = try await requestProcessor.process(request: request, responseType: NoCodes.Screen.self)
      
      return screen
    } catch {
      throw QonversionError(type: .screenLoadingFailed, message: nil, error: error)
    }
  }
  
}
