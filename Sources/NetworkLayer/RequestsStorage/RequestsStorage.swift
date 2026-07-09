//
//  RequestsStorage.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 08.02.2024.
//

import Foundation

// @unchecked: lock-guarded over thread-safe UserDefaults.
class RequestsStorage: RequestsStorageInterface, @unchecked Sendable {

    /// Bounds UserDefaults growth; the oldest requests are dropped first.
    static let maxStoredRequests = 50

    let userDefaults: UserDefaults
    let storeKey: String

    // append (live failures) and remove (replay) run concurrently; the
    // fetch-mutate-persist sequence must be atomic to avoid lost updates.
    private let lock = NSLock()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults, storeKey: String) {
        self.userDefaults = userDefaults
        self.storeKey = storeKey
    }

    func append(_ request: StoredRequest) {
        lock.lock()
        defer { lock.unlock() }

        var requests: [StoredRequest] = fetchStoredRequests()
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
        lock.lock()
        defer { lock.unlock() }

        var requests: [StoredRequest] = fetchStoredRequests()
        guard let index = requests.firstIndex(of: request) else { return }

        requests.remove(at: index)
        persist(requests)
    }

    private func persist(_ requests: [StoredRequest]) {
        guard let data = try? encoder.encode(requests) else { return }
        userDefaults.set(data, forKey: storeKey)
    }

    func fetchRequests() -> [StoredRequest] {
        lock.lock()
        defer { lock.unlock() }

        return fetchStoredRequests()
    }

    func clean() {
        lock.lock()
        defer { lock.unlock() }

        userDefaults.removeObject(forKey: storeKey)
    }

    private func fetchStoredRequests() -> [StoredRequest] {
        guard let data = userDefaults.data(forKey: storeKey),
              let requests = try? decoder.decode([StoredRequest].self, from: data) else {
            return []
        }

        return requests
    }
}
