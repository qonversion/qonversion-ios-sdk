//
//  RequestsStorage.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 08.02.2024.
//

class RequestsStorage: RequestsStorageInterface {
    
    let userDefaults: UserDefaults
    let storeKey: String
    
    init(userDefaults: UserDefaults, storeKey: String) {
        self.userDefaults = userDefaults
        self.storeKey = storeKey
    }
    
    func store(requests: [URLRequest], key: String) {
        userDefaults.set(requests, forKey: storeKey)
    }
    
    func append(requests: [URLRequest], key: String) {
        var storedRequests: [URLRequest] = fetchRequests()
        storedRequests.append(contentsOf: requests)
        
        store(requests: storedRequests, key: storeKey)
    }
    
    func fetchRequests() -> [URLRequest] {
        let storedRequests: [URLRequest] = userDefaults.object(forKey: storeKey) as? [URLRequest] ?? []
        
        return storedRequests
    }
    
    func clean() {
        userDefaults.removeObject(forKey: storeKey)
    }
    
}
