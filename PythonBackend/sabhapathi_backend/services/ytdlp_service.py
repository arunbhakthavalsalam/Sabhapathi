"""yt-dlp download service — shells out to the bundled standalone binary.

The Python `yt_dlp` package is capped at 2025.10.14 on Python 3.9, which YouTube
has moved past. The standalone `yt-dlp_macos` binary ships its own interpreter
and is updated independently of our runtime.
"""
import json
import os
import re
import subprocess
from pathlib import Path
from typing import Callable, Optional

PROJECTS_DIR = os.path.expanduser(
    "~/Library/Application Support/Sabhapathi/projects"
)

_REPO_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.dirname(__file__)))
)

YT_DLP_BINARY = os.path.join(_REPO_ROOT, "yt-dlp_macos")
FFMPEG_PATH = os.path.join(_REPO_ROOT, "ffmpeg")

_PROGRESS_RE = re.compile(r"^\[download\]\s+([0-9.]+)%")


class YtDlpService:
    def download(
        self,
        url: str,
        project_id: str,
        on_progress: Optional[Callable[[float, str], None]] = None,
    ) -> dict:
        """Download audio from YouTube URL. Returns dict with title and output_path."""
        if not os.path.exists(YT_DLP_BINARY):
            raise RuntimeError(
                f"yt-dlp binary not found at {YT_DLP_BINARY}. "
                "Download the latest yt-dlp_macos from "
                "https://github.com/yt-dlp/yt-dlp/releases/latest"
            )

        project_dir = Path(PROJECTS_DIR) / project_id
        project_dir.mkdir(parents=True, exist_ok=True)
        output_template = str(project_dir / "original.%(ext)s")

        cmd = [
            YT_DLP_BINARY,
            "--no-playlist",
            "--format", "bestaudio/best",
            "--extract-audio",
            "--audio-format", "mp3",
            "--audio-quality", "192K",
            "--output", output_template,
            "--newline",              # each progress update on its own line
            "--progress",
            "--no-warnings",
            "--print-json",           # emit the final JSON metadata block
            "--no-simulate",
        ]
        if os.path.exists(FFMPEG_PATH):
            cmd += ["--ffmpeg-location", os.path.dirname(FFMPEG_PATH)]
        cmd.append(url)

        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )

        title = "Unknown"
        info_json: Optional[dict] = None

        assert proc.stdout is not None
        for line in proc.stdout:
            line = line.rstrip("\n")
            if not line:
                continue

            # Progress lines
            m = _PROGRESS_RE.match(line)
            if m and on_progress:
                try:
                    pct = float(m.group(1)) / 100.0
                    on_progress(0.1 + pct * 0.75, f"Downloading: {pct:.0%}")
                except ValueError:
                    pass
                continue

            if line.startswith("[ExtractAudio]") or "Destination:" in line:
                if on_progress:
                    on_progress(0.9, "Converting to MP3...")
                continue

            # JSON metadata block from --print-json (single line of JSON)
            if line.startswith("{") and info_json is None:
                try:
                    info_json = json.loads(line)
                    title = info_json.get("title") or title
                except json.JSONDecodeError:
                    pass

        returncode = proc.wait()
        stderr = proc.stderr.read() if proc.stderr else ""

        if returncode != 0:
            msg = stderr.strip() or f"yt-dlp exited with code {returncode}"
            raise RuntimeError(msg)

        output_path = str(project_dir / "original.mp3")
        if not os.path.exists(output_path):
            for ext in ("mp3", "m4a", "wav", "opus", "webm"):
                candidate = str(project_dir / f"original.{ext}")
                if os.path.exists(candidate):
                    output_path = candidate
                    break

        return {"title": title, "output_path": output_path}
