import Foundation

/// Single source of truth for external binary + interpreter paths.
///
/// Resolution order for each resource:
///   1. Inside the .app bundle (what ships to users).
///   2. A user-installed venv at `~/Library/Application Support/Sabhapathi/python_env`
///      (populated by `scripts/install_dependencies.sh`).
///   3. Hardcoded repo paths — dev-only fallback so Xcode debug runs still work.
enum RuntimePaths {
    static var ytdlp: String {
        if let url = Bundle.main.url(forResource: "yt-dlp_macos", withExtension: nil) {
            return url.path
        }
        return repoFallback("yt-dlp_macos")
    }

    static var ffmpeg: String {
        if let url = Bundle.main.url(forResource: "ffmpeg", withExtension: nil) {
            return url.path
        }
        return repoFallback("ffmpeg")
    }

    static var whisperScript: String {
        if let url = Bundle.main.url(forResource: "whisper_to_lrc", withExtension: "py") {
            return url.path
        }
        return repoFallback("PythonBackend/scripts/whisper_to_lrc.py")
    }

    /// Path to a Python interpreter with demucs + whisper installed.
    static var python: String {
        if let env = ProcessInfo.processInfo.environment["SABHAPATHI_PYTHON"] {
            return env
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let installed = support
            .appendingPathComponent("Sabhapathi")
            .appendingPathComponent("python_env")
            .appendingPathComponent("bin")
            .appendingPathComponent("python3")
        if FileManager.default.fileExists(atPath: installed.path) {
            return installed.path
        }
        return repoFallback("PythonBackend/venv/bin/python3")
    }

    static var pythonAvailable: Bool {
        FileManager.default.fileExists(atPath: python)
    }

    /// Env dict for subprocesses that invoke Python tools so bundled ffmpeg is
    /// found by whisper's internal subprocess call.
    static func pythonProcessEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let ffmpegDir = (ffmpeg as NSString).deletingLastPathComponent
        let existing = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = "\(ffmpegDir):\(existing)"
        return env
    }

    private static func repoFallback(_ relative: String) -> String {
        "/Users/arunb/Documents/Sabhapathi/\(relative)"
    }
}
