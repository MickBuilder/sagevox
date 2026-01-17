# SageVox Converter

A CLI tool to convert ePub books into SageVox audiobooks with word-level synchronization.

## Features

- Parse ePub files and extract chapters (skipping front matter)
- Generate high-quality audio using Google Gemini TTS
- Create word-level timestamps for text synchronization
- Support for 30 different narrator voices
- Progress tracking and rich terminal output

## Installation

### Development

```bash
cd converter
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -e .
```

### Production

```bash
cd converter
python3 -m venv .venv
source .venv/bin/activate
pip install .
```

### Requirements

- Python 3.11+
- Google Cloud account with Text-to-Speech API enabled
- `ffmpeg` installed (for audio conversion)

```bash
# macOS
brew install ffmpeg

# Ubuntu/Debian
sudo apt install ffmpeg

# Windows (with Chocolatey)
choco install ffmpeg
```

### Gemini API Setup

1. Get a Gemini API key from [Google AI Studio](https://aistudio.google.com/apikey)
2. Set the environment variable:

```bash
export GEMINI_API_KEY=your-api-key-here
```

Or create a `.env` file in the converter directory:

```
GEMINI_API_KEY=your-api-key-here
```

## Usage

### Convert an ePub

```bash
sagevox-convert convert book.epub -v Kore -o ./output/my-book
```

### Options

| Option | Description |
|--------|-------------|
| `-o, --output` | Output directory |
| `-v, --voice` | Narrator voice (default: Kore) |
| `-l, --language` | Language code (default: en-US) |
| `--style` | TTS style prompt |
| `--start-chapter` | Start from chapter N |
| `--end-chapter` | End at chapter N |
| `--dry-run` | Parse only, don't generate audio |

### List Available Voices

```bash
sagevox-convert voices
```

### View Audiobook Info

```bash
sagevox-convert info ./output/my-book/metadata.json
```

## Output Structure

```
my-book/
├── metadata.json           # Book metadata and chapter info
├── cover.jpg               # Cover image (if available)
├── chapter-01.mp3          # Audio for chapter 1
├── chapter-01.txt          # Text for chapter 1
├── chapter-01-sync.json    # Word timestamps for chapter 1
├── chapter-02.mp3
├── chapter-02.txt
├── chapter-02-sync.json
└── ...
```

## Metadata Format

```json
{
  "id": "pride-and-prejudice",
  "title": "Pride and Prejudice",
  "author": "Jane Austen",
  "narrator_voice": "Kore",
  "language_code": "en-US",
  "total_chapters": 61,
  "total_duration_seconds": 43200.5,
  "chapters": [
    {
      "number": 1,
      "title": "Chapter 1",
      "audio_file": "chapter-01.mp3",
      "sync_file": "chapter-01-sync.json",
      "text_file": "chapter-01.txt",
      "duration_seconds": 720.5
    }
  ]
}
```

## Word Sync Format

```json
{
  "version": "1.0",
  "timestamps": [
    {"word": "It", "start": 0.0, "end": 0.15},
    {"word": "is", "start": 0.15, "end": 0.28},
    {"word": "a", "start": 0.28, "end": 0.35}
  ]
}
```
