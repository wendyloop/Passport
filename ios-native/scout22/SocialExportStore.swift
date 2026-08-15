import Foundation
import SwiftUI

// Drives social-card export batches from the admin Social tab.
//
// Render is bursty and must happen on-device (the carousel art is SwiftUI —
// see SocialCardExporter); publishing is a cron draining the queue at a few
// posts a day. So one batch of ~20 jobs every week or two keeps the account
// fed without anyone touching it in between.
//
// There is no approval step by design: the quality bar lives in the
// get_jobs_needing_social_post RPC, which applies identically whether a human
// or the cron does the posting. `skip` here is a manual kill switch for a
// specific card, not a gate every card must pass.

@MainActor
final class SocialExportStore: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var progress: String?
    @Published private(set) var lastError: String?
    @Published private(set) var lastRunSummary: String?
    @Published private(set) var queue: [SocialPostRecord] = []
    @Published var platform: SocialPlatform = .instagram

    /// Injected by AdminHomeView; returns a session with a live token.
    var sessionProvider: (() async throws -> AuthSession)?

    private let service = SupabaseService.shared

    /// One batch fills roughly two weeks of posting at 1–3/day.
    static let defaultBatchSize = 20

    // MARK: - Queue

    func loadQueue() async {
        guard let sessionProvider else { return }
        do {
            let session = try await sessionProvider()
            queue = try await service.fetchSocialPosts(platform: platform, session: session)
            lastError = nil
        } catch {
            lastError = friendly(error)
        }
    }

    func setStatus(_ post: SocialPostRecord, to status: SocialPostStatus) async {
        guard let sessionProvider else { return }
        do {
            let session = try await sessionProvider()
            try await service.updateSocialPostStatus(id: post.id, status: status, session: session)
            await loadQueue()
        } catch {
            lastError = friendly(error)
        }
    }

    // MARK: - Batch

    func runBatch(limit: Int = defaultBatchSize) async {
        guard !isRunning, let sessionProvider else { return }
        isRunning = true
        lastError = nil
        lastRunSummary = nil
        defer { isRunning = false; progress = nil }

        var exported = 0
        var skipped = 0
        var failed = 0

        do {
            let session = try await sessionProvider()

            progress = "Finding eligible jobs…"
            let jobIDs = try await service.fetchJobIDsNeedingSocialPost(
                limit: limit,
                platform: platform,
                session: session
            )
            guard !jobIDs.isEmpty else {
                lastRunSummary = "Nothing eligible — the queue is empty."
                await loadQueue()
                return
            }

            progress = "Loading \(jobIDs.count) jobs…"
            let jobs = try await service.fetchJobs(ids: jobIDs, session: session)

            for (index, job) in jobs.enumerated() {
                progress = "Rendering \(index + 1)/\(jobs.count) — \(job.title)"

                guard let carousel = job.carousel else {
                    skipped += 1
                    continue
                }

                do {
                    // Render first: if a job can't produce enough publishable
                    // slides we skip it without leaving orphaned uploads.
                    let jpegs = try SocialCardExporter.renderJPEGs(job: job, carousel: carousel)

                    var paths: [String] = []
                    for (slideIndex, jpeg) in jpegs.enumerated() {
                        let path = SocialCardExporter.storagePath(
                            jobID: job.id,
                            platform: platform,
                            index: slideIndex
                        )
                        _ = try await service.uploadSocialCard(path: path, jpeg: jpeg, session: session)
                        paths.append(path)
                    }

                    let draft = SocialPostDraft(
                        jobID: job.id,
                        platform: platform.rawValue,
                        imagePaths: paths,
                        caption: SocialCardExporter.caption(job: job, carousel: carousel),
                        hashtags: SocialCardExporter.hashtags(job: job)
                    )
                    try await service.createSocialPost(draft, session: session)
                    exported += 1
                } catch let error as SocialCardExporter.ExportError {
                    // Too few slides is an expected outcome, not a failure —
                    // it just means this job isn't postable.
                    if case .tooFewSlides = error { skipped += 1 } else { failed += 1 }
                } catch {
                    failed += 1
                    lastError = friendly(error)
                }
            }

            var parts = ["\(exported) exported"]
            if skipped > 0 { parts.append("\(skipped) skipped") }
            if failed > 0 { parts.append("\(failed) failed") }
            lastRunSummary = parts.joined(separator: " · ")
            await loadQueue()
        } catch {
            lastError = friendly(error)
        }
    }

    // MARK: - Sharing

    /// Public bucket URL for a stored card. Used by the TikTok hand-off (its
    /// audit is unfinished, so those go out manually) and for eyeballing what
    /// the publisher will send.
    func publicURL(for path: String) -> URL? {
        service.publicStorageURL(bucket: "social-cards", path: path)
    }

    private func friendly(_ error: Error) -> String {
        SupabaseErrorMapping.friendlyMessage(for: error)
    }
}
