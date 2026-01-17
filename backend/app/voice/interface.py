from abc import ABC, abstractmethod
from typing import Any, Dict, Optional

class VoiceOrchestrator(ABC):
    """Abstract interface for Voice AI orchestration platforms (LiveKit, Pipecat, etc)."""

    @abstractmethod
    def generate_token(
        self, 
        room_name: str, 
        participant_identity: str, 
        participant_name: str, 
        metadata: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Generate a session token/credentials for the client.
        
        Returns:
            Dict containing 'token', 'url', and other connection details.
        """
        pass
