import SwiftUI
import AuthenticationServices
import UIKit

struct NativeRootView: View {
    @StateObject private var store = AppSessionStore()
    private let config = PassportConfig.load()
    private let webAuthenticationPresentationContextProvider = WebAuthenticationPresentationContextProvider()
    private let loginAccent = PassportTheme.accent
    private let authCardReservedHeight: CGFloat = 250

    @State private var email = ""
    @State private var password = ""
    @State private var authNoticeMessage: String?
    @State private var webAuthenticationSession: ASWebAuthenticationSession?
    @State private var selectedLoginMethod: LoginMethod = .google
    @State private var emailAuthMode: EmailAuthMode = .signIn
    @State private var lastHandledAuthRedirect: String?

    @State private var showingNotifications = false
    @FocusState private var focusedField: Field?

    private var authRedirectURL: URL {
        URL(string: "\(config.redirectScheme)://auth-callback")!
    }

    var body: some View {
        NavigationStack {
            ZStack {
                authBackground
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
            // F10: share deep link jobtok://job/{id} → queue for the feed.
            if url.host == "job" {
                let jobID = url.lastPathComponent
                if !jobID.isEmpty && jobID != "job" {
                    store.pendingSharedJobID = jobID
                }
                return
            }
            Task {
                authNoticeMessage = nil
                await handleAuthRedirectIfNeeded(url: url)
            }
        }
    }

    @ViewBuilder
    private var authBackground: some View {
        switch store.phase {
        case .signedOut:
            PassportTheme.background
        case .launching, .offline:
            PassportTheme.accent
        case .onboarding, .signedIn:
            LinearGradient(
                colors: [PassportTheme.background, PassportTheme.card],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .launching:
            launchingView
        case .offline:
            offlineView
        case .signedOut:
            authView
        case .onboarding:
            signedInView
        case .signedIn:
            signedInView
        }
    }

    private var launchingView: some View {
        VStack(spacing: 16) {
            Text("💼")
                .font(.system(size: 70))

            Text("scout22")
                .font(.system(size: 44, weight: .black, design: .rounded))
                .foregroundStyle(Color.black)

            ProgressView()
                .tint(Color.black)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // AUDIT P0-1: signed in but the backend is unreachable. The store retries
    // on its own when connectivity returns; the button is a manual nudge.
    private var offlineView: some View {
        VStack(spacing: 16) {
            Text("💼")
                .font(.system(size: 70))

            Text("scout22")
                .font(.system(size: 44, weight: .black, design: .rounded))
                .foregroundStyle(Color.black)

            Text("You're offline. We'll reconnect automatically.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.7))
                .multilineTextAlignment(.center)

            Button {
                Task { await store.retryConnection() }
            } label: {
                Text("Retry")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(Color.black)
                    .foregroundStyle(PassportTheme.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var authView: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack {
                    Spacer(minLength: 0)

                    VStack(spacing: 30) {
                        VStack(spacing: 16) {
                            Text("scout22")
                                .font(.system(size: 68, weight: .black, design: .rounded))
                                .foregroundStyle(Color.black)
                                .multilineTextAlignment(.center)

                            Text(selectedLoginMethod.subtitle)
                                .font(.system(size: 17, weight: .medium, design: .rounded))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(PassportTheme.textSecondary)
                        }

                        loginMethodSelector
                        authCard
                    }
                    .frame(maxWidth: 360)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
                .frame(minHeight: max(proxy.size.height, 0))
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    @ViewBuilder
    private var signedInView: some View {
        switch store.role {
        case .jobSeeker:
            jobSeekerHome()
        // PRE-LAUNCH (2026-07-20): the employer and admin surfaces are hidden
        // — every role gets the candidate experience. The original routing is
        // kept commented out below; restore by swapping the branches back in.
        case .employer:
            jobSeekerHome()
            /*
            EmployerHomeView(
                profile: store.employerDraft,
                accountEmail: store.currentEmail ?? "",
                jobs: store.employerJobs,
                applications: store.employerApplications,
                discoverableCandidates: store.discoverableCandidates,
                latestOutreachByCandidateID: store.latestOutreachByCandidateID,
                onSaveProfile: { draft in
                    Task { await store.saveEmployerProfile(draft) }
                },
                onCreateJob: { draft, videoURL in
                    Task { await store.createEmployerJob(draft: draft, localVideoURL: videoURL) }
                },
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
                onUpdateApplication: { applicationID, status, notes in
                    Task { await store.updateApplication(applicationID: applicationID, status: status, internalNotes: notes) }
                },
                onRequestResumeURL: { applicationID in
                    try await store.resumeURL(applicationID: applicationID)
                },
                onShowNotifications: { showingNotifications = true },
                onSignOut: { Task { await store.signOut() } },
                onDeleteAccount: { Task { await store.deleteAccount() } }
            )
            */
        case .admin:
            jobSeekerHome()
            /*
            AdminHomeView(
                jobs: store.adminJobs,
                employers: store.employerDirectoryItems,
                onCreateJob: { draft, videoURL in
                    await store.createJob(draft: draft, localVideoURL: videoURL)
                },
                onImportSharedPost: { sourceURL in
                    try await store.parseSharedJobPosting(sourceURL: sourceURL)
                },
                onToggleJobPublishState: { jobID, isPublished in
                    Task { await store.toggleJobPublishState(jobID: jobID, isPublished: isPublished) }
                },
                onRefresh: { Task { await store.refreshCurrentRoleData() } },
                onShowNotifications: { showingNotifications = true },
                onSignOut: { Task { await store.signOut() } }
            )
            */
        case .none:
            // Role not yet chosen — default to the candidate experience.
            jobSeekerHome()
        }
    }

    private func jobSeekerHome() -> some View {
        JobSeekerHomeView(
            profile: store.candidateDraft,
            jobs: store.jobFeed,
            savedJobs: store.savedJobs,
            savedJobIDs: store.savedJobIDs,
            applications: store.candidateApplications,
            session: store.session,
            sharedJobID: store.pendingSharedJobID,
            onConsumeSharedJob: { store.pendingSharedJobID = nil },
            onSaveProfile: { profile in Task { await store.saveCandidateProfile(profile) } },
            onUploadAvatar: { data in Task { await store.uploadCandidateAvatar(imageData: data) } },
            onUploadResume: { url in Task { await store.uploadResume(fileURL: url) } },
            onUploadVideo: { url, duration in Task { await store.uploadCandidateVideo(fileURL: url, duration: duration) } },
            onRequestResumePreview: { try await store.requestResumePreviewURL() },
            onApply: { draft in Task { await store.applyToJob(draft) } },
            onToggleSavedJob: { jobID in Task { await store.toggleSavedJob(jobID: jobID) } },
            onRefresh: { Task { await store.refreshCurrentRoleData() } },
            onShowNotifications: { showingNotifications = true },
            onSignOut: { Task { await store.signOut() } },
            onDeleteAccount: { Task { await store.deleteAccount() } },
            onFiltersChanged: { filters in Task { await store.applyFeedFilters(filters) } }
        )
    }

    private var loginMethodSelector: some View {
        HStack(spacing: 20) {
            ForEach(LoginMethod.allCases) { method in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedLoginMethod = method
                        authNoticeMessage = nil
                        if method != .email {
                            focusedField = nil
                        }
                    }
                } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(selectedLoginMethod == method ? loginAccent : PassportTheme.card)
                                .frame(width: 56, height: 56)

                            Image(systemName: method.symbol)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(selectedLoginMethod == method ? Color.black : PassportTheme.textPrimary)
                        }

                        Text(method.title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(selectedLoginMethod == method ? PassportTheme.textPrimary : PassportTheme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var authCard: some View {
        VStack(spacing: 18) {
            switch selectedLoginMethod {
            case .google:
                Button {
                    startOAuthLogin(with: .google)
                } label: {
                    primaryAuthButtonLabel(title: "Continue with Google", systemImage: "globe")
                }
                .buttonStyle(.plain)
                .disabled(store.isBusy)
            case .apple:
                Button {
                    startOAuthLogin(with: .apple)
                } label: {
                    primaryAuthButtonLabel(title: "Continue with Apple", systemImage: "apple.logo")
                }
                .buttonStyle(.plain)
                .disabled(store.isBusy)
            case .email:
                VStack(spacing: 14) {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .textFieldStyle(AuthTextFieldStyle())

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .textFieldStyle(AuthTextFieldStyle())

                    Button(action: handleEmailPasswordAuth) {
                        primaryAuthButtonLabel(
                            title: emailAuthMode == .signIn ? "Sign In with Email" : "Create Account",
                            systemImage: "envelope.fill"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isBusy || trimmedEmail.isEmpty || password.isEmpty)

                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            emailAuthMode = emailAuthMode == .signIn ? .createAccount : .signIn
                            authNoticeMessage = nil
                        }
                    } label: {
                        Text(emailAuthMode == .signIn ? "Need an account? Create one" : "Already have an account? Sign in")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(PassportTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let authNoticeMessage {
                Text(authNoticeMessage)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(PassportTheme.textSecondary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: 360)
        .frame(minHeight: authCardReservedHeight, alignment: .top)
    }

    private func primaryAuthButtonLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 22)
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 17)
        .background(PassportTheme.card)
        .foregroundStyle(PassportTheme.textPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(PassportTheme.border.opacity(0.7), lineWidth: 1)
        )
    }

    private func startOAuthLogin(with provider: SocialAuthProvider) {
        focusedField = nil
        authNoticeMessage = nil
        lastHandledAuthRedirect = nil

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
                        await handleAuthRedirectIfNeeded(url: callbackURL)
                    } else if let error {
                        if let authError = error as? ASWebAuthenticationSessionError,
                           authError.code == .canceledLogin {
                            webAuthenticationSession = nil
                            return
                        }
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

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleEmailPasswordAuth() {
        focusedField = nil
        authNoticeMessage = nil

        Task {
            switch emailAuthMode {
            case .signIn:
                await store.signIn(email: trimmedEmail, password: password)
            case .createAccount:
                await store.signUp(email: trimmedEmail, password: password)
            }
        }
    }

    @MainActor
    private func handleAuthRedirectIfNeeded(url: URL) async {
        let redirectSignature = url.absoluteString
        guard lastHandledAuthRedirect != redirectSignature else { return }
        lastHandledAuthRedirect = redirectSignature
        await store.handleAuthRedirect(url: url)
    }

}

struct AuthTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(PassportTheme.card)
            .foregroundStyle(PassportTheme.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(PassportTheme.border.opacity(0.7), lineWidth: 1)
            )
    }
}

typealias PassportTextFieldStyle = AuthTextFieldStyle

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
    case password
}

private enum LoginMethod: String, CaseIterable, Identifiable {
    case google
    case apple
    case email

    var id: String { rawValue }

    var title: String {
        switch self {
        case .google: return "Google"
        case .apple: return "Apple"
        case .email: return "Email"
        }
    }

    var subtitle: String {
        switch self {
        case .google: return "Sign in with Google"
        case .apple: return "Sign in with Apple"
        case .email: return "Sign in with Email"
        }
    }

    var symbol: String {
        switch self {
        case .google: return "globe"
        case .apple: return "apple.logo"
        case .email: return "envelope.fill"
        }
    }
}

private enum EmailAuthMode {
    case signIn
    case createAccount
}

private final class WebAuthenticationPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
