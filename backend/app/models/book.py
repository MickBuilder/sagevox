"""Pydantic models for Book and Chapter data."""

from pydantic import BaseModel


class TranscriptSegment(BaseModel):
    """A segment of text with timing information."""
    text: str
    start: float
    end: float


class Transcript(BaseModel):
    """Transcript with sentence-level timestamps."""
    text: str
    duration: float
    segments: list[TranscriptSegment]


class ChapterMetadata(BaseModel):
    """Chapter as stored in metadata.json (without transcript)."""
    number: int
    title: str
    audio_file: str | None = None
    transcript_file: str | None = None
    duration_seconds: float = 0.0


class Chapter(BaseModel):
    """Chapter with embedded transcript for API response."""
    number: int
    title: str
    audio_file: str | None = None
    duration_seconds: float = 0.0
    transcript: Transcript | None = None


class BookMetadata(BaseModel):
    """Book metadata as stored in metadata.json."""
    id: str
    title: str
    author: str
    description: str = ""
    narrator_voice: str = "Kore"
    language_code: str = "en-US"
    cover_image: str | None = None
    total_chapters: int = 0
    total_duration_seconds: float = 0.0
    chapters: list[ChapterMetadata] = []


class Book(BaseModel):
    """Full book with embedded transcripts for API response."""
    id: str
    title: str
    author: str
    description: str = ""
    narrator_voice: str = "Kore"
    language_code: str = "en-US"
    cover_image: str | None = None
    total_chapters: int = 0
    total_duration_seconds: float = 0.0
    chapters: list[Chapter] = []


class BookSummary(BaseModel):
    """Lightweight book info for library listing."""
    id: str
    title: str
    author: str
    description: str
    cover_url: str | None = None
    total_chapters: int
    total_duration_seconds: float
