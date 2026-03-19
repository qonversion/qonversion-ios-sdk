//
//  NoCodesHTMLInjector.swift
//  NoCodes
//
//  Created by Suren Sarkisyan on 12.03.2026.
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

import Foundation

#if os(iOS)

protocol NoCodesHTMLInjectorInterface {
  func injectCustomLocale(into html: String, locale: String?) -> String
  func injectTheme(into html: String, theme: NoCodesTheme) -> String
}

final class NoCodesHTMLInjector: NoCodesHTMLInjectorInterface {

  func injectCustomLocale(into html: String, locale: String?) -> String {
    guard let locale = locale else {
      return html
    }

    let localeScript = "<script>window.noCodesCustomLocale = \"\(locale)\";</script>"
    return injectAfterHead(script: localeScript, into: html)
  }

  func injectTheme(into html: String, theme: NoCodesTheme) -> String {
    let themeScript = "<script>window.noCodesTheme = \"\(theme.rawValue)\";</script>"
    return injectAfterHead(script: themeScript, into: html)
  }

  // MARK: - Private

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

#endif
