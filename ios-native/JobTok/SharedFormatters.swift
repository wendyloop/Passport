import Foundation

// Formatting helpers that were previously copy-pasted across view files.
// Note: the various social-username normalizers (@-stripping with different
// allowed character sets) are intentionally NOT unified here — they differ
// in behavior per call site.

extension JobPostingRecord {
    /// FIRST-100-USERS founder-fatigue rank: 0 = untouched, 1 = a founder
    /// was reached earlier this week (soft demote), 2 = reached today (hard
    /// demote). Feed sorts ascending bucket, newest-first within a bucket.
    func founderFatigueBucket(now: Date) -> Int {
        guard let touched = lastFounderTouchAt else { return 0 }
        if Calendar.current.isDate(touched, inSameDayAs: now) { return 2 }
        if touched > now.addingTimeInterval(-7 * 24 * 3600) { return 1 }
        return 0
    }

    /// F8 big-company handling: 1000+/acquired/IPO companies stay in the
    /// catalog but rank below startups and don't get the founder-pitch
    /// button (apply-only). Unknown stage counts as a startup.
    private static let bigCompanyStages: Set<String> = ["1000+ employees", "acquisition", "ipo"]

    var isBigCompany: Bool {
        guard let stage = company?.stage else { return false }
        return Self.bigCompanyStages.contains(stage)
    }

    /// The founder-pitch path only makes sense where an email plausibly
    /// reaches a founder. Backend contact data is untouched — this only
    /// gates the button.
    var founderPitchAllowed: Bool {
        companyID != nil && !isBigCompany
    }

    /// "$120,000 – $150,000" / "From $30/hr" / nil when no compensation set.
    var compensationSummary: String? {
        if compensationMinAnnual != nil || compensationMaxAnnual != nil {
            return SharedFormatters.compensation(min: compensationMinAnnual, max: compensationMaxAnnual, suffix: "")
        }
        if compensationMinHourly != nil || compensationMaxHourly != nil {
            return SharedFormatters.compensation(min: compensationMinHourly, max: compensationMaxHourly, suffix: "/hr")
        }
        return nil
    }
}

enum SharedFormatters {
    static func compensation(min: Int?, max: Int?, suffix: String) -> String? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0

        let minimum = min.flatMap { formatter.string(from: NSNumber(value: $0)) }
        let maximum = max.flatMap { formatter.string(from: NSNumber(value: $0)) }

        switch (minimum, maximum) {
        case let (min?, max?): return "\(min) – \(max)\(suffix)"
        case let (min?, nil): return "From \(min)\(suffix)"
        case let (nil, max?): return "Up to \(max)\(suffix)"
        case (nil, nil): return nil
        }
    }

    /// Profile handle: lowercase, [a-z0-9_] only. Empty result means the
    /// input had no usable characters.
    static func profileHandle(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9_]", with: "", options: .regularExpression)
    }

    /// "today" / "3d ago" / "2w ago" — freshness chip on carousel covers.
    static func relativeAge(of date: Date, now: Date = Date()) -> String {
        let days = Int(now.timeIntervalSince(date) / 86_400)
        if days <= 0 { return "today" }
        if days == 1 { return "1d ago" }
        if days < 14 { return "\(days)d ago" }
        return "\(days / 7)w ago"
    }

    /// "1:05" style mm:ss.
    static func duration(_ duration: Double) -> String {
        let totalSeconds = Int(duration.rounded())
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
