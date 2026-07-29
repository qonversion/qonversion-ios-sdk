//
//  CrashReportFilter.swift
//  Qonversion
//

import Foundation

/// Decides whether an uncaught exception came out of the SDK, by walking
/// `callStackSymbols` for an SDK frame. An app's own exception is never
/// reported.
///
/// Two linkages have to be recognized: a framework build gives the SDK its own
/// image name, an SPM static build folds it into the host executable so only
/// the symbol tells them apart. The whole stack is scanned, because SDK frames
/// usually sit below the app frame that called in.
enum CrashReportFilter {

    /// The frames' own image names when the SDK is its own binary. NoCodes is
    /// a separate module and a separate framework product, and it holds every
    /// piece of UIKit code in the SDK — the likeliest source of an NSException
    /// anywhere in it.
    static var sdkImageNames: [String] {
        return ["Qonversion", "NoCodes"]
    }

    /// Mangled and ObjC-era prefixes only: the demangled `Qonversion.` and
    /// `NoCodes.` forms are deliberately absent, since they also appear in host
    /// frames that merely mention an SDK type in their signature.
    static var sdkSymbolMarkers: [String] {
        return ["$s10Qonversion", "$s7NoCodes", "-[QON", "-[QN"]
    }

    /// nil when the exception is not the SDK's; otherwise how the SDK was linked.
    static func linkage(ofCallStackSymbols symbols: [String], appExecutableName: String) -> CrashReport.Linkage? {
        var appFrameMatched = false

        for symbol in symbols {
            guard let imageName: String = imageName(ofFrame: symbol) else { continue }

            if sdkImageNames.contains(imageName) {
                return .framework
            }
            if imageName == appExecutableName, containsSdkSymbol(symbol) {
                // Keep scanning: an explicit Qonversion image is more precise.
                appFrameMatched = true
            }
        }

        return appFrameMatched ? .spm : nil
    }

    /// The token that opens the address column of a `backtrace_symbols` frame.
    private static let addressPrefix = "0x"

    /// A frame is `2   My App   0x0000000104 symbol + 42`. The image name is
    /// everything between the index and the address column, not field 1 — an
    /// executable name can contain spaces.
    static func imageName(ofFrame frame: String) -> String? {
        let fields: [Substring] = frame.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 2 else { return nil }

        guard let addressIndex: Int = fields.firstIndex(where: { $0.hasPrefix(addressPrefix) }) else {
            return String(fields[1])
        }
        // An address in field 1 means the frame carries no image name at all.
        guard addressIndex >= 2 else { return nil }

        return fields[1..<addressIndex].joined(separator: " ")
    }

    static func containsSdkSymbol(_ frame: String) -> Bool {
        return sdkSymbolMarkers.contains { frame.contains($0) }
    }

    /// The image name an SPM-linked SDK's frames carry.
    static func currentAppExecutableName() -> String {
        return Bundle.main.executablePath.map { ($0 as NSString).lastPathComponent } ?? ""
    }
}
