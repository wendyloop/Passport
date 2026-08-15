import SwiftUI
import UIKit

// Renders a job's carousel to publishable JPEGs and builds its caption.
//
// The carousel art exists only as SwiftUI — `carousels.content` is text and a
// theme id, and the v1 migration is explicit that we never store images. So
// publishing needs one capture step: draw the same CardTemplateSlideView the
// feed uses and write it to a file instead of the screen. Nothing is
// regenerated; this is a screenshot of work already done.
//
// The design canvas is 390×487.5 (exactly 4:5), which is Instagram's native
// feed ratio — rendering at scale 1080/390 lands on 1080×1350 with no
// cropping or letterboxing.

@MainActor
enum SocialCardExporter {
    /// CardCanvas' design space. Kept in sync with CarouselCardTemplates.
    static let designWidth: CGFloat = 390
    static let designHeight: CGFloat = 487.5
    /// Instagram's preferred long edge for a 4:5 feed image.
    static let outputWidth: CGFloat = 1080

    /// Instagram allows 2–10 images per carousel; TikTok photo mode is
    /// similar. Below the minimum there is no carousel to post.
    static let minSlides = 2
    static let maxSlides = 10

    enum ExportError: LocalizedError {
        case tooFewSlides(Int)
        case renderFailed(Int)

        var errorDescription: String? {
            switch self {
            case .tooFewSlides(let n):
                return "Only \(n) publishable slide(s); need at least \(minSlides)."
            case .renderFailed(let index):
                return "Slide \(index + 1) failed to render."
            }
        }
    }

    // MARK: - Slide selection

    /// Slides that may be published.
    ///
    /// The founder slide is excluded unconditionally. It names a real person
    /// extracted by an LLM from a job description or a contact scrape;
    /// showing that to one job seeker inside the app is a different act from
    /// publishing it to a public grid, and they never consented to the
    /// latter. This filter is the only thing standing between that data and a
    /// public image file — do not make it conditional.
    static func publishableSlides(_ carousel: Carousel, job: JobPostingRecord) -> [CarouselSlide] {
        carousel.renderableSlides
            .filter { slide in
                if case .founder = slide { return false }
                // Same emptiness guard the feed applies, for the same reason:
                // a bare "the deets" header is a dead card.
                if case .details(let details) = slide {
                    return details.hasRenderableContent(for: job)
                }
                return true
            }
            .prefix(maxSlides)
            .map { $0 }
    }

    // MARK: - Rendering

    /// One JPEG per publishable slide, in order, at 1080×1350.
    static func renderJPEGs(job: JobPostingRecord, carousel: Carousel) throws -> [Data] {
        let slides = publishableSlides(carousel, job: job)
        guard slides.count >= minSlides else {
            throw ExportError.tooFewSlides(slides.count)
        }

        let style = CarouselStyle.resolve(jobID: job.id, themeID: carousel.themeId)
        var output: [Data] = []
        output.reserveCapacity(slides.count)

        for (index, slide) in slides.enumerated() {
            let card = CardTemplateSlideView(
                slide: slide,
                style: style,
                job: job,
                // No live CTA in an exported image, and no founder path.
                onEmailFounder: nil,
                previewMode: true
            )
            .frame(width: designWidth, height: designHeight)

            let renderer = ImageRenderer(content: card)
            renderer.scale = outputWidth / designWidth
            // Opaque: JPEG has no alpha, and a transparent ground would
            // composite to black on the platforms' side.
            renderer.isOpaque = true

            guard let image = renderer.uiImage,
                  let data = image.jpegData(compressionQuality: 0.9) else {
                throw ExportError.renderFailed(index)
            }
            output.append(data)
        }
        return output
    }

    // MARK: - Caption

    /// Caption built from fields the backend already generates.
    ///
    /// `hook` and `youd_line` are produced by the carousel LLM for every job
    /// and rendered by no template — they were written to be short, second
    /// person and specific, which is exactly what a caption wants, so this is
    /// the one place they finally earn their tokens.
    static func caption(job: JobPostingRecord, carousel: Carousel) -> String {
        var lines: [String] = []

        if let opener = hookLine(carousel) {
            lines.append(opener)
            lines.append("")
        }

        lines.append("\(job.title) · \(job.displayCompanyName)")

        var facts: [String] = []
        if let comp = job.compensationSummary ?? job.compensationText, !comp.isEmpty {
            facts.append("💰 \(comp)")
        }
        if let location = job.location, !location.isEmpty {
            facts.append("📍 \(location)")
        }
        if !facts.isEmpty { lines.append(facts.joined(separator: "   ")) }

        lines.append("")
        lines.append("apply in the scout22 app — link in bio 👆")

        return lines.joined(separator: "\n")
    }

    /// The LLM's hook, falling back to its you'd-line. Both are capped short
    /// by the backend schema (70 and 80 chars).
    private static func hookLine(_ carousel: Carousel) -> String? {
        for slide in carousel.content {
            guard case .cover(let cover) = slide else { continue }
            if let hook = cover.hook?.trimmingCharacters(in: .whitespacesAndNewlines), !hook.isEmpty {
                return hook
            }
            if let youd = cover.youdLine?.trimmingCharacters(in: .whitespacesAndNewlines), !youd.isEmpty {
                return youd
            }
        }
        return nil
    }

    /// Hashtags derived from what the job actually is. Deliberately modest —
    /// keyword-stuffed tag walls read as spam and Instagram caps at 30.
    static func hashtags(job: JobPostingRecord) -> [String] {
        var tags = ["scout22", "startupjobs", "hiring", "techjobs"]

        switch job.jobFunction {
        case .engineering:        tags.append(contentsOf: ["engineeringjobs", "developerjobs"])
        case .design:             tags.append(contentsOf: ["designjobs", "uxjobs"])
        case .product:            tags.append("productjobs")
        case .science:            tags.append(contentsOf: ["datascience", "machinelearningjobs"])
        case .sales:              tags.append("salesjobs")
        case .marketing:          tags.append("marketingjobs")
        case .support:            tags.append("customersuccess")
        case .operations:         tags.append("opsjobs")
        case .hr:                 tags.append(contentsOf: ["hrjobs", "recruiting"])
        case .finance:            tags.append("financejobs")
        case .legal:              tags.append("legaljobs")
        case .programManagement:  tags.append("projectmanagement")
        case .clinical:           tags.append(contentsOf: ["healthcarejobs", "clinicaljobs"])
        case .none:               break
        }

        if let location = job.location?.lowercased() {
            if location.contains("remote") { tags.append("remotework") }
            if location.contains("new york") || location.contains("nyc") { tags.append("nycjobs") }
            if location.contains("san francisco") || location.contains("sf") { tags.append("sfjobs") }
            if location.contains("london") { tags.append("londonjobs") }
        }

        return tags
    }

    /// Storage path for one slide inside the `social-cards` bucket.
    static func storagePath(jobID: String, platform: SocialPlatform, index: Int) -> String {
        "\(jobID)/\(platform.rawValue)/\(index).jpg"
    }
}
