//
//  ReissueViewController.swift
//  Qonversion
//
//  Internal fallback UI for Web 2 App reissue (DEV-847 / M1).
//  Presented modally by Qonversion.shared().presentReissueUI(from:onCompletion:)
//  when the token-based redemption flow can't recover automatically
//  (token expired, install attribution failed, etc.).
//

import Foundation

#if canImport(UIKit) && (os(iOS) || os(tvOS) || os(visionOS))
import UIKit
@_exported import Qonversion

/// Internal modal UI that collects an email and POSTs to
/// `/v4/web/redeem/reissue`. Strings are intentionally inline + minimal —
/// host apps wanting full L10n control should build their own UI and call
/// the Obj-C `reissueRedemption(email:completion:)` directly.
@available(iOS 13.0, tvOS 13.0, *)
final class ReissueViewController: UIViewController, UITextFieldDelegate, UIAdaptivePresentationControllerDelegate {

  // MARK: - Strings (kept inline; not yet in .strings — see TODO at bottom)

  private enum L {
    static let title       = "Restore your purchase"
    static let prompt      = "Enter the email you used for the purchase. We'll send you a fresh redemption link."
    static let placeholder = "you@example.com"
    static let send        = "Send link"
    static let cancel      = "Cancel"
    static let success     = "Email sent if we found a matching purchase. Check your inbox (and spam). If nothing arrives in 5 minutes, try a different email."
    static let rateLimited = "Too many attempts. Please try again later."
    static let serverError = "Something went wrong. Please try again."
    static let retry       = "Retry"
    static let dismiss     = "OK"
  }

  // MARK: - Inputs

  private let onCompletion: (Bool) -> Void
  private var didCallCompletion = false

  // MARK: - Views

  private let titleLabel    = UILabel()
  private let promptLabel   = UILabel()
  private let emailField    = UITextField()
  private let sendButton    = UIButton(type: .system)
  private let cancelButton  = UIButton(type: .system)
  private let spinner       = UIActivityIndicatorView(style: .medium)
  private let stack         = UIStackView()

  init(onCompletion: @escaping (Bool) -> Void) {
    self.onCompletion = onCompletion
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

  // MARK: - Lifecycle

  override func viewDidLoad() {
    super.viewDidLoad()
    // #4 — own the presentation controller's delegate so an interactive
    // swipe-to-dismiss (the default for `.formSheet`/`.pageSheet` on iOS 13+)
    // is reported back to the host via `onCompletion(false)`. Without this the
    // user could dismiss the sheet by swiping and the host would wait forever
    // for a completion that never arrives.
    presentationController?.delegate = self
    // `systemBackground` is unavailable on tvOS; fall back to black there
    // so the multi-platform podspec lint compiles.
    #if os(tvOS)
    view.backgroundColor = .black
    #else
    view.backgroundColor = .systemBackground
    #endif

    titleLabel.text = L.title
    titleLabel.font = .preferredFont(forTextStyle: .title2)
    titleLabel.numberOfLines = 0

    promptLabel.text = L.prompt
    promptLabel.font = .preferredFont(forTextStyle: .body)
    promptLabel.numberOfLines = 0
    promptLabel.textColor = .secondaryLabel

    emailField.placeholder = L.placeholder
    emailField.keyboardType = .emailAddress
    emailField.autocapitalizationType = .none
    emailField.autocorrectionType = .no
    emailField.returnKeyType = .send
    emailField.borderStyle = .roundedRect
    emailField.delegate = self
    emailField.addTarget(self, action: #selector(emailChanged), for: .editingChanged)

    sendButton.setTitle(L.send, for: .normal)
    sendButton.isEnabled = false
    sendButton.addTarget(self, action: #selector(didTapSend), for: .touchUpInside)

    cancelButton.setTitle(L.cancel, for: .normal)
    cancelButton.addTarget(self, action: #selector(didTapCancel), for: .touchUpInside)

    spinner.hidesWhenStopped = true

    stack.axis = .vertical
    stack.spacing = 16
    stack.alignment = .fill
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.addArrangedSubview(titleLabel)
    stack.addArrangedSubview(promptLabel)
    stack.addArrangedSubview(emailField)
    stack.addArrangedSubview(sendButton)
    stack.addArrangedSubview(spinner)
    stack.addArrangedSubview(cancelButton)
    view.addSubview(stack)

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
      stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
      stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
    ])
  }

  // MARK: - Actions

  @objc private func emailChanged() {
    sendButton.isEnabled = isValidEmail(emailField.text ?? "")
  }

  @objc private func didTapSend() {
    let email = (emailField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard isValidEmail(email) else { return }

    setLoading(true)
    Qonversion.shared().reissueRedemption(email: email) { [weak self] success, statusCode, error in
      // Callback is already on main per QONRedemptionManager.
      guard let self = self else { return }
      self.setLoading(false)

      if success {
        self.showAlert(message: L.success, dismissOnOK: true, didSucceed: true)
        return
      }

      // 429 — rate limited
      if statusCode == 429 {
        self.showAlert(message: L.rateLimited, dismissOnOK: false, didSucceed: false)
        return
      }

      // 503 / other server error / transport error
      self.showAlert(message: L.serverError, dismissOnOK: false, didSucceed: false)
    }
  }

  @objc private func didTapCancel() {
    finish(success: false)
  }

  // MARK: - UI helpers

  private func setLoading(_ loading: Bool) {
    if loading {
      spinner.startAnimating()
    } else {
      spinner.stopAnimating()
    }
    sendButton.isEnabled = !loading && isValidEmail(emailField.text ?? "")
    emailField.isEnabled = !loading
    cancelButton.isEnabled = !loading
  }

  private func showAlert(message: String, dismissOnOK: Bool, didSucceed: Bool) {
    let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: L.dismiss, style: .default) { [weak self] _ in
      if dismissOnOK {
        self?.finish(success: didSucceed)
      }
    })
    present(alert, animated: true)
  }

  private func finish(success: Bool) {
    guard !didCallCompletion else { return }
    didCallCompletion = true
    let callback = onCompletion
    dismiss(animated: true) {
      callback(success)
    }
  }

  /// Fires the completion exactly once WITHOUT issuing a dismiss — used when
  /// the system has already dismissed us (interactive swipe). Calling
  /// `dismiss` again here would be a no-op whose completion never runs, so the
  /// callback must be invoked directly.
  private func completeWithoutDismiss(success: Bool) {
    guard !didCallCompletion else { return }
    didCallCompletion = true
    onCompletion(success)
  }

  // MARK: - UIAdaptivePresentationControllerDelegate

  /// #4 — Called when the user dismisses the sheet interactively (swipe down).
  /// `didTapCancel`/`finish` is NOT invoked in that case, so we must report the
  /// cancellation here or the host hangs.
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    completeWithoutDismiss(success: false)
  }

  // MARK: - Validation

  private func isValidEmail(_ candidate: String) -> Bool {
    // Minimal — server is authoritative. We just want to disable Send for empty / obviously-bad input.
    let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count >= 3, let at = trimmed.firstIndex(of: "@") else { return false }
    let domain = trimmed[trimmed.index(after: at)...]
    return domain.contains(".")
  }

  // MARK: - UITextFieldDelegate

  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    if sendButton.isEnabled {
      didTapSend()
    }
    return true
  }
}

// TODO(DEV-847 follow-up): move L strings into a .strings catalog when the
// SDK adds L10n infra. Inline keeps the M1 scope minimal.
#endif
