#!/usr/bin/env bash
# One-shot setup for Sabhapathi's Python dependencies on a recipient's Mac.
# Creates a virtualenv at ~/Library/Application Support/Sabhapathi/python_env
# and installs demucs + openai-whisper into it. The app looks there first.
set -euo pipefail

ENV_DIR="$HOME/Library/Application Support/Sabhapathi/python_env"

if [ -d "$ENV_DIR" ]; then
  echo "Existing environment at:"
  echo "  $ENV_DIR"
  echo
  read -r -p "Delete and reinstall? [y/N] " answer
  case "$answer" in
    [yY][eE][sS]|[yY]) rm -rf "$ENV_DIR" ;;
    *) echo "Leaving existing env in place. Exiting."; exit 0 ;;
  esac
fi

PYTHON_BIN=""
for candidate in python3.11 python3.10 python3.9 python3; do
  if command -v "$candidate" >/dev/null 2>&1; then
    version=$("$candidate" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "0.0")
    major=${version%%.*}
    minor=${version##*.}
    if [ "$major" -ge 3 ] && [ "$minor" -ge 9 ]; then
      PYTHON_BIN="$(command -v "$candidate")"
      break
    fi
  fi
done

if [ -z "$PYTHON_BIN" ]; then
  cat >&2 <<'ERR'
No suitable Python found. Install Python 3.9+ first:

  brew install python@3.11

Then rerun this script.
ERR
  exit 1
fi

echo "Creating virtualenv at:"
echo "  $ENV_DIR"
echo "using $PYTHON_BIN"
mkdir -p "$(dirname "$ENV_DIR")"
"$PYTHON_BIN" -m venv "$ENV_DIR"

# shellcheck disable=SC1091
"$ENV_DIR/bin/pip" install --upgrade pip wheel

echo "Installing demucs (vocal separation)..."
"$ENV_DIR/bin/pip" install \
  "demucs==4.0.1" \
  "torch==2.8.0" \
  "torchaudio==2.8.0"

echo "Installing whisper (lyrics transcription)..."
"$ENV_DIR/bin/pip" install "openai-whisper"

cat <<DONE

Done. Sabhapathi will use:
  $ENV_DIR/bin/python3

First separation will download the htdemucs model (~300MB) to
~/.cache/torch/hub/checkpoints. First transcription downloads the
Whisper base model (~140MB).
DONE
