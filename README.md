# Sabhapathi Karaoke — macOS App

Native macOS app that turns an MP3 or YouTube link into a karaoke track (vocals removed), synced lyrics display, and a "keep the chorus" mixback mode.

---

## Architecture (V2 — native, no backend)

V1 used a FastAPI sidecar on `localhost:9457`. V2 runs everything in-process: Swift drives `yt-dlp`, `demucs`, and `whisper` as subprocesses, and talks to LRCLIB directly over HTTPS. The FastAPI backend is still in the repo for fallback but is disabled by default via `AppFlags.allServicesNative`.

```
SwiftUI Views (Import, Processing, Karaoke Player, Library)
        │
Swift Services
  ├── NativeDownloadService   → yt-dlp_macos subprocess
  ├── NativeSeparationService → python -m demucs.separate subprocess
  ├── NativeLyricsService     → URLSession → LRCLib, then whisper subprocess
  ├── AudioEngineService      → AVAudioEngine (4 stem player nodes)
  ├── StemMixer / LyricsService / ProjectManager / AudioExporter
  └── RuntimePaths            → bundle-first resolution with dev fallback
        │
File System: ~/Library/Application Support/Sabhapathi/projects/{uuid}/
```

`AppFlags.useNativeDownload / useNativeSeparation / useNativeLyrics` default to `true`. Flip them to fall back to the FastAPI backend (`PythonBackendManager` only starts the sidecar when at least one flag is off).

---

## Project Structure

```
Sabhapathi/
├── SabhapathiApp.xcodeproj/
│
├── SabhapathiApp/
│   ├── App/
│   │   ├── SabhapathiApp.swift        # @main
│   │   ├── AppDelegate.swift          # starts backend only if !allServicesNative
│   │   └── ContentView.swift          # NavigationSplitView + status badge
│   │
│   ├── Views/
│   │   ├── ImportView.swift           # Drag-drop MP3 + YouTube URL
│   │   ├── ProcessingView.swift       # Download/separation progress
│   │   ├── KaraokePlayerView.swift    # Playback + lyrics + mixer
│   │   ├── LibraryView.swift          # Sidebar
│   │   ├── StemMixerView.swift
│   │   ├── LyricsDisplayView.swift
│   │   ├── ChorusSectionEditor.swift
│   │   └── SettingsView.swift
│   │
│   ├── Services/
│   │   ├── AppFlags.swift             # Native vs backend switches
│   │   ├── RuntimePaths.swift         # Bundle → ~/Library → repo fallback
│   │   ├── DownloadService.swift      # Protocol + DownloadState
│   │   ├── NativeDownloadService.swift
│   │   ├── SeparationService.swift    # Protocol + SeparationState
│   │   ├── NativeSeparationService.swift
│   │   ├── LyricsService.swift        # LRCLib + Whisper orchestration
│   │   ├── NativeLyricsService.swift
│   │   ├── AudioEngineService.swift   # AVAudioEngine, 4 stems
│   │   ├── StemMixer.swift            # Volume/mute + chorus mixback
│   │   ├── LRCParser.swift
│   │   ├── ProjectManager.swift       # Persistence + hoisted progress state
│   │   ├── AudioExporter.swift        # Mix stems to MP3 via ffmpeg
│   │   ├── BackendAPIClient.swift     # Legacy, only used when flags are off
│   │   └── PythonBackendManager.swift # Legacy FastAPI sidecar lifecycle
│   │
│   ├── Models/
│   │   ├── KaraokeProject.swift
│   │   ├── Song.swift
│   │   ├── StemSet.swift
│   │   ├── LyricsLine.swift
│   │   └── ProcessingJob.swift
│   │
│   └── Resources/
│       ├── Info.plist
│       └── Sabhapathi.entitlements    # Hardened runtime, JIT, dyld-env
│
├── PythonBackend/
│   ├── requirements.txt
│   ├── scripts/
│   │   └── whisper_to_lrc.py          # CLI shim invoked by NativeLyricsService
│   └── sabhapathi_backend/             # Legacy FastAPI app (fallback only)
│       ├── __main__.py
│       ├── server.py
│       ├── routes/ (health, separation, download, lyrics)
│       └── services/ (demucs, ytdlp, whisper)
│
├── scripts/
│   ├── install_dependencies.sh         # Recipient-side Python venv setup
│   └── package_release.sh              # Archive + notarize + staple
│
├── ffmpeg                              # Bundled binary (Copy Resources)
├── yt-dlp_macos                        # Bundled binary (Copy Resources)
└── *.mp3                               # Test samples
```

---

## Tech Stack

### Swift (macOS App)
| Component | Technology |
|-----------|-----------|
| UI Framework | SwiftUI (macOS 13+) |
| Audio Playback | AVAudioEngine (4 stem player nodes) |
| Subprocess IPC | `Process` + `Pipe` + line-buffered stdout parsing |
| HTTP Client | URLSession (direct LRCLib lookups) |
| Data Persistence | JSON in `~/Library/Application Support/Sabhapathi` |
| Audio Export | ffmpeg subprocess |

### Python (subprocesses — no server)
| Component | Technology |
|-----------|-----------|
| Vocal Separation | Demucs `htdemucs` (MPS GPU on Apple Silicon) |
| YouTube Download | yt-dlp (bundled `yt-dlp_macos` binary) |
| Lyrics (primary) | LRCLib API (free synced lyrics, no key) |
| Lyrics (fallback) | OpenAI Whisper `base` via `whisper_to_lrc.py` |

Python interpreter resolution order (`RuntimePaths.python`):
1. `$SABHAPATHI_PYTHON` env var (dev override)
2. `~/Library/Application Support/Sabhapathi/python_env/bin/python3` (installer output)
3. `PythonBackend/venv/bin/python3` (repo fallback)

---

## Data Model

### KaraokeProject
- `id: UUID`
- `song: Song` — title, artist, source
- `stemSet: StemSet?` — URLs to vocals/drums/bass/other + karaoke.wav
- `lyrics: [LyricsLine]` — timestamped
- `chorusSections: [ChorusSection]` — marked chorus regions
- `processingStatus` — `imported | downloading | separating | completed | failed`

### File System Layout
```
~/Library/Application Support/Sabhapathi/
├── projects.json                    # Project manifest
├── python_env/                      # Recipient-installed venv (optional)
└── projects/
    └── {uuid}/
        ├── original.mp3             # Source audio
        ├── lyrics.lrc               # Synced lyrics (LRC or Whisper)
        └── stems/
            ├── vocals.wav
            ├── drums.wav
            ├── bass.wav
            ├── other.wav
            └── karaoke.wav          # Pre-mixed instrumental
```

---

## Key Features

1. **Import** — drag-drop any common audio format (MP3, M4A, WAV, FLAC, AAC, OGG, Opus, AIFF, WebM), file picker (Cmd+O), or paste a YouTube URL. The source extension is preserved on disk so there's no lossy re-encode before separation.
2. **Vocal separation** — Demucs `htdemucs`. Progress parsed from the tqdm stream. Drums+bass+other are mixed to `karaoke.wav` via a streaming chunked mixer in `NativeSeparationService` — memory stays bounded even for long tracks, and stem-format mismatches are caught before writing. Device defaults to CPU; set `SABHAPATHI_DEMUCS_DEVICE=mps` to enable the MPS backend (with `PYTORCH_ENABLE_MPS_FALLBACK=1` wired automatically).
3. **Karaoke playback** — 4 stem players, per-stem volume + mute, transport controls, spacebar toggles play/pause, Karaoke/Original presets. Seek position tracks accurately after a scrub (seek offset is added to the running player-time), and the time-tracking timer runs on `.common` runloop mode so the play-head doesn't freeze during menus or sliders.
4. **Synced lyrics** — LRCLib first, falls back to Whisper if the track isn't in the database. The LRC parser handles BOMs, metadata tags, multi-timestamp lines (`[00:12.00][01:24.00]Refrain`), and `mm:ss:xxx` sub-second separators. Auto-scroll with highlighted current line.
5. **Chorus mode** — mark start/end during playback; vocals mix back at configurable volume (-6 dB default) through those regions. Outside chorus, the user's own vocals slider is respected (no more "stuck at 0").
6. **Export** — karaoke MP3 (192 kbps default) or WAV, MP3 + LRC pair, chorus-mixback export, or individual stems. The ffmpeg runner drains stderr concurrently so long renders can't deadlock on a saturated pipe; the last ~8 lines of ffmpeg's error output surface on failure.
7. **Progress survives navigation** — download/separation state is hoisted into `ProjectManager`, so jumping between projects in the sidebar doesn't abort the job or lose the progress bar.

### Robustness notes

- Diagnostic logs for every native service flow through `os.Logger` under subsystem `com.sabhapathi.karaoke` (visible via `log stream --predicate 'subsystem == "com.sabhapathi.karaoke"'` or Console.app) — no more silent failures in separation, download, lyrics, or export paths.
- `AudioEngineService.loadStems` rolls back the engine cleanly if one stem fails to decode, rather than leaving half-attached nodes in place.
- `ProjectManager.importAudio` surfaces copy/directory failures instead of silently swallowing them, and rolls back a partial project dir if the source copy fails.
- LRCLib URL construction is no longer force-unwrapped; malformed inputs return `nil` rather than crashing the app.

---

## Setup & Running (development)

Prerequisites: macOS 13+, Xcode 15+, Python 3.10+, ~5 GB for ML models.

```bash
# One-time: set up the Python venv (demucs, torch, whisper)
cd PythonBackend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
cd ..

# Build and run
open SabhapathiApp.xcodeproj
# …or…
xcodebuild -project SabhapathiApp.xcodeproj -scheme Sabhapathi -configuration Debug build
```

The status badge in the bottom-right shows "Native (no backend)" when V2 services are active. It only polls the FastAPI health endpoint if you've flipped an `AppFlags` switch.

---

## Distribution

### Quick local install (personal use)
```bash
xcodebuild -project SabhapathiApp.xcodeproj -scheme Sabhapathi -configuration Debug build
cp -R ~/Library/Developer/Xcode/DerivedData/SabhapathiApp-*/Build/Products/Debug/Sabhapathi.app /Applications/
```
Ad-hoc signed; runs without Gatekeeper friction on the machine that built it.

### Shareable build (another Mac)
Developer ID signing + notarization is wired up. Release config uses manual signing with team `VJ5KRG427U` and the `Developer ID Application` identity; a Run Script build phase re-signs the bundled `yt-dlp_macos` and `ffmpeg` under the hardened runtime.

```bash
export APPLE_ID=you@example.com
export APP_PASSWORD=xxxx-xxxx-xxxx-xxxx    # app-specific password
scripts/package_release.sh
# Output: build/release/Sabhapathi.zip (signed, notarized, stapled)
```

On the recipient's Mac:
```bash
# Unzip the app into /Applications, then:
scripts/install_dependencies.sh
# Creates ~/Library/Application Support/Sabhapathi/python_env and installs
# demucs + torch + openai-whisper (~4 GB total).
```

Whisper `base` (~140 MB) and Demucs `htdemucs` (~300 MB) are downloaded to the user's cache on first run.

### Entitlements (hardened runtime)
- `com.apple.security.app-sandbox` = false (needed to spawn Python subprocesses)
- `com.apple.security.cs.allow-jit` (torch JIT)
- `com.apple.security.cs.allow-unsigned-executable-memory`
- `com.apple.security.cs.allow-dyld-environment-variables`
- `com.apple.security.cs.disable-library-validation`
- `com.apple.security.network.client`
- `com.apple.security.files.user-selected.read-write`

---

## Fallback: FastAPI backend

If you flip any `AppFlags` switch to `false`, the app starts the legacy FastAPI sidecar on `localhost:9457`. Endpoints:

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/health` | Backend health check |
| POST | `/api/separate` + GET `/api/status/{id}` | Vocal separation |
| POST | `/api/download` + GET `/api/download/status/{id}` | YouTube download |
| POST | `/api/lyrics/search` / `/api/lyrics/transcribe` | Lyrics |
