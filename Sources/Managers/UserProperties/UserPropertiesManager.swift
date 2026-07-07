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
    // After this many failed attempts the batch stays in the storage but the
    // scheduling stops; the next setProperty call re-triggers sending.
    case sendPropertiesMaxRetries = 10
}

final class UserPropertiesManager : UserPropertiesManagerInterface {
    
    private let requestProcessor: RequestProcessorInterface
    private let propertiesStorage: PropertiesStorage
    private let delayCalculator: IncrementalDelayCalculator
    private let userIdProvider: UserIdProvider
    private let userManager: UserManagerInterface
    private let logger: LoggerWrapper

    private var sendingTask: Task<Void, Error>? = nil
    private var sendPropertiesRetryDelay: Int = Constants.sendPropertiesMinDelaySec.rawValue
    private var sendPropertiesRetryCount: Int = 0
    private var isSendingInProgress: Bool = false
    
    init(
        requestProcessor: RequestProcessorInterface,
        propertiesStorage: PropertiesStorage,
        delayCalculator: IncrementalDelayCalculator,
        userIdProvider: UserIdProvider,
        userManager: UserManagerInterface,
        logger: LoggerWrapper
    ) {
        self.requestProcessor = requestProcessor
        self.propertiesStorage = propertiesStorage
        self.delayCalculator = delayCalculator
        self.userIdProvider = userIdProvider
        self.userManager = userManager
        self.logger = logger
    }
    
    func collectAppleSearchAdsAttribution() {
        #if canImport(AdServices)
        if #available(iOS 14.3, macOS 11.1, visionOS 1.0, *) {
            do {
                let token: String = try AAAttribution.attributionToken()

                processRequest(with: token)
            } catch {
                logger.error("\(LoggerInfoMessages.failedToCollectAppleSearchAdsAttribution.rawValue) \(error)")
            }
        } else {
            logger.warning(LoggerInfoMessages.unableToCollectAppleSearchAdsAttribution.rawValue)
        }
        #else
        logger.warning(LoggerInfoMessages.unableToCollectAppleSearchAdsAttribution.rawValue)
        #endif
    }
    
    func userProperties() async throws -> Qonversion.UserProperties {
        try await userManager.obtainUser()

        let request = Request.getProperties(userId: userIdProvider.getUserId())
        let properties: [Qonversion.UserProperty]? = try? await requestProcessor.process(request: request, responseType: [Qonversion.UserProperty].self)
        let resultProperties: [Qonversion.UserProperty] = properties ?? []
        let result = Qonversion.UserProperties(resultProperties)
        return result
    }

    func setUserProperty(key: Qonversion.UserPropertyKey, value: String) {
        guard key != .custom else {
            logger.warning("Can not set user property with the key `.custom`. " +
                    "To set custom user property, use the `setCustomUserProperty` method.")
            return
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
        // Single-flight: a batch already in flight covers the current storage
        // snapshot; properties added meanwhile are picked up by the trailing
        // reschedule below.
        guard !isSendingInProgress else { return }
        isSendingInProgress = true
        defer { isSendingInProgress = false }

        if (sendingTask != nil) {
            sendingTask?.cancel()
            sendingTask = nil
        }

        let properties: [Qonversion.UserProperty] = propertiesStorage.all()

        guard !properties.isEmpty else { return }

        // The backend user must exist before any data is sent. On failure keep
        // the properties and retry later — the gate itself retries creation on
        // the next demand.
        do {
            try await userManager.obtainUser()
        } catch {
            logger.warning("Failed to obtain user before sending properties: " + error.message)
            retrySendingProperties()
            return
        }

        let body: RequestBodyArray = properties.map { ["key": $0.key, "value": $0.value] as RequestBodyDict }
        let request = Request.sendProperties(userId: userIdProvider.getUserId(), body: body)
        do {
            let result: SendUserPropertiesResult? = try await requestProcessor.process(request: request, responseType: SendUserPropertiesResult.self)
            result?.propertyErrors.forEach({ propertyError in
                logger.error("Failed to save property " + propertyError.key + ": " + propertyError.error)
            })
            
            sendPropertiesRetryCount = 0
            sendPropertiesRetryDelay = Constants.sendPropertiesMinDelaySec.rawValue
            
            propertiesStorage.clear(properties: properties)

            // Properties set while the batch was in flight.
            if !propertiesStorage.all().isEmpty {
                scheduleSendingProperties(withDelay: Constants.sendPropertiesMinDelaySec.rawValue)
            }
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
                // sendProperties handles its own retries; anything reaching
                // here is unexpected and must not crash the schedule chain.
                self.logger.error("Failed to send user properties: \(error)")
            }
        }
    }

    private func retrySendingProperties() {
        sendPropertiesRetryCount += 1
        guard sendPropertiesRetryCount <= Constants.sendPropertiesMaxRetries.rawValue else {
            logger.error("Giving up sending user properties after \(Constants.sendPropertiesMaxRetries.rawValue) attempts; kept for the next trigger.")
            sendPropertiesRetryCount = 0
            sendPropertiesRetryDelay = Constants.sendPropertiesMinDelaySec.rawValue
            return
        }
        sendPropertiesRetryDelay = delayCalculator.countDelay(minDelay: Constants.sendPropertiesMinDelaySec.rawValue, retriesCount: sendPropertiesRetryCount)
        scheduleSendingProperties(withDelay: sendPropertiesRetryDelay)
    }
}
