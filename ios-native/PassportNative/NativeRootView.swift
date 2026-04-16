import SwiftUI
import PhotosUI
import CoreTransferable
import AVFoundation
import UniformTypeIdentifiers

struct NativeRootView: View {
    @StateObject private var store = AppSessionStore()

    @State private var authMode: AuthMode = .signIn
    @State private var email = ""
    @State private var password = ""

    @State private var onboardingRole: UserRole = .jobSeeker
    @State private var fullName = ""
    @State private var headline = ""
    @State private var schoolName = ""
    @State private var employersText = ""
    @State private var selectedJobFunction: JobFunctionOption = .engineering
    @State private var companyName = ""
    @State private var companyDomain = ""
    @State private var positionTitle = ""
    @State private var referralToken = ""

    @State private var showingResumeImporter = false
    @State private var selectedResumeURL: URL?
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var selectedVideoURL: URL?
    @State private var selectedVideoDuration: Double?
    @State private var showingNotifications = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [PassportTheme.background, Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                content
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingNotifications) {
                NotificationsSheet()
                    .environmentObject(store)
                    .presentationDetents([.medium, .large])
            }
        }
        .fileImporter(
            isPresented: $showingResumeImporter,
            allowedContentTypes: supportedResumeTypes,
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let first = urls.first {
                selectedResumeURL = copyImportedFileToTemporaryDirectory(from: first)
            }
        }
        .onChange(of: selectedVideoItem) { _, newValue in
            guard let newValue else { return }
            Task {
                await loadSelectedVideo(from: newValue)
            }
        }
        .alert("Issue", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    store.errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .launching:
            ProgressView()
                .tint(PassportTheme.accent)
        case .signedOut:
            authView
        case .onboarding:
            onboardingView
        case .signedIn:
            signedInView
        }
    }

    private var authView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Passport")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(PassportTheme.textPrimary)

                Text("Short-form hiring for iPhone. Job seekers upload a concise intro video. Employers scroll, like, and schedule directly.")
                    .font(.headline)
                    .foregroundStyle(PassportTheme.textSecondary)

                VStack(spacing: 14) {
                    Picker("Mode", selection: $authMode) {
                        ForEach(AuthMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .textFieldStyle(PassportTextFieldStyle())

                    SecureField("Password", text: $password)
                        .textFieldStyle(PassportTextFieldStyle())
                }
                .padding(20)
                .background(PassportTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(PassportTheme.border, lineWidth: 1)
                )

                Button(action: handleEmailAuth) {
                    Text(authMode == .signIn ? "Sign In" : "Create Account")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(PassportTheme.accent)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .disabled(store.isBusy)

                Button(action: { Task { await store.signInWithGoogle() } }) {
                    Text("Continue With Google")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(PassportTheme.surface)
                        .foregroundStyle(PassportTheme.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(PassportTheme.border, lineWidth: 1)
                        )
                }
                .disabled(store.isBusy)

                configCard
            }
            .padding(24)
        }
    }

    private var onboardingView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Finish Your Profile")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(PassportTheme.textPrimary)

                Text("Choose a role, fill in your public profile, and upload the assets needed for the hiring flow.")
                    .foregroundStyle(PassportTheme.textSecondary)

                VStack(spacing: 16) {
                    Picker("Role", selection: $onboardingRole) {
                        ForEach(UserRole.allCases) { role in
                            Text(role.title).tag(role)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Full name", text: $fullName)
                        .textFieldStyle(PassportTextFieldStyle())

                    TextField("Headline", text: $headline, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(PassportTextFieldStyle())

                    if onboardingRole == .jobSeeker {
                        TextField("School", text: $schoolName)
                            .textFieldStyle(PassportTextFieldStyle())

                        TextField("Previous employers, comma separated", text: $employersText, axis: .vertical)
                            .lineLimit(2...4)
                            .textFieldStyle(PassportTextFieldStyle())

                        Picker("Job function", selection: $selectedJobFunction) {
                            ForEach(JobFunctionOption.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(PassportTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                        TextField("Referral token (optional)", text: $referralToken)
                            .textFieldStyle(PassportTextFieldStyle())

                        Button {
                            showingResumeImporter = true
                        } label: {
                            labelRow(
                                title: selectedResumeURL == nil ? "Upload resume" : "Resume selected",
                                subtitle: selectedResumeURL?.lastPathComponent ?? "We parse school and employers when possible."
                            )
                        }

                        PhotosPicker(
                            selection: $selectedVideoItem,
                            matching: .videos,
                            photoLibrary: .shared()
                        ) {
                            labelRow(
                                title: selectedVideoURL == nil ? "Upload intro video" : "Intro video selected",
                                subtitle: selectedVideoURL?.lastPathComponent ?? "Maximum 2 minutes. This becomes your feed card video."
                            )
                        }
                    } else {
                        TextField("Company name", text: $companyName)
                            .textFieldStyle(PassportTextFieldStyle())

                        TextField("Company domain", text: $companyDomain)
                            .textInputAutocapitalization(.never)
                            .textFieldStyle(PassportTextFieldStyle())

                        TextField("Position title", text: $positionTitle)
                            .textFieldStyle(PassportTextFieldStyle())
                    }
                }
                .padding(20)
                .background(PassportTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(PassportTheme.border, lineWidth: 1)
                )

                Button(action: saveOnboarding) {
                    Text("Save And Continue")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(PassportTheme.accent)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .disabled(store.isBusy)
            }
            .padding(24)
            .onAppear(perform: populateOnboardingDefaultsIfNeeded)
        }
    }

    @ViewBuilder
    private var signedInView: some View {
        if store.role == .employer {
            EmployerHomeView(
                fullName: store.profile?.fullName ?? "Employer",
                candidates: store.employerFeed,
                likedCandidates: store.likedCandidates,
                availabilitySlots: store.employerAvailabilitySlots,
                approvals: store.employerApprovalItems,
                onRefresh: { Task { await store.refreshCurrentRoleData() } },
                onLikeCandidate: { candidateID in Task { await store.likeCandidate(candidateID: candidateID) } },
                onAddAvailabilitySlot: { start, end in Task { await store.addAvailabilitySlot(startAt: start, endAt: end) } },
                onRespondToApproval: { requestID, approved in Task { await store.respondToInterview(requestID: requestID, approved: approved) } },
                onIssueReferral: { email in Task { _ = await store.issueReferral(email: email) } },
                onShowNotifications: { showingNotifications = true },
                onSignOut: { Task { await store.signOut() } }
            )
        } else {
            JobSeekerHomeView(
                profile: store.candidateDraft,
                requests: store.jobSeekerRequestItems,
                openSlotsByEmployer: store.openSlotsByEmployer,
                onSaveProfile: { profile in Task { await store.saveCandidateProfile(profile) } },
                onUploadResume: { url in Task { await store.uploadResume(fileURL: url) } },
                onUploadVideo: { url, duration in Task { await store.uploadCandidateVideo(fileURL: url, duration: duration) } },
                onSelectSlot: { requestID, slotID in Task { await store.selectInterviewSlot(requestID: requestID, slotID: slotID) } },
                onShowNotifications: { showingNotifications = true },
                onSignOut: { Task { await store.signOut() } }
            )
        }
    }

    private var configCard: some View {
        let config = PassportConfig.load()

        return VStack(alignment: .leading, spacing: 10) {
            Text("Native config")
                .font(.headline)
                .foregroundStyle(PassportTheme.textPrimary)

            Text("Use a hosted Supabase project. Manual employer availability is active for now. Google Calendar linkage is intentionally left as a later TODO.")
                .foregroundStyle(PassportTheme.textSecondary)

            Text("SUPABASE_URL: \(config.supabaseURL)")
                .font(.footnote.monospaced())
                .foregroundStyle(PassportTheme.textSecondary)

            Text("REDIRECT_SCHEME: \(config.redirectScheme)")
                .font(.footnote.monospaced())
                .foregroundStyle(PassportTheme.textSecondary)
        }
        .padding(20)
        .background(PassportTheme.card.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(PassportTheme.border, lineWidth: 1)
        )
    }

    private func handleEmailAuth() {
        Task {
            if authMode == .signIn {
                await store.signIn(email: email, password: password)
            } else {
                await store.signUp(email: email, password: password)
            }
        }
    }

    private func saveOnboarding() {
        let employers = employersText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        Task {
            await store.completeOnboarding(
                role: onboardingRole,
                fullName: fullName,
                headline: headline,
                schoolName: schoolName,
                employers: employers,
                jobFunction: selectedJobFunction,
                companyName: companyName,
                companyDomain: companyDomain,
                positionTitle: positionTitle,
                referralToken: referralToken,
                resumeURL: selectedResumeURL,
                introVideoURL: selectedVideoURL,
                introVideoDuration: selectedVideoDuration
            )
        }
    }

    private func populateOnboardingDefaultsIfNeeded() {
        if fullName.isEmpty { fullName = store.profile?.fullName ?? "" }
        if headline.isEmpty { headline = store.profile?.headline ?? "" }
        if schoolName.isEmpty { schoolName = store.jobSeekerProfile?.schoolName ?? "" }
        if employersText.isEmpty { employersText = store.jobSeekerEmployers.map(\.employerName).joined(separator: ", ") }
        if let role = store.role { onboardingRole = role }
        if let jobFunction = store.jobSeekerProfile?.jobFunction { selectedJobFunction = jobFunction }
        if companyName.isEmpty { companyName = store.employerProfile?.companyName ?? "" }
        if companyDomain.isEmpty { companyDomain = store.employerProfile?.companyDomain ?? "" }
        if positionTitle.isEmpty { positionTitle = store.employerProfile?.positionTitle ?? "" }
    }

    private func loadSelectedVideo(from item: PhotosPickerItem) async {
        do {
            guard let movie = try await RootSelectedMovie.load(from: item) else { return }
            let asset = AVURLAsset(url: movie.url)
            let duration = try await asset.load(.duration).seconds
            guard duration <= 120 else {
                store.errorMessage = "Your intro video must be 2 minutes or shorter."
                return
            }
            selectedVideoURL = movie.url
            selectedVideoDuration = duration
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private var supportedResumeTypes: [UTType] {
        var types: [UTType] = [.pdf, .plainText, .rtf]
        if let docx = UTType(filenameExtension: "docx") { types.append(docx) }
        if let doc = UTType(filenameExtension: "doc") { types.append(doc) }
        return types
    }

    private func labelRow(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundStyle(PassportTheme.textPrimary)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(PassportTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(PassportTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            store.errorMessage = error.localizedDescription
            return nil
        }
    }
}

struct PassportTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(14)
            .background(PassportTheme.card)
            .foregroundStyle(PassportTheme.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct NotificationsSheet: View {
    @EnvironmentObject private var store: AppSessionStore

    var body: some View {
        NavigationStack {
            List(store.notifications) { notification in
                VStack(alignment: .leading, spacing: 6) {
                    Text(notification.title)
                        .font(.headline)
                    Text(notification.body)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(PassportTheme.background)
            .navigationTitle("Notifications")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Mark all read") {
                        Task { await store.markNotificationsRead() }
                    }
                }
            }
        }
    }
}

private enum AuthMode: String, CaseIterable, Identifiable {
    case signIn
    case signUp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .signIn: return "Sign In"
        case .signUp: return "Create"
        }
    }
}

private struct RootSelectedMovie {
    let url: URL

    static func load(from item: PhotosPickerItem) async throws -> RootSelectedMovie? {
        guard let movie = try await item.loadTransferable(type: SelectedMovieTransferable.self) else {
            return nil
        }
        return RootSelectedMovie(url: movie.url)
    }
}

private struct SelectedMovieTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let temporaryDirectory = URL(filePath: NSTemporaryDirectory())
            let copiedURL = temporaryDirectory.appending(path: received.file.lastPathComponent)

            if FileManager.default.fileExists(atPath: copiedURL.path) {
                try FileManager.default.removeItem(at: copiedURL)
            }

            try FileManager.default.copyItem(at: received.file, to: copiedURL)
            return SelectedMovieTransferable(url: copiedURL)
        }
    }
}

#Preview {
    NativeRootView()
}
