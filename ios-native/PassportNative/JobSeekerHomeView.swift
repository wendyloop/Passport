import SwiftUI
import PhotosUI
import AVFoundation
import CoreTransferable
import UniformTypeIdentifiers

struct JobSeekerHomeView: View {
    let profile: CandidateProfileDraft
    let requests: [JobSeekerRequestItem]
    let openSlotsByEmployer: [String: [AvailabilitySlotRecord]]
    let onSaveProfile: (CandidateProfileDraft) -> Void
    let onUploadResume: (URL) -> Void
    let onUploadVideo: (URL, Double) -> Void
    let onSelectSlot: (String, String) -> Void
    let onShowNotifications: () -> Void
    let onSignOut: () -> Void

    @State private var workingProfile: CandidateProfileDraft
    @State private var isEditingProfile = false
    @State private var showingResumeImporter = false
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var importErrorMessage: String?

    init(
        profile: CandidateProfileDraft,
        requests: [JobSeekerRequestItem],
        openSlotsByEmployer: [String: [AvailabilitySlotRecord]],
        onSaveProfile: @escaping (CandidateProfileDraft) -> Void,
        onUploadResume: @escaping (URL) -> Void,
        onUploadVideo: @escaping (URL, Double) -> Void,
        onSelectSlot: @escaping (String, String) -> Void,
        onShowNotifications: @escaping () -> Void,
        onSignOut: @escaping () -> Void
    ) {
        self.profile = profile
        self.requests = requests
        self.openSlotsByEmployer = openSlotsByEmployer
        self.onSaveProfile = onSaveProfile
        self.onUploadResume = onUploadResume
        self.onUploadVideo = onUploadVideo
        self.onSelectSlot = onSelectSlot
        self.onShowNotifications = onShowNotifications
        self.onSignOut = onSignOut
        _workingProfile = State(initialValue: profile)
    }

    var body: some View {
        TabView {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(
                            title: "Profile",
                            subtitle: "Your public candidate profile for employers."
                        )

                        profileCard
                        mediaCard
                    }
                    .padding(20)
                }
                .background(PassportTheme.background)
            }
            .tabItem {
                Label("Profile", systemImage: "person.crop.circle")
            }

            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(
                            title: "Interview Requests",
                            subtitle: "Employers you interest can send requests and let you choose from open slots."
                        )

                        if requests.isEmpty {
                            SimpleProfileCard(
                                title: "No requests yet",
                                details: "Once an employer likes your video profile, their interview request will show up here."
                            )
                        } else {
                            ForEach(requests) { request in
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(request.employerName)
                                        .font(.headline)
                                        .foregroundStyle(PassportTheme.textPrimary)

                                    Text("Status: \(request.status)")
                                        .foregroundStyle(PassportTheme.textSecondary)

                                    let slots = openSlotsByEmployer[request.employerProfileID] ?? []
                                    if slots.isEmpty {
                                        Text("No open slots published right now.")
                                            .font(.footnote)
                                            .foregroundStyle(PassportTheme.textSecondary)
                                    } else {
                                        VStack(spacing: 10) {
                                            ForEach(slots) { slot in
                                                Button {
                                                    onSelectSlot(request.id, slot.id)
                                                } label: {
                                                    Text(slotLabel(slot))
                                                        .font(.subheadline.weight(.semibold))
                                                        .frame(maxWidth: .infinity, alignment: .leading)
                                                        .padding(.horizontal, 14)
                                                        .padding(.vertical, 12)
                                                        .background(PassportTheme.card)
                                                        .foregroundStyle(PassportTheme.textPrimary)
                                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                                }
                                            }
                                        }
                                    }
                                }
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
            .tabItem {
                Label("Requests", systemImage: "calendar")
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

    private func header(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(PassportTheme.textPrimary)

                    Text(subtitle)
                        .foregroundStyle(PassportTheme.textSecondary)
                }

                Spacer()

                Button(action: onShowNotifications) {
                    Image(systemName: "bell")
                        .foregroundStyle(PassportTheme.textPrimary)
                        .padding(10)
                        .background(PassportTheme.surface)
                        .clipShape(Circle())
                }

                Button {
                    isEditingProfile = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(PassportTheme.textPrimary)
                        .padding(10)
                        .background(PassportTheme.surface)
                        .clipShape(Circle())
                }
            }

            Button("Sign out", action: onSignOut)
                .foregroundStyle(PassportTheme.danger)
        }
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(workingProfile.fullName.isEmpty ? "Candidate" : workingProfile.fullName)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(PassportTheme.textPrimary)

            Text(workingProfile.headline)
                .foregroundStyle(PassportTheme.textPrimary)

            Divider().overlay(PassportTheme.border)

            Text("School: \(workingProfile.school)")
                .foregroundStyle(PassportTheme.textSecondary)
            Text("Employers: \(workingProfile.employers.joined(separator: ", "))")
                .foregroundStyle(PassportTheme.textSecondary)
            Text("Referral badge: \(workingProfile.referred ? "Yes" : "No")")
                .foregroundStyle(PassportTheme.textSecondary)
            Text("Job function: \(workingProfile.jobFunction.title)")
                .foregroundStyle(PassportTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(PassportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(PassportTheme.border, lineWidth: 1)
        )
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
                    Label("Upload Video", systemImage: "video.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .background(PassportTheme.accent)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            Text("Intro video must be 2:00 or shorter and is picked from the camera roll.")
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
                    title: "Intro video ready",
                    details: "\(videoFileName)\nDuration \(duration)"
                )
            }

            if let videoURL = workingProfile.introVideoURL, !videoURL.isEmpty {
                SimpleProfileCard(
                    title: "Video uploaded",
                    details: shortDisplayURL(videoURL)
                )
            } else if workingProfile.introVideoFileName != nil {
                SimpleProfileCard(
                    title: "Upload pending",
                    details: "The video has been selected locally, but no Supabase URL has been saved yet."
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(PassportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(PassportTheme.border, lineWidth: 1)
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

            guard duration <= 120 else {
                importErrorMessage = "Your intro video must be 2 minutes or shorter."
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

    private func shortDisplayURL(_ urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host else {
            return urlString
        }

        let path = url.path.isEmpty ? "/" : url.path
        return "\(host)\n\(path)"
    }

    private func slotLabel(_ slot: AvailabilitySlotRecord) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let endFormatter = DateFormatter()
        endFormatter.timeStyle = .short
        endFormatter.dateStyle = .none
        return "\(formatter.string(from: slot.startAt)) - \(endFormatter.string(from: slot.endAt))"
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
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(PassportTheme.border, lineWidth: 1)
        )
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

#Preview {
    JobSeekerHomeView(
        profile: DemoData.defaultCandidateProfile,
        requests: [
            JobSeekerRequestItem(
                id: "req-1",
                employerName: "Acme",
                status: "pending_candidate_selection",
                employerProfileID: "employer-1",
                availabilitySlotID: nil
            )
        ],
        openSlotsByEmployer: [:],
        onSaveProfile: { _ in },
        onUploadResume: { _ in },
        onUploadVideo: { _, _ in },
        onSelectSlot: { _, _ in },
        onShowNotifications: {},
        onSignOut: {}
    )
}
