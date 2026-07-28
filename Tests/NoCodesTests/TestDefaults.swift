//
//  TestDefaults.swift
//  NoCodesTests
//
//  An isolated UserDefaults suite per test, so nothing leaks into the
//  standard domain of the machine running the suite.
//

import Foundation

enum TestDefaults {

    static func makeIsolated(_ name: String = #function) -> UserDefaults {
        let suiteName: String = "io.qonversion.nocodes.tests." + name + "." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        return defaults
    }
}
