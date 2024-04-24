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
    private let localStorage: LocalStorageInterface
    private let internalConfig: InternalConfig
    
    init(requestProcessor: RequestProcessorInterface, localStorage: LocalStorageInterface, internalConfig: InternalConfig) {
        self.requestProcessor = requestProcessor
        self.localStorage = localStorage
        self.internalConfig = internalConfig
        
        prepareUserId()
    }
    
    func generateUserId() -> String {
        let uuidString: String = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let userId: String = Constants.userIdPrefix.rawValue + uuidString.lowercased()
        localStorage.set(userId, forKey: Constants.userIdKey.rawValue)
        internalConfig.userId = userId
        
        return userId
    }
    
    func createUser() async throws -> Qonversion.User {
        let userId: String = generateUserId()
        do {
            let request = Request.createUser(id: userId, body: ["environment": "sandbox"])
            let user: Qonversion.User = try await requestProcessor.process(request: request, responseType: Qonversion.User.self)
            
            return user
        } catch {
            throw QonversionError(type: .userCreationFailed, message: nil, error: error)
        }
    }
    
    func user() async throws -> Qonversion.User {
        let request = Request.getUser(id: internalConfig.userId)
        do {
            let user: Qonversion.User = try await requestProcessor.process(request: request, responseType: Qonversion.User.self)
            
            return user
        } catch {
            throw QonversionError(type: .userLoadingFailed, message: nil, error: error)
        }
    }
}

// MARK: - Private

extension UserService {
    
    private func prepareUserId() {
        let userId: String = localStorage.string(forKey: Constants.userIdKey.rawValue) ?? generateUserId()
        internalConfig.userId = userId
    }
}
