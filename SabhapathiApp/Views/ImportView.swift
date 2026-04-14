import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @Environment(\.dismiss) private var dismiss
    @State private var youtubeURL = ""
    @State private var isDroppingFile = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Text("Import Song")
                .font(.title2.bold())

            // Drag & drop area
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isDroppingFile ? Color.accentColor : Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: 2, dash: [8])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isDroppingFile ? Color.accentColor.opacity(0.05) : Color.clear)
                    )
                    .frame(height: 160)

                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("Drop MP3 file here")
                        .font(.headline)
                    Text("or")
                        .foregroundStyle(.tertiary)
                    Button("Choose File...") {
                        openFilePicker()
                    }
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isDroppingFile) { providers in
                handleDrop(providers: providers)
            }

            Divider()

            // YouTube URL input
            VStack(alignment: .leading, spacing: 8) {
                Text("Or paste a YouTube URL")
                    .font(.headline)
                HStack {
                    TextField("https://youtube.com/watch?v=...", text: $youtubeURL)
                        .textFieldStyle(.roundedBorder)
                    Button("Download") {
                        importFromYouTube()
                    }
                    .disabled(youtubeURL.isEmpty)
                    .buttonStyle(.borderedProminent)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 500, height: 400)
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.mp3, UTType.audio]
        panel.allowsMultipleSelection = true

        if panel.runModal() == .OK {
            for url in panel.urls {
                _ = projectManager.importMP3(from: url)
            }
            dismiss()
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

                if url.pathExtension.lowercased() == "mp3" {
                    DispatchQueue.main.async {
                        _ = projectManager.importMP3(from: url)
                        dismiss()
                    }
                } else {
                    DispatchQueue.main.async {
                        errorMessage = "Only MP3 files are supported"
                    }
                }
            }
        }
        return true
    }

    private func importFromYouTube() {
        guard !youtubeURL.isEmpty else { return }
        let project = projectManager.createProjectForYouTube(url: youtubeURL)
        let url = youtubeURL

        if AppFlags.useNativeDownload {
            projectManager.startNativeDownload(urlString: url, project: project)
            dismiss()
            return
        }

        Task {
            do {
                let response = try await BackendAPIClient.shared.startDownload(
                    url: url, projectId: project.id.uuidString
                )
                await MainActor.run {
                    projectManager.downloadJobs[project.id] = response.jobId
                }
            } catch {
                await MainActor.run {
                    var failed = project
                    failed.processingStatus = .failed
                    failed.failureReason = "Download failed: \(error.localizedDescription)"
                    projectManager.updateProject(failed)
                    errorMessage = "Download failed: \(error.localizedDescription)"
                }
            }
        }

        dismiss()
    }
}
