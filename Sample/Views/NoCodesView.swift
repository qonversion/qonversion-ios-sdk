//
//  NoCodesView.swift
//  Sample
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

import SwiftUI
import UIKit
import NoCodes

struct NoCodesView: View {

    @EnvironmentObject var appState: AppState

    @State private var contextKey = "main"
    @State private var selectedPresentationStyle: NoCodesPresentationStyleOption = .fullScreen
    @State private var animated = true
    @State private var customizationDelegateSet = false
    @State private var customVariableName = ""
    @State private var customVariableValue = ""
    @State private var customVariablesDelegateSet = false
    @State private var variables: [String: String] = [:]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                showScreenSection
                loadBeforePresentSection
                presentationSection
                customVariablesSection

                ActionButton(title: "Close No-Code Screen", color: .red) {
                    NoCodes.shared.close()
                    appState.addNoCodesEvent("Close requested")
                }

                eventsSection
            }
            .padding()
        }
        .navigationTitle("No-Codes")
        .messageAlerts()
        .task {
            // The delegate is set once for the screen's lifetime. It is a
            // single-slot delegate, so setting it per action would just
            // replace it with an identical one.
            NoCodesSampleListener.shared.appState = appState
            NoCodes.shared.set(delegate: NoCodesSampleListener.shared)
        }
    }

    private var showScreenSection: some View {
        Card(title: "Show Screen") {
            TextField("Context Key", text: $contextKey)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .disableAutocorrection(true)

            ActionButton(title: "Show No-Code Screen", color: .blue) {
                appState.addNoCodesEvent("Showing screen for '\(currentContextKey)'")
                NoCodes.shared.showScreen(withContextKey: currentContextKey)
            }
        }
    }

    private var loadBeforePresentSection: some View {
        Card(title: "Load Before Present") {
            Text("Ask-first: load the screen, then present it or show your own fallback. Nothing is presented by the load itself.")
                .font(.caption)
                .foregroundColor(.secondary)

            ActionButton(title: "Load, Then Present or Fallback", color: .indigo) {
                loadBeforePresent()
            }
        }
    }

    private var presentationSection: some View {
        Card(title: "Presentation Config") {
            Picker("Presentation Style", selection: $selectedPresentationStyle) {
                ForEach(NoCodesPresentationStyleOption.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Animated", isOn: $animated)

            ActionButton(title: "Apply Presentation Configuration", color: .purple) {
                let handler = NoCodesSampleCustomization.shared
                handler.presentationStyle = selectedPresentationStyle.nativeStyle
                handler.animated = animated
                NoCodes.shared.set(screenCustomizationDelegate: handler)
                customizationDelegateSet = true
                appState.addNoCodesEvent("Presentation set: \(selectedPresentationStyle.displayName), animated=\(animated)")
            }

            if customizationDelegateSet {
                ActiveBadge(text: "Customization delegate active (\(selectedPresentationStyle.displayName))")
            }
        }
    }

    private var customVariablesSection: some View {
        Card(title: "Custom Variables") {
            TextField("Variable Name", text: $customVariableName)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
            TextField("Variable Value", text: $customVariableValue)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)

            ActionButton(title: "Add Variable", color: .orange) {
                guard !customVariableName.isEmpty else {
                    appState.errorMessage = "Enter a variable name first"
                    return
                }
                variables[customVariableName] = customVariableValue
                NoCodesSampleCustomVariables.shared.variables = variables
                appState.addNoCodesEvent("Variable '\(customVariableName)' = '\(customVariableValue)' added")
                customVariableName = ""
                customVariableValue = ""
            }

            ActionButton(title: "Set Custom Variables Delegate", color: .orange) {
                NoCodesSampleCustomVariables.shared.variables = variables
                NoCodes.shared.set(customVariablesDelegate: NoCodesSampleCustomVariables.shared)
                customVariablesDelegateSet = true
                appState.addNoCodesEvent("Custom variables delegate set (\(variables.count) variables)")
            }

            if customVariablesDelegateSet {
                ActiveBadge(text: "Custom variables delegate active (\(variables.count) vars)")
            }

            ForEach(variables.keys.sorted(), id: \.self) { key in
                HStack {
                    Text("\(key) = \(variables[key] ?? "")")
                        .font(.caption)
                    Spacer()
                }
            }
        }
    }

    private var eventsSection: some View {
        Card(title: "No-Codes Events") {
            if appState.noCodesEvents.isEmpty {
                Text("No events yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(Array(appState.noCodesEvents.enumerated()), id: \.offset) { index, event in
                    HStack(alignment: .top) {
                        Text("\(index + 1).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(event)
                            .font(.caption)
                        Spacer()
                    }
                }

                Button("Clear") { appState.noCodesEvents.removeAll() }
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    private var currentContextKey: String {
        return contextKey.isEmpty ? "main" : contextKey
    }

    private func loadBeforePresent() {
        let key: String = currentContextKey
        Task { @MainActor in
            do {
                // Gate on real availability before anything is presented.
                let screen: NoCodesScreen = try await NoCodes.shared.loadScreen(withContextKey: key)
                appState.addNoCodesEvent("Screen loaded (id: \(screen.id)), presenting from the warm cache")

                // The loaded screen carries the typed default variables set in
                // the builder — readable by key before anything is presented.
                let variables: String = screen.defaultVariables
                    .map { "\($0.kind.rawValue) \($0.key) = \($0.value.stringValue)" }
                    .joined(separator: ", ")
                appState.addNoCodesEvent("Default variables: [\(variables)]")
                appState.addNoCodesEvent("Default selected product: \(screen.defaultSelectedProductId ?? "none")")

                NoCodes.shared.showScreen(withContextKey: key)
            } catch let error as NoCodesError {
                // No SDK screen ever appeared, so the app can show its own UI.
                appState.errorMessage = "Load failed (\(error.type)) — showing the app fallback instead of the No-Code screen."
            } catch {
                appState.errorMessage = "Load failed: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Active badge

struct ActiveBadge: View {

    let text: String

    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Presentation style

enum NoCodesPresentationStyleOption: String, CaseIterable {

    case fullScreen
    case push
    case popover

    var displayName: String {
        switch self {
        case .fullScreen:
            return "Full Screen"
        case .push:
            return "Push"
        case .popover:
            return "Popover"
        }
    }

    var nativeStyle: NoCodesPresentationStyle {
        switch self {
        case .fullScreen:
            return .fullScreen
        case .push:
            return .push
        case .popover:
            return .popover
        }
    }
}

// MARK: - Delegates

/// Reports the No-Codes flow lifecycle back into the sample UI.
@MainActor
final class NoCodesSampleListener: NoCodesDelegate {

    static let shared = NoCodesSampleListener()

    weak var appState: AppState?

    func controllerForNavigation() -> UIViewController? {
        // nil lets the SDK present from the topmost view controller.
        return nil
    }

    func noCodesHasShownScreen(id: String) {
        appState?.addNoCodesEvent("Screen shown: \(id)")
    }

    func noCodesStartsExecuting(action: NoCodesAction) {
        appState?.addNoCodesEvent("Action started: \(action.type)")
    }

    func noCodesFailedToExecute(action: NoCodesAction, error: Error?) {
        let description: String = error?.localizedDescription ?? "unknown error"
        appState?.addNoCodesEvent("Action failed: \(action.type) - \(description)")
    }

    func noCodesFinishedExecuting(action: NoCodesAction) {
        appState?.addNoCodesEvent("Action finished: \(action.type)")
    }

    func noCodesReceivedCustomAction(value: String) {
        appState?.addNoCodesEvent("Custom action received: '\(value)'")
    }

    func noCodesFinished() {
        appState?.addNoCodesEvent("Flow finished")
    }

    func noCodesFailedToLoadScreen(error: Error?) {
        let description: String = error?.localizedDescription ?? "unknown error"
        appState?.addNoCodesEvent("Screen failed to load: \(description)")
        NoCodes.shared.close()
    }
}

/// Chooses how the first screen of the chain is presented.
@MainActor
final class NoCodesSampleCustomization: NoCodesScreenCustomizationDelegate {

    static let shared = NoCodesSampleCustomization()

    var presentationStyle: NoCodesPresentationStyle = .fullScreen
    var animated: Bool = true

    func presentationConfigurationForScreen(contextKey: String) -> NoCodesPresentationConfiguration {
        return NoCodesPresentationConfiguration(animated: animated, presentationStyle: presentationStyle)
    }

    func viewForPopoverPresentation() -> UIView? {
        return nil
    }
}

/// Supplies the variables injected into the screen's JavaScript context.
@MainActor
final class NoCodesSampleCustomVariables: NoCodesCustomVariablesDelegate {

    static let shared = NoCodesSampleCustomVariables()

    var variables: [String: String] = [:]

    func customVariables(for contextKey: String) -> [String: String] {
        return variables
    }
}

#Preview {
    NavigationView {
        NoCodesView()
            .environmentObject(AppState())
    }
}
