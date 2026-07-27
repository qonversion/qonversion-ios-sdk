//
//  MiscAssembly.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 27.03.2024.
//

import Foundation
import OSLog
import StoreKit

fileprivate enum IntConstants: UInt {
    case maxRequestsPerSecond = 5
}

fileprivate enum StringConstants: String {
    case requestsStorageKey = "requests"
}

final class MiscAssembly {
    
    let apiKey: String
    let userDefaults: UserDefaults
    
    // Weak: ServicesAssembly holds MiscAssembly strongly; a strong back
    // reference would leak the whole graph on every initialize.
    weak var servicesAssembly: ServicesAssembly!
    var internalConfig: InternalConfig

    // One instance SDK-wide: the user gate notifies through it, and every
    // user-scoped cache registers with it.
    private let userChangesNotifierInstance = UserChangesNotifier()

    // One instance SDK-wide: every per-service RequestProcessor persists into
    // the same UserDefaults key — separate instances would race their locks
    // and lose queued requests.
    private var requestsStorageInstance: RequestsStorageInterface?
    private var replayQueueObserver: ReplayQueueUserObserver?

    init(apiKey: String, userDefaults: UserDefaults, internalConfig: InternalConfig) {
        self.apiKey = apiKey
        self.userDefaults = userDefaults
        self.internalConfig = internalConfig
    }

    func userChangesNotifier() -> UserChangesNotifier {
        return userChangesNotifierInstance
    }
    
    func localStorage() -> LocalStorage {
        let encoder: JSONEncoder = encoder()
        let decoder: JSONDecoder = jsonDecoder()
        let localStorage = LocalStorage(userDefaults: userDefaults, encoder: encoder, decoder: decoder)

        return localStorage
    }
    
    func userIdProvider() -> UserIdProvider {
        return internalConfig
    }
    
    func delayCalculator() -> IncrementalDelayCalculator {
        return IncrementalDelayCalculator()
    }
    
    func userPropertiesStorage() -> UserPropertiesStorage {
        return UserPropertiesStorage()
    }
    
    func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        // Must mirror jsonDecoder(): the cache round-trip (e.g. User.creationDate)
        // breaks with mismatched date strategies.
        encoder.dateEncodingStrategy = .iso8601

        return encoder
    }
    
    func requestsStorage() -> RequestsStorageInterface {
        if let requestsStorageInstance {
            return requestsStorageInstance
        }

        // Scoped by apiKey: the replayed requests are stamped with the CURRENT
        // Authorization, so another project's queue must never leak into it.
        let storeKey: String = InternalConstants.storagePrefix.rawValue + StringConstants.requestsStorageKey.rawValue + "." + apiKey
        let requestsStorage = RequestsStorage(userDefaults: userDefaults, storeKey: storeKey)
        requestsStorageInstance = requestsStorage

        // Queued requests carry the previous user's uid in their URLs — they
        // must not be replayed against the account after a logout/identify
        // switch.
        let observer = ReplayQueueUserObserver(requestsStorage: requestsStorage)
        replayQueueObserver = observer
        userChangesNotifierInstance.add(observer: observer)

        return requestsStorage
    }
    
    func loggerWrapper() -> LoggerWrapper {
        return LoggerWrapper.make(logLevel: internalConfig.logLevel)
    }
    
    func rateLimiter() -> RateLimiterInterface {
        let rateLimiter = RateLimiter(maxRequestsPerSecond: IntConstants.maxRequestsPerSecond.rawValue)

        return rateLimiter
    }
    
    func jsonDecoder() -> JSONDecoder {
        let jsonDecoder = JSONDecoder()
        // v4 API: all dates are RFC3339 — with or without fractional seconds,
        // and unix timestamps on the fields inherited from the previous API
        // generation. A strict strategy would fail the whole payload.
        jsonDecoder.dateDecodingStrategy = .qonversionTolerant
        
        return jsonDecoder
    }
    
    func responseDecoder() -> ResponseDecoderInterface {
        let jsonDecoder: JSONDecoder = jsonDecoder()
        
        let responseDecoder = ResponseDecoder(decoder: jsonDecoder)
        
        return responseDecoder
    }
    
    func errorHandler() -> NetworkErrorHandlerInterface {
        let criticalErrorCodes: [ResponseCode] = [
            ResponseCode.unauthorized,
            ResponseCode.paymentRequired,
            ResponseCode.forbidden
        ]

        let responseDecoder: ResponseDecoderInterface = responseDecoder()

        let networkErrorHandler = NetworkErrorHandler(criticalErrorCodes: criticalErrorCodes, decoder: responseDecoder)
        
        return networkErrorHandler
    }
    
    func headersBuilder() -> HeadersBuilderInterface {
        let deviceInfoCollector: DeviceInfoCollectorInterface = servicesAssembly.deviceInfoCollector()
        let headersBuilder = HeadersBuilder(apiKey: apiKey, sdkVersion: SDKVersion.current, deviceInfoCollector: deviceInfoCollector, userDefaults: userDefaults)
        
        return headersBuilder
    }
    
}

/// Clears the offline replay queue when the SDK switches users.
private final class ReplayQueueUserObserver: UserChangedObserver {

    private let requestsStorage: RequestsStorageInterface

    init(requestsStorage: RequestsStorageInterface) {
        self.requestsStorage = requestsStorage
    }

    var userChangeTeardownPriority: Int { UserChangeTeardownPriority.outgoingQueue }

    func userDidChange() {
        requestsStorage.clean()
    }
}
