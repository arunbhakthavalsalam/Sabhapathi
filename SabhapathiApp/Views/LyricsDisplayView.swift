import SwiftUI

struct LyricsDisplayView: View {
    let lyrics: [LyricsLine]
    let currentTime: TimeInterval
    @State private var autoScroll = true

    var currentLineIndex: Int? {
        guard !lyrics.isEmpty else { return nil }
        var lastIndex: Int?
        for (index, line) in lyrics.enumerated() {
            if line.timestamp <= currentTime {
                lastIndex = index
            } else {
                break
            }
        }
        return lastIndex
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Lyrics")
                    .font(.headline)
                Spacer()
                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
            .padding()

            Divider()

            if lyrics.isEmpty {
                VStack {
                    Spacer()
                    Text("No lyrics available")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(lyrics.enumerated()), id: \.element.id) { index, line in
                                LyricsLineView(
                                    line: line,
                                    isActive: index == currentLineIndex,
                                    isPast: currentLineIndex.map { index < $0 } ?? false
                                )
                                .id(line.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: currentLineIndex) { newIndex in
                        if autoScroll, let index = newIndex, index < lyrics.count {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(lyrics[index].id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct LyricsLineView: View {
    let line: LyricsLine
    let isActive: Bool
    let isPast: Bool

    var body: some View {
        Text(line.text)
            .font(isActive ? .title3.bold() : .body)
            .foregroundColor(
                isActive ? .primary :
                isPast ? .secondary : .primary.opacity(0.7)
            )
            .scaleEffect(isActive ? 1.05 : 1.0, anchor: .leading)
            .animation(.easeInOut(duration: 0.2), value: isActive)
            .padding(.vertical, 2)
    }
}
