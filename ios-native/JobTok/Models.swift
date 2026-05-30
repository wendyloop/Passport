import Foundation

enum UserRole: String, CaseIterable, Identifiable, Codable {
    case jobSeeker = "job_seeker"
    case employer = "employer"
    case admin = "admin"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jobSeeker:
            "Job Seeker"
        case .employer:
            "Employer"
        case .admin:
            "Admin"
        }
    }
}

enum JobFunctionOption: String, CaseIterable, Identifiable, Codable {
    case engineering
    case design
    case product
    case science
    case sales
    case marketing
    case support
    case operations
    case hr
    case finance
    case legal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .engineering: return "Engineering"
        case .design: return "Design"
        case .product: return "Product"
        case .science: return "Science"
        case .sales: return "Sales"
        case .marketing: return "Marketing"
        case .support: return "Support"
        case .operations: return "Operations"
        case .hr: return "HR"
        case .finance: return "Finance"
        case .legal: return "Legal"
        }
    }
}

enum EmploymentTypeOption: String, CaseIterable, Identifiable, Codable {
    case fullTime = "full_time"
    case partTime = "part_time"
    case contract

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullTime:
            return "Full-time"
        case .partTime:
            return "Part-time"
        case .contract:
            return "Contract"
        }
    }
}

enum SocialSourcePlatform: String, CaseIterable, Identifiable, Codable {
    case tiktok
    case instagram
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tiktok:
            return "TikTok"
        case .instagram:
            return "Instagram"
        case .other:
            return "External"
        }
    }
}

enum CandidateVisibility: String, CaseIterable, Identifiable, Codable {
    case `private`
    case appliedRolesOnly = "applied_roles_only"
    case discoverableToHiringEmployers = "discoverable_to_hiring_employers"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .private: return "Private"
        case .appliedRolesOnly: return "Private"
        case .discoverableToHiringEmployers: return "Public"
        }
    }

    var explanation: String {
        switch self {
        case .private:
            return "Only employers tied to your applications can view your profile."
        case .appliedRolesOnly:
            return "Only employers tied to your applications can view your profile."
        case .discoverableToHiringEmployers:
            return "Any hiring employer can discover your profile."
        }
    }
}

struct SharedImportItem: Codable, Equatable {
    let id: UUID
    let sourceURL: String
    let sourceAppBundleID: String?
    let createdAt: Date
}

enum SharedImportInbox {
    static let appGroupIdentifier = "group.com.jobtok.shared"

    private static let defaults = UserDefaults(suiteName: appGroupIdentifier)
    private static let queueKey = "shared_import_queue_v1"
    private static let roleKey = "shared_import_last_known_role_v1"
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func enqueueURL(_ sourceURL: String, sourceAppBundleID: String?) {
        let trimmed = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var queue = pendingItems()
        queue.append(
            SharedImportItem(
                id: UUID(),
                sourceURL: trimmed,
                sourceAppBundleID: sourceAppBundleID,
                createdAt: Date()
            )
        )
        persist(queue)
    }

    static func consumePendingURL() -> SharedImportItem? {
        var queue = pendingItems()
        guard !queue.isEmpty else { return nil }
        let item = queue.removeFirst()
        persist(queue)
        return item
    }

    static func pendingItems() -> [SharedImportItem] {
        guard let data = defaults?.data(forKey: queueKey),
              let items = try? decoder.decode([SharedImportItem].self, from: data) else {
            return []
        }
        return items
    }

    static func updateCurrentRole(_ role: UserRole?) {
        defaults?.set(role?.rawValue, forKey: roleKey)
    }

    static func clearCurrentRole() {
        defaults?.removeObject(forKey: roleKey)
    }

    private static func persist(_ items: [SharedImportItem]) {
        guard let data = try? encoder.encode(items) else { return }
        defaults?.set(data, forKey: queueKey)
    }
}

struct AuthSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let user: AuthUser
}

struct AuthUser: Codable, Identifiable {
    let id: String
    let email: String?
}

struct AppProfileRecord: Codable, Identifiable {
    let id: String
    var role: UserRole?
    var fullName: String?
    var fullNameLastChangedAt: Date?
    var email: String?
    var handle: String?
    var handleLastChangedAt: Date?
    var avatarURL: String?
    var headline: String?
    var onboardingComplete: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case fullName = "full_name"
        case fullNameLastChangedAt = "full_name_last_changed_at"
        case email
        case handle
        case handleLastChangedAt = "handle_last_changed_at"
        case avatarURL = "avatar_url"
        case headline
        case onboardingComplete = "onboarding_complete"
    }
}

struct JobSeekerProfileRecord: Codable {
    let profileID: String
    var schoolName: String?
    var jobFunction: JobFunctionOption?
    var referralBadge: Bool
    var referralInviteID: String?
    var introVideoURL: String?
    var dreamRole: String?
    var desiredCompensationAnnual: Int?
    var desiredCompensationRange: String?
    var linkedInURL: String?
    var instagramUsername: String?
    var tiktokUsername: String?
    var discoveryVisibility: CandidateVisibility

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case schoolName = "school_name"
        case jobFunction = "job_function"
        case referralBadge = "referral_badge"
        case referralInviteID = "referral_invite_id"
        case introVideoURL = "intro_video_url"
        case dreamRole = "dream_role"
        case desiredCompensationAnnual = "desired_compensation_annual"
        case desiredCompensationRange = "desired_compensation_range"
        case linkedInURL = "linkedin_url"
        case instagramUsername = "instagram_username"
        case tiktokUsername = "tiktok_username"
        case discoveryVisibility = "discovery_visibility"
    }
}

struct EmployerProfileRecord: Codable {
    let profileID: String
    var companyName: String?
    var companyDomain: String?
    var positionTitle: String?
    var calendarConnected: Bool
    var monthlyReferralLimit: Int

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case companyName = "company_name"
        case companyDomain = "company_domain"
        case positionTitle = "position_title"
        case calendarConnected = "calendar_connected"
        case monthlyReferralLimit = "monthly_referral_limit"
    }
}

struct JobSeekerEmployerRecord: Codable, Identifiable {
    let id: String
    let profileID: String
    let employerName: String
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case profileID = "profile_id"
        case employerName = "employer_name"
        case sortOrder = "sort_order"
    }
}

struct ResumeUploadRecord: Codable, Identifiable {
    let id: String
    let profileID: String
    let filePath: String
    let parseStatus: String
    let parsedSchoolName: String?
    let parsedEmployers: [String]
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case profileID = "profile_id"
        case filePath = "file_path"
        case parseStatus = "parse_status"
        case parsedSchoolName = "parsed_school_name"
        case parsedEmployers = "parsed_employers"
        case createdAt = "created_at"
    }
}

struct NotificationRecord: Codable, Identifiable {
    let id: String
    let title: String
    let body: String
    let createdAt: Date
    let readAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case body
        case createdAt = "created_at"
        case readAt = "read_at"
    }
}

struct JobPostingRecord: Codable, Identifiable {
    let id: String
    let employerProfileID: String?
    let postedByProfileID: String
    let title: String
    let companyName: String
    let location: String?
    let compensationMinAnnual: Int?
    let compensationMaxAnnual: Int?
    let compensationMinHourly: Int?
    let compensationMaxHourly: Int?
    let employmentType: EmploymentTypeOption?
    let jobFunction: JobFunctionOption?
    let description: String
    let applicationEmail: String
    let videoURL: String
    let sourceURL: String?
    let sourcePlatform: SocialSourcePlatform?
    let sourceCreatorName: String?
    let sourceCreatorURL: String?
    let sourceThumbnailURL: String?
    let sourceCaption: String?
    let sourceCaptionRaw: String?
    let sourcePostedAt: Date?
    let sourceApplyEmailExtracted: String?
    let isPublished: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case employerProfileID = "employer_profile_id"
        case postedByProfileID = "posted_by_profile_id"
        case title
        case companyName = "company_name"
        case location
        case compensationMinAnnual = "compensation_min_annual"
        case compensationMaxAnnual = "compensation_max_annual"
        case compensationMinHourly = "compensation_min_hourly"
        case compensationMaxHourly = "compensation_max_hourly"
        case employmentType = "employment_type"
        case jobFunction = "job_function"
        case description
        case applicationEmail = "application_email"
        case videoURL = "video_url"
        case sourceURL = "source_url"
        case sourcePlatform = "source_platform"
        case sourceCreatorName = "source_creator_name"
        case sourceCreatorURL = "source_creator_url"
        case sourceThumbnailURL = "source_thumbnail_url"
        case sourceCaption = "source_caption"
        case sourceCaptionRaw = "source_caption_raw"
        case sourcePostedAt = "source_posted_at"
        case sourceApplyEmailExtracted = "source_apply_email_extracted"
        case isPublished = "is_published"
        case createdAt = "created_at"
    }
}

struct JobApplicationRecord: Codable, Identifiable {
    let id: String
    let jobID: String
    let employerProfileID: String
    let candidateProfileID: String
    let status: String
    let coverNote: String?
    let jobTitle: String
    let companyName: String
    let jobLocation: String?
    let applicationEmail: String
    let candidateName: String
    let candidateHeadline: String?
    let candidateSchoolName: String?
    let candidateJobFunction: JobFunctionOption?
    let candidateDreamRole: String?
    let candidatePreviousEmployers: [String]
    let candidateVideoURL: String?
    let candidateLinkedInURL: String?
    let candidateInstagramUsername: String?
    let candidateTiktokUsername: String?
    let candidateCompensationRange: String?
    let resumeFilePath: String?
    let resumeFileName: String?
    let emailDeliveryStatus: String
    let emailDeliveryError: String?
    let appliedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case jobID = "job_id"
        case employerProfileID = "employer_profile_id"
        case candidateProfileID = "candidate_profile_id"
        case status
        case coverNote = "cover_note"
        case jobTitle = "job_title"
        case companyName = "company_name"
        case jobLocation = "job_location"
        case applicationEmail = "application_email"
        case candidateName = "candidate_name"
        case candidateHeadline = "candidate_headline"
        case candidateSchoolName = "candidate_school_name"
        case candidateJobFunction = "candidate_job_function"
        case candidateDreamRole = "candidate_dream_role"
        case candidatePreviousEmployers = "candidate_previous_employers"
        case candidateVideoURL = "candidate_video_url"
        case candidateLinkedInURL = "candidate_linkedin_url"
        case candidateInstagramUsername = "candidate_instagram_username"
        case candidateTiktokUsername = "candidate_tiktok_username"
        case candidateCompensationRange = "candidate_compensation_range"
        case resumeFilePath = "resume_file_path"
        case resumeFileName = "resume_file_name"
        case emailDeliveryStatus = "email_delivery_status"
        case emailDeliveryError = "email_delivery_error"
        case appliedAt = "applied_at"
    }
}

struct DiscoverableCandidateRecord: Codable, Identifiable {
    let candidateID: String
    let fullName: String?
    let headline: String?
    let handle: String?
    let avatarURL: String?
    let schoolName: String?
    let jobFunction: JobFunctionOption?
    let dreamRole: String?
    let discoveryVisibility: CandidateVisibility
    let linkedInURL: String?
    let instagramUsername: String?
    let tiktokUsername: String?
    let desiredCompensationRange: String?
    let previousEmployers: [String]
    let videoURL: String?

    var id: String { candidateID }

    enum CodingKeys: String, CodingKey {
        case candidateID = "candidate_id"
        case fullName = "full_name"
        case headline
        case handle
        case avatarURL = "avatar_url"
        case schoolName = "school_name"
        case jobFunction = "job_function"
        case dreamRole = "dream_role"
        case discoveryVisibility = "discovery_visibility"
        case linkedInURL = "linkedin_url"
        case instagramUsername = "instagram_username"
        case tiktokUsername = "tiktok_username"
        case desiredCompensationRange = "desired_compensation_range"
        case previousEmployers = "previous_employers"
        case videoURL = "video_url"
    }
}

struct CandidateOutreachRecord: Codable, Identifiable {
    let id: String
    let employerProfileID: String
    let candidateProfileID: String
    let relatedJobID: String?
    let subject: String
    let body: String
    let deliveryStatus: String
    let deliveryError: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case employerProfileID = "employer_profile_id"
        case candidateProfileID = "candidate_profile_id"
        case relatedJobID = "related_job_id"
        case subject
        case body
        case deliveryStatus = "delivery_status"
        case deliveryError = "delivery_error"
        case createdAt = "created_at"
    }
}

struct SavedJobRecord: Codable, Identifiable {
    let id: String
    let profileID: String
    let jobID: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case profileID = "profile_id"
        case jobID = "job_id"
        case createdAt = "created_at"
    }
}

struct JobApplicationDraft: Equatable {
    var jobID: String = ""
    var resumeFileName: String?
    var resumeFilePath: String?
    var includePitchVideo = false
    var pitchVideoURL: String?
    var sharedSocialLink: String = ""
}

struct EmployerDirectoryItem: Identifiable, Hashable {
    let id: String
    let fullName: String
    let email: String
    let companyName: String
}

struct CandidateProfileDraft: Equatable {
    var fullName: String = ""
    var fullNameLastChangedAt: Date?
    var headline: String = ""
    var handle: String = ""
    var handleLastChangedAt: Date?
    var avatarURL: String?
    var school: String = ""
    var employers: [String] = []
    var jobFunction: JobFunctionOption = .engineering
    var dreamRole: String = ""
    var desiredCompensationRange: String = ""
    var linkedInURL: String = ""
    var instagramUsername: String = ""
    var tiktokUsername: String = ""
    var visibility: CandidateVisibility = .appliedRolesOnly
    var resumeFileName: String?
    var resumeStoragePath: String?
    var resumeImportedAt: Date?
    var introVideoFileName: String?
    var introVideoDuration: Double?
    var introVideoURL: String?
}

struct EmployerProfileDraft: Equatable {
    var fullName: String = ""
    var fullNameLastChangedAt: Date?
    var headline: String = ""
    var companyName: String = ""
    var companyDomain: String = ""
    var positionTitle: String = ""
}

struct JobPostingDraft {
    var employerProfileID: String = ""
    var title: String = ""
    var companyName: String = ""
    var location: String = ""
    var compensationMinAnnual: String = ""
    var compensationMaxAnnual: String = ""
    var compensationMinHourly: String = ""
    var compensationMaxHourly: String = ""
    var employmentType: EmploymentTypeOption?
    var jobFunction: JobFunctionOption = .engineering
    var description: String = ""
    var applicationEmail: String = ""
    var sourceURL: String = ""
    var sourcePlatform: SocialSourcePlatform?
    var sourceCreatorName: String = ""
    var sourceCreatorURL: String = ""
    var sourceThumbnailURL: String = ""
    var sourceCaption: String = ""
    var sourceCaptionRaw: String = ""
    var sourcePostedAt: Date?
    var sourceApplyEmailExtracted: String = ""
    var sourceCompensationText: String = ""
    var sourceHowToApplyText: String = ""
    var importedVideoURL: String = ""
    var isPublished = true
}

struct ImportedJobSuggestion: Codable, Equatable {
    var sourcePlatform: SocialSourcePlatform?
    var sourceURL: String
    var sourceCreatorName: String?
    var sourceCreatorURL: String?
    var sourceThumbnailURL: String?
    var sourceCaption: String
    var sourceCaptionRaw: String
    var sourcePostedAt: Date?
    var sourceApplyEmailExtracted: String?
    var company: String?
    var title: String?
    var location: String?
    var compensation: String?
    var howToApply: String?
    var description: String?
    var applicationEmail: String?
    var videoPlayURL: String?
    var diagnostics: ImportDiagnostics?

    enum CodingKeys: String, CodingKey {
        case sourcePlatform = "source_platform"
        case sourceURL = "source_url"
        case sourceCreatorName = "source_creator_name"
        case sourceCreatorURL = "source_creator_url"
        case sourceThumbnailURL = "source_thumbnail_url"
        case sourceCaption = "source_caption"
        case sourceCaptionRaw = "source_caption_raw"
        case sourcePostedAt = "source_posted_at"
        case sourceApplyEmailExtracted = "source_apply_email_extracted"
        case company
        case title
        case location
        case compensation
        case howToApply = "how_to_apply"
        case description
        case applicationEmail = "application_email"
        case videoPlayURL = "video_play_url"
        case diagnostics
    }
}

struct ImportDiagnostics: Codable, Equatable {
    var fetchStatus: Int?
    var fetchContentType: String?
    var htmlLength: Int?
    var sourceTextLength: Int?
    var metadataKeysWithValues: [String]
    var openAIEnabled: Bool?
    var llmUsed: Bool?
    var scrapedMetadata: [String: String]?

    enum CodingKeys: String, CodingKey {
        case fetchStatus = "fetch_status"
        case fetchContentType = "fetch_content_type"
        case htmlLength = "html_length"
        case sourceTextLength = "source_text_length"
        case metadataKeysWithValues = "metadata_keys_with_values"
        case openAIEnabled = "openai_enabled"
        case llmUsed = "llm_used"
        case scrapedMetadata = "scraped_metadata"
    }
}

enum DemoData {
    static let defaultCandidateProfile = CandidateProfileDraft(
        fullName: "Maya Chen",
        fullNameLastChangedAt: nil,
        headline: "Product designer with a creator-first portfolio and short-form storytelling skills.",
        handle: "mayachen",
        handleLastChangedAt: nil,
        avatarURL: nil,
        school: "Stanford University",
        employers: ["Figma", "Notion"],
        jobFunction: .design,
        dreamRole: "Founding Product Designer",
        desiredCompensationRange: "$150k-$175k",
        linkedInURL: "",
        instagramUsername: "",
        tiktokUsername: "",
        visibility: .appliedRolesOnly,
        resumeFileName: nil,
        resumeStoragePath: nil,
        resumeImportedAt: nil,
        introVideoFileName: nil,
        introVideoDuration: nil,
        introVideoURL: nil
    )

    static let jobs: [JobPostingRecord] = [
        JobPostingRecord(
            id: "demo-job-1",
            employerProfileID: "employer-1",
            postedByProfileID: "admin-1",
            title: "Senior Product Designer",
            companyName: "Figma",
            location: "San Francisco, CA",
            compensationMinAnnual: 140000,
            compensationMaxAnnual: 180000,
            compensationMinHourly: nil,
            compensationMaxHourly: nil,
            employmentType: .fullTime,
            jobFunction: .design,
            description: "Own the candidate application experience and create product surfaces that convert attention into applications.",
            applicationEmail: "talent@figma.com",
            videoURL: "https://example.com/jobs/figma-designer.mp4",
            sourceURL: "https://www.tiktok.com/@figma",
            sourcePlatform: .tiktok,
            sourceCreatorName: "Figma",
            sourceCreatorURL: "https://www.tiktok.com/@figma",
            sourceThumbnailURL: nil,
            sourceCaption: nil,
            sourceCaptionRaw: nil,
            sourcePostedAt: nil,
            sourceApplyEmailExtracted: nil,
            isPublished: true,
            createdAt: .now
        ),
        JobPostingRecord(
            id: "demo-job-2",
            employerProfileID: "employer-2",
            postedByProfileID: "admin-1",
            title: "Growth Product Manager",
            companyName: "Ramp",
            location: "New York, NY",
            compensationMinAnnual: 125000,
            compensationMaxAnnual: 165000,
            compensationMinHourly: nil,
            compensationMaxHourly: nil,
            employmentType: .contract,
            jobFunction: .product,
            description: "Build creator-native acquisition and activation loops across mobile and web hiring funnels.",
            applicationEmail: "jobs@ramp.com",
            videoURL: "https://example.com/jobs/ramp-pm.mp4",
            sourceURL: nil,
            sourcePlatform: nil,
            sourceCreatorName: nil,
            sourceCreatorURL: nil,
            sourceThumbnailURL: nil,
            sourceCaption: nil,
            sourceCaptionRaw: nil,
            sourcePostedAt: nil,
            sourceApplyEmailExtracted: nil,
            isPublished: true,
            createdAt: .now
        ),
    ]
}
