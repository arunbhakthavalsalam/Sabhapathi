"""Demucs vocal separation service with MPS (Apple Silicon) support."""
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Callable, Optional

PROJECTS_DIR = os.path.expanduser(
    "~/Library/Application Support/Sabhapathi/projects"
)


class DemucsService:
    def __init__(self):
        self._model_cache: dict = {}

    def separate(
        self,
        input_path: str,
        project_id: str,
        model_name: str = "htdemucs",
        on_progress: Optional[Callable[[float, str], None]] = None,
    ) -> dict:
        """Run Demucs separation on an audio file.

        Returns dict with output_dir and stems paths.
        """
        import torch
        import torchaudio

        project_dir = Path(PROJECTS_DIR) / project_id / "stems"
        project_dir.mkdir(parents=True, exist_ok=True)
        demucs_output_root = project_dir / "_demucs_output"
        if demucs_output_root.exists():
            shutil.rmtree(demucs_output_root)

        if on_progress:
            on_progress(0.15, "Initializing Demucs model...")

        # Select device: MPS for Apple Silicon, CPU fallback
        if torch.backends.mps.is_available():
            # Older Demucs builds often don't support MPS through their public CLI.
            device = "cpu"
        elif torch.cuda.is_available():
            device = "cuda"
        else:
            device = "cpu"

        if on_progress:
            on_progress(0.2, f"Using device: {device}")

        if on_progress:
            on_progress(0.3, "Running separation...")

        command = [
            sys.executable,
            "-m",
            "demucs.separate",
            "-n",
            model_name,
            "-o",
            str(demucs_output_root),
            "-d",
            device,
            input_path,
        ]

        completed = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=False,
        )
        if completed.returncode != 0:
            error_output = (completed.stderr or completed.stdout).strip()
            raise RuntimeError(error_output or "Demucs separation failed.")

        track_output_dir = demucs_output_root / model_name / Path(input_path).stem
        if not track_output_dir.exists():
            raise RuntimeError(f"Demucs output not found at {track_output_dir}")

        if on_progress:
            on_progress(0.8, "Saving stems...")

        stem_names = ["drums", "bass", "other", "vocals"]
        stems = {}

        for stem_name in stem_names:
            source_path = track_output_dir / f"{stem_name}.wav"
            if source_path.exists():
                stem_path = project_dir / f"{stem_name}.wav"
                shutil.move(str(source_path), str(stem_path))
                stems[stem_name] = str(stem_path)

        if on_progress:
            on_progress(0.95, "Creating karaoke mix...")

        if not stems:
            raise RuntimeError("Demucs completed but no stem files were produced.")

        karaoke_path = str(project_dir / "karaoke.wav")
        instrumental = None
        sample_rate = None

        for stem_name in ["drums", "bass", "other"]:
            stem_file = stems.get(stem_name)
            if not stem_file:
                continue

            waveform, current_sample_rate = torchaudio.load(stem_file)
            if instrumental is None:
                instrumental = waveform
                sample_rate = current_sample_rate
            else:
                instrumental = instrumental + waveform

        if instrumental is None or sample_rate is None:
            raise RuntimeError("Unable to create karaoke mix from separated stems.")

        torchaudio.save(karaoke_path, instrumental, sample_rate)
        stems["karaoke"] = karaoke_path

        shutil.rmtree(demucs_output_root, ignore_errors=True)

        return {
            "output_dir": str(project_dir),
            "stems": stems,
        }
