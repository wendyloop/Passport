import SwiftUI
import PhotosUI
import AVFoundation
import AuthenticationServices
import CoreTransferable
import UniformTypeIdentifiers
import UIKit

struct NativeRootView: View {
    @StateObject private var store = AppSessionStore()
    private let config = PassportConfig.load()
    private let webAuthenticationPresentationContextProvider = WebAuthenticationPresentationContextProvider()

    @State private var email = ""
    @State private var authNoticeMessage: String?
    @State private var webAuthenticationSession: ASWebAuthenticationSession?

    @State private var fullName = ""
    @State private var headline = ""
    @State private var schoolName = ""
    @State private var employersText = ""
    @State private var selectedJobFunction: JobFunctionOption = .engineering
    @State private var dreamRole = ""
    @State private var companyName = ""
    @State private var companyDomain = ""
    @State private var positionTitle = ""

    @State private var showingResumeImporter = false
    @State private var selectedResumeURL: URL?
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var selectedVideoURL: URL?
    @State private var selectedVideoDuration: Double?
    @State private var showingNotifications = false
    @FocusState private var focusedField: Field?

    private var authRedirectURL: URL {
        URL(string: "\(config.redirectScheme)://auth-callback")!
    }

    private var onboardingRole: UserRole {
        store.role ?? .jobSeeker
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [PassportTheme.background, PassportTheme.card],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                .onTapGesture {
                    focusedField = nil
                }

                content
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingNotifications, onDismiss: {
                Task { await store.markNotificationsRead() }
            }) {
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
                if !newValue { store.errorMessage = nil }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .onOpenURL { url in
            Task {
                authNoticeMessage = nil
                await store.handleAuthRedirect(url: url)
            }
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
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("JobTok")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundStyle(PassportTheme.textPrimary)
                        Text("Short-form hiring for candidates, employers, and admins.")
                            .foregroundStyle(PassportTheme.textSecondary)
                    }

                    authCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 28)
                .frame(minHeight: max(proxy.size.height, 0), alignment: .top)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var onboardingView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("\(onboardingRole.onboardingTitle) Setup")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(PassportTheme.textPrimary)

                Text(onboardingRole.onboardingSubtitle)
                    .foregroundStyle(PassportTheme.textSecondary)

                VStack(spacing: 16) {
                    TextField("Full name", text: $fullName)
                        .focused($focusedField, equals: .fullName)
                        .textFieldStyle(PassportTextFieldStyle())

                    TextField("Headline", text: $headline, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($focusedField, equals: .headline)
                        .textFieldStyle(PassportTextFieldStyle())

                    switch onboardingRole {
                    case .jobSeeker:
                        TextField("School", text: $schoolName)
                            .focused($focusedField, equals: .school)
                            .textFieldStyle(PassportTextFieldStyle())

                        TextField("Previous employers, comma separated", text: $employersText, axis: .vertical)
                            .lineLimit(2...4)
                            .focused($focusedField, equals: .employers)
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

                        TextField("Dream role", text: $dreamRole)
                            .focused($focusedField, equals: .dreamRole)
                            .textFieldStyle(PassportTextFieldStyle())

                        Button {
                            showingResumeImporter = true
                        } label: {
                            labelRow(
                                title: selectedResumeURL == nil ? "Upload resume" : "Resume selected",
                                subtitle: selectedResumeURL?.lastPathComponent ?? "Required to apply to jobs."
                            )
                        }

                        PhotosPicker(
                            selection: $selectedVideoItem,
                            matching: .videos,
                            photoLibrary: .shared()
                        ) {
                            labelRow(
                                title: selectedVideoURL == nil ? "Upload 60s pitch" : "Pitch selected",
                                subtitle: selectedVideoURL?.lastPathComponent ?? "Optional for MVP. Phase 2 discovery will use this heavily."
                            )
                        }

                    case .employer:
                        TextField("Company name", text: $companyName)
                            .focused($focusedField, equals: .companyName)
                            .textFieldStyle(PassportTextFieldStyle())

                        TextField("Company domain", text: $companyDomain)
                            .textInputAutocapitalization(.never)
                            .focused($focusedField, equals: .companyDomain)
                            .textFieldStyle(PassportTextFieldStyle())

                        TextField("Position title", text: $positionTitle)
                            .focused($focusedField, equals: .positionTitle)
                            .textFieldStyle(PassportTextFieldStyle())

                    case .admin:
                        labelRow(
                            title: "Admin access",
                            subtitle: "Admins can upload and publish job videos once your backend role is set to admin."
                        )
                    }
                }
                .padding(20)
                .background(PassportTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

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
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private var signedInView: some View {
        switch store.role {
        case .jobSeeker:
            JobSeekerHomeView(
                profile: store.candidateDraft,
                jobs: store.jobFeed,
                applications: store.candidateApplications,
                onSaveProfile: { profile in Task { await store.saveCandidateProfile(profile) } },
                onUploadResume: { url in Task { await store.uploadResume(fileURL: url) } },
                onUploadVideo: { url, duration in Task { await store.uploadCandidateVideo(fileURL: url, duration: duration) } },
                onApply: { jobID, coverNote in Task { await store.applyToJob(jobID: jobID, coverNote: coverNote) } },
                onRefresh: { Task { await store.refreshCurrentRoleData() } },
                onShowNotifications: { showingNotifications = true },
                onSignOut: { Task { await store.signOut() } }
            )
        case .employer:
            EmployerHomeView(
                fullName: store.profile?.fullName ?? "Employer",
                jobs: store.employerJobs,
                applications: store.employerApplications,
                discoverableCandidates: store.discoverableCandidates,
                latestOutreachByCandidateID: store.latestOutreachByCandidateID,
                onRefresh: { Task { await store.refreshCurrentRoleData() } },
                onToggleJobPublishState: { jobID, isPublished in
                    Task { await store.toggleJobPublishState(jobID: jobID, isPublished: isPublished) }
                },
                onReachOut: { candidateID, relatedJobID, subject, message in
                    Task {
                        await store.reachOutToCandidate(
                            candidateID: candidateID,
                            relatedJobID: relatedJobID,
                            subject: subject,
                            message: message
                        )
                    }
                },
                onShowNotifications: { showingNotifications = true },
                onSignOut: { Task { await store.signOut() } }
            )
        case .admin:
            AdminHomeView(
                jobs: store.adminJobs,
                employers: store.employerDirectoryItems,
                onCreateJob: { draft, videoURL in Task { await store.createJob(draft: draft, localVideoURL: videoURL) } },
                onToggleJobPublishState: { jobID, isPublished in
                    Task { await store.toggleJobPublishState(jobID: jobID, isPublished: isPublished) }
                },
                onRefresh: { Task { await store.refreshCurrentRoleData() } },
                onShowNotifications: { showingNotifications = true },
                onSignOut: { Task { await store.signOut() } }
            )
        case .none:
            JobSeekerHomeView(
                profile: store.candidateDraft,
                jobs: store.jobFeed,
                applications: store.candidateApplications,
                onSaveProfile: { profile in Task { await store.saveCandidateProfile(profile) } },
                onUploadResume: { url in Task { await store.uploadResume(fileURL: url) } },
                onUploadVideo: { url, duration in Task { await store.uploadCandidateVideo(fileURL: url, duration: duration) } },
                onApply: { jobID, coverNote in Task { await store.applyToJob(jobID: jobID, coverNote: coverNote) } },
                onRefresh: { Task { await store.refreshCurrentRoleData() } },
                onShowNotifications: { showingNotifications = true },
                onSignOut: { Task { await store.signOut() } }
            )
        }
    }

    private var authCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Continue")
                .font(.headline)
                .foregroundStyle(PassportTheme.textPrimary)

            Button {
                startOAuthLogin(with: .google)
            } label: {
                authButtonLabel(title: "Continue with Google", systemImage: "globe")
            }
            .buttonStyle(.plain)
            .disabled(store.isBusy)

            Button {
                startOAuthLogin(with: .apple)
            } label: {
                authButtonLabel(title: "Continue with Apple", systemImage: "apple.logo")
            }
            .buttonStyle(.plain)
            .disabled(store.isBusy)

            HStack {
                Rectangle()
                    .fill(PassportTheme.border)
                    .frame(height: 1)
                Text("or")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PassportTheme.textSecondary)
                Rectangle()
                    .fill(PassportTheme.border)
                    .frame(height: 1)
            }

            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .textFieldStyle(PassportTextFieldStyle())

                Button(action: handleEmailAuth) {
                    Text("Send Magic Link")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(PassportTheme.accent)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .disabled(store.isBusy || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let authNoticeMessage {
                Text(authNoticeMessage)
                    .font(.footnote)
                    .foregroundStyle(PassportTheme.textSecondary)
            }

            Text("Roles are assigned in Supabase. Admin and employer access should be granted in the backend. Everyone else signs in as a candidate.")
                .font(.footnote)
                .foregroundStyle(PassportTheme.textSecondary)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(PassportTheme.surface.opacity(0.96))
        )
    }

    private func authButtonLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
            Text(title)
                .fontWeight(.bold)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(PassportTheme.card)
        .foregroundStyle(PassportTheme.textPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func startOAuthLogin(with provider: SocialAuthProvider) {
        focusedField = nil
        authNoticeMessage = nil

        do {
            let authorizationURL = try store.oauthAuthorizationURL(
                provider: provider,
                redirectTo: authRedirectURL
            )
            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: config.redirectScheme
            ) { callbackURL, error in
                Task { @MainActor in
                    if let callbackURL {
                        await store.handleAuthRedirect(url: callbackURL)
                    } else if let error {
                        store.errorMessage = error.localizedDescription
                    }
                    webAuthenticationSession = nil
                }
            }
            session.presentationContextProvider = webAuthenticationPresentationContextProvider
            session.prefersEphemeralWebBrowserSession = false
            webAuthenticationSession = session
            session.start()
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func handleEmailAuth() {
        focusedField = nil
        authNoticeMessage = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            let didSend = await store.sendEmailLogin(email: trimmedEmail, redirectTo: authRedirectURL)
            if didSend {
                authNoticeMessage = "Check \(trimmedEmail) for your JobTok magic link."
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
                fullName: fullName,
                headline: headline,
                schoolName: schoolName,
                employers: employers,
                jobFunction: selectedJobFunction,
                dreamRole: dreamRole,
                companyName: companyName,
                companyDomain: companyDomain,
                positionTitle: positionTitle,
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
        if dreamRole.isEmpty { dreamRole = store.jobSeekerProfile?.dreamRole ?? "" }
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
            guard duration <= 60 else {
                store.errorMessage = "Your pitch video must be 60 seconds or shorter."
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
                .padding(.vertical, 4)
            }
            .navigationTitle("Notifications")
        }
    }
}

private enum Field {
    case email
    case fullName
    case headline
    case school
    case employers
    case dreamRole
    case companyName
    case companyDomain
    case positionTitle
}

private struct RootSelectedMovie: Transferable {
    let url: URL

    static func load(from item: PhotosPickerItem) async throws -> RootSelectedMovie? {
        try await item.loadTransferable(type: RootSelectedMovie.self)
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let temporaryDirectory = URL(filePath: NSTemporaryDirectory())
            let copiedURL = temporaryDirectory.appending(path: received.file.lastPathComponent)

            if FileManager.default.fileExists(atPath: copiedURL.path) {
                try FileManager.default.removeItem(at: copiedURL)
            }

            try FileManager.default.copyItem(at: received.file, to: copiedURL)
            return RootSelectedMovie(url: copiedURL)
        }
    }
}

private extension UserRole {
    var onboardingTitle: String {
        switch self {
        case .jobSeeker:
            return "Candidate"
        case .employer:
            return "Employer"
        case .admin:
            return "Admin"
        }
    }

    var onboardingSubtitle: String {
        switch self {
        case .jobSeeker:
            return "Build your public profile with a resume and a 60-second pitch."
        case .employer:
            return "Set up the company profile that will receive applications."
        case .admin:
            return "Admins upload and publish job videos for employer accounts."
        }
    }
}

private final class WebAuthenticationPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
