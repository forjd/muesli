import Foundation

struct TranscriptExporter {
    static func data(for session: TranscriptSession, format: TranscriptExportFormat) throws -> Data {
        switch format {
        case .text:
            return Data(session.displayTranscript.utf8)
        case .markdown:
            return Data(markdownText(for: session).utf8)
        case .docx:
            return try DOCXWriter.documentData(title: title(for: session), body: session.displayTranscript)
        case .json:
            let payload = TranscriptExportPayload(
                id: session.id,
                createdAt: session.createdAt,
                audioPath: session.audioURL.path,
                model: session.model.rawValue,
                transcript: session.displayTranscript,
                liveTranscript: session.liveTranscript,
                finalTranscript: session.finalTranscript,
                segments: session.segments,
                duration: session.duration,
                fileSize: session.fileSize
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(payload)
        case .srt:
            return Data(srtText(for: session).utf8)
        }
    }

    static func clipboardText(for session: TranscriptSession, template: TranscriptClipboardTemplate) -> String {
        switch template {
        case .plain:
            session.displayTranscript
        case .markdown:
            markdownText(for: session)
        case .notes:
            [
                "# \(title(for: session))",
                "",
                "## Summary",
                "",
                "## Transcript",
                "",
                session.displayTranscript
            ].joined(separator: "\n")
        }
    }

    static func markdownText(for session: TranscriptSession) -> String {
        [
            "# \(title(for: session))",
            "",
            "- Created: \(Self.isoDateFormatter.string(from: session.createdAt))",
            "- Model: \(session.model.label)",
            session.duration.map { "- Duration: \(formatDuration($0))" },
            session.fileSize.map { "- Audio size: \(ByteCountFormatter.string(fromByteCount: $0, countStyle: .file))" },
            "",
            "## Transcript",
            "",
            session.displayTranscript
        ]
        .compactMap(\.self)
        .joined(separator: "\n")
    }

    static func srtText(for session: TranscriptSession) -> String {
        let segments = session.segments
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.startTime < $1.startTime }

        if segments.isEmpty {
            return "1\n00:00:00,000 --> 00:00:05,000\n\(session.displayTranscript)\n"
        }

        return segments.enumerated().map { index, segment in
            [
                "\(index + 1)",
                "\(formatSRTTime(segment.startTime)) --> \(formatSRTTime(max(segment.endTime, segment.startTime + 1)))",
                segment.text,
                ""
            ].joined(separator: "\n")
        }.joined(separator: "\n")
    }

    static func formatSRTTime(_ time: TimeInterval) -> String {
        let milliseconds = Int((time * 1000).rounded())
        let hours = milliseconds / 3_600_000
        let minutes = (milliseconds % 3_600_000) / 60_000
        let seconds = (milliseconds % 60_000) / 1000
        let millis = milliseconds % 1000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, millis)
    }

    private static func title(for session: TranscriptSession) -> String {
        "Muesli Transcript \(Self.filenameDateFormatter.string(from: session.createdAt))"
    }

    private static func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private static let isoDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

private struct TranscriptExportPayload: Encodable {
    let id: UUID
    let createdAt: Date
    let audioPath: String
    let model: String
    let transcript: String
    let liveTranscript: String
    let finalTranscript: String
    let segments: [TranscriptSegment]
    let duration: TimeInterval?
    let fileSize: Int64?
}

private enum DOCXWriter {
    static func documentData(title: String, body: String) throws -> Data {
        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>\(paragraphXML(title, style: "Title"))\(body.components(separatedBy: .newlines).map { paragraphXML($0) }.joined())<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr></w:body></w:document>
        """

        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>
        """

        let relationships = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
        """

        let styles = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:rPr><w:b/><w:sz w:val="32"/></w:rPr></w:style></w:styles>
        """

        return try ZipStoreWriter.write([
            ZipStoreFile(path: "[Content_Types].xml", data: Data(contentTypes.utf8)),
            ZipStoreFile(path: "_rels/.rels", data: Data(relationships.utf8)),
            ZipStoreFile(path: "word/document.xml", data: Data(documentXML.utf8)),
            ZipStoreFile(path: "word/styles.xml", data: Data(styles.utf8))
        ])
    }

    private static func paragraphXML(_ text: String, style: String? = nil) -> String {
        let styleXML = style.map { "<w:pPr><w:pStyle w:val=\"\($0)\"/></w:pPr>" } ?? ""
        return "<w:p>\(styleXML)<w:r><w:t xml:space=\"preserve\">\(escapeXML(text))</w:t></w:r></w:p>"
    }

    private static func escapeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private struct ZipStoreFile {
    let path: String
    let data: Data
}

private enum ZipStoreWriter {
    static func write(_ files: [ZipStoreFile]) throws -> Data {
        var output = Data()
        var centralDirectory = Data()

        for file in files {
            let localOffset = UInt32(output.count)
            let pathData = Data(file.path.utf8)
            let crc = crc32(file.data)
            output.appendLittleEndian(UInt32(0x04034b50))
            output.appendLittleEndian(UInt16(20))
            output.appendLittleEndian(UInt16(0))
            output.appendLittleEndian(UInt16(0))
            output.appendLittleEndian(UInt16(0))
            output.appendLittleEndian(UInt16(0))
            output.appendLittleEndian(crc)
            output.appendLittleEndian(UInt32(file.data.count))
            output.appendLittleEndian(UInt32(file.data.count))
            output.appendLittleEndian(UInt16(pathData.count))
            output.appendLittleEndian(UInt16(0))
            output.append(pathData)
            output.append(file.data)

            centralDirectory.appendLittleEndian(UInt32(0x02014b50))
            centralDirectory.appendLittleEndian(UInt16(20))
            centralDirectory.appendLittleEndian(UInt16(20))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(crc)
            centralDirectory.appendLittleEndian(UInt32(file.data.count))
            centralDirectory.appendLittleEndian(UInt32(file.data.count))
            centralDirectory.appendLittleEndian(UInt16(pathData.count))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt32(0))
            centralDirectory.appendLittleEndian(localOffset)
            centralDirectory.append(pathData)
        }

        let centralOffset = UInt32(output.count)
        output.append(centralDirectory)
        output.appendLittleEndian(UInt32(0x06054b50))
        output.appendLittleEndian(UInt16(0))
        output.appendLittleEndian(UInt16(0))
        output.appendLittleEndian(UInt16(files.count))
        output.appendLittleEndian(UInt16(files.count))
        output.appendLittleEndian(UInt32(centralDirectory.count))
        output.appendLittleEndian(centralOffset)
        output.appendLittleEndian(UInt16(0))
        return output
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xedb8_8320 : crc >> 1
            }
        }
        return crc ^ 0xffff_ffff
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
