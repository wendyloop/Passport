import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {

    private let appGroupID  = "group.com.jobtok.shared"
    private let tokenKey    = "jobtok.shared.accessToken"
    private let supabaseKey = "jobtok.shared.supabaseURL"
    private let roleKey     = "jobtok.shared.userRole"

    // MARK: - UI

    private let card: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(white: 0.1, alpha: 1)
        v.layer.cornerRadius = 24
        v.layer.cornerCurve = .continuous
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let iconLabel: UILabel = {
        let l = UILabel()
        l.text = "scout22"
        l.font = .systemFont(ofSize: 22, weight: .black)
        l.textColor = .white
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let statusLabel: UILabel = {
        let l = UILabel()
        l.text = "Adding reel…"
        l.font = .systemFont(ofSize: 15, weight: .medium)
        l.textColor = UIColor(white: 0.7, alpha: 1)
        l.numberOfLines = 2
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let spinner: UIActivityIndicatorView = {
        let s = UIActivityIndicatorView(style: .medium)
        s.color = .white
        s.hidesWhenStopped = true
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private let doneButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Done"
        config.baseBackgroundColor = UIColor(red: 0.97, green: 0.9, blue: 0.2, alpha: 1)
        config.baseForegroundColor = .black
        config.cornerStyle = .large
        let b = UIButton(configuration: config)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.isHidden = true
        return b
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        buildLayout()
        spinner.startAnimating()
        processSharedURL()
    }

    private func buildLayout() {
        view.addSubview(card)
        card.addSubview(iconLabel)
        card.addSubview(statusLabel)
        card.addSubview(spinner)
        card.addSubview(doneButton)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 280),

            iconLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 28),
            iconLabel.centerXAnchor.constraint(equalTo: card.centerXAnchor),

            spinner.topAnchor.constraint(equalTo: iconLabel.bottomAnchor, constant: 20),
            spinner.centerXAnchor.constraint(equalTo: card.centerXAnchor),

            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),

            doneButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 20),
            doneButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            doneButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            doneButton.heightAnchor.constraint(equalToConstant: 48),
            doneButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24),
        ])

        doneButton.addTarget(self, action: #selector(didTapDone), for: .touchUpInside)
    }

    // MARK: - URL extraction

    private func processSharedURL() {
        guard let inputItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            finish(success: false, message: "Nothing to share.")
            return
        }

        let urlTypeID = UTType.url.identifier
        for item in inputItems {
            for provider in (item.attachments ?? []) {
                if provider.hasItemConformingToTypeIdentifier(urlTypeID) {
                    provider.loadItem(forTypeIdentifier: urlTypeID, options: nil) { [weak self] data, _ in
                        DispatchQueue.main.async {
                            let url: URL?
                            if let u = data as? URL { url = u }
                            else if let s = data as? String { url = URL(string: s) }
                            else { url = nil }

                            if let url {
                                self?.ingest(url: url)
                            } else {
                                self?.finish(success: false, message: "Could not read the URL.")
                            }
                        }
                    }
                    return
                }
            }
        }
        finish(success: false, message: "No URL found in shared content.")
    }

    // MARK: - Ingest

    private func ingest(url: URL) {
        let shared = UserDefaults(suiteName: appGroupID)

        guard let token = shared?.string(forKey: tokenKey), !token.isEmpty else {
            finish(success: false, message: "Sign in to scout22 first, then try again.")
            return
        }
        guard let role = shared?.string(forKey: roleKey), role == "admin" else {
            finish(success: false, message: "Only admins can add reels directly.")
            return
        }
        guard let supabaseURL = shared?.string(forKey: supabaseKey), !supabaseURL.isEmpty,
              let endpoint = URL(string: "\(supabaseURL)/functions/v1/ingest-shared-reel") else {
            finish(success: false, message: "App configuration error.")
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["url": url.absoluteString])

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if error != nil || status >= 400 {
                    // Share extensions can't run our refresh-token flow — the
                    // Supabase JWT cached in the App Group eventually expires.
                    // Tell the user to bounce into the main app, which calls
                    // ensureValidSession on launch and rewrites the fresh
                    // token back to the App Group.
                    let message: String
                    if status == 401 {
                        message = "Your scout22 sign-in expired. Open the scout22 app, then try sharing again."
                    } else if let data,
                              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let errMsg = body["error"] as? String {
                        message = errMsg
                    } else {
                        message = "Failed to add reel (error \(status))."
                    }
                    self?.finish(success: false, message: message)
                } else {
                    self?.finish(success: true, message: "Reel added to scout22!")
                }
            }
        }.resume()
    }

    // MARK: - Finish

    private func finish(success: Bool, message: String) {
        spinner.stopAnimating()
        statusLabel.text = message
        statusLabel.textColor = success
            ? UIColor(red: 0.97, green: 0.9, blue: 0.2, alpha: 1)
            : UIColor(red: 1, green: 0.35, blue: 0.35, alpha: 1)
        doneButton.isHidden = false
    }

    @objc private func didTapDone() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
