import Foundation

struct Song: Identifiable, Codable {
    let id: UUID
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var originalFilePath: String
    var sourceType: SourceType

    init(
        title: String,
        artist: String = "",
        album: String = "",
        duration: TimeInterval = 0,
        originalFilePath: String,
        sourceType: SourceType = .localFile
    ) {
        self.id = UUID()
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.originalFilePath = originalFilePath
        self.sourceType = sourceType
    }
}

enum SourceType: String, Codable {
    case localFile
    case youtube
}
