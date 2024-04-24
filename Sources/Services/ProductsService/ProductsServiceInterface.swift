//
//  ProductsServiceInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 18.04.2024.
//

import Foundation

protocol ProductsServiceInterface {
    
    func products() async throws -> [Qonversion.Product]
    
    func offerings() async throws -> Qonversion.Offerings
    
}
