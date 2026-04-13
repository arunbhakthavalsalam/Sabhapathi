import Foundation

struct KaraokeProject: Identifiable, Codable {
    let id: UUID
    var song: Song
    var stemSet: StemSet?
    var lyrics: [LyricsLine]
    var chorusSections: [ChorusSection]
    var processingStatus: ProcessingStatus
    var failureReason: String?
    var dateCreated: Date
    var dateModified: Date

    init(song: Song) {
        self.id = UUID()
        self.song = song
        self.stemSet = nil
        self.lyrics = []
        self.chorusSections = []
        self.processingStatus = .imported
        self.failureReason = nil
        self.dateCreated = Date()
        self.dateModified = Date()
    }

    var projectDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("Sabhapathi")
            .appendingPathComponent("projects")
            .appendingPathComponent(id.uuidString)
    }
}

enum ProcessingStatus: String, Codable {
    case imported
    case downloading
    case separating
    case completed
    case failed
}

struct ChorusSection: Identifiable, Codable {
    let id: UUID
    var startTime: TimeInterval
    var endTime: TimeInterval
    var label: String

    init(startTime: TimeInterval, endTime: TimeInterval, label: String = "Chorus") {
        self.id = UUID()
        self.startTime = startTime
        self.endTime = endTime
        self.label = label
    }
}
