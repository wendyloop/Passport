import SwiftUI

// TODO(deferred): Admin view refactor (~600 lines). Same treatment as the
// employer/candidate views — extract subviews, route networking through the
// service layer. Do it alongside the employer refactor. Effort: medium/large.
// See docs/DEFERRED_WORK.md.
struct AdminHomeView: View {
    let jobs: [JobPostingRecord]
    let employers: [EmployerDirectoryItem]
    let onCreateJob: (JobPostingDraft, URL?) async -> String?
    let onImportSharedPost: (String) async throws -> ImportedJobSuggestion
    let onToggleJobPublishState: (String, Bool) -> Void
    let onRefresh: () -> Void
    let onShowNotifications: () -> Void
    let onSignOut: () -> Void
    /// Supplies a token-refreshed session to the social exporter.
    let socialSession: () async throws -> AuthSession

    @State private var showingCreateSheet = false
    @State private var showingVideoStudio = false
    @State private var selectedVideoURL: URL?
    @State private var selectedVideoName = ""
    @State private var selectedTab: AdminHomeTab = .manage
    @State private var currentPreviewJobID: String?
    @StateObject private var socialExport = SocialExportStore()

    var body: some View {
        NavigationStack {
            Group {
                switch selectedTab {
                case .manage:
                    manageView
                case .feedPreview:
                    feedPreviewView
                case .social:
                    SocialExportView(store: socialExport)
                }
            }
            .background(PassportTheme.background)
            .task {
                socialExport.sessionProvider = socialSession
                await socialExport.loadQueue()
            }
        }
        .fullScreenCover(isPresented: $showingVideoStudio) {
            Scout22VideoStudio(
                purpose: .adminRole,
                startMode: .library,
                onCancel: {
                    showingVideoStudio = false
                },
                onComplete: { composedVideo in
                    selectedVideoURL = composedVideo.url
                    selectedVideoName = composedVideo.fileName
                    showingVideoStudio = false
                    showingCreateSheet = true
                }
            )
        }
        .sheet(isPresented: $showingCreateSheet) {
            AdminCreateJobSheet(
                employers: employers,
                selectedVideoURL: selectedVideoURL,
                videoName: selectedVideoName,
                initialSourceURL: nil,
                onImportSharedPost: onImportSharedPost,
                onCreateJob: onCreateJob
            )
            .presentationDetents([.large])
        }
    }

    private var publishedJobs: [JobPostingRecord] {
        jobs.filter(\.isPublished)
    }

    private var manageView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                tabSelector

                VStack(spacing: 12) {
                    Button {
                        selectedVideoURL = nil
                        selectedVideoName = ""
                        showingCreateSheet = true
                    } label: {
                        Text("Import from Link")
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(PassportTheme.accent)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    Button {
                        showingVideoStudio = true
                    } label: {
                        Text("Select Local Video")
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(PassportTheme.card)
                            .foregroundStyle(PassportTheme.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }

                if jobs.isEmpty {
                    AdminInfoCard(
                        title: "No jobs yet",
                        details: "Paste a TikTok or Instagram link to import a post directly, or upload a local video if you want to host the media inside scout22."
                    )
                } else {
                    ForEach(jobs) { job in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(job.title)
                                        .font(.headline)
                                        .foregroundStyle(PassportTheme.textPrimary)
                                    Text("\(job.companyName) • \(job.location ?? "Remote")")
                                        .foregroundStyle(PassportTheme.textSecondary)
                                }

                                Spacer()

                                if let sourcePlatform = job.sourcePlatform {
                                    Text(sourcePlatform.title)
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(PassportTheme.card)
                                        .foregroundStyle(PassportTheme.textPrimary)
                                        .clipShape(Capsule())
                                }
                            }

                            Text(job.description)
                                .foregroundStyle(PassportTheme.textPrimary)
                                .lineLimit(4)

                            if let sourceURL = job.sourceURL, !sourceURL.isEmpty {
                                Text(sourceURL)
                                    .font(.footnote)
                                    .foregroundStyle(PassportTheme.textSecondary)
                                    .lineLimit(1)
                            }

                            HStack {
                                Text(job.isPublished ? "Published" : "Draft")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(job.isPublished ? PassportTheme.accent : PassportTheme.card)
                                    .foregroundStyle(job.isPublished ? .black : PassportTheme.textPrimary)
                                    .clipShape(Capsule())

                                if job.applicationEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text("Missing apply route")
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(Color.orange.opacity(0.18))
                                        .foregroundStyle(Color.orange)
                                        .clipShape(Capsule())
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
                        .scout22Card(cornerRadius: 22)
                    }
                }
            }
            .padding(20)
        }
    }

    private var feedPreviewView: some View {
        GeometryReader { proxy in
            let pageWidth = proxy.size.width
            let pageHeight = proxy.size.height

            ZStack(alignment: .top) {
                if publishedJobs.isEmpty {
                    VStack(spacing: 16) {
                        header
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                        tabSelector
                            .padding(.horizontal, 20)
                        Spacer()
                        AdminInfoCard(
                            title: "No published feed yet",
                            details: "Publish a job post and it will appear here exactly where candidates see it."
                        )
                        .padding(.horizontal, 20)
                        Spacer()
                    }
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(publishedJobs) { job in
                                AdminFeedPreviewCard(
                                    job: job,
                                    isActive: currentPreviewJobID == job.id
                                )
                                .frame(width: pageWidth, height: pageHeight)
                                .id(job.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $currentPreviewJobID)
                    .ignoresSafeArea()
                    .onAppear {
                        currentPreviewJobID = publishedJobs.first?.id
                    }

                    VStack(spacing: 14) {
                        header
                        tabSelector
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Admin")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(PassportTheme.textPrimary)
                    Text("Import sourced social posts, publish the live feed, and route applications to company inboxes.")
                        .foregroundStyle(PassportTheme.textSecondary)
                }
                Spacer()
                HeaderAction(symbol: "arrow.clockwise", action: onRefresh)
                HeaderAction(symbol: "bell.fill", action: onShowNotifications)
                HeaderAction(symbol: "rectangle.portrait.and.arrow.right", action: onSignOut)
            }
        }
    }

    private var tabSelector: some View {
        HStack(spacing: 10) {
            ForEach(AdminHomeTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(selectedTab == tab ? .black : PassportTheme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(selectedTab == tab ? PassportTheme.accent : PassportTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

}

private enum AdminHomeTab: String, CaseIterable, Identifiable {
    case manage
    case feedPreview
    case social

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manage:
            return "Manage"
        case .feedPreview:
            return "Feed Preview"
        case .social:
            return "Social"
        }
    }
}

private struct AdminCreateJobSheet: View {
    let employers: [EmployerDirectoryItem]
    let selectedVideoURL: URL?
    let videoName: String
    let initialSourceURL: String?
    let onImportSharedPost: (String) async throws -> ImportedJobSuggestion
    let onCreateJob: (JobPostingDraft, URL?) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var draft = JobPostingDraft()
    @State private var errorMessage: String?
    @State private var isImportingMetadata = false
    @State private var isPublishing = false
    @State private var didAttemptInitialImport = false
    @State private var importDiagnostics: ImportDiagnostics?

    private var isLinkImportMode: Bool {
        selectedVideoURL == nil
    }

    private var hasImportedPayload: Bool {
        !draft.sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var videoStatusTitle: String {
        selectedVideoURL == nil ? "Using imported social embed" : "Job video selected"
    }

    private var videoStatusMessage: String {
        selectedVideoURL == nil
            ? "This post will render from the imported TikTok or Instagram link in the candidate feed."
            : videoName
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !isLinkImportMode {
                        employerPicker
                    }
                    if isLinkImportMode {
                        importSection
                        if hasImportedPayload {
                            importedSummarySection
                        }
                    } else {
                        field(title: "Job title", text: $draft.title)
                        field(title: "Company name", text: $draft.companyName)
                        field(title: "Location", text: $draft.location)
                        compensationFields

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Job function")
                                .font(.headline)
                                .foregroundStyle(PassportTheme.textPrimary)

                            Picker("Job function", selection: $draft.jobFunction) {
                                ForEach(JobFunctionOption.allCases) { option in
                                    Text(option.title).tag(option)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(PassportTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        field(title: "Application email", text: $draft.applicationEmail)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Job description")
                                .font(.headline)
                                .foregroundStyle(PassportTheme.textPrimary)

                            TextField("Paste or review the job description", text: $draft.description, axis: .vertical)
                                .lineLimit(6...10)
                                .textFieldStyle(PassportTextFieldStyle())
                        }

                        Toggle(isOn: $draft.isPublished) {
                            Text("Publish immediately")
                                .foregroundStyle(PassportTheme.textPrimary)
                        }
                        .tint(PassportTheme.accent)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(videoStatusTitle)
                            .font(.headline)
                            .foregroundStyle(PassportTheme.textPrimary)
                        Text(videoStatusMessage)
                            .font(.footnote)
                            .foregroundStyle(PassportTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(PassportTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Button {
                        Task {
                            await publishJob()
                        }
                    } label: {
                        HStack {
                            if isPublishing {
                                ProgressView()
                                    .tint(.black)
                            }
                            Text(isPublishing ? "Publishing…" : (isLinkImportMode ? "Publish Imported Post" : "Create Job"))
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(PassportTheme.accent)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .disabled(isPublishing || isImportingMetadata)
                }
                .padding(20)
            }
            .background(PassportTheme.background)
            .navigationTitle("New Job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(PassportTheme.textSecondary)
                }
            }
        }
        .onAppear {
            if draft.sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.sourceURL = initialSourceURL ?? ""
            }
            if draft.employerProfileID.isEmpty {
                draft.employerProfileID = employers.first?.id ?? ""
                draft.companyName = employers.first?.companyName ?? ""
                if !isLinkImportMode {
                    draft.applicationEmail = employers.first?.email ?? ""
                }
            }
            if isLinkImportMode,
               !didAttemptInitialImport,
               !draft.sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                didAttemptInitialImport = true
                Task {
                    await importSharedPost()
                }
            }
        }
        .onChange(of: draft.employerProfileID) { _, newValue in
            guard let employer = employers.first(where: { $0.id == newValue }) else { return }
            draft.companyName = employer.companyName
            if !isLinkImportMode && draft.applicationEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.applicationEmail = employer.email
            }
        }
        .alert("Issue", isPresented: Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue { errorMessage = nil }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import from TikTok / Instagram")
                .font(.headline)
                .foregroundStyle(PassportTheme.textPrimary)

            Text("Paste the shared post link. scout22 will fetch the source page and scrape the description, posting date, and apply route automatically. If the apply route is missing, the post can still be created and will be flagged in admin.")
                .font(.footnote)
                .foregroundStyle(PassportTheme.textSecondary)

            field(title: "Source link", text: $draft.sourceURL)

            Button {
                Task {
                    await importSharedPost()
                }
            } label: {
                HStack {
                    if isImportingMetadata {
                        ProgressView()
                            .tint(.black)
                    }
                    Text(isImportingMetadata ? "Importing…" : "Auto-fill from shared post")
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(PassportTheme.card)
                .foregroundStyle(PassportTheme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(isImportingMetadata || draft.sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(18)
        .scout22Card(cornerRadius: 22)
    }

    private var importedSummarySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("Imported details")
                    .font(.headline)
                    .foregroundStyle(PassportTheme.textPrimary)

                Spacer()

                if let sourcePlatform = draft.sourcePlatform {
                    Text(sourcePlatform.title)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(PassportTheme.card)
                        .foregroundStyle(PassportTheme.textPrimary)
                        .clipShape(Capsule())
                }
            }

            importedRow(title: "Company", value: draft.companyName)
            importedRow(title: "Title", value: draft.title)
            importedRow(title: "Creator", value: draft.sourceCreatorName)
            importedRow(title: "Location", value: draft.location)
            importedRow(title: "Compensation", value: draft.sourceCompensationText)
            importedRow(title: "Apply route", value: draft.applicationEmail, highlightMissing: true)
            importedRow(title: "Extracted email", value: draft.sourceApplyEmailExtracted, highlightMissing: true)
            importedRow(title: "How to apply", value: draft.sourceHowToApplyText)
            importedRow(title: "Posted", value: draft.sourcePostedAt.map(formattedSourceDate) ?? "")
            importedRow(title: "Description", value: draft.description)

            if draft.applicationEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("No apply email was found in the caption. This post can still be published, but it will be flagged in admin until you source a valid apply route.")
                    .font(.footnote)
                    .foregroundStyle(Color.orange)
            }

            if let importDiagnostics {
                diagnosticsSection(importDiagnostics)
            }
        }
        .padding(18)
        .scout22Card(cornerRadius: 22)
    }

    private var employerPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Assign employer")
                .font(.headline)
                .foregroundStyle(PassportTheme.textPrimary)

            Picker("Employer", selection: $draft.employerProfileID) {
                ForEach(employers) { employer in
                    Text("\(employer.companyName) • \(employer.fullName)").tag(employer.id)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(PassportTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var compensationFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Annual pay (optional)")
                .font(.headline)
                .foregroundStyle(PassportTheme.textPrimary)

            HStack(spacing: 12) {
                field(title: "Min", text: $draft.compensationMinAnnual)
                field(title: "Max", text: $draft.compensationMaxAnnual)
            }

            Text("Enter whole numbers only, for example 120000.")
                .font(.footnote)
                .foregroundStyle(PassportTheme.textSecondary)
        }
    }

    private func field(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(PassportTheme.textPrimary)
            TextField(title, text: text)
                .textFieldStyle(PassportTextFieldStyle())
        }
    }

    private func formattedSourceDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func importedRow(title: String, value: String, highlightMissing: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(PassportTheme.textSecondary)
            Text(
                value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (highlightMissing ? "Missing" : "Not found")
                : value
            )
            .font(.subheadline)
            .foregroundStyle(
                value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && highlightMissing
                ? Color.orange
                : PassportTheme.textPrimary
            )
        }
    }

    @State private var showDiagnostics = false

    private func diagnosticsSection(_ diagnostics: ImportDiagnostics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { showDiagnostics.toggle() }
            } label: {
                HStack {
                    Text("Scrape diagnostics")
                        .font(.headline)
                        .foregroundStyle(PassportTheme.textPrimary)
                    Spacer()
                    Image(systemName: showDiagnostics ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PassportTheme.textSecondary)
                }
            }
            .buttonStyle(.plain)

            if showDiagnostics {
                Group {
                    diagRow(label: "Fetch status", value: diagnostics.fetchStatus.map(String.init))
                    diagRow(label: "Content type", value: diagnostics.fetchContentType)
                    diagRow(label: "HTML length", value: diagnostics.htmlLength.map { "\($0) bytes" })
                    diagRow(label: "Source text length", value: diagnostics.sourceTextLength.map { "\($0) chars" })
                    diagRow(label: "OpenAI enabled", value: diagnostics.openAIEnabled.map { $0 ? "Yes" : "No" })
                    diagRow(label: "LLM used", value: diagnostics.llmUsed.map { $0 ? "Yes" : "No" })
                }

                if let meta = diagnostics.scrapedMetadata, !meta.isEmpty {
                    Text("Raw scraped fields")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PassportTheme.textSecondary)
                        .padding(.top, 4)

                    ForEach(meta.keys.sorted(), id: \.self) { key in
                        diagRow(label: key, value: meta[key])
                    }
                } else {
                    diagRow(label: "Raw scraped fields", value: "None found")
                }

                let caption = diagnostics.scrapedMetadata?.values.first(where: { !$0.isEmpty }) ?? ""
                if caption.isEmpty {
                    diagRow(label: "Combined source text", value: "Empty — LLM had nothing to work with")
                }
            }
        }
        .padding(.top, 8)
    }

    private func diagRow(label: String, value: String?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PassportTheme.textSecondary)
                .frame(width: 140, alignment: .leading)
            Text(value?.isEmpty == false ? value! : "—")
                .font(.caption)
                .foregroundStyle(value?.isEmpty == false ? PassportTheme.textPrimary : PassportTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    @MainActor
    private func importSharedPost() async {
        isImportingMetadata = true
        defer { isImportingMetadata = false }

        do {
            let suggestion = try await onImportSharedPost(
                draft.sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            draft.sourceURL = suggestion.sourceURL
            draft.sourcePlatform = suggestion.sourcePlatform
            draft.sourceCreatorName = suggestion.sourceCreatorName ?? ""
            draft.sourceCreatorURL = suggestion.sourceCreatorURL ?? ""
            draft.sourceThumbnailURL = suggestion.sourceThumbnailURL ?? ""
            draft.sourcePostedAt = suggestion.sourcePostedAt
            draft.sourceCaption = suggestion.sourceCaption
            draft.sourceCaptionRaw = suggestion.sourceCaptionRaw
            draft.sourceApplyEmailExtracted = suggestion.sourceApplyEmailExtracted ?? ""
            draft.sourceCompensationText = suggestion.compensation ?? ""
            draft.sourceHowToApplyText = suggestion.howToApply ?? ""
            draft.importedVideoURL = suggestion.videoPlayURL ?? ""
            importDiagnostics = suggestion.diagnostics

            if let company = suggestion.company, !company.isEmpty {
                draft.companyName = company
            }

            if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.title = suggestion.title ?? draft.title
            } else if let title = suggestion.title, !title.isEmpty {
                draft.title = title
            }

            if let location = suggestion.location, !location.isEmpty {
                draft.location = location
            }
            if let description = suggestion.description, !description.isEmpty {
                draft.description = description
            }
            if let applicationEmail = suggestion.applicationEmail, !applicationEmail.isEmpty {
                draft.applicationEmail = applicationEmail
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func publishJob() async {
        guard selectedVideoURL != nil || !draft.sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Select a video or import a shared TikTok / Instagram link before publishing."
            return
        }

        if !isLinkImportMode && draft.employerProfileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = employers.isEmpty
                ? "No employer profiles found. An employer account must be created first."
                : "Select an employer before publishing."
            return
        }

        isPublishing = true
        defer { isPublishing = false }

        let normalized = draft
        let error = await onCreateJob(normalized, selectedVideoURL)
        if let error, !error.isEmpty {
            errorMessage = error
            return
        }

        dismiss()
    }
}

private struct AdminFeedPreviewCard: View {
    let job: JobPostingRecord
    let isActive: Bool

    var body: some View {
        ZStack {
            RemoteVideoSurface(
                urlString: job.videoURL,
                isActive: isActive,
                allowsTapToTogglePlayback: true,
                showsPlayOverlayWhenPaused: true,
                isMuted: true
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.20),
                    Color.black.opacity(0.88)
                ],
                startPoint: .center,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                HStack(alignment: .bottom, spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            if let sourcePlatform = job.sourcePlatform {
                                previewTag(sourcePlatform.title, accent: true)
                            }
                            if let location = job.location, !location.isEmpty {
                                previewTag(location, accent: false)
                            }
                        }

                        Text(job.title)
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundStyle(.white)

                        Text(job.companyName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))

                        Text(job.description)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(3)

                        Text("Apply route: \(job.applicationEmail)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.72))

                        if let sourceURL = job.sourceURL, !sourceURL.isEmpty {
                            Text(sourceURL)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.62))
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 34)
            }
        }
        .background(Color.black)
    }

    private func previewTag(_ text: String, accent: Bool) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(accent ? PassportTheme.accentSoft.opacity(0.95) : Color.black.opacity(0.45))
            .foregroundStyle(accent ? PassportTheme.accent : .white)
            .clipShape(Capsule())
    }
}

private struct AdminInfoCard: View {
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
        .scout22Card(cornerRadius: 22)
    }
}
