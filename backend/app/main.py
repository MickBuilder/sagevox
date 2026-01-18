"""SageVox Backend - Main FastAPI application."""

import logging
from contextlib import asynccontextmanager
from typing import AsyncGenerator

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from .config import get_settings
from .routers import live, books

settings = get_settings()

# Configure logging
logging.basicConfig(
    level=logging.DEBUG if settings.debug else logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """Application lifespan handler."""
    settings = get_settings()
    logger.info(f"Starting SageVox Backend")

    logger.info(f"Gemini Live Model: {settings.gemini_live_model}")
    logger.info(f"Books directory: {settings.books_dir}")
    logger.info(f"Books directory exists: {settings.books_dir.exists()}")

    # Log all registered routes for debugging
    routes = [f"{route.methods} {route.path}" for route in app.routes if hasattr(route, 'methods')]
    logger.info(f"Registered routes: {routes}")

    yield
    logger.info("Shutting down SageVox Backend")


# Create FastAPI application
app = FastAPI(
    title="SageVox Backend",
    description="WebSocket proxy for Gemini Live API - Interactive audiobook Q&A",
    version="0.1.0",
    lifespan=lifespan,
)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_allow_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(live.router)
app.include_router(books.router)

# Mount books directory for static file serving (audio, covers)
# StaticFiles automatically handles HTTP Range requests for streaming
if settings.books_dir.exists():
    app.mount("/books", StaticFiles(directory=settings.books_dir), name="books_static")


@app.get("/")
async def root() -> dict[str, str]:
    """Root endpoint."""
    return {
        "name": "SageVox Backend",
        "version": "0.1.0",
        "status": "running",
    }


@app.get("/health")
async def health_check() -> dict[str, str]:
    """Health check endpoint."""
    settings = get_settings()
    return {
        "status": "healthy",
        "model": settings.gemini_live_model,
        "default_voice": settings.default_voice,
    }


if __name__ == "__main__":
    import uvicorn

    settings = get_settings()
    uvicorn.run(
        "app.main:app",
        host=settings.host,
        port=settings.port,
        reload=settings.debug,
        # WebSocket keepalive settings - increase timeouts for long audio streaming
        ws_ping_interval=60.0,  # Send ping every 60 seconds (default: 20)
        ws_ping_timeout=60.0,  # Wait 60 seconds for pong (default: 20)
    )
