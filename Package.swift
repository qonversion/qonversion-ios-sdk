// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let sources: [String] = ["Qonversion/Automations/Constants",
                         "Qonversion/Automations/Main",
                         "Qonversion/Automations/Main/QONAutomationsActionsHandler",
                         "Qonversion/Automations/Main/QONAutomationsFlowAssembly",
                         "Qonversion/Automations/Main/QONAutomationsFlowCoordinator",
                         "Qonversion/Automations/Mappers",
                         "Qonversion/Automations/Mappers/QONAutomationsEventsMapper",
                         "Qonversion/Automations/Mappers/QONAutomationsMapper",
                         "Qonversion/Automations/Models",
                         "Qonversion/Automations/Models/QONAutomationsScreen",
                         "Qonversion/Automations/Models/QONMacrosProcess",
                         "Qonversion/Automations/Models/QONUserActionPoint",
                         "Qonversion/Automations/Services",
                         "Qonversion/Automations/Services/QONAutomationsScreenProcessor",
                         "Qonversion/Automations/Services/QONAutomationsService",
                         "Qonversion/Automations/Views",
                         "Qonversion/Automations/Views/QONAutomationsNavigationController",
                         "Qonversion/Automations/Views/QONAutomationsViewController",
                         "Qonversion/Automations/Services/QONNotificationsService",
                         "Qonversion/IDFA",
                         "Qonversion/Public",
                         "Qonversion/Qonversion/Assemblies",
                         "Qonversion/Qonversion/Assemblies/QNServicesAssembly",
                         "Qonversion/Qonversion/Constants",
                         "Qonversion/Qonversion/Constants/QNAPIConstants",
                         "Qonversion/Qonversion/Constants/QNInternalConstants",
                         "Qonversion/Qonversion/Core",
                         "Qonversion/Qonversion/Core/QNInMemoryStorage",
                         "Qonversion/Qonversion/Core/QNKeychain",
                         "Qonversion/Qonversion/Core/QNKeychainStorage",
                         "Qonversion/Qonversion/Core/QNKeyedArchiver",
                         "Qonversion/Qonversion/Core/QNRequestBuilder",
                         "Qonversion/Qonversion/Core/QNRequestSerializer",
                         "Qonversion/Qonversion/Core/QNUserDefaultsStorage",
                         "Qonversion/Qonversion/Main",
                         "Qonversion/Qonversion/Main/QNAttributionManager",
                         "Qonversion/Qonversion/Main/QNIdentityManager",
                         "Qonversion/Qonversion/Main/QNProductCenterManager",
                         "Qonversion/Qonversion/Main/QNUserPropertiesManager",
                         "Qonversion/Qonversion/Main/QONRemoteConfigManager",
                         "Qonversion/Qonversion/Mappers",
                         "Qonversion/Qonversion/Mappers/QNErrorsMapper",
                         "Qonversion/Qonversion/Mappers/QNMapper",
                         "Qonversion/Qonversion/Mappers/QNUserInfoMapper",
                         "Qonversion/Qonversion/Mappers/QONRemoteConfigMapper",
                         "Qonversion/Qonversion/Mappers/QONUserPropertiesMapper",
                         "Qonversion/Qonversion/Models",
                         "Qonversion/Qonversion/Models/Protected",
                         "Qonversion/Qonversion/Models/QONStoreKit2PurchaseModel",
                         "Qonversion/Qonversion/Models/QNMapperObject",
                         "Qonversion/Qonversion/Services",
                         "Qonversion/Qonversion/Services/QNAPIClient",
                         "Qonversion/Qonversion/Services/QNIdentityService",
                         "Qonversion/Qonversion/Services/QNStoreKitService",
                         "Qonversion/Qonversion/Services/QNUserInfoService",
                         "Qonversion/Qonversion/Services/QONRemoteConfigService",
                         "Qonversion/Qonversion/Services/QONExceptionManager",
                         "Qonversion/Qonversion/Utils",
                         "Qonversion/Qonversion/Utils/QNDevice",
                         "Qonversion/Qonversion/Utils/QNProperties",
                         "Qonversion/Qonversion/Utils/QNRateLimiter",
                         "Qonversion/Qonversion/Utils/QNUserInfo",
                         "Qonversion/Qonversion/Utils/QNUtils"]

let package = Package(
    name: "Qonversion",
    platforms: [
        .iOS(.v9), .watchOS("6.2"), .macOS(.v10_12), .tvOS(.v9)
    ],
    products: [
        .library(
            name: "Qonversion",
            targets: ["Qonversion", "QonversionSwift"])
    ],
    targets: [.target(
                name: "Qonversion",
                path: "Sources",
                exclude: ["Swift"],
                resources: [
                    .copy("../Sources/PrivacyInfo.xcprivacy")
                ],
                publicHeadersPath: "Qonversion/Public",
                cSettings: sources.map { .headerSearchPath($0) }),
              .target(
                name: "QonversionSwift",
                dependencies: ["Qonversion"],
                path: "Sources",
                exclude: ["Qonversion"],
                resources: [
                    .copy("../Sources/PrivacyInfo.xcprivacy")
                ])]
)
