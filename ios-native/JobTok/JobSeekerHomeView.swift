import SwiftUI
import PhotosUI
import AVFoundation
import CoreTransferable
import UniformTypeIdentifiers

struct JobSeekerHomeView: View {
    let profile: CandidateProfileDraft
    let jobs: [JobPostingRecord]
    let applications: [JobApplicationRecord]
    let onSaveProfile: (CandidateProfileDraft) -> Void
    let onUploadResume: (URL) -> Void
    let onUploadVideo: (URL, Double) -> Void
    let onApply: (String, String?) -> Void
    let onRefresh: () -> Void
    let onShowNotifications: () -> Void
    let onSignOut: () -> Void

    @State private var workingProfile: CandidateProfileDraft
    @State private var isEditingProfile = false
    @State private var showingResumeImporter = false
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var importErrorMessage: String?
    @State private var currentJobID: String?
    @State private var applyingJob: JobPostingRecord?
    @State private var coverNote = ""

    init(
        profile: CandidateProfileDraft,
        jobs: [JobPostingRecord],
        applications: [JobApplicationRecord],
        onSaveProfile: @escaping (CandidateProfileDraft) -> Void,
        onUploadResume: @escaping (URL) -> Void,
        onUploadVideo: @escaping (URL, Double) -> Void,
        onApply: @escaping (String, String?) -> Void,
        onRefresh: @escaping () -> Void,
        onShowNotifications: @escaping () -> Void,
        onSignOut: @escaping () -> Void
    ) {
        self.profile = profile
        self.jobs = jobs
        self.applications = applications
        self.onSaveProfile = onSaveProfile
        self.onUploadResume = onUploadResume
        self.onUploadVideo = onUploadVideo
        self.onApply = onApply
        self.onRefresh = onRefresh
        self.onShowNotifications = onShowNotifications
        self.onSignOut = onSignOut
        _workingProfile = State(initialValue: profile)
    }

    private var appliedJobIDs: Set<String> {
        Set(applications.map(\.jobID))
    }

    var body: some View {
        TabView {
            jobsFeed
                .tabItem {
                    Label("Jobs", systemImage: "play.square.fill")
                }

            applicationsView
                .tabItem {
                    Label("Applications", systemImage: "tray.full")
                }

            profileView
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
        }
        .tint(PassportTheme.accent)
        .sheet(isPresented: $isEditingProfile) {
            CandidateProfileEditor(
                profile: $workingProfile,
                onSave: {
                    onSaveProfile(workingProfile)
                }
            )
            .presentationDetents([.large])
        }
        .sheet(item: $applyingJob) { job in
            ApplySheet(
                job: job,
                coverNote: $coverNote,
                onApply: {
                    let trimmed = coverNote.trimmingCharacters(in: .whitespacesAndNewlines)
                    onApply(job.id, trimmed.isEmpty ? nil : trimmed)
                    coverNote = ""
                    applyingJob = nil
                }
            )
        }
        .fileImporter(
            isPresented: $showingResumeImporter,
            allowedContentTypes: supportedResumeTypes,
            allowsMultipleSelection: false
        ) { result in
            handleResumeImport(result: result)
        }
        .onChange(of: selectedVideoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await handleVideoSelection(item: newItem)
            }
        }
        .onChange(of: profile) { _, newValue in
            workingProfile = newValue
        }
        .alert("Import issue", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    importErrorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "")
        }
    }

    private var jobsFeed: some View {
        GeometryReader { proxy in
            let pageWidth = proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing
            let pageHeight = proxy.size.height + proxy.safeAreaInsets.top

            ZStack(alignment: .top) {
                if jobs.isEmpty {
                    EmptyStateView(
                        title: "No jobs live yet",
                        message: "Admins can publish the first JobTok openings from the admin portal."
                    )
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(jobs) { job in
                                JobFeedCard(
                                    job: job,
                                    alreadyApplied: appliedJobIDs.contains(job.id),
                                    isActive: currentJobID == job.id,
                                    onApply: {
                                        applyingJob = job
                                    }
                                )
                                .frame(width: pageWidth, height: pageHeight)
                                .clipped()
                                .id(job.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $currentJobID)
                    .frame(width: pageWidth, height: pageHeight)
                    .offset(y: -proxy.safeAreaInsets.top)
                }

                topBar
                    .padding(.horizontal, 10)
                    .padding(.top, max(proxy.safeAreaInsets.top - 2, 0))
                    .offset(y: -24)
            }
            .onAppear {
                if currentJobID == nil {
                    currentJobID = jobs.first?.id
                }
            }
            .onChange(of: jobs.map(\.id)) { _, ids in
                guard let first = ids.first else {
                    currentJobID = nil
                    return
                }
                if let currentJobID, ids.contains(currentJobID) {
                    return
                }
                self.currentJobID = first
            }
        }
    }

    private var applicationsView: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    screenHeader(
                        title: "Applications",
                        subtitle: "Track everything you’ve sent through JobTok."
                    )

                    if applications.isEmpty {
                        SimpleProfileCard(
                            title: "No applications yet",
                            details: "Apply to a job from the feed and it will appear here."
                        )
                    } else {
                        ForEach(applications) { application in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(application.jobTitle)
                                    .font(.headline)
                                    .foregroundStyle(PassportTheme.textPrimary)
                                Text(application.companyName)
                                    .foregroundStyle(PassportTheme.textSecondary)
                                if let jobLocation = application.jobLocation, !jobLocation.isEmpty {
                                    Text(jobLocation)
                                        .foregroundStyle(PassportTheme.textSecondary)
                                }
                                Text("Status: \(application.status.capitalized)")
                                    .foregroundStyle(PassportTheme.textPrimary)
                                Text("Email delivery: \(application.emailDeliveryStatus.capitalized)")
                                    .font(.footnote)
                                    .foregroundStyle(PassportTheme.textSecondary)
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

    private var profileView: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    screenHeader(
                        title: "Profile",
                        subtitle: "Resume, pitch, and the profile employers receive with your application or discovery visibility."
                    )

                    profileCard
                    mediaCard
                    phaseTwoNote
                }
                .padding(20)
            }
            .background(PassportTheme.background)
        }
    }

    private var topBar: some View {
        HStack {
            Text("JobTok")
                .font(.headline.weight(.bold))
                .foregroundStyle(PassportTheme.textPrimary)

            Spacer()

            HeaderAction(symbol: "arrow.clockwise", action: onRefresh)
            HeaderAction(symbol: "bell.fill", action: onShowNotifications)
            HeaderAction(symbol: "rectangle.portrait.and.arrow.right", action: onSignOut)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial.opacity(0.4))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(PassportTheme.border.opacity(0.3), lineWidth: 1))
    }

    private func screenHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
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
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(workingProfile.fullName.isEmpty ? "Candidate" : workingProfile.fullName)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(PassportTheme.textPrimary)
                    Text(workingProfile.headline)
                        .foregroundStyle(PassportTheme.textPrimary)
                }
                Spacer()
                Button("Edit") {
                    isEditingProfile = true
                }
                .font(.subheadline.weight(.bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(PassportTheme.card)
                .foregroundStyle(PassportTheme.textPrimary)
                .clipShape(Capsule())
            }

            Divider().overlay(PassportTheme.border)

            Text("School: \(workingProfile.school)")
                .foregroundStyle(PassportTheme.textSecondary)
            Text("Employers: \(workingProfile.employers.joined(separator: ", "))")
                .foregroundStyle(PassportTheme.textSecondary)
            Text("Job function: \(workingProfile.jobFunction.title)")
                .foregroundStyle(PassportTheme.textSecondary)
            Text("Visibility: \(workingProfile.visibility.title)")
                .foregroundStyle(PassportTheme.textSecondary)
            if !workingProfile.dreamRole.isEmpty {
                Text("Dream role: \(workingProfile.dreamRole)")
                    .foregroundStyle(PassportTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(PassportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var mediaCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Profile media")
                .font(.headline)
                .foregroundStyle(PassportTheme.textPrimary)

            HStack(spacing: 12) {
                Button {
                    showingResumeImporter = true
                } label: {
                    Label("Import Resume", systemImage: "doc.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .background(PassportTheme.surface)
                .foregroundStyle(PassportTheme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                PhotosPicker(
                    selection: $selectedVideoItem,
                    matching: .videos,
                    photoLibrary: .shared()
                ) {
                    Label("Upload Pitch", systemImage: "video.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .background(PassportTheme.accent)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            Text("Pitch video must be 1:00 or shorter.")
                .font(.footnote)
                .foregroundStyle(PassportTheme.textSecondary)

            if let resumeFileName = workingProfile.resumeFileName {
                SimpleProfileCard(
                    title: "Resume ready",
                    details: "\(resumeFileName)\nImported \(formattedImportDate(workingProfile.resumeImportedAt))"
                )
            }

            if let videoFileName = workingProfile.introVideoFileName {
                let duration = formattedDuration(workingProfile.introVideoDuration ?? 0)
                SimpleProfileCard(
                    title: "Pitch ready",
                    details: "\(videoFileName)\nDuration \(duration)"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(PassportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var phaseTwoNote: some View {
        SimpleProfileCard(
            title: "Discovery visibility",
            details: "Discovery is live. Set your visibility to control whether hiring employers can find you directly, or only see your profile after you apply."
        )
    }

    private var supportedResumeTypes: [UTType] {
        var types: [UTType] = [.pdf, .plainText, .rtf]
        if let docx = UTType(filenameExtension: "docx") { types.append(docx) }
        if let doc = UTType(filenameExtension: "doc") { types.append(doc) }
        return types
    }

    private func handleResumeImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard let copiedURL = copyImportedFileToTemporaryDirectory(from: url) else { return }
            workingProfile.resumeFileName = copiedURL.lastPathComponent
            workingProfile.resumeImportedAt = Date()
            onUploadResume(copiedURL)
        case .failure(let error):
            importErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func handleVideoSelection(item: PhotosPickerItem) async {
        do {
            guard let movie = try await item.loadTransferable(type: JobSeekerSelectedMovie.self) else {
                importErrorMessage = "The selected video could not be loaded."
                return
            }

            let asset = AVURLAsset(url: movie.url)
            let duration = try await asset.load(.duration).seconds

            guard duration <= 60 else {
                importErrorMessage = "Your pitch video must be 60 seconds or shorter."
                selectedVideoItem = nil
                return
            }

            workingProfile.introVideoFileName = movie.fileName
            workingProfile.introVideoDuration = duration
            onUploadVideo(movie.url, duration)
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    private func formattedDuration(_ duration: Double) -> String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formattedImportDate(_ date: Date?) -> String {
        guard let date else { return "just now" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func copyImportedFileToTemporaryDirectory(from url: URL) -> URL? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let destination = URL(filePath: NSTemporaryDirectory()).appending(path: url.lastPathComponent)

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            importErrorMessage = error.localizedDescription
            return nil
        }
    }
}

private struct JobFeedCard: View {
    let job: JobPostingRecord
    let alreadyApplied: Bool
    let isActive: Bool
    let onApply: () -> Void

    var body: some View {
        ZStack {
            RemoteVideoSurface(urlString: job.videoURL, isActive: isActive)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.1),
                    Color.black.opacity(0.92)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 12) {
                    if let jobFunction = job.jobFunction {
                        Text(jobFunction.title.uppercased())
                            .font(.caption.weight(.bold))
                            .tracking(1.1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(PassportTheme.surface.opacity(0.92))
                            .foregroundStyle(PassportTheme.textPrimary)
                            .clipShape(Capsule())
                    }

                    Text(job.title)
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(PassportTheme.textPrimary)

                    Text(job.companyName)
                        .font(.headline)
                        .foregroundStyle(PassportTheme.textPrimary)

                    if let location = job.location, !location.isEmpty {
                        Text(location)
                            .foregroundStyle(PassportTheme.textSecondary)
                    }

                    Text(job.description)
                        .font(.subheadline)
                        .foregroundStyle(PassportTheme.textPrimary)
                        .lineLimit(5)

                    Button(action: onApply) {
                        Text(alreadyApplied ? "Already Applied" : "Apply Now")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(alreadyApplied ? PassportTheme.card : PassportTheme.accent)
                            .foregroundStyle(alreadyApplied ? PassportTheme.textPrimary : .black)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .disabled(alreadyApplied)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 72)
            }
        }
    }
}

private struct ApplySheet: View {
    let job: JobPostingRecord
    @Binding var coverNote: String
    let onApply: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(job.title)
                    .font(.title2.bold())
                Text(job.companyName)
                    .foregroundStyle(PassportTheme.textSecondary)

                TextEditor(text: $coverNote)
                    .frame(minHeight: 160)
                    .padding(12)
                    .background(PassportTheme.card)
                    .foregroundStyle(PassportTheme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text("Optional note. Your saved resume and pitch profile will be emailed automatically.")
                    .font(.footnote)
                    .foregroundStyle(PassportTheme.textSecondary)

                Button {
                    onApply()
                    dismiss()
                } label: {
                    Text("Submit Application")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(PassportTheme.accent)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                Spacer()
            }
            .padding(20)
            .background(PassportTheme.background)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(PassportTheme.textSecondary)
                }
            }
        }
    }
}

private struct CandidateProfileEditor: View {
    @Binding var profile: CandidateProfileDraft
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var employersText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    profileField(title: "Full name", text: $profile.fullName)
                    profileField(title: "Headline", text: $profile.headline, axis: .vertical)
                    profileField(title: "School", text: $profile.school)
                    profileField(
                        title: "Previous employers",
                        text: $employersText,
                        axis: .vertical,
                        placeholder: "Figma, Notion, Stripe"
                    )
                    profileField(title: "Dream role", text: $profile.dreamRole)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Job function")
                            .font(.headline)
                            .foregroundStyle(PassportTheme.textPrimary)

                        Picker("Job function", selection: $profile.jobFunction) {
                            ForEach(JobFunctionOption.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 150)
                    }
                    .padding(18)
                    .background(PassportTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Visibility")
                            .font(.headline)
                            .foregroundStyle(PassportTheme.textPrimary)

                        Picker("Visibility", selection: $profile.visibility) {
                            ForEach(CandidateVisibility.allCases) { visibility in
                                Text(visibility.title).tag(visibility)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(PassportTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                        Text(profile.visibility.explanation)
                            .font(.footnote)
                            .foregroundStyle(PassportTheme.textSecondary)
                    }
                    .padding(18)
                    .background(PassportTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .padding(20)
            }
            .background(PassportTheme.background)
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(PassportTheme.textSecondary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        profile.employers = employersText
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        onSave()
                        dismiss()
                    }
                    .foregroundStyle(PassportTheme.accent)
                }
            }
            .onAppear {
                employersText = profile.employers.joined(separator: ", ")
            }
        }
    }

    private func profileField(
        title: String,
        text: Binding<String>,
        axis: Axis = .horizontal,
        placeholder: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(PassportTheme.textPrimary)

            TextField(placeholder ?? title, text: text, axis: axis)
                .textFieldStyle(PassportTextFieldStyle())
                .lineLimit(axis == .vertical ? 3...6 : 1...1)
        }
        .padding(18)
        .background(PassportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct SimpleProfileCard: View {
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

private struct EmptyStateView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(PassportTheme.textPrimary)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(PassportTheme.textSecondary)
        }
        .padding(24)
    }
}

private struct JobSeekerSelectedMovie: Transferable {
    let url: URL
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let temporaryDirectory = URL(filePath: NSTemporaryDirectory())
            let copiedURL = temporaryDirectory.appending(path: received.file.lastPathComponent)

            if FileManager.default.fileExists(atPath: copiedURL.path) {
                try FileManager.default.removeItem(at: copiedURL)
            }

            try FileManager.default.copyItem(at: received.file, to: copiedURL)
            return JobSeekerSelectedMovie(url: copiedURL, fileName: received.file.lastPathComponent)
        }
    }
}
