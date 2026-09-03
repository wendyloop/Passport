import UIKit

/// S-4: renders a tailored resume to PDF, on device.
///
/// **One template, and it is deliberately plain.** Every resume rendered here
/// is going into an applicant tracking system, which reads the text layer and
/// discards the layout. Columns, sidebars, tables, icons and graphics are the
/// documented causes of ATS parse failures — a two-column resume routinely
/// interleaves into nonsense. So: single column, one font family, real text
/// in reading order, no drawing primitives at all.
///
/// Same dependency-free approach as `CoverLetterPDF` — `UIGraphicsPDFRenderer`
/// plus CoreText — rather than a layout library.
enum ResumePDF {
    private static let pageSize = CGSize(width: 612, height: 792)   // US Letter, 72dpi
    private static let margin: CGFloat = 54

    // MARK: - Input

    /// What the renderer needs, independent of where it came from. A base
    /// resume and a tailored version both flatten into this, so the renderer
    /// does not branch on which it was handed.
    struct Content {
        struct Role {
            let company: String
            let title: String
            let dates: String
            let bullets: [String]
        }
        struct School {
            let school: String
            let degree: String
            let year: String
        }

        var fullName: String
        var contactLine: String
        var summary: String?
        var roles: [Role]
        var education: [School]
        var skills: [String]
    }

    // MARK: - Type scale

    private static let nameFont = UIFont.systemFont(ofSize: 20, weight: .bold)
    private static let contactFont = UIFont.systemFont(ofSize: 9.5)
    private static let sectionFont = UIFont.systemFont(ofSize: 10, weight: .bold)
    private static let roleFont = UIFont.systemFont(ofSize: 11, weight: .semibold)
    private static let metaFont = UIFont.systemFont(ofSize: 9.5)
    private static let bodyFont = UIFont.systemFont(ofSize: 10)

    static func render(_ content: Content) -> Data? {
        let name = content.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty || !content.roles.isEmpty else { return nil }

        let doc = NSMutableAttributedString()

        doc.append(line(name, font: nameFont, spacingAfter: 2))
        if !content.contactLine.isEmpty {
            doc.append(line(content.contactLine, font: contactFont, spacingAfter: 12))
        }

        if let summary = content.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            doc.append(section("SUMMARY"))
            doc.append(line(summary, font: bodyFont, spacingAfter: 12))
        }

        if !content.roles.isEmpty {
            doc.append(section("EXPERIENCE"))
            for role in content.roles {
                let heading = [role.title, role.company]
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
                doc.append(line(heading, font: roleFont, spacingAfter: 0))
                if !role.dates.isEmpty {
                    doc.append(line(role.dates, font: metaFont, spacingAfter: 3))
                }
                for bullet in role.bullets where !bullet.trimmingCharacters(in: .whitespaces).isEmpty {
                    doc.append(bulletLine(bullet))
                }
                doc.append(spacer(8))
            }
            doc.append(spacer(4))
        }

        if !content.education.isEmpty {
            doc.append(section("EDUCATION"))
            for school in content.education {
                let heading = [school.degree, school.school]
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
                doc.append(line(heading, font: roleFont, spacingAfter: 0))
                if !school.year.isEmpty {
                    doc.append(line(school.year, font: metaFont, spacingAfter: 6))
                } else {
                    doc.append(spacer(6))
                }
            }
            doc.append(spacer(4))
        }

        if !content.skills.isEmpty {
            doc.append(section("SKILLS"))
            // A comma-joined line, not chips or columns: every ATS reads this
            // correctly and nothing about a grid survives text extraction.
            doc.append(line(content.skills.joined(separator: ", "),
                            font: bodyFont, spacingAfter: 0))
        }

        return paginate(doc)
    }

    // MARK: - Building blocks

    private static func paragraphStyle(
        spacingAfter: CGFloat,
        headIndent: CGFloat = 0,
        firstLineIndent: CGFloat = 0
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 1.5
        style.paragraphSpacing = spacingAfter
        style.headIndent = headIndent
        style.firstLineHeadIndent = firstLineIndent
        return style
    }

    private static func line(
        _ text: String,
        font: UIFont,
        spacingAfter: CGFloat
    ) -> NSAttributedString {
        NSAttributedString(string: text + "\n", attributes: [
            .font: font,
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraphStyle(spacingAfter: spacingAfter)
        ])
    }

    private static func section(_ title: String) -> NSAttributedString {
        NSAttributedString(string: title + "\n", attributes: [
            .font: sectionFont,
            .foregroundColor: UIColor.black,
            .kern: 1.2,
            .paragraphStyle: paragraphStyle(spacingAfter: 4)
        ])
    }

    /// A literal "• " prefix rather than an NSTextList. Text lists render as
    /// list markup that some extractors drop entirely, taking the bullet's
    /// text with it; a bullet character is just text and always survives.
    private static func bulletLine(_ text: String) -> NSAttributedString {
        NSAttributedString(string: "• " + text + "\n", attributes: [
            .font: bodyFont,
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraphStyle(spacingAfter: 2, headIndent: 11)
        ])
    }

    private static func spacer(_ height: CGFloat) -> NSAttributedString {
        NSAttributedString(string: "\n", attributes: [
            .font: UIFont.systemFont(ofSize: height / 2),
            .paragraphStyle: paragraphStyle(spacingAfter: 0)
        ])
    }

    // MARK: - Pagination

    private static func paginate(_ doc: NSAttributedString) -> Data? {
        let bounds = CGRect(
            x: margin,
            y: margin,
            width: pageSize.width - margin * 2,
            height: pageSize.height - margin * 2
        )
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        return renderer.pdfData { context in
            let framesetter = CTFramesetterCreateWithAttributedString(doc)
            var consumed = 0
            let total = doc.length

            repeat {
                context.beginPage()
                let path = CGPath(rect: bounds, transform: nil)
                let frame = CTFramesetterCreateFrame(
                    framesetter, CFRangeMake(consumed, 0), path, nil
                )
                guard let cg = UIGraphicsGetCurrentContext() else { return }
                // CoreText's origin is bottom-left; flip so text lands upright.
                cg.saveGState()
                cg.translateBy(x: 0, y: pageSize.height)
                cg.scaleBy(x: 1, y: -1)
                CTFrameDraw(frame, cg)
                cg.restoreGState()

                let visible = CTFrameGetVisibleStringRange(frame)
                // A page fitting nothing would loop forever.
                if visible.length <= 0 { return }
                consumed += visible.length
            } while consumed < total
        }
    }

    // MARK: - Naming

    /// Recruiters see this in a folder of hundreds, and some uploaders reject
    /// spaces and punctuation outright.
    static func fileName(candidateName: String?, companyName: String?) -> String {
        let parts = [candidateName, companyName, "Resume"]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let safe = parts
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined()
            .replacingOccurrences(of: " ", with: "_")
        return (safe.isEmpty ? "Resume" : safe) + ".pdf"
    }
}

// MARK: - Mapping

extension ResumePDF.Content {
    /// A tailored version. Bullets render as `tailored`, which already has any
    /// override the candidate made applied server-side.
    init(
        tailored: TailoredResumeContent,
        fullName: String,
        contactLine: String,
        education: [ParsedResumeDetails.Education]
    ) {
        self.fullName = fullName
        self.contactLine = contactLine
        self.summary = tailored.summary
        self.roles = tailored.employment.map { role in
            ResumePDF.Content.Role(
                company: role.company,
                title: role.title,
                dates: role.dates ?? "",
                bullets: role.bullets.map(\.tailored)
            )
        }
        // Education is not tailored — degrees and dates are facts, and the
        // model is forbidden from touching them — so it comes from the base
        // resume rather than round-tripping through the rewrite.
        self.education = education.map {
            ResumePDF.Content.School(
                school: $0.school ?? "",
                degree: $0.degree ?? "",
                year: $0.graduationYear ?? ""
            )
        }
        self.skills = tailored.skillsOrdered ?? []
    }

    /// The base resume, untailored. Same renderer, so a candidate can export
    /// what they uploaded without a job attached.
    init(parsed: ParsedResumeDetails, fullName: String, contactLine: String) {
        self.fullName = fullName
        self.contactLine = contactLine
        self.summary = nil
        self.roles = parsed.employers.map { employer in
            ResumePDF.Content.Role(
                company: employer.company ?? "",
                title: employer.title ?? "",
                dates: [employer.startDate, employer.isCurrent == true ? "Present" : employer.endDate]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: " – "),
                bullets: employer.bullets
            )
        }
        self.education = parsed.education.map {
            ResumePDF.Content.School(
                school: $0.school ?? "",
                degree: $0.degree ?? "",
                year: $0.graduationYear ?? ""
            )
        }
        self.skills = parsed.skills
    }
}
