import SwiftUI
import UniformTypeIdentifiers

/// M-D first-run flow: basics → resume → pitch video → done. Resume and
/// video are deliberately skippable — signup conversion wins, and the
/// founder-email gates re-ask at the moment of value. Skipped items stay
/// visible on the profile strength ring.
struct OnboardingFlowView: View {
    @ObservedObject var store: AppSessionStore

    private enum Step: Int, CaseIterable {
        case basics, resume, video
    }

    @State private var step: Step = .basics
    @State private var fullName = ""
    @State private var headline = ""
    @State private var jobFunction: JobFunctionOption = .engineering
    @State private var showingResumeImporter = false
    @State private var showingVideoStudio = false
    @State private var didSeedFields = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { candidate in
                    Capsule()
                        .fill(candidate.rawValue <= step.rawValue ? PassportTheme.accent : PassportTheme.card)
                        .frame(height: 4)
                }
            }
            .padding(.top, 20)

            switch step {
            case .basics:
                basicsStep
            case .resume:
                resumeStep
            case .video:
                videoStep
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PassportTheme.background.ignoresSafeArea())
        .overlay {
            if store.isBusy {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.15))
            }
        }
        .onAppear {
            guard !didSeedFields else { return }
            didSeedFields = true
            let draft = store.candidateDraft
            fullName = draft.fullName
            headline = draft.headline
            jobFunction = draft.jobFunction
        }
        .fileImporter(
            isPresented: $showingResumeImporter,
            allowedContentTypes: resumeTypes,
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first,
                  let copied = copyToTemporaryDirectory(url) else { return }
            Task {
                await store.uploadResume(fileURL: copied)
                step = .video
            }
        }
        .fullScreenCover(isPresented: $showingVideoStudio) {
            JobTokVideoStudio(
                purpose: .candidatePitch,
                startMode: .library,
                onCancel: { showingVideoStudio = false },
                onComplete: { composed in
                    showingVideoStudio = false
                    Task {
                        await store.uploadCandidateVideo(fileURL: composed.url, duration: composed.duration)
                        await store.markOnboardingComplete()
                    }
                }
            )
        }
    }

    // MARK: - Steps

    private var basicsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to scout22")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(PassportTheme.textPrimary)

            Text("Jobs come to you as videos. Tell us who you are — this powers your profile and every application you send.")
                .foregroundStyle(PassportTheme.textSecondary)

            TextField("Your name", text: $fullName)
                .textFieldStyle(.roundedBorder)

            TextField("One-line headline (e.g. CS @ Berkeley)", text: $headline)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text("Looking for")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PassportTheme.textPrimary)
                Spacer()
                Menu {
                    ForEach(JobFunctionOption.allCases) { option in
                        Button(option.title) { jobFunction = option }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(jobFunction.title)
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                    .foregroundStyle(PassportTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(PassportTheme.card)
                    .clipShape(Capsule())
                }
            }

            accentButton("Continue", disabled: fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                var draft = store.candidateDraft
                draft.fullName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
                draft.headline = headline.trimmingCharacters(in: .whitespacesAndNewlines)
                draft.jobFunction = jobFunction
                Task {
                    await store.saveCandidateProfile(draft)
                    step = .resume
                }
            }
        }
    }

    private var resumeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add your resume")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(PassportTheme.textPrimary)

            Text("Your profile fills itself in from it — experience, education, skills. It also unlocks founder pitches and ranks the feed to fit you.")
                .foregroundStyle(PassportTheme.textSecondary)

            accentButton("Upload resume") {
                showingResumeImporter = true
            }

            skipButton("Skip for now") { step = .video }
        }
    }

    private var videoStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Record your video intro")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(PassportTheme.textPrimary)

            Text("Founders reply to faces, not resumes. Up to 3 minutes — it rides along with every application and founder intro.")
                .foregroundStyle(PassportTheme.textSecondary)

            accentButton("Record or upload") {
                showingVideoStudio = true
            }

            skipButton("Skip for now") {
                Task { await store.markOnboardingComplete() }
            }

            Text("You can add both later from your profile. Tip: different reviewers check different links — marketing looks at Instagram and TikTok, engineering at GitHub, design at your portfolio. Add yours in Profile → About.")
                .font(.caption)
                .foregroundStyle(PassportTheme.textMuted)
        }
    }

    // MARK: - Pieces

    private func accentButton(_ title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .background(disabled ? Color.gray.opacity(0.3) : PassportTheme.accent)
        .foregroundStyle(.black)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .disabled(disabled)
        .buttonStyle(.plain)
    }

    private func skipButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .foregroundStyle(PassportTheme.textSecondary)
        .buttonStyle(.plain)
    }

    private var resumeTypes: [UTType] {
        var types: [UTType] = [.pdf, .plainText, .rtf]
        if let docx = UTType(filenameExtension: "docx") { types.append(docx) }
        if let doc = UTType(filenameExtension: "doc") { types.append(doc) }
        return types
    }

    private func copyToTemporaryDirectory(_ url: URL) -> URL? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}
