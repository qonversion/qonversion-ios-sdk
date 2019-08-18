//
//  UserInfoTests.swift
//  QonversionTests
//
//  Created by Kostya on 16/08/2019.
//

import XCTest

fileprivate enum Constants {
    typealias Dict = [String: Any]
    
    static let dummyOverallData: [String: Any] = {
        let appContent: Dict = {
            return [
                "name": "Bundle.Name",
                "version": "1.0.0",
                "build": "12",
                "bundle": "Bundle.Id"
            ]
        }()
        return ["app": appContent]
    }()
}

class UserInfoTests: XCTestCase {
    
    func testOverallDataStructure() {
        // TODO:
    }
}
