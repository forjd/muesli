import AppKit
import CoreText
import Foundation

enum MeetingNotesPDFWriter {
    static func data(title: String, markdown: String) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 54
        let textRect = pageRect.insetBy(dx: margin, dy: margin)
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            return Data()
        }

        let attributed = attributedString(title: title, markdown: markdown)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
        var range = CFRange(location: 0, length: 0)

        while range.location < attributed.length {
            context.beginPDFPage([kCGPDFContextMediaBox as String: pageRect] as CFDictionary)
            context.saveGState()
            context.textMatrix = .identity
            context.translateBy(x: 0, y: pageRect.height)
            context.scaleBy(x: 1, y: -1)

            let path = CGMutablePath()
            path.addRect(textRect)
            let frame = CTFramesetterCreateFrame(framesetter, range, path, nil)
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            range.location += visible.length

            context.restoreGState()
            context.endPDFPage()

            if visible.length == 0 {
                break
            }
        }

        context.closePDF()
        return output as Data
    }

    private static func attributedString(title: String, markdown: String) -> NSAttributedString {
        let body = NSMutableAttributedString()
        let titleAttributes = attributes(font: .boldSystemFont(ofSize: 20), spacing: 10)
        body.append(NSAttributedString(string: "\(title)\n\n", attributes: titleAttributes))

        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let attributes: [NSAttributedString.Key: Any]
            let rendered: String
            if trimmed.hasPrefix("# ") {
                attributes = Self.attributes(font: .boldSystemFont(ofSize: 18), spacing: 8)
                rendered = String(trimmed.dropFirst(2))
            } else if trimmed.hasPrefix("## ") {
                attributes = Self.attributes(font: .boldSystemFont(ofSize: 14), spacing: 6)
                rendered = String(trimmed.dropFirst(3))
            } else {
                attributes = Self.attributes(font: .systemFont(ofSize: 11), spacing: 4)
                rendered = line
            }
            body.append(NSAttributedString(string: "\(rendered)\n", attributes: attributes))
        }

        return body
    }

    private static func attributes(font: NSFont, spacing: CGFloat) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = spacing
        paragraph.lineSpacing = 2
        return [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
    }
}
