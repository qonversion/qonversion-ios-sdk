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
        if let dedupKey = request.dedupKey, requests.contains(where: { $0.dedupKey == dedupKey }) {
            return
        }

        requests.append(request)
        if requests.count > Self.maxStoredRequests {
            requests.removeFirst(requests.count - Self.maxStoredRequests)
        }

        persist(requests)
    }

    func remove(_ request: StoredRequest) {
        var requests: [StoredRequest] = fetchRequests()
        guard let index = requests.firstIndex(of: request) else { return }

        requests.remove(at: index)
        persist(requests)
    }

    private func persist(_ requests: [StoredRequest]) {
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
