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
    let employerProfileID: String
    let postedByProfileID: String
    let title: String
    let companyName: String
    let location: String?
    let compensationMinAnnual: Int?
    let compensationMaxAnnual: Int?
    let jobFunction: JobFunctionOption?
    let description: String
    let applicationEmail: String
    let videoURL: String
    let sourceURL: String?
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
        case jobFunction = "job_function"
        case description
        case applicationEmail = "application_email"
        case videoURL = "video_url"
        case sourceURL = "source_url"
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
    var jobFunction: JobFunctionOption = .engineering
    var description: String = ""
    var applicationEmail: String = ""
    var sourceURL: String = ""
    var isPublished = true
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
            jobFunction: .design,
            description: "Own the candidate application experience and create product surfaces that convert attention into applications.",
            applicationEmail: "talent@figma.com",
            videoURL: "https://example.com/jobs/figma-designer.mp4",
            sourceURL: "https://www.tiktok.com/@figma",
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
            jobFunction: .product,
            description: "Build creator-native acquisition and activation loops across mobile and web hiring funnels.",
            applicationEmail: "jobs@ramp.com",
            videoURL: "https://example.com/jobs/ramp-pm.mp4",
            sourceURL: nil,
            isPublished: true,
            createdAt: .now
        ),
    ]
}
