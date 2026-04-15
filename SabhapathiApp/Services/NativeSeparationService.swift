import AVFoundation
import Foundation
import os.log

/// V2 prototype: invokes Python demucs via subprocess against the existing venv,
/// then mixes drums+bass+other into karaoke.wav using AVAudioFile on the Swift side.
///
/// This lets us drop the FastAPI layer while we evaluate whether full backend-less
/// operation is viable. The Python interpreter path is still external — a later
/// iteration will bundle a relocatable python-build-standalone runtime.
final class NativeSeparationService: SeparationService {
    private static let log = Logger(subsystem: "com.sabhapathi.karaoke", category: "Separation")
    enum SeparationError: Error, LocalizedError {
        case pythonMissing(String)
        case demucsFailed(String)
        case stemsMissing(String)
        case mixFailed(String)

        var errorDescription: String? {
            switch self {
            case .pythonMissing(let path): return "Python interpreter not found at \(path)."
            case .demucsFailed(let msg): return "Demucs failed: \(msg)"
            case .stemsMissing(let msg): return "Expected stems not found: \(msg)"
            case .mixFailed(let msg): return "Karaoke mix failed: \(msg)"
            }
        }
    }

    private let pythonPath: String
    private let modelName: String
    private let projectsDir: URL
    private let device: String

    init(
        pythonPath: String = RuntimePaths.python,
        modelName: String = "htdemucs"
    ) {
        self.pythonPath = pythonPath
        self.modelName = modelName
        // Power-user override: `SABHAPATHI_DEMUCS_DEVICE=mps` selects the MPS
        // backend. Default stays "cpu" because demucs' MPS path still silently
        // falls back on a handful of ops unless PYTORCH_ENABLE_MPS_FALLBACK=1
        // is set (which we do in pythonProcessEnvironment below).
        self.device = ProcessInfo.processInfo.environment["SABHAPATHI_DEMUCS_DEVICE"] ?? "cpu"
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.projectsDir = support
            .appendingPathComponent("Sabhapathi")
            .appendingPathComponent("projects")
    }

    func separate(
        inputPath: String,
        projectId: String,
        onProgress: @Sendable @escaping (Double, String) -> Void
    ) async throws -> SeparationResult {
        guard FileManager.default.fileExists(atPath: pythonPath) else {
            throw SeparationError.pythonMissing(pythonPath)
        }

        onProgress(0.1, "Preparing separation...")

        let stemsDir = projectsDir
            .appendingPathComponent(projectId)
            .appendingPathComponent("stems")
        try FileManager.default.createDirectory(at: stemsDir, withIntermediateDirectories: true)

        let demucsOut = stemsDir.appendingPathComponent("_demucs_output")
        try? FileManager.default.removeItem(at: demucsOut)
        try FileManager.default.createDirectory(at: demucsOut, withIntermediateDirectories: true)

        onProgress(0.2, "Running Demucs...")
        try await runDemucs(inputPath: inputPath, outputDir: demucsOut.path, onProgress: onProgress)

        onProgress(0.75, "Collecting stems...")
        let inputStem = (inputPath as NSString).lastPathComponent
        let inputBase = (inputStem as NSString).deletingPathExtension
        let trackDir = demucsOut
            .appendingPathComponent(modelName)
            .appendingPathComponent(inputBase)

        var stems: [String: String] = [:]
        for name in ["drums", "bass", "other", "vocals"] {
            let src = trackDir.appendingPathComponent("\(name).wav")
            guard FileManager.default.fileExists(atPath: src.path) else { continue }
            let dst = stemsDir.appendingPathComponent("\(name).wav")
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.moveItem(at: src, to: dst)
            stems[name] = dst.path
        }

        guard !stems.isEmpty else {
            throw SeparationError.stemsMissing(trackDir.path)
        }

        onProgress(0.9, "Creating karaoke mix...")
        let karaokePath = stemsDir.appendingPathComponent("karaoke.wav")
        try mixKaraoke(
            inputs: ["drums", "bass", "other"].compactMap { stems[$0].map(URL.init(fileURLWithPath:)) },
            output: karaokePath
        )
        stems["karaoke"] = karaokePath.path

        try? FileManager.default.removeItem(at: demucsOut)

        onProgress(1.0, "Complete.")
        return SeparationResult(outputDir: stemsDir.path, stems: stems)
    }

    // MARK: - Subprocess

    private func runDemucs(
        inputPath: String,
        outputDir: String,
        onProgress: @Sendable @escaping (Double, String) -> Void
    ) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        var env = RuntimePaths.pythonProcessEnvironment()
        // Lets demucs fall back to CPU for any MPS op that isn't implemented yet.
        env["PYTORCH_ENABLE_MPS_FALLBACK"] = "1"
        process.environment = env
        process.arguments = [
            "-u",
            "-m", "demucs.separate",
            "-n", modelName,
            "-o", outputDir,
            "-d", device,
            inputPath,
        ]

        Self.log.info("demucs start: device=\(self.device, privacy: .public) model=\(self.modelName, privacy: .public)")

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Demucs writes tqdm progress to stderr.
        let percentRegex = try NSRegularExpression(pattern: #"(\d{1,3})%"#)
        let stderrBuffer = DataBox()
        let stdoutBuffer = DataBox()

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            stderrBuffer.append(data)

            if let text = String(data: data, encoding: .utf8) {
                let ns = text as NSString
                let matches = percentRegex.matches(
                    in: text,
                    range: NSRange(location: 0, length: ns.length)
                )
                if let last = matches.last, last.numberOfRanges > 1 {
                    let pctStr = ns.substring(with: last.range(at: 1))
                    if let pct = Double(pctStr) {
                        let scaled = 0.2 + (pct / 100.0) * 0.55
                        onProgress(scaled, "Separating: \(Int(pct))%")
                    }
                }
            }
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            stdoutBuffer.append(data)
        }

        try process.run()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { proc in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let err = String(data: stderrBuffer.value, encoding: .utf8) ?? ""
                    let out = String(data: stdoutBuffer.value, encoding: .utf8) ?? ""
                    let msg = err.isEmpty ? out : err
                    Self.log.error("demucs exit \(proc.terminationStatus): \(msg, privacy: .public)")
                    continuation.resume(throwing: SeparationError.demucsFailed(
                        msg.trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                }
            }
        }
    }

    // MARK: - Karaoke mix

    /// Sums PCM samples from the given stems into a single WAV file.
    ///
    /// Streams in fixed-size chunks rather than loading full stems into memory,
    /// so a 30-minute source doesn't spike to ~1 GB of RAM during the mix. Also
    /// validates that every stem shares the same sample rate + channel count —
    /// demucs always emits 44.1 kHz stereo, but we check anyway so a future
    /// model swap can't silently produce garbage.
    private func mixKaraoke(inputs: [URL], output: URL) throws {
        guard !inputs.isEmpty else {
            throw SeparationError.mixFailed("no inputs")
        }

        let readers = try inputs.map { try AVAudioFile(forReading: $0) }
        let processingFormat = readers[0].processingFormat

        // Validate uniformity.
        for reader in readers.dropFirst() {
            let f = reader.processingFormat
            guard f.sampleRate == processingFormat.sampleRate,
                  f.channelCount == processingFormat.channelCount else {
                throw SeparationError.mixFailed(
                    "Stem format mismatch: \(f.sampleRate) Hz / \(f.channelCount) ch " +
                    "vs \(processingFormat.sampleRate) Hz / \(processingFormat.channelCount) ch"
                )
            }
        }

        let totalFrames = readers.map(\.length).max() ?? 0
        guard totalFrames > 0 else {
            throw SeparationError.mixFailed("empty stems")
        }

        let channelCount = Int(processingFormat.channelCount)
        let chunkFrames: AVAudioFrameCount = 1 << 15 // ~32k frames ≈ 0.74 s at 44.1 kHz

        try? FileManager.default.removeItem(at: output)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: processingFormat.sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let outFile = try AVAudioFile(forWriting: output, settings: settings)

        guard let mixBuffer = AVAudioPCMBuffer(
            pcmFormat: processingFormat,
            frameCapacity: chunkFrames
        ) else {
            throw SeparationError.mixFailed("could not allocate chunk buffer")
        }

        let stemBuffers: [AVAudioPCMBuffer] = try readers.map { reader in
            guard let buf = AVAudioPCMBuffer(
                pcmFormat: reader.processingFormat,
                frameCapacity: chunkFrames
            ) else {
                throw SeparationError.mixFailed("could not allocate stem buffer")
            }
            return buf
        }

        var remaining = totalFrames
        while remaining > 0 {
            let thisChunk = AVAudioFrameCount(min(Int64(chunkFrames), remaining))
            mixBuffer.frameLength = thisChunk

            guard let dst = mixBuffer.floatChannelData else {
                throw SeparationError.mixFailed("mix buffer has no float channel data")
            }
            for ch in 0..<channelCount {
                memset(dst[ch], 0, Int(thisChunk) * MemoryLayout<Float>.size)
            }

            for (reader, buf) in zip(readers, stemBuffers) {
                buf.frameLength = 0
                do {
                    try reader.read(into: buf, frameCount: thisChunk)
                } catch {
                    // Past EOF on a shorter stem: keep going, treat as silence.
                    continue
                }
                guard let src = buf.floatChannelData else { continue }
                let frames = min(Int(buf.frameLength), Int(thisChunk))
                for ch in 0..<channelCount {
                    let d = dst[ch]
                    let s = src[ch]
                    for i in 0..<frames {
                        d[i] += s[i]
                    }
                }
            }

            // Clamp to [-1, 1] so the 16-bit writer doesn't wrap on clipped peaks.
            for ch in 0..<channelCount {
                let d = dst[ch]
                for i in 0..<Int(thisChunk) {
                    if d[i] > 1.0 { d[i] = 1.0 }
                    else if d[i] < -1.0 { d[i] = -1.0 }
                }
            }

            try outFile.write(from: mixBuffer)
            remaining -= Int64(thisChunk)
        }
    }
}

/// Lock-protected `Data` accumulator shared between subprocess readability
/// handlers and the termination continuation.
private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = Data()
    var value: Data { lock.lock(); defer { lock.unlock() }; return _value }
    func append(_ d: Data) { lock.lock(); _value.append(d); lock.unlock() }
}
