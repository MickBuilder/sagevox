# SageVox Backend

FastAPI server + LiveKit Voice Agent for real-time spoiler-free Q&A.

## Architecture

```
┌─────────────┐     REST API      ┌─────────────────┐
│   iOS App   │◄─────────────────►│  FastAPI Server │
│             │                   │  (main.py)      │
│             │     LiveKit       │                 │
│             │◄─────────────────►│  Voice Agent    │
│             │   (audio + data)  │  (agent.py)     │
└─────────────┘                   └─────────────────┘
                                          │
                                          ▼
                                  ┌───────────────┐
                                  │ LiveKit Cloud │
                                  │ + Gemini API  │
                                  └───────────────┘
```

## Features

- **REST API** (`/api/books`) - Book library and metadata
- **Static Files** (`/books/{id}/`) - Audio streaming with HTTP Range support
- **Token Endpoint** (`/engage/token`) - LiveKit room access tokens
- **Voice Agent** - Gemini-powered conversational AI with tools:
  - `get_current_context` - Fetch current listening position
  - `wait_more` - Patient listening for user pauses
  - `stop_and_resume_book` - Resume audiobook playback
  - `skip_back/forward` - Navigate in the book
  - `go_to_chapter` - Jump to specific chapter

## Requirements

- Python 3.11+
- [LiveKit Cloud](https://cloud.livekit.io) account (free tier available)
- [Gemini API Key](https://aistudio.google.com/apikey)

## Installation

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate
pip install -e .
```

## Configuration

Create a `.env` file:

```bash
# Required - Google Gemini
GOOGLE_API_KEY=your-gemini-api-key

# Required - LiveKit Cloud
LIVEKIT_URL=wss://your-app.livekit.cloud
LIVEKIT_API_KEY=your-api-key
LIVEKIT_API_SECRET=your-api-secret

# Optional
DEBUG=false
PORT=8000
CORS_ALLOW_ORIGINS=["*"]
```

## Running Locally

You need to run **two processes**:

### 1. FastAPI Server (REST API + Static Files)

```bash
./run_dev.sh
# Or manually:
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### 2. LiveKit Voice Agent

```bash
python agent.py dev
```

The agent connects to LiveKit Cloud and handles voice interactions.

## API Endpoints

### Books API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/books` | GET | List all books (summary) |
| `/api/books/{id}` | GET | Get book with chapters & transcripts |
| `/books/{id}/{file}` | GET | Static files (audio, covers) |

### Voice API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/engage/token` | GET | Get LiveKit room token |

#### Token Parameters

```
GET /engage/token?book_id=xxx&participant_name=User&title=BookTitle&voice=Kore
```

## Book Storage

Books are stored in `backend/books/` directory:

```
books/
├── {book-id}/
│   ├── metadata.json       # Book info + chapter list
│   ├── cover.jpg           # Cover image
│   ├── chapter-01.mp3      # Audio files
│   ├── chapter-01.json     # Transcript with timestamps
│   └── ...
```

### metadata.json Format

```json
{
  "id": "pride-and-prejudice",
  "title": "Pride and Prejudice",
  "author": "Jane Austen",
  "description": "A classic romance novel...",
  "narrator_voice": "Kore",
  "cover_image": "cover.jpg",
  "total_chapters": 61,
  "total_duration_seconds": 43200,
  "chapters": [
    {
      "number": 1,
      "title": "Chapter 1",
      "audio_file": "chapter-01.mp3",
      "transcript_file": "chapter-01.json",
      "duration_seconds": 720
    }
  ]
}
```

## Production Deployment

See [DEPLOYMENT.md](../DEPLOYMENT.md) for Railway deployment instructions.

## Docker

```dockerfile
FROM python:3.11-slim

WORKDIR /app
COPY pyproject.toml .
RUN pip install --no-cache-dir .

COPY app/ app/
COPY agent.py .

RUN useradd -m -u 1000 sagevox && chown -R sagevox:sagevox /app
USER sagevox

EXPOSE 8000

# Note: agent.py runs separately via `python agent.py start`
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

## Spoiler Prevention

The system prompt in `app/voice/prompt.py` instructs the AI to:
- Only discuss content the user has already heard
- Deflect questions about future plot points
- Use the `get_current_context` tool to know the user's position

Context is sent from iOS via LiveKit data channel when voice Q&A starts.
