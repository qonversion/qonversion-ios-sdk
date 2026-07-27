//
//  CrashReportFilter.swift
//  Qonversion
//

import Foundation

/// Decides whether an uncaught exception came out of the SDK.
///
/// The SDK reports its OWN crashes and nothing else: an app's exception is the
/// app's business, and shipping it to Qonversion would be both useless and a
/// privacy problem. The ObjC SDK made the same decision the same way — walk
/// `callStackSymbols`, pull the binary image name out of each frame, and look
/// for the SDK (QONExceptionManager.m:61-92).
///
/// Two shapes have to be recognized, because linkage changes what the frame
/// looks like:
///   * a dynamic framework / CocoaPods build gives the SDK its own image, so
///     the image name IS "Qonversion";
///   * an SPM static build folds the SDK into the host executable, so the
///     image name is the app's and only the symbol tells them apart.
///
/// Two deliberate differences from the ObjC implementation:
///   * the symbol markers are Swift's, not `-[QON` / `-[QN`: an SDK frame in a
///     Swift build mangles to `$s10Qonversion…`, where the module name is
///     length-prefixed, so the marker cannot match a frame that merely
///     mentions an SDK type in its signature. The ObjC prefixes are kept too
///     so an ObjC-era frame in a mixed stack still matches;
///   * the whole stack is scanned. ObjC returned NO the moment it saw an app
///     frame whose symbol did not match, which misses every SDK frame sitting
///     below an app frame — the common case, since the app is what calls in.
enum CrashReportFilter {

    /// The frames' own image name when the SDK is its own binary.
    static var sdkImageName: String { "Qonversion" }

    /// Symbol fragments that identify an SDK frame inside the host executable.
    ///
    /// The demangled form is deliberately NOT in this list. "Qonversion." also
    /// appears in the signature of any host frame that merely takes or returns
    /// an SDK type — `MyApp.Paywall.show(product: Qonversion.Product)` is the
    /// app's own frame, and matching it would ship the app's crashes to us.
    /// The mangled prefix cannot false-positive that way: `$s10Qonversion`
    /// means the frame's DECLARING module is Qonversion, module names being
    /// length-prefixed in Swift mangling. The two ObjC-era prefixes are kept
    /// for a mixed stack and are anchored to the start of a selector.
    static var sdkSymbolMarkers: [String] {
        return ["$s10Qonversion", "-[QON", "-[QN"]
    }

    /// nil when the exception is not the SDK's; otherwise how the SDK was
    /// linked, which the report carries so the stack can be symbolicated.
    static func linkage(ofCallStackSymbols symbols: [String], appExecutableName: String) -> CrashReport.Linkage? {
        var appFrameMatched = false

        for symbol in symbols {
            guard let imageName: String = imageName(ofFrame: symbol) else { continue }

            if imageName == sdkImageName {
                return .framework
            }
            if imageName == appExecutableName, containsSdkSymbol(symbol) {
                // Keep scanning: a later frame may still be an explicit
                // Qonversion image, which is the more precise answer.
                appFrameMatched = true
            }
        }

        return appFrameMatched ? .spm : nil
    }

    /// A frame looks like `2   Qonversion   0x0000000104 symbol + 42`: the
    /// index, then the binary image name. Same shape the ObjC regex
    /// (`\S+\s+(\S+)`) captured, without paying for a regex on a crash path.
    static func imageName(ofFrame frame: String) -> String? {
        let fields: [Substring] = frame.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 2 else { return nil }

        return String(fields[1])
    }

    static func containsSdkSymbol(_ frame: String) -> Bool {
        return sdkSymbolMarkers.contains { frame.contains($0) }
    }

    /// The host executable's name, which is what an SPM-linked SDK's frames
    /// carry as their image name.
    static func currentAppExecutableName() -> String {
        return Bundle.main.executablePath.map { ($0 as NSString).lastPathComponent } ?? ""
    }
}
