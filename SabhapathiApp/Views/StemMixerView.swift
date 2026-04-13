import SwiftUI

struct StemMixerView: View {
    @ObservedObject var stemMixer: StemMixer

    private let stems = [
        ("vocals", "mic.fill", Color.blue),
        ("drums", "drum.fill", Color.orange),
        ("bass", "speaker.wave.2.fill", Color.purple),
        ("other", "music.note", Color.green),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stem Mixer")
                .font(.headline)
                .padding(.horizontal)

            ForEach(stems, id: \.0) { stem, icon, color in
                StemSliderRow(
                    name: stem.capitalized,
                    icon: icon,
                    color: color,
                    volume: Binding(
                        get: { stemMixer.volumes[stem, default: 1.0] },
                        set: { stemMixer.setVolume(stem: stem, volume: $0) }
                    ),
                    isMuted: stemMixer.muted[stem, default: false],
                    onToggleMute: { stemMixer.toggleMute(stem: stem) }
                )
            }

            Divider()

            // Chorus vocal volume
            VStack(alignment: .leading, spacing: 4) {
                Text("Chorus Vocal Level")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { stemMixer.chorusVocalVolume },
                    set: { stemMixer.chorusVocalVolume = $0 }
                ), in: 0...1)
                Text("\(Int(stemMixer.chorusVocalVolume * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.vertical)
    }
}

struct StemSliderRow: View {
    let name: String
    let icon: String
    let color: Color
    @Binding var volume: Float
    let isMuted: Bool
    let onToggleMute: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggleMute) {
                Image(systemName: isMuted ? "speaker.slash.fill" : icon)
                    .frame(width: 20)
                    .foregroundStyle(isMuted ? .secondary : color)
            }
            .buttonStyle(.plain)

            Text(name)
                .font(.caption)
                .frame(width: 50, alignment: .leading)

            Slider(value: Binding(
                get: { volume },
                set: { volume = $0 }
            ), in: 0...1)
            .disabled(isMuted)
            .opacity(isMuted ? 0.4 : 1.0)

            Text("\(Int(volume * 100))")
                .font(.caption.monospacedDigit())
                .frame(width: 28, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }
}
