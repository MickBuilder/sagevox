"""Configuration management for SageVox Backend."""

from functools import lru_cache
from pathlib import Path
from typing import Optional

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # Server settings
    host: str = "0.0.0.0"
    port: int = 8000
    debug: bool = False
    cors_allow_origins: list[str] = ["http://localhost:3000"]

    # Google API Key (required)
    google_api_key: str

    # Gemini Live API settings
    gemini_api_version: str = "v1alpha"  # Required for affective dialog and proactive audio
    gemini_live_model: str = "gemini-2.5-flash-native-audio-preview-12-2025"
    default_voice: str = "Kore"

    # LiveKit
    livekit_url: str
    livekit_api_key: str
    livekit_api_secret: str
    default_language: str = "en-US"

    # Session settings
    session_timeout_seconds: int = 300  # 5 minutes
    max_concurrent_sessions: int = 100

    # Books storage directory
    books_dir: Path = Path(__file__).parent.parent / "books"


@lru_cache
def get_settings() -> Settings:
    """Get cached application settings."""
    return Settings()
