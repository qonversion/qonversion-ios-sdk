//
//  QonversionAssembly.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 13.03.2024.
//

import Foundation

final class QonversionAssembly {
    
    let servicesAssembly: ServicesAssembly
    private let miscAssembly: MiscAssembly

    // The user gate is stateful (single-flight creation pipeline) — it must be
    // one instance SDK-wide, like InternalConfig.
    private var userManagerInstance: UserManagerInterface?

    // Holds the in-memory products and mapping caches consumed by the local
    // entitlements calculation — stateful, one instance SDK-wide.
    private var productsManagerInstance: ProductsManager?

    // Holds the in-memory per-context-key remote config cache — stateful,
    // one instance SDK-wide.
    private var remoteConfigManagerInstance: RemoteConfigManager?


    // Holds the transaction reports dedup gate and the update streams —
    // stateful, one instance SDK-wide.
    private var purchasesManagerInstance: PurchasesManager?

    // Owns the shared pending-properties storage: the remote config manager
    // flushes the same batch the facade fills — one instance SDK-wide.
    private var userPropertiesManagerInstance: UserPropertiesManagerInterface?

    // Consumed by both the facade and the purchases manager — one instance
    // SDK-wide, and a single user-change observer registration.
    private var entitlementsManagerInstance: EntitlementsManagerInterface?

    // A weakly held observer: a per-call instance would deregister itself the
    // moment the caller let go of it.
    private var deviceManagerInstance: DeviceManagerInterface?
    
    required init(apiKey: String, userDefaults: UserDefaults?, launchMode: Qonversion.LaunchMode = .analytics, baseURL: String? = nil, entitlementsCacheLifetime: Qonversion.EntitlementsCacheLifetime = .month, logLevel: Qonversion.LogLevel = .verbose, environment: Qonversion.Environment = .production) {
        let userDefaults: UserDefaults = userDefaults ?? UserDefaults.standard
        let internalConfig = InternalConfig(userId: "", launchMode: launchMode, entitlementsCacheLifetime: entitlementsCacheLifetime, logLevel: logLevel, environment: environment)
        self.miscAssembly = MiscAssembly(apiKey: apiKey, userDefaults: userDefaults, internalConfig: internalConfig)
        self.servicesAssembly = ServicesAssembly(apiKey: apiKey, miscAssembly: miscAssembly, baseURL: baseURL)
        self.miscAssembly.servicesAssembly = self.servicesAssembly

        // Resolves the anonymous user id (persisted or generated) into InternalConfig.
        _ = servicesAssembly.userService()

        // The previous SDK generation's offline purchase queue cannot be
        // replayed against v4; the unfinished-transaction sweep covers it.
        let legacyPurchasesQueueMigration = LegacyPurchasesQueueMigration()
        legacyPurchasesQueueMigration.run()
    }

    /// Registers every user-scoped cache with the user gate in a FIXED order,
    /// instead of letting it emerge from whichever manager happens to be built
    /// first. The order is the teardown order of a user switch: stop the
    /// outgoing queue, then the purchase bookkeeping, then the caches.
    func registerUserChangeObservers() {
        _ = miscAssembly.requestsStorage()
        _ = purchasesManager()
        _ = entitlementsManager()
        _ = productsManager()
        _ = remoteConfigManager()
        _ = deviceManager()
        _ = userPropertiesManager()
    }

    /// Resends requests that failed on transport in previous sessions —
    /// called once per initialization by the facade, after the graph is built.
    func replayStoredRequests() {
        servicesAssembly.requestProcessor().processStoredRequests()
    }
    
    func userManager() -> UserManagerInterface {
        if let userManagerInstance {
            return userManagerInstance
        }

        let userService: UserServiceInterface = servicesAssembly.userService()
        let localStorage: LocalStorageInterface = miscAssembly.localStorage()
        let userChangesNotifier: UserChangesNotifier = miscAssembly.userChangesNotifier()
        let logger: LoggerWrapper = miscAssembly.loggerWrapper()
        let userManager = UserManager(userService: userService, localStorage: localStorage, internalConfig: miscAssembly.internalConfig, userChangesNotifier: userChangesNotifier, logger: logger)
        userManagerInstance = userManager

        return userManager
    }

    func userPropertiesManager() -> UserPropertiesManagerInterface {
        if let userPropertiesManagerInstance {
            return userPropertiesManagerInstance
        }

        let requestProcessor: RequestProcessorInterface = servicesAssembly.requestProcessor()
        let delayCalculator: IncrementalDelayCalculator = miscAssembly.delayCalculator()
        let propertiesStorage: PropertiesStorage = miscAssembly.userPropertiesStorage()
        let logger: LoggerWrapper = miscAssembly.loggerWrapper()
        let userManager: UserManagerInterface = userManager()
        let deviceInfoCollector: DeviceInfoCollectorInterface = servicesAssembly.deviceInfoCollector()
        let integrationsInfoCollector = IntegrationsInfoCollector(deviceInfoCollector: deviceInfoCollector)
        let userPropertiesManager = UserPropertiesManager(requestProcessor: requestProcessor, propertiesStorage: propertiesStorage, delayCalculator: delayCalculator, userIdProvider: miscAssembly.internalConfig, userManager: userManager, integrationsInfoCollector: integrationsInfoCollector, logger: logger)
        userPropertiesManagerInstance = userPropertiesManager
        miscAssembly.userChangesNotifier().add(observer: userPropertiesManager)

        return userPropertiesManager
    }
    
    func deviceManager() -> DeviceManagerInterface {
        if let deviceManagerInstance {
            return deviceManagerInstance
        }

        let deviceInfoCollector: DeviceInfoCollectorInterface = servicesAssembly.deviceInfoCollector()
        let deviceService: DeviceServiceInterface = servicesAssembly.deviceService()
        let logger: LoggerWrapper = miscAssembly.loggerWrapper()
        let deviceManager = DeviceManager(deviceInfoCollector: deviceInfoCollector, deviceService: deviceService, logger: logger)
        deviceManagerInstance = deviceManager
        miscAssembly.userChangesNotifier().add(observer: deviceManager)

        return deviceManager
    }
    
    func productsManager() -> ProductsManagerInterface {
        return sharedProductsManager()
    }

    private func sharedProductsManager() -> ProductsManager {
        if let productsManagerInstance {
            return productsManagerInstance
        }

        let productsService: ProductsServiceInterface = servicesAssembly.productsService()
        let storeKitFacade: StoreKitFacade = servicesAssembly.storeKitFacade()
        let localStorage: LocalStorageInterface = miscAssembly.localStorage()
        let logger: LoggerWrapper = miscAssembly.loggerWrapper()
        let productsManager = ProductsManager(productsService: productsService, storeKitFacade: storeKitFacade, localStorage: localStorage, fallbackService: servicesAssembly.fallbackService(), logger: logger)
        
        let userChangesNotifier: UserChangesNotifier = miscAssembly.userChangesNotifier()

        productsManagerInstance = productsManager
        userChangesNotifier.add(observer: productsManager)

        return productsManager
    }
    
    func purchasesManager() -> PurchasesManagerInterface {
        if let purchasesManagerInstance {
            return purchasesManagerInstance
        }

        let purchasesService: PurchasesServiceInterface = servicesAssembly.purchasesService()
        let storeKitFacade: StoreKitFacade = servicesAssembly.storeKitFacade()
        let localStorage: LocalStorageInterface = miscAssembly.localStorage()
        let purchaseAssociationsStorage = PurchaseAssociationsStorage(localStorage: localStorage)
        let userManager: UserManagerInterface = userManager()
        let entitlementsManager: EntitlementsManagerInterface = entitlementsManager()
        let logger: LoggerWrapper = miscAssembly.loggerWrapper()
        let purchasesManager = PurchasesManager(
            purchasesService: purchasesService,
            storeKitFacade: storeKitFacade,
            userManager: userManager,
            entitlementsManager: entitlementsManager,
            userIdProvider: miscAssembly.internalConfig,
            launchModeProvider: miscAssembly.internalConfig,
            purchaseAssociationsStorage: purchaseAssociationsStorage,
            localStorage: localStorage,
            logger: logger
        )

        // Observed out-of-band transactions and promo intents flow into the
        // purchases manager.
        storeKitFacade.delegate = purchasesManager
        purchasesManagerInstance = purchasesManager
        miscAssembly.userChangesNotifier().add(observer: purchasesManager)

        return purchasesManager
    }

    func entitlementsManager() -> EntitlementsManagerInterface {
        if let entitlementsManagerInstance {
            return entitlementsManagerInstance
        }

        let entitlementsService: EntitlementsServiceInterface = servicesAssembly.entitlementsService()
        let storeKitFacade: StoreKitFacadeInterface = servicesAssembly.storeKitFacade()
        let productsDataSource: ProductsDataSource = sharedProductsManager()
        let userManager: UserManagerInterface = userManager()
        let localStorage: LocalStorageInterface = miscAssembly.localStorage()
        let cacheLifetime: TimeInterval = miscAssembly.internalConfig.entitlementsCacheLifetime.seconds
        let logger: LoggerWrapper = miscAssembly.loggerWrapper()
        let entitlementsManager = EntitlementsManager(
            entitlementsService: entitlementsService,
            storeKitFacade: storeKitFacade,
            productsDataSource: productsDataSource,
            userManager: userManager,
            userIdProvider: miscAssembly.internalConfig,
            localStorage: localStorage,
            cacheLifetime: cacheLifetime,
            logger: logger
        )

        let userChangesNotifier: UserChangesNotifier = miscAssembly.userChangesNotifier()
        entitlementsManagerInstance = entitlementsManager
        userChangesNotifier.add(observer: entitlementsManager)

        return entitlementsManager
    }

    func remoteConfigManager() -> RemoteConfigManagerInterface {
        if let remoteConfigManagerInstance {
            return remoteConfigManagerInstance
        }

        let remoteConfigService: RemoteConfigServiceInterface = servicesAssembly.remoteConfigService()
        let logger: LoggerWrapper = miscAssembly.loggerWrapper()
        let userManager: UserManagerInterface = userManager()
        let userPropertiesManager: UserPropertiesManagerInterface = userPropertiesManager()
        let fallbackService: FallbackServiceInterface = servicesAssembly.fallbackService()
        let remoteConfigManager = RemoteConfigManager(remoteConfigService: remoteConfigService, userManager: userManager, userPropertiesManager: userPropertiesManager, fallbackService: fallbackService, logger: logger)

        let userChangesNotifier: UserChangesNotifier = miscAssembly.userChangesNotifier()

        remoteConfigManagerInstance = remoteConfigManager
        userChangesNotifier.add(observer: remoteConfigManager)

        return remoteConfigManager
    }
}
