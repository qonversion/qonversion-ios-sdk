//
//  RemoteConfigsView.swift
//  Sample
//
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import SwiftUI
import Qonversion

struct RemoteConfigsView: View {
    @EnvironmentObject var appState: AppState
    
    @State private var contextKeys = ""
    @State private var singleContextKey = ""
    @State private var experimentId = ""
    @State private var groupId = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Remote Config List Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Remote Config List")
                        .font(.headline)
                    
                    TextField("Context Keys (comma-separated)", text: $contextKeys)
                        .textFieldStyle(.roundedBorder)
                    
                    ActionButton(title: "Get Remote Config List", color: .blue) {
                        Task {
                            let keys = contextKeys.isEmpty ? nil : contextKeys.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                            await appState.loadRemoteConfigList(contextKeys: keys)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Single Remote Config Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Single Remote Config")
                        .font(.headline)
                    
                    TextField("Context Key (optional)", text: $singleContextKey)
                        .textFieldStyle(.roundedBorder)
                    
                    ActionButton(title: "Get Remote Config", color: .purple) {
                        Task {
                            let key = singleContextKey.isEmpty ? nil : singleContextKey
                            await appState.loadRemoteConfig(contextKey: key)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Experiments Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Experiments")
                        .font(.headline)
                    
                    TextField("Experiment ID", text: $experimentId)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("Group ID", text: $groupId)
                        .textFieldStyle(.roundedBorder)
                    
                    HStack(spacing: 12) {
                        ActionButton(title: "Attach", color: .green) {
                            guard !experimentId.isEmpty, !groupId.isEmpty else {
                                appState.errorMessage = "Please enter both Experiment ID and Group ID"
                                return
                            }
                            Task {
                                await appState.attachToExperiment(experimentId: experimentId, groupId: groupId)
                            }
                        }
                        
                        ActionButton(title: "Detach", color: .red) {
                            guard !experimentId.isEmpty else {
                                appState.errorMessage = "Please enter Experiment ID"
                                return
                            }
                            Task {
                                await appState.detachFromExperiment(experimentId: experimentId)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Remote Configs Results
                if let remoteConfigs = appState.remoteConfigs {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Results")
                            .font(.headline)
                        
                        ForEach(remoteConfigs.remoteConfigs, id: \.source.identifier) { config in
                            RemoteConfigCard(config: config)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Remote Configs")
        .overlay {
            if appState.isLoading {
                LoadingOverlay()
            }
        }
        .alert("Error", isPresented: .constant(appState.errorMessage != nil)) {
            Button("OK") { appState.clearMessages() }
        } message: {
            Text(appState.errorMessage ?? "")
        }
        .alert("Success", isPresented: .constant(appState.successMessage != nil)) {
            Button("OK") { appState.clearMessages() }
        } message: {
            Text(appState.successMessage ?? "")
        }
    }
}

// MARK: - Remote Config Card
struct RemoteConfigCard: View {
    let config: Qonversion.RemoteConfig
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack {
                    Text("Context Key: \(config.source.contextKey ?? "empty")")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }
            
            if isExpanded {
                Divider()
                
                VStack(alignment: .leading, spacing: 4) {
                    DetailRow(label: "Source Name", value: config.source.name)
                    DetailRow(label: "Source Type", value: sourceTypeString(config.source.type))
                    DetailRow(label: "Experiment ID", value: config.experiment?.identifier ?? "N/A")
                    DetailRow(label: "Experiment Name", value: config.experiment?.name ?? "N/A")
                    
                    if let payload = config.payload as NSDictionary? {
                        Text("Payload:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                        
                        Text(payloadString(payload))
                            .font(.caption)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemBackground))
                            .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray5))
        .cornerRadius(12)
    }
    
    private func sourceTypeString(_ type: Qonversion.RemoteConfigurationSourceType) -> String {
        switch type {
        case .unknown:
            return "Unknown"
        case .experimentTreatmentGroup:
            return "Experiment Treatment Group"
        case .experimentControlGroup:
            return "Experiment Control Group"
        case .remoteConfiguration:
            return "Remote Configuration"
        @unknown default:
            return "Unknown"
        }
    }
    
    private func payloadString(_ payload: NSDictionary) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "\(payload)"
    }
}

#Preview {
    NavigationView {
        RemoteConfigsView()
            .environmentObject(AppState())
    }
}
