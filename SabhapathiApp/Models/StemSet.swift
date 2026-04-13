import Foundation

struct StemSet: Codable {
    var vocals: URL?
    var drums: URL?
    var bass: URL?
    var other: URL?
    var karaoke: URL?

    var allStems: [(name: String, url: URL)] {
        var result: [(String, URL)] = []
        if let vocals { result.append(("Vocals", vocals)) }
        if let drums { result.append(("Drums", drums)) }
        if let bass { result.append(("Bass", bass)) }
        if let other { result.append(("Other", other)) }
        if let karaoke { result.append(("Karaoke", karaoke)) }
        return result
    }
}
