import XCTest
import JavaScriptCore
@testable import scout22

// AUDIT P1-6: autofill injection is allowlisted to the 14 known ATS domains
// and host matching is suffix-based (spoof-resistant).
final class ATSAutofillPolicyTests: XCTestCase {
    func testAllowlistHasTheFourteenKnownDomains() {
        XCTAssertEqual(ATSAutofillPolicy.allowedDomains.count, 14)
        XCTAssertEqual(Set(ATSAutofillPolicy.allowedDomains).count, 14, "no duplicates")
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

    // The exact JS prologue that ships inside the WKUserScripts, executed in
    // JavaScriptCore with a stubbed location — proves the injected gate
    // agrees with the Swift policy.
    private func injectedGateAllows(host: String) -> Bool {
        let context = JSContext()!
        let js = """
        (function() {
          var location = { hostname: '\(host)' };
          var result = (function() {
            \(ATSAutofillPolicy.hostGateJS)
            return true;
          })();
          return result === true;
        })()
        """
        return context.evaluateScript(js)?.toBool() ?? false
    }

    func testInjectedJSGateMatchesPolicy() {
        for host in ["boards.greenhouse.io", "jobs.lever.co", "acme.wd5.myworkday.com", "acme.recruitee.com"] {
            XCTAssertTrue(injectedGateAllows(host: host), "\(host) should pass the injected gate")
        }
        for host in ["example.com", "greenhouse.io.evil.com", "lever.co.attacker.net", ""] {
            XCTAssertFalse(injectedGateAllows(host: host), "\(host) should be stopped by the injected gate")
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
}
