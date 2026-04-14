import Foundation

/// V2 migration flags. Single source of truth so UI and services agree on which code path is live.
enum AppFlags {
    /// When true, vocal separation runs via subprocess-invoked Python (no FastAPI).
    /// When false, separation goes through the V1 FastAPI backend.
    static let useNativeSeparation = true

    /// When true, YouTube download runs via the bundled yt-dlp_macos binary (no FastAPI).
    /// When false, download goes through the V1 FastAPI backend.
    static let useNativeDownload = true

    /// When true, lyrics lookup calls LRCLib directly from Swift and Whisper runs
    /// via subprocess to a Python shim. When false, both go through the FastAPI.
    static let useNativeLyrics = true

    /// True when every migrated code path is on its V2 implementation. When true the
    /// app no longer needs to auto-start the FastAPI sidecar on launch.
    static var allServicesNative: Bool {
        useNativeSeparation && useNativeDownload && useNativeLyrics
    }
}
