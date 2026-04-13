"""FastAPI application for Sabhapathi Karaoke backend."""
import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .routes import health, separation, download, lyrics

app = FastAPI(title="Sabhapathi Backend", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Project storage directory
PROJECTS_DIR = os.path.expanduser(
    "~/Library/Application Support/Sabhapathi/projects"
)
os.makedirs(PROJECTS_DIR, exist_ok=True)

app.include_router(health.router, tags=["health"])
app.include_router(separation.router, prefix="/api", tags=["separation"])
app.include_router(download.router, prefix="/api", tags=["download"])
app.include_router(lyrics.router, prefix="/api", tags=["lyrics"])
