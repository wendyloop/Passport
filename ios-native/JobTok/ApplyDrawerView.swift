import SwiftUI
import WebKit

// MARK: - ATS detection

enum ATSPlatform: String {
    case greenhouse = "greenhouse"
    case lever      = "lever"
    case workday    = "workday"
    case ashby      = "ashby"
    case rippling   = "rippling"   // blocked — open in Safari
    case other      = "other"

    static func detect(from url: URL) -> ATSPlatform {
        let host = url.host?.lowercased() ?? ""
        if host.contains("greenhouse.io")  { return .greenhouse }
        if host.contains("lever.co")       { return .lever }
        if host.contains("myworkday.com") || host.contains("workday.com") { return .workday }
        if host.contains("ashbyhq.com")    { return .ashby }
        if host.contains("rippling.com")   { return .rippling }
        return .other
    }

    var isBlocked: Bool { self == .rippling }
}

// MARK: - Prefill model (from get-prefill-profile)

struct PrefillProfile: Codable {
    let firstName: String
    let lastName: String
    let fullName: String
    let email: String
    let phone: String
    let city: String
    let linkedInUrl: String
    let githubUrl: String
    let portfolioUrl: String
}

struct PrefillResponse: Codable {
    let profile: PrefillProfile
    let fieldHistory: [String: String]
}

// MARK: - ApplyDrawerView

struct ApplyDrawerView: View {
    let job: JobPostingRecord
    let session: AuthSession
    @Binding var isPresented: Bool

    private let service = SupabaseService.shared

    @State private var prefill: PrefillResponse?
    @State private var eventId: String?
    @State private var submittedSuccessfully = false

    var body: some View {
        NavigationStack {
            Group {
                if let applyURL = job.applyUrl.flatMap(URL.init) {
                    if ATSPlatform.detect(from: applyURL).isBlocked {
                        blockedView(url: applyURL)
                    } else {
                        ApplyWebView(
                            url: applyURL,
                            prefill: prefill,
                            onSubmitted: { fields in
                                handleSubmission(fields: fields)
                            }
                        )
                        .ignoresSafeArea(edges: .bottom)
                    }
                } else {
                    Text("No apply URL available.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(job.companyName.isEmpty ? "Apply" : job.companyName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                }
            }
            .overlay {
                if submittedSuccessfully {
                    submittedBanner
                }
            }
        }
        .task { await loadPrefillAndLogOpen() }
    }

    // MARK: - Subviews

    private func blockedView(url: URL) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "safari")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("This application must be opened in Safari.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Open in Safari") {
                UIApplication.shared.open(url)
                isPresented = false
            }
            .buttonStyle(.borderedProminent)
            .tint(PassportTheme.accent)
        }
        .padding(40)
    }

    private var submittedBanner: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Application submitted!")
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.regularMaterial)
            .clipShape(Capsule())
            .padding(.bottom, 32)
        }
    }

    // MARK: - Actions

    private func loadPrefillAndLogOpen() async {
        async let prefillTask = fetchPrefill()
        async let eventTask = logEvent(type: "opened", applicationId: nil)
        let (p, eid) = await (prefillTask, eventTask)
        prefill = p
        eventId = eid
    }

    private func fetchPrefill() async -> PrefillResponse? {
        try? await service.getPrefillProfile(session: session)
    }

    private func logEvent(type: String, applicationId: String?) async -> String? {
        try? await service.logApplicationEvent(
            jobID: job.id,
            eventType: type,
            applicationID: applicationId,
            atsType: job.applyUrl.flatMap(URL.init).map { ATSPlatform.detect(from: $0).rawValue },
            applyURL: job.applyUrl,
            session: session
        )
    }

    private func handleSubmission(fields: [String: String]) {
        submittedSuccessfully = true
        Task {
            let eid: String?
            if let existing = eventId {
                eid = existing
            } else {
                eid = await logEvent(type: "submitted", applicationId: nil)
            }
            if let eid, !fields.isEmpty {
                await storeFields(eventId: eid, fields: fields)
            }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            isPresented = false
        }
    }

    private func storeFields(eventId: String, fields: [String: String]) async {
        try? await service.storeApplicationFields(
            eventID: eventId,
            fields: fields,
            session: session
        )
    }
}

// MARK: - ApplyWebView (UIViewRepresentable)

struct ApplyWebView: UIViewRepresentable {
    let url: URL
    let prefill: PrefillResponse?
    let onSubmitted: ([String: String]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSubmitted: onSubmitted)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "formSubmitted")
        config.userContentController.add(context.coordinator, name: "fieldCaptured")

        if let prefill {
            let script = WKUserScript(
                source: buildPrefillJS(prefill: prefill),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
            config.userContentController.addUserScript(script)

            // MutationObserver for SPA re-renders
            let spaScript = WKUserScript(
                source: buildSPAObserverJS(prefill: prefill),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
            config.userContentController.addUserScript(spaScript)
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        if let prefill {
            context.coordinator.prefillJS = buildPrefillJS(prefill: prefill)
        }
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    // MARK: - JS builders

    private func buildPrefillJS(prefill: PrefillResponse) -> String {
        let encoder = JSONEncoder()
        guard let profileData = try? encoder.encode(prefill.profile),
              let profileJSON = String(data: profileData, encoding: .utf8) else { return "" }

        let historyEntries = prefill.fieldHistory.map { k, v in
            "\"\(k.replacingOccurrences(of: "\"", with: "\\\""))\": \"\(v.replacingOccurrences(of: "\"", with: "\\\""))\""
        }.joined(separator: ", ")
        let historyJSON = "{\(historyEntries)}"

        return """
        (function() {
          var profile = \(profileJSON);
          var history = \(historyJSON);

          function fillInput(el, value) {
            if (!el || !value) return;
            var nativeSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value') ||
                               Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value');
            if (nativeSetter && nativeSetter.set) nativeSetter.set.call(el, value);
            else el.value = value;
            el.dispatchEvent(new Event('input', { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
          }

          function findByLabel(text) {
            var lower = text.toLowerCase();
            var labels = document.querySelectorAll('label');
            for (var i = 0; i < labels.length; i++) {
              var l = labels[i];
              if (l.textContent.toLowerCase().indexOf(lower) !== -1) {
                var forEl = l.htmlFor ? document.getElementById(l.htmlFor) : null;
                return forEl || l.querySelector('input, textarea');
              }
            }
            // aria-label fallback
            var inputs = document.querySelectorAll('input[aria-label], textarea[aria-label]');
            for (var j = 0; j < inputs.length; j++) {
              if ((inputs[j].getAttribute('aria-label') || '').toLowerCase().indexOf(lower) !== -1) {
                return inputs[j];
              }
            }
            // placeholder fallback
            var ph = document.querySelectorAll('input[placeholder], textarea[placeholder]');
            for (var k = 0; k < ph.length; k++) {
              if ((ph[k].getAttribute('placeholder') || '').toLowerCase().indexOf(lower) !== -1) {
                return ph[k];
              }
            }
            return null;
          }

          // Standard field mappings (label keyword -> profile value)
          var mappings = [
            ['first name', profile.firstName],
            ['last name', profile.lastName],
            ['full name', profile.fullName],
            ['your name', profile.fullName],
            ['email', profile.email],
            ['phone', profile.phone],
            ['city', profile.city],
            ['location', profile.city],
            ['linkedin', profile.linkedInUrl],
            ['github', profile.githubUrl],
            ['portfolio', profile.portfolioUrl],
            ['website', profile.portfolioUrl],
          ];

          mappings.forEach(function(m) {
            fillInput(findByLabel(m[0]), m[1]);
          });

          // Historical field values from previous applications
          Object.keys(history).forEach(function(label) {
            var el = findByLabel(label);
            if (el && !el.value) fillInput(el, history[label]);
          });

          // Capture form submission
          function labelFor(input) {
            if (input.id) {
              var l = document.querySelector('label[for="' + input.id + '"]');
              if (l) return l.textContent.trim();
            }
            var p = input.closest('label');
            if (p) return p.textContent.trim();
            return input.getAttribute('aria-label') || input.placeholder || input.name || null;
          }

          document.addEventListener('submit', function() {
            var fields = {};
            document.querySelectorAll('input, textarea, select').forEach(function(el) {
              var lbl = labelFor(el);
              if (lbl && el.value && el.type !== 'password' && el.type !== 'hidden') {
                fields[lbl] = el.value;
              }
            });
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.formSubmitted) {
              window.webkit.messageHandlers.formSubmitted.postMessage({ fields: fields, url: window.location.href });
            }
          }, true);
        })();
        """
    }

    private func buildSPAObserverJS(prefill: PrefillResponse) -> String {
        // Throttled observer: notify native when URL changes (SPA navigation) so WKWebView can re-inject
        return """
        (function() {
          var lastUrl = location.href;
          var timer = null;
          var obs = new MutationObserver(function() {
            if (location.href !== lastUrl) {
              lastUrl = location.href;
              clearTimeout(timer);
              timer = setTimeout(function() {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.fieldCaptured) {
                  window.webkit.messageHandlers.fieldCaptured.postMessage({ spaNavigation: true, url: location.href });
                }
              }, 600);
            }
          });
          if (document.body) obs.observe(document.body, { childList: true, subtree: true });
        })();
        """
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let onSubmitted: ([String: String]) -> Void
        var prefillJS: String = ""
        private var hasReportedSubmission = false

        init(onSubmitted: @escaping ([String: String]) -> Void) {
            self.onSubmitted = onSubmitted
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "formSubmitted" {
                guard !hasReportedSubmission else { return }
                hasReportedSubmission = true
                let body = message.body as? [String: Any]
                let fields = body?["fields"] as? [String: String] ?? [:]
                DispatchQueue.main.async { self.onSubmitted(fields) }
            } else if message.name == "fieldCaptured" {
                // SPA navigation detected — re-run prefill in current webView
                let body = message.body as? [String: Any]
                guard (body?["spaNavigation"] as? Bool) == true else { return }
                // The message handler doesn't have direct access to the webView here;
                // re-injection happens via webView(_:didFinish:) after SPA pushState
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            // Non-fatal; webview renders its own error page.
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !prefillJS.isEmpty else { return }
            webView.evaluateJavaScript(prefillJS, completionHandler: nil)
        }
    }
}
