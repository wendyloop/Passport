import SwiftUI

/// S-4: review a tailored resume before it goes anywhere.
///
/// Every rewritten bullet is shown next to the sentence it came from. That
/// pairing is the whole point of the screen: a rewrite that quietly changed
/// what someone claims is only catchable if the original is right there, and
/// the server-side fabrication check cannot catch a subtler drift in emphasis.
///
/// An edit here is filed against the BASE resume, so correcting a clumsy line
/// once carries into every future tailoring rather than dying with this
/// version.
struct TailoredResumeSheet: View {
    let job: JobPostingRecord
    let session: AuthSession
    let service: CandidateService
    /// The resume this was tailored from — where overrides are stored.
    let baseResumeID: String
    @Binding var isPresented: Bool
    /// Handed the rendered PDF when the candidate accepts it.
    var onUse: ((Data, String) -> Void)?

    @State private var phase: Phase = .loading
    @State private var content: TailoredResumeContent?
    @State private var stillMissing: [String] = []
    @State private var editingBullet: TailoredResumeContent.Bullet?
    @State private var editText: String = ""
    /// Local edits, applied over `content` for display so the list updates
    /// without re-running the whole tailoring pass.
    @State private var overrides: [String: String] = [:]

    private enum Phase: Equatable {
        case loading
        case ready
        case refused(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    loadingView
                case .refused(let reason):
                    refusedView(reason)
                case .ready:
                    readyView
                }
            }
            .navigationTitle("Tailored resume")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                }
                if phase == .ready {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Use this") { useTailoredResume() }
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .task { await load() }
        .sheet(item: $editingBullet) { bullet in
            editSheet(for: bullet)
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Rewriting your resume for this role…")
                .font(.system(size: 13))
                .foregroundStyle(PassportTheme.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A refusal is not an error, and it should not read like one. The most
    /// important case — the model invented something — is stated plainly
    /// rather than dressed up as a temporary glitch.
    private func refusedView(_ reason: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: reason == "fabrication_detected" ? "exclamationmark.shield" : "doc.text")
                .font(.system(size: 40))
                .foregroundStyle(PassportTheme.textMuted)
            Text(refusalMessage(reason))
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundStyle(PassportTheme.textMuted)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func refusalMessage(_ reason: String) -> String {
        switch reason {
        case "fabrication_detected":
            return "The rewrite changed something it shouldn't have, so we threw it away. "
                + "Your original resume is untouched — try again, or apply with it as is."
        case "no_bullets":
            return "Your resume doesn't have bullet points we can rewrite. "
                + "Re-upload it and we'll take another pass at reading it."
        case "no_resume":
            return "Upload a resume first and we'll tailor it to this role."
        case "disabled":
            return "Resume tailoring is turned off right now."
        default:
            return "We couldn't tailor your resume for this role. Your original is unchanged."
        }
    }

    private var readyView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let content {
                    let changed = content.changedBullets
                    Text(changed.isEmpty
                         ? "Your resume already fits this role — nothing needed rewriting."
                         : "\(changed.count) line\(changed.count == 1 ? "" : "s") rewritten. "
                           + "Check each one before you send it.")
                        .font(.system(size: 13))
                        .foregroundStyle(PassportTheme.textMuted)

                    ForEach(content.employment, id: \.company) { role in
                        roleSection(role)
                    }

                    if !stillMissing.isEmpty {
                        missingSection
                    }
                }
            }
            .padding(18)
            .padding(.bottom, 40)
        }
        .background(PassportTheme.background)
    }

    private func roleSection(_ role: TailoredResumeContent.Role) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text([role.title, role.company].filter { !$0.isEmpty }.joined(separator: ", "))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(PassportTheme.textPrimary)

            ForEach(role.bullets, id: \.key) { bullet in
                bulletRow(bullet)
            }
        }
    }

    private func bulletRow(_ bullet: TailoredResumeContent.Bullet) -> some View {
        let shown = overrides[bullet.key] ?? bullet.tailored
        let isEdited = overrides[bullet.key] != nil
        // Compared against `shown` rather than `bullet.tailored`: once the
        // candidate edits a line it is theirs, and marking it "rewritten"
        // would be wrong even if the model touched it first.
        let isRewritten = !isEdited && bullet.wasChanged

        return VStack(alignment: .leading, spacing: 5) {
            Text(shown)
                .font(.system(size: 13))
                .foregroundStyle(PassportTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if isRewritten {
                // The original, right there. A drifted claim is only catchable
                // next to the sentence it drifted from.
                Text("was: \(bullet.original)")
                    .font(.system(size: 11))
                    .foregroundStyle(PassportTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                if isEdited {
                    Label("your wording", systemImage: "pencil")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(PassportTheme.accent)
                } else if isRewritten {
                    Label("rewritten", systemImage: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(PassportTheme.textMuted)
                }
                Button("Edit") {
                    editText = shown
                    editingBullet = bullet
                }
                .font(.system(size: 11, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(PassportTheme.accent)
            }
        }
        .padding(.leading, 10)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isEdited ? PassportTheme.accent : PassportTheme.border)
                .frame(width: 2)
        }
    }

    private var missingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Still not on your resume")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(PassportTheme.textPrimary)
            Text(stillMissing.joined(separator: ", "))
                .font(.system(size: 12))
                .foregroundStyle(PassportTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            // Said explicitly, because the alternative — quietly adding these
            // — is what makes a candidate fail an interview instead of a
            // keyword filter.
            Text("We won't add these for you. If you've actually done them, add them yourself.")
                .font(.system(size: 11))
                .foregroundStyle(PassportTheme.textMuted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(PassportTheme.border.opacity(0.25))
        )
    }

    private func editSheet(for bullet: TailoredResumeContent.Bullet) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Original")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(PassportTheme.textMuted)
                Text(bullet.original)
                    .font(.system(size: 12))
                    .foregroundStyle(PassportTheme.textMuted)

                Text("Your version")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(PassportTheme.textMuted)
                TextEditor(text: $editText)
                    .font(.system(size: 13))
                    .frame(minHeight: 120)
                    .padding(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(PassportTheme.border, lineWidth: 1)
                    )

                Text("Saved to your resume, not just this application — we'll use your wording next time too.")
                    .font(.system(size: 11))
                    .foregroundStyle(PassportTheme.textMuted)

                Spacer()
            }
            .padding(18)
            .navigationTitle("Edit line")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editingBullet = nil }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") { saveOverride(for: bullet) }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Actions

    private func load() async {
        let response = try? await service.tailorResume(jobID: job.id, session: session)
        guard let response, response.available, let content = response.content else {
            phase = .refused(response?.reason ?? "tailor_failed")
            return
        }
        self.content = content
        self.stillMissing = response.keywordsStillMissing ?? []
        phase = .ready
    }

    private func saveOverride(for bullet: TailoredResumeContent.Bullet) {
        let text = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Reverting to the model's exact wording is a clear, and clears the
        // stored override rather than pinning a duplicate of it forever.
        if text.isEmpty || text == bullet.tailored {
            overrides.removeValue(forKey: bullet.key)
        } else {
            overrides[bullet.key] = text
        }
        editingBullet = nil

        let key = bullet.key
        let saved = overrides[key] ?? ""
        Task {
            try? await service.setBulletOverride(
                resumeID: baseResumeID,
                bulletKey: key,
                text: saved,
                session: session
            )
        }
    }

    private func useTailoredResume() {
        guard let content else { return }
        // Local edits win over the model's wording, matching what the server
        // will apply on the next tailoring once the overrides land.
        let merged = TailoredResumeContent(
            summary: content.summary,
            skillsOrdered: content.skillsOrdered,
            employment: content.employment.map { role in
                TailoredResumeContent.Role(
                    company: role.company,
                    title: role.title,
                    dates: role.dates,
                    bullets: role.bullets.map { bullet in
                        guard let override = overrides[bullet.key] else { return bullet }
                        return TailoredResumeContent.Bullet(
                            key: bullet.key,
                            original: bullet.original,
                            tailored: override,
                            keywordsAdded: bullet.keywordsAdded
                        )
                    }
                )
            },
            keywordsCovered: content.keywordsCovered,
            keywordsStillMissing: content.keywordsStillMissing
        )

        let rendered = ResumePDF.render(
            ResumePDF.Content(
                tailored: merged,
                fullName: candidateName,
                contactLine: contactLine,
                education: baseEducation
            )
        )
        guard let rendered else { return }
        onUse?(rendered, ResumePDF.fileName(
            candidateName: candidateName,
            companyName: job.companyName
        ))
        isPresented = false
    }

    // MARK: - Context passed in from the drawer

    var candidateName: String = ""
    var contactLine: String = ""
    var baseEducation: [ParsedResumeDetails.Education] = []
}

extension TailoredResumeContent.Bullet: Identifiable {
    var id: String { key }
}
