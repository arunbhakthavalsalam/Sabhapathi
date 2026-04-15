import Foundation

/// Parses LRC format lyrics into LyricsLine array.
enum LRCParser {
    /// Matches one `[mm:ss(.xxx)]` timestamp. LRC allows multiple timestamps
    /// on a single lyric line to share the same text across several points in
    /// the song (e.g. `[00:12.00][01:24.00]Refrain`). We extract all of them.
    private static let timestampRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2}(?:[\.:]\d{1,3})?)\]"#)
    }()

    /// Parse LRC content string into a sorted `[LyricsLine]` array.
    ///
    /// Tolerates:
    ///   - leading UTF-8 BOM
    ///   - metadata tags like `[ti:Title]`, `[ar:Artist]` (skipped)
    ///   - multi-timestamp lines (each timestamp emits its own line)
    ///   - both `.` and `:` as the sub-second separator
    static func parse(_ content: String) -> [LyricsLine] {
        var text = content
        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }

        var lines: [LyricsLine] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let ns = trimmed as NSString
            let fullRange = NSRange(location: 0, length: ns.length)
            let matches = timestampRegex.matches(in: trimmed, range: fullRange)
            guard !matches.isEmpty else { continue }

            // Text is everything after the last timestamp.
            guard let last = matches.last else { continue }
            let textStart = last.range.location + last.range.length
            guard textStart <= ns.length else { continue }
            let lyricText = ns
                .substring(from: textStart)
                .trimmingCharacters(in: .whitespaces)
            guard !lyricText.isEmpty else { continue }

            for match in matches where match.numberOfRanges >= 3 {
                guard let minRange = Range(match.range(at: 1), in: trimmed),
                      let secRange = Range(match.range(at: 2), in: trimmed) else { continue }

                let minutes = Double(trimmed[minRange]) ?? 0
                // Normalize `:` to `.` for sub-seconds.
                let secondsStr = trimmed[secRange].replacingOccurrences(of: ":", with: ".")
                let seconds = Double(secondsStr) ?? 0

                let timestamp = minutes * 60 + seconds
                lines.append(LyricsLine(timestamp: timestamp, text: lyricText))
            }
        }

        return lines.sorted { $0.timestamp < $1.timestamp }
    }

    /// Generate LRC string from LyricsLine array.
    static func generate(from lines: [LyricsLine]) -> String {
        lines.map { line in
            let minutes = Int(line.timestamp) / 60
            let seconds = line.timestamp.truncatingRemainder(dividingBy: 60)
            return String(format: "[%02d:%05.2f]%@", minutes, seconds, line.text)
        }.joined(separator: "\n")
    }
}
