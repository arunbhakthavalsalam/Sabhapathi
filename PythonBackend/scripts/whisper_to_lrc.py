"""V2 CLI shim: transcribe audio with Whisper and print LRC to stdout.

Invoked from Swift via subprocess. Keeps the same LRC formatting as
`sabhapathi_backend.services.whisper_service.WhisperService` so the app
behavior stays identical when the FastAPI path is disabled.

Usage:
    python whisper_to_lrc.py <audio_path> <project_id> [model_name]
"""
import os
import sys
from pathlib import Path

PROJECTS_DIR = os.path.expanduser(
    "~/Library/Application Support/Sabhapathi/projects"
)


def main() -> int:
    if len(sys.argv) < 3:
        sys.stderr.write("usage: whisper_to_lrc.py <audio_path> <project_id> [model_name]\n")
        return 2

    audio_path = sys.argv[1]
    project_id = sys.argv[2]
    model_name = sys.argv[3] if len(sys.argv) > 3 else "base"

    # Imported lazily so argument errors don't pay the torch import cost.
    import whisper

    model = whisper.load_model(model_name)
    result = model.transcribe(
        audio_path,
        word_timestamps=True,
        language=None,  # auto-detect
    )

    lrc_lines = []
    for segment in result.get("segments", []):
        start = segment["start"]
        text = (segment.get("text") or "").strip()
        if not text:
            continue
        minutes = int(start // 60)
        seconds = start % 60
        lrc_lines.append(f"[{minutes:02d}:{seconds:05.2f}]{text}")

    lrc_content = "\n".join(lrc_lines)

    project_dir = Path(PROJECTS_DIR) / project_id
    project_dir.mkdir(parents=True, exist_ok=True)
    (project_dir / "lyrics.lrc").write_text(lrc_content, encoding="utf-8")

    sys.stdout.write(lrc_content)
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
