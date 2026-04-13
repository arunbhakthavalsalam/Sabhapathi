import Foundation

struct LyricsLine: Identifiable, Codable {
    let id: UUID
    var timestamp: TimeInterval
    var text: String

    init(timestamp: TimeInterval, text: String) {
        self.id = UUID()
        self.timestamp = timestamp
        self.text = text
    }

    var formattedTimestamp: String {
        let minutes = Int(timestamp) / 60
        let seconds = timestamp.truncatingRemainder(dividingBy: 60)
        return String(format: "[%02d:%05.2f]", minutes, seconds)
    }
}
