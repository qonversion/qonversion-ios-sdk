//
//  NoCodesJavaScript.swift
//  NoCodes
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

import Foundation

/// Builds the JavaScript the SDK hands to a screen's web view.
///
/// The values carried by that JavaScript come from the host app and from the
/// screen payload, and the web view they land in owns the purchase bridge, so
/// none of them may be interpolated raw.
enum NoCodesJavaScript {

  /// Renders `value` as a JavaScript string literal, quotes included.
  ///
  /// JSON string syntax is a subset of the JavaScript one, so the encoder does
  /// the quoting and the escaping of quotes, backslashes and control
  /// characters. What it deliberately leaves alone are the characters that mean
  /// something to an HTML parser, for the literals that end up inside a
  /// `<script>` element, and the two line separators that are illegal raw in a
  /// JavaScript literal, so those are escaped afterwards. Every replacement is a
  /// unicode escape, so the literal still evaluates to the original text.
  static func stringLiteral(from value: String) -> String {
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

  /// Builds the script that hands the host app's custom variables to the screen.
  ///
  /// One statement per variable, in a stable order so the same variables always
  /// produce the same script. Names are escaped as well as values: both come
  /// from the host app, and a single unescapable character in either used to be
  /// enough to make the whole script fail to parse, which set no variables at
  /// all rather than just the offending one.
  static func setCustomVariablesScript(for variables: [String: String]) -> String {
    let statements: [String] = variables.sorted { $0.key < $1.key }.map { name, value in
      let nameLiteral: String = stringLiteral(from: name)
      let valueLiteral: String = stringLiteral(from: value)

      return "window.noCodesSetVariable?.(\(nameLiteral), \(valueLiteral));"
    }

    return statements.joined(separator: "\n")
  }
}
