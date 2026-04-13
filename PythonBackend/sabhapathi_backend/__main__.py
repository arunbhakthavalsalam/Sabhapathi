"""Entry point for the Sabhapathi backend server."""
import uvicorn

if __name__ == "__main__":
    uvicorn.run(
        "sabhapathi_backend.server:app",
        host="127.0.0.1",
        port=9457,
        reload=False,
        log_level="info",
    )
