import UIKit
import UniformTypeIdentifiers

private struct SharedImportItem: Codable, Equatable {
    let id: UUID
    let sourceURL: String
    let sourceAppBundleID: String?
    let createdAt: Date
}

private enum SharedImportInboxWriter {
    static let appGroupIdentifier = "group.com.jobtok.shared"
    private static let queueKey = "shared_import_queue_v1"
    private static let roleKey = "shared_import_last_known_role_v1"

    static func enqueueURL(_ sourceURL: String, sourceAppBundleID: String?) {
        let trimmed = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let existingItems: [SharedImportItem]
        if let data = defaults?.data(forKey: queueKey),
           let decoded = try? decoder.decode([SharedImportItem].self, from: data) {
            existingItems = decoded
        } else {
            existingItems = []
        }

        let updatedItems = existingItems + [
            SharedImportItem(
                id: UUID(),
                sourceURL: trimmed,
                sourceAppBundleID: sourceAppBundleID,
                createdAt: Date()
            )
        ]

        guard let data = try? encoder.encode(updatedItems) else { return }
        defaults?.set(data, forKey: queueKey)
    }

    static var lastKnownRole: String? {
        UserDefaults(suiteName: appGroupIdentifier)?.string(forKey: roleKey)
    }
}

final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let primaryButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)

    private var sharedURLString: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()

        Task {
            let resolvedURL = await extractSharedURL()
            await MainActor.run {
                self.sharedURLString = resolvedURL
                self.renderResolvedState()
            }
        }
    }

    private func configureUI() {
        view.backgroundColor = .systemBackground

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 28, weight: .bold)
        statusLabel.textAlignment = .center
        statusLabel.text = "scout22"

        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.font = .systemFont(ofSize: 16, weight: .regular)
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 0
        descriptionLabel.text = "Preparing shared post…"

        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        primaryButton.configuration = .filled()
        primaryButton.configuration?.baseBackgroundColor = UIColor.black
        primaryButton.configuration?.baseForegroundColor = UIColor.white
        primaryButton.configuration?.cornerStyle = .large
        primaryButton.configuration?.title = "Save to scout22"
        primaryButton.isEnabled = false
        primaryButton.addTarget(self, action: #selector(handleSave), for: .touchUpInside)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.configuration = .plain()
        closeButton.configuration?.title = "Cancel"
        closeButton.addTarget(self, action: #selector(handleCancel), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [statusLabel, descriptionLabel, primaryButton, closeButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 18
        stack.alignment = .fill

        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func renderResolvedState() {
        guard SharedImportInboxWriter.lastKnownRole == "admin" else {
            descriptionLabel.text = "Only scout22 admins can import shared posts. Open the scout22 app with an admin account first."
            primaryButton.isEnabled = false
            return
        }

        if let sharedURLString, !sharedURLString.isEmpty {
            descriptionLabel.text = "Save this shared TikTok or Instagram link to the scout22 admin import inbox."
            primaryButton.isEnabled = true
        } else {
            descriptionLabel.text = "This share did not include a usable post link. Share a TikTok or Instagram URL into scout22 instead."
            primaryButton.isEnabled = false
        }
    }

    @objc
    private func handleSave() {
        guard let sharedURLString, !sharedURLString.isEmpty else { return }
        SharedImportInboxWriter.enqueueURL(sharedURLString, sourceAppBundleID: nil)
        extensionContext?.completeRequest(returningItems: nil)
    }

    @objc
    private func handleCancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: "JobTokShare", code: 1))
    }

    private func extractSharedURL() async -> String? {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            return nil
        }

        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = await loadURL(from: provider) {
                        return url.absoluteString
                    }
                }

                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = await loadText(from: provider),
                       let url = firstURLString(in: text) {
                        return url
                    }
                }
            }
        }

        return nil
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                    return
                }
                continuation.resume(returning: nil)
            }
        }
    }

    private func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                if let text = item as? String {
                    continuation.resume(returning: text)
                    return
                }
                if let url = item as? URL {
                    continuation.resume(returning: url.absoluteString)
                    return
                }
                continuation.resume(returning: nil)
            }
        }
    }

    private func firstURLString(in text: String) -> String? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(location: 0, length: text.utf16.count)
        let match = detector?.firstMatch(in: text, options: [], range: range)
        return match?.url?.absoluteString
    }
}
