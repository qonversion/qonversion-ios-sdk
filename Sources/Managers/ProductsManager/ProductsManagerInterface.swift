//
//  ProductsManagerInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 22.04.2024.
//

import Foundation

protocol ProductsManagerInterface {
    
    func products() async throws -> [Qonversion.Product]
    
    func offerings() async throws -> Qonversion.Offerings
    
}
