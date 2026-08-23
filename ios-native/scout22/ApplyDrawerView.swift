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
    case icims      = "icims"
    case taleo      = "taleo"
    case workable   = "workable"
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
        // myworkdayjobs.com is the candidate-facing domain; myworkday.com is
        // the internal tenant one. Both exist in the wild.
        if matches("myworkdayjobs.com") || matches("myworkdaysite.com")
            || matches("myworkday.com") || matches("workday.com") { return .workday }
        if matches("ashbyhq.com")    { return .ashby }
        if matches("smartrecruiters.com") { return .smartrecruiters }
        if matches("recruitee.com")  { return .recruitee }
        if matches("icims.com")      { return .icims }
        if matches("taleo.net")      { return .taleo }
        if matches("workable.com")   { return .workable }
        if matches("rippling.com")   { return .rippling }
        return .other
    }

    var isBlocked: Bool { self == .rippling }
}

/// AUDIT P1-6: autofill (fill AND capture) runs only on known ATS domains —
/// matched as exact host or dot-suffix, mirrored into the injected JS. Any
/// other host gets no prefill, no submit capture, no message posts, visible
/// fields or not.
///
/// Entries are registrable domains only; suffix matching covers every
/// subdomain, so `greenhouse.io` already admits `boards.greenhouse.io` and
/// `job-boards.greenhouse.io`.
///
/// One exception is granted at runtime and never from this list: an ATS that
/// *redirects* an allowlisted apply URL onto the employer's own domain
/// (Greenhouse does this for customers with a custom careers domain, e.g.
/// boards.greenhouse.io/cookunity → careers.cookunity.com). `ApplyWebView`
/// resolves that redirect chain and activates the engine explicitly. The
/// chain must still START on an allowlisted host, so a scraped apply_url
/// pointing straight at an attacker domain stays inert.
enum ATSAutofillPolicy {
    static let allowedDomains: [String] = [
        "greenhouse.io",
        "lever.co",
        "ashbyhq.com",
        "myworkdayjobs.com",
        "myworkdaysite.com",
        "myworkday.com",
        "workday.com",
        "smartrecruiters.com",
        "recruitee.com",
        "rippling.com",
        "icims.com",
        "taleo.net",
        "workable.com",
        "jobvite.com",
        "breezy.hr",
        "bamboohr.com",
        "applytojob.com",
        "avature.net",
        "successfactors.com",
        "successfactors.eu",
        "oraclecloud.com",
        "dayforcehcm.com",
        "eightfold.ai",
        "phenompeople.com",
        "paylocity.com",
        "teamtailor.com",
        "pinpointhq.com",
        "personio.de",
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

    /// Text on a control that genuinely submits an application.
    ///
    /// "apply" is deliberately NOT here. On a two-page gateway (Ashby,
    /// Lever, Greenhouse) the button reading "Apply for this job" OPENS the
    /// form — treating it as a submission reported applications the candidate
    /// never sent, and closed the sheet on them mid-apply.
    static let strongSubmitPattern =
        "\\b(submit|send application|finish application|complete application)\\b"

    /// Ambiguous: some portals really do label the final button "Apply now".
    /// Only counts as a submission when the control sits inside a form that is
    /// already filled in, which a gateway's apply link never is.
    static let weakSubmitPattern = "\\b(apply)\\b"

    static func isStrongSubmitLabel(_ label: String?) -> Bool {
        matches(label, strongSubmitPattern)
    }

    static func isWeakSubmitLabel(_ label: String?) -> Bool {
        matches(label, weakSubmitPattern)
    }

    private static func matches(_ label: String?, _ pattern: String) -> Bool {
        guard let label, !label.isEmpty else { return false }
        return label.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The same two patterns as JS regex literals, for the injected engine.
    static var submitPatternsJS: String {
        """
        var STRONG_SUBMIT_RE = /\(strongSubmitPattern)/;
          var WEAK_SUBMIT_RE = /\(weakSubmitPattern)/;
        """
    }

    /// Defines `__scoutHostAllowed(host)` in the injected scope. The engine
    /// self-activates when it returns true; otherwise it stays dormant until
    /// native calls `__scoutActivate()` for a resolved redirect target.
    static var hostAllowedJS: String {
        """
        var ATS_DOMAINS = \(domainsJSArray);
        function __scoutHostAllowed(host) {
          var h = String(host || '').toLowerCase();
          if (!h) return false;
          for (var i = 0; i < ATS_DOMAINS.length; i++) {
            var d = ATS_DOMAINS[i];
            if (h === d || h.slice(-(d.length + 1)) === '.' + d) return true;
          }
          return false;
        }
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
    /// Latest field map the page has reported. Held in memory only; it is sent
    /// to the backend when a submission is confirmed, never before.
    @State private var buffer = CapturedSubmission(shortFields: [], essays: [])
    @State private var askingDidSubmit = false
    @State private var isSaving = false
    @State private var resumeBase64: String?
    @State private var resumeFileName: String?

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
                            resumeBase64: resumeBase64,
                            resumeFileName: resumeFileName,
                            session: session,
                            service: service,
                            onBuffered: { buffer = $0 },
                            onSubmitted: { handleSubmission(payload: $0) }
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
                    Button("Close") { attemptClose() }
                }
            }
            .overlay {
                if submittedSuccessfully {
                    submittedBanner
                }
            }
            // Detection can miss on an unusual portal. If the candidate typed
            // real answers and we never saw a submission, ask rather than lose
            // the application — this is the difference between a tracker that
            // works and one that silently under-reports.
            .confirmationDialog(
                "Did you submit this application?",
                isPresented: $askingDidSubmit,
                titleVisibility: .visible
            ) {
                Button("Yes, I submitted it") {
                    handleSubmission(payload: buffer, confirmedByUser: true)
                }
                Button("Not yet") { isPresented = false }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("We'll save your answers so you never have to type them again, and add it to your applications.")
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
                Text(isSaving ? "Saving your answers…" : "Application submitted!")
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

    private func attemptClose() {
        // Two answered fields is the threshold for "they were really applying".
        if !submittedSuccessfully, buffer.shortFields.count + buffer.essays.count >= 2 {
            askingDidSubmit = true
        } else {
            isPresented = false
        }
    }

    private func loadPrefillAndLogOpen() async {
        async let prefillTask = fetchPrefill()
        async let eventTask = logEvent(type: "opened", applicationId: nil)
        async let resumeTask = fetchResume()
        let (p, eid, r) = await (prefillTask, eventTask, resumeTask)
        prefill = p
        eventId = eid
        resumeBase64 = r?.base64
        resumeFileName = r?.fileName
    }

    /// Resume bytes for auto-attach. Capped: a resume larger than this is not a
    /// resume, and base64 of it would bloat the evaluateJavaScript payload.
    private static let maxResumeBytes = 8 * 1024 * 1024

    private func fetchResume() async -> (base64: String, fileName: String)? {
        guard let resume = try? await service.downloadLatestResume(session: session),
              resume.data.count <= Self.maxResumeBytes else { return nil }
        return (resume.data.base64EncodedString(), resume.fileName)
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

    private func handleSubmission(payload: CapturedSubmission, confirmedByUser: Bool = false) {
        guard !submittedSuccessfully else { return }
        submittedSuccessfully = true
        isSaving = true
        Task {
            // AUDIT P1-2: always log the submitted funnel event. Logging it is
            // also what records the application on the Applications tab —
            // log-application-event writes the ats_apply job_applications row.
            let submittedEventId = await logEvent(type: "submitted", applicationId: nil)
            // Prefer the richer of the two: a live walk at submit time can be
            // empty if the ATS already tore the form down, in which case the
            // buffered map is all we have.
            let fields = payload.shortFields.isEmpty && payload.essays.isEmpty ? buffer : payload
            if let eid = submittedEventId ?? eventId,
               !fields.shortFields.isEmpty || !fields.essays.isEmpty {
                try? await service.storeApplicationFields(
                    eventID: eid,
                    shortFields: fields.shortFields,
                    essays: fields.essays,
                    session: session
                )
            }
            isSaving = false
            try? await Task.sleep(nanoseconds: confirmedByUser ? 1_200_000_000 : 2_500_000_000)
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
    let resumeBase64: String?
    let resumeFileName: String?
    let session: AuthSession
    let service: CandidateService
    let onBuffered: (CapturedSubmission) -> Void
    let onSubmitted: (CapturedSubmission) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            initialHostAllowed: ATSAutofillPolicy.isHostAllowed(url.host),
            session: session,
            service: service,
            onBuffered: onBuffered,
            onSubmitted: onSubmitted
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        for name in ["scoutSubmitted", "scoutFields", "scoutEssayQuestions", "scoutLog"] {
            config.userContentController.add(context.coordinator, name: name)
        }

        // .atDocumentStart, not .atDocumentEnd: the engine patches fetch/XHR to
        // detect submissions, and an SPA that grabs `window.fetch` at load time
        // would otherwise keep the unpatched reference. It also means the
        // engine is installed before React mounts, so its MutationObserver
        // sees the form appear.
        config.userContentController.addUserScript(
            WKUserScript(
                source: engineJS,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )

        // Several ATS serve a degraded form to mobile UAs (Workday in
        // particular drops field labels), which starves label matching.
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
            + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = webView
        webView.load(URLRequest(url: url))
        return webView
    }

    // The profile and resume both arrive asynchronously, after the WebView is
    // already on screen. This is the only hook that sees them.
    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.setProfileJS(ApplyWebView.profileJS(prefill: prefill), webView: webView)
        context.coordinator.setResume(base64: resumeBase64, fileName: resumeFileName, webView: webView)
    }

    // MARK: - JS builder

    /// The `__scoutSetProfile(...)` call carrying this candidate's answers.
    /// Separate from the engine script on purpose: the engine is injected at
    /// document-start, but the profile only exists once get-prefill-profile
    /// returns, which is strictly later. Baking it into the script was why
    /// nothing ever filled.
    static func profileJS(prefill: PrefillResponse?) -> String? {
        guard let prefill else { return nil }
        let encoder = JSONEncoder()
        let canonicalMap: [String: String] = {
            var out = prefill.canonical ?? [:]
            // Hydrate from the legacy `profile` bundle for older backends.
            let p = prefill.profile
            do {
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
        let rawHistory = prefill.rawHistory ?? prefill.fieldHistory

        let canonicalJSON = (try? encoder.encode(canonicalMap)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let historyJSON   = (try? encoder.encode(rawHistory)).flatMap   { String(data: $0, encoding: .utf8) } ?? "{}"
        if canonicalJSON == "{}" && historyJSON == "{}" { return nil }
        return "window.__scoutSetProfile && window.__scoutSetProfile(\(canonicalJSON), \(historyJSON));"
    }

    private var engineJS: String {
        """
        (function() {
          if (window.__scoutEngineInstalled) return;
          window.__scoutEngineInstalled = true;

          \(ATSAutofillPolicy.hostAllowedJS)

          // Filled in by native through __scoutSetProfile once
          // get-prefill-profile returns. They MUST start empty: this script is
          // injected at document-start, long before that fetch completes, so
          // baking the values in here would freeze them as {} forever.
          var CANONICAL   = {};
          var RAW_HISTORY = {};
          var RAW_INDEX   = {};
          var SENSITIVE   = \(ATSAutofillPolicy.sensitivePatternsJSArray);
          var ESSAY_MIN   = 200;

          // Canonical key -> normalized label fragments it answers to. Kept
          // deliberately small; a verbatim prior answer always wins over these.
          var CANON_PATTERNS = {
            first_name:       ['first name','given name','forename'],
            last_name:        ['last name','surname','family name'],
            email:            ['email','e mail'],
            phone:            ['phone','mobile','cell number','telephone'],
            city:             ['city','town'],
            state:            ['state','province','region'],
            country:          ['country'],
            postal_code:      ['zip','postal'],
            linkedin_url:     ['linkedin'],
            github_url:       ['github'],
            portfolio_url:    ['portfolio'],
            personal_website: ['website','personal site'],
            twitter_url:      ['twitter','x handle','x profile'],
            current_title:    ['current title','job title','current job title','current role'],
            current_company:  ['current employer','current company','employer'],
            years_experience: ['years of experience','experience years'],
            highest_degree:   ['highest level of education','highest degree','degree'],
            school:           ['school','university','college','institution'],
            graduation_year:  ['graduation year','grad year'],
            field_of_study:   ['major','field of study','concentration','discipline'],
            work_authorization: ['work authorization','authorized to work','work eligibility','legally authorized'],
            requires_sponsorship: ['sponsorship','visa sponsor'],
            salary_expectation: ['salary expectation','desired salary','compensation expectation','expected salary'],
            available_start_date: ['start date','available to start'],
            preferred_location: ['preferred location','where would you like to work'],
            willing_to_relocate: ['relocate','relocation'],
            remote_preference: ['remote','work from home'],
            commute_ok:       ['commute','commuting','onsite','on site','in office','hybrid'],
            pronouns:         ['pronouns'],
            referral_source:  ['referred by','referral source'],
            how_did_you_hear: ['how did you hear','how do you hear']
          };
          // 'name' alone is too greedy to live in the table above ("name of
          // school" would win full_name), so it is matched exactly.
          var FULL_NAME_EXACT = ['name','full name','your name','legal name'];

          // ---------- utilities ----------

          function post(name, body) {
            try {
              if (window.webkit && window.webkit.messageHandlers &&
                  window.webkit.messageHandlers[name]) {
                window.webkit.messageHandlers[name].postMessage(body);
              }
            } catch (e) { /* handler gone; nothing to do */ }
          }
          function log(msg) { post('scoutLog', String(msg).slice(0, 400)); }

          function norm(s) {
            return String(s == null ? '' : s)
              .toLowerCase()
              .replace(/[\\u2018\\u2019']/g, '')
              .replace(/[^a-z0-9]+/g, ' ')
              .trim();
          }
          function text(el) {
            if (!el) return '';
            return (el.textContent || '')
              .replace(/\\s+/g, ' ')
              .replace(/[*\\u2731]/g, '')
              .replace(/\\(required\\)/ig, '')
              .replace(/\\brequired\\b/ig, '')
              .trim();
          }
          function esc(s) {
            if (window.CSS && CSS.escape) return CSS.escape(s);
            return String(s).replace(/["\\\\]/g, '\\\\$&');
          }
          function isSensitive(label) {
            if (!label) return false;
            for (var i = 0; i < SENSITIVE.length; i++) {
              if (SENSITIVE[i].test(label)) return true;
            }
            return false;
          }

          // AUDIT P1-6: CSS-hidden fields are neither filled nor captured — a
          // hostile page can't plant invisible "email"/"salary" inputs, let the
          // prefill populate them, and read them back on submit.
          function isVisible(el) {
            try {
              var rect = el.getBoundingClientRect();
              if (rect.width < 1 || rect.height < 1) return false;
              if (typeof el.checkVisibility === 'function') {
                return el.checkVisibility({ checkOpacity: true, checkVisibilityCSS: true });
              }
              var style = window.getComputedStyle(el);
              return style.display !== 'none'
                && style.visibility !== 'hidden'
                && parseFloat(style.opacity) > 0;
            } catch (e) { return false; }
          }

          function isEligible(el) {
            if (!el || !el.tagName) return false;
            var t = (el.type || '').toLowerCase();
            if (t === 'password' || t === 'hidden' || t === 'file' ||
                t === 'submit' || t === 'button' || t === 'reset' || t === 'image') return false;
            if (isSensitive(labelFor(el))) return false;
            return isVisible(el);
          }
          function isFillable(el) {
            if (el.disabled || el.readOnly) return false;
            return isEligible(el);
          }
          // Capture is laxer than fill: some ATS mark typeahead results
          // readonly after selection, and that value is exactly what we want.
          function isCapturable(el) {
            if (el.disabled) return false;
            return isEligible(el);
          }

          // ---------- labelling ----------

          function ownLabel(el) {
            try {
              if (el.id) {
                var l = document.querySelector('label[for="' + esc(el.id) + '"]');
                if (l && text(l)) return text(l);
              }
              var p = el.closest ? el.closest('label') : null;
              if (p && text(p)) return text(p);
              var ariaLabelledBy = el.getAttribute('aria-labelledby');
              if (ariaLabelledBy) {
                var e = document.getElementById(ariaLabelledBy);
                if (e && text(e)) return text(e);
              }
              return (el.getAttribute('aria-label') || el.getAttribute('placeholder') || el.name || '').trim();
            } catch (e) { return ''; }
          }

          // For a radio/checkbox the useful label is the QUESTION, not the
          // option ("Are you willing to commute?", not "Yes"). Walk up to the
          // fieldset legend / group aria-label, else the nearest ancestor
          // carrying question text that doesn't contain this input.
          function groupLabel(el) {
            try {
              var fs = el.closest('fieldset');
              if (fs) {
                var lg = fs.querySelector('legend');
                if (lg && text(lg)) return text(lg);
              }
              var rg = el.closest('[role="radiogroup"],[role="group"]');
              if (rg) {
                var al = rg.getAttribute('aria-label');
                if (al && al.trim()) return al.trim();
                var lb = rg.getAttribute('aria-labelledby');
                if (lb) {
                  var e = document.getElementById(lb);
                  if (e && text(e)) return text(e);
                }
              }
              var c = el.parentElement;
              for (var i = 0; i < 5 && c; i++) {
                var cand = c.querySelector('legend, label:not([for]), [class*="label"], [class*="question"], [class*="Label"], [class*="Question"]');
                if (cand && !cand.contains(el)) {
                  var t = text(cand);
                  if (t.length > 5) return t;
                }
                c = c.parentElement;
              }
            } catch (e) { /* fall through */ }
            return '';
          }

          function labelFor(el) {
            var t = (el.type || '').toLowerCase();
            if (t === 'radio' || t === 'checkbox') return groupLabel(el) || ownLabel(el);
            return ownLabel(el);
          }

          // ---------- reading values ----------

          function readValue(el) {
            try {
              if (el.tagName === 'SELECT') {
                var o = el.selectedOptions && el.selectedOptions[0];
                if (!o) return '';
                var t = text(o);
                // Skip the placeholder option ("Select...", "-- Choose --").
                if (!t || /^(select|choose|please select|--)/i.test(t)) return '';
                return t;
              }
              var ty = (el.type || '').toLowerCase();
              if (ty === 'radio' || ty === 'checkbox') {
                return el.checked ? (ownLabel(el) || el.value || '') : '';
              }
              return (el.value || '').trim();
            } catch (e) { return ''; }
          }

          // ---------- writing values ----------

          function fire(el) {
            el.dispatchEvent(new Event('input',  { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
          }

          // React tracks its own value on the DOM node, so writing .value
          // directly is ignored on re-render. Going through the prototype's
          // native setter is what makes controlled inputs accept the write.
          // The prototype MUST match the element type: calling the
          // HTMLInputElement setter on a <select> throws, and an uncaught
          // throw here used to abort the whole fill pass.
          function setNative(el, value) {
            var proto = el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype
                      : el instanceof HTMLSelectElement   ? HTMLSelectElement.prototype
                      : HTMLInputElement.prototype;
            var d = Object.getOwnPropertyDescriptor(proto, 'value');
            if (d && d.set) d.set.call(el, value); else el.value = value;
            fire(el);
          }

          // Never set .value on a <select> — it must match an option's value
          // attribute, which is usually an opaque id. Match on visible text.
          function fillSelect(el, value) {
            var want = norm(value);
            if (!want) return false;
            var opts = el.options || [], best = -1;
            for (var i = 0; i < opts.length; i++) {
              if (norm(text(opts[i])) === want) { best = i; break; }
            }
            if (best < 0) {
              for (var j = 0; j < opts.length; j++) {
                var t = norm(text(opts[j]));
                if (!t || /^(select|choose|please select)/.test(t)) continue;
                if (t.indexOf(want) === 0 || want.indexOf(t) === 0) { best = j; break; }
              }
            }
            if (best < 0) return false;
            el.selectedIndex = best;
            fire(el);
            return true;
          }

          // Setting .checked skips React's handler; clicking the label works
          // everywhere and also drives custom-styled controls.
          function fillChoice(el, value) {
            var want = norm(value);
            if (!want || !el.name) return false;
            var scope = el.form || document;
            var members = scope.querySelectorAll(
              'input[type="' + (el.type || 'radio') + '"][name="' + esc(el.name) + '"]');
            for (var i = 0; i < members.length; i++) {
              var m = members[i];
              var t = norm(ownLabel(m) || m.value);
              if (!t) continue;
              if (t === want || t.indexOf(want) === 0 || want.indexOf(t) === 0) {
                if (m.checked) return true;
                var lab = m.id ? document.querySelector('label[for="' + esc(m.id) + '"]') : null;
                if (lab) lab.click(); else m.click();
                return true;
              }
            }
            return false;
          }

          // ---------- the answer index ----------

          // Native pushes the candidate's profile here, on first load and
          // again after any navigation. RAW_INDEX holds normalized verbatim
          // answers from previous applications: "First Name *" and "First name"
          // collapse to one key, so the same question asked by a different
          // company still matches.
          window.__scoutSetProfile = function (canonical, rawHistory) {
            try {
              CANONICAL = canonical || {};
              RAW_HISTORY = rawHistory || {};
              RAW_INDEX = {};
              for (var k in RAW_HISTORY) {
                var n = norm(k);
                if (n && RAW_HISTORY[k]) RAW_INDEX[n] = RAW_HISTORY[k];
              }
              // New data means the previous "nothing to do" verdict is stale.
              lastSignature = '';
              if (booted) fillIfChanged();
              log('profile: ' + Object.keys(CANONICAL).length + ' canonical, '
                  + Object.keys(RAW_INDEX).length + ' remembered');
            } catch (e) { log('setProfile failed: ' + e); }
          };

          // A screening question is prose, not a field label. Matching short
          // generic tokens inside prose is how "…VoIP telephony and phone
          // systems?" got answered with a phone number and "…located in
          // Guatemala City?" with a home city. Only keys whose patterns are
          // themselves question-shaped may answer a question.
          var SAFE_IN_QUESTIONS = {
            work_authorization: 1, requires_sponsorship: 1, commute_ok: 1,
            willing_to_relocate: 1, remote_preference: 1, salary_expectation: 1,
            available_start_date: 1, how_did_you_hear: 1, referral_source: 1,
            years_experience: 1
          };
          function isQuestionLike(label, n) {
            if (label.indexOf('?') !== -1) return true;
            return n.split(' ').length > 6;
          }
          // Whole-phrase match on a space-normalized label, so 'city' cannot
          // fire inside 'Guatemala City' the way indexOf did.
          function containsPhrase(n, phrase) {
            return (' ' + n + ' ').indexOf(' ' + phrase + ' ') !== -1;
          }

          function lookup(label) {
            var n = norm(label);
            if (!n) return '';
            // A real prior answer beats any canonical guess, at any length.
            if (RAW_INDEX[n]) return RAW_INDEX[n];
            if (CANONICAL.full_name && FULL_NAME_EXACT.indexOf(n) !== -1) return CANONICAL.full_name;
            var question = isQuestionLike(label, n);
            for (var key in CANON_PATTERNS) {
              var v = CANONICAL[key];
              if (!v) continue;
              if (question && !SAFE_IN_QUESTIONS[key]) continue;
              var pats = CANON_PATTERNS[key];
              for (var i = 0; i < pats.length; i++) {
                if (containsPhrase(n, pats[i])) return v;
              }
            }
            return '';
          }

          // ---------- fill pass ----------

          function runPrefill() {
            var els = document.querySelectorAll('input, textarea, select');
            var filled = 0, groupsDone = {};
            for (var i = 0; i < els.length; i++) {
              var el = els[i];
              // Per-field isolation: one hostile or exotic control must never
              // stop the remaining fields from being filled.
              try {
                if (!isFillable(el)) continue;
                var ty = (el.type || '').toLowerCase();
                var isChoice = (ty === 'radio' || ty === 'checkbox');
                if (isChoice) {
                  if (groupsDone[el.name]) continue;
                } else if (el.value && String(el.value).trim().length > 0) {
                  continue;   // the candidate already typed something
                }
                var label = labelFor(el);
                if (!label) continue;
                var value = lookup(label);
                if (!value) continue;

                var ok = false;
                if (el.tagName === 'SELECT') ok = fillSelect(el, value);
                else if (isChoice) { ok = fillChoice(el, value); if (ok) groupsDone[el.name] = true; }
                else { setNative(el, value); ok = true; }
                if (ok) filled++;
              } catch (e) {
                log('fill error: ' + (e && e.message ? e.message : e));
              }
            }
            reportEssayQuestions();
            if (filled > 0) log('filled ' + filled + ' field(s) on ' + location.hostname);
            return filled;
          }

          function reportEssayQuestions() {
            var questions = [];
            try {
              document.querySelectorAll('textarea').forEach(function (ta) {
                if (!isFillable(ta) || (ta.value && ta.value.trim())) return;
                var label = labelFor(ta);
                if (label && label.length > 8) {
                  questions.push({ question: label, selector: cssPath(ta) });
                }
              });
            } catch (e) { /* ignore */ }
            if (questions.length) post('scoutEssayQuestions', { questions: questions });
          }

          // Native calls this back after match-essay-answer returns. We don't
          // overwrite if the candidate already typed something — the prefill is
          // a suggestion, not an assertion.
          window.__scoutFillEssay = function (selector, value) {
            try {
              var el = document.querySelector(selector);
              if (el && isFillable(el) && (!el.value || !el.value.trim())) setNative(el, value);
            } catch (e) { /* bad selector shouldn't crash the page */ }
          };

          // Attach the candidate's resume to the form's file input. Queried
          // directly rather than through isFillable: ATS file inputs are almost
          // always visually hidden behind a styled "Attach" button, so the
          // visibility gate that protects fill/capture would skip every one.
          window.__scoutAttachResume = function (b64, name, mime) {
            try {
              var inputs = document.querySelectorAll('input[type="file"]');
              var target = null;
              for (var i = 0; i < inputs.length; i++) {
                var el = inputs[i];
                if (el.disabled) continue;
                if (el.files && el.files.length > 0) continue;   // already attached
                var hay = norm([el.getAttribute('name'), el.id, ownLabel(el),
                                el.getAttribute('accept')].join(' '));
                if (/resume|cv|attach/.test(hay)) { target = el; break; }
                if (!target) target = el;   // fall back to the first free input
              }
              if (!target) return false;
              var bin = atob(b64), arr = new Uint8Array(bin.length);
              for (var j = 0; j < bin.length; j++) arr[j] = bin.charCodeAt(j);
              var dt = new DataTransfer();
              dt.items.add(new File([arr], name, { type: mime || 'application/pdf' }));
              target.files = dt.files;
              target.dispatchEvent(new Event('input',  { bubbles: true }));
              target.dispatchEvent(new Event('change', { bubbles: true }));
              log('resume attached (' + name + ')');
              return true;
            } catch (e) { log('resume attach failed: ' + e); return false; }
          };

          function cssPath(el) {
            if (!(el instanceof Element)) return '';
            var path = [];
            while (el && el.nodeType === 1 && path.length < 6) {
              var sel = el.nodeName.toLowerCase();
              if (el.id) { sel += '#' + esc(el.id); path.unshift(sel); break; }
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

          // ---------- capture ----------

          var fieldBuffer = {};   // label -> value
          var essayBuffer = {};
          var intentAt = 0;
          var snapshotAtIntent = null;
          var submitReported = false;

          function collect() {
            // Start from the buffer, which survives a teardown the live walk
            // would miss, then overlay whatever is still on the page.
            var shorts = {}, essays = {}, k;
            for (k in fieldBuffer) shorts[k] = fieldBuffer[k];
            for (k in essayBuffer) essays[k] = essayBuffer[k];
            try {
              var els = document.querySelectorAll('input, textarea, select');
              for (var i = 0; i < els.length; i++) {
                try {
                  var el = els[i];
                  if (!isCapturable(el)) continue;
                  var label = labelFor(el);
                  if (!label) continue;
                  var v = readValue(el);
                  if (!v) continue;
                  if (el.tagName === 'TEXTAREA' && v.length >= ESSAY_MIN) essays[label] = v;
                  else shorts[label] = v;
                } catch (e) { /* skip this field */ }
              }
            } catch (e) { /* skip the walk */ }
            return { shortFields: toShortList(shorts), essays: toEssayList(essays) };
          }
          function toShortList(map) {
            var out = [];
            for (var k in map) if (map[k]) out.push({ label: k, value: String(map[k]) });
            return out;
          }
          function toEssayList(map) {
            var out = [];
            for (var k in map) if (map[k]) out.push({ question: k, answer: String(map[k]) });
            return out;
          }

          var flushTimer = null;
          function onEdit(e) {
            try {
              var el = e.target;
              if (!el || !el.tagName) return;
              if (!isCapturable(el)) return;
              var label = labelFor(el);
              if (!label) return;
              var v = readValue(el);
              if (!v) return;
              if (el.tagName === 'TEXTAREA' && v.length >= ESSAY_MIN) essayBuffer[label] = v;
              else fieldBuffer[label] = v;
              clearTimeout(flushTimer);
              flushTimer = setTimeout(function () {
                var c = collect();
                post('scoutFields', { shortFields: c.shortFields, essays: c.essays });
              }, 700);
            } catch (err) { log('buffer error: ' + err); }
          }

          // "Apply for this job" on a two-page gateway OPENS the form — it does
          // not submit one. Treating it as submit intent is how landing on the
          // application page got reported as a completed application.
          \(ATSAutofillPolicy.submitPatternsJS)
          // A real application carries a whole form, not a stray value or two.
          var MIN_SUBMISSION_FIELDS = 3;
          var intentStrong = false;

          function filledFieldCount(scope) {
            var n = 0;
            try {
              var els = (scope || document).querySelectorAll('input, textarea, select');
              for (var i = 0; i < els.length; i++) {
                try { if (isCapturable(els[i]) && readValue(els[i])) n++; } catch (e) {}
              }
            } catch (e) { /* ignore */ }
            return n;
          }

          function noteIntent(strong) {
            intentAt = Date.now();
            intentStrong = !!strong;
            snapshotAtIntent = collect();
          }
          function hasIntent(requireStrong) {
            if (!intentAt || (Date.now() - intentAt) >= 12000) return false;
            return requireStrong ? intentStrong : true;
          }

          function reportSubmission(reason) {
            if (submitReported) return;
            var live = collect();
            var payload = (live.shortFields.length || live.essays.length)
              ? live
              : (snapshotAtIntent || live);
            var count = payload.shortFields.length + payload.essays.length;
            if (!count) return;
            // Confirmation text is self-evidently a submission; everything else
            // has to look like a filled-in application before we believe it.
            if (count < MIN_SUBMISSION_FIELDS && reason !== 'confirmation-text') {
              log('ignored ' + reason + ': only ' + count + ' field(s) — not a submission');
              return;
            }
            submitReported = true;
            post('scoutSubmitted', {
              reason: reason,
              shortFields: payload.shortFields,
              essays: payload.essays,
              url: location.href
            });
          }

          // A successful POST alone means nothing (analytics beacons fire
          // constantly); a successful POST shortly after the candidate pressed
          // an apply/submit control is a submission. This is the only signal
          // that works on an ATS which submits by fetch and never navigates.
          // SPAs POST constantly — analytics, session replay, feature flags,
          // and the form-config fetch that happens when a gateway opens the
          // application page. None of those are submissions.
          var TELEMETRY_RE = new RegExp([
            'analytics','telemetry','segment\\.io','sentry','datadog','amplitude',
            'mixpanel','google-analytics','googletagmanager','doubleclick','hotjar',
            'fullstory','logrocket','statsig','launchdarkly','/log(s)?\\b','/track\\b',
            '/metric(s)?\\b','/event(s)?\\b','/beacon\\b','/collect\\b','/ping\\b'
          ].join('|'), 'i');

          function noteNetworkPost(url) {
            if (url && TELEMETRY_RE.test(String(url))) return;
            if (!hasIntent(true)) return;
            reportSubmission('network');
          }

          function patchNetwork() {
            try {
              var of = window.fetch;
              if (of) {
                window.fetch = function (input, init) {
                  var m = (init && init.method) || (input && input.method) || 'GET';
                  var u = (typeof input === 'string') ? input : (input && input.url) || '';
                  var p = of.apply(this, arguments);
                  try {
                    if (String(m).toUpperCase() === 'POST' && p && p.then) {
                      p.then(function (r) { if (r && r.ok) noteNetworkPost(u || (r && r.url)); },
                             function () {});
                    }
                  } catch (e) { /* ignore */ }
                  return p;
                };
              }
              var oOpen = XMLHttpRequest.prototype.open;
              var oSend = XMLHttpRequest.prototype.send;
              XMLHttpRequest.prototype.open = function (m, u) {
                try { this.__scoutMethod = m; this.__scoutURL = u; } catch (e) {}
                return oOpen.apply(this, arguments);
              };
              XMLHttpRequest.prototype.send = function () {
                var xhr = this;
                try {
                  if (String(xhr.__scoutMethod || '').toUpperCase() === 'POST') {
                    xhr.addEventListener('load', function () {
                      if (xhr.status >= 200 && xhr.status < 300) noteNetworkPost(xhr.__scoutURL);
                    });
                  }
                } catch (e) { /* ignore */ }
                return oSend.apply(this, arguments);
              };
              if (navigator.sendBeacon) {
                var ob = navigator.sendBeacon.bind(navigator);
                // A beacon is telemetry by definition — never a submission.
                navigator.sendBeacon = function () { return ob.apply(null, arguments); };
              }
            } catch (e) { log('patchNetwork failed: ' + e); }
          }

          var CONFIRM_RE = /(thank you for applying|application (has been )?(received|submitted)|thanks for applying|we('| ha)ve received your application|successfully submitted)/i;
          function looksConfirmed() {
            try {
              return CONFIRM_RE.test((document.body && document.body.innerText || '').slice(0, 4000));
            } catch (e) { return false; }
          }

          function installCapture() {
            document.addEventListener('input',  onEdit, true);
            document.addEventListener('change', onEdit, true);

            // Snapshot BEFORE the framework tears the form down.
            document.addEventListener('click', function (e) {
              try {
                var el = e.target && e.target.closest
                  ? e.target.closest('button, input[type="submit"], [role="button"], a')
                  : null;
                if (!el) return;
                var t = norm(text(el) || el.value || el.getAttribute('aria-label') || '');
                if (!t) return;
                if (STRONG_SUBMIT_RE.test(t)) { noteIntent(true); return; }
                if (WEAK_SUBMIT_RE.test(t)) {
                  var form = el.form || (el.closest ? el.closest('form') : null);
                  if (form && filledFieldCount(form) >= 2) noteIntent(true);
                }
              } catch (err) { /* ignore */ }
            }, true);

            // A real form POST: note intent, then let the navigation or the
            // network hook confirm it. Reporting here directly would count
            // submissions that failed client-side validation.
            document.addEventListener('submit', function () { noteIntent(true); }, true);

            window.addEventListener('pagehide', function () {
              if (hasIntent(true)) reportSubmission('pagehide');
            });
          }

          // ---------- readiness + re-arm ----------

          function signature() {
            var parts = [];
            try {
              var els = document.querySelectorAll('input, textarea, select');
              for (var i = 0; i < els.length; i++) {
                if (isFillable(els[i])) parts.push(labelFor(els[i]));
              }
            } catch (e) { /* ignore */ }
            return parts.sort().join('|');
          }

          var lastSignature = '';
          function fillIfChanged() {
            var sig = signature();
            if (!sig || sig === lastSignature) return;
            lastSignature = sig;
            runPrefill();
          }

          // Never a fixed delay: wait for the field count to stop moving, so a
          // client-rendered form is filled the moment it finishes mounting.
          function whenFormReady(cb) {
            var last = -1, stable = 0, tries = 0;
            var t = setInterval(function () {
              tries++;
              var n = document.querySelectorAll('input, textarea, select').length;
              if (n > 0 && n === last) {
                if (++stable >= 3) { clearInterval(t); cb(); return; }
              } else { stable = 0; last = n; }
              if (tries > 100) clearInterval(t);   // give up after ~20s
            }, 200);
          }

          function observe() {
            var timer = null;
            var obs = new MutationObserver(function () {
              clearTimeout(timer);
              timer = setTimeout(function () {
                fillIfChanged();
                if (hasIntent(false) && looksConfirmed()) reportSubmission('confirmation-text');
              }, 400);
            });
            try {
              obs.observe(document.body || document.documentElement,
                          { childList: true, subtree: true });
            } catch (e) { log('observe failed: ' + e); }
          }

          // ---------- activation ----------

          var booted = false;
          function boot() {
            if (booted) return;
            booted = true;
            installCapture();
            whenFormReady(fillIfChanged);
            observe();
            log('engine active on ' + location.hostname);
          }

          window.__scoutActivate = function () {
            if (document.body) boot();
            else document.addEventListener('DOMContentLoaded', boot);
          };
          // Re-run on demand (native calls this after a navigation completes).
          window.__scoutRunPrefill = function () { if (booted) fillIfChanged(); };

          // Patch the network before anything else can capture references,
          // regardless of activation — the patches are inert until intent.
          patchNetwork();

          if (__scoutHostAllowed(location.hostname)) window.__scoutActivate();
        })();
        """
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let session: AuthSession
        let service: CandidateService
        let onBuffered: (CapturedSubmission) -> Void
        let onSubmitted: (CapturedSubmission) -> Void
        weak var webView: WKWebView?

        /// True when the job's own apply URL was on the allowlist. Only then
        /// will we trust a host the ATS redirected us to.
        private let initialHostAllowed: Bool
        /// Host the initial navigation actually landed on after redirects.
        private var resolvedHost: String?
        private var hasReportedSubmission = false
        private var essayLookupsInFlight = Set<String>()
        /// Held so every navigation can be re-seeded: a new document means a
        /// fresh JS context with an empty profile again.
        private var profileJS: String?
        private var resumeJS: String?
        private var isActivated = false

        func setProfileJS(_ js: String?, webView: WKWebView) {
            guard let js, js != profileJS else { return }
            profileJS = js
            if isActivated { webView.evaluateJavaScript(js, completionHandler: nil) }
        }

        func setResume(base64: String?, fileName: String?, webView: WKWebView) {
            guard let base64, let fileName else { return }
            let js = "window.__scoutAttachResume && window.__scoutAttachResume("
                + "\(jsString(base64)), \(jsString(fileName)), \"application/pdf\");"
            guard js != resumeJS else { return }
            resumeJS = js
            if isActivated { webView.evaluateJavaScript(js, completionHandler: nil) }
        }

        init(
            initialHostAllowed: Bool,
            session: AuthSession,
            service: CandidateService,
            onBuffered: @escaping (CapturedSubmission) -> Void,
            onSubmitted: @escaping (CapturedSubmission) -> Void
        ) {
            self.initialHostAllowed = initialHostAllowed
            self.session = session
            self.service = service
            self.onBuffered = onBuffered
            self.onSubmitted = onSubmitted
        }

        /// An employer's own careers domain is trusted only as the resolved
        /// endpoint of a redirect chain that began on a known ATS.
        private func shouldActivate(for host: String?) -> Bool {
            guard let host = host?.lowercased(), !host.isEmpty else { return false }
            if ATSAutofillPolicy.isHostAllowed(host) { return true }
            guard initialHostAllowed else { return false }
            return host == resolvedHost
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "scoutSubmitted":
                guard !hasReportedSubmission else { return }
                hasReportedSubmission = true
                let payload = Self.parseCapture(message.body)
                if let reason = (message.body as? [String: Any])?["reason"] as? String {
                    AppLog.autofill.notice("submission detected via \(reason, privacy: .public)")
                }
                DispatchQueue.main.async { self.onSubmitted(payload) }

            case "scoutFields":
                let payload = Self.parseCapture(message.body)
                DispatchQueue.main.async { self.onBuffered(payload) }

            case "scoutEssayQuestions":
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

            case "scoutLog":
                AppLog.autofill.debug("\(String(describing: message.body))")

            default:
                return
            }
        }

        private static func parseCapture(_ body: Any) -> CapturedSubmission {
            let dict = body as? [String: Any]
            let shorts = (dict?["shortFields"] as? [[String: String]] ?? []).compactMap { d -> ApplicationShortField? in
                guard let label = d["label"], let value = d["value"] else { return nil }
                return ApplicationShortField(label: label, value: value)
            }
            let essays = (dict?["essays"] as? [[String: String]] ?? []).compactMap { d -> ApplicationEssay? in
                guard let q = d["question"], let a = d["answer"] else { return nil }
                return ApplicationEssay(question: q, answer: a)
            }
            return CapturedSubmission(shortFields: shorts, essays: essays)
        }

        private func lookupEssay(question: String, selector: String) async {
            let match = try? await service.matchEssayAnswer(question: question, session: session)
            guard let match else { return }
            let js = "window.__scoutFillEssay && window.__scoutFillEssay(\(jsString(selector)), \(jsString(match.answer)));"
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
            // Non-fatal; the webview renders its own error page.
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let host = webView.url?.host?.lowercased()
            // The first completed navigation defines the redirect endpoint we
            // are willing to trust for the rest of this application.
            if resolvedHost == nil { resolvedHost = host }

            guard shouldActivate(for: host) else {
                AppLog.autofill.notice("inert on \(host ?? "unknown", privacy: .public) — not a known ATS")
                return
            }
            isActivated = true
            // Order matters: activate, seed the profile (which triggers a fill
            // on its own), attach the resume, then sweep once more for any
            // field the seed pass raced.
            var js = "window.__scoutActivate && window.__scoutActivate();\n"
            if let profileJS { js += profileJS + "\n" }
            if let resumeJS  { js += resumeJS  + "\n" }
            js += "window.__scoutRunPrefill && window.__scoutRunPrefill();"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
