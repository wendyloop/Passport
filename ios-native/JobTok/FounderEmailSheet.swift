import SwiftUI

/// "Email the founder" — the secondary apply path. Presented from the feed;
/// resolves eligibility server-side on appear (video gate, contact
/// availability, weekly quota) and walks the candidate through a
/// template-dominant compose with one optional note.
struct FounderEmailSheet: View {
    let job: JobPostingRecord
    let session: AuthSession
    /// M-C: the candidate's videos, for picking which one to feature.
    var videos: [CandidateVideoRecord] = []
    /// Dismiss and route into the pitch-video studio.
    let onRecordPitch: () -> Void
    /// Dismiss and route into the resume file importer (M-B resume gate).
    let onAddResume: () -> Void
    /// Dismiss and fall back to the normal apply path.
    let onFallbackApply: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .loading
    @State private var note = ""
    @State private var selectedVideoURL: String?

    private static let maxNoteChars = 400

    enum Phase: Equatable {
        case loading
        case videoGate
        case resumeGate
        case noContact
        case companyCapped
        case compose(FounderEmailPreview)
        case sending(FounderEmailPreview)
        case sent(remaining: Int, limit: Int)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(PassportTheme.background.ignoresSafeArea())
                .navigationTitle("Pitch the founder")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close") { dismiss() }
                            .font(.subheadline.weight(.semibold))
                    }
                }
        }
        .task { await loadPreview() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView("Finding the founder…")
                .padding(.top, 80)

        case .videoGate:
            gateView

        case .resumeGate:
            resumeGateView

        case .noContact:
            noContactView

        case .companyCapped:
            companyCappedView

        case .compose(let preview), .sending(let preview):
            composeView(preview: preview, isSending: isSending)

        case .sent(let remaining, let limit):
            sentView(remaining: remaining, limit: limit)

        case .failed(let message):
            failedView(message: message)
        }
    }

    private var isSending: Bool {
        if case .sending = phase { return true }
        return false
    }

    private func videoMenuTitle(_ video: CandidateVideoRecord) -> String {
        let caption = video.caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = (caption?.isEmpty == false ? caption! : "Untitled video")
        return video.isPrimary ? "\(base) · Primary" : base
    }

    private var selectedVideoTitle: String {
        guard let selected = videos.first(where: { $0.videoURL == selectedVideoURL }) else {
            return "Primary video"
        }
        return videoMenuTitle(selected)
    }

    // MARK: - States

    private var gateView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Founders reply to faces, not resumes")
                .font(.title2.weight(.black))
                .foregroundStyle(PassportTheme.textPrimary)

            Text("Record a short pitch video and it rides along with every founder intro you send. That's the whole point — show up as a person, not a PDF.")
                .foregroundStyle(PassportTheme.textSecondary)

            Button {
                dismiss()
                onRecordPitch()
            } label: {
                Label("Record your pitch", systemImage: "video.badge.plus")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .background(PassportTheme.accent)
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(20)
        .jobTokCard(cornerRadius: 28)
        .padding(20)
    }

    private var resumeGateView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Founders check the resume too")
                .font(.title2.weight(.black))
                .foregroundStyle(PassportTheme.textPrimary)

            Text("Your pitch email promises a resume alongside your video. Add yours once and it rides along with every founder intro you send.")
                .foregroundStyle(PassportTheme.textSecondary)

            Button {
                dismiss()
                onAddResume()
            } label: {
                Label("Add your resume", systemImage: "doc.badge.plus")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .background(PassportTheme.accent)
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(20)
        .jobTokCard(cornerRadius: 28)
        .padding(20)
    }

    private var noContactView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("No founder contact yet")
                .font(.title2.weight(.black))
                .foregroundStyle(PassportTheme.textPrimary)

            Text("We haven't found a founder for \(job.companyName) yet. The regular application still gets you in the door.")
                .foregroundStyle(PassportTheme.textSecondary)

            Button {
                dismiss()
                onFallbackApply()
            } label: {
                Text("Apply instead")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .background(PassportTheme.accent)
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(20)
        .jobTokCard(cornerRadius: 28)
        .padding(20)
    }

    private var companyCappedView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("This founder's inbox is full this week")
                .font(.title2.weight(.black))
                .foregroundStyle(PassportTheme.textPrimary)

            Text("A few candidates already pitched \(job.companyName) this week — we cap it so every pitch actually gets read. The regular application still works, or come back next week.")
                .foregroundStyle(PassportTheme.textSecondary)

            Button {
                dismiss()
                onFallbackApply()
            } label: {
                Text("Apply instead")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .background(PassportTheme.accent)
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(20)
        .jobTokCard(cornerRadius: 28)
        .padding(20)
    }

    private func composeView(preview: FounderEmailPreview, isSending: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let contact = preview.contact {
                    recipientCard(contact)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("What they'll get")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(PassportTheme.textPrimary)
                    Label("Your pitch video, front and center", systemImage: "video.fill")
                    if videos.count > 1 {
                        Menu {
                            ForEach(videos) { video in
                                Button(videoMenuTitle(video)) {
                                    selectedVideoURL = video.videoURL
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(selectedVideoTitle)
                                    .font(.footnote.weight(.semibold))
                                    .lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                            }
                            .foregroundStyle(PassportTheme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(PassportTheme.card)
                            .clipShape(Capsule())
                        }
                    }
                    Label("Your latest resume", systemImage: "doc.fill")
                    if let subject = preview.subjectPreview {
                        Label(subject, systemImage: "envelope")
                            .lineLimit(2)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(PassportTheme.textSecondary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .jobTokCard(cornerRadius: 20)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Add a personal line (optional)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(PassportTheme.textPrimary)
                    TextField("Why this company, in your words", text: $note, axis: .vertical)
                        .lineLimit(3...5)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: note) { _, newValue in
                            if newValue.count > Self.maxNoteChars {
                                note = String(newValue.prefix(Self.maxNoteChars))
                            }
                        }
                    Text("\(note.count)/\(Self.maxNoteChars) · links are removed")
                        .font(.caption)
                        .foregroundStyle(PassportTheme.textSecondary)
                }

                HStack {
                    Text("\(preview.remaining) of \(preview.limit) pitches left this week")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(PassportTheme.accentSoft)
                        .foregroundStyle(PassportTheme.accent)
                        .clipShape(Capsule())
                    Spacer()
                }

                Button {
                    Task { await send(preview: preview) }
                } label: {
                    Group {
                        if isSending {
                            ProgressView().tint(.black)
                        } else {
                            Text(preview.remaining > 0 ? "Send your pitch" : "Weekly limit reached")
                        }
                    }
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                }
                .background(preview.remaining > 0 ? PassportTheme.accent : Color.gray.opacity(0.3))
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .disabled(preview.remaining <= 0 || isSending)

                Text("Sent from scout22 on your behalf — replies land straight in your inbox.")
                    .font(.caption)
                    .foregroundStyle(PassportTheme.textSecondary)
            }
            .padding(20)
        }
    }

    private func recipientCard(_ contact: FounderContactPreview) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(PassportTheme.accent)

            VStack(alignment: .leading, spacing: 3) {
                Text(contact.fullName ?? "Company founder")
                    .font(.headline)
                    .foregroundStyle(PassportTheme.textPrimary)
                if let role = contact.roleTitle, !role.isEmpty {
                    Text("\(role) · \(job.companyName)")
                        .font(.caption)
                        .foregroundStyle(PassportTheme.textSecondary)
                } else {
                    Text(job.companyName)
                        .font(.caption)
                        .foregroundStyle(PassportTheme.textSecondary)
                }
                HStack(spacing: 6) {
                    Text(contact.emailMasked)
                        .font(.caption.monospaced())
                        .foregroundStyle(PassportTheme.textSecondary)
                    if contact.isGuessedAddress {
                        Text("guessed address")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.18))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
            }
            Spacer()
        }
        .padding(16)
        .jobTokCard(cornerRadius: 20)
    }

    private func sentView(remaining: Int, limit: Int) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "paperplane.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(PassportTheme.accent)
            Text("Pitch sent 🚀")
                .font(.title2.weight(.black))
                .foregroundStyle(PassportTheme.textPrimary)
            Text("Your pitch is on its way to \(job.companyName)\u{2019}s founder. Replies land straight in your inbox.")
                .multilineTextAlignment(.center)
                .foregroundStyle(PassportTheme.textSecondary)
            Text("\(remaining) of \(limit) pitches left this week")
                .font(.caption.weight(.bold))
                .foregroundStyle(PassportTheme.textSecondary)
            Button("Done") { dismiss() }
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(PassportTheme.accent)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(24)
        .jobTokCard(cornerRadius: 28)
        .padding(20)
    }

    private func failedView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Couldn't send")
                .font(.title3.weight(.bold))
                .foregroundStyle(PassportTheme.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(PassportTheme.textSecondary)
            Button("Try again") {
                phase = .loading
                Task { await loadPreview() }
            }
            .font(.subheadline.weight(.bold))
        }
        .padding(20)
        .jobTokCard(cornerRadius: 28)
        .padding(20)
    }

    // MARK: - Actions

    private func loadPreview() async {
        guard case .loading = phase else { return }
        do {
            let preview = try await SupabaseService.shared.candidate.previewFounderEmail(jobID: job.id, session: session)
            switch preview.reason {
            case "pitch_video_required":
                phase = .videoGate
            case "resume_required":
                phase = .resumeGate
            case "no_contact":
                phase = .noContact
            case "company_capped":
                phase = .companyCapped
            default:
                phase = .compose(preview)
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func send(preview: FounderEmailPreview) async {
        phase = .sending(preview)
        do {
            let result = try await SupabaseService.shared.candidate.sendFounderEmail(
                jobID: job.id,
                contactID: preview.contact?.id,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                videoURL: selectedVideoURL,
                session: session
            )
            phase = .sent(remaining: result.remaining, limit: result.limit)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
