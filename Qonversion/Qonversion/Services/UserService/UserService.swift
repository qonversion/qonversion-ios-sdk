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
        
        prepareUserId()
    }
    
    func generateUserId() -> String {
        let uuidString: String = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let userId: String = Constants.userIdPrefix.rawValue + uuidString.lowercased()
        userDefaults.set(userId, forKey: Constants.userIdKey.rawValue)
        internalConfig.userId = userId
        
        return userId
    }
    
    func createUser() async throws -> User {
        let userId: String = generateUserId()
        do {
            let request = Request.createUser(id: userId, body: ["environment": "sandbox"])
            let user: User = try await requestProcessor.process(request: request, responseType: User.self)
            
            return user
        } catch {
            throw QonversionError(type: .userCreationFailed, message: nil, error: error)
        }
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

// MARK: - Private

extension UserService {
    
    private func prepareUserId() {
        let userId: String = userDefaults.string(forKey: Constants.userIdKey.rawValue) ?? generateUserId()
        internalConfig.userId = userId
    }
    
}
