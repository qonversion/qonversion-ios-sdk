//
//  RequestsStorageInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 08.02.2024.
//

import Foundation

protocol RequestsStorageInterface {
    
    func store(requests: [URLRequest])
    
    func append(requests: [URLRequest])
    
    func fetchRequests() -> [URLRequest]
    
    func clean()
}
