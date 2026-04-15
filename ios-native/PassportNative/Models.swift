import Foundation

enum UserRole: String, CaseIterable, Identifiable {
    case jobSeeker = "Job Seeker"
    case employer = "Employer"

    var id: String { rawValue }
}

struct Candidate: Identifiable {
    let id = UUID()
    let name: String
    let headline: String
    let school: String
    let previousEmployers: [String]
    let jobFunction: String
    let referred: Bool
}

struct InterviewRequest: Identifiable {
    let id = UUID()
    let title: String
    let status: String
    let slots: [String]
}

struct NotificationItem: Identifiable {
    let id = UUID()
    let title: String
    let body: String
}

enum DemoData {
    static let candidates: [Candidate] = [
        Candidate(
            name: "Maya Chen",
            headline: "Senior Product Designer with a marketplace growth focus",
            school: "Stanford University",
            previousEmployers: ["Figma", "Notion"],
            jobFunction: "Design",
            referred: true
        ),
        Candidate(
            name: "Jordan Patel",
            headline: "Full-stack engineer shipping AI onboarding systems",
            school: "Georgia Tech",
            previousEmployers: ["Stripe", "Ramp"],
            jobFunction: "Engineering",
            referred: false
        ),
        Candidate(
            name: "Sofia Martinez",
            headline: "Product lead for fintech and operations-heavy systems",
            school: "Wharton",
            previousEmployers: ["Brex", "Mercury"],
            jobFunction: "Product",
            referred: true
        )
    ]

    static let jobSeekerRequests: [InterviewRequest] = [
        InterviewRequest(
            title: "Acme interview request",
            status: "Pending time selection",
            slots: [
                "Apr 18, 9:00 AM",
                "Apr 18, 1:30 PM",
                "Apr 19, 11:00 AM"
            ]
        ),
        InterviewRequest(
            title: "Northstar approval",
            status: "Pending employer approval",
            slots: ["Apr 21, 2:00 PM"]
        )
    ]

    static let employerRequests: [InterviewRequest] = [
        InterviewRequest(
            title: "Maya Chen selected a slot",
            status: "Needs approval",
            slots: ["Apr 18, 1:30 PM"]
        ),
        InterviewRequest(
            title: "Jordan Patel selected a slot",
            status: "Needs approval",
            slots: ["Apr 19, 11:00 AM"]
        )
    ]

    static let notifications: [NotificationItem] = [
        NotificationItem(
            title: "Interview request sent",
            body: "A new interview request was created after you liked Maya Chen."
        ),
        NotificationItem(
            title: "Referral used",
            body: "One of your five monthly referral invites was used by a new candidate."
        ),
        NotificationItem(
            title: "Calendar sync needed",
            body: "Connect Google Calendar before sending live interview holds."
        )
    ]
}
