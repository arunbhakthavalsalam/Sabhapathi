# Sabhapathi Karaoke - macOS App

A native macOS app that takes MP3 files or YouTube links and produces karaoke audio (vocals removed, instrumentals kept), with synced lyrics display and a "keep chorus" mode.

---

## Architecture

**Three-layer design**: SwiftUI frontend -> Swift service layer -> Python backend (FastAPI on localhost:9457)

```
SwiftUI Views (Import, Processing, Karaoke Player, Library)
        |
Swift Services (PythonBridge, AudioEngine, LyricsService, ProjectManager)
        |
Python Backend on localhost:9457 (FastAPI + Demucs + yt-dlp + Whisper)
        |
File System: ~/Library/Application Support/Sabhapathi/projects/{uuid}/
```

---

## Project Structure

```
Sabhapathi/
├── SabhapathiApp.xcodeproj/        # Xcode project (auto-generated)
│   └── project.pbxproj
│
├── SabhapathiApp/                   # Swift source code
│   ├── App/
│   │   ├── SabhapathiApp.swift      # @main entry point, window/menu config
│   │   ├── AppDelegate.swift        # Python backend lifecycle (start/stop)
│   │   └── ContentView.swift        # Root NavigationSplitView
│   │
│   ├── Views/
│   │   ├── ImportView.swift         # Drag-drop MP3 + YouTube URL input
│   │   ├── ProcessingView.swift     # Progress bar during separation
│   │   ├── KaraokePlayerView.swift  # Playback + lyrics + stem mixer
│   │   ├── LibraryView.swift        # Sidebar list of processed songs
│   │   ├── StemMixerView.swift      # Per-stem volume sliders + mute
│   │   ├── LyricsDisplayView.swift  # Scrolling synced lyrics
│   │   ├── ChorusSectionEditor.swift# Mark/auto-detect chorus sections
│   │   └── SettingsView.swift       # Model selection, quality, etc.
│   │
│   ├── Services/
│   │   ├── PythonBackendManager.swift  # Spawn/monitor/kill Python process
│   │   ├── BackendAPIClient.swift      # HTTP calls to FastAPI backend
│   │   ├── AudioEngineService.swift    # AVAudioEngine 4-stem playback
│   │   ├── StemMixer.swift             # Real-time volume/mute + chorus mixback
│   │   ├── LyricsService.swift         # LRCLIB + Whisper orchestration
│   │   ├── LRCParser.swift             # Parse/generate .lrc files
│   │   ├── ProjectManager.swift        # File/project CRUD, JSON persistence
│   │   └── AudioExporter.swift         # Mix stems to MP3 via ffmpeg
│   │
│   ├── Models/
│   │   ├── KaraokeProject.swift     # Top-level project model
│   │   ├── Song.swift               # Song metadata (title, artist, source)
│   │   ├── StemSet.swift            # URLs to separated stems
│   │   ├── LyricsLine.swift         # Timestamped lyric line
│   │   └── ProcessingJob.swift      # Backend job tracking
│   │
│   └── Resources/
│       ├── Info.plist               # App config, local networking allowed
│       └── Sabhapathi.entitlements  # Sandbox disabled, network client
│
├── PythonBackend/                   # FastAPI backend
│   ├── requirements.txt             # Python dependencies
│   └── sabhapathi_backend/
│       ├── __init__.py
│       ├── __main__.py              # uvicorn entry point
│       ├── server.py                # FastAPI app + CORS + route registration
│       ├── routes/
│       │   ├── __init__.py
│       │   ├── health.py            # GET /health
│       │   ├── separation.py        # POST /api/separate, GET /api/status/{id}
│       │   ├── download.py          # POST /api/download, GET /api/download/status/{id}
│       │   └── lyrics.py            # POST /api/lyrics/search, POST /api/lyrics/transcribe
│       └── services/
│           ├── __init__.py
│           ├── demucs_service.py    # Demucs vocal separation (MPS GPU)
│           ├── ytdlp_service.py     # YouTube audio download
│           └── whisper_service.py   # Whisper transcription -> LRC
│
├── ffmpeg                           # Bundled ffmpeg binary
├── compare_mfcc.py                  # MFCC analysis for chorus detection
└── *.mp3                            # Test MP3 samples
```

---

## Tech Stack

### Swift (macOS App)
| Component | Technology |
|-----------|-----------|
| UI Framework | SwiftUI (macOS 13+) |
| Audio Playback | AVAudioEngine (4 player nodes for stems) |
| HTTP Client | URLSession |
| Data Persistence | JSON files in Application Support |
| Audio Export | ffmpeg subprocess |

### Python (Backend Server)
| Component | Technology |
|-----------|-----------|
| Web Framework | FastAPI + Uvicorn |
| Vocal Separation | Demucs `htdemucs` (MPS GPU on Apple Silicon) |
| YouTube Download | yt-dlp |
| Lyrics (primary) | LRCLIB API (free synced lyrics database) |
| Lyrics (fallback) | OpenAI Whisper (speech-to-text) |
| Audio Processing | torchaudio, librosa |

---

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Backend health check |
| POST | `/api/separate` | Start vocal separation job |
| GET | `/api/status/{job_id}` | Poll separation progress |
| POST | `/api/download` | Start YouTube download |
| GET | `/api/download/status/{job_id}` | Poll download progress |
| POST | `/api/lyrics/search` | Search LRCLIB for synced lyrics |
| POST | `/api/lyrics/transcribe` | Start Whisper transcription |
| GET | `/api/lyrics/status/{job_id}` | Poll transcription progress |

---

## Data Model

### KaraokeProject
- `id: UUID` - Unique project identifier
- `song: Song` - Song metadata
- `stemSet: StemSet?` - Separated audio stems (vocals, drums, bass, other, karaoke)
- `lyrics: [LyricsLine]` - Timestamped lyrics
- `chorusSections: [ChorusSection]` - Marked chorus regions
- `processingStatus` - imported | downloading | separating | completed | failed

### File System Layout
```
~/Library/Application Support/Sabhapathi/
├── projects.json                    # Project manifest
└── projects/
    └── {uuid}/
        ├── original.mp3             # Source audio
        └── stems/
            ├── vocals.wav
            ├── drums.wav
            ├── bass.wav
            ├── other.wav
            └── karaoke.wav          # Pre-mixed instrumental
```

---

## Key Features

### 1. Import
- **Drag & drop** MP3 files onto the import area
- **File picker** (Cmd+O) for standard file selection
- **YouTube URL** paste and download

### 2. Vocal Separation
- Uses **Demucs htdemucs** model for high-quality source separation
- **MPS GPU acceleration** on Apple Silicon Macs
- Produces 4 stems: vocals, drums, bass, other
- Auto-generates karaoke mix (instrumental only)
- Real-time progress polling during processing

### 3. Karaoke Playback
- **AVAudioEngine** plays 4 stems simultaneously
- **Stem mixer** with per-stem volume sliders and mute buttons
- Transport controls: play/pause, seek, skip ±10s
- One-click presets: "Karaoke" (mute vocals) / "Original" (all stems)

### 4. Synced Lyrics
- **LRCLIB API** for instant lyrics lookup (free, no API key needed)
- **Whisper fallback** for songs not in LRCLIB database
- Auto-scrolling display with highlighted current line
- Visual distinction: active (bold, large), past (dimmed), upcoming (normal)

### 5. Chorus Mode
- **Manual marking**: click "Mark Start" → "End Section" during playback
- **Auto-detection**: planned via MFCC analysis (compare_mfcc.py)
- During chorus sections, vocals mix back at configurable volume (-6dB default)
- Works in both real-time playback and exported files

### 6. Export
- **Karaoke MP3**: instrumental-only mix
- **MP3 + LRC pair**: karaoke audio with synced lyrics file
- **Chorus export**: instrumental + vocal choruses via ffmpeg filter
- **Individual stems**: raw WAV stems for advanced users

---

## Setup & Running

### Prerequisites
- macOS 13.0+
- Xcode 15+
- Python 3.10+
- ~5GB disk space for ML models (Demucs, Whisper)

### Python Backend Setup
```bash
cd PythonBackend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Test the backend
python -m sabhapathi_backend
# Should start on http://127.0.0.1:9457
# Verify: curl http://127.0.0.1:9457/health
```

### Building the App
```bash
# From project root
xcodebuild -project SabhapathiApp.xcodeproj -scheme Sabhapathi -configuration Debug build

# Or open in Xcode
open SabhapathiApp.xcodeproj
```

### Running
1. The app automatically starts the Python backend on launch
2. Backend health is shown in the bottom-right corner
3. Import a song via drag-drop or File → Import MP3
4. Click "Start Processing" to separate stems
5. Once complete, the karaoke player appears with stem mixer and lyrics

---

## Configuration (Settings)

| Setting | Options | Default |
|---------|---------|---------|
| Demucs Model | htdemucs, htdemucs_ft, mdx_extra | htdemucs |
| Whisper Model | tiny, base, small, medium | base |
| Output Quality | 128, 192, 320 kbps | 192 kbps |
| Auto-fetch Lyrics | on/off | on |

---

## Processing Pipeline

```
MP3 Import ──────┐
                  ├──→ Copy to project dir ──→ POST /api/separate ──→ Demucs
YouTube URL ─────┘     (original.mp3)          (poll /api/status)     (htdemucs)
                                                     │
                                                     ▼
                                              4 stems + karaoke.wav
                                                     │
                                                     ▼
                                            Search LRCLIB for lyrics
                                              ┌──────┴──────┐
                                            Found        Not found
                                              │              │
                                           Use LRC     Whisper transcribe
                                              │         vocal stem
                                              └──────┬──────┘
                                                     │
                                                     ▼
                                            KaraokePlayerView
                                         (stems + lyrics + mixer)
```

---

## Distribution
- **Outside App Store** (DMG + notarization) to allow Python subprocess spawning
- App Sandbox disabled in entitlements
- Hardened Runtime enabled for notarization compatibility
- Code-signed with `com.apple.security.cs.allow-unsigned-executable-memory` for Python runtime
