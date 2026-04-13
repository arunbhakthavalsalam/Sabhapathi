import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @Binding var selectedProject: KaraokeProject?
    @State private var searchText = ""

    var filteredProjects: [KaraokeProject] {
        if searchText.isEmpty {
            return projectManager.projects
        }
        return projectManager.projects.filter {
            $0.song.title.localizedCaseInsensitiveContains(searchText) ||
            $0.song.artist.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: { selectedProject?.id },
            set: { id in
                selectedProject = projectManager.projects.first { $0.id == id }
            }
        )
    }

    var body: some View {
        List(filteredProjects, selection: selectionBinding) { project in
            LibraryRow(project: project)
                .tag(project.id)
                .contextMenu {
                    Button("Delete", role: .destructive) {
                        if selectedProject?.id == project.id {
                            selectedProject = nil
                        }
                        projectManager.deleteProject(project)
                    }
                }
        }
        .searchable(text: $searchText, prompt: "Search songs")
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    NotificationCenter.default.post(name: .importMP3, object: nil)
                } label: {
                    Label("Import", systemImage: "plus")
                }
            }
        }
        .overlay {
            if projectManager.projects.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No Songs Yet")
                        .font(.title3)
                    Text("Import an MP3 or paste a YouTube URL to get started.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct LibraryRow: View {
    let project: KaraokeProject

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.song.title)
                    .font(.body)
                    .lineLimit(1)

                if !project.song.artist.isEmpty {
                    Text(project.song.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            sourceIcon
        }
        .padding(.vertical, 2)
    }

    private var statusIcon: some View {
        Group {
            switch project.processingStatus {
            case .imported:
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            case .downloading, .separating:
                ProgressView()
                    .scaleEffect(0.6)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private var sourceIcon: some View {
        Group {
            switch project.song.sourceType {
            case .localFile:
                Image(systemName: "doc.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .youtube:
                Image(systemName: "play.rectangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.7))
            }
        }
    }
}
