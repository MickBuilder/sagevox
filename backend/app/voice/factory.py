from functools import lru_cache

from .interface import VoiceOrchestrator
from .livekit_impl import LiveKitOrchestrator

# We can use an env var or settings to switch implementations later
CURRENT_PROVIDER = "livekit"

@lru_cache
def get_voice_orchestrator() -> VoiceOrchestrator:
    """Factory to get the configured VoiceOrchestrator instance."""
    if CURRENT_PROVIDER == "livekit":
        return LiveKitOrchestrator()
    else:
        # Fallback or error for unknown provider
        raise ValueError(f"Unknown voice provider: {CURRENT_PROVIDER}")
