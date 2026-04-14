import AVFoundation
import Foundation

/// V2 prototype: invokes Python demucs via subprocess against the existing venv,
/// then mixes drums+bass+other into karaoke.wav using AVAudioFile on the Swift side.
///
/// This lets us drop the FastAPI layer while we evaluate whether full backend-less
/// operation is viable. The Python interpreter path is still external — a later
/// iteration will bundle a relocatable python-build-standalone runtime.
final class NativeSeparationService: SeparationService {
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

    init(
        pythonPath: String = RuntimePaths.python,
        modelName: String = "htdemucs"
    ) {
        self.pythonPath = pythonPath
        self.modelName = modelName
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
        process.environment = RuntimePaths.pythonProcessEnvironment()
        process.arguments = [
            "-u",
            "-m", "demucs.separate",
            "-n", modelName,
            "-o", outputDir,
            "-d", "cpu",
            inputPath,
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Demucs writes tqdm progress to stderr.
        let percentRegex = try NSRegularExpression(pattern: #"(\d{1,3})%"#)
        var stderrBuffer = Data()
        let stderrLock = NSLock()

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            stderrLock.lock()
            stderrBuffer.append(data)
            stderrLock.unlock()

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

        var stdoutBuffer = Data()
        let stdoutLock = NSLock()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            stdoutLock.lock()
            stdoutBuffer.append(data)
            stdoutLock.unlock()
        }

        try process.run()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { proc in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    stderrLock.lock()
                    let err = String(data: stderrBuffer, encoding: .utf8) ?? ""
                    stderrLock.unlock()
                    stdoutLock.lock()
                    let out = String(data: stdoutBuffer, encoding: .utf8) ?? ""
                    stdoutLock.unlock()
                    let msg = err.isEmpty ? out : err
                    continuation.resume(throwing: SeparationError.demucsFailed(
                        msg.trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                }
            }
        }
    }

    // MARK: - Karaoke mix

    /// Sums PCM samples from the given stems into a single WAV file.
    /// Assumes all stems share the same format (demucs always emits 44.1kHz stereo float32).
    private func mixKaraoke(inputs: [URL], output: URL) throws {
        guard !inputs.isEmpty else {
            throw SeparationError.mixFailed("no inputs")
        }

        let readers = try inputs.map { try AVAudioFile(forReading: $0) }
        let processingFormat = readers[0].processingFormat
        let frameCount = AVAudioFrameCount(readers[0].length)

        guard let mixBuffer = AVAudioPCMBuffer(
            pcmFormat: processingFormat,
            frameCapacity: frameCount
        ) else {
            throw SeparationError.mixFailed("could not allocate mix buffer")
        }
        mixBuffer.frameLength = frameCount

        guard let channelData = mixBuffer.floatChannelData else {
            throw SeparationError.mixFailed("mix buffer has no float channel data")
        }
        let channelCount = Int(processingFormat.channelCount)
        for ch in 0..<channelCount {
            memset(channelData[ch], 0, Int(frameCount) * MemoryLayout<Float>.size)
        }

        for reader in readers {
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: reader.processingFormat,
                frameCapacity: AVAudioFrameCount(reader.length)
            ) else { continue }
            try reader.read(into: buffer)

            guard let src = buffer.floatChannelData else { continue }
            let frames = min(Int(buffer.frameLength), Int(frameCount))
            for ch in 0..<channelCount {
                let dst = channelData[ch]
                let s = src[ch]
                for i in 0..<frames {
                    dst[i] += s[i]
                }
            }
        }

        // Float32 can exceed [-1, 1] after summing; clamp to avoid wrap on 16-bit writers.
        for ch in 0..<channelCount {
            let dst = channelData[ch]
            for i in 0..<Int(frameCount) {
                if dst[i] > 1.0 { dst[i] = 1.0 }
                else if dst[i] < -1.0 { dst[i] = -1.0 }
            }
        }

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
        try outFile.write(from: mixBuffer)
    }
}
