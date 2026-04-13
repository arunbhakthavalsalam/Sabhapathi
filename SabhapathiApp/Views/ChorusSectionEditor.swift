import SwiftUI

struct ChorusSectionEditor: View {
    @Binding var project: KaraokeProject
    @EnvironmentObject var projectManager: ProjectManager
    @StateObject private var audioEngine = AudioEngineService.shared
    @State private var markingStart: TimeInterval?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Chorus Sections")
                    .font(.headline)
                Spacer()
                Button("Auto-Detect") {
                    autoDetectChorus()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Manual marking controls
            HStack {
                if let start = markingStart {
                    Text("Marking from \(formatTime(start))...")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("End Section") {
                        let section = ChorusSection(
                            startTime: start,
                            endTime: audioEngine.currentTime
                        )
                        project.chorusSections.append(section)
                        projectManager.updateProject(project)
                        markingStart = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Cancel") {
                        markingStart = nil
                    }
                    .controlSize(.small)
                } else {
                    Button("Mark Chorus Start") {
                        markingStart = audioEngine.currentTime
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Divider()

            // List of chorus sections
            if project.chorusSections.isEmpty {
                Text("No chorus sections marked")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(project.chorusSections) { section in
                    HStack {
                        Image(systemName: "music.mic")
                            .foregroundStyle(.purple)

                        Text(section.label)
                            .font(.caption.bold())

                        Text("\(formatTime(section.startTime)) - \(formatTime(section.endTime))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            project.chorusSections.removeAll { $0.id == section.id }
                            projectManager.updateProject(project)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }
                }
            }
        }
        .padding()
    }

    private func autoDetectChorus() {
        // Use MFCC comparison to detect repeating sections
        // Calls the existing compare_mfcc.py logic via backend
        // For now, placeholder that can be connected to the Python backend
        Task {
            // TODO: Implement auto-detection via MFCC analysis endpoint
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
