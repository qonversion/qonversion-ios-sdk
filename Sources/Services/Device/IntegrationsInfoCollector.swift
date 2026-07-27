//
//  IntegrationsInfoCollector.swift
//  Qonversion
//

import Foundation

protocol IntegrationsInfoCollectorInterface: Sendable {

    /// The Adjust adid, when the Adjust SDK is integrated into the host app.
    /// Async because Adjust 5 exposes the id through a completion handler.
    func adjustUserId(completion: @escaping @Sendable (String?) -> Void)

    /// The AppsFlyer UID, when the AppsFlyer SDK is integrated.
    func appsFlyerUserId() -> String?

    /// The Facebook anonymous id — only meaningful without an IDFA, when it
    /// is the sole way to attribute the install.
    func facebookAnonymousId() -> String?
}

/// Reads attribution ids of third-party SDKs the host app may have integrated.
/// The SDKs are not linked — the ids are resolved through the Objective-C
/// runtime by class name, exactly like the production SDK does; an absent SDK
/// resolves to nil.
final class IntegrationsInfoCollector: IntegrationsInfoCollectorInterface {

    private let deviceInfoCollector: DeviceInfoCollectorInterface

    init(deviceInfoCollector: DeviceInfoCollectorInterface) {
        self.deviceInfoCollector = deviceInfoCollector
    }

    func adjustUserId(completion: @escaping @Sendable (String?) -> Void) {
        guard let adjustClass: AnyClass = NSClassFromString("Adjust") else {
            return completion(nil)
        }
        let adjust: AnyObject = adjustClass as AnyObject

        // Adjust 4 answers synchronously, Adjust 5 only through a completion.
        let syncSelector: Selector = NSSelectorFromString("adid")
        let asyncSelector: Selector = NSSelectorFromString("adidWithCompletionHandler:")
        if adjust.responds(to: syncSelector) {
            let adid: String? = adjust.perform(syncSelector)?.takeUnretainedValue() as? String
            completion(adid)
        } else if adjust.responds(to: asyncSelector) {
            let handler: @convention(block) @Sendable (String?) -> Void = { adid in
                completion(adid)
            }
            _ = adjust.perform(asyncSelector, with: handler)
        } else {
            completion(nil)
        }
    }

    func appsFlyerUserId() -> String? {
        // AppsFlyer 5 / AppsFlyer 6 entry points.
        let entryPoints: [(className: String, sharedSelector: String)] = [
            ("AppsFlyerTracker", "sharedTracker"),
            ("AppsFlyerLib", "shared"),
        ]
        let uidSelector: Selector = NSSelectorFromString("getAppsFlyerUID")

        for entryPoint in entryPoints {
            guard let trackerClass: AnyClass = NSClassFromString(entryPoint.className) else { continue }
            let tracker: AnyObject = trackerClass as AnyObject
            let sharedSelector: Selector = NSSelectorFromString(entryPoint.sharedSelector)
            guard tracker.responds(to: sharedSelector),
                  let shared: AnyObject = tracker.perform(sharedSelector)?.takeUnretainedValue() else { continue }
            guard shared.responds(to: uidSelector),
                  let uid: String = shared.perform(uidSelector)?.takeUnretainedValue() as? String else { continue }

            return uid
        }

        return nil
    }

    func facebookAnonymousId() -> String? {
        // With a usable IDFA available Facebook attributes by it — the
        // anonymous id only matters without one, whether because tracking was
        // denied or because the host app does not link the framework at all.
        // The collector already reports the unauthorised identifier as nil, so
        // a non-nil value here is always a real one.
        if deviceInfoCollector.advertisingId() != nil {
            return nil
        }

        let anonymousIdSelector: Selector = NSSelectorFromString("anonymousID")
        for className in ["FBSDKAppEvents", "FBSDKBasicUtility"] {
            guard let fbClass: AnyClass = NSClassFromString(className) else { continue }
            let fb: AnyObject = fbClass as AnyObject
            guard fb.responds(to: anonymousIdSelector),
                  let anonymousId: String = fb.perform(anonymousIdSelector)?.takeUnretainedValue() as? String else { continue }

            return anonymousId
        }

        return nil
    }
}
