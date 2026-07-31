import SwiftUI
import Photos
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import UIKit

struct Scout22ComposedVideo {
    let url: URL
    let duration: Double
    let fileName: String
}

enum Scout22VideoStudioPurpose {
    case candidatePitch
    case employerRole
    case adminRole

    var title: String {
        switch self {
        case .candidatePitch:
            return "Pitch Video"
        case .employerRole:
            return "Add Role"
        case .adminRole:
            return "Create Post"
        }
    }

    var subtitle: String {
        switch self {
        case .candidatePitch:
            return "Up to 3 minutes: who you are, then one project you're proud of — show it off."
        case .employerRole:
            return "Pick clips, record, add text, and turn it into a hiring post."
        case .adminRole:
            return "Build a short-form role post from camera roll or a fresh recording."
        }
    }

    var maxDuration: Double? {
        switch self {
        case .candidatePitch:
            return 180
        case .employerRole, .adminRole:
            return nil
        }
    }

    var completionLabel: String {
        switch self {
        case .candidatePitch:
            return "Use Video"
        case .employerRole, .adminRole:
            return "Next"
        }
    }
}

enum Scout22VideoStudioStartMode {
    case library
    case camera
}

struct Scout22VideoStudio: View {
    let purpose: Scout22VideoStudioPurpose
    var startMode: Scout22VideoStudioStartMode = .library
    let onCancel: () -> Void
    let onComplete: (Scout22ComposedVideo) -> Void

    @State private var selectedTab: Scout22VideoStudioTab
    @State private var selectedClips: [Scout22VideoClip] = []
    @State private var editorClips: [Scout22VideoClip] = []
    @State private var showingEditor = false
    @State private var studioError: String?

    init(
        purpose: Scout22VideoStudioPurpose,
        startMode: Scout22VideoStudioStartMode = .library,
        onCancel: @escaping () -> Void,
        onComplete: @escaping (Scout22ComposedVideo) -> Void
    ) {
        self.purpose = purpose
        self.startMode = startMode
        self.onCancel = onCancel
        self.onComplete = onComplete
        _selectedTab = State(initialValue: startMode == .library ? .library : .camera)
    }

    var body: some View {
        ZStack {
            PassportTheme.background
                .ignoresSafeArea()

            if showingEditor {
                Scout22VideoEditor(
                    clips: editorClips,
                    purpose: purpose,
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingEditor = false
                        }
                    },
                    onComplete: onComplete
                )
            } else {
                VStack(spacing: 18) {
                    header
                    if purpose == .candidatePitch {
                        pitchScriptCard
                    }
                    sourceTabs

                    Group {
                        switch selectedTab {
                        case .library:
                            Scout22VideoLibraryPicker(
                                purpose: purpose,
                                selectedClips: $selectedClips,
                                onCameraShortcut: {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        selectedTab = .camera
                                    }
                                },
                                onError: { studioError = $0 }
                            )
                        case .camera:
                            Scout22CameraRecorder(
                                purpose: purpose,
                                recordedClips: $selectedClips,
                                onError: { studioError = $0 }
                            )
                        }
                    }

                    footer
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 14)
            }
        }
        .alert("Issue", isPresented: Binding(
            get: { studioError != nil },
            set: { if !$0 { studioError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(studioError ?? "")
        }
    }

    private var totalDuration: Double {
        selectedClips.reduce(0) { $0 + $1.duration }
    }

    private var durationLabel: String {
        let totalSeconds = Int(totalDuration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // The three beats of a good pitch — visible while picking/recording so
    // candidates know what to say before the camera rolls.
    private var pitchScriptCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("your 3 beats", systemImage: "sparkles")
                .font(.caption.weight(.heavy))
                .foregroundStyle(PassportTheme.accent)
            scriptBeat(number: "1", text: "who you are — name, what you do, one line")
            scriptBeat(number: "2", text: "one project you're proud of — what and why")
            scriptBeat(number: "3", text: "show it! screen-record it, hold it up, demo it")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PassportTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 18)
    }

    private func scriptBeat(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.weight(.black))
                .frame(width: 20, height: 20)
                .background(PassportTheme.accentSoft)
                .foregroundStyle(PassportTheme.accent)
                .clipShape(Circle())
            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(PassportTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(PassportTheme.textPrimary)

                Spacer()

                Text(purpose.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(PassportTheme.textPrimary)

                Spacer()

                Color.clear
                    .frame(width: 54, height: 20)
            }

            VStack(spacing: 6) {
                Text(purpose.subtitle)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(PassportTheme.textSecondary)

                if !selectedClips.isEmpty {
                    Text("\(selectedClips.count) clip\(selectedClips.count == 1 ? "" : "s") • \(durationLabel)")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(PassportTheme.textPrimary)
                }
            }
        }
    }

    private var sourceTabs: some View {
        HStack(spacing: 10) {
            ForEach(Scout22VideoStudioTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 15, weight: .semibold))
                        Text(tab.title)
                            .font(.subheadline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(selectedTab == tab ? PassportTheme.accent : PassportTheme.card)
                    .foregroundStyle(selectedTab == tab ? .black : PassportTheme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if !selectedClips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(selectedClips) { clip in
                            ZStack(alignment: .topTrailing) {
                                if let thumbnail = clip.thumbnail {
                                    Image(uiImage: thumbnail)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    PassportTheme.card
                                }

                                Button {
                                    selectedClips.removeAll { $0.id == clip.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.white, Color.black.opacity(0.65))
                                }
                                .padding(6)
                            }
                            .frame(width: 84, height: 118)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(PassportTheme.border.opacity(0.5), lineWidth: 1)
                            )
                        }
                    }
                }
            }

            Button {
                guard durationIsAllowed else {
                    if let maxDuration = purpose.maxDuration {
                        studioError = "Keep this video under \(Int(maxDuration) / 60) minutes."
                    }
                    return
                }
                editorClips = selectedClips
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingEditor = true
                }
            } label: {
                Text("Next")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(selectedClips.isEmpty ? PassportTheme.card : PassportTheme.accent)
                    .foregroundStyle(selectedClips.isEmpty ? PassportTheme.textMuted : .black)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(selectedClips.isEmpty)
        }
    }

    private var durationIsAllowed: Bool {
        guard let maxDuration = purpose.maxDuration else { return true }
        return totalDuration <= maxDuration
    }
}

// TODO(deferred): This employer job-creation workflow lives inside the
// 2,300-line VideoStudio.swift and belongs with the employer refactor —
// extract it into its own file when EmployerHomeView is refactored.
// See docs/DEFERRED_WORK.md.
struct Scout22EmployerRoleWorkflow: View {
    let profile: EmployerProfileDraft
    let accountEmail: String
    let onCancel: () -> Void
    let onCreateJob: (JobPostingDraft, URL) -> Void

    @State private var step: EmployerRoleWorkflowStep = .select
    @State private var sourceMode: EmployerRoleSourceMode = .library
    @State private var selectedClips: [Scout22VideoClip] = []
    @State private var composedVideo: Scout22ComposedVideo?
    @State private var draft = JobPostingDraft()
    @State private var compensationText = ""
    @State private var hourlyRateText = ""
    @State private var selectedDetailField: EmployerRoleDetailField?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            switch step {
            case .select:
                selectionStep
            case .edit:
                editStep
            case .details:
                detailsStep
            }
        }
        .background(PassportTheme.background.ignoresSafeArea())
        .onAppear {
            draft.companyName = profile.companyName
            draft.applicationEmail = accountEmail
            draft.isPublished = true
        }
        .alert("Issue", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var selectionStep: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Add Role")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.black)

                Spacer()

                Button {
                    step = .edit
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "textformat")
                            .font(.caption.weight(.bold))
                        Text("Text")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(selectedClips.isEmpty ? Color(.systemGray3) : Color.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(selectedClips.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            Group {
                if sourceMode == .library {
                    Scout22VideoLibraryPicker(
                        purpose: .employerRole,
                        selectedClips: $selectedClips,
                        onCameraShortcut: {
                            sourceMode = .camera
                        },
                        onError: { errorMessage = $0 }
                    )
                } else {
                    Scout22CameraRecorder(
                        purpose: .employerRole,
                        recordedClips: $selectedClips,
                        onError: { errorMessage = $0 }
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomSelectionBar
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(PassportTheme.surface)
        }
    }

    private var bottomSelectionBar: some View {
        HStack(spacing: 12) {
            Button {
                sourceMode = sourceMode == .library ? .camera : .library
            } label: {
                Text(sourceMode == .library ? "Record" : "Library")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color(.systemGray6))
                    .foregroundStyle(Color.black)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                guard !selectedClips.isEmpty else { return }
                step = .edit
            } label: {
                Text("Next")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(selectedClips.isEmpty ? Color(.systemGray5) : PassportTheme.accent)
                    .foregroundStyle(selectedClips.isEmpty ? Color(.systemGray) : Color.black)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(selectedClips.isEmpty)
        }
    }

    private var editStep: some View {
        Scout22VideoEditor(
            clips: selectedClips,
            purpose: .employerRole,
            onBack: {
                step = .select
            },
            onComplete: { video in
                composedVideo = video
                step = .details
            }
        )
    }

    private var detailsStep: some View {
        NavigationStack {
            ZStack {
                PassportTheme.surface.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .top, spacing: 14) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Description")
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(Color(.systemGray))
                                TextEditor(text: Binding(
                                    get: { draft.description },
                                    set: { draft.description = String($0.prefix(1200)) }
                                ))
                                .font(.body)
                                .foregroundStyle(Color.black)
                                .scrollContentBackground(.hidden)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .frame(minHeight: 160)
                                .overlay(alignment: .topLeading) {
                                    if draft.description.isEmpty {
                                        Text("Paste job description...")
                                            .foregroundStyle(Color(.systemGray2))
                                            .padding(.top, 10)
                                            .padding(.leading, 8)
                                            .allowsHitTesting(false)
                                    }
                                }
                            }

                            if let url = composedVideo?.url {
                                ZStack(alignment: .bottomLeading) {
                                    Scout22EditableVideoSurface(url: url)
                                        .frame(width: 96, height: 152)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    Text("Preview")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(6)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Job Title")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Color(.systemGray))
                            TextField("Add job title", text: $draft.title)
                                .textFieldStyle(PassportTextFieldStyle())
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Job Function")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Color(.systemGray))
                            Menu {
                                ForEach(JobFunctionOption.allCases) { option in
                                    Button(option.title) { draft.jobFunction = option }
                                }
                            } label: {
                                inlineMenuLabel(draft.jobFunction.title)
                            }
                        }

                        Divider()
                            .padding(.vertical, 4)

                        optionalExpandableRow(title: "Location", field: .location, value: draft.location) {
                            TextField("City, state or remote", text: $draft.location)
                                .textFieldStyle(PassportTextFieldStyle())
                        }

                        optionalExpandableRow(title: "Annual Compensation", field: .compensation, value: compensationSummary) {
                            TextField("Example: $120k–$150k", text: $compensationText)
                                .textFieldStyle(PassportTextFieldStyle())
                        }

                        optionalExpandableRow(title: "Hourly Rate", field: .hourlyRate, value: hourlySummary) {
                            TextField("Example: $45–$60/hr", text: $hourlyRateText)
                                .textFieldStyle(PassportTextFieldStyle())
                        }

                        optionalExpandableRow(title: "Employment Type", field: .employmentType, value: draft.employmentType?.title ?? "") {
                            Menu {
                                Button("Not set") { draft.employmentType = nil }
                                ForEach(EmploymentTypeOption.allCases) { option in
                                    Button(option.title) { draft.employmentType = option }
                                }
                            } label: {
                                inlineMenuLabel(draft.employmentType?.title ?? "Select type")
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 120)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        step = .edit
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.black)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button {
                        step = .edit
                    } label: {
                        Text("Back")
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color(.systemGray6))
                            .foregroundStyle(Color.black)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        guard let url = composedVideo?.url else {
                            errorMessage = "Create the role video first."
                            return
                        }
                        let normalized = normalizedDraftForSubmit()
                        guard !normalized.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            errorMessage = "Add a job title."
                            return
                        }
                        guard !normalized.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            errorMessage = "Paste the job description."
                            return
                        }
                        onCreateJob(normalized, url)
                        onCancel()
                    } label: {
                        Text("Post")
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(PassportTheme.accent)
                            .foregroundStyle(Color.black)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(PassportTheme.surface)
            }
        }
    }

    @ViewBuilder
    private func optionalExpandableRow<Editor: View>(
        title: String,
        field: EmployerRoleDetailField,
        value: String,
        @ViewBuilder editor: () -> Editor
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    selectedDetailField = selectedDetailField == field ? nil : field
                }
            } label: {
                HStack {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.black)
                    Spacer()
                    if !value.isEmpty {
                        Text(value)
                            .font(.subheadline)
                            .lineLimit(1)
                            .foregroundStyle(Color(.systemGray))
                    }
                    Image(systemName: selectedDetailField == field ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color(.systemGray2))
                }
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if selectedDetailField == field {
                editor()
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()
        }
    }

    private func inlineMenuLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .foregroundStyle(Color.black)
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(.systemGray))
        }
        .padding(14)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var compensationSummary: String {
        compensationText.isEmpty ? normalizedCompensationSummary(from: draft) : compensationText
    }

    private var hourlySummary: String {
        hourlyRateText.isEmpty ? normalizedHourlySummary(from: draft) : hourlyRateText
    }

    private func normalizedDraftForSubmit() -> JobPostingDraft {
        var normalized = draft
        let annual = parsedRange(from: compensationText)
        normalized.compensationMinAnnual = annual.min ?? ""
        normalized.compensationMaxAnnual = annual.max ?? ""
        let hourly = parsedRange(from: hourlyRateText)
        normalized.compensationMinHourly = hourly.min ?? ""
        normalized.compensationMaxHourly = hourly.max ?? ""
        normalized.isPublished = true
        return normalized
    }

    private func parsedRange(from text: String) -> (min: String?, max: String?) {
        let numbers = text
            .replacingOccurrences(of: ",", with: "")
            .components(separatedBy: CharacterSet.decimalDigits.inverted)
            .filter { !$0.isEmpty }

        switch numbers.count {
        case 0:
            return (nil, nil)
        case 1:
            return (numbers[0], nil)
        default:
            return (numbers[0], numbers[1])
        }
    }

    private func normalizedCompensationSummary(from draft: JobPostingDraft) -> String {
        let min = draft.compensationMinAnnual.trimmingCharacters(in: .whitespacesAndNewlines)
        let max = draft.compensationMaxAnnual.trimmingCharacters(in: .whitespacesAndNewlines)
        if min.isEmpty && max.isEmpty { return "" }
        if !min.isEmpty && !max.isEmpty { return "$\(min)-$\(max)" }
        return !min.isEmpty ? "$\(min)+" : "$\(max)"
    }

    private func normalizedHourlySummary(from draft: JobPostingDraft) -> String {
        let min = draft.compensationMinHourly.trimmingCharacters(in: .whitespacesAndNewlines)
        let max = draft.compensationMaxHourly.trimmingCharacters(in: .whitespacesAndNewlines)
        if min.isEmpty && max.isEmpty { return "" }
        if !min.isEmpty && !max.isEmpty { return "$\(min)-$\(max)/hr" }
        return !min.isEmpty ? "$\(min)+/hr" : "$\(max)/hr"
    }
}

private enum EmployerRoleWorkflowStep {
    case select
    case edit
    case details
}

private enum EmployerRoleSourceMode {
    case library
    case camera
}

private enum EmployerRoleDetailField: String, CaseIterable, Identifiable {
    case location
    case compensation
    case hourlyRate
    case employmentType

    var id: String { rawValue }

    var title: String {
        switch self {
        case .location: return "Location"
        case .compensation: return "Annual Compensation"
        case .hourlyRate: return "Hourly Rate"
        case .employmentType: return "Employment Type"
        }
    }
}

private enum Scout22VideoStudioTab: String, CaseIterable, Identifiable {
    case library
    case camera

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library:
            return "Library"
        case .camera:
            return "Camera"
        }
    }

    var symbol: String {
        switch self {
        case .library:
            return "square.grid.2x2.fill"
        case .camera:
            return "video.fill.badge.plus"
        }
    }
}

private struct Scout22VideoClip: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let fileName: String
    let duration: Double
    let thumbnail: UIImage?
}

private struct Scout22VideoLibraryPicker: View {
    let purpose: Scout22VideoStudioPurpose
    @Binding var selectedClips: [Scout22VideoClip]
    let onCameraShortcut: () -> Void
    let onError: (String) -> Void

    @StateObject private var libraryStore = Scout22PhotoLibraryStore()

    var body: some View {
        VStack(spacing: 14) {
            switch libraryStore.authorizationState {
            case .authorized, .limited:
                if libraryStore.authorizationState == .limited {
                    // "Selected Photos" access: without this, videos outside
                    // the shared selection silently never appear.
                    HStack(spacing: 10) {
                        Text("Only your selected videos are shown.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PassportTheme.textSecondary)
                        Spacer()
                        Button("Manage") {
                            presentLimitedLibraryPicker()
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PassportTheme.accent)
                    }
                    .padding(12)
                    .background(PassportTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
                        spacing: 6
                    ) {
                        Button {
                            onCameraShortcut()
                        } label: {
                            VStack(spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .fill(PassportTheme.card)

                                    Image(systemName: "video.badge.plus")
                                        .font(.system(size: 28, weight: .bold))
                                        .foregroundStyle(PassportTheme.textPrimary)
                                }
                                .frame(height: 168)

                                Text("Record")
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(PassportTheme.textPrimary)
                            }
                        }
                        .buttonStyle(.plain)

                        ForEach(libraryStore.assets, id: \.localIdentifier) { asset in
                            Scout22AssetThumbnailCell(
                                asset: asset,
                                selectionIndex: selectedClips.firstIndex(where: { $0.fileName == asset.localIdentifier }).map { $0 + 1 },
                                onTap: {
                                    toggle(asset: asset)
                                }
                            )
                        }

                        if libraryStore.assets.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "film.stack")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(PassportTheme.textPrimary)
                                Text("No videos found in your library yet.")
                                    .font(.footnote.weight(.semibold))
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(PassportTheme.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 32)
                            .gridCellColumns(3)
                        }
                    }
                    .padding(.bottom, 12)
                }
            case .denied, .restricted:
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(PassportTheme.textPrimary)
                    Text("Allow photo access to build your video.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(PassportTheme.textSecondary)
                    Button("Retry") {
                        Task {
                            await libraryStore.requestAccess()
                        }
                    }
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(PassportTheme.accent)
                    .foregroundStyle(.black)
                    .clipShape(Capsule())
                    Spacer()
                }
            case .notDetermined:
                ProgressView()
                    .tint(PassportTheme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            @unknown default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 6)
        .task {
            await libraryStore.requestAccess()
        }
    }

    private func presentLimitedLibraryPicker() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.flatMap(\.windows).first(where: { $0.isKeyWindow }) ?? scenes.first?.windows.first,
              let root = window.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top)
    }

    private func toggle(asset: PHAsset) {
        if selectedClips.contains(where: { $0.fileName == asset.localIdentifier }) {
            selectedClips.removeAll { $0.fileName == asset.localIdentifier }
            return
        }

        Task {
            do {
                let clip = try await libraryStore.loadClip(for: asset)
                await MainActor.run {
                    selectedClips.append(
                        Scout22VideoClip(
                            url: clip.url,
                            fileName: asset.localIdentifier,
                            duration: clip.duration,
                            thumbnail: clip.thumbnail
                        )
                    )
                }
            } catch {
                await MainActor.run {
                    onError(error.localizedDescription)
                }
            }
        }
    }
}

@MainActor
private final class Scout22PhotoLibraryStore: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published var assets: [PHAsset] = []
    @Published var authorizationState: PHAuthorizationStatus = .notDetermined

    private let manager = PHCachingImageManager()
    private var isObservingLibrary = false

    deinit {
        if isObservingLibrary {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
        }
    }

    // Limited-access users can change their selection (or save new videos)
    // while the picker is open — refetch so the grid always reflects it.
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async { [weak self] in
            self?.fetchVideos()
        }
    }

    func requestAccess() async {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if current == .notDetermined {
            authorizationState = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        } else {
            authorizationState = current
        }

        guard authorizationState == .authorized || authorizationState == .limited else {
            assets = []
            return
        }

        if !isObservingLibrary {
            PHPhotoLibrary.shared().register(self)
            isObservingLibrary = true
        }

        fetchVideos()
    }

    func fetchVideos() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        let result = PHAsset.fetchAssets(with: options)
        var fetched: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            fetched.append(asset)
        }
        assets = fetched
    }

    func requestThumbnail(for asset: PHAsset, targetSize: CGSize, completion: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        manager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            completion(image)
        }
    }

    func loadClip(for asset: PHAsset) async throws -> Scout22LoadedClip {
        let avAsset = try await requestAVAsset(for: asset)

        let url: URL
        if let urlAsset = avAsset as? AVURLAsset {
            url = try copyMediaFileToTemporaryDirectory(from: urlAsset.url)
        } else {
            throw Scout22VideoStudioError.message("This video format could not be loaded.")
        }

        let thumbnail = try await generateThumbnail(from: AVURLAsset(url: url))
        return Scout22LoadedClip(url: url, duration: asset.duration, thumbnail: thumbnail)
    }

    private func requestAVAsset(for asset: PHAsset) async throws -> AVAsset {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.deliveryMode = .automatic
            options.version = .current
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { asset, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let asset else {
                    continuation.resume(throwing: Scout22VideoStudioError.message("The selected video could not be loaded."))
                    return
                }

                continuation.resume(returning: asset)
            }
        }
    }
}

private struct Scout22LoadedClip {
    let url: URL
    let duration: Double
    let thumbnail: UIImage?
}

private struct Scout22AssetThumbnailCell: View {
    let asset: PHAsset
    let selectionIndex: Int?
    let onTap: () -> Void

    @StateObject private var imageLoader = Scout22AssetThumbnailLoader()

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image = imageLoader.image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        PassportTheme.card
                    }
                }
                .frame(height: 168)
                .clipped()

                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.46)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                HStack {
                    Text(SharedFormatters.duration(asset.duration))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Capsule())

                    Spacer()
                }
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

                if let selectionIndex {
                    Text("\(selectionIndex)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(width: 28, height: 28)
                        .background(PassportTheme.accent)
                        .clipShape(Circle())
                        .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(selectionIndex == nil ? PassportTheme.border.opacity(0.35) : PassportTheme.accent, lineWidth: selectionIndex == nil ? 1 : 2)
            )
        }
        .buttonStyle(.plain)
        .task {
            imageLoader.load(asset: asset)
        }
    }

}

@MainActor
private final class Scout22AssetThumbnailLoader: ObservableObject {
    @Published var image: UIImage?
    private let store = PHCachingImageManager()

    func load(asset: PHAsset) {
        guard image == nil else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        let scale = UIScreen.main.scale
        let targetSize = CGSize(width: 260 * scale, height: 420 * scale)
        store.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, _ in
            self?.image = image
        }
    }
}

private struct Scout22CameraRecorder: View {
    let purpose: Scout22VideoStudioPurpose
    @Binding var recordedClips: [Scout22VideoClip]
    let onError: (String) -> Void

    @StateObject private var recorder = Scout22CameraRecorderStore()

    var body: some View {
        ZStack {
            if recorder.permissionDenied {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "camera.fill")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(PassportTheme.textPrimary)
                    Text("Allow camera and microphone access to record a post.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(PassportTheme.textSecondary)
                    Button("Retry") {
                        Task {
                            await recorder.prepare()
                        }
                    }
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(PassportTheme.accent)
                    .foregroundStyle(.black)
                    .clipShape(Capsule())
                    Spacer()
                }
            } else {
                ZStack(alignment: .top) {
                    Scout22CameraPreview(session: recorder.session)
                        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 32, style: .continuous)
                                .stroke(PassportTheme.border.opacity(0.35), lineWidth: 1)
                        )

                    VStack {
                        HStack {
                            Button {
                                recorder.toggleCameraPosition()
                            } label: {
                                Image(systemName: "arrow.triangle.2.circlepath.camera")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 42, height: 42)
                                    .background(Color.black.opacity(0.44))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Text(recorder.totalDurationLabel)
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.44))
                                .clipShape(Capsule())
                        }
                        .padding(16)

                        Spacer()

                        HStack(spacing: 16) {
                            Button {
                                recorder.removeLastClip()
                                recordedClips = recorder.recordedClips
                            } label: {
                                Image(systemName: "delete.left.fill")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 52, height: 52)
                                    .background(Color.black.opacity(0.44))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .opacity(recorder.recordedClips.isEmpty ? 0.25 : 1)
                            .disabled(recorder.recordedClips.isEmpty)

                            Button {
                                recorder.toggleRecording()
                            } label: {
                                ZStack {
                                    Circle()
                                        .stroke(Color.white.opacity(0.3), lineWidth: 8)
                                        .frame(width: 90, height: 90)

                                    Circle()
                                        .fill(recorder.isRecording ? Color.white : PassportTheme.accent)
                                        .frame(width: recorder.isRecording ? 34 : 66, height: recorder.isRecording ? 34 : 66)
                                }
                            }
                            .buttonStyle(.plain)

                            Color.clear
                                .frame(width: 52, height: 52)
                        }
                        .padding(.bottom, 26)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await recorder.prepare()
        }
        .onDisappear {
            recorder.stopSession()
        }
        .onReceive(recorder.$recordedClips) { clips in
            recordedClips = clips
        }
        .onReceive(recorder.$errorMessage.compactMap { $0 }) { message in
            onError(message)
            recorder.errorMessage = nil
        }
    }
}

@MainActor
private final class Scout22CameraRecorderStore: NSObject, ObservableObject, @preconcurrency AVCaptureFileOutputRecordingDelegate {
    @Published var recordedClips: [Scout22VideoClip] = []
    @Published var isRecording = false
    @Published var permissionDenied = false
    @Published var errorMessage: String?
    @Published private var activeRecordingElapsed: TimeInterval = 0

    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var currentPosition: AVCaptureDevice.Position = .back
    private var recordingStartedAt: Date?
    private var recordingTickerTask: Task<Void, Never>?

    var totalDurationLabel: String {
        let committedDuration = recordedClips.reduce(0) { $0 + $1.duration }
        let total = Int((committedDuration + activeRecordingElapsed).rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    func prepare() async {
        let videoAuthorized = await AVCaptureDevice.requestAccessIfNeeded(for: .video)
        let audioAuthorized = await AVCaptureDevice.requestAccessIfNeeded(for: .audio)
        guard videoAuthorized, audioAuthorized else {
            permissionDenied = true
            return
        }

        permissionDenied = false
        configureSessionIfNeeded()
        startSession()
    }

    func startSession() {
        guard !session.isRunning else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker])
        try? AVAudioSession.sharedInstance().setActive(true)
        session.startRunning()
    }

    func stopSession() {
        guard session.isRunning else { return }
        stopRecordingTicker(resetElapsed: true)
        session.stopRunning()
    }

    func toggleCameraPosition() {
        currentPosition = currentPosition == .back ? .front : .back
        reconfigureInput()
    }

    func toggleRecording() {
        if movieOutput.isRecording {
            movieOutput.stopRecording()
            isRecording = false
            stopRecordingTicker(resetElapsed: false)
        } else {
            let url = temporaryMediaURL(fileExtension: "mov")
            movieOutput.startRecording(to: url, recordingDelegate: self)
            isRecording = true
            startRecordingTicker()
        }
    }

    func removeLastClip() {
        guard let clip = recordedClips.popLast() else { return }
        try? FileManager.default.removeItem(at: clip.url)
    }

    private func configureSessionIfNeeded() {
        guard currentInput == nil else { return }

        session.beginConfiguration()
        session.sessionPreset = .high
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
        if let mic = AVCaptureDevice.default(for: .audio),
           let micInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(micInput) {
            session.addInput(micInput)
        }
        session.commitConfiguration()
        reconfigureInput()
    }

    private func reconfigureInput() {
        session.beginConfiguration()
        if let currentInput {
            session.removeInput(currentInput)
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentPosition) else {
            errorMessage = "No camera is available on this device."
            session.commitConfiguration()
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
                currentInput = input
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        session.commitConfiguration()
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async {
            self.isRecording = false
            self.stopRecordingTicker(resetElapsed: true)
        }

        if let error {
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
            }
            return
        }

        Task {
            do {
                let asset = AVURLAsset(url: outputFileURL)
                let duration = try await asset.load(.duration).seconds
                let thumbnail = try await generateThumbnail(from: asset)
                let clip = Scout22VideoClip(
                    url: outputFileURL,
                    fileName: outputFileURL.lastPathComponent,
                    duration: duration,
                    thumbnail: thumbnail
                )
                await MainActor.run {
                    self.recordedClips.append(clip)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func startRecordingTicker() {
        recordingTickerTask?.cancel()
        recordingStartedAt = Date()
        activeRecordingElapsed = 0

        recordingTickerTask = Task { @MainActor in
            while !Task.isCancelled && self.isRecording {
                if let recordingStartedAt {
                    self.activeRecordingElapsed = max(0, Date().timeIntervalSince(recordingStartedAt))
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func stopRecordingTicker(resetElapsed: Bool) {
        recordingTickerTask?.cancel()
        recordingTickerTask = nil
        recordingStartedAt = nil
        if resetElapsed {
            activeRecordingElapsed = 0
        }
    }
}

private struct Scout22CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> Scout22CameraPreviewView {
        let view = Scout22CameraPreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: Scout22CameraPreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}

private final class Scout22CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

private struct Scout22VideoEditor: View {
    let clips: [Scout22VideoClip]
    let purpose: Scout22VideoStudioPurpose
    let onBack: () -> Void
    let onComplete: (Scout22ComposedVideo) -> Void

    @StateObject private var editorStore: Scout22VideoEditorStore
    @State private var showingTextSheet = false
    @State private var editingSticker: Scout22TextSticker?

    init(
        clips: [Scout22VideoClip],
        purpose: Scout22VideoStudioPurpose,
        onBack: @escaping () -> Void,
        onComplete: @escaping (Scout22ComposedVideo) -> Void
    ) {
        self.clips = clips
        self.purpose = purpose
        self.onBack = onBack
        self.onComplete = onComplete
        _editorStore = StateObject(wrappedValue: Scout22VideoEditorStore(clips: clips, purpose: purpose))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { proxy in
                ZStack {
                    if let url = editorStore.previewURL {
                        Scout22EditableVideoSurface(url: url)
                            .ignoresSafeArea()
                    } else {
                        ZStack {
                            Color.black
                            ProgressView().tint(PassportTheme.accent)
                        }
                        .ignoresSafeArea()
                    }

                    ForEach($editorStore.stickers) { $sticker in
                        Text(sticker.text)
                            .font(.custom(sticker.font.fontName, size: sticker.font.size))
                            .multilineTextAlignment(sticker.alignment.textAlignment)
                            .foregroundStyle(sticker.foregroundColor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(sticker.backgroundColor.opacity(sticker.backgroundOpacity))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .position(
                                x: proxy.size.width * sticker.normalizedX,
                                y: proxy.size.height * sticker.normalizedY
                            )
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        let x = min(max(value.location.x / proxy.size.width, 0.1), 0.9)
                                        let y = min(max(value.location.y / proxy.size.height, 0.12), 0.88)
                                        sticker.normalizedX = x
                                        sticker.normalizedY = y
                                    }
                            )
                            .onTapGesture {
                                editingSticker = sticker
                                showingTextSheet = true
                            }
                    }
                }
            }
            .ignoresSafeArea()

            VStack {
                HStack(alignment: .top) {
                    Button { onBack() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.44))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    VStack(spacing: 20) {
                        FeedActionButton(symbol: "textformat", label: "Text") {
                            editingSticker = nil
                            showingTextSheet = true
                        }

                        ForEach(editorStore.stickers) { sticker in
                            Button {
                                editorStore.removeSticker(id: sticker.id)
                            } label: {
                                VStack(spacing: 4) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.black.opacity(0.38))
                                            .frame(width: 48, height: 48)
                                        Image(systemName: "xmark")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                    Text(sticker.text)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                        .frame(width: 56)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.trailing, 14)
                }
                .padding(.top, 16)
                .padding(.leading, 16)

                Spacer()

                Button {
                    Task {
                        if let result = await editorStore.exportFinalVideo() {
                            onComplete(result)
                        }
                    }
                } label: {
                    Text(purpose.completionLabel)
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(editorStore.isProcessing || editorStore.previewURL == nil ? Color.white.opacity(0.25) : PassportTheme.accent)
                        .foregroundStyle(editorStore.isProcessing || editorStore.previewURL == nil ? Color.white.opacity(0.5) : .black)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(editorStore.isProcessing || editorStore.previewURL == nil)
                .padding(.horizontal, 18)
                .padding(.bottom, 36)
            }

            if editorStore.isProcessing {
                Color.black.opacity(0.55).ignoresSafeArea()

                VStack(spacing: 14) {
                    ProgressView(value: editorStore.processingProgress)
                        .tint(PassportTheme.accent)
                    Text(editorStore.processingMessage)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                }
                .padding(24)
                .background(Color.black.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
        .task {
            await editorStore.preparePreview()
        }
        .sheet(isPresented: $showingTextSheet) {
            Scout22TextOverlayEditor(
                sticker: editingSticker,
                onSave: { sticker in
                    editorStore.saveSticker(sticker)
                }
            )
            .presentationDetents([.medium])
        }
        .alert("Issue", isPresented: Binding(
            get: { editorStore.errorMessage != nil },
            set: { if !$0 { editorStore.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(editorStore.errorMessage ?? "")
        }
    }
}

@MainActor
private final class Scout22VideoEditorStore: ObservableObject {
    @Published var previewURL: URL?
    @Published var stickers: [Scout22TextSticker] = []
    @Published var selectedAudioURL: URL?
    @Published var isProcessing = false
    @Published var processingProgress = 0.0
    @Published var processingMessage = "Processing..."
    @Published var errorMessage: String?

    let clips: [Scout22VideoClip]
    let purpose: Scout22VideoStudioPurpose

    init(clips: [Scout22VideoClip], purpose: Scout22VideoStudioPurpose) {
        self.clips = clips
        self.purpose = purpose
    }

    var soundDisplayTitle: String {
        selectedAudioURL?.deletingPathExtension().lastPathComponent ?? "Add Sound"
    }

    func preparePreview() async {
        guard previewURL == nil else { return }
        do {
            if clips.count == 1 {
                previewURL = clips[0].url
                return
            }

            processingMessage = "Merging clips..."
            isProcessing = true
            let result = try await Scout22VideoComposer.concatenate(clips: clips, progress: { progress in
                Task { @MainActor in
                    self.processingProgress = progress
                }
            })
            previewURL = result.url
            isProcessing = false
            processingProgress = 0
        } catch {
            isProcessing = false
            errorMessage = error.localizedDescription
        }
    }

    func handleAudioImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                selectedAudioURL = try copyMediaFileToTemporaryDirectory(from: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    func clearAudio() {
        selectedAudioURL = nil
    }

    func saveSticker(_ sticker: Scout22TextSticker) {
        if let index = stickers.firstIndex(where: { $0.id == sticker.id }) {
            stickers[index] = sticker
        } else {
            stickers.append(sticker)
        }
    }

    func removeSticker(id: UUID) {
        stickers.removeAll { $0.id == id }
    }

    func exportFinalVideo() async -> Scout22ComposedVideo? {
        do {
            processingMessage = "Exporting Post..."
            processingProgress = 0
            isProcessing = true

            let resultURL = try await Scout22VideoComposer.export(
                clips: clips,
                audioURL: selectedAudioURL,
                stickers: stickers,
                progress: { progress in
                    Task { @MainActor in
                        self.processingProgress = progress
                    }
                }
            )

            let resultAsset = AVURLAsset(url: resultURL)
            let duration = try await resultAsset.load(.duration).seconds
            if let maxDuration = purpose.maxDuration, duration > maxDuration {
                throw Scout22VideoStudioError.message("Keep this video under \(Int(maxDuration) / 60) minutes.")
            }

            isProcessing = false
            processingProgress = 1
            return Scout22ComposedVideo(
                url: resultURL,
                duration: duration,
                fileName: resultURL.lastPathComponent
            )
        } catch {
            isProcessing = false
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

private struct Scout22TextSticker: Identifiable, Equatable {
    let id: UUID
    var text: String
    var normalizedX: Double
    var normalizedY: Double
    var foregroundColor: Color
    var foregroundUIColor: UIColor
    var backgroundColor: Color
    var backgroundUIColor: UIColor
    var backgroundOpacity: Double
    var font: Scout22FontChoice
    var alignment: Scout22TextAlignment

    init(
        id: UUID = UUID(),
        text: String,
        normalizedX: Double = 0.5,
        normalizedY: Double = 0.28,
        foregroundUIColor: UIColor = .white,
        backgroundUIColor: UIColor = .black,
        backgroundOpacity: Double = 0.0,
        font: Scout22FontChoice = .rounded,
        alignment: Scout22TextAlignment = .center
    ) {
        self.id = id
        self.text = text
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        self.foregroundUIColor = foregroundUIColor
        self.foregroundColor = Color(uiColor: foregroundUIColor)
        self.backgroundUIColor = backgroundUIColor
        self.backgroundColor = Color(uiColor: backgroundUIColor)
        self.backgroundOpacity = backgroundOpacity
        self.font = font
        self.alignment = alignment
    }
}

private enum Scout22TextAlignment: String, CaseIterable, Identifiable {
    case left
    case center
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: return "Left"
        case .center: return "Center"
        case .right: return "Right"
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }

    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }
}

private enum Scout22FontChoice: String, CaseIterable, Identifiable {
    case rounded
    case serif
    case mono
    case black
    case condensed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        case .mono: return "Mono"
        case .black: return "Heavy"
        case .condensed: return "Narrow"
        }
    }

    var fontName: String {
        uiFont(ofSize: 32).fontName
    }

    var size: CGFloat { 32 }

    func uiFont(ofSize size: CGFloat) -> UIFont {
        switch self {
        case .rounded:
            let descriptor = UIFont.systemFont(ofSize: size, weight: .bold).fontDescriptor.withDesign(.rounded)
            return descriptor.map { UIFont(descriptor: $0, size: size) } ?? .boldSystemFont(ofSize: size)
        case .serif:
            return UIFont(name: "Georgia-Bold", size: size) ?? .boldSystemFont(ofSize: size)
        case .mono:
            return UIFont.monospacedSystemFont(ofSize: size, weight: .bold)
        case .black:
            return UIFont.systemFont(ofSize: size, weight: .black)
        case .condensed:
            return UIFont(name: "AvenirNextCondensed-Bold", size: size) ?? .boldSystemFont(ofSize: size)
        }
    }
}

private struct Scout22TextOverlayEditor: View {
    let sticker: Scout22TextSticker?
    let onSave: (Scout22TextSticker) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var font: Scout22FontChoice = .rounded
    @State private var alignment: Scout22TextAlignment = .center
    @State private var foreground = UIColor.white
    @State private var background = UIColor.black
    @State private var backgroundOpacity = 0.0

    private let colors: [UIColor] = [
        .white,
        .black,
        .systemYellow,
        .systemPink,
        .systemBlue,
        .systemGreen,
        .systemOrange
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TextField("Type your overlay", text: $text, axis: .vertical)
                        .lineLimit(3...6)
                        .textFieldStyle(PassportTextFieldStyle())

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Font")
                            .font(.headline)
                            .foregroundStyle(PassportTheme.textPrimary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Scout22FontChoice.allCases) { option in
                                    Button {
                                        font = option
                                    } label: {
                                        Text(option.title)
                                            .font(.custom(option.fontName, size: 16))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 10)
                                            .background(font == option ? PassportTheme.accent : PassportTheme.card)
                                            .foregroundStyle(font == option ? .black : PassportTheme.textPrimary)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        ForEach(Scout22TextAlignment.allCases) { option in
                            Button {
                                alignment = option
                            } label: {
                                Text(option.title)
                                    .font(.subheadline.weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(alignment == option ? PassportTheme.accent : PassportTheme.card)
                                    .foregroundStyle(alignment == option ? .black : PassportTheme.textPrimary)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    colorPickerSection(title: "Text Color", selected: $foreground)
                    colorPickerSection(title: "Background", selected: $background)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Background Strength")
                            .font(.headline)
                            .foregroundStyle(PassportTheme.textPrimary)

                        Slider(value: $backgroundOpacity, in: 0...0.8)
                            .tint(PassportTheme.accent)
                    }
                }
                .padding(20)
            }
            .background(PassportTheme.background)
            .navigationTitle(sticker == nil ? "Add Text" : "Edit Text")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(PassportTheme.textPrimary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let updated = Scout22TextSticker(
                            id: sticker?.id ?? UUID(),
                            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                            normalizedX: sticker?.normalizedX ?? 0.5,
                            normalizedY: sticker?.normalizedY ?? 0.28,
                            foregroundUIColor: foreground,
                            backgroundUIColor: background,
                            backgroundOpacity: backgroundOpacity,
                            font: font,
                            alignment: alignment
                        )
                        onSave(updated)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .foregroundStyle(PassportTheme.textPrimary)
                }
            }
            .onAppear {
                guard let sticker else { return }
                text = sticker.text
                font = sticker.font
                alignment = sticker.alignment
                foreground = sticker.foregroundUIColor
                background = sticker.backgroundUIColor
                backgroundOpacity = sticker.backgroundOpacity
            }
        }
    }

    private func colorPickerSection(title: String, selected: Binding<UIColor>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(PassportTheme.textPrimary)

            HStack(spacing: 12) {
                ForEach(colors, id: \.self) { color in
                    Button {
                        selected.wrappedValue = color
                    } label: {
                        Circle()
                            .fill(Color(uiColor: color))
                            .frame(width: 30, height: 30)
                            .overlay(
                                Circle()
                                    .stroke(selected.wrappedValue == color ? PassportTheme.accent : Color.clear, lineWidth: 3)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct Scout22EditableVideoSurface: View {
    let url: URL

    @StateObject private var playerStore = Scout22EditablePlayerStore()

    var body: some View {
        ZStack {
            Scout22PlayerLayerView(player: playerStore.player)
                .background(Color.black)

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { playerStore.toggle() }

            if !playerStore.isPlaying {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.55))
                        .frame(width: 68, height: 68)
                    Image(systemName: "play.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: 2)
                }
                .allowsHitTesting(false)
            }
        }
        .onAppear { playerStore.configure(url: url) }
        .onDisappear { playerStore.pause() }
    }
}

private final class Scout22EditablePlayerStore: ObservableObject {
    let player = AVPlayer()
    @Published var isPlaying = false
    @Published var progress = 0.0

    private var timeObserver: Any?
    private var currentURL: URL?

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
    }

    func configure(url: URL) {
        guard currentURL != url else { return }
        currentURL = url
        configureAudioSession()
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.seek(to: .zero)
        isPlaying = false
        progress = 0
        setUpObserver()
    }

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func toggle() {
        if isPlaying {
            pause()
        } else {
            player.play()
            isPlaying = true
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func seek(to progress: Double) {
        guard let duration = player.currentItem?.duration.seconds, duration.isFinite else { return }
        let time = CMTime(seconds: duration * progress, preferredTimescale: 600)
        player.seek(to: time)
        self.progress = progress
    }

    private func setUpObserver() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] currentTime in
            guard let self else { return }
            guard let duration = self.player.currentItem?.duration.seconds, duration.isFinite, duration > 0 else {
                self.progress = 0
                return
            }
            self.progress = currentTime.seconds / duration
            if self.progress >= 0.999 {
                self.player.seek(to: .zero)
                self.player.pause()
                self.isPlaying = false
                self.progress = 0
            }
        }
    }
}

private struct Scout22PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> Scout22PlayerContainerView {
        let view = Scout22PlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: Scout22PlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = .resizeAspectFill
    }
}

private final class Scout22PlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

private enum Scout22VideoStudioError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            return message
        }
    }
}

private enum Scout22VideoComposer {
    static func concatenate(
        clips: [Scout22VideoClip],
        progress: @escaping (Double) -> Void
    ) async throws -> (url: URL, duration: Double) {
        let result = try buildComposition(for: clips, audioURL: nil, stickers: [])
        let url = temporaryMediaURL(fileExtension: "mp4")
        try await export(
            asset: result.composition,
            videoComposition: result.videoComposition,
            outputURL: url,
            progress: progress
        )
        return (url, result.totalDuration.seconds)
    }

    static func export(
        clips: [Scout22VideoClip],
        audioURL: URL?,
        stickers: [Scout22TextSticker],
        progress: @escaping (Double) -> Void
    ) async throws -> URL {
        let result = try buildComposition(for: clips, audioURL: audioURL, stickers: stickers)
        let url = temporaryMediaURL(fileExtension: "mp4")
        try await export(
            asset: result.composition,
            videoComposition: result.videoComposition,
            outputURL: url,
            progress: progress
        )
        return (url)
    }

    private static func buildComposition(
        for clips: [Scout22VideoClip],
        audioURL: URL?,
        stickers: [Scout22TextSticker]
    ) throws -> (composition: AVMutableComposition, videoComposition: AVMutableVideoComposition, totalDuration: CMTime) {
        let composition = AVMutableComposition()
        let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        var instructions: [AVMutableVideoCompositionInstruction] = []
        var cursor = CMTime.zero
        // 720p portrait: pitch-video quality at half the encode work of 1080p,
        // and small enough that the upload-prep pass never re-encodes.
        let renderSize = CGSize(width: 720, height: 1280)

        for clip in clips {
            let asset = AVURLAsset(url: clip.url)
            guard let assetVideoTrack = asset.tracks(withMediaType: .video).first else { continue }
            let duration = asset.duration

            try videoTrack?.insertTimeRange(.init(start: .zero, duration: duration), of: assetVideoTrack, at: cursor)
            if let assetAudioTrack = asset.tracks(withMediaType: .audio).first {
                try audioTrack?.insertTimeRange(.init(start: .zero, duration: duration), of: assetAudioTrack, at: cursor)
            }

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = .init(start: cursor, duration: duration)

            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack!)
            let transform = transformForPortraitVideo(
                assetTrack: assetVideoTrack,
                renderSize: renderSize
            )
            layerInstruction.setTransform(transform, at: cursor)
            instruction.layerInstructions = [layerInstruction]
            instructions.append(instruction)

            cursor = cursor + duration
        }

        if let audioURL {
            let soundAsset = AVURLAsset(url: audioURL)
            if let soundTrack = soundAsset.tracks(withMediaType: .audio).first {
                let soundCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                var soundCursor = CMTime.zero
                while soundCursor < cursor {
                    let remaining = cursor - soundCursor
                    let insertDuration = min(soundAsset.duration, remaining)
                    try soundCompositionTrack?.insertTimeRange(.init(start: .zero, duration: insertDuration), of: soundTrack, at: soundCursor)
                    soundCursor = soundCursor + insertDuration
                }
            }
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = instructions
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.renderSize = renderSize

        if !stickers.isEmpty {
            let parentLayer = CALayer()
            parentLayer.frame = CGRect(origin: .zero, size: renderSize)
            let videoLayer = CALayer()
            videoLayer.frame = CGRect(origin: .zero, size: renderSize)
            parentLayer.addSublayer(videoLayer)

            for sticker in stickers {
                let layer = CATextLayer()
                layer.contentsScale = UIScreen.main.scale
                layer.string = attributedStickerText(for: sticker)
                layer.alignmentMode = sticker.alignment.nsTextAlignment.caAlignmentMode
                let width = renderSize.width * 0.72
                let height = renderSize.height * 0.2
                let x = renderSize.width * sticker.normalizedX - width / 2
                let y = renderSize.height * sticker.normalizedY - height / 2
                layer.frame = CGRect(x: x, y: y, width: width, height: height)
                layer.isWrapped = true
                layer.backgroundColor = sticker.backgroundUIColor.withAlphaComponent(sticker.backgroundOpacity).cgColor
                layer.cornerRadius = 18
                parentLayer.addSublayer(layer)
            }

            videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
                postProcessingAsVideoLayer: videoLayer,
                in: parentLayer
            )
        }

        return (composition, videoComposition, cursor)
    }

    private static func transformForPortraitVideo(assetTrack: AVAssetTrack, renderSize: CGSize) -> CGAffineTransform {
        let preferredTransform = assetTrack.preferredTransform
        let naturalSize = assetTrack.naturalSize.applying(preferredTransform)
        let videoSize = CGSize(width: abs(naturalSize.width), height: abs(naturalSize.height))

        let scale = min(renderSize.width / videoSize.width, renderSize.height / videoSize.height)
        let scaledSize = CGSize(width: videoSize.width * scale, height: videoSize.height * scale)
        let xOffset = (renderSize.width - scaledSize.width) / 2
        let yOffset = (renderSize.height - scaledSize.height) / 2

        return preferredTransform
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: xOffset, y: yOffset))
    }

    private static func export(
        asset: AVAsset,
        videoComposition: AVVideoComposition,
        outputURL: URL,
        progress: @escaping (Double) -> Void
    ) async throws {
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
            throw Scout22VideoStudioError.message("The selected clips could not be exported.")
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.videoComposition = videoComposition
        // Target the upload cap directly so this is the ONLY encode — the
        // old HighestQuality pass regularly blew past 45MB and triggered a
        // full second compression in prepareVideoForUpload.
        exportSession.fileLengthLimit = VideoProcessing.preferredUploadLimitBytes

        try? FileManager.default.removeItem(at: outputURL)

        let progressTask = Task {
            while exportSession.status == .waiting || exportSession.status == .exporting {
                progress(Double(exportSession.progress))
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }

        try await withCheckedThrowingContinuation { continuation in
            exportSession.exportAsynchronously {
                progressTask.cancel()
                switch exportSession.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(throwing: exportSession.error ?? Scout22VideoStudioError.message("Video export failed."))
                case .cancelled:
                    continuation.resume(throwing: Scout22VideoStudioError.message("Video export was cancelled."))
                default:
                    continuation.resume(throwing: Scout22VideoStudioError.message("Video export failed."))
                }
            }
        }
    }

    private static func attributedStickerText(for sticker: Scout22TextSticker) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = sticker.alignment.nsTextAlignment
        paragraphStyle.lineBreakMode = .byWordWrapping

        return NSAttributedString(
            string: sticker.text,
            attributes: [
                .font: sticker.font.uiFont(ofSize: 76),
                .foregroundColor: sticker.foregroundUIColor,
                .paragraphStyle: paragraphStyle
            ]
        )
    }
}

private func generateThumbnail(from asset: AVAsset) async throws -> UIImage? {
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 500, height: 900)
    let cgImage = try await generator.image(at: .zero).image
    return UIImage(cgImage: cgImage)
}

private func copyMediaFileToTemporaryDirectory(from url: URL) throws -> URL {
    let target = temporaryMediaURL(fileExtension: url.pathExtension)
    try? FileManager.default.removeItem(at: target)
    try FileManager.default.copyItem(at: url, to: target)
    return target
}

private func temporaryMediaURL(fileExtension: String) -> URL {
    URL(filePath: NSTemporaryDirectory())
        .appending(path: "jobtok-media-\(UUID().uuidString).\(fileExtension)")
}

private extension AVCaptureDevice {
    static func requestAccessIfNeeded(for mediaType: AVMediaType) async -> Bool {
        let status = authorizationStatus(for: mediaType)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await requestAccess(for: mediaType)
        default:
            return false
        }
    }
}

private extension CATextLayerAlignmentMode {
    init(_ alignment: NSTextAlignment) {
        switch alignment {
        case .left:
            self = .left
        case .right:
            self = .right
        default:
            self = .center
        }
    }
}

private extension NSTextAlignment {
    var caAlignmentMode: CATextLayerAlignmentMode {
        switch self {
        case .left:
            return .left
        case .right:
            return .right
        default:
            return .center
        }
    }
}
