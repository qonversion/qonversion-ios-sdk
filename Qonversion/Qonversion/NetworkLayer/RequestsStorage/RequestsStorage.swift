//
//  RequestsStorage.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 08.02.2024.
//

class RequestsStorage: RequestsStorageInterface {
    
    let userDefaults: UserDefaults
    
    init(userDefaults: UserDefaults, storeRequestsKey: String) {
        self.userDefaults = userDefaults
    }
    
    func store(requests: [URLRequest], key: String) {
        userDefaults.set(requests, forKey: key)
    }
    
    func enrichStoredRequests(_ requests: [URLRequest], key: String) {
        var storedRequests: [URLRequest] = userDefaults.object(forKey: key) as? [URLRequest] ?? []
        storedRequests.append(contentsOf: requests)
        
        store(requests: storedRequests, key: key)
    }
    
    func fetchStoredRequests(for key: String) -> [URLRequest] {
        let storedRequests: [URLRequest] = userDefaults.object(forKey: key) as? [URLRequest] ?? []
        
        return storedRequests
    }
    
}
