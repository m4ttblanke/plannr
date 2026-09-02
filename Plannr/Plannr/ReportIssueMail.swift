//
//  ReportIssueMail.swift
//  Plannr
//
//  Beta feedback support: an in-app mail composer for reporting an issue or
//  suggesting a feature, with a mailto: fallback when the device has no Mail
//  account configured.
//

import SwiftUI
import MessageUI
import UIKit

enum ReportIssue {
    static let recipient = "mattheweblanke@gmail.com"

    /// What the user is sending — drives the subject line and the body prompt.
    enum Kind {
        case issue
        case feature

        var subject: String {
            switch self {
            case .issue:   return "Plannr Beta — Issue Report"
            case .feature: return "Plannr Beta — Feature Suggestion"
            }
        }

        /// Menu title / alert title for this kind.
        var title: String {
            switch self {
            case .issue:   return "Report an Issue"
            case .feature: return "Suggest a Feature"
            }
        }

        fileprivate var prompt: String {
            switch self {
            case .issue:
                return """
                Describe the issue (what happened, and what you expected):


                Steps to reproduce:
                """
            case .feature:
                return """
                What would you like Plannr to do?


                Why would this help, and when do you hit the need?
                """
            }
        }
    }

    /// Body pre-fill: a short prompt plus environment details that make a beta
    /// report actionable without a back-and-forth.
    static func body(kind: Kind, accountDescription: String) -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let device = UIDevice.current
        return """
        \(kind.prompt)

        ————————————————
        Plannr \(version) (\(build))
        \(device.systemName) \(device.systemVersion) • \(device.model)
        Account: \(accountDescription)
        """
    }

    /// Open the system mail client with a pre-filled message. Used when the
    /// in-app composer isn't available. Returns false if nothing could handle it.
    @discardableResult
    static func openMailto(kind: Kind, accountDescription: String) -> Bool {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: kind.subject),
            URLQueryItem(name: "body", value: body(kind: kind, accountDescription: accountDescription)),
        ]
        guard let url = components.url, UIApplication.shared.canOpenURL(url) else { return false }
        UIApplication.shared.open(url)
        return true
    }
}

/// SwiftUI wrapper around `MFMailComposeViewController` for the in-app compose
/// sheet. Only present this when `MFMailComposeViewController.canSendMail()`.
struct MailComposeView: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    var onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([recipient])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        return vc
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true, completion: onFinish)
        }
    }
}
