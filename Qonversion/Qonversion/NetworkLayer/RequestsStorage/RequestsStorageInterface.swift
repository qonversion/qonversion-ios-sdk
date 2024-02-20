//
//  RequestsStorageInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 08.02.2024.
//

protocol RequestsStorageInterface {
    
    func store(requests: [URLRequest], key: String)
    
    func append(requests: [URLRequest], key: String)
    
    func fetchRequests() -> [URLRequest]
    
    func clean()
    
}
