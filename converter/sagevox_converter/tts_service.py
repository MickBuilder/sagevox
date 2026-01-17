"""Gemini TTS service for audiobook generation with sentence-level timestamps."""

import os
import wave
import json
import base64
from pathlib import Path
from typing import Optional
from dataclasses import dataclass

from google import genai
from google.genai import types

from .models import Chapter


# Maximum characters per TTS request
MAX_CHUNK_CHARS = 4000

# Narrator style presets for different audiobook experiences
NARRATOR_STYLES = {
    "classic": """# AUDIO PROFILE: The Classic Narrator
## "The Storyteller"

## The Scene
A warm, wood-paneled recording studio with soft ambient lighting. 
The narrator sits in a comfortable chair, speaking as if sharing 
a beloved story with a close friend by the fireside.

### DIRECTOR'S NOTES
* **Pace:** Measured and unhurried. Allow the story to breathe.
* **Breathing:** Natural pauses at paragraph breaks. Audible but soft inhales.
* **Dynamics:** Gentle rises and falls. Never rushed, never monotone.
* **Articulation:** Clear but warm. Not clinical or robotic.
* **Consistency:** Maintain the same tempo throughout. Do not accelerate.

### PERFORMANCE NOTES
Read as if you have all the time in the world. Let each sentence 
land before moving to the next. The listener is not in a hurry.""",

    "dramatic": """# AUDIO PROFILE: The Dramatic Narrator
## "The Theater Performer"

## The Scene
A darkened stage with a single spotlight. The narrator commands 
attention, drawing listeners into every twist and emotional beat 
of the story with theatrical gravitas.

### DIRECTOR'S NOTES
* **Pace:** Varied and purposeful. Slow for tension, quicker for action.
* **Breathing:** Dramatic pauses for effect. Let silence build anticipation.
* **Dynamics:** Bold contrasts. Whispers to crescendos as the story demands.
* **Articulation:** Precise and expressive. Every word has weight.
* **Emotion:** Fully inhabit the emotional landscape of each scene.

### PERFORMANCE NOTES
This is a performance, not just a reading. Let the drama unfold 
through your voice. Engage the listener's emotions at every turn.""",

    "calm": """# AUDIO PROFILE: The Calm Narrator
## "The Meditation Guide"

## The Scene
A peaceful sanctuary bathed in soft natural light. The narrator 
speaks with serene composure, creating a soothing listening 
experience perfect for relaxation or bedtime.

### DIRECTOR'S NOTES
* **Pace:** Slow and steady. Never hurried. Embrace silence.
* **Breathing:** Deep, visible breaths. Calming and rhythmic.
* **Dynamics:** Minimal variation. Maintain a gentle, even tone.
* **Articulation:** Soft and flowing. Words melt into one another.
* **Energy:** Low and peaceful. This is a lullaby, not a lecture.

### PERFORMANCE NOTES
Imagine the listener is drifting off to sleep. Your voice should 
comfort and soothe. Never jar or startle. Pure tranquility.""",

    "energetic": """# AUDIO PROFILE: The Energetic Narrator
## "The Enthusiast"

## The Scene
A bright, modern studio with an engaged, attentive audience. 
The narrator radiates enthusiasm and keeps listeners hooked 
with infectious energy and dynamic delivery.

### DIRECTOR'S NOTES
* **Pace:** Brisk but clear. Keep momentum without sacrificing clarity.
* **Breathing:** Quick, energetic breaths. Ready for the next beat.
* **Dynamics:** Lively variation. Punchy emphasis on key moments.
* **Articulation:** Crisp and engaging. Every word pops.
* **Enthusiasm:** Genuine excitement for the material.

### PERFORMANCE NOTES
You love this story and want to share that excitement. Keep 
listeners on the edge of their seats with your infectious energy.""",
}


@dataclass
class Segment:
    """A segment of text with its timing."""
    text: str
    start: float
    end: float
    
    def to_dict(self) -> dict:
        return {
            "text": self.text,
            "start": round(self.start, 3),
            "end": round(self.end, 3),
        }


@dataclass 
class TranscriptData:
    """Transcript with segment-level timestamps."""
    text: str
    duration: float
    segments: list[Segment]
    
    def to_dict(self) -> dict:
        return {
            "text": self.text,
            "duration": round(self.duration, 2),
            "segments": [s.to_dict() for s in self.segments],
        }
    
    def save(self, path: Path) -> None:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(self.to_dict(), f, indent=2, ensure_ascii=False)


class GeminiTTSService:
    """Service for generating audiobook audio using Gemini TTS with API key."""
    
    AVAILABLE_VOICES = [
        "Zephyr", "Puck", "Charon", "Kore", "Fenrir", "Aoede",
        "Leda", "Orus", "Autonoe", "Enceladus", "Iapetus", "Umbriel",
        "Algieba", "Despina", "Erinome", "Algenib", "Rasalgethi",
        "Laomedeia", "Achernar", "Alnilam", "Schedar", "Gacrux",
        "Pulcherrima", "Achird", "Zubenelgenubi", "Vindemiatrix",
        "Sadachbia", "Sadaltager", "Sulafat",
    ]
    
    def __init__(
        self,
        voice: str = "Kore",
        language_code: str = "en-US",
        api_key: Optional[str] = None,
    ):
        self.voice = voice
        self.language_code = language_code
        
        self.api_key = api_key or os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
        if not self.api_key:
            raise ValueError("Gemini API key required. Set GEMINI_API_KEY environment variable.")
        
        self.client = genai.Client(api_key=self.api_key)
    
    def _split_into_sentences(self, text: str) -> list[str]:
        """Split text into sentences."""
        import re
        # Split on sentence endings, keeping the punctuation
        sentences = re.split(r'(?<=[.!?])\s+', text)
        return [s.strip() for s in sentences if s.strip()]
    
    def _chunk_sentences(self, sentences: list[str]) -> list[list[str]]:
        """Group sentences into chunks that fit API limits."""
        chunks = []
        current_chunk = []
        current_length = 0
        
        for sentence in sentences:
            sentence_len = len(sentence)
            
            if current_length + sentence_len + 1 > MAX_CHUNK_CHARS:
                if current_chunk:
                    chunks.append(current_chunk)
                current_chunk = [sentence]
                current_length = sentence_len
            else:
                current_chunk.append(sentence)
                current_length += sentence_len + 1
        
        if current_chunk:
            chunks.append(current_chunk)
        
        return chunks
    
    # Consistency reminder for subsequent chunks to prevent pacing drift
    CONSISTENCY_REMINDER = """[Continue with the same measured pace, warm tone, and natural breathing as before. Do not speed up. Maintain consistent tempo.]

"""
    
    def _generate_audio(self, text: str, chunk_index: int = 0, style_prompt: str = "") -> bytes:
        """Generate audio for text chunk.
        
        Args:
            text: The text to synthesize
            chunk_index: Index of this chunk (0 = first, gets full style prompt)
            style_prompt: The full narrator style prompt
        """
        if chunk_index == 0 and style_prompt:
            # First chunk gets full style prompt
            full_text = f"{style_prompt}\n\n{text}"
        elif chunk_index > 0:
            # Subsequent chunks get consistency reminder
            full_text = f"{self.CONSISTENCY_REMINDER}{text}"
        else:
            full_text = text
        
        speech_config = types.SpeechConfig(
            voice_config=types.VoiceConfig(
                prebuilt_voice_config=types.PrebuiltVoiceConfig(
                    voice_name=self.voice,
                )
            )
        )
        
        response = self.client.models.generate_content(
            model="gemini-2.5-flash-preview-tts",
            contents=full_text,
            config=types.GenerateContentConfig(
                response_modalities=["AUDIO"],
                speech_config=speech_config,
            ),
        )
        
        audio_data = b""
        if response.candidates and response.candidates[0].content.parts:
            for part in response.candidates[0].content.parts:
                if hasattr(part, 'inline_data') and part.inline_data:
                    data = part.inline_data.data
                    if isinstance(data, str):
                        data = base64.b64decode(data)
                    audio_data += data
        
        return audio_data
    
    def _audio_duration(self, audio_bytes: bytes) -> float:
        """Calculate duration from PCM audio bytes (24kHz, 16-bit, mono)."""
        return len(audio_bytes) / (24000 * 2)
    
    def synthesize_chapter(
        self,
        chapter: Chapter,
        output_dir: Path,
        style_prompt: Optional[str] = None,
        narrator_style: str = "classic",
    ) -> tuple[str, float, TranscriptData]:
        """Synthesize audio for a chapter with sentence-level timestamps.
        
        Args:
            chapter: The chapter to synthesize
            output_dir: Directory to save output files
            style_prompt: Custom style prompt (overrides narrator_style)
            narrator_style: Preset narrator style: "classic", "dramatic", "calm", "energetic"
        
        Returns:
            Tuple of (audio_filename, duration_seconds, transcript_data)
        """
        # Resolve style prompt: custom takes precedence, then preset, then default
        if style_prompt is None:
            style_prompt = NARRATOR_STYLES.get(narrator_style, NARRATOR_STYLES["classic"])
        
        # Split into sentences
        sentences = self._split_into_sentences(chapter.text_content)
        
        # Group into API-sized chunks
        chunks = self._chunk_sentences(sentences)
        
        # Track audio and timestamps
        all_audio = b""
        segments: list[Segment] = []
        current_time = 0.0
        
        for chunk_idx, sentence_group in enumerate(chunks):
            # Combine sentences for this API call
            chunk_text = " ".join(sentence_group)
            
            # Generate audio (first chunk gets full style, subsequent get consistency reminder)
            audio_bytes = self._generate_audio(
                chunk_text, 
                chunk_index=chunk_idx,
                style_prompt=style_prompt
            )
            
            chunk_duration = self._audio_duration(audio_bytes)
            
            # Estimate timing per sentence based on character length
            total_chars = sum(len(s) for s in sentence_group)
            
            for sentence in sentence_group:
                # Proportional duration based on character count
                if total_chars > 0:
                    sentence_duration = chunk_duration * (len(sentence) / total_chars)
                else:
                    sentence_duration = chunk_duration / len(sentence_group)
                
                segments.append(Segment(
                    text=sentence,
                    start=current_time,
                    end=current_time + sentence_duration,
                ))
                current_time += sentence_duration
            
            all_audio += audio_bytes
        
        # Save audio
        audio_filename = f"chapter-{chapter.number:02d}.mp3"
        wav_path = output_dir / f"chapter-{chapter.number:02d}.wav"
        mp3_path = output_dir / audio_filename
        
        with wave.open(str(wav_path), "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(24000)
            wf.writeframes(all_audio)
        
        total_duration = self._audio_duration(all_audio)
        
        # Convert to MP3
        try:
            import subprocess
            import shutil
            
            ffmpeg_path = shutil.which("ffmpeg")
            if not ffmpeg_path:
                raise RuntimeError("ffmpeg not found")
            
            result = subprocess.run(
                [ffmpeg_path, "-y", "-i", str(wav_path),
                 "-acodec", "libmp3lame", "-ab", "192k",
                 "-ar", "24000", "-ac", "1", str(mp3_path)],
                capture_output=True, text=True,
            )
            if result.returncode == 0:
                wav_path.unlink()
            else:
                raise RuntimeError(result.stderr)
        except Exception as e:
            print(f"Warning: MP3 conversion failed ({e}), keeping WAV")
            audio_filename = f"chapter-{chapter.number:02d}.wav"
            if wav_path.exists():
                wav_path.rename(output_dir / audio_filename)
        
        # Create transcript
        transcript = TranscriptData(
            text=chapter.text_content,
            duration=total_duration,
            segments=segments,
        )
        
        return audio_filename, total_duration, transcript
