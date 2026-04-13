"""YouTube download routes."""
import uuid
import asyncio
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Dict, Optional

from ..services.ytdlp_service import YtDlpService

router = APIRouter()
ytdlp_service = YtDlpService()


class DownloadRequest(BaseModel):
    url: str
    project_id: str


class DownloadResponse(BaseModel):
    job_id: str
    status: str


class DownloadStatus(BaseModel):
    job_id: str
    status: str
    progress: float
    message: str = ""
    title: Optional[str] = None
    output_path: Optional[str] = None


_download_jobs: Dict[str, DownloadStatus] = {}


@router.post("/download", response_model=DownloadResponse)
async def start_download(request: DownloadRequest):
    job_id = str(uuid.uuid4())
    _download_jobs[job_id] = DownloadStatus(
        job_id=job_id, status="queued", progress=0.0, message="Queued for download"
    )

    asyncio.create_task(_run_download(job_id, request.url, request.project_id))

    return DownloadResponse(job_id=job_id, status="queued")


@router.get("/download/status/{job_id}", response_model=DownloadStatus)
async def get_download_status(job_id: str):
    if job_id not in _download_jobs:
        raise HTTPException(status_code=404, detail="Download job not found")
    return _download_jobs[job_id]


async def _run_download(job_id: str, url: str, project_id: str):
    try:
        _download_jobs[job_id].status = "processing"
        _download_jobs[job_id].progress = 0.1
        _download_jobs[job_id].message = "Starting download..."

        def on_progress(progress: float, message: str):
            _download_jobs[job_id].progress = progress
            _download_jobs[job_id].message = message

        result = await asyncio.to_thread(
            ytdlp_service.download, url, project_id, on_progress
        )

        _download_jobs[job_id].status = "completed"
        _download_jobs[job_id].progress = 1.0
        _download_jobs[job_id].message = "Download complete"
        _download_jobs[job_id].title = result["title"]
        _download_jobs[job_id].output_path = result["output_path"]

    except Exception as e:
        _download_jobs[job_id].status = "failed"
        _download_jobs[job_id].message = str(e)
