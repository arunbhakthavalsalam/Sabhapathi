import SwiftUI

struct ContentView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @EnvironmentObject var backendManager: PythonBackendManager
    @State private var selectedProject: KaraokeProject?
    @State private var showingImport = false

    var body: some View {
        NavigationSplitView {
            LibraryView(selectedProject: $selectedProject)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            if let project = selectedProject {
                detailView(for: project)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Select a song or import one")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Button("Import MP3") {
                        showingImport = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showingImport) {
            ImportView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .importMP3)) { _ in
            showingImport = true
        }
        .overlay(alignment: .bottomTrailing) {
            backendStatusBadge
                .padding()
        }
    }

    @ViewBuilder
    private func detailView(for project: KaraokeProject) -> some View {
        switch project.processingStatus {
        case .imported:
            ProcessingView(project: binding(for: project))
        case .downloading, .separating:
            ProcessingView(project: binding(for: project))
        case .completed:
            KaraokePlayerView(project: project)
                .id(project.id)
        case .failed:
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36))
                    .foregroundColor(.red)
                Text("Processing failed")
                    .font(.title3)
                if let failureReason = project.failureReason, !failureReason.isEmpty {
                    Text(failureReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                }
                if let backendError = backendManager.lastError, !backendError.isEmpty {
                    Text(backendError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                }
                Button("Retry") {
                    backendManager.stop()
                    backendManager.start()
                    var p = project
                    p.processingStatus = .imported
                    p.failureReason = nil
                    projectManager.updateProject(p)
                }
            }
        }
    }

    private func binding(for project: KaraokeProject) -> Binding<KaraokeProject> {
        Binding(
            get: {
                projectManager.projects.first { $0.id == project.id } ?? project
            },
            set: { newValue in
                projectManager.updateProject(newValue)
                if selectedProject?.id == newValue.id {
                    selectedProject = newValue
                }
            }
        )
    }

    private var backendStatusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(backendStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var statusColor: Color {
        if AppFlags.allServicesNative { return .green }
        return backendManager.isRunning ? .green : .red
    }

    private var backendStatusText: String {
        if AppFlags.allServicesNative {
            return "Native (no backend)"
        }

        if backendManager.isRunning {
            return "Backend Ready"
        }

        if backendManager.lastError != nil {
            return "Backend Error"
        }

        return "Backend Starting..."
    }
}
