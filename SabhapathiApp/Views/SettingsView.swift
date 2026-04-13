import SwiftUI

struct SettingsView: View {
    @AppStorage("demucsModel") private var demucsModel = "htdemucs"
    @AppStorage("whisperModel") private var whisperModel = "base"
    @AppStorage("outputQuality") private var outputQuality = "192"
    @AppStorage("autoFetchLyrics") private var autoFetchLyrics = true

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            processingSettings
                .tabItem {
                    Label("Processing", systemImage: "waveform")
                }
        }
        .frame(width: 450, height: 300)
    }

    private var generalSettings: some View {
        Form {
            Toggle("Auto-fetch lyrics on import", isOn: $autoFetchLyrics)

            Picker("Output quality", selection: $outputQuality) {
                Text("128 kbps").tag("128")
                Text("192 kbps").tag("192")
                Text("320 kbps").tag("320")
            }
        }
        .padding()
    }

    private var processingSettings: some View {
        Form {
            Picker("Demucs model", selection: $demucsModel) {
                Text("htdemucs (Recommended)").tag("htdemucs")
                Text("htdemucs_ft (Higher quality)").tag("htdemucs_ft")
                Text("mdx_extra (Alternative)").tag("mdx_extra")
            }

            Picker("Whisper model", selection: $whisperModel) {
                Text("tiny (Fastest)").tag("tiny")
                Text("base (Balanced)").tag("base")
                Text("small (Better accuracy)").tag("small")
                Text("medium (High accuracy)").tag("medium")
            }

            Section {
                HStack {
                    Text("Backend port:")
                    Text("9457")
                        .foregroundStyle(.secondary)
                        .monospaced()
                }
            } header: {
                Text("Advanced")
            }
        }
        .padding()
    }
}
