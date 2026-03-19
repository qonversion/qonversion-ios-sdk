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
    
    @State private var contextKey = "con_test"
    @State private var selectedPresentationStyle: NoCodesPresentationStyleOption = .fullScreen
    @State private var animated = true
    @State private var listenerSet = false
    @State private var customizationDelegateSet = false
    
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

#Preview {
    NavigationView {
        NoCodesView()
            .environmentObject(AppState())
    }
}
