import UIKit

/// S-3: renders a plain-text cover letter to a PDF, on device.
///
/// Many ATS ask for the cover letter as a file upload rather than a textarea,
/// and there is nothing to upload unless we make one. Deliberately text-only:
/// this is a letter, not a designed document, and the recruiter's ATS will
/// strip the formatting on ingest anyway.
///
/// `UIGraphicsPDFRenderer` + `NSAttributedString` keeps this dependency-free,
/// consistent with how carousel cards are rendered on device rather than
/// server-side. The heavier template work for S-4 resumes is separate.
enum CoverLetterPDF {
    /// US Letter at 72dpi, the size every ATS parser expects.
    private static let pageSize = CGSize(width: 612, height: 792)
    private static let margin: CGFloat = 64

    static func render(body: String, candidateName: String?) -> Data? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let text = NSMutableAttributedString()

        if let name = candidateName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            text.append(NSAttributedString(string: name + "\n\n", attributes: [
                .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: UIColor.black
            ]))
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 12
        text.append(NSAttributedString(string: trimmed, attributes: [
            .font: UIFont.systemFont(ofSize: 11.5),
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraph
        ]))

        let bounds = CGRect(
            x: margin,
            y: margin,
            width: pageSize.width - margin * 2,
            height: pageSize.height - margin * 2
        )

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        return renderer.pdfData { context in
            // CoreText paginates by handing back the range it consumed, so a
            // long letter flows onto a second page instead of being clipped.
            let framesetter = CTFramesetterCreateWithAttributedString(text)
            var consumed = 0
            let total = text.length

            repeat {
                context.beginPage()
                let path = CGPath(rect: bounds, transform: nil)
                let frame = CTFramesetterCreateFrame(
                    framesetter,
                    CFRangeMake(consumed, 0),
                    path,
                    nil
                )

                guard let cgContext = UIGraphicsGetCurrentContext() else { return }
                // CoreText draws bottom-up; flip so the text lands upright.
                cgContext.saveGState()
                cgContext.translateBy(x: 0, y: pageSize.height)
                cgContext.scaleBy(x: 1, y: -1)
                CTFrameDraw(frame, cgContext)
                cgContext.restoreGState()

                let visible = CTFrameGetVisibleStringRange(frame)
                // A page that fits nothing would loop forever — bail rather
                // than hang the apply flow.
                if visible.length <= 0 { return }
                consumed += visible.length
            } while consumed < total
        }
    }

    /// Filename an ATS will accept and a recruiter can identify in a folder of
    /// hundreds. Spaces and punctuation are stripped: some uploaders reject
    /// them outright.
    static func fileName(candidateName: String?, companyName: String?) -> String {
        let parts = [candidateName, companyName, "Cover Letter"]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let safe = parts
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined()
            .replacingOccurrences(of: " ", with: "_")
        return (safe.isEmpty ? "Cover_Letter" : safe) + ".pdf"
    }
}
