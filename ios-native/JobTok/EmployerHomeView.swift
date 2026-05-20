import SwiftUI

struct EmployerHomeView: View {
    let fullName: String
    let jobs: [JobPostingRecord]
    let applications: [JobApplicationRecord]
    let discoverableCandidates: [DiscoverableCandidateRecord]
    let latestOutreachByCandidateID: [String: CandidateOutreachRecord]
    let onRefresh: () -> Void
    let onToggleJobPublishState: (String, Bool) -> Void
    let onReachOut: (String, String?, String, String) -> Void
    let onShowNotifications: () -> Void
    let onSignOut: () -> Void

    @State private var selectedJobFunctionRawValue = "all"
    @State private var dreamRoleQuery = ""
    @State private var schoolQuery = ""
    @State private var employerQuery = ""
    @State private var selectedCandidateForOutreach: DiscoverableCandidateRecord?

    private var selectedJobFunction: JobFunctionOption? {
        guard selectedJobFunctionRawValue != "all" else { return nil }
        return JobFunctionOption(rawValue: selectedJobFunctionRawValue)
    }

    private var filteredCandidates: [DiscoverableCandidateRecord] {
        discoverableCandidates.filter { candidate in
            if let selectedJobFunction, candidate.jobFunction != selectedJobFunction {
                return false
            }

            if !dreamRoleQuery.isEmpty {
                let dreamRole = candidate.dreamRole ?? ""
                if !dreamRole.localizedCaseInsensitiveContains(dreamRoleQuery) {
                    return false
                }
            }

            if !schoolQuery.isEmpty {
                let schoolName = candidate.schoolName ?? ""
                if !schoolName.localizedCaseInsensitiveContains(schoolQuery) {
                    return false
                }
            }

            if !employerQuery.isEmpty {
                let flattenedEmployers = candidate.previousEmployers.joined(separator: " ")
                if !flattenedEmployers.localizedCaseInsensitiveContains(employerQuery) {
                    return false
                }
            }

            return true
        }
    }

    var body: some View {
        TabView {
            jobsView
                .tabItem {
                    Label("Jobs", systemImage: "briefcase.fill")
                }

            applicantsView
                .tabItem {
                    Label("Applicants", systemImage: "person.2.fill")
                }

            discoveryView
                .tabItem {
                    Label("Discover", systemImage: "sparkles")
                }
        }
        .tint(PassportTheme.accent)
        .sheet(item: $selectedCandidateForOutreach) { candidate in
            EmployerOutreachSheet(
                candidate: candidate,
                jobs: jobs,
                latestOutreach: latestOutreachByCandidateID[candidate.id],
                onSend: { relatedJobID, subject, message in
                    onReachOut(candidate.id, relatedJobID, subject, message)
                    selectedCandidateForOutreach = nil
                }
            )
            .presentationDetents([.large])
        }
    }

    private var jobsView: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    screenHeader(
                        title: fullName.isEmpty ? "Employer" : fullName,
                        subtitle: "Own the feed you’ve published and manage what is live."
                    )

                    if jobs.isEmpty {
                        EmployerInfoCard(
                            title: "No jobs assigned",
                            details: "Admins can assign your first JobTok role from the admin portal."
                        )
                    } else {
                        ForEach(jobs) { job in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(job.title)
                                    .font(.headline)
                                    .foregroundStyle(PassportTheme.textPrimary)

                                Text("\(job.companyName) • \(job.location ?? "Remote")")
                                    .foregroundStyle(PassportTheme.textSecondary)

                                Text(job.description)
                                    .foregroundStyle(PassportTheme.textPrimary)
                                    .lineLimit(4)

                                HStack {
                                    statusPill(
                                        title: job.isPublished ? "Published" : "Draft",
                                        isEmphasized: job.isPublished
                                    )

                                    if let jobFunction = job.jobFunction {
                                        statusPill(title: jobFunction.title, isEmphasized: false)
                                    }

                                    Spacer()

                                    Button(job.isPublished ? "Unpublish" : "Publish") {
                                        onToggleJobPublishState(job.id, !job.isPublished)
                                    }
                                    .font(.subheadline.weight(.bold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(PassportTheme.card)
                                    .foregroundStyle(PassportTheme.textPrimary)
                                    .clipShape(Capsule())
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18)
                            .background(PassportTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                    }
                }
                .padding(20)
            }
            .background(PassportTheme.background)
        }
    }

    private var applicantsView: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    screenHeader(
                        title: "Applicants",
                        subtitle: "Every in-app application arrives here with the saved resume snapshot and pitch."
                    )

                    if applications.isEmpty {
                        EmployerInfoCard(
                            title: "No applicants yet",
                            details: "Once candidates apply to your jobs, their profile snapshot and pitch video will appear here."
                        )
                    } else {
                        ForEach(applications) { application in
                            EmployerApplicantCard(application: application)
                        }
                    }
                }
                .padding(20)
            }
            .background(PassportTheme.background)
        }
    }

    private var discoveryView: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    screenHeader(
                        title: "Discover",
                        subtitle: "Browse candidates who made themselves discoverable to hiring employers."
                    )

                    discoveryFilters

                    if filteredCandidates.isEmpty {
                        EmployerInfoCard(
                            title: discoverableCandidates.isEmpty ? "No discoverable candidates yet" : "No matches for these filters",
                            details: discoverableCandidates.isEmpty
                                ? "Candidates will appear here after they set their profile visibility to discoverable."
                                : "Adjust dream role, school, prior employers, or job function filters."
                        )
                    } else {
                        ForEach(filteredCandidates) { candidate in
                            EmployerDiscoveryCard(
                                candidate: candidate,
                                latestOutreach: latestOutreachByCandidateID[candidate.id],
                                onReachOut: {
                                    selectedCandidateForOutreach = candidate
                                }
                            )
                        }
                    }
                }
                .padding(20)
            }
            .background(PassportTheme.background)
        }
    }

    private var discoveryFilters: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Filters")
                .font(.headline)
                .foregroundStyle(PassportTheme.textPrimary)

            Picker("Job function", selection: $selectedJobFunctionRawValue) {
                Text("All Functions").tag("all")
                ForEach(JobFunctionOption.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(PassportTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            TextField("Dream role", text: $dreamRoleQuery)
                .textFieldStyle(PassportTextFieldStyle())

            TextField("School", text: $schoolQuery)
                .textFieldStyle(PassportTextFieldStyle())

            TextField("Previous employer", text: $employerQuery)
                .textFieldStyle(PassportTextFieldStyle())
        }
        .padding(18)
        .background(PassportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func screenHeader(title: String, subtitle: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(PassportTheme.textPrimary)
                Text(subtitle)
                    .foregroundStyle(PassportTheme.textSecondary)
            }

            Spacer()

            HeaderAction(symbol: "arrow.clockwise", action: onRefresh)
            HeaderAction(symbol: "bell.fill", action: onShowNotifications)
            HeaderAction(symbol: "rectangle.portrait.and.arrow.right", action: onSignOut)
        }
    }

    private func statusPill(title: String, isEmphasized: Bool) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isEmphasized ? PassportTheme.accent : PassportTheme.card)
            .foregroundStyle(isEmphasized ? Color.black : PassportTheme.textPrimary)
            .clipShape(Capsule())
    }
}

private struct EmployerApplicantCard: View {
    let application: JobApplicationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if application.candidateVideoURL != nil {
                RemoteVideoSurface(urlString: application.candidateVideoURL, isActive: true)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(application.candidateName)
                    .font(.headline)
                    .foregroundStyle(PassportTheme.textPrimary)

                if let headline = application.candidateHeadline, !headline.isEmpty {
                    Text(headline)
                        .foregroundStyle(PassportTheme.textPrimary)
                }

                Text("\(application.jobTitle) • \(application.companyName)")
                    .foregroundStyle(PassportTheme.textSecondary)

                if let school = application.candidateSchoolName, !school.isEmpty {
                    Text("School: \(school)")
                        .foregroundStyle(PassportTheme.textSecondary)
                }

                if let dreamRole = application.candidateDreamRole, !dreamRole.isEmpty {
                    Text("Dream role: \(dreamRole)")
                        .foregroundStyle(PassportTheme.textSecondary)
                }

                if !application.candidatePreviousEmployers.isEmpty {
                    Text("Previous employers: \(application.candidatePreviousEmployers.joined(separator: ", "))")
                        .foregroundStyle(PassportTheme.textSecondary)
                }

                HStack {
                    applicationStatusPill(title: application.status.capitalized)
                    applicationStatusPill(title: application.emailDeliveryStatus.capitalized)
                }

                if let coverNote = application.coverNote, !coverNote.isEmpty {
                    Text("Cover note")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(PassportTheme.textPrimary)
                    Text(coverNote)
                        .foregroundStyle(PassportTheme.textSecondary)
                }

                if let resumeFileName = application.resumeFileName, !resumeFileName.isEmpty {
                    Text("Resume snapshot: \(resumeFileName)")
                        .foregroundStyle(PassportTheme.textPrimary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(PassportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func applicationStatusPill(title: String) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(PassportTheme.card)
            .foregroundStyle(PassportTheme.textPrimary)
            .clipShape(Capsule())
    }
}

private struct EmployerDiscoveryCard: View {
    let candidate: DiscoverableCandidateRecord
    let latestOutreach: CandidateOutreachRecord?
    let onReachOut: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RemoteVideoSurface(urlString: candidate.videoURL, isActive: true)
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(candidate.fullName ?? "Candidate")
                    .font(.headline)
                    .foregroundStyle(PassportTheme.textPrimary)

                if let headline = candidate.headline, !headline.isEmpty {
                    Text(headline)
                        .foregroundStyle(PassportTheme.textPrimary)
                }

                if let schoolName = candidate.schoolName, !schoolName.isEmpty {
                    Text("School: \(schoolName)")
                        .foregroundStyle(PassportTheme.textSecondary)
                }

                if let jobFunction = candidate.jobFunction {
                    Text("Function: \(jobFunction.title)")
                        .foregroundStyle(PassportTheme.textSecondary)
                }

                if let dreamRole = candidate.dreamRole, !dreamRole.isEmpty {
                    Text("Dream role: \(dreamRole)")
                        .foregroundStyle(PassportTheme.textSecondary)
                }

                if !candidate.previousEmployers.isEmpty {
                    Text("Previous employers: \(candidate.previousEmployers.joined(separator: ", "))")
                        .foregroundStyle(PassportTheme.textSecondary)
                }

                Text("Visibility: \(candidate.discoveryVisibility.title)")
                    .foregroundStyle(PassportTheme.textSecondary)

                if let latestOutreach {
                    Text("Last outreach: \(formattedDate(latestOutreach.createdAt)) • \(latestOutreach.deliveryStatus.capitalized)")
                        .font(.footnote)
                        .foregroundStyle(PassportTheme.textSecondary)
                }
            }

            Button(action: onReachOut) {
                Text(latestOutreach == nil ? "Reach Out" : "Reach Out Again")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(PassportTheme.accent)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(PassportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct EmployerOutreachSheet: View {
    let candidate: DiscoverableCandidateRecord
    let jobs: [JobPostingRecord]
    let latestOutreach: CandidateOutreachRecord?
    let onSend: (String?, String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedRelatedJobID = ""
    @State private var subject = ""
    @State private var message = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    EmployerInfoCard(
                        title: candidate.fullName ?? "Candidate",
                        details: [
                            candidate.headline,
                            candidate.dreamRole.map { "Dream role: \($0)" },
                            candidate.schoolName.map { "School: \($0)" }
                        ]
                        .compactMap { $0 }
                        .joined(separator: "\n")
                    )

                    if let latestOutreach {
                        EmployerInfoCard(
                            title: "Latest outreach",
                            details: "\(latestOutreach.subject)\nSent \(formattedDate(latestOutreach.createdAt)) • \(latestOutreach.deliveryStatus.capitalized)"
                        )
                    }

                    if !jobs.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Related job (optional)")
                                .font(.headline)
                                .foregroundStyle(PassportTheme.textPrimary)

                            Picker("Related job", selection: $selectedRelatedJobID) {
                                Text("None").tag("")
                                ForEach(jobs) { job in
                                    Text("\(job.title) • \(job.companyName)").tag(job.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(PassportTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .padding(18)
                        .background(PassportTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Subject")
                            .font(.headline)
                            .foregroundStyle(PassportTheme.textPrimary)

                        TextField("Subject", text: $subject)
                            .textFieldStyle(PassportTextFieldStyle())

                        Text("Message")
                            .font(.headline)
                            .foregroundStyle(PassportTheme.textPrimary)

                        TextEditor(text: $message)
                            .frame(minHeight: 180)
                            .padding(12)
                            .background(PassportTheme.card)
                            .foregroundStyle(PassportTheme.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(18)
                    .background(PassportTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                    Button {
                        let relatedJobID = selectedRelatedJobID.isEmpty ? nil : selectedRelatedJobID
                        onSend(relatedJobID, subject.trimmingCharacters(in: .whitespacesAndNewlines), message.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    } label: {
                        Text("Send Outreach")
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(PassportTheme.accent)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .disabled(subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(20)
            }
            .background(PassportTheme.background)
            .navigationTitle("Reach Out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(PassportTheme.textSecondary)
                }
            }
            .onAppear {
                if let firstJob = jobs.first {
                    selectedRelatedJobID = firstJob.id
                }
                subject = defaultSubject
                message = defaultMessage
            }
        }
    }

    private var defaultSubject: String {
        if let dreamRole = candidate.dreamRole, !dreamRole.isEmpty {
            return "Opportunity for \(dreamRole)"
        }
        return "Opportunity from JobTok"
    }

    private var defaultMessage: String {
        let name = candidate.fullName ?? "there"
        if let relatedJob = jobs.first(where: { $0.id == selectedRelatedJobID }) {
            return "Hi \(name),\n\nI came across your JobTok profile and think you could be a strong fit for our \(relatedJob.title) role at \(relatedJob.companyName). If you’re interested, reply and we can continue the conversation.\n"
        }
        return "Hi \(name),\n\nI came across your JobTok profile and wanted to reach out about opportunities on our team. If you’re interested, reply and we can continue the conversation.\n"
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct EmployerInfoCard: View {
    let title: String
    let details: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(PassportTheme.textPrimary)

            Text(details)
                .foregroundStyle(PassportTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(PassportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
