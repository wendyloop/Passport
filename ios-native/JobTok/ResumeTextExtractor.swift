import Foundation
import PDFKit

/// Best-effort local text extraction from an uploaded resume, fed to the
/// parse-resume edge function as a fallback when server-side parsing can't
/// read the file. Unsupported formats return nil.
enum ResumeTextExtractor {
    static func extractText(from url: URL) -> String? {
        let fileExtension = url.pathExtension.lowercased()

        if fileExtension == "pdf", let document = PDFDocument(url: url) {
            return (0..<document.pageCount)
                .compactMap { document.page(at: $0)?.string }
                .joined(separator: "\n")
        }

        if ["txt", "rtf"].contains(fileExtension) {
            return try? String(contentsOf: url)
        }

        return nil
    }
}
