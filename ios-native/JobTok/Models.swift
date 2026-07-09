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
    var introVideoURL: String?
    var dreamRole: String?
    var desiredCompensationAnnual: Int?
    var desiredCompensationRange: String?
    var linkedInURL: String?
    var instagramUsername: String?
    var tiktokUsername: String?
    var discoveryVisibility: CandidateVisibility
    var githubURL: String?
    var portfolioURL: String?
    var city: String?
    var phone: String?

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case schoolName = "school_name"
        case jobFunction = "job_function"
        case introVideoURL = "intro_video_url"
        case dreamRole = "dream_role"
        case desiredCompensationAnnual = "desired_compensation_annual"
        case desiredCompensationRange = "desired_compensation_range"
        case linkedInURL = "linkedin_url"
        case instagramUsername = "instagram_username"
        case tiktokUsername = "tiktok_username"
        case discoveryVisibility = "discovery_visibility"
        case githubURL = "github_url"
        case portfolioURL = "portfolio_url"
        case city
        case phone
    }
}

struct EmployerProfileRecord: Codable {
    let profileID: String
    var companyName: String?
    var companyDomain: String?
    var positionTitle: String?

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case companyName = "company_name"
        case companyDomain = "company_domain"
        case positionTitle = "position_title"
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

// Source taxonomy for a job row. Drives feed-card routing and badge display.
//   * employerPost — employer- or admin-created posting (has video)
//   * reel         — scraped TikTok/Instagram post (has video, source_platform set)
//   * ats          — Pitch v1: direct ATS sync (no video, rendered with carousel)
//   * board        — Pitch v2: portfolio fund board ingestion (no video, carousel)
enum JobSourceKind: String, Codable {
    case employerPost = "employer_post"
    case reel
    case ats
    case board
}

extension JobSourceKind {
    // Both ats and board rows are non-video Pitch jobs that render as carousels.
    var rendersCarousel: Bool { self == .ats || self == .board }
}

// Embedded slice of the companies row, returned by PostgREST when fetchJobs
// requests `select=*,company:companies(...)`. Only present for ATS rows.
struct CompanyRef: Codable, Equatable {
    let id: String
    let name: String?
    let domain: String?
    let logoUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case domain
        case logoUrl = "logo_url"
    }
}

// Carousel attached to an ATS job (one per job). Generated by the
// generate-carousel edge function; the iOS app renders it as a swipeable
// pager with theme-driven palette/typography.
struct Carousel: Codable, Equatable {
    let themeId: String
    let slideCount: Int
    let content: [CarouselSlide]
    let status: CarouselStatus

    enum CodingKeys: String, CodingKey {
        case themeId = "theme_id"
        case slideCount = "slide_count"
        case content
        case status
    }

    /// Slides this build can actually draw, in display order. Unknown slide
    /// types (from a newer backend) are dropped.
    var renderableSlides: [CarouselSlide] {
        content.filter(\.isRenderable).sorted { $0.order < $1.order }
    }

    var hasRenderableSlides: Bool {
        content.contains(where: \.isRenderable)
    }
}

enum CarouselStatus: String, Codable {
    case generated
    case fallback
}

// One slide. The backend writes a JSONB array of five shapes keyed by `type`.
// We decode into a typed enum so each layout view is total over its inputs.
enum CarouselSlide: Codable, Equatable, Identifiable {
    case cover(CoverSlide)
    case aboutCompany(AboutCompanySlide)
    case role(RoleSlide)
    case requirements(RequirementsSlide)
    case perks(PerksSlide)
    case details(DetailsSlide)
    // A slide type this build doesn't recognize — e.g. a new layout added by
    // a newer backend. It decodes successfully (so the surrounding carousel
    // survives) but is skipped at render time. This keeps a single new slide
    // type from dropping the whole job out of an old client's feed.
    case unknown(order: Int)

    var id: Int { order }

    var order: Int {
        switch self {
        case .cover(let s):         return s.order
        case .aboutCompany(let s):  return s.order
        case .role(let s):          return s.order
        case .requirements(let s):  return s.order
        case .perks(let s):         return s.order
        case .details(let s):       return s.order
        case .unknown(let order):   return order
        }
    }

    var isRenderable: Bool {
        if case .unknown = self { return false }
        return true
    }

    private enum DiscriminatorKey: String, CodingKey {
        case type
        case order
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DiscriminatorKey.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "cover":         self = .cover(try CoverSlide(from: decoder))
        case "about_company": self = .aboutCompany(try AboutCompanySlide(from: decoder))
        case "role":          self = .role(try RoleSlide(from: decoder))
        case "requirements":  self = .requirements(try RequirementsSlide(from: decoder))
        case "perks":         self = .perks(try PerksSlide(from: decoder))
        case "details":       self = .details(try DetailsSlide(from: decoder))
        default:
            self = .unknown(order: (try? c.decode(Int.self, forKey: .order)) ?? 0)
        }
    }

    func encode(to encoder: Encoder) throws {
        // Read-only client — slides are written by the backend.
    }
}

struct CoverSlide: Codable, Equatable {
    let order: Int
    let hook: String?
    let role: String?
    let company: String?
    let location: String?
    // The backend has always sent this; the client just never decoded it.
    let compensation: String?
}

struct AboutCompanySlide: Codable, Equatable {
    let order: Int
    let blurb: String?
    let company: String?
    let industry: String?
    let stage: String?
    let backedBy: String?

    enum CodingKeys: String, CodingKey {
        case order, blurb, company, industry, stage
        case backedBy = "backed_by"
    }
}

struct RoleSlide: Codable, Equatable {
    let order: Int
    let bullets: [String]
}

struct RequirementsSlide: Codable, Equatable {
    let order: Int
    let bullets: [String]
}

struct PerksSlide: Codable, Equatable {
    let order: Int
    let bullets: [String]
}

struct DetailsSlide: Codable, Equatable {
    let order: Int
    let location: String?
    let employment: String?
    let compensation: String?
    let perks: [String]?
}

struct JobPostingRecord: Codable, Identifiable {
    let id: String
    let employerProfileID: String?
    let postedByProfileID: String?
    let title: String
    let companyName: String
    let location: String?
    let compensationMinAnnual: Int?
    let compensationMaxAnnual: Int?
    let compensationMinHourly: Int?
    let compensationMaxHourly: Int?
    let compensationText: String?
    let employmentType: EmploymentTypeOption?
    let jobFunction: JobFunctionOption?
    let description: String
    let applicationEmail: String
    // Null for ATS rows (no video). Reel + employer_post rows always have one.
    let videoURL: String?
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
    // ATS apply flow
    let applyUrl: String?
    let atsType: String?
    // Pitch fields — populated by sync-jobs for source_kind = 'ats'.
    let sourceKind: JobSourceKind
    let sourceAts: String?
    let applyFlow: String?
    let companyID: String?
    // PostgREST-embedded company slice (only present when select asks for it).
    let company: CompanyRef?
    // PostgREST-embedded carousel row (only present for ATS rows that have
    // been processed by generate-carousel).
    let carousel: Carousel?
    // FIRST-100-USERS: stamped by the backend when a founder email or a
    // video application lands on this job; the feed demotes touched jobs so
    // early applications spread across companies. See founder_fatigue migration.
    let lastFounderTouchAt: Date?

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
        case compensationText = "compensation_text"
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
        case applyUrl = "apply_url"
        case atsType = "ats_type"
        case sourceKind = "source_kind"
        case sourceAts = "source_ats"
        case applyFlow = "apply_flow"
        case companyID = "company_id"
        case lastFounderTouchAt = "last_founder_touch_at"
        case company
        case carousel
    }
}

extension JobPostingRecord {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                        = try c.decode(String.self,                       forKey: .id)
        employerProfileID         = try c.decodeIfPresent(String.self,              forKey: .employerProfileID)
        postedByProfileID         = try c.decodeIfPresent(String.self,              forKey: .postedByProfileID)
        title                     = try c.decode(String.self,                       forKey: .title)
        companyName               = try c.decodeIfPresent(String.self,              forKey: .companyName) ?? ""
        location                  = try c.decodeIfPresent(String.self,              forKey: .location)
        compensationMinAnnual     = try c.decodeIfPresent(Int.self,                 forKey: .compensationMinAnnual)
        compensationMaxAnnual     = try c.decodeIfPresent(Int.self,                 forKey: .compensationMaxAnnual)
        compensationMinHourly     = try c.decodeIfPresent(Int.self,                 forKey: .compensationMinHourly)
        compensationMaxHourly     = try c.decodeIfPresent(Int.self,                 forKey: .compensationMaxHourly)
        employmentType            = try c.decodeIfPresent(EmploymentTypeOption.self, forKey: .employmentType)
        jobFunction               = try c.decodeIfPresent(JobFunctionOption.self,    forKey: .jobFunction)
        description               = try c.decodeIfPresent(String.self,              forKey: .description)     ?? ""
        applicationEmail          = try c.decodeIfPresent(String.self,              forKey: .applicationEmail) ?? ""
        videoURL                  = try c.decodeIfPresent(String.self,              forKey: .videoURL)
        sourceURL                 = try c.decodeIfPresent(String.self,              forKey: .sourceURL)
        sourcePlatform            = try c.decodeIfPresent(SocialSourcePlatform.self, forKey: .sourcePlatform)
        sourceCreatorName         = try c.decodeIfPresent(String.self,              forKey: .sourceCreatorName)
        sourceCreatorURL          = try c.decodeIfPresent(String.self,              forKey: .sourceCreatorURL)
        sourceThumbnailURL        = try c.decodeIfPresent(String.self,              forKey: .sourceThumbnailURL)
        sourceCaption             = try c.decodeIfPresent(String.self,              forKey: .sourceCaption)
        sourceCaptionRaw          = try c.decodeIfPresent(String.self,              forKey: .sourceCaptionRaw)
        sourcePostedAt            = try c.decodeIfPresent(Date.self,                forKey: .sourcePostedAt)
        sourceApplyEmailExtracted = try c.decodeIfPresent(String.self,              forKey: .sourceApplyEmailExtracted)
        isPublished               = try c.decode(Bool.self,                         forKey: .isPublished)
        createdAt                 = try c.decode(Date.self,                         forKey: .createdAt)
        applyUrl                  = try c.decodeIfPresent(String.self,              forKey: .applyUrl)
        atsType                   = try c.decodeIfPresent(String.self,              forKey: .atsType)
        compensationText          = try c.decodeIfPresent(String.self,              forKey: .compensationText)
        // source_kind is NOT NULL in the DB but older clients hitting in-flight
        // data may see absent/null; default to the safe legacy value.
        sourceKind                = try c.decodeIfPresent(JobSourceKind.self,       forKey: .sourceKind) ?? .employerPost
        sourceAts                 = try c.decodeIfPresent(String.self,              forKey: .sourceAts)
        applyFlow                 = try c.decodeIfPresent(String.self,              forKey: .applyFlow)
        companyID                 = try c.decodeIfPresent(String.self,              forKey: .companyID)
        lastFounderTouchAt        = try c.decodeIfPresent(Date.self,                forKey: .lastFounderTouchAt)
        company                   = try c.decodeIfPresent(CompanyRef.self,          forKey: .company)
        // PostgREST may embed a one-to-one FK as either a single object or a
        // single-element array depending on whether it detects the unique
        // constraint. Accept both shapes so a schema-discovery quirk doesn't
        // break the entire feed decode.
        if let single = try? c.decodeIfPresent(Carousel.self, forKey: .carousel) {
            carousel = single
        } else if let array = try? c.decodeIfPresent([Carousel].self, forKey: .carousel) {
            carousel = array.first
        } else {
            carousel = nil
        }
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
            compensationText: nil,
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
            createdAt: .now,
            applyUrl: nil,
            atsType: nil,
            sourceKind: .reel,
            sourceAts: nil,
            applyFlow: nil,
            companyID: nil,
            company: nil,
            carousel: nil,
            lastFounderTouchAt: nil
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
            compensationText: nil,
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
            createdAt: .now,
            applyUrl: nil,
            atsType: nil,
            sourceKind: .employerPost,
            sourceAts: nil,
            applyFlow: nil,
            companyID: nil,
            company: nil,
            carousel: nil,
            lastFounderTouchAt: nil
        ),
    ]
}

// MARK: - Founder email (direct apply path)

struct FounderContactPreview: Codable, Equatable {
    let id: String
    let fullName: String?
    let roleTitle: String?
    let emailMasked: String
    let source: String
    let confidence: Double?

    /// Guessed addresses get an honest badge in the compose UI; verified
    /// posting emails don't need one.
    var isGuessedAddress: Bool {
        source != "posting_email"
    }
}

struct FounderEmailPreview: Codable, Equatable {
    let eligible: Bool
    let reason: String?          // "pitch_video_required" | "no_contact" | "weekly_limit_reached"
    let contact: FounderContactPreview?
    let remaining: Int
    let limit: Int
    let subjectPreview: String?
}

struct FounderOutreachRecord: Codable, Equatable {
    let id: String
    let jobId: String?
    let subject: String
    let deliveryStatus: String
    let createdAt: Date
}

struct FounderEmailSendResult: Codable {
    let outreach: FounderOutreachRecord
    let remaining: Int
    let limit: Int
}

// MARK: - ATS autofill (apply drawer)

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
    // Canonical autofill bundle (label keys without the `canon:` prefix).
    // Falls back to empty dict for older backend builds.
    let canonical: [String: String]?
    let rawHistory: [String: String]?
    // Legacy union of canonical (still prefixed) + rawHistory.
    let fieldHistory: [String: String]
}

// MARK: - Capture + match models

struct ApplicationShortField: Codable {
    let label: String
    let value: String
}

struct ApplicationEssay: Codable {
    let question: String
    let answer: String
}

struct EssayMatch: Codable {
    let question: String
    let answer: String
    let similarity: Double
    let sourceJobId: String?
    let updatedAt: String
}

struct EssayMatchEnvelope: Codable {
    let match: EssayMatch?
}

