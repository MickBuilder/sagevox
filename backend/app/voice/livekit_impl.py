import logging
from typing import Any, Dict

from livekit import api

from ..config import get_settings
from .interface import VoiceOrchestrator

logger = logging.getLogger(__name__)


class LiveKitOrchestrator(VoiceOrchestrator):
    """LiveKit implementation of VoiceOrchestrator."""

    def __init__(self) -> None:
        self.settings = get_settings()

    def generate_token(
        self,
        room_name: str,
        participant_identity: str,
        participant_name: str,
        metadata: Dict[str, Any],
    ) -> Dict[str, Any]:
        # Create the token
        token = api.AccessToken(self.settings.livekit_api_key, self.settings.livekit_api_secret)

        # Set permissions
        token.with_identity(participant_identity).with_name(participant_name).with_grants(
            api.VideoGrants(
                room_join=True,
                room=room_name,
                can_publish=True,
                can_subscribe=True,
            )
        )

        # Convert metadata to string as LiveKit expects string metadata
        # We explicitly support string conversion for the dict
        token.with_metadata(str(metadata))

        jwt = token.to_jwt()

        logger.info(f"Minted LiveKit token for room {room_name}, user {participant_identity}")

        return {
            "token": jwt,
            "url": self.settings.livekit_url,
            "room": room_name,
            "identity": participant_identity,
            # Return provider type so client knows how to handle it if we switch
            "provider": "livekit",
        }
