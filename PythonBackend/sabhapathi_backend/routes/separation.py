"""Vocal separation routes."""
import uuid
import asyncio
from pathlib import Path
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Dict, Optional

from ..services.demucs_service import DemucsService

router = APIRouter()
demucs_service = DemucsService()


class SeparationRequest(BaseModel):
    input_path: str
    project_id: str
    model: str = "htdemucs"


class SeparationResponse(BaseModel):
    job_id: str
    status: str


class JobStatus(BaseModel):
    job_id: str
    status: str  # "queued", "processing", "completed", "failed"
    progress: float  # 0.0 - 1.0
    message: str = ""
    output_dir: Optional[str] = None
    stems: Optional[Dict[str, str]] = None


# In-memory job tracking
_jobs: Dict[str, JobStatus] = {}


@router.post("/separate", response_model=SeparationResponse)
async def start_separation(request: SeparationRequest):
    input_path = Path(request.input_path)
    if not input_path.exists():
        raise HTTPException(status_code=404, detail="Input file not found")

    job_id = str(uuid.uuid4())
    _jobs[job_id] = JobStatus(
        job_id=job_id, status="queued", progress=0.0, message="Queued for processing"
    )

    asyncio.create_task(
        _run_separation(job_id, str(input_path), request.project_id, request.model)
    )

    return SeparationResponse(job_id=job_id, status="queued")


@router.get("/status/{job_id}", response_model=JobStatus)
async def get_job_status(job_id: str):
    if job_id not in _jobs:
        raise HTTPException(status_code=404, detail="Job not found")
    return _jobs[job_id]


async def _run_separation(
    job_id: str, input_path: str, project_id: str, model: str
):
    try:
        _jobs[job_id].status = "processing"
        _jobs[job_id].progress = 0.1
        _jobs[job_id].message = "Loading model..."

        def on_progress(progress: float, message: str):
            _jobs[job_id].progress = progress
            _jobs[job_id].message = message

        result = await asyncio.to_thread(
            demucs_service.separate, input_path, project_id, model, on_progress
        )

        _jobs[job_id].status = "completed"
        _jobs[job_id].progress = 1.0
        _jobs[job_id].message = "Separation complete"
        _jobs[job_id].output_dir = result["output_dir"]
        _jobs[job_id].stems = result["stems"]

    except Exception as e:
        _jobs[job_id].status = "failed"
        _jobs[job_id].message = str(e)
