"""Lyrics routes - LRCLIB lookup and Whisper transcription."""
import uuid
import asyncio
import json
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Dict, Optional
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from ..services.whisper_service import WhisperService

router = APIRouter()
whisper_service = WhisperService()


class LRCLibRequest(BaseModel):
    title: str
    artist: str = ""
    album: str = ""
    duration: Optional[float] = None


class WhisperRequest(BaseModel):
    audio_path: str
    project_id: str


class LyricsResponse(BaseModel):
    job_id: Optional[str] = None
    status: str
    source: str = ""  # "lrclib" or "whisper"
    lrc_content: Optional[str] = None


_whisper_jobs: Dict[str, LyricsResponse] = {}


def _search_lrclib(params: Dict[str, object]) -> list[dict]:
    query = urlencode(params)
    request = Request(
        f"https://lrclib.net/api/search?{query}",
        headers={"User-Agent": "Sabhapathi Karaoke v1.0"},
    )

    with urlopen(request, timeout=10) as response:
        if response.status != 200:
            return []
        return json.loads(response.read().decode("utf-8"))


@router.post("/lyrics/search", response_model=LyricsResponse)
async def search_lyrics(request: LRCLibRequest):
    """Search LRCLIB for synced lyrics."""
    params = {"track_name": request.title}
    if request.artist:
        params["artist_name"] = request.artist
    if request.album:
        params["album_name"] = request.album
    if request.duration:
        params["duration"] = int(request.duration)

    try:
        results = await asyncio.to_thread(_search_lrclib, params)
        for item in results:
            if item.get("syncedLyrics"):
                return LyricsResponse(
                    status="found",
                    source="lrclib",
                    lrc_content=item["syncedLyrics"],
                )
        return LyricsResponse(status="not_found", source="lrclib")
    except Exception:
        return LyricsResponse(status="error", source="lrclib")


@router.post("/lyrics/transcribe", response_model=LyricsResponse)
async def transcribe_lyrics(request: WhisperRequest):
    """Transcribe vocals using Whisper and generate LRC."""
    job_id = str(uuid.uuid4())
    _whisper_jobs[job_id] = LyricsResponse(
        job_id=job_id, status="processing", source="whisper"
    )

    asyncio.create_task(_run_whisper(job_id, request.audio_path, request.project_id))

    return LyricsResponse(job_id=job_id, status="processing", source="whisper")


@router.get("/lyrics/status/{job_id}", response_model=LyricsResponse)
async def get_lyrics_status(job_id: str):
    if job_id not in _whisper_jobs:
        raise HTTPException(status_code=404, detail="Lyrics job not found")
    return _whisper_jobs[job_id]


async def _run_whisper(job_id: str, audio_path: str, project_id: str):
    try:
        lrc_content = await asyncio.to_thread(
            whisper_service.transcribe_to_lrc, audio_path, project_id
        )
        _whisper_jobs[job_id].status = "completed"
        _whisper_jobs[job_id].lrc_content = lrc_content
    except Exception as e:
        _whisper_jobs[job_id].status = "failed"
        _whisper_jobs[job_id].lrc_content = None
