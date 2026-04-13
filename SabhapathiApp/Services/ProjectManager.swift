import Foundation
import Combine

/// Manages karaoke projects on disk.
final class ProjectManager: ObservableObject {
    static let shared = ProjectManager()

    @Published var projects: [KaraokeProject] = []

    /// In-memory map from project id to active YouTube download job id.
    /// Not persisted — backend job state is in-memory only.
    var downloadJobs: [UUID: String] = [:]

    private let baseDirectory: URL
    private let manifestFile: URL

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        baseDirectory = appSupport
            .appendingPathComponent("Sabhapathi")
            .appendingPathComponent("projects")
        manifestFile = appSupport
            .appendingPathComponent("Sabhapathi")
            .appendingPathComponent("projects.json")

        try? FileManager.default.createDirectory(
            at: baseDirectory, withIntermediateDirectories: true
        )

        loadProjects()
    }

    func importMP3(from sourceURL: URL) -> KaraokeProject {
        let title = sourceURL.deletingPathExtension().lastPathComponent
        let song = Song(
            title: title,
            originalFilePath: sourceURL.path,
            sourceType: .localFile
        )
        var project = KaraokeProject(song: song)

        // Copy file to project directory
        let projectDir = project.projectDirectory
        try? FileManager.default.createDirectory(
            at: projectDir, withIntermediateDirectories: true
        )

        let destURL = projectDir.appendingPathComponent("original.mp3")
        try? FileManager.default.copyItem(at: sourceURL, to: destURL)
        project.song.originalFilePath = destURL.path

        projects.append(project)
        saveProjects()
        return project
    }

    func createProjectForYouTube(url: String) -> KaraokeProject {
        let song = Song(
            title: "Downloading...",
            originalFilePath: "",
            sourceType: .youtube
        )
        var project = KaraokeProject(song: song)
        project.processingStatus = .downloading

        let projectDir = project.projectDirectory
        try? FileManager.default.createDirectory(
            at: projectDir, withIntermediateDirectories: true
        )

        projects.append(project)
        saveProjects()
        return project
    }

    func updateProject(_ project: KaraokeProject) {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
            projects[index].dateModified = Date()
            saveProjects()
        }
    }

    func deleteProject(_ project: KaraokeProject) {
        projects.removeAll { $0.id == project.id }
        try? FileManager.default.removeItem(at: project.projectDirectory)
        saveProjects()
    }

    private func loadProjects() {
        guard FileManager.default.fileExists(atPath: manifestFile.path),
              let data = try? Data(contentsOf: manifestFile) else { return }
        projects = (try? JSONDecoder().decode([KaraokeProject].self, from: data)) ?? []
    }

    private func saveProjects() {
        let data = try? JSONEncoder().encode(projects)
        try? data?.write(to: manifestFile, options: .atomic)
    }
}
