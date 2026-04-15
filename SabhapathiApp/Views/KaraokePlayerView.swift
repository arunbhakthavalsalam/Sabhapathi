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
    @State private var instrumentalPeaks: [Float] = []
    @State private var vocalPeaks: [Float] = []
    @State private var peaksLoadingForProject: UUID?

    private let audioExporter = AudioExporter()

    init(project: KaraokeProject) {
        self.project = project
        _stemMixer = StateObject(wrappedValue: StemMixer())
    }

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                // Main content area
                HSplitView {
                    if showLyrics {
                        LyricsDisplayView(
                            lyrics: lyricsService.lyrics,
                            currentTime: audioEngine.currentTime
                        )
                        .frame(minWidth: 300)
                    }

                    if showStemMixer {
                        StemMixerView(stemMixer: stemMixer)
                            .frame(width: 280)
                    }
                }

                playbackPanel
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .padding(.bottom, 20)
            }
        }
        .onAppear {
            loadAudio()
            fetchLyrics()
            loadWaveformPeaks()
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

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.97, green: 0.96, blue: 1.00),
                Color(red: 0.93, green: 0.94, blue: 0.99),
                Color(red: 0.99, green: 0.95, blue: 0.97),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            artworkBadge

            VStack(alignment: .leading, spacing: 4) {
                Text(project.song.title)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !project.song.artist.isEmpty {
                    Text(project.song.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 10) {
                Button {
                    saveKaraoke()
                } label: {
                    Label(isExporting ? "Saving…" : "Save Karaoke",
                          systemImage: "square.and.arrow.down.fill")
                }
                .disabled(isExporting)
                .buttonStyle(.borderedProminent)
                .tint(.pink)

                Toggle(isOn: $showLyrics) {
                    Label("Lyrics", systemImage: "text.quote")
                }
                .toggleStyle(.button)

                Toggle(isOn: $showStemMixer) {
                    Label("Mixer", systemImage: "slider.horizontal.3")
                }
                .toggleStyle(.button)
            }
            .labelStyle(.titleAndIcon)
            .controlSize(.regular)
        }
    }

    private var artworkBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.45, green: 0.22, blue: 0.78),
                            Color(red: 0.92, green: 0.30, blue: 0.55),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
            Image(systemName: "music.mic")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 56, height: 56)
    }

    // MARK: - Playback panel

    private var playbackPanel: some View {
        VStack(spacing: 12) {
            HStack {
                Text(formatTime(audioEngine.currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)

                WaveformView(
                    instrumentalPeaks: instrumentalPeaks,
                    vocalPeaks: vocalPeaks,
                    currentTime: audioEngine.currentTime,
                    duration: audioEngine.duration,
                    onSeek: { audioEngine.seek(to: $0) }
                )
                .frame(height: 64)
                .overlay(alignment: .center) {
                    if instrumentalPeaks.isEmpty && vocalPeaks.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Analyzing waveform…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Text(formatTime(audioEngine.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }

            HStack {
                WaveformLegend()
                Spacer()
            }

            transportRow
        }
    }

    private var transportRow: some View {
        HStack(spacing: 18) {
            Spacer()

            Button {
                audioEngine.seek(to: max(audioEngine.currentTime - 10, 0))
            } label: {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)

            Button {
                if audioEngine.isPlaying {
                    audioEngine.pause()
                } else {
                    audioEngine.play()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.00, green: 0.36, blue: 0.60),
                                    Color(red: 0.78, green: 0.24, blue: 0.85),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color(red: 0.9, green: 0.3, blue: 0.6).opacity(0.45),
                                radius: 12, y: 4)
                    Image(systemName: audioEngine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: audioEngine.isPlaying ? 0 : 2)
                }
                .frame(width: 54, height: 54)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])

            Button {
                audioEngine.seek(to: min(audioEngine.currentTime + 10, audioEngine.duration))
            } label: {
                Image(systemName: "goforward.10")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 8) {
                Button("Karaoke") { stemMixer.resetToKaraoke() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.pink)

                Button("Original") { stemMixer.resetToOriginal() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Loading

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

    private func loadWaveformPeaks() {
        guard let stemSet = project.stemSet else { return }
        // Guard against duplicate loads when the view re-appears for the same project.
        guard peaksLoadingForProject != project.id else { return }
        peaksLoadingForProject = project.id
        instrumentalPeaks = []
        vocalPeaks = []

        let vocalsURL = stemSet.vocals
        // Prefer the pre-mixed karaoke stem for the instrumental layer; if it's
        // missing (older projects), fall back to `other` — drums+bass alone
        // paints too sparse a picture to be useful.
        let instrumentalURL = stemSet.karaoke ?? stemSet.other

        Task { @MainActor in
            async let instrumentalTask: [Float] = {
                guard let url = instrumentalURL else { return [] }
                return await WaveformService.peaks(for: url)
            }()
            async let vocalsTask: [Float] = {
                guard let url = vocalsURL else { return [] }
                return await WaveformService.peaks(for: url)
            }()

            let (inst, voc) = await (instrumentalTask, vocalsTask)
            self.instrumentalPeaks = inst
            self.vocalPeaks = voc
        }
    }

    // MARK: - Export

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
        guard time.isFinite, time >= 0 else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
