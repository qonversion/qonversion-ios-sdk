//
//  UserPropertiesManager.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 23.02.2024.
//

import Foundation

final class UserPropertiesManager : UserPropertiesManagerInterface {
    
    private let requestProcessor: RequestProcessorInterface
    
    init(requestProcessor: RequestProcessorInterface) {
        self.requestProcessor = requestProcessor
    }
    
    func userProperties(for userId: String) async throws -> UserProperties {
        let request = Request.getProperties(userId: userId)
        let properties = try await requestProcessor.process(request: request, responseType: [UserProperty].self)
        let resultProperties: [UserProperty] = properties ?? []
        let result = UserProperties(resultProperties)
        return result
    }
}
