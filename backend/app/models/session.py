"""Session models for tracking Live API connections."""

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional
from enum import Enum


class SessionState(str, Enum):
    """Possible states for a Live API session."""

    CONNECTING = "connecting"
    LISTENING = "listening"
    PROCESSING = "processing"
    RESPONDING = "responding"
    WAITING = "waiting"
    DISCONNECTED = "disconnected"


@dataclass
class BookContext:
    """Context about the book being listened to."""

    book_id: str
    title: str
    author: str
    narrator_voice: str
    current_chapter: int
    total_chapters: int
    chapter_summaries: dict[int, str] = field(default_factory=dict)

    def get_context_up_to_chapter(self, chapter: int) -> str:
        """Get summaries for chapters up to and including the given chapter."""
        summaries = []
        for ch_num in range(1, chapter + 1):
            if ch_num in self.chapter_summaries:
                summaries.append(f"Chapter {ch_num}: {self.chapter_summaries[ch_num]}")
        return "\n".join(summaries) if summaries else "No chapter summaries available."


@dataclass
class Session:
    """Represents an active Live API session."""

    session_id: str
    book_context: BookContext
    state: SessionState = SessionState.CONNECTING
    created_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    last_activity: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    questions_asked: int = 0

    def update_activity(self) -> None:
        """Update the last activity timestamp."""
        self.last_activity = datetime.now(timezone.utc)

    def increment_questions(self) -> None:
        """Increment the questions asked counter."""
        self.questions_asked += 1
        self.update_activity()

    def is_expired(self, timeout_seconds: int) -> bool:
        """Check if the session has expired."""
        elapsed = (datetime.now(timezone.utc) - self.last_activity).total_seconds()
        return elapsed > timeout_seconds
