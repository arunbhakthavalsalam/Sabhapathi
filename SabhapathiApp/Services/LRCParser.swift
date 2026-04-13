import Foundation

/// Parses LRC format lyrics into LyricsLine array.
enum LRCParser {
    /// Parse LRC content string into sorted LyricsLine array.
    static func parse(_ content: String) -> [LyricsLine] {
        let pattern = #"\[(\d{2}):(\d{2}(?:\.\d{1,3})?)\](.*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        var lines: [LyricsLine] = []

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            guard let match = regex.firstMatch(in: trimmed, range: range) else { continue }

            guard let minutesRange = Range(match.range(at: 1), in: trimmed),
                  let secondsRange = Range(match.range(at: 2), in: trimmed),
                  let textRange = Range(match.range(at: 3), in: trimmed) else { continue }

            let minutes = Double(trimmed[minutesRange]) ?? 0
            let seconds = Double(trimmed[secondsRange]) ?? 0
            let text = String(trimmed[textRange]).trimmingCharacters(in: .whitespaces)

            guard !text.isEmpty else { continue }

            let timestamp = minutes * 60 + seconds
            lines.append(LyricsLine(timestamp: timestamp, text: text))
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
