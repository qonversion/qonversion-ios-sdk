//
//  RemoteConfigsView.swift
//  Sample
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

import SwiftUI
import Qonversion

struct RemoteConfigsView: View {

    @EnvironmentObject var appState: AppState

    @State private var contextKeys = ""
    @State private var singleContextKey = ""
    @State private var experimentId = ""
    @State private var groupId = ""
    @State private var remoteConfigurationId = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                listSection
                singleSection
                experimentsSection
                remoteConfigurationSection
                results
            }
            .padding()
        }
        .navigationTitle("Remote Configs")
        .overlay {
            if appState.isLoading {
                LoadingOverlay()
            }
        }
        .messageAlerts()
    }

    private var listSection: some View {
        Card(title: "Remote Config List") {
            TextField("Context Keys (comma-separated)", text: $contextKeys)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)

            ActionButton(title: "Get Remote Config List", color: .blue) {
                Task {
                    let keys: [String]? = contextKeys.isEmpty
                        ? nil
                        : contextKeys.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    await appState.loadRemoteConfigList(contextKeys: keys)
                }
            }
        }
    }

    private var singleSection: some View {
        Card(title: "Single Remote Config") {
            TextField("Context Key (optional)", text: $singleContextKey)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)

            ActionButton(title: "Get Remote Config", color: .purple) {
                Task {
                    await appState.loadRemoteConfig(contextKey: singleContextKey.isEmpty ? nil : singleContextKey)
                }
            }
        }
    }

    private var experimentsSection: some View {
        Card(title: "Experiments") {
            TextField("Experiment ID", text: $experimentId)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)

            TextField("Group ID", text: $groupId)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)

            HStack(spacing: 12) {
                ActionButton(title: "Attach", color: .green) {
                    guard !experimentId.isEmpty, !groupId.isEmpty else {
                        appState.errorMessage = "Please enter both Experiment ID and Group ID"
                        return
                    }
                    Task { await appState.attachToExperiment(experimentId: experimentId, groupId: groupId) }
                }

                ActionButton(title: "Detach", color: .red) {
                    guard !experimentId.isEmpty else {
                        appState.errorMessage = "Please enter Experiment ID"
                        return
                    }
                    Task { await appState.detachFromExperiment(experimentId: experimentId) }
                }
            }
        }
    }

    /// New in this SDK: a user can be pinned to a remote configuration the same
    /// way they are pinned to an experiment group.
    private var remoteConfigurationSection: some View {
        Card(title: "Remote Configuration Assignment") {
            TextField("Remote Configuration ID", text: $remoteConfigurationId)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)

            HStack(spacing: 12) {
                ActionButton(title: "Attach", color: .green) {
                    guard !remoteConfigurationId.isEmpty else {
                        appState.errorMessage = "Please enter Remote Configuration ID"
                        return
                    }
                    Task { await appState.attachToRemoteConfiguration(id: remoteConfigurationId) }
                }

                ActionButton(title: "Detach", color: .red) {
                    guard !remoteConfigurationId.isEmpty else {
                        appState.errorMessage = "Please enter Remote Configuration ID"
                        return
                    }
                    Task { await appState.detachFromRemoteConfiguration(id: remoteConfigurationId) }
                }
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        if !appState.remoteConfigs.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Results")
                    .font(.headline)

                ForEach(Array(appState.remoteConfigs.enumerated()), id: \.offset) { _, config in
                    RemoteConfigCard(config: config)
                }
            }
        }
    }
}

// MARK: - Card

struct Card<Content: View>: View {

    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
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
                    Text("Context Key: \(config.source?.contextKey ?? "empty")")
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
                    DetailRow(label: "Source Name", value: config.source?.name ?? "N/A")
                    DetailRow(label: "Source Type", value: config.source?.type.rawValue ?? "N/A")
                    DetailRow(label: "Assignment", value: config.source?.assignmentType.rawValue ?? "N/A")
                    DetailRow(label: "Experiment ID", value: config.experiment?.identifier ?? "N/A")
                    DetailRow(label: "Experiment Name", value: config.experiment?.name ?? "N/A")

                    if let payload: [String: Any] = config.payload {
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

    private func payloadString(_ payload: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(payload),
              let data: Data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
              let string: String = String(data: data, encoding: .utf8) else {
            return "\(payload)"
        }

        return string
    }
}

#Preview {
    NavigationView {
        RemoteConfigsView()
            .environmentObject(AppState())
    }
}
