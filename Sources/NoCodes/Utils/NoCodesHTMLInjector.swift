//
//  NoCodesHTMLInjector.swift
//  NoCodes
//
//  Created by Suren Sarkisyan on 12.03.2026.
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

import Foundation

protocol NoCodesHTMLInjectorInterface: Sendable {
  func injectCustomLocale(into html: String, locale: String?) -> String
  func injectTheme(into html: String, theme: NoCodesTheme) -> String
}

final class NoCodesHTMLInjector: NoCodesHTMLInjectorInterface, Sendable {

  func injectCustomLocale(into html: String, locale: String?) -> String {
    guard let locale = locale else {
      return html
    }

    let localeLiteral: String = jsStringLiteral(from: locale)
    let localeScript: String = "<script>window.noCodesCustomLocale = \(localeLiteral);</script>"
    return injectAfterHead(script: localeScript, into: html)
  }

  func injectTheme(into html: String, theme: NoCodesTheme) -> String {
    let themeLiteral: String = jsStringLiteral(from: theme.rawValue)
    let themeScript: String = "<script>window.noCodesTheme = \(themeLiteral);</script>"
    return injectAfterHead(script: themeScript, into: html)
  }

  // MARK: - Private

  /// Renders `value` as a JavaScript string literal, quotes included, that is
  /// safe to drop into a `<script>` body.
  ///
  /// The values are caller and server controlled, and the web view they land in
  /// owns the purchase bridge, so interpolating them raw turns a stray quote or
  /// a `</script>` into code execution. JSON string syntax is a subset of the
  /// JavaScript one, so the encoder does the quoting; what it deliberately
  /// leaves alone are the characters that mean something to the *HTML* parser
  /// wrapping the script, plus the two line separators that are illegal raw in
  /// a JavaScript literal, so those are escaped afterwards. Every replacement
  /// is a unicode escape, so the value still decodes to the original text.
  private func jsStringLiteral(from value: String) -> String {
    let emptyLiteral: String = "\"\""
    // Wrapped in an array because a bare string is not a valid top level JSON
    // object on every platform version the SDK supports.
    guard let data: Data = try? JSONSerialization.data(withJSONObject: [value], options: []),
          let json: String = String(data: data, encoding: .utf8),
          json.count > 2
    else {
      return emptyLiteral
    }

    let literal: String = String(json.dropFirst().dropLast())

    return literal
      .replacingOccurrences(of: "<", with: "\\u003C")
      .replacingOccurrences(of: ">", with: "\\u003E")
      .replacingOccurrences(of: "&", with: "\\u0026")
      .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
      .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
  }

  private func injectAfterHead(script: String, into html: String) -> String {
    if let headRange = html.range(of: "<head>", options: .caseInsensitive) {
      var modifiedHtml = html
      modifiedHtml.insert(contentsOf: script, at: headRange.upperBound)
      return modifiedHtml
    } else {
      return script + html
    }
  }
}
