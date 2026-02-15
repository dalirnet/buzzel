import Foundation
import AppKit
import UserNotifications

class BuzzelNotificationManager: NSObject, UNUserNotificationCenterDelegate {

    static let shared = BuzzelNotificationManager()

    func requestPermission() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // Register smart copy action
        let copyAction = UNNotificationAction(identifier: "COPY_ACTION", title: "Copy", options: [])
        let category = UNNotificationCategory(
            identifier: "SMS_CATEGORY",
            actions: [copyAction],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])
    }

    func showSms(sender: String, contactName: String?, body: String) {
        let content = UNMutableNotificationContent()
        content.title = contactName.map { "\($0) (\(sender))" } ?? sender
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "SMS_CATEGORY"

        // Smart copy — detect actionable content
        if let smartValue = detectSmartCopy(body) {
            content.userInfo = ["copyValue": smartValue.value]

            let copyAction = UNNotificationAction(
                identifier: "COPY_ACTION",
                title: "Copy \"\(smartValue.display)\"",
                options: []
            )
            let category = UNNotificationCategory(
                identifier: "SMS_CATEGORY",
                actions: [copyAction],
                intentIdentifiers: []
            )
            UNUserNotificationCenter.current().setNotificationCategories([category])
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == "COPY_ACTION" {
            if let value = response.notification.request.content.userInfo["copyValue"] as? String {
                copyToClipboard(value)
            }
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // MARK: - Smart Copy Detection

    struct SmartValue {
        let value: String
        let display: String
    }

    func detectSmartCopy(_ text: String) -> SmartValue? {
        // Priority: OTP > URL > Phone > @ > #

        // OTP: 4-8 digit numbers near keywords
        if let otp = detectOTP(text) { return otp }
        // URL
        if let url = detectURL(text) { return url }
        // Phone
        if let phone = detectPhone(text) { return phone }
        // @mention
        if let mention = detectMention(text) { return mention }
        // #hashtag
        if let hashtag = detectHashtag(text) { return hashtag }

        return nil
    }

    private func detectOTP(_ text: String) -> SmartValue? {
        let keywords = ["code", "otp", "pin", "verify", "verification", "token", "password"]
        let lower = text.lowercased()
        let hasKeyword = keywords.contains { lower.contains($0) }
        guard hasKeyword else { return nil }

        let pattern = "\\b(\\d{4,8})\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }

        let code = String(text[range])
        return SmartValue(value: code, display: code)
    }

    private func detectURL(_ text: String) -> SmartValue? {
        let pattern = "https?://[^\\s]+"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text)
        else { return nil }

        let url = String(text[range])
        let display = url.count > 30 ? String(url.prefix(30)) + "..." : url
        return SmartValue(value: url, display: display)
    }

    private func detectPhone(_ text: String) -> SmartValue? {
        let pattern = "[+]?[\\d][\\d\\s\\-()]{6,}\\d"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text)
        else { return nil }

        let raw = String(text[range])
        let cleaned = raw.filter { $0.isNumber || $0 == "+" }
        return SmartValue(value: cleaned, display: raw.trimmingCharacters(in: .whitespaces))
    }

    private func detectMention(_ text: String) -> SmartValue? {
        let pattern = "@[a-zA-Z0-9_]+"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text)
        else { return nil }

        let mention = String(text[range])
        return SmartValue(value: mention, display: mention)
    }

    private func detectHashtag(_ text: String) -> SmartValue? {
        let pattern = "#[a-zA-Z0-9_]+"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text)
        else { return nil }

        let hashtag = String(text[range])
        return SmartValue(value: hashtag, display: hashtag)
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
