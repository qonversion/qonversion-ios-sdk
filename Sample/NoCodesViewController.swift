//
//  NoCodesViewController.swift
//  Sample
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

import UIKit
import Qonversion
import NoCodes

/// Exercises the No-Codes public surface: presenting a screen by context key,
/// loading it before presenting, the delegate set, presentation customization
/// and custom variables.
final class NoCodesViewController: UIViewController {

    private let contextKeyField = UITextField()
    private let variableNameField = UITextField()
    private let variableValueField = UITextField()
    private let presentationStylePicker = UISegmentedControl(items: ["Full Screen", "Push", "Popover"])
    private let animatedSwitch = UISwitch()
    private let logTextView = UITextView()

    private let listener = NoCodesSampleListener()
    private let customization = NoCodesSampleCustomization()
    private let customVariables = NoCodesSampleCustomVariables()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "No-Codes"

        configureFields()
        configureLog()

        // The delegate reports what happens inside the flow: screens shown,
        // actions started and finished, load failures.
        listener.onEvent = { [weak self] event in
            self?.log(event)
        }
        NoCodes.shared.set(delegate: listener)

        let actions: [(String, () -> Void)] = [
            ("Show screen", { self.showScreen() }),
            ("Load, then present or fall back", { self.loadBeforePresent() }),
            ("Apply presentation configuration", { self.applyPresentationConfiguration() }),
            ("Add custom variable", { self.addCustomVariable() }),
            ("Set custom variables delegate", { self.setCustomVariablesDelegate() }),
            ("Close screen", { self.closeScreen() }),
            ("Clear log", { self.logTextView.text = "" }),
        ]

        let buttons: [UIButton] = actions.map { title, handler in
            var configuration = UIButton.Configuration.filled()
            configuration.title = title
            let action = UIAction { _ in handler() }

            return UIButton(configuration: configuration, primaryAction: action)
        }

        let animatedRow = UIStackView(arrangedSubviews: [makeLabel("Animated"), animatedSwitch])
        animatedRow.axis = .horizontal
        animatedRow.spacing = 8

        var arrangedSubviews: [UIView] = [
            makeLabel("Context key"),
            contextKeyField,
            makeLabel("Presentation style"),
            presentationStylePicker,
            animatedRow,
            makeLabel("Custom variable"),
            variableNameField,
            variableValueField,
        ]
        arrangedSubviews.append(contentsOf: buttons)
        arrangedSubviews.append(logTextView)

        let rootStack = UIStackView(arrangedSubviews: arrangedSubviews)
        rootStack.axis = .vertical
        rootStack.spacing = 8
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            rootStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            rootStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            rootStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
    }

    // MARK: - Actions

    private func showScreen() {
        let contextKey: String = currentContextKey()
        log("Showing screen for context key '\(contextKey)'")
        NoCodes.shared.showScreen(withContextKey: contextKey)
    }

    /// Ask-first flow: load the screen, then decide whether to present it or to
    /// show the app's own UI instead. Nothing is presented by the load itself.
    private func loadBeforePresent() {
        let contextKey: String = currentContextKey()
        Task { @MainActor in
            do {
                let screen: NoCodesScreen = try await NoCodes.shared.loadScreen(withContextKey: contextKey)
                log("Screen loaded (id: \(screen.id)), presenting from the warm cache")

                // The loaded screen carries the typed default variables configured
                // in the builder, readable by key before anything is presented.
                let variables: String = screen.defaultVariables
                    .map { "\($0.kind.rawValue) \($0.key) = \($0.value.stringValue)" }
                    .joined(separator: ", ")
                log("Default variables: [\(variables)]")
                log("Default selected product: \(screen.defaultSelectedProductId ?? "none")")

                NoCodes.shared.showScreen(withContextKey: contextKey)
            } catch let error as NoCodesError {
                // No SDK screen ever appeared, so the app can show its own UI.
                log("Load failed (\(error.type)), showing the app fallback instead")
            } catch {
                log("Load failed: \(error.localizedDescription)")
            }
        }
    }

    private func applyPresentationConfiguration() {
        let style: NoCodesPresentationStyle = selectedPresentationStyle()
        customization.presentationStyle = style
        customization.animated = animatedSwitch.isOn
        NoCodes.shared.set(screenCustomizationDelegate: customization)
        log("Presentation configuration applied: \(style), animated=\(animatedSwitch.isOn)")
    }

    private func addCustomVariable() {
        let name: String = variableNameField.text ?? ""
        guard !name.isEmpty else {
            log("Enter a variable name first")
            return
        }

        let value: String = variableValueField.text ?? ""
        customVariables.variables[name] = value
        variableNameField.text = ""
        variableValueField.text = ""
        log("Custom variable '\(name)' = '\(value)' added")
    }

    private func setCustomVariablesDelegate() {
        NoCodes.shared.set(customVariablesDelegate: customVariables)
        log("Custom variables delegate set (\(customVariables.variables.count) variables)")
    }

    private func closeScreen() {
        NoCodes.shared.close()
        log("Close requested")
    }

    // MARK: - Helpers

    private func currentContextKey() -> String {
        let contextKey: String = contextKeyField.text ?? ""

        return contextKey.isEmpty ? "main" : contextKey
    }

    private func selectedPresentationStyle() -> NoCodesPresentationStyle {
        switch presentationStylePicker.selectedSegmentIndex {
        case 1:
            return .push
        case 2:
            return .popover
        default:
            return .fullScreen
        }
    }

    private func configureFields() {
        contextKeyField.placeholder = "Context key"
        contextKeyField.text = "main"
        contextKeyField.borderStyle = .roundedRect
        contextKeyField.autocapitalizationType = .none
        contextKeyField.autocorrectionType = .no

        variableNameField.placeholder = "Variable name"
        variableNameField.borderStyle = .roundedRect
        variableNameField.autocapitalizationType = .none
        variableNameField.autocorrectionType = .no

        variableValueField.placeholder = "Variable value"
        variableValueField.borderStyle = .roundedRect
        variableValueField.autocapitalizationType = .none
        variableValueField.autocorrectionType = .no

        presentationStylePicker.selectedSegmentIndex = 0
        animatedSwitch.isOn = true
    }

    private func configureLog() {
        logTextView.isEditable = false
        logTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        logTextView.layer.borderColor = UIColor.separator.cgColor
        logTextView.layer.borderWidth = 1
    }

    private func makeLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel

        return label
    }

    private func log(_ message: String) {
        let existing: String = logTextView.text ?? ""
        logTextView.text = existing.isEmpty ? message : existing + "\n" + message
    }
}

// MARK: - Delegates

/// Reports the No-Codes flow lifecycle back into the sample UI.
@MainActor
final class NoCodesSampleListener: NoCodesDelegate {

    var onEvent: ((String) -> Void)?

    func controllerForNavigation() -> UIViewController? {
        // nil lets the SDK present from the topmost view controller.
        return nil
    }

    func noCodesHasShownScreen(id: String) {
        onEvent?("Screen shown: \(id)")
    }

    func noCodesStartsExecuting(action: NoCodesAction) {
        onEvent?("Action started: \(action.type)")
    }

    func noCodesFailedToExecute(action: NoCodesAction, error: Error?) {
        let description: String = error?.localizedDescription ?? "unknown error"
        onEvent?("Action failed: \(action.type) - \(description)")
    }

    func noCodesFinishedExecuting(action: NoCodesAction) {
        onEvent?("Action finished: \(action.type)")
    }

    func noCodesReceivedCustomAction(value: String) {
        onEvent?("Custom action received: '\(value)'")
    }

    func noCodesFinished() {
        onEvent?("Flow finished")
    }

    func noCodesFailedToLoadScreen(error: Error?) {
        let description: String = error?.localizedDescription ?? "unknown error"
        onEvent?("Screen failed to load: \(description)")
        NoCodes.shared.close()
    }
}

/// Chooses how the first screen of the chain is presented.
@MainActor
final class NoCodesSampleCustomization: NoCodesScreenCustomizationDelegate {

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

    var variables: [String: String] = [:]

    func customVariables(for contextKey: String) -> [String: String] {
        return variables
    }
}
