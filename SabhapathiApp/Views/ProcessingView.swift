import SwiftUI

struct ProcessingView: View {
    @Binding var project: KaraokeProject
    @EnvironmentObject var projectManager: ProjectManager
    @EnvironmentObject var backendManager: PythonBackendManager
    @State private var progress: Double = 0
    @State private var statusMessage = "Preparing..."
    @State private var jobId: String?
    @State private var isProcessing = false

    private let api = BackendAPIClient.shared

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: statusIcon)
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .opacity(isProcessing ? 0.6 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isProcessing)

            Text(project.song.title)
                .font(.title2.bold())

            VStack(spacing: 8) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 400)

                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(Int(progress * 100))%")
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if !isProcessing && project.processingStatus == .imported {
                Button("Start Processing") {
                    startSeparation()
                }
                .disabled(!backendManager.isRunning)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if !backendManager.isRunning {
                    Text("Waiting for backend to start...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if project.processingStatus == .downloading {
                // Already downloading from YouTube import
                await pollDownloadThenSeparate()
            }
        }
    }

    private var statusIcon: String {
        switch project.processingStatus {
        case .imported: return "waveform.badge.plus"
        case .downloading: return "arrow.down.circle"
        case .separating: return "waveform"
        case .completed: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private func startSeparation() {
        isProcessing = true
        project.processingStatus = .separating
        project.failureReason = nil
        projectManager.updateProject(project)

        Task {
            do {
                let response = try await api.startSeparation(
                    inputPath: project.song.originalFilePath,
                    projectId: project.id.uuidString
                )
                jobId = response.jobId
                await pollSeparationStatus()
            } catch {
                await MainActor.run {
                    statusMessage = "Error: \(error.localizedDescription)"
                    project.processingStatus = .failed
                    project.failureReason = error.localizedDescription
                    projectManager.updateProject(project)
                    isProcessing = false
                }
            }
        }
    }

    private func pollSeparationStatus() async {
        guard let jobId else { return }

        while true {
            try? await Task.sleep(nanoseconds: 500_000_000)
            do {
                let status = try await api.getJobStatus(jobId: jobId)
                await MainActor.run {
                    progress = status.progress
                    statusMessage = status.message
                }

                if status.status == "completed" {
                    await MainActor.run {
                        updateProjectWithStems(status.stems ?? [:], outputDir: status.outputDir ?? "")
                    }
                    return
                } else if status.status == "failed" {
                    await MainActor.run {
                        project.processingStatus = .failed
                        project.failureReason = status.message
                        projectManager.updateProject(project)
                        isProcessing = false
                    }
                    return
                }
            } catch {
                continue
            }
        }
    }

    private func pollDownloadThenSeparate() async {
        await MainActor.run {
            statusMessage = "Downloading from YouTube..."
            isProcessing = true
        }

        // Wait briefly for ImportView to register the jobId.
        var downloadJobId: String?
        for _ in 0..<20 {
            if let id = projectManager.downloadJobs[project.id] {
                downloadJobId = id
                break
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        guard let downloadJobId else {
            await MainActor.run {
                statusMessage = "Download did not start. Please re-import."
                project.processingStatus = .failed
                project.failureReason = "Download job was lost (backend may have restarted)."
                projectManager.updateProject(project)
                isProcessing = false
            }
            return
        }

        while true {
            try? await Task.sleep(nanoseconds: 500_000_000)
            do {
                let status = try await api.getDownloadStatus(jobId: downloadJobId)
                await MainActor.run {
                    progress = status.progress
                    statusMessage = status.message
                }

                if status.status == "completed" {
                    await MainActor.run {
                        if let path = status.outputPath {
                            project.song.originalFilePath = path
                        }
                        if let title = status.title, !title.isEmpty {
                            project.song.title = title
                        }
                        project.processingStatus = .imported
                        projectManager.updateProject(project)
                        projectManager.downloadJobs.removeValue(forKey: project.id)
                        startSeparation()
                    }
                    return
                } else if status.status == "failed" {
                    await MainActor.run {
                        project.processingStatus = .failed
                        project.failureReason = status.message
                        projectManager.updateProject(project)
                        projectManager.downloadJobs.removeValue(forKey: project.id)
                        isProcessing = false
                    }
                    return
                }
            } catch {
                continue
            }
        }
    }

    private func updateProjectWithStems(_ stems: [String: String], outputDir: String) {
        var stemSet = StemSet()
        if let path = stems["vocals"] { stemSet.vocals = URL(fileURLWithPath: path) }
        if let path = stems["drums"] { stemSet.drums = URL(fileURLWithPath: path) }
        if let path = stems["bass"] { stemSet.bass = URL(fileURLWithPath: path) }
        if let path = stems["other"] { stemSet.other = URL(fileURLWithPath: path) }
        if let path = stems["karaoke"] { stemSet.karaoke = URL(fileURLWithPath: path) }

        project.stemSet = stemSet
        project.processingStatus = .completed
        projectManager.updateProject(project)
        isProcessing = false
    }
}
