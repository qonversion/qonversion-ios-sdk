//
//  UserService.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 10.03.2024.
//

import Foundation

fileprivate enum Constants: String {
    case userIdKey = "qonversion.keys.userId"
    case userIdPrefix = "QON_"
}

final class UserService: UserServiceInterface {
    
    private let requestProcessor: RequestProcessorInterface
    private let userDefaults: UserDefaults
    private let internalConfig: InternalConfig
    
    init(requestProcessor: RequestProcessorInterface, userDefaults: UserDefaults, internalConfig: InternalConfig) {
        self.requestProcessor = requestProcessor
        self.userDefaults = userDefaults
        self.internalConfig = internalConfig
    }
    
    func userId() -> String {
        guard let userId: String = userDefaults.string(forKey: Constants.userIdKey.rawValue) else {
            return generateUserId()
        }
        
        return userId
    }
    
    func generateUserId() -> String {
        let uuidString: String = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let userId: String = Constants.userIdPrefix.rawValue + uuidString.lowercased()
        userDefaults.set(userId, forKey: Constants.userIdKey.rawValue)
        
        return userId
    }
    
    func user() async throws -> User {
        let request = Request.getUser(id: internalConfig.userId)
        do {
            let user: User = try await requestProcessor.process(request: request, responseType: User.self)
            
            return user
        } catch {
            throw QonversionError(type: .userLoadingFailed, message: nil, error: error)
        }
    }
    
}
