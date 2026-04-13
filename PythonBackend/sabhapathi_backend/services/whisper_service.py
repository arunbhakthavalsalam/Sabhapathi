"""Whisper transcription service - generates LRC from audio."""
import os
from pathlib import Path

PROJECTS_DIR = os.path.expanduser(
    "~/Library/Application Support/Sabhapathi/projects"
)


class WhisperService:
    def __init__(self):
        self._model = None

    def _get_model(self):
        if self._model is None:
            import whisper
            self._model = whisper.load_model("base")
        return self._model

    def transcribe_to_lrc(self, audio_path: str, project_id: str) -> str:
        """Transcribe audio and return LRC-formatted lyrics."""
        model = self._get_model()

        result = model.transcribe(
            audio_path,
            word_timestamps=True,
            language=None,  # auto-detect
        )

        lrc_lines = []
        for segment in result.get("segments", []):
            start = segment["start"]
            text = segment["text"].strip()
            if text:
                minutes = int(start // 60)
                seconds = start % 60
                lrc_lines.append(f"[{minutes:02d}:{seconds:05.2f}]{text}")

        lrc_content = "\n".join(lrc_lines)

        # Save LRC file
        project_dir = Path(PROJECTS_DIR) / project_id
        project_dir.mkdir(parents=True, exist_ok=True)
        lrc_path = project_dir / "lyrics.lrc"
        lrc_path.write_text(lrc_content, encoding="utf-8")

        return lrc_content
