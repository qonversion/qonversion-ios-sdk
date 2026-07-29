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

    private var _cleanGeneration = 0

    var cleanGeneration: Int {
        lock.lock()
        defer { lock.unlock() }
        return _cleanGeneration
    }

    init(userDefaults: UserDefaults, storeKey: String) {
        self.userDefaults = userDefaults
        self.storeKey = storeKey
    }

    func append(_ request: StoredRequest, ifGenerationIs generation: Int) {
        lock.lock()
        defer { lock.unlock() }

        guard _cleanGeneration == generation else { return }

        var requests: [StoredRequest] = fetchStoredRequests()
        if let dedupKey = request.dedupKey, let index = requests.firstIndex(where: { $0.dedupKey == dedupKey }) {
            // Device and attribution keys identify the RESOURCE, not the
            // payload, so a second append under the same key is usually a
            // fresher state (an IDFA collected after the first failure) that
            // must supersede the queued one — in place, to keep the send order.
            // An identical payload is a true duplicate: keep the queued entry,
            // whose attempt count is the real one.
            if requests[index].body != request.body {
                requests[index] = request
                persist(requests)
            }

            return
        }

        requests.append(request)
        if requests.count > Self.maxStoredRequests {
            requests.removeFirst(requests.count - Self.maxStoredRequests)
        }

        persist(requests)
    }

    func removeAll(ifGenerationIs generation: Int, where shouldRemove: @Sendable (StoredRequest) -> Bool) {
        lock.lock()
        defer { lock.unlock() }

        guard _cleanGeneration == generation else { return }

        var requests: [StoredRequest] = fetchStoredRequests()
        requests.removeAll(where: shouldRemove)
        persist(requests)
    }

    func replace(_ request: StoredRequest, with replacement: StoredRequest, ifGenerationIs generation: Int) {
        lock.lock()
        defer { lock.unlock() }

        guard _cleanGeneration == generation else { return }

        var requests: [StoredRequest] = fetchStoredRequests()
        guard let index = requests.firstIndex(of: request) else { return }

        requests[index] = replacement
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

        _cleanGeneration += 1
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
