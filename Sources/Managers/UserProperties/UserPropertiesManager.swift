//
//  UserPropertiesManager.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 23.02.2024.
//

import Foundation
#if canImport(AdServices)
import AdServices
#endif

fileprivate enum Constants: Int {
    case sendPropertiesMinDelaySec = 5
}

final class UserPropertiesManager : UserPropertiesManagerInterface {
    
    private let requestProcessor: RequestProcessorInterface
    private let propertiesStorage: PropertiesStorage
    private let delayCalculator: IncrementalDelayCalculator
    private let userIdProvider: UserIdProvider
    private let logger: LoggerWrapper

    private var sendingTask: Task<Void, Error>? = nil
    private var sendPropertiesRetryDelay: Int = Constants.sendPropertiesMinDelaySec.rawValue
    private var sendPropertiesRetryCount: Int = 0
    
    init(
        requestProcessor: RequestProcessorInterface,
        propertiesStorage: PropertiesStorage,
        delayCalculator: IncrementalDelayCalculator,
        userIdProvider: UserIdProvider,
        logger: LoggerWrapper
    ) {
        self.requestProcessor = requestProcessor
        self.propertiesStorage = propertiesStorage
        self.delayCalculator = delayCalculator
        self.userIdProvider = userIdProvider
        self.logger = logger
    }
    
    func collectAppleSearchAdsAttribution() {
        if #available(iOS 14.3, *) {
            do {
                let token: String = try AAAttribution.attributionToken()
                
                processRequest(with: token)
            } catch {
                logger.error("\(LoggerInfoMessages.failedToCollectAppleSearchAdsAttribution.rawValue) \(error)")
            }
        } else {
            logger.warning(LoggerInfoMessages.unableToCollectAppleSearchAdsAttribution.rawValue)
        }
    }
    
    func userProperties() async throws -> Qonversion.UserProperties {
        let request = Request.getProperties(userId: userIdProvider.getUserId())
        let properties: [Qonversion.UserProperty]? = try? await requestProcessor.process(request: request, responseType: [Qonversion.UserProperty].self)
        let resultProperties: [Qonversion.UserProperty] = properties ?? []
        let result = Qonversion.UserProperties(resultProperties)
        return result
    }

    func setUserProperty(key: Qonversion.UserPropertyKey, value: String) {
        guard key != .custom else {
            return print("Can not set user property with the key `.custom`. " +
                    "To set custom user property, use the `setCustomUserProperty` method.")
        }
        
        setCustomUserProperty(key: key.rawValue, value: value)
    }

    func setCustomUserProperty(key: String, value: String) {
        guard !value.isEmpty else { return }

        let userProperty = Qonversion.UserProperty(key: key, value: value)
        propertiesStorage.save(userProperty)
        
        guard sendingTask == nil else { return }

        scheduleSendingProperties(withDelay: sendPropertiesRetryDelay)
    }

    func sendProperties() async throws {
        if (sendingTask != nil) {
            sendingTask?.cancel()
            sendingTask = nil
        }

        let properties: [Qonversion.UserProperty] = propertiesStorage.all()

        guard !properties.isEmpty else { return }
        
        #warning("Fix body type to prevent extra serializations")
        let body: RequestBodyArray = try properties.map { property in
            let data = try JSONEncoder().encode(property)
            return try JSONSerialization.jsonObject(with: data, options: []) as? RequestBodyDict
        }
        let request = Request.sendProperties(userId: userIdProvider.getUserId(), body: body)
        do {
            let result: SendUserPropertiesResult? = try await requestProcessor.process(request: request, responseType: SendUserPropertiesResult.self)
            result?.propertyErrors.forEach({ propertyError in
                print("Failed to save property " + propertyError.key + ": " + propertyError.error)
            })
            
            sendPropertiesRetryCount = 0
            sendPropertiesRetryDelay = Constants.sendPropertiesMinDelaySec.rawValue
            
            propertiesStorage.clear(properties: properties)
        } catch {
            retrySendingProperties()
        }
    }

    func clearDelayedProperties() {
        propertiesStorage.clear()
    }

}

// MARK: - Private

extension UserPropertiesManager {

    func processRequest(with token: String) {
        Task {
            do {
                let request = Request.appleSearchAds(userId: userIdProvider.getUserId(), body: ["token": token])
                let _ = try await requestProcessor.process(request: request, responseType: String.self)
                logger.info(LoggerInfoMessages.appleSearchAdsAttributionRequestSucceeded.rawValue)
            } catch {
                logger.error("\(LoggerInfoMessages.appleSearchAdsAttributionRequestFailed.rawValue) \(error)")
            }
        }
    }
    
    private func scheduleSendingProperties(withDelay delaySec: Int) {
        // Cancel for the case, when the previous task was scheduled via "setProperty" call, but then retry for another request occurred.
        sendingTask?.cancel()

        sendingTask = Task<Void, Error>.delayed(byTimeInterval: TimeInterval(delaySec)) {
            self.sendingTask = nil
            do {
                try await self.sendProperties()
            } catch {
                #warning("Handle error correctly")
                print(error)
            }
        }
    }

    private func retrySendingProperties() {
        sendPropertiesRetryCount += 1
        sendPropertiesRetryDelay = delayCalculator.countDelay(minDelay: Constants.sendPropertiesMinDelaySec.rawValue, retriesCount: sendPropertiesRetryCount)
        scheduleSendingProperties(withDelay: sendPropertiesRetryDelay)
    }
}
