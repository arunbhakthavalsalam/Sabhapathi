import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct KaraokePlayerView: View {
    let project: KaraokeProject
    @StateObject private var audioEngine = AudioEngineService.shared
    @StateObject private var stemMixer: StemMixer
    @StateObject private var lyricsService = LyricsService()
    @State private var showStemMixer = true
    @State private var showLyrics = true
    @State private var isExporting = false
    @State private var showExportAlert = false
    @State private var exportAlertTitle = ""
    @State private var exportAlertMessage = ""

    private let audioExporter = AudioExporter()

    init(project: KaraokeProject) {
        self.project = project
        _stemMixer = StateObject(wrappedValue: StemMixer())
    }

    var body: some View {
        VStack(spacing: 0) {
            // Song header
            HStack {
                VStack(alignment: .leading) {
                    Text(project.song.title)
                        .font(.title2.bold())
                    if !project.song.artist.isEmpty {
                        Text(project.song.artist)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()

                // View toggles
                HStack(spacing: 8) {
                    Button(isExporting ? "Saving..." : "Save Karaoke") {
                        saveKaraoke()
                    }
                    .disabled(isExporting)
                    .buttonStyle(.borderedProminent)

                    Toggle(isOn: $showLyrics) {
                        Label("Lyrics", systemImage: "text.quote")
                    }
                    .toggleStyle(.button)

                    Toggle(isOn: $showStemMixer) {
                        Label("Mixer", systemImage: "slider.horizontal.3")
                    }
                    .toggleStyle(.button)
                }
            }
            .padding()

            Divider()

            // Main content area
            HSplitView {
                // Lyrics display
                if showLyrics {
                    LyricsDisplayView(
                        lyrics: lyricsService.lyrics,
                        currentTime: audioEngine.currentTime
                    )
                    .frame(minWidth: 300)
                }

                // Stem mixer
                if showStemMixer {
                    StemMixerView(stemMixer: stemMixer)
                        .frame(width: 280)
                }
            }

            Divider()

            // Transport controls
            transportControls
                .padding()
        }
        .onAppear {
            loadAudio()
            fetchLyrics()
        }
        .onDisappear {
            audioEngine.stop()
        }
        .onChange(of: audioEngine.currentTime) { newTime in
            stemMixer.applyChorusMode(
                currentTime: newTime,
                chorusSections: project.chorusSections
            )
        }
        .alert(exportAlertTitle, isPresented: $showExportAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportAlertMessage)
        }
    }

    private var transportControls: some View {
        VStack(spacing: 8) {
            // Seek bar
            HStack {
                Text(formatTime(audioEngine.currentTime))
                    .font(.caption.monospacedDigit())
                    .frame(width: 50)

                Slider(
                    value: Binding(
                        get: { audioEngine.currentTime },
                        set: { audioEngine.seek(to: $0) }
                    ),
                    in: 0...max(audioEngine.duration, 1)
                )

                Text(formatTime(audioEngine.duration))
                    .font(.caption.monospacedDigit())
                    .frame(width: 50)
            }

            // Play/Pause controls
            HStack(spacing: 20) {
                Button {
                    audioEngine.seek(to: max(audioEngine.currentTime - 10, 0))
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.title2)
                }
                .buttonStyle(.plain)

                Button {
                    if audioEngine.isPlaying {
                        audioEngine.pause()
                    } else {
                        audioEngine.play()
                    }
                } label: {
                    Image(systemName: audioEngine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: [])

                Button {
                    audioEngine.seek(to: min(audioEngine.currentTime + 10, audioEngine.duration))
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.title2)
                }
                .buttonStyle(.plain)

                Spacer().frame(width: 40)

                // Quick presets
                Button("Karaoke") { stemMixer.resetToKaraoke() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button("Original") { stemMixer.resetToOriginal() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private func loadAudio() {
        guard let stemSet = project.stemSet else { return }
        try? audioEngine.loadStems(from: stemSet)
        stemMixer.resetToKaraoke()
    }

    private func fetchLyrics() {
        Task {
            _ = await lyricsService.fetchLyrics(for: project)
        }
    }

    private func saveKaraoke() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mp3]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = suggestedExportName

        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        isExporting = true

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try audioExporter.exportKaraokeMP3(project: project, outputURL: outputURL)
                DispatchQueue.main.async {
                    isExporting = false
                    exportAlertTitle = "Karaoke Saved"
                    exportAlertMessage = "Saved MP3 to \(outputURL.lastPathComponent)."
                    showExportAlert = true
                }
            } catch {
                DispatchQueue.main.async {
                    isExporting = false
                    exportAlertTitle = "Save Failed"
                    exportAlertMessage = error.localizedDescription
                    showExportAlert = true
                }
            }
        }
    }

    private var suggestedExportName: String {
        "\(project.song.title) - Karaoke.mp3"
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
