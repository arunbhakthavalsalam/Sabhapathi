import Foundation
import Combine
import os.log

/// Manages karaoke projects on disk.
final class ProjectManager: ObservableObject {
    static let shared = ProjectManager()
    private static let log = Logger(subsystem: "com.sabhapathi.karaoke", category: "ProjectManager")

    @Published var projects: [KaraokeProject] = []

    /// In-memory map from project id to active V1 FastAPI download job id.
    /// Not persisted — backend job state is in-memory only.
    var downloadJobs: [UUID: String] = [:]

    /// V2: live state for native (in-process) YouTube downloads. ProcessingView
    /// observes this map directly instead of polling an HTTP endpoint.
    @Published var downloadStates: [UUID: DownloadState] = [:]

    /// V2: live state for native separation. Survives view teardown so progress
    /// persists when the user navigates away and returns.
    @Published var separationStates: [UUID: SeparationState] = [:]

    private let nativeDownloadService: DownloadService = NativeDownloadService()
    private let nativeSeparationService: SeparationService = NativeSeparationService()

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

    /// Import a local audio file into a new project. Preserves the source
    /// extension so `original.<ext>` retains its original codec — demucs/ffmpeg
    /// can decode all the formats ImportView accepts without a re-encode pass.
    ///
    /// Returns nil if the file couldn't be copied; the project isn't created.
    @discardableResult
    func importAudio(from sourceURL: URL) -> KaraokeProject? {
        let title = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension.lowercased().isEmpty
            ? "mp3"
            : sourceURL.pathExtension.lowercased()
        let song = Song(
            title: title,
            originalFilePath: sourceURL.path,
            sourceType: .localFile
        )
        var project = KaraokeProject(song: song)

        let projectDir = project.projectDirectory
        do {
            try FileManager.default.createDirectory(
                at: projectDir, withIntermediateDirectories: true
            )
        } catch {
            Self.log.error("Failed to create project dir: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let destURL = projectDir.appendingPathComponent("original.\(ext)")
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        } catch {
            Self.log.error("Failed to copy \(sourceURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: projectDir)
            return nil
        }
        project.song.originalFilePath = destURL.path

        projects.append(project)
        saveProjects()
        return project
    }

    /// Back-compat shim for any caller that still hits the old name.
    @discardableResult
    func importMP3(from sourceURL: URL) -> KaraokeProject? {
        importAudio(from: sourceURL)
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

    /// V2: kick off a native YouTube download for an already-created project.
    /// Progress flows into `downloadStates[project.id]`; on completion the project's
    /// original file path + title are updated and the state is marked completed.
    func startNativeDownload(urlString: String, project: KaraokeProject) {
        guard let url = URL(string: urlString) else {
            var state = DownloadState()
            state.status = .failed
            state.message = "Invalid URL"
            downloadStates[project.id] = state
            return
        }

        downloadStates[project.id] = DownloadState()

        let projectId = project.id
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.nativeDownloadService.download(
                    url: url,
                    projectId: projectId.uuidString,
                    onProgress: { pct, msg in
                        Task { @MainActor in
                            var state = self.downloadStates[projectId] ?? DownloadState()
                            state.progress = pct
                            state.message = msg
                            self.downloadStates[projectId] = state
                        }
                    }
                )
                await MainActor.run {
                    if var p = self.projects.first(where: { $0.id == projectId }) {
                        p.song.originalFilePath = result.outputPath
                        p.song.title = result.title
                        p.processingStatus = .imported
                        self.updateProject(p)
                    }
                    var state = self.downloadStates[projectId] ?? DownloadState()
                    state.status = .completed
                    state.progress = 1.0
                    state.message = "Downloaded."
                    state.title = result.title
                    state.outputPath = result.outputPath
                    self.downloadStates[projectId] = state
                }
            } catch {
                await MainActor.run {
                    if var p = self.projects.first(where: { $0.id == projectId }) {
                        p.processingStatus = .failed
                        p.failureReason = error.localizedDescription
                        self.updateProject(p)
                    }
                    var state = self.downloadStates[projectId] ?? DownloadState()
                    state.status = .failed
                    state.message = error.localizedDescription
                    self.downloadStates[projectId] = state
                }
            }
        }
    }

    /// V2: kick off a native separation run. Progress flows into
    /// `separationStates[project.id]` so the UI survives navigation.
    func startNativeSeparation(project: KaraokeProject) {
        separationStates[project.id] = SeparationState()

        var updated = project
        updated.processingStatus = .separating
        updated.failureReason = nil
        updateProject(updated)

        let projectId = project.id
        let inputPath = project.song.originalFilePath

        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.nativeSeparationService.separate(
                    inputPath: inputPath,
                    projectId: projectId.uuidString,
                    onProgress: { pct, msg in
                        Task { @MainActor in
                            var state = self.separationStates[projectId] ?? SeparationState()
                            state.progress = pct
                            state.message = msg
                            self.separationStates[projectId] = state
                        }
                    }
                )
                await MainActor.run {
                    if var p = self.projects.first(where: { $0.id == projectId }) {
                        var stemSet = StemSet()
                        if let path = result.stems["vocals"] { stemSet.vocals = URL(fileURLWithPath: path) }
                        if let path = result.stems["drums"] { stemSet.drums = URL(fileURLWithPath: path) }
                        if let path = result.stems["bass"] { stemSet.bass = URL(fileURLWithPath: path) }
                        if let path = result.stems["other"] { stemSet.other = URL(fileURLWithPath: path) }
                        if let path = result.stems["karaoke"] { stemSet.karaoke = URL(fileURLWithPath: path) }
                        p.stemSet = stemSet
                        p.processingStatus = .completed
                        self.updateProject(p)
                    }
                    var state = self.separationStates[projectId] ?? SeparationState()
                    state.status = .completed
                    state.progress = 1.0
                    state.message = "Complete."
                    self.separationStates[projectId] = state
                }
            } catch {
                await MainActor.run {
                    if var p = self.projects.first(where: { $0.id == projectId }) {
                        p.processingStatus = .failed
                        p.failureReason = error.localizedDescription
                        self.updateProject(p)
                    }
                    var state = self.separationStates[projectId] ?? SeparationState()
                    state.status = .failed
                    state.message = error.localizedDescription
                    self.separationStates[projectId] = state
                }
            }
        }
    }

    func deleteProject(_ project: KaraokeProject) {
        projects.removeAll { $0.id == project.id }
        try? FileManager.default.removeItem(at: project.projectDirectory)
        saveProjects()
    }

    private func loadProjects() {
        guard FileManager.default.fileExists(atPath: manifestFile.path) else { return }
        do {
            let data = try Data(contentsOf: manifestFile)
            projects = try JSONDecoder().decode([KaraokeProject].self, from: data)
        } catch {
            Self.log.error("Failed to load projects manifest: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func saveProjects() {
        do {
            let data = try JSONEncoder().encode(projects)
            try data.write(to: manifestFile, options: .atomic)
        } catch {
            Self.log.error("Failed to save projects manifest: \(error.localizedDescription, privacy: .public)")
        }
    }
}
