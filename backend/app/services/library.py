"""Service for loading book data from the file system."""

import json
import logging
from pathlib import Path
from typing import Optional

from pydantic import ValidationError

from ..config import get_settings
from ..models.book import (
    Book,
    BookMetadata,
    Chapter,
    Transcript,
)

logger = logging.getLogger(__name__)


def get_books_dir() -> Path:
    """Get the books directory path."""
    settings = get_settings()
    return settings.books_dir


def resolve_book_dir(book_id: str) -> Path | None:
    """Resolve and validate a book directory path."""
    if not book_id or "/" in book_id or "\\" in book_id or ".." in book_id:
        logger.warning(f"Invalid book_id received: {book_id}")
        return None

    books_dir = get_books_dir().resolve()
    candidate = (books_dir / book_id).resolve()

    try:
        candidate.relative_to(books_dir)
    except ValueError:
        logger.warning(f"Rejected book_id outside books directory: {book_id}")
        return None

    return candidate


def load_book_metadata(book_dir: Path) -> BookMetadata | None:
    """Load book metadata from a directory."""
    metadata_path = book_dir / "metadata.json"
    if not metadata_path.exists():
        return None

    try:
        with open(metadata_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return BookMetadata(**data)
    except json.JSONDecodeError as e:
        logger.error(f"Invalid metadata JSON in {metadata_path}: {e}")
        return None
    except ValidationError as e:
        logger.error(f"Metadata validation failed for {metadata_path}: {e}")
        return None
    except Exception as e:
        logger.error(f"Failed to load metadata from {metadata_path}: {e}")
        return None


def load_transcript(book_dir: Path, transcript_file: str) -> Transcript | None:
    """Load a transcript file."""
    transcript_path = book_dir / transcript_file
    if not transcript_path.exists():
        logger.warning(f"Transcript file not found: {transcript_path}")
        return None

    try:
        with open(transcript_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return Transcript(**data)
    except json.JSONDecodeError as e:
        logger.error(f"Invalid transcript JSON in {transcript_path}: {e}")
        return None
    except ValidationError as e:
        logger.error(f"Transcript validation failed for {transcript_path}: {e}")
        return None
    except Exception as e:
        logger.error(f"Failed to load transcript from {transcript_path}: {e}")
        return None


def get_book_with_chapters(book_id: str) -> Book | None:
    """Get full book object with all chapters and transcripts loaded."""
    book_dir = resolve_book_dir(book_id)

    if book_dir is None or not book_dir.exists():
        return None

    metadata = load_book_metadata(book_dir)
    if metadata is None:
        return None

    # Build chapters with embedded transcripts
    chapters: list[Chapter] = []
    for ch_meta in metadata.chapters:
        # Load transcript if available
        transcript = None
        if ch_meta.transcript_file:
            transcript = load_transcript(book_dir, ch_meta.transcript_file)

        chapters.append(
            Chapter(
                number=ch_meta.number,
                title=ch_meta.title,
                audio_file=ch_meta.audio_file,
                duration_seconds=ch_meta.duration_seconds,
                transcript=transcript,
            )
        )

    return Book(
        id=metadata.id,
        title=metadata.title,
        author=metadata.author,
        description=metadata.description,
        narrator_voice=metadata.narrator_voice,
        language_code=metadata.language_code,
        cover_image=metadata.cover_image,
        total_chapters=metadata.total_chapters,
        total_duration_seconds=metadata.total_duration_seconds,
        chapters=chapters,
    )
