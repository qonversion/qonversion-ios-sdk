//
//  ContentView.swift
//  Watch Sample Watch App
//
//  Created by Suren Sarkisyan on 21.07.2025.
//  Copyright © 2025 Qonversion Inc. All rights reserved.
//

import SwiftUI
import Qonversion

struct ContentView: View {
  @StateObject private var qonversionManager = QonversionManager()
  
  var body: some View {
    NavigationView {
      ScrollView {
        VStack(spacing: 12) {
          // Header
          Text("Qonversion SDK")
            .font(.headline)
            .foregroundColor(.primary)
          
          // Connection status
          ConnectionStatusView(isConnected: qonversionManager.isConnected)
          
          // Main functions
          Group {
            Button("Check Entitlements") {
              qonversionManager.checkEntitlements()
            }
            .buttonStyle(.bordered)
            
            Button("Get Products") {
              qonversionManager.getProducts()
            }
            .buttonStyle(.bordered)
            
            Button("User Info") {
              qonversionManager.getUserInfo()
            }
            .buttonStyle(.bordered)
            
            Button("Remote Config") {
              qonversionManager.getRemoteConfig()
            }
            .buttonStyle(.bordered)
          }
          
          // Logs
          if !qonversionManager.logs.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
              Text("Logs:")
                .font(.caption)
                .foregroundColor(.secondary)
              
              ForEach(qonversionManager.logs, id: \.self) { log in
                Text(log)
                  .font(.caption2)
                  .foregroundColor(.secondary)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
          }
        }
        .padding()
      }
    }
  }
}

struct ConnectionStatusView: View {
  let isConnected: Bool
  
  var body: some View {
    HStack {
      Circle()
        .fill(isConnected ? Color.green : Color.red)
        .frame(width: 8, height: 8)
      
      Text(isConnected ? "Connected" : "Disconnected")
        .font(.caption)
        .foregroundColor(.secondary)
    }
  }
}

class QonversionManager: ObservableObject {
  @Published var isConnected = false
  @Published var logs: [String] = []
  
  init() {
    // Check connection status
    checkConnectionStatus()
  }
  
  private func checkConnectionStatus() {
    Qonversion.shared().userInfo { [weak self] user, error in
      DispatchQueue.main.async {
        if error == nil {
          self?.isConnected = true
          self?.addLog("✅ Successfully connected to Qonversion")
        } else {
          self?.isConnected = false
          self?.addLog("❌ Connection error: \(error?.localizedDescription ?? "Unknown error")")
        }
      }
    }
  }
  
  func checkEntitlements() {
    addLog("🔍 Checking entitlements...")
    
    Qonversion.shared().checkEntitlements { [weak self] entitlements, error in
      DispatchQueue.main.async {
        if let error = error {
          self?.addLog("❌ Error checking entitlements: \(error.localizedDescription)")
        } else {
          self?.addLog("✅ Found entitlements: \(entitlements.count)")
          
          for (key, entitlement) in entitlements {
            self?.addLog("  - \(key): \(entitlement.isActive ? "Active" : "Inactive")")
          }
        }
      }
    }
  }
  
  // Products are managed via Remote Configs — see migration guide:
  // https://documentation.qonversion.io/docs/migrate-offerings-to-remote-configs
  func getProducts() {
    addLog("📦 Getting products...")

    Qonversion.shared().products { [weak self] products, error in
      DispatchQueue.main.async {
        if let error = error {
          self?.addLog("❌ Error getting products: \(error.localizedDescription)")
        } else if !products.isEmpty {
          self?.addLog("✅ Found products: \(products.count)")

          for (id, product) in products {
            self?.addLog("  - \(id): \(product.prettyPrice)")
          }
        } else {
          self?.addLog("ℹ️ No products found")
        }
      }
    }
  }
  
  func getUserInfo() {
    addLog("👤 Getting user info...")
    
    Qonversion.shared().userInfo { [weak self] user, error in
      DispatchQueue.main.async {
        if let error = error {
          self?.addLog("❌ Error getting user info: \(error.localizedDescription)")
        } else if let user = user {
          self?.addLog("✅ User: \(user.qonversionId)")
          if let identityId = user.identityId {
            self?.addLog("  - Identity ID: \(identityId)")
          }
          if let version = user.originalAppVersion {
            self?.addLog("  - App version: \(version)")
          }
        }
      }
    }
  }
  
  func getRemoteConfig() {
    addLog("⚙️ Getting Remote Config...")
    
    Qonversion.shared().remoteConfig { [weak self] config, error in
      DispatchQueue.main.async {
        if let error = error {
          self?.addLog("❌ Error getting Remote Config: \(error.localizedDescription)")
        } else if let config = config {
          let count = config.payload?.count ?? 0
          self?.addLog("✅ Remote Config received: \(count) parameters")
          
          if let payload = config.payload {
            for (key, value) in payload {
              self?.addLog("  - \(key): \(value)")
            }
          }
        } else {
          self?.addLog("ℹ️ Remote Config is empty")
        }
      }
    }
  }
  
  private func addLog(_ message: String) {
    logs.append("[\(Date().formatted(date: .omitted, time: .standard))] \(message)")
    
    // Limit number of logs
    if logs.count > 20 {
      logs.removeFirst()
    }
  }
}

#Preview {
  ContentView()
}
