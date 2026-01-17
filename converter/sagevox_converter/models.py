"""Data models for SageVox Converter."""

from dataclasses import dataclass, field
from typing import Optional
import json
from pathlib import Path


@dataclass
class Chapter:
    """Represents a single chapter in a book."""
    number: int
    title: str
    text_content: str
    audio_file: Optional[str] = None
    transcript_file: Optional[str] = None  # JSON with word-level timestamps
    duration_seconds: float = 0.0
    
    def to_dict(self) -> dict:
        return {
            "number": self.number,
            "title": self.title,
            "audio_file": self.audio_file,
            "transcript_file": self.transcript_file,
            "duration_seconds": round(self.duration_seconds, 2),
        }


@dataclass
class BookMetadata:
    """Metadata for a converted audiobook."""
    id: str
    title: str
    author: str
    description: str = ""
    narrator_voice: str = "Kore"
    language_code: str = "en-US"
    cover_image: Optional[str] = None
    total_chapters: int = 0
    total_duration_seconds: float = 0.0
    chapters: list[Chapter] = field(default_factory=list)
    
    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "title": self.title,
            "author": self.author,
            "description": self.description,
            "narrator_voice": self.narrator_voice,
            "language_code": self.language_code,
            "cover_image": self.cover_image,
            "total_chapters": self.total_chapters,
            "total_duration_seconds": round(self.total_duration_seconds, 2),
            "chapters": [ch.to_dict() for ch in self.chapters],
        }
    
    def save(self, output_dir: Path) -> None:
        """Save metadata to JSON file."""
        metadata_path = output_dir / "metadata.json"
        with open(metadata_path, "w", encoding="utf-8") as f:
            json.dump(self.to_dict(), f, indent=2, ensure_ascii=False)
    
    @classmethod
    def load(cls, metadata_path: Path) -> "BookMetadata":
        """Load metadata from JSON file."""
        with open(metadata_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        
        chapters = [
            Chapter(
                number=ch["number"],
                title=ch["title"],
                text_content="",
                audio_file=ch.get("audio_file"),
                transcript_file=ch.get("transcript_file"),
                duration_seconds=ch.get("duration_seconds", 0.0),
            )
            for ch in data.get("chapters", [])
        ]
        
        return cls(
            id=data["id"],
            title=data["title"],
            author=data["author"],
            description=data.get("description", ""),
            narrator_voice=data.get("narrator_voice", "Kore"),
            language_code=data.get("language_code", "en-US"),
            cover_image=data.get("cover_image"),
            total_chapters=data.get("total_chapters", len(chapters)),
            total_duration_seconds=data.get("total_duration_seconds", 0.0),
            chapters=chapters,
        )
