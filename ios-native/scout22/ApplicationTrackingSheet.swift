import SwiftUI

/// S-6: where the candidate says one application stands.
///
/// Everything here is the candidate's own record, stored in a table the
/// employer cannot read. `job_applications.status` — the employer's pipeline
/// — is deliberately not editable from here, and not even shown: it is
/// employer-written, and it is absent entirely on board jobs, reel jobs and
/// founder pitches, which have no employer user at all.
struct ApplicationTrackingSheet: View {
    let application: JobApplicationRecord
    let session: AuthSession
    let service: CandidateService
    @Binding var isPresented: Bool
    var onSaved: () -> Void

    @State private var stage: CandidateApplicationStage
    @State private var hasInterview: Bool
    @State private var interviewAt: Date
    @State private var hasFollowUp: Bool
    @State private var followUpOn: Date
    @State private var notes: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        application: JobApplicationRecord,
        session: AuthSession,
        service: CandidateService,
        isPresented: Binding<Bool>,
        onSaved: @escaping () -> Void
    ) {
        self.application = application
        self.session = session
        self.service = service
        self._isPresented = isPresented
        self.onSaved = onSaved

        let tracking = application.candidateTracking
        _stage = State(initialValue: tracking?.stageValue ?? .applied)
        _hasInterview = State(initialValue: tracking?.interviewAt != nil)
        _interviewAt = State(initialValue: tracking?.interviewAt ?? Self.defaultInterviewDate())
        let parsedFollowUp = tracking?.followUpOn
            .flatMap(JobSeekerHomeView.dateOnlyParser.date(from:))
        _hasFollowUp = State(initialValue: parsedFollowUp != nil)
        _followUpOn = State(initialValue: parsedFollowUp ?? Self.defaultFollowUpDate())
        _notes = State(initialValue: tracking?.notes ?? "")
    }

    /// Tomorrow at 10am — a plausible interview slot, so the picker does not
    /// open on "now", which is never the answer.
    private static func defaultInterviewDate() -> Date {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return Calendar.current.date(
            bySettingHour: 10, minute: 0, second: 0, of: tomorrow
        ) ?? tomorrow
    }

    /// A week out. Long enough that a recruiter has plausibly had time, short
    /// enough to still matter.
    private static func defaultFollowUpDate() -> Date {
        Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(application.jobTitle)
                        .font(.system(size: 15, weight: .bold))
                    Text(application.companyName)
                        .font(.system(size: 13))
                        .foregroundStyle(PassportTheme.textMuted)
                }

                Section("Where it stands") {
                    Picker("Stage", selection: $stage) {
                        ForEach(CandidateApplicationStage.allCases) { option in
                            Label(option.title, systemImage: option.symbol).tag(option)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section {
                    Toggle("Interview scheduled", isOn: $hasInterview.animation())
                    if hasInterview {
                        DatePicker(
                            "When",
                            selection: $interviewAt,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                }

                Section {
                    Toggle("Remind me to follow up", isOn: $hasFollowUp.animation())
                    if hasFollowUp {
                        DatePicker(
                            "On",
                            selection: $followUpOn,
                            displayedComponents: [.date]
                        )
                    }
                } footer: {
                    // Honest about what this does. There are no push
                    // notifications in this app, and implying otherwise would
                    // have people miss the thing they set the reminder for.
                    Text("Applications due a follow-up move to the top of your Inbox. We won't send you a notification.")
                }

                Section {
                    TextEditor(text: $notes)
                        .frame(minHeight: 90)
                } header: {
                    Text("Private notes")
                } footer: {
                    Text("Only you can see these. Employers never do.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Track application")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(isSaving)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await service.updateApplicationTracking(
                    applicationID: application.id,
                    candidateID: session.user.id,
                    stage: stage,
                    // Toggling off clears the stored value rather than leaving
                    // a stale interview date attached to a closed application.
                    interviewAt: hasInterview ? interviewAt : nil,
                    followUpOn: hasFollowUp ? followUpOn : nil,
                    notes: notes,
                    session: session
                )
                await MainActor.run {
                    isSaving = false
                    onSaved()
                    isPresented = false
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Couldn't save that. Try again."
                }
            }
        }
    }
}
