//
//  UserPropertiesManagerInterface.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 23.02.2024.
//

import Foundation

protocol UserPropertiesManagerInterface {
  
    func userProperties(for userId: String) async throws -> UserProperties
}
