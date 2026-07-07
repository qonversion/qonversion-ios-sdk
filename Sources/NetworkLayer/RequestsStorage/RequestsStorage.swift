//
//  RequestsStorage.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 08.02.2024.
//

import Foundation

class RequestsStorage: RequestsStorageInterface {

    /// Bounds UserDefaults growth; the oldest requests are dropped first.
    static let maxStoredRequests = 50

    let userDefaults: UserDefaults
    let storeKey: String

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults, storeKey: String) {
        self.userDefaults = userDefaults
        self.storeKey = storeKey
    }

    func append(_ request: StoredRequest) {
        var requests: [StoredRequest] = fetchRequests()
        requests.append(request)
        if requests.count > Self.maxStoredRequests {
            requests.removeFirst(requests.count - Self.maxStoredRequests)
        }

        guard let data = try? encoder.encode(requests) else { return }
        userDefaults.set(data, forKey: storeKey)
    }

    func fetchRequests() -> [StoredRequest] {
        guard let data = userDefaults.data(forKey: storeKey),
              let requests = try? decoder.decode([StoredRequest].self, from: data) else {
            return []
        }

        return requests
    }

    func clean() {
        userDefaults.removeObject(forKey: storeKey)
    }
}
