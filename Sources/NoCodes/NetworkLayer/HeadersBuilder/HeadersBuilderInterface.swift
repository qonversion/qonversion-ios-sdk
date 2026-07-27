//
//  HeadersBuilderInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 07.02.2024.
//

import Foundation

protocol HeadersBuilderInterface {
    
    func addHeaders(to request: inout URLRequest)
}
