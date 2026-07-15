//
//  NoCodesView.swift
//  Sample
//
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import SwiftUI
import Qonversion

struct NoCodesView: View {
    @EnvironmentObject var appState: AppState
    
    @State private var contextKey = "kamo_test"
    @State private var selectedPresentationStyle: NoCodesPresentationStyleOption = .fullScreen
    @State private var animated = true
    @State private var listenerSet = false
    @State private var customizationDelegateSet = false
    @State private var customVariableName = ""
    @State private var customVariableValue = ""
    @State private var customVariablesDelegateSet = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Show Screen Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Show Screen")
                        .font(.headline)
                    
                    TextField("Context Key", text: $contextKey)
                        .textFieldStyle(.roundedBorder)
                    
                    ActionButton(title: "Show No-Code Screen", color: .blue) {
                        NoCodes.shared.showScreen(withContextKey: contextKey)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Load Before Present Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Load Before Present")
                        .font(.headline)

                    Text("Ask-first: load the screen, then present it or show your own fallback.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ActionButton(title: "Load, Then Present or Fallback", color: .indigo) {
                        loadBeforePresent()
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Presentation Config Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Presentation Config")
                        .font(.headline)
                    
                    Picker("Presentation Style", selection: $selectedPresentationStyle) {
                        ForEach(NoCodesPresentationStyleOption.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Toggle("Animated", isOn: $animated)
                    
                    ActionButton(title: "Set Screen Customization Delegate", color: .purple) {
                        setScreenCustomizationDelegate()
                    }
                    
                    if customizationDelegateSet {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Customization delegate active (\(selectedPresentationStyle.displayName))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Listener Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Listener")
                        .font(.headline)
                    
                    if listenerSet {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("No-Codes listener is active")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    ActionButton(title: "Set Listener", color: .green) {
                        setNoCodesListener()
                    }
                    .disabled(listenerSet)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Custom Variables Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Custom Variables")
                        .font(.headline)

                    TextField("Variable Name", text: $customVariableName)
                        .textFieldStyle(.roundedBorder)
                    TextField("Variable Value", text: $customVariableValue)
                        .textFieldStyle(.roundedBorder)

                    ActionButton(title: "Add Variable", color: .orange) {
                        guard !customVariableName.isEmpty else { return }
                        NoCodesCustomVariablesHandler.shared.variables[customVariableName] = customVariableValue
                        appState.successMessage = "Variable '\(customVariableName)' = '\(customVariableValue)' added"
                        customVariableName = ""
                        customVariableValue = ""
                    }

                    ActionButton(title: "Set Custom Variables Delegate", color: .orange) {
                        NoCodes.shared.set(customVariablesDelegate: NoCodesCustomVariablesHandler.shared)
                        customVariablesDelegateSet = true
                        appState.successMessage = "Custom variables delegate set!"
                    }

                    if customVariablesDelegateSet {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Custom variables delegate active (\(NoCodesCustomVariablesHandler.shared.variables.count) vars)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if !NoCodesCustomVariablesHandler.shared.variables.isEmpty {
                        ForEach(Array(NoCodesCustomVariablesHandler.shared.variables.keys.sorted()), id: \.self) { key in
                            HStack {
                                Text("\(key) = \(NoCodesCustomVariablesHandler.shared.variables[key] ?? "")")
                                    .font(.caption)
                                Spacer()
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Close Button
                ActionButton(title: "Close No-Code Screen", color: .red) {
                    NoCodes.shared.close()
                    appState.successMessage = "No-Codes screen closed!"
                }
                .padding(.horizontal)
                
                // Events Log
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("No-Codes Events")
                            .font(.headline)
                        Spacer()
                        Button("Clear") {
                            appState.noCodesEvents.removeAll()
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                    }
                    
                    if appState.noCodesEvents.isEmpty {
                        Text("No events yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(Array(appState.noCodesEvents.enumerated()), id: \.offset) { index, event in
                            HStack {
                                Text("\(index + 1).")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(event)
                                    .font(.caption)
                                Spacer()
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            .padding()
        }
        .navigationTitle("No-Codes")
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
    
    private func setNoCodesListener() {
        NoCodes.shared.set(delegate: NoCodesListenerHandler.shared)
        NoCodesListenerHandler.shared.appState = appState
        listenerSet = true
        appState.successMessage = "No-Codes listener set!"
    }
    
    private func setScreenCustomizationDelegate() {
        let handler = NoCodesCustomizationHandler.shared
        handler.presentationStyle = selectedPresentationStyle.nativeStyle
        handler.animated = animated
        NoCodes.shared.set(screenCustomizationDelegate: handler)
        customizationDelegateSet = true
        appState.successMessage = "Screen customization delegate set with \(selectedPresentationStyle.displayName) style!"
    }

    private func loadBeforePresent() {
        let key = contextKey
        Task { @MainActor in
            do {
                // Gate on real availability before anything is presented.
                let screen = try await NoCodes.shared.loadScreen(withContextKey: key)
                appState.addNoCodesEvent("Screen loaded (id: \(screen.id)), presenting from warm cache")

                // The loaded entity carries the typed default variables configured in the
                // builder — authored custom variables and product slots — readable by key
                // (e.g. screen.defaultVariable(forKey: "show_trial")) before presenting.
                let variables = screen.defaultVariables
                    .map { "\($0.kind.rawValue) \($0.key) = \(formatVariableValue($0.value))" }
                    .joined(separator: ", ")
                appState.addNoCodesEvent("Default variables: [\(variables)]")

                NoCodes.shared.showScreen(withContextKey: key)
            } catch {
                // The SDK skeleton never appeared, so we can show our own fallback UI instead.
                let type = (error as? NoCodesError)?.type
                appState.errorMessage = "Load failed (\(String(describing: type))), showing app fallback instead of the No-Code screen."
            }
        }
    }

    private func formatVariableValue(_ value: NoCodesScreenVariableValue) -> String {
        switch value {
        case .bool(let boolValue): return String(boolValue)
        case .string(let stringValue): return "\"\(stringValue)\""
        case .number(let numberValue): return String(numberValue)
        case .none: return "null"
        }
    }
}

// MARK: - NoCodes Presentation Style Option
enum NoCodesPresentationStyleOption: String, CaseIterable {
    case push
    case popover
    case fullScreen
    
    var displayName: String {
        switch self {
        case .push: return "Push"
        case .popover: return "Popover"
        case .fullScreen: return "Full Screen"
        }
    }
    
    var nativeStyle: NoCodesPresentationStyle {
        switch self {
        case .push: return .push
        case .popover: return .popover
        case .fullScreen: return .fullScreen
        }
    }
}

// MARK: - NoCodes Customization Handler
class NoCodesCustomizationHandler: NoCodesScreenCustomizationDelegate {
    static let shared = NoCodesCustomizationHandler()
    
    var presentationStyle: NoCodesPresentationStyle = .fullScreen
    var animated: Bool = true
    
    func presentationConfigurationForScreen(contextKey: String) -> NoCodesPresentationConfiguration {
        return NoCodesPresentationConfiguration(animated: animated, presentationStyle: presentationStyle)
    }
    
    func presentationConfigurationForScreen(id: String) -> NoCodesPresentationConfiguration {
        return NoCodesPresentationConfiguration(animated: animated, presentationStyle: presentationStyle)
    }
    
    func viewForPopoverPresentation() -> UIView? {
        return nil
    }
}

// MARK: - NoCodes Listener Handler
class NoCodesListenerHandler: NoCodesDelegate {
    static let shared = NoCodesListenerHandler()
    weak var appState: AppState?
    
    func controllerForNavigation() -> UIViewController? {
        return nil
    }
    
    func noCodesHasShownScreen(id: String) {
        Task { @MainActor in
            appState?.addNoCodesEvent("Screen shown: \(id)")
        }
    }

    func noCodesStartsExecuting(action: NoCodesAction) {
        Task { @MainActor in
            appState?.addNoCodesEvent("Action started: \(actionTypeString(action.type))")
        }
    }
    
    func noCodesFailedToExecute(action: NoCodesAction, error: Error?) {
        Task { @MainActor in
            let errorMessage = error?.localizedDescription ?? "Unknown error"
            appState?.addNoCodesEvent("Action failed: \(actionTypeString(action.type)) - \(errorMessage)")
        }
    }
    
    func noCodesFinishedExecuting(action: NoCodesAction) {
        Task { @MainActor in
            appState?.addNoCodesEvent("Action finished: \(actionTypeString(action.type))")
        }
    }
    
    func noCodesFinished() {
        Task { @MainActor in
            appState?.addNoCodesEvent("Flow finished")
        }
    }
    
    func noCodesFailedToLoadScreen(error: Error?) {
        Task { @MainActor in
            let errorMessage = error?.localizedDescription ?? "Unknown error"
            appState?.addNoCodesEvent("Screen failed to load: \(errorMessage)")
        }
    }
    
    private func actionTypeString(_ type: NoCodesActionType) -> String {
        switch type {
        case .url:
            return "URL"
        case .deeplink:
            return "Deeplink"
        case .close:
            return "Close"
        case .closeAll:
            return "Close All"
        case .purchase:
            return "Purchase"
        case .restore:
            return "Restore"
        case .navigation:
            return "Navigation"
        case .loadProducts:
            return "Load Products"
        case .showScreen:
            return "Show Screen"
        case .redeemPromoCode:
            return "Redeem Promo Code"
        case .screenAnalytics:
            return "Screen Analytics"
        case .getContext:
            return "Get Context"
        case .unknown:
            return "Unknown"
        @unknown default:
            return "Unknown"
        }
    }
}

// MARK: - NoCodes Custom Variables Handler
class NoCodesCustomVariablesHandler: NoCodesCustomVariablesDelegate {
    static let shared = NoCodesCustomVariablesHandler()
    var variables: [String: String] = [:]

    func customVariables(for contextKey: String) -> [String: String] {
        print("Custom variables requested for context key: \(contextKey), returning: \(variables)")
        return variables
    }
}

#Preview {
    NavigationView {
        NoCodesView()
            .environmentObject(AppState())
    }
}
