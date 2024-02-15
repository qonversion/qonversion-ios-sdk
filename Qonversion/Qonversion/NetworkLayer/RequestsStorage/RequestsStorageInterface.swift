//
//  RequestsStorageInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 08.02.2024.
//

protocol RequestsStorageInterface {
    
    func store(requests: [URLRequest], key: String)
    
    func enrichStoredRequests(_ requests: [URLRequest], key: String)
    
    func fetchStoredRequests(for key: String) -> [URLRequest]
    
}
