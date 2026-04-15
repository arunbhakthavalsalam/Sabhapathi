import SwiftUI

/// Dual-layer waveform scrubber. Each bar's height reflects combined
/// magnitude; its hue interpolates from blue (instrumental) to pink
/// (vocals) so you can *see* where the singing happens.
struct WaveformView: View {
    let instrumentalPeaks: [Float]
    let vocalPeaks: [Float]
    let currentTime: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    private static let instrumentalRGB: (r: Double, g: Double, b: Double) = (0.38, 0.58, 1.00)
    private static let vocalRGB: (r: Double, g: Double, b: Double) = (1.00, 0.36, 0.60)

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let progress = duration > 0
                ? CGFloat(max(0, min(currentTime / duration, 1)))
                : 0

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)

                Canvas { context, size in
                    draw(in: context, size: size, progress: progress)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 10)

                // Playhead
                Rectangle()
                    .fill(Color.primary.opacity(0.85))
                    .frame(width: 2)
                    .shadow(color: Color.black.opacity(0.25), radius: 2)
                    .offset(x: max(0, width * progress - 1))
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard width > 0, duration > 0 else { return }
                        let fraction = max(0, min(1, value.location.x / width))
                        onSeek(duration * Double(fraction))
                    }
            )
        }
    }

    private func draw(in context: GraphicsContext, size: CGSize, progress: CGFloat) {
        let binCount = max(instrumentalPeaks.count, vocalPeaks.count)
        guard binCount > 0, size.width > 0, size.height > 0 else { return }

        let barSpacing: CGFloat = 1.5
        let barWidth = max(1, size.width / CGFloat(binCount) - barSpacing)
        let midY = size.height / 2
        let maxBarHeight = size.height - 2
        let playedX = size.width * progress

        for i in 0..<binCount {
            let inst = i < instrumentalPeaks.count ? CGFloat(instrumentalPeaks[i]) : 0
            let voc  = i < vocalPeaks.count ? CGFloat(vocalPeaks[i]) : 0
            let combined = max(inst, voc)
            let magnitude = max(combined, 0.03)
            let barH = magnitude * maxBarHeight
            let x = (CGFloat(i) / CGFloat(binCount)) * size.width

            let sum = inst + voc
            let vocalRatio = sum > 0 ? voc / sum : 0
            let color = barColor(vocalRatio: vocalRatio, played: x < playedX)

            let rect = CGRect(
                x: x,
                y: midY - barH / 2,
                width: barWidth,
                height: barH
            )
            context.fill(
                Path(roundedRect: rect, cornerRadius: barWidth / 2),
                with: .color(color)
            )
        }
    }

    private func barColor(vocalRatio: CGFloat, played: Bool) -> Color {
        let t = vocalRatio
        let r = Self.instrumentalRGB.r + (Self.vocalRGB.r - Self.instrumentalRGB.r) * Double(t)
        let g = Self.instrumentalRGB.g + (Self.vocalRGB.g - Self.instrumentalRGB.g) * Double(t)
        let b = Self.instrumentalRGB.b + (Self.vocalRGB.b - Self.instrumentalRGB.b) * Double(t)
        let alpha: Double = played ? 1.0 : 0.55
        return Color(red: r, green: g, blue: b, opacity: alpha)
    }
}

struct WaveformLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            legendDot(color: Color(red: 0.38, green: 0.58, blue: 1.00), label: "Instrumental")
            legendDot(color: Color(red: 1.00, green: 0.36, blue: 0.60), label: "Vocals")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
        }
    }
}
