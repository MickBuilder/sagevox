import json
import logging
import asyncio
from typing import Any, Literal

from dotenv import load_dotenv
from livekit import rtc
from livekit.agents import (
    AutoSubscribe,
    JobContext,
    WorkerOptions,
    cli,
    llm,
    room_io,
    function_tool,
    RunContext,
)
from livekit.agents.voice import Agent, AgentSession
from livekit.plugins import google, noise_cancellation, silero
from livekit.plugins.turn_detector.multilingual import MultilingualModel
from pydantic import BaseModel, ValidationError


# Import local services
from app.voice.prompt import SYSTEM_PROMPT

load_dotenv()

logger = logging.getLogger("sagevox-agent")


class ContextUpdateMessage(BaseModel):
    """Schema for context update messages from the client."""

    type: Literal["context_update"]
    context: dict[str, Any]


class SageVoxAgent(Agent):
    """Custom agent with tools for patient conversations and playback control."""

    def __init__(self, instructions: str, book_title: str = "", room: rtc.Room | None = None):
        super().__init__(instructions=instructions)
        self.book_title = book_title
        self.room = room
        # Store dynamic context received from iOS - updated per interaction
        self.current_context: dict[str, Any] = {}

    def update_context(self, context: dict):
        """Update the current context from iOS client."""
        self.current_context = context
        logger.info(
            f"Context updated: book={context.get('bookInfo', {}).get('title', 'unknown')}, "
            f"chapter={context.get('audioPosition', {}).get('chapter', '?')}"
        )

    async def _send_command(self, command: str, data: dict[str, Any] | None = None) -> None:
        """Send a command to the iOS client via data channel."""
        if self.room and self.room.local_participant:
            payload = json.dumps({"command": command, "data": data or {}}).encode()
            await self.room.local_participant.publish_data(payload, reliable=True)
            logger.info(f"Sent command to client: {command}")

    @function_tool()
    async def get_current_context(self, context: RunContext) -> str:
        """Get the current book context to help answer the user's question.
        Call this tool to understand what the user is currently listening to.
        """
        if not self.current_context:
            return "No context available yet. Ask the user what book they're listening to."

        ctx = self.current_context
        book_info = ctx.get("bookInfo", {})
        audio_pos = ctx.get("audioPosition", {})
        system_instruction = ctx.get("systemInstruction", "")

        return f"""Current listening context:
Book: {book_info.get("title", "Unknown")} by {book_info.get("author", "Unknown")}
Description: {book_info.get("description", "N/A")}
Current Chapter: {audio_pos.get("chapter", "?")} of {book_info.get("chapters", "?")}
Time Position: {audio_pos.get("timeOffset", 0):.1f} seconds

Current text context:
{system_instruction}
"""

    @function_tool()
    async def wait_more(self, context: RunContext) -> str:
        """Use this tool when the user seems to be thinking, pausing, or hasn't finished their thought.
        Signs to wait: 'hmm', 'let me think', long pauses, incomplete sentences.
        This makes you more patient and gives the user time to complete their thought.
        """
        logger.info("wait_more tool called - giving user more time to think")
        return "I'm listening, take your time."

    @function_tool()
    async def stop_and_resume_book(self, context: RunContext) -> str:
        """Use this when the user wants to stop talking and continue listening to the book.
        Trigger words: 'stop', 'that's all', 'thanks', 'bye', 'continue reading', 'go back to the book', 'resume', 'I'm done'
        """
        logger.info("stop_and_resume_book tool called")
        await asyncio.sleep(0.5)
        await self._send_command("resume_playback")
        return ""

    @function_tool()
    async def skip_back(self, context: RunContext, seconds: int = 30) -> str:
        """Use this when the user wants to go back in the audiobook.
        Trigger words: 'go back', 'rewind', 'skip back', 'replay that part'

        Args:
            seconds: Number of seconds to skip back (default 30)
        """
        logger.info(f"skip_back tool called: {seconds}s")
        await self._send_command("skip_back", {"seconds": seconds})
        return f"Going back {seconds} seconds."

    @function_tool()
    async def skip_forward(self, context: RunContext, seconds: int = 30) -> str:
        """Use this when the user wants to skip forward in the audiobook.
        Trigger words: 'skip', 'skip ahead', 'fast forward'

        Args:
            seconds: Number of seconds to skip forward (default 30)
        """
        logger.info(f"skip_forward tool called: {seconds}s")
        await self._send_command("skip_forward", {"seconds": seconds})
        return f"Skipping ahead {seconds} seconds."

    @function_tool()
    async def go_to_chapter(self, context: RunContext, chapter_number: int) -> str:
        """Use this when the user wants to jump to a specific chapter.
        Only for chapters they've already listened to.

        Args:
            chapter_number: The chapter number to jump to
        """
        logger.info(f"go_to_chapter tool called: chapter {chapter_number}")
        await self._send_command("go_to_chapter", {"chapter": chapter_number})
        return f"Jumping to chapter {chapter_number}."


async def entrypoint(ctx: JobContext):
    """Main agent logic entrypoint."""
    logger.info(f"connecting to room {ctx.room.name}")
    await ctx.connect(auto_subscribe=AutoSubscribe.AUDIO_ONLY)

    # Wait for participant to join
    participant = await ctx.wait_for_participant()
    logger.info(f"Participant joined: {participant.identity}")

    # Get basic metadata (book_title for greeting only)
    metadata = participant.metadata
    book_title = ""
    narrator_voice = "Kore"

    if metadata:
        try:
            meta_dict = json.loads(metadata)
            if not isinstance(meta_dict, dict):
                raise ValueError("Metadata must be a JSON object")
            book_title = str(meta_dict.get("book_title", ""))
            narrator_voice = str(meta_dict.get("narrator_voice", "Kore"))
            if narrator_voice not in ["Puck", "Charon", "Kore", "Fenrir", "Aoede"]:
                narrator_voice = "Kore"
            logger.info(f"Parsed metadata: book_title={book_title}, voice={narrator_voice}")
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse metadata JSON: {e}")
        except (ValueError, TypeError) as e:
            logger.error(f"Invalid metadata format: {e}")

    logger.info(f"Starting voice agent with FIXED system prompt")

    # Load VAD model
    vad = silero.VAD.load()

    # Create agent with FIXED system prompt - NEVER changes!
    agent = SageVoxAgent(
        instructions=SYSTEM_PROMPT,
        book_title=book_title,
        room=ctx.room,
    )

    # Create the agent session with FIXED system instruction
    session = AgentSession(
        vad=vad,
        turn_detection=MultilingualModel(),
        llm=google.realtime.RealtimeModel(
            model="gemini-2.5-flash-native-audio-preview-12-2025",
            voice=narrator_voice,
            temperature=0.7,
            instructions=SYSTEM_PROMPT,  # FIXED - never changes!
        ),
        min_endpointing_delay=0.8,
        max_endpointing_delay=8.0,
        allow_interruptions=True,
        min_interruption_duration=0.5,
    )

    # Listen for data channel messages (context updates from iOS)
    @ctx.room.on("data_received")
    def on_data_received(data: rtc.DataPacket):
        try:
            payload = data.data.decode("utf-8")
            message = ContextUpdateMessage.model_validate_json(payload)
        except UnicodeDecodeError as exc:
            logger.warning(f"Invalid data channel payload encoding: {exc}")
            return
        except ValidationError as exc:
            logger.warning(f"Invalid data channel payload schema: {exc}")
            return

        # iOS sent updated context for the current interaction
        agent.update_context(message.context)
        logger.info("Received context update from iOS")

    # Start the session
    await session.start(
        room=ctx.room,
        agent=agent,
        room_options=room_io.RoomOptions(
            audio_input=room_io.AudioInputOptions(
                noise_cancellation=lambda params: noise_cancellation.BVCTelephony()
                if params.participant.kind == rtc.ParticipantKind.PARTICIPANT_KIND_SIP
                else noise_cancellation.BVC(),
            ),
        ),
    )

    # Initial greeting
    greeting = (
        f"Hey! I'm SageVox, your companion for {book_title}. What would you like to know?"
        if book_title
        else "Hey! I'm SageVox, your audiobook companion. What would you like to know?"
    )
    await session.generate_reply(instructions=f"Say exactly: '{greeting}'")


if __name__ == "__main__":
    cli.run_app(
        WorkerOptions(
            entrypoint_fnc=entrypoint,
        ),
    )
