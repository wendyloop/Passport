import Foundation

enum UserRole: String, CaseIterable, Identifiable, Codable {
    case jobSeeker = "job_seeker"
    case employer = "employer"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jobSeeker:
            "Job Seeker"
        case .employer:
            "Employer"
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
    var email: String?
    var avatarURL: String?
    var headline: String?
    var onboardingComplete: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case fullName = "full_name"
        case email
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

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case schoolName = "school_name"
        case jobFunction = "job_function"
        case referralBadge = "referral_badge"
        case referralInviteID = "referral_invite_id"
        case introVideoURL = "intro_video_url"
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

struct CandidateVideoRecord: Codable, Identifiable {
    let id: String
    let profileID: String
    let videoURL: String
    let posterURL: String?
    let durationSeconds: Int?
    let status: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case profileID = "profile_id"
        case videoURL = "video_url"
        case posterURL = "poster_url"
        case durationSeconds = "duration_seconds"
        case status
        case createdAt = "created_at"
    }
}

struct CandidateFeedRecord: Codable, Identifiable {
    let candidateID: String
    let fullName: String?
    let headline: String?
    let schoolName: String?
    let jobFunction: JobFunctionOption?
    let referralBadge: Bool?
    let previousEmployers: [String]
    let videoURL: String?
    let posterURL: String?

    var id: String { candidateID }

    enum CodingKeys: String, CodingKey {
        case candidateID = "candidate_id"
        case fullName = "full_name"
        case headline
        case schoolName = "school_name"
        case jobFunction = "job_function"
        case referralBadge = "referral_badge"
        case previousEmployers = "previous_employers"
        case videoURL = "video_url"
        case posterURL = "poster_url"
    }
}

struct CandidateLikeRecord: Codable, Identifiable {
    let id: String
    let candidateProfileID: String

    enum CodingKeys: String, CodingKey {
        case id
        case candidateProfileID = "candidate_profile_id"
    }
}

struct AvailabilitySlotRecord: Codable, Identifiable {
    let id: String
    let employerProfileID: String
    let startAt: Date
    let endAt: Date
    let slotStatus: String
    let source: String
    let reservedByProfileID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case employerProfileID = "employer_profile_id"
        case startAt = "start_at"
        case endAt = "end_at"
        case slotStatus = "slot_status"
        case source
        case reservedByProfileID = "reserved_by_profile_id"
    }
}

struct InterviewRequestRecord: Codable, Identifiable {
    let id: String
    let employerProfileID: String
    let candidateProfileID: String
    let status: String
    let availabilitySlotID: String?
    let requestedAt: Date
    let candidateSelectedAt: Date?
    let approvedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case employerProfileID = "employer_profile_id"
        case candidateProfileID = "candidate_profile_id"
        case status
        case availabilitySlotID = "availability_slot_id"
        case requestedAt = "requested_at"
        case candidateSelectedAt = "candidate_selected_at"
        case approvedAt = "approved_at"
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

struct ReferralInviteRecord: Codable, Identifiable {
    let id: String
    let token: String
    let email: String?
    let status: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case token
        case email
        case status
        case expiresAt = "expires_at"
    }
}

struct CandidateProfileDraft: Equatable {
    var fullName: String = ""
    var headline: String = ""
    var school: String = ""
    var employers: [String] = []
    var jobFunction: JobFunctionOption = .engineering
    var referred: Bool = false
    var resumeFileName: String?
    var resumeImportedAt: Date?
    var introVideoFileName: String?
    var introVideoDuration: Double?
    var introVideoURL: String?
}

struct EmployerProfileDraft {
    var fullName: String = ""
    var headline: String = ""
    var companyName: String = ""
    var companyDomain: String = ""
    var positionTitle: String = ""
}

struct Candidate: Identifiable {
    let id: String
    let name: String
    let headline: String
    let school: String
    let previousEmployers: [String]
    let jobFunction: String
    let referred: Bool
    let demoVideoName: String?
    let localVideoPath: String?
    let remoteVideoURL: String?
}

struct EmployerApprovalItem: Identifiable {
    let id: String
    let candidateName: String
    let status: String
    let slotLabel: String
}

struct JobSeekerRequestItem: Identifiable {
    let id: String
    let employerName: String
    let status: String
    let employerProfileID: String
    let availabilitySlotID: String?
}

struct NotificationItem: Identifiable {
    let id: String
    let title: String
    let body: String
}

enum DemoData {
    static let defaultCandidateProfile = CandidateProfileDraft(
        fullName: "Maya Chen",
        headline: "Senior designer focused on marketplace trust and candidate experience.",
        school: "Stanford University",
        employers: ["Figma", "Notion"],
        jobFunction: .design,
        referred: true,
        resumeFileName: nil,
        resumeImportedAt: nil,
        introVideoFileName: nil,
        introVideoDuration: nil,
        introVideoURL: nil
    )

    static let candidates: [Candidate] = [
        Candidate(
            id: "demo-candidate-1",
            name: "Maya Chen",
            headline: "Senior Product Designer with a marketplace growth focus",
            school: "Stanford University",
            previousEmployers: ["Figma", "Notion"],
            jobFunction: "Design",
            referred: true,
            demoVideoName: "candidate-1",
            localVideoPath: nil,
            remoteVideoURL: nil
        ),
        Candidate(
            id: "demo-candidate-2",
            name: "Jordan Patel",
            headline: "Full-stack engineer shipping AI onboarding systems",
            school: "Georgia Tech",
            previousEmployers: ["Stripe", "Ramp"],
            jobFunction: "Engineering",
            referred: false,
            demoVideoName: "candidate-2",
            localVideoPath: nil,
            remoteVideoURL: nil
        ),
        Candidate(
            id: "demo-candidate-3",
            name: "Sofia Martinez",
            headline: "Product lead for fintech and operations-heavy systems",
            school: "Wharton",
            previousEmployers: ["Brex", "Mercury"],
            jobFunction: "Product",
            referred: true,
            demoVideoName: "candidate-3",
            localVideoPath: nil,
            remoteVideoURL: nil
        )
    ]

    static let notifications: [NotificationItem] = [
        NotificationItem(
            id: "demo-notification-1",
            title: "Interview request sent",
            body: "A new interview request was created after you liked Maya Chen."
        ),
        NotificationItem(
            id: "demo-notification-2",
            title: "Referral used",
            body: "One of your five monthly referral invites was used by a new candidate."
        ),
        NotificationItem(
            id: "demo-notification-3",
            title: "Calendar sync later",
            body: "Google Calendar linkage is intentionally deferred. Manual availability is active for now."
        )
    ]
}
