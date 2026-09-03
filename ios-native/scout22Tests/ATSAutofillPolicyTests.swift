import XCTest
import JavaScriptCore
@testable import scout22

// AUDIT P1-6: autofill injection is allowlisted to known ATS domains and host
// matching is suffix-based (spoof-resistant).
final class ATSAutofillPolicyTests: XCTestCase {
    func testAllowlistHasNoDuplicatesOrRedundantSubdomains() {
        let domains = ATSAutofillPolicy.allowedDomains
        XCTAssertEqual(Set(domains).count, domains.count, "no duplicates")
        // Suffix matching already admits every subdomain, so listing one is
        // dead weight that hides the real coverage.
        for domain in domains {
            for other in domains where other != domain {
                XCTAssertFalse(
                    domain.hasSuffix("." + other),
                    "\(domain) is redundant — \(other) already covers it by suffix match"
                )
            }
        }
    }

    func testKnownATSHostsAreAllowed() {
        XCTAssertTrue(ATSAutofillPolicy.isHostAllowed("boards.greenhouse.io"))
        XCTAssertTrue(ATSAutofillPolicy.isHostAllowed("job-boards.greenhouse.io"))
        XCTAssertTrue(ATSAutofillPolicy.isHostAllowed("jobs.lever.co"))
        XCTAssertTrue(ATSAutofillPolicy.isHostAllowed("jobs.ashbyhq.com"))
        XCTAssertTrue(ATSAutofillPolicy.isHostAllowed("acme.wd5.myworkday.com"))
        XCTAssertTrue(ATSAutofillPolicy.isHostAllowed("careers.smartrecruiters.com"))
        XCTAssertTrue(ATSAutofillPolicy.isHostAllowed("acme.recruitee.com"))
        XCTAssertTrue(ATSAutofillPolicy.isHostAllowed("GREENHOUSE.IO"), "case-insensitive")
    }

    // Workday serves candidate-facing applications from myworkdayjobs.com, not
    // myworkday.com. Only the latter was listed, so every Workday application
    // silently got no autofill and no capture.
    func testWorkdayCandidateDomainsAreAllowed() {
        XCTAssertTrue(ATSAutofillPolicy.isHostAllowed("cox.wd1.myworkdayjobs.com"))
        XCTAssertTrue(ATSAutofillPolicy.isHostAllowed("acme.wd5.myworkdaysite.com"))
        XCTAssertEqual(
            ATSPlatform.detect(from: URL(string: "https://cox.wd1.myworkdayjobs.com/en-US/cox/job/x")!),
            .workday
        )
    }

    func testOtherHostsGetNoAutofill() {
        XCTAssertFalse(ATSAutofillPolicy.isHostAllowed("example.com"))
        XCTAssertFalse(ATSAutofillPolicy.isHostAllowed("acme-careers.com"))
        XCTAssertFalse(ATSAutofillPolicy.isHostAllowed(nil))
        XCTAssertFalse(ATSAutofillPolicy.isHostAllowed(""))
    }

    func testSpoofedHostsAreRejected() {
        XCTAssertFalse(ATSAutofillPolicy.isHostAllowed("greenhouse.io.evil.com"))
        XCTAssertFalse(ATSAutofillPolicy.isHostAllowed("evilgreenhouse.io"))
        XCTAssertFalse(ATSAutofillPolicy.isHostAllowed("lever.co.attacker.net"))
        XCTAssertFalse(ATSAutofillPolicy.isHostAllowed("notrippling.com"))
    }

    // The exact host test that ships inside the WKUserScript, executed in
    // JavaScriptCore — proves the injected gate agrees with the Swift policy.
    private func injectedGateAllows(host: String) -> Bool {
        let context = JSContext()!
        let js = """
        (function() {
          \(ATSAutofillPolicy.hostAllowedJS)
          return __scoutHostAllowed('\(host)') === true;
        })()
        """
        return context.evaluateScript(js)?.toBool() ?? false
    }

    // S-3: the pattern is shared by Swift and the injected engine, and both
    // sides must agree — one routes a textarea to the letter generator, the
    // other keeps the resume out of a cover-letter file input.
    private func injectedCoverLetterMatches(_ label: String) -> Bool {
        let context = JSContext()!
        let js = """
        (function() {
          \(ATSAutofillPolicy.coverLetterPatternJS)
          return COVER_LETTER_RE.test('\(label)') === true;
        })()
        """
        return context.evaluateScript(js)?.toBool() ?? false
    }

    func testCoverLetterLabelsAreRecognisedOnBothSides() {
        // Every separator an ATS actually uses, plus the norm()'d form.
        let hits = [
            "Cover Letter", "cover letter", "Cover-Letter",
            "cover_letter", "coverLetter", "coverletter",
            "Upload your cover letter (optional)",
        ]
        for label in hits {
            XCTAssertTrue(
                ATSAutofillPolicy.isCoverLetterLabel(label),
                "Swift policy should match \(label)"
            )
            XCTAssertTrue(
                injectedCoverLetterMatches(label),
                "injected regex should match \(label)"
            )
        }
    }

    func testResumeLabelsAreNotCoverLetters() {
        // A false positive here sends the resume nowhere and drops a letter in
        // the resume slot, so the negatives matter as much as the hits.
        for label in ["Resume", "Resume / CV", "Upload CV", "Portfolio", "Letter of recommendation", ""] {
            XCTAssertFalse(
                ATSAutofillPolicy.isCoverLetterLabel(label),
                "Swift policy should not match \(label)"
            )
        }
        for label in ["Resume", "Resume / CV", "Upload CV", "Portfolio", "Letter of recommendation"] {
            XCTAssertFalse(
                injectedCoverLetterMatches(label),
                "injected regex should not match \(label)"
            )
        }
    }

    // No `g` flag: a global regex carries lastIndex between .test() calls and
    // would return alternating results for the same label.
    func testInjectedCoverLetterRegexIsStateless() {
        for _ in 0..<3 {
            XCTAssertTrue(injectedCoverLetterMatches("Cover Letter"))
        }
    }

    func testInjectedJSGateMatchesPolicy() {
        let allowed = [
            "boards.greenhouse.io", "jobs.lever.co", "acme.wd5.myworkday.com",
            "cox.wd1.myworkdayjobs.com", "acme.recruitee.com",
        ]
        for host in allowed {
            XCTAssertTrue(injectedGateAllows(host: host), "\(host) should pass the injected gate")
            XCTAssertTrue(ATSAutofillPolicy.isHostAllowed(host), "Swift policy must agree for \(host)")
        }
        for host in ["example.com", "greenhouse.io.evil.com", "lever.co.attacker.net", ""] {
            XCTAssertFalse(injectedGateAllows(host: host), "\(host) should be stopped by the injected gate")
            XCTAssertFalse(ATSAutofillPolicy.isHostAllowed(host), "Swift policy must agree for \(host)")
        }
    }

    // Every domain in the Swift list must also be accepted by the injected
    // copy — a divergence would mean the app thinks it is filling a form the
    // page-side gate silently refuses (or worse, the reverse).
    func testInjectedGateAgreesOnEveryAllowlistedDomain() {
        for domain in ATSAutofillPolicy.allowedDomains {
            XCTAssertTrue(injectedGateAllows(host: domain), "\(domain) rejected by injected gate")
            XCTAssertTrue(injectedGateAllows(host: "careers." + domain), "subdomain of \(domain) rejected")
            XCTAssertFalse(injectedGateAllows(host: domain + ".evil.com"), "\(domain).evil.com must not pass")
        }
    }

    // EEO / protected-class labels are never filled and never captured, so
    // application_fields can't accumulate GDPR Art. 9 special-category data.
    func testEEOLabelsAreSensitive() {
        for label in [
            "Race", "Race/Ethnicity", "What is your race?", "Ethnicity",
            "Disability Status", "Do you have a disability?",
            "Veteran Status", "Protected Veteran Status",
            "Gender", "Gender Identity", "Sex",
            "Sexual Orientation", "Religion", "Political affiliation",
            "Trade union membership", "Genetic information", "Biometric data",
        ] {
            XCTAssertTrue(ATSAutofillPolicy.isSensitiveLabel(label), "\(label) must be treated as sensitive")
        }
    }

    // Word boundaries keep ordinary fields fillable — a denylist that eats
    // "Essex" or "Embrace" would silently break autofill.
    func testOrdinaryLabelsStayFillable() {
        for label in [
            "First Name", "Email", "Phone", "City", "County (e.g. Essex)",
            "Why do you embrace our mission?", "Field of Study",
            "Work Authorization", "Desired Salary", "LinkedIn", "Pronouns",
            "Racetrack experience", "",
        ] {
            XCTAssertFalse(ATSAutofillPolicy.isSensitiveLabel(label), "\(label) should stay fillable")
        }
        XCTAssertFalse(ATSAutofillPolicy.isSensitiveLabel(nil))
    }

    // The denylist that actually ships is the JS mirror, not the Swift array —
    // execute it the way WebKit will.
    private func injectedJSMarksSensitive(_ label: String) -> Bool {
        let context = JSContext()!
        let js = """
        (function() {
          var SENSITIVE_LABEL_PATTERNS = \(ATSAutofillPolicy.sensitivePatternsJSArray);
          function isSensitiveLabel(label) {
            if (!label) return false;
            for (var i = 0; i < SENSITIVE_LABEL_PATTERNS.length; i++) {
              if (SENSITIVE_LABEL_PATTERNS[i].test(label)) return true;
            }
            return false;
          }
          return isSensitiveLabel('\(label)');
        })()
        """
        return context.evaluateScript(js)?.toBool() ?? false
    }

    func testInjectedJSDenylistMatchesPolicy() {
        for label in ["Race/Ethnicity", "Disability Status", "Veteran Status", "Gender", "Sexual Orientation"] {
            XCTAssertTrue(injectedJSMarksSensitive(label), "\(label) should be blocked by the injected denylist")
            XCTAssertEqual(injectedJSMarksSensitive(label), ATSAutofillPolicy.isSensitiveLabel(label))
        }
        for label in ["First Name", "Email", "County (e.g. Essex)", "Pronouns"] {
            XCTAssertFalse(injectedJSMarksSensitive(label), "\(label) should still autofill")
            XCTAssertEqual(injectedJSMarksSensitive(label), ATSAutofillPolicy.isSensitiveLabel(label))
        }
    }

    // A /g/ regex would make .test() stateful — the same label would flip
    // between blocked and allowed on alternating calls.
    func testInjectedDenylistIsStateless() {
        for _ in 0..<3 {
            XCTAssertTrue(injectedJSMarksSensitive("Race/Ethnicity"))
        }
    }

    func testDetectUsesSuffixMatchingNotContains() {
        func platform(_ urlString: String) -> ATSPlatform {
            ATSPlatform.detect(from: URL(string: urlString)!)
        }
        XCTAssertEqual(platform("https://boards.greenhouse.io/acme/jobs/1"), .greenhouse)
        XCTAssertEqual(platform("https://jobs.lever.co/acme/1"), .lever)
        XCTAssertEqual(platform("https://acme.wd5.myworkday.com/careers"), .workday)
        XCTAssertEqual(platform("https://jobs.ashbyhq.com/acme/1"), .ashby)
        XCTAssertEqual(platform("https://acme.recruitee.com/o/role"), .recruitee)
        XCTAssertEqual(platform("https://ats.rippling.com/acme/jobs/1"), .rippling)
        // The old contains() matching passed all of these:
        XCTAssertEqual(platform("https://greenhouse.io.evil.com/steal"), .other)
        XCTAssertEqual(platform("https://lever.co.attacker.net/x"), .other)
        XCTAssertEqual(platform("https://evilgreenhouse.io/x"), .other)
    }

    // REGRESSION: the engine script is injected at document-start, but the
    // candidate's profile only exists after get-prefill-profile returns. It
    // used to be baked into the script at makeUIView time — when `prefill` was
    // still nil — and updateUIView did nothing, so every page got an empty
    // profile and NOTHING ever autofilled. The profile must travel separately.
    private func samplePrefill(canonical: [String: String]?, raw: [String: String]?) -> PrefillResponse {
        PrefillResponse(
            profile: PrefillProfile(
                firstName: "Wendy", lastName: "Shi", fullName: "Wendy Shi",
                email: "w@example.com", phone: "555-0100", city: "New York",
                linkedInUrl: "", githubUrl: "", portfolioUrl: ""
            ),
            canonical: canonical,
            rawHistory: raw,
            fieldHistory: [:]
        )
    }

    func testProfileJSCarriesTheCandidatesAnswers() {
        let js = ApplyWebView.profileJS(
            prefill: samplePrefill(
                canonical: ["email": "w@example.com"],
                raw: ["Are you willing to commute?": "Yes"]
            )
        )
        let unwrapped = try? XCTUnwrap(js)
        XCTAssertNotNil(unwrapped)
        XCTAssertTrue(js?.contains("__scoutSetProfile") == true, "must call the native-side setter")
        XCTAssertTrue(js?.contains("w@example.com") == true, "canonical values must be carried")
        XCTAssertTrue(js?.contains("Are you willing to commute?") == true, "prior answers must be carried")
    }

    // Falls back to the legacy flat profile bundle, so a candidate with no
    // application history still gets a fill on their very first application.
    func testProfileJSHydratesFromLegacyProfileWhenCanonicalIsEmpty() {
        let js = ApplyWebView.profileJS(prefill: samplePrefill(canonical: [:], raw: [:]))
        XCTAssertNotNil(js)
        XCTAssertTrue(js?.contains("Wendy") == true)
        XCTAssertTrue(js?.contains("555-0100") == true)
    }

    func testProfileJSIsNilBeforeThePrefillArrives() {
        // Nothing to push yet — native must not emit a call that would clobber
        // a profile already in the page with an empty one.
        XCTAssertNil(ApplyWebView.profileJS(prefill: nil))
    }

    // REGRESSION (Perplexity, Ashby, 2026-08-21): the intent regex included
    // "apply", so clicking "Apply for this job" on a two-page gateway counted
    // as submitting. The SPA's route-change POST then confirmed it, the sheet
    // reported success and closed — for an application that was never sent.
    func testGatewayApplyButtonIsNotASubmission() {
        for label in [
            "Apply for this job", "Apply", "Apply now", "Apply to this role",
            "I'm interested", "Continue", "Next",
        ] {
            XCTAssertFalse(
                ATSAutofillPolicy.isStrongSubmitLabel(label),
                "\(label) must not by itself count as submitting"
            )
        }
    }

    func testRealSubmitButtonsAreStrongIntent() {
        for label in [
            "Submit Application", "Submit application", "SUBMIT", "Submit",
            "Send application", "Complete application", "Finish application",
        ] {
            XCTAssertTrue(
                ATSAutofillPolicy.isStrongSubmitLabel(label),
                "\(label) should register as a submission"
            )
        }
    }

    // "Apply now" is still reachable, but only inside an already-filled form —
    // the engine checks that separately. Here we just pin the vocabulary.
    func testApplyIsWeakIntentNotDiscarded() {
        XCTAssertTrue(ATSAutofillPolicy.isWeakSubmitLabel("Apply for this job"))
        XCTAssertTrue(ATSAutofillPolicy.isWeakSubmitLabel("Apply now"))
        XCTAssertFalse(ATSAutofillPolicy.isWeakSubmitLabel("Save for later"))
        XCTAssertFalse(ATSAutofillPolicy.isWeakSubmitLabel(nil))
    }

    // The regexes that actually ship are the JS mirrors — run them the way
    // WebKit will, and require them to agree with the Swift policy.
    private func injectedSubmitVerdict(_ label: String) -> (strong: Bool, weak: Bool) {
        let context = JSContext()!
        let js = """
        (function() {
          \(ATSAutofillPolicy.submitPatternsJS)
          var t = '\(label)'.toLowerCase();
          return [STRONG_SUBMIT_RE.test(t), WEAK_SUBMIT_RE.test(t)];
        })()
        """
        let result = context.evaluateScript(js)
        return (result?.atIndex(0)?.toBool() ?? false, result?.atIndex(1)?.toBool() ?? false)
    }

    func testInjectedSubmitPatternsMatchPolicy() {
        for label in ["Apply for this job", "Submit Application", "Apply now", "Send application"] {
            let injected = injectedSubmitVerdict(label)
            XCTAssertEqual(injected.strong, ATSAutofillPolicy.isStrongSubmitLabel(label),
                           "strong verdict diverged for \(label)")
            XCTAssertEqual(injected.weak, ATSAutofillPolicy.isWeakSubmitLabel(label),
                           "weak verdict diverged for \(label)")
        }
        XCTAssertFalse(injectedSubmitVerdict("Apply for this job").strong,
                       "the gateway button must not be a strong submit in the shipped JS")
        XCTAssertTrue(injectedSubmitVerdict("Submit Application").strong)
    }
}
