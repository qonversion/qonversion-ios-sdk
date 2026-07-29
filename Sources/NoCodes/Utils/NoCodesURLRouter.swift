//
//  NoCodesURLRouter.swift
//  NoCodes
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

import Foundation

/// How a URL carried by a screen action has to be opened.
enum NoCodesURLRoute: Equatable {

  /// An `http`/`https` address, which the in-app browser can show.
  case inAppBrowser(URL)

  /// A valid URL the in-app browser refuses — `mailto:`, `tel:`, `itms-apps:`
  /// and every other scheme — which only the system can open.
  case system(URL)

  /// Nothing openable, so the host hears the action failed.
  case unopenable
}

/// Decides how a screen's URL action has to be opened.
///
/// `SFSafariViewController` takes `http` and `https` only and raises an
/// Objective-C exception for anything else — one Swift cannot catch, so it
/// takes the host app down. `URL(string:)` accepts far more than that: every
/// custom scheme, and schemeless strings such as `www.example.com`, which it
/// reads as a relative path.
enum NoCodesURLRouter {

  private static let inAppBrowserSchemes: Set<String> = ["http", "https"]

  static func route(urlString: String?) -> NoCodesURLRoute {
    guard let urlString else { return .unopenable }

    let address: String = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !address.isEmpty, let url = URL(string: address) else { return .unopenable }
    guard let scheme: String = url.scheme?.lowercased() else { return webRoute(forSchemeless: address) }
    guard inAppBrowserSchemes.contains(scheme) else { return .system(url) }
    // An `http://` with nothing behind it is one of the URLs the in-app browser
    // raises on.
    guard let browsableURL: URL = browsableURL(from: url, scheme: scheme) else { return .unopenable }

    return .inAppBrowser(browsableURL)
  }

  /// A schemeless string is a builder authoring slip rather than a link
  /// somewhere else, so it is read as a web address instead of being dropped.
  private static func webRoute(forSchemeless address: String) -> NoCodesURLRoute {
    guard !address.contains(where: { $0.isWhitespace }), let url = URL(string: "https://\(address)") else { return .unopenable }
    guard let browsableURL: URL = browsableURL(from: url, scheme: "https") else { return .unopenable }

    return .inAppBrowser(browsableURL)
  }

  /// The in-app browser matches the scheme literally, so an `HTTP://` address
  /// would reach it as an unsupported one.
  private static func browsableURL(from url: URL, scheme: String) -> URL? {
    guard let host: String = url.host, !host.isEmpty else { return nil }
    guard url.scheme != scheme else { return url }
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

    components.scheme = scheme

    return components.url
  }
}
