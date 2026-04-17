import SwiftUI
import PhotosUI
import CoreTransferable
import AVFoundation
import UniformTypeIdentifiers

struct NativeRootView: View {
    @StateObject private var store = AppSessionStore()

    @State private var selectedPortal: AuthPortal = .employee
    @State private var authMode: AuthMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var isPasswordVisible = false

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
    @FocusState private var focusedAuthField: AuthField?
    @FocusState private var focusedOnboardingField: OnboardingField?

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [PassportTheme.background, Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                .onTapGesture {
                    focusedAuthField = nil
                    focusedOnboardingField = nil
                }

                content
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedAuthField = nil
                        focusedOnboardingField = nil
                    }
                }
            }
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
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    authHeader
                    portalSelector
                    authCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .frame(minHeight: max(proxy.size.height, 0), alignment: .top)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var onboardingView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("\(selectedPortal.portalTitle) Setup")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(PassportTheme.textPrimary)

                Text(selectedPortal.onboardingSubtitle)
                    .foregroundStyle(PassportTheme.textSecondary)

                VStack(spacing: 16) {
                    onboardingPortalCard

                    TextField("Full name", text: $fullName)
                        .focused($focusedOnboardingField, equals: .fullName)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedOnboardingField = .headline
                        }
                        .textFieldStyle(PassportTextFieldStyle())

                    TextField("Headline", text: $headline, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($focusedOnboardingField, equals: .headline)
                        .textFieldStyle(PassportTextFieldStyle())

                    if onboardingRole == .jobSeeker {
                        TextField("School", text: $schoolName)
                            .focused($focusedOnboardingField, equals: .school)
                            .submitLabel(.next)
                            .onSubmit {
                                focusedOnboardingField = .employers
                            }
                            .textFieldStyle(PassportTextFieldStyle())

                        TextField("Previous employers, comma separated", text: $employersText, axis: .vertical)
                            .lineLimit(2...4)
                            .focused($focusedOnboardingField, equals: .employers)
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
                            .focused($focusedOnboardingField, equals: .companyName)
                            .submitLabel(.next)
                            .onSubmit {
                                focusedOnboardingField = .companyDomain
                            }
                            .textFieldStyle(PassportTextFieldStyle())

                        TextField("Company domain", text: $companyDomain)
                            .textInputAutocapitalization(.never)
                            .focused($focusedOnboardingField, equals: .companyDomain)
                            .submitLabel(.next)
                            .onSubmit {
                                focusedOnboardingField = .positionTitle
                            }
                            .textFieldStyle(PassportTextFieldStyle())

                        TextField("Position title", text: $positionTitle)
                            .focused($focusedOnboardingField, equals: .positionTitle)
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
            .padding(.bottom, 12)
            .onAppear(perform: populateOnboardingDefaultsIfNeeded)
        }
        .scrollDismissesKeyboard(.interactively)
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

    private var authHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Passport")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(PassportTheme.textPrimary)

            Text(selectedPortal.heroTitle)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(PassportTheme.textPrimary)
        }
    }

    private var portalSelector: some View {
        HStack(spacing: 10) {
            ForEach(AuthPortal.allCases) { portal in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedPortal = portal
                        onboardingRole = portal.role
                    }
                } label: {
                    Text(portal.portalTitle)
                        .font(.subheadline.weight(.bold))
                    .foregroundStyle(selectedPortal == portal ? Color.black : PassportTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .background(selectedPortal == portal ? PassportTheme.accent : PassportTheme.surface.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(selectedPortal == portal ? PassportTheme.accentSoft : PassportTheme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var authCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text(selectedPortal.portalTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PassportTheme.textPrimary)

                Spacer()

                Picker("Mode", selection: $authMode) {
                    ForEach(AuthMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
            }

            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.emailAddress)
                    .focused($focusedAuthField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit {
                        focusedAuthField = .password
                    }
                    .textFieldStyle(PassportTextFieldStyle())

                passwordField
            }

            Button(action: handleEmailAuth) {
                Text(authMode == .signIn ? "Continue In \(selectedPortal.shortPortalName)" : "Create \(selectedPortal.shortPortalName) Account")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(PassportTheme.accent)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .disabled(store.isBusy)

//            Button(action: {
//                onboardingRole = selectedPortal.role
//                focusedAuthField = nil
//                Task { await store.signInWithGoogle() }
//            }) {
//                Text("Continue With Google")
//                    .fontWeight(.semibold)
//                    .frame(maxWidth: .infinity)
//                    .padding(.vertical, 15)
//                    .background(PassportTheme.surface)
//                    .foregroundStyle(PassportTheme.textPrimary)
//                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
//                    .overlay(
//                        RoundedRectangle(cornerRadius: 18, style: .continuous)
//                            .stroke(PassportTheme.border, lineWidth: 1)
//                    )
//            }
//            .disabled(store.isBusy)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(PassportTheme.surface.opacity(0.96))
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(PassportTheme.border.opacity(0.95), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 26, y: 12)
    }

    private var passwordField: some View {
        HStack(spacing: 12) {
            Group {
                if isPasswordVisible {
                    TextField("Password", text: $password)
                        .focused($focusedAuthField, equals: .password)
                } else {
                    SecureField("Password", text: $password)
                        .focused($focusedAuthField, equals: .password)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.asciiCapable)
            .submitLabel(.go)
            .onSubmit(handleEmailAuth)

            Button {
                isPasswordVisible.toggle()
                focusedAuthField = .password
            } label: {
                Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PassportTheme.textSecondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(PassportTheme.card)
        .foregroundStyle(PassportTheme.textPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var onboardingPortalCard: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(PassportTheme.accent)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(selectedPortal.portalTitle)
                    .font(.headline)
                    .foregroundStyle(PassportTheme.textPrimary)

                Text(selectedPortal.onboardingSubtitle)
                    .font(.footnote)
                    .foregroundStyle(PassportTheme.textSecondary)
            }

            Spacer()
        }
        .padding(16)
        .background(PassportTheme.card.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func handleEmailAuth() {
        onboardingRole = selectedPortal.role
        focusedAuthField = nil
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
        if let role = store.role {
            onboardingRole = role
            selectedPortal = role == .employer ? .employer : .employee
        } else {
            onboardingRole = selectedPortal.role
        }
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

private enum AuthPortal: String, CaseIterable, Identifiable {
    case employee
    case employer

    var id: String { rawValue }

    var role: UserRole {
        switch self {
        case .employee: return .jobSeeker
        case .employer: return .employer
        }
    }

    var portalTitle: String {
        switch self {
        case .employee: return "Employee Portal"
        case .employer: return "Employer Portal"
        }
    }

    var shortPortalName: String {
        switch self {
        case .employee: return "Employee"
        case .employer: return "Employer"
        }
    }

    var heroTitle: String {
        switch self {
        case .employee: return "Employee Portal"
        case .employer: return "Employer Portal"
        }
    }

    var onboardingSubtitle: String {
        switch self {
        case .employee: return "Complete your candidate profile and add the video employers will see in the feed."
        case .employer: return "Set up your hiring profile and add the company details candidates will see."
        }
    }

    var signInHint: String {
        switch self {
        case .employee: return "Existing candidate accounts will open into the job seeker experience."
        case .employer: return "Existing employer accounts will open into the hiring dashboard."
        }
    }

    var signUpHint: String {
        switch self {
        case .employee: return ""
        case .employer: return ""
        }
    }
}

private enum AuthField: Hashable {
    case email
    case password
}

private enum OnboardingField: Hashable {
    case fullName
    case headline
    case school
    case employers
    case companyName
    case companyDomain
    case positionTitle
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
