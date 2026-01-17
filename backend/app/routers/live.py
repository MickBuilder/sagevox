"""LiveKit Token Minting API."""

import logging
import uuid
from typing import Optional

from fastapi import APIRouter, Query

from ..config import get_settings
from ..voice.factory import get_voice_orchestrator

router = APIRouter(prefix="/engage", tags=["live"])
logger = logging.getLogger(__name__)


@router.get("/token")
async def get_token(
    book_id: str = Query(..., description="ID of the book for the room name"),
    participant_name: str = Query(..., description="Name of the participant"),
    title: Optional[str] = None,
    voice: Optional[str] = None,
) -> dict[str, str]:
    """
    Mint an Access Token for the iOS client.
    Context is sent via data channel, not metadata.
    """
    settings = get_settings()
    orchestrator = get_voice_orchestrator()

    # Make room name unique per session to allow reconnections
    session_id = uuid.uuid4().hex[:8]
    room_name = f"book-{book_id}-{session_id}"
    identity = f"user-{uuid.uuid4().hex[:8]}"

    logger.info(f"Creating new session: room={room_name}, book={book_id}")

    # Minimal metadata - just for greeting. Context sent via data channel.
    metadata = {
        "book_title": title or "",
        "narrator_voice": voice or settings.default_voice,
    }

    # Generate token using the abstract orchestrator
    connection_details = orchestrator.generate_token(
        room_name=room_name,
        participant_identity=identity,
        participant_name=participant_name,
        metadata=metadata,
    )

    return connection_details
