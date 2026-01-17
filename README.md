# SageVox

AI-Powered Interactive Audiobooks with Spoiler-Free Q&A.

## What is SageVox?

SageVox lets you **pause your audiobook and ask questions** about characters, plot, themes - anything. The AI answers **without spoiling** anything you haven't heard yet.

## How It Works

```
┌──────────────┐     ┌───────────────┐     ┌─────────────┐
│  ePub Book   │────►│   Converter   │────►│  Audiobook  │
│              │     │  (Gemini TTS) │     │  (MP3 + TS) │
└──────────────┘     └───────────────┘     └──────┬──────┘
                                                  │
                                                  ▼
┌──────────────┐     ┌───────────────┐     ┌─────────────┐
│   iOS App    │◄───►│    Backend    │◄───►│   LiveKit   │
│  (SwiftUI)   │     │   (FastAPI)   │     │  + Gemini   │
└──────────────┘     └───────────────┘     └─────────────┘
```

## Features

- **High-Quality Narration** - 29 Gemini TTS voices with style presets
- **Spoiler-Free Q&A** - AI knows exactly where you are in the book
- **Text Follow-Along** - Synchronized highlighting as you listen
- **Voice Control** - "Skip back", "Go to chapter 3", "Resume"
- **Progress Tracking** - Pick up where you left off

## Project Structure

```
sagevox/
├── converter/     # ePub → Audiobook CLI tool
├── backend/       # FastAPI server + LiveKit voice agent
├── ios/           # SwiftUI iOS app
└── DEPLOYMENT.md  # Production deployment guide
```

## Quick Start

### Prerequisites

- Python 3.11+
- Xcode 15+
- [Gemini API Key](https://aistudio.google.com/apikey)
- [LiveKit Cloud](https://cloud.livekit.io) account

### 1. Convert a Book

```bash
cd converter
python3 -m venv .venv && source .venv/bin/activate
pip install -e .

sagevox-convert book.epub --voice Kore --output ../backend/books/my-book
```

### 2. Run Backend

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -e .

# Create .env with GOOGLE_API_KEY, LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET
cp .env.example .env

# Terminal 1: API server
./run_dev.sh

# Terminal 2: Voice agent
python agent.py dev
```

### 3. Run iOS App

```bash
open ios/Sagevox/Sagevox.xcodeproj
```

1. Add packages: LiveKit SDK, PostHog
2. Create `Config.plist` from `Config.plist.example`
3. Build and run on Simulator or device

## Documentation

| Doc | Description |
|-----|-------------|
| [Backend README](backend/README.md) | API, agent, configuration |
| [iOS README](ios/README.md) | App architecture, setup |
| [Converter README](converter/README.md) | ePub conversion options |
| [Deployment Guide](DEPLOYMENT.md) | Railway + TestFlight deployment |

## Tech Stack

| Component | Technology |
|-----------|------------|
| TTS | Google Gemini TTS |
| Voice AI | Google Gemini Live + LiveKit Agents |
| Backend | Python, FastAPI, LiveKit SDK |
| iOS | SwiftUI, AVFoundation, LiveKit iOS SDK |
| Analytics | PostHog |

## Environment Variables

### Backend

```bash
GOOGLE_API_KEY=...           # Required
LIVEKIT_URL=wss://...        # Required
LIVEKIT_API_KEY=...          # Required
LIVEKIT_API_SECRET=...       # Required
```

### Converter

```bash
GEMINI_API_KEY=...           # Required (or GOOGLE_API_KEY)
```

## License

MIT
