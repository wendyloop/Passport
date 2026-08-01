import SwiftUI
import WebKit

// MARK: - ATS detection

enum ATSPlatform: String {
    case greenhouse = "greenhouse"
    case lever      = "lever"
    case workday    = "workday"
    case ashby      = "ashby"
    case smartrecruiters = "smartrecruiters"
    case recruitee  = "recruitee"
    case rippling   = "rippling"   // blocked — open in Safari
    case other      = "other"

    static func detect(from url: URL) -> ATSPlatform {
        let host = url.host?.lowercased() ?? ""
        // Suffix match, not contains — "greenhouse.io.evil.com" must not pass.
        func matches(_ domain: String) -> Bool {
            host == domain || host.hasSuffix("." + domain)
        }
        if matches("greenhouse.io")  { return .greenhouse }
        if matches("lever.co")       { return .lever }
        if matches("myworkday.com") || matches("workday.com") { return .workday }
        if matches("ashbyhq.com")    { return .ashby }
        if matches("smartrecruiters.com") { return .smartrecruiters }
        if matches("recruitee.com")  { return .recruitee }
        if matches("rippling.com")   { return .rippling }
        return .other
    }

    var isBlocked: Bool { self == .rippling }
}

/// AUDIT P1-6: autofill (fill AND capture) runs only on these 14 known ATS
/// domains — matched as exact host or dot-suffix, mirrored into the injected
/// JS. Any other host gets no prefill, no submit capture, no message posts,
/// visible fields or not.
enum ATSAutofillPolicy {
    static let allowedDomains: [String] = [
        "greenhouse.io",
        "boards.greenhouse.io",
        "job-boards.greenhouse.io",
        "lever.co",
        "jobs.lever.co",
        "ashbyhq.com",
        "jobs.ashbyhq.com",
        "myworkday.com",
        "workday.com",
        "smartrecruiters.com",
        "jobs.smartrecruiters.com",
        "careers.smartrecruiters.com",
        "recruitee.com",
        "rippling.com"
    ]

    static func isHostAllowed(_ host: String?) -> Bool {
        guard let host = host?.lowercased(), !host.isEmpty else { return false }
        return allowedDomains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// The allowlist as a JS array literal for injection.
    static var domainsJSArray: String {
        let quoted = allowedDomains.map { "'\($0)'" }.joined(separator: ",")
        return "[\(quoted)]"
    }

    /// Field labels we never fill and never capture: the EEO / protected-class
    /// block every major ATS appends to its application form. Capturing these
    /// would put racial, disability and similar answers into
    /// `application_fields` — GDPR Art. 9 special-category data, and the exact
    /// segregation EEO reporting depends on. The candidate still answers them
    /// on the ATS page; scout22 just never reads or stores them.
    ///
    /// Word boundaries matter: `\brace\b` must not fire on "embrace", and
    /// `\bsex\b` must not fire on "Essex" in an address field. Mirrored into
    /// the injected JS as regex literals.
    static let sensitiveLabelPatterns: [String] = [
        "\\brace\\b",
        "ethnic",
        "disab",
        "\\bveteran\\b",
        "\\bgender\\b",
        "\\bsex\\b",
        "sexual",
        "pregnan",
        "religio",
        "politic",
        "trade union",
        "genetic",
        "biometric",
    ]

    static func isSensitiveLabel(_ label: String?) -> Bool {
        guard let label, !label.isEmpty else { return false }
        return sensitiveLabelPatterns.contains {
            label.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    /// The denylist as JS regex literals. Case-insensitive, never global —
    /// a /g/ regex would make `.test()` stateful across elements.
    static var sensitivePatternsJSArray: String {
        "[\(sensitiveLabelPatterns.map { "/\($0)/i" }.joined(separator: ","))]"
    }

    /// Shared prologue for every injected script: bail out unless the
    /// document's own host is a known ATS. Runs per navigation and per frame.
    static var hostGateJS: String {
        """
        var ATS_DOMAINS = \(domainsJSArray);
          var __jtHost = (location.hostname || '').toLowerCase();
          var __jtAllowed = ATS_DOMAINS.some(function(d) {
            return __jtHost === d || __jtHost.slice(-(d.length + 1)) === '.' + d;
          });
          if (!__jtAllowed) return;
        """
    }
}

// MARK: - ApplyDrawerView

struct ApplyDrawerView: View {
    let job: JobPostingRecord
    let session: AuthSession
    let service: CandidateService
    @Binding var isPresented: Bool

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
                            session: session,
                            service: service,
                            onSubmitted: { payload in
                                handleSubmission(payload: payload)
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

    private func handleSubmission(payload: CapturedSubmission) {
        submittedSuccessfully = true
        Task {
            // AUDIT P1-2: always log the submitted funnel event. It used to
            // be logged only when the earlier "opened" log had failed, so
            // application_events recorded ~zero submissions. Captured fields
            // attach to the submitted event (opened event as fallback).
            let submittedEventId = await logEvent(type: "submitted", applicationId: nil)
            if let eid = submittedEventId ?? eventId,
               !payload.shortFields.isEmpty || !payload.essays.isEmpty {
                try? await service.storeApplicationFields(
                    eventID: eid,
                    shortFields: payload.shortFields,
                    essays: payload.essays,
                    session: session
                )
            }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            isPresented = false
        }
    }
}

// MARK: - Capture payload from WebView

struct CapturedSubmission {
    var shortFields: [ApplicationShortField]
    var essays: [ApplicationEssay]
}

// MARK: - ApplyWebView (UIViewRepresentable)

struct ApplyWebView: UIViewRepresentable {
    let url: URL
    let prefill: PrefillResponse?
    let session: AuthSession
    let service: CandidateService
    let onSubmitted: (CapturedSubmission) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, service: service, onSubmitted: onSubmitted)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "formSubmitted")
        config.userContentController.add(context.coordinator, name: "essayQuestionsFound")
        config.userContentController.add(context.coordinator, name: "spaNavigation")

        let prefillJS = buildPrefillJS(prefill: prefill)
        config.userContentController.addUserScript(
            WKUserScript(source: prefillJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        )
        config.userContentController.addUserScript(
            WKUserScript(source: spaObserverJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        )

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.prefillJS = prefillJS
        context.coordinator.webView = webView
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    // MARK: - JS builders

    private func buildPrefillJS(prefill: PrefillResponse?) -> String {
        let encoder = JSONEncoder()
        let canonicalMap: [String: String] = {
            var out = prefill?.canonical ?? [:]
            // Hydrate from the legacy `profile` bundle for older backends.
            if let p = prefill?.profile {
                if out["first_name"]    == nil, !p.firstName.isEmpty    { out["first_name"]    = p.firstName }
                if out["last_name"]     == nil, !p.lastName.isEmpty     { out["last_name"]     = p.lastName }
                if out["full_name"]     == nil, !p.fullName.isEmpty     { out["full_name"]     = p.fullName }
                if out["email"]         == nil, !p.email.isEmpty        { out["email"]         = p.email }
                if out["phone"]         == nil, !p.phone.isEmpty        { out["phone"]         = p.phone }
                if out["city"]          == nil, !p.city.isEmpty         { out["city"]          = p.city }
                if out["linkedin_url"]  == nil, !p.linkedInUrl.isEmpty  { out["linkedin_url"]  = p.linkedInUrl }
                if out["github_url"]    == nil, !p.githubUrl.isEmpty    { out["github_url"]    = p.githubUrl }
                if out["portfolio_url"] == nil, !p.portfolioUrl.isEmpty { out["portfolio_url"] = p.portfolioUrl }
            }
            return out
        }()
        let rawHistory = prefill?.rawHistory ?? prefill?.fieldHistory ?? [:]

        let canonicalJSON = (try? encoder.encode(canonicalMap)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let historyJSON   = (try? encoder.encode(rawHistory)).flatMap   { String(data: $0, encoding: .utf8) } ?? "{}"

        return """
        (function() {
          // AUDIT P1-6: no autofill of any kind off the ATS allowlist.
          \(ATSAutofillPolicy.hostGateJS)
          if (window.__jobtokAutofillInstalled) return;
          window.__jobtokAutofillInstalled = true;

          var canonical = \(canonicalJSON);
          var rawHistory = \(historyJSON);

          // Each canonical key has a set of label patterns it answers to.
          // Kept short on purpose — the broader ATS-specific selectors live
          // server-side in _shared/profile_fields.ts heuristics.
          var CANON_PATTERNS = {
            first_name:       ['first name','given name'],
            last_name:        ['last name','surname','family name'],
            full_name:        ['full name','your name','name'],
            email:            ['email'],
            phone:            ['phone','mobile','cell'],
            city:             ['city','town'],
            state:            ['state','province','region'],
            country:          ['country'],
            postal_code:      ['zip','postal'],
            linkedin_url:     ['linkedin'],
            github_url:       ['github'],
            portfolio_url:    ['portfolio'],
            personal_website: ['website','personal site'],
            twitter_url:      ['twitter','x handle','x profile'],
            current_title:    ['current title','job title','current job title'],
            current_company:  ['current employer','current company','employer'],
            years_experience: ['years of experience','experience (years)'],
            highest_degree:   ['highest level of education','highest degree','degree'],
            school:           ['school','university','college','institution'],
            graduation_year:  ['graduation year','grad year'],
            field_of_study:   ['major','field of study','concentration'],
            work_authorization: ['work authorization','authorized to work','work eligibility'],
            requires_sponsorship: ['sponsorship','visa sponsorship'],
            salary_expectation: ['salary expectation','desired salary','compensation expectation'],
            available_start_date: ['start date','available to start'],
            preferred_location: ['preferred location','where would you like to work'],
            willing_to_relocate: ['relocate','relocation'],
            remote_preference: ['remote','work from home'],
            pronouns:         ['pronouns'],
            referral_source:  ['referred by','referral source'],
            how_did_you_hear: ['how did you hear','how do you hear']
          };

          function nativeSet(el, value) {
            if (!el || value == null || value === '') return;
            var proto = el instanceof HTMLTextAreaElement
              ? window.HTMLTextAreaElement.prototype
              : window.HTMLInputElement.prototype;
            var setter = Object.getOwnPropertyDescriptor(proto, 'value');
            if (setter && setter.set) setter.set.call(el, value);
            else el.value = value;
            el.dispatchEvent(new Event('input', { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
          }

          function labelFor(el) {
            if (!el) return '';
            if (el.id) {
              var l = document.querySelector('label[for="' + el.id + '"]');
              if (l && l.textContent) return l.textContent.trim();
            }
            var parentLabel = el.closest('label');
            if (parentLabel && parentLabel.textContent) return parentLabel.textContent.trim();
            return (el.getAttribute('aria-label') || el.placeholder || el.name || '').trim();
          }

          // AUDIT P1-6: CSS-hidden fields are neither filled nor captured —
          // a hostile page can't plant invisible "email"/"salary" inputs,
          // let the prefill populate them, and read them back on submit.
          function isVisible(el) {
            if (!el) return false;
            var rect = el.getBoundingClientRect();
            if (rect.width < 1 || rect.height < 1) return false;
            if (typeof el.checkVisibility === 'function') {
              return el.checkVisibility({ checkOpacity: true, checkVisibilityCSS: true });
            }
            var style = window.getComputedStyle(el);
            return style.display !== 'none'
              && style.visibility !== 'hidden'
              && parseFloat(style.opacity) > 0;
          }

          // EEO / protected-class questions are neither filled nor captured.
          // Gating here covers every path at once: the fill pass, the essay
          // collector, fillEssayMatch, and the submit capture all go through
          // isFillable.
          var SENSITIVE_LABEL_PATTERNS = \(ATSAutofillPolicy.sensitivePatternsJSArray);

          function isSensitiveLabel(label) {
            if (!label) return false;
            for (var i = 0; i < SENSITIVE_LABEL_PATTERNS.length; i++) {
              if (SENSITIVE_LABEL_PATTERNS[i].test(label)) return true;
            }
            return false;
          }

          function isFillable(el) {
            if (!el) return false;
            if (el.disabled || el.readOnly) return false;
            if (el.type === 'password' || el.type === 'hidden' || el.type === 'file' ||
                el.type === 'submit' || el.type === 'button') return false;
            if (isSensitiveLabel(labelFor(el))) return false;
            return isVisible(el);
          }

          function matchesPattern(label, patterns) {
            var lower = label.toLowerCase();
            for (var i = 0; i < patterns.length; i++) {
              if (lower.indexOf(patterns[i]) !== -1) return true;
            }
            return false;
          }

          function runPrefill() {
            var inputs = document.querySelectorAll('input, textarea, select');
            inputs.forEach(function(el) {
              if (!isFillable(el)) return;
              if (el.value && el.value.trim().length > 0) return;  // user already typed
              var label = labelFor(el);
              if (!label) return;

              // 1. Canonical match wins — survives ATS swaps.
              for (var key in CANON_PATTERNS) {
                if (matchesPattern(label, CANON_PATTERNS[key]) && canonical[key]) {
                  nativeSet(el, canonical[key]);
                  return;
                }
              }
              // 2. Verbatim raw-label match for repeat visits to the same ATS.
              if (rawHistory[label]) {
                nativeSet(el, rawHistory[label]);
                return;
              }
            });

            // Report textarea-style questions back to native so it can fetch
            // similarity matches and prefill them via fillEssayMatch(...).
            var essayQuestions = [];
            document.querySelectorAll('textarea').forEach(function(ta) {
              if (!isFillable(ta) || (ta.value && ta.value.trim().length > 0)) return;
              var label = labelFor(ta);
              if (label && label.length > 8) {
                essayQuestions.push({
                  question: label,
                  selector: cssPath(ta)
                });
              }
            });
            if (essayQuestions.length > 0 &&
                window.webkit && window.webkit.messageHandlers.essayQuestionsFound) {
              window.webkit.messageHandlers.essayQuestionsFound.postMessage({
                questions: essayQuestions
              });
            }
          }

          // Native calls this back after match-essay-answer returns. We don't
          // overwrite if the user already typed something — the prefill is
          // a suggestion, not an assertion.
          window.fillEssayMatch = function(selector, value) {
            try {
              var el = document.querySelector(selector);
              if (el && isFillable(el) && (!el.value || el.value.trim() === '')) {
                nativeSet(el, value);
              }
            } catch (e) { /* swallow — bad selector shouldn't crash the page */ }
          };

          // Stable enough CSS path for our purposes: tag + id + nth-of-type chain.
          function cssPath(el) {
            if (!(el instanceof Element)) return '';
            var path = [];
            while (el && el.nodeType === 1 && path.length < 6) {
              var sel = el.nodeName.toLowerCase();
              if (el.id) { sel += '#' + el.id; path.unshift(sel); break; }
              var sibling = el, nth = 1;
              while ((sibling = sibling.previousElementSibling) != null) {
                if (sibling.nodeName.toLowerCase() === el.nodeName.toLowerCase()) nth++;
              }
              sel += ':nth-of-type(' + nth + ')';
              path.unshift(sel);
              el = el.parentElement;
            }
            return path.join(' > ');
          }

          // Capture-on-submit: split textareas (essays) from inputs (short fields).
          document.addEventListener('submit', function() {
            var shortFields = [];
            var essays = [];
            document.querySelectorAll('input, textarea, select').forEach(function(el) {
              if (!isFillable(el)) return;
              var value = (el.value || '').trim();
              if (!value) return;
              var label = labelFor(el);
              if (!label) return;
              if (el.tagName === 'TEXTAREA' && value.length >= 200) {
                essays.push({ question: label, answer: value });
              } else {
                shortFields.push({ label: label, value: value });
              }
            });
            if (window.webkit && window.webkit.messageHandlers.formSubmitted) {
              window.webkit.messageHandlers.formSubmitted.postMessage({
                shortFields: shortFields,
                essays: essays,
                url: window.location.href
              });
            }
          }, true);

          // Initial pass; the SPA observer re-triggers it after route changes.
          runPrefill();
          window.__jobtokRunPrefill = runPrefill;
        })();
        """
    }

    private var spaObserverJS: String {
        // Watch for SPA-style route changes (Workday, Lever) and re-run prefill
        // after the new form mounts. Throttled to avoid hammering on every DOM tick.
        return """
        (function() {
          // AUDIT P1-6: same host gate as the prefill script.
          \(ATSAutofillPolicy.hostGateJS)
          var lastUrl = location.href;
          var timer = null;
          var obs = new MutationObserver(function() {
            if (location.href !== lastUrl) {
              lastUrl = location.href;
              clearTimeout(timer);
              timer = setTimeout(function() {
                if (typeof window.__jobtokRunPrefill === 'function') {
                  window.__jobtokRunPrefill();
                }
                if (window.webkit && window.webkit.messageHandlers.spaNavigation) {
                  window.webkit.messageHandlers.spaNavigation.postMessage({ url: location.href });
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
        let session: AuthSession
        let service: CandidateService
        let onSubmitted: (CapturedSubmission) -> Void
        var prefillJS: String = ""
        weak var webView: WKWebView?
        private var hasReportedSubmission = false
        // Same question on the same form shouldn't trigger N round-trips per
        // SPA tick. Keyed by selector+question.
        private var essayLookupsInFlight = Set<String>()

        init(session: AuthSession, service: CandidateService, onSubmitted: @escaping (CapturedSubmission) -> Void) {
            self.session = session
            self.service = service
            self.onSubmitted = onSubmitted
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "formSubmitted":
                guard !hasReportedSubmission else { return }
                hasReportedSubmission = true
                let body = message.body as? [String: Any]
                let shorts = (body?["shortFields"] as? [[String: String]] ?? []).compactMap { dict -> ApplicationShortField? in
                    guard let label = dict["label"], let value = dict["value"] else { return nil }
                    return ApplicationShortField(label: label, value: value)
                }
                let essays = (body?["essays"] as? [[String: String]] ?? []).compactMap { dict -> ApplicationEssay? in
                    guard let q = dict["question"], let a = dict["answer"] else { return nil }
                    return ApplicationEssay(question: q, answer: a)
                }
                DispatchQueue.main.async {
                    self.onSubmitted(CapturedSubmission(shortFields: shorts, essays: essays))
                }

            case "essayQuestionsFound":
                let body = message.body as? [String: Any]
                let questions = body?["questions"] as? [[String: String]] ?? []
                for q in questions {
                    guard let question = q["question"], let selector = q["selector"] else { continue }
                    let key = "\(selector)|\(question)"
                    if essayLookupsInFlight.contains(key) { continue }
                    essayLookupsInFlight.insert(key)
                    Task { [weak self] in
                        await self?.lookupEssay(question: question, selector: selector)
                    }
                }

            case "spaNavigation":
                // Prefill already re-ran via window.__jobtokRunPrefill; nothing
                // else to do here.
                return

            default:
                return
            }
        }

        private func lookupEssay(question: String, selector: String) async {
            let match = try? await service.matchEssayAnswer(question: question, session: session)
            guard let match else { return }
            let escapedSelector = jsString(selector)
            let escapedValue = jsString(match.answer)
            let js = "window.fillEssayMatch && window.fillEssayMatch(\(escapedSelector), \(escapedValue));"
            await MainActor.run {
                self.webView?.evaluateJavaScript(js, completionHandler: nil)
            }
        }

        private func jsString(_ s: String) -> String {
            let escaped = s
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            return "\"\(escaped)\""
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            // Non-fatal; webview renders its own error page.
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // The @atDocumentEnd user script already injected prefill code; no
            // need to re-evaluate prefillJS here (would risk double-install).
            // We do trigger a re-run in case the page mutated between
            // document-end and load completion.
            webView.evaluateJavaScript(
                "window.__jobtokRunPrefill && window.__jobtokRunPrefill();",
                completionHandler: nil
            )
        }
    }
}
