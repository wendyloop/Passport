import SwiftUI
import PhotosUI
import CoreTransferable

struct AdminHomeView: View {
    let jobs: [JobPostingRecord]
    let employers: [EmployerDirectoryItem]
    let onCreateJob: (JobPostingDraft, URL) -> Void
    let onToggleJobPublishState: (String, Bool) -> Void
    let onRefresh: () -> Void
    let onShowNotifications: () -> Void
    let onSignOut: () -> Void

    @State private var showingCreateSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    Button {
                        showingCreateSheet = true
                    } label: {
                        Text("Create JobTok Post")
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(PassportTheme.accent)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    if jobs.isEmpty {
                        AdminInfoCard(
                            title: "No jobs yet",
                            details: "Create the first role, attach a vertical video, and assign it to an employer portal."
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
                                    Text(job.isPublished ? "Published" : "Draft")
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(job.isPublished ? PassportTheme.accent : PassportTheme.card)
                                        .foregroundStyle(job.isPublished ? .black : PassportTheme.textPrimary)
                                        .clipShape(Capsule())

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

                    AdminInfoCard(
                        title: "Phase 2 note",
                        details: "The schema already carries candidate visibility and dream-role data so employer discovery can be added without reworking applications."
                    )
                }
                .padding(20)
            }
            .background(PassportTheme.background)
        }
        .sheet(isPresented: $showingCreateSheet) {
            AdminCreateJobSheet(employers: employers, onCreateJob: onCreateJob)
                .presentationDetents([.large])
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Admin")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(PassportTheme.textPrimary)
                    Text("Upload job videos, assign them to employers, and publish the feed.")
                        .foregroundStyle(PassportTheme.textSecondary)
                }
                Spacer()
                HeaderAction(symbol: "arrow.clockwise", action: onRefresh)
                HeaderAction(symbol: "bell.fill", action: onShowNotifications)
                HeaderAction(symbol: "rectangle.portrait.and.arrow.right", action: onSignOut)
            }
        }
    }
}

private struct AdminCreateJobSheet: View {
    let employers: [EmployerDirectoryItem]
    let onCreateJob: (JobPostingDraft, URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = JobPostingDraft()
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var selectedVideoURL: URL?
    @State private var videoName = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    employerPicker

                    field(title: "Job title", text: $draft.title)
                    field(title: "Company name", text: $draft.companyName)
                    field(title: "Location", text: $draft.location)

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
                    field(title: "Source URL (optional)", text: $draft.sourceURL)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Description")
                            .font(.headline)
                            .foregroundStyle(PassportTheme.textPrimary)

                        TextField("Describe the opening", text: $draft.description, axis: .vertical)
                            .lineLimit(5...8)
                            .textFieldStyle(PassportTextFieldStyle())
                    }

                    Toggle(isOn: $draft.isPublished) {
                        Text("Publish immediately")
                            .foregroundStyle(PassportTheme.textPrimary)
                    }
                    .tint(PassportTheme.accent)

                    PhotosPicker(
                        selection: $selectedVideoItem,
                        matching: .videos,
                        photoLibrary: .shared()
                    ) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(selectedVideoURL == nil ? "Upload job video" : "Job video selected")
                                .font(.headline)
                                .foregroundStyle(PassportTheme.textPrimary)
                            Text(selectedVideoURL == nil ? "Choose the short-form job clip to publish." : videoName)
                                .font(.footnote)
                                .foregroundStyle(PassportTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(PassportTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    Button {
                        guard let selectedVideoURL else {
                            errorMessage = "Select a job video before publishing."
                            return
                        }
                        onCreateJob(draft, selectedVideoURL)
                        dismiss()
                    } label: {
                        Text("Create Job")
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(PassportTheme.accent)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .disabled(employers.isEmpty)
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
            if draft.employerProfileID.isEmpty {
                draft.employerProfileID = employers.first?.id ?? ""
                draft.companyName = employers.first?.companyName ?? ""
                draft.applicationEmail = employers.first?.email ?? ""
            }
        }
        .onChange(of: selectedVideoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await loadVideo(newItem)
            }
        }
        .onChange(of: draft.employerProfileID) { _, newValue in
            guard let employer = employers.first(where: { $0.id == newValue }) else { return }
            draft.companyName = employer.companyName
            draft.applicationEmail = employer.email
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

    private func field(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(PassportTheme.textPrimary)
            TextField(title, text: text)
                .textFieldStyle(PassportTextFieldStyle())
        }
    }

    private func loadVideo(_ item: PhotosPickerItem) async {
        do {
            guard let movie = try await item.loadTransferable(type: AdminSelectedMovie.self) else {
                errorMessage = "The selected video could not be loaded."
                return
            }
            selectedVideoURL = movie.url
            videoName = movie.fileName
        } catch {
            errorMessage = error.localizedDescription
        }
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
        .background(PassportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct AdminSelectedMovie: Transferable {
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
            return AdminSelectedMovie(url: copiedURL, fileName: received.file.lastPathComponent)
        }
    }
}
