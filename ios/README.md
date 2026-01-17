# SageVox iOS App

SwiftUI audiobook player with AI-powered spoiler-free voice Q&A.

## Features

- Browse audiobook library
- Stream audio from backend server
- Text follow-along with synchronized highlighting
- Voice Q&A via LiveKit (pause and ask questions about the book)
- Playback controls (speed, skip, chapter navigation)
- Progress tracking (persisted locally)
- Lock screen controls
- PostHog analytics

## Requirements

- Xcode 15+
- iOS 15.0+
- macOS 13+ (for development)

## Project Structure

```
ios/Sagevox/Sagevox/
├── SagevoxApp.swift              # App entry point
├── ContentView.swift             # Root view with navigation
├── Config.plist                  # API keys (gitignored)
├── Config.plist.example          # Template for Config.plist
│
├── Models/
│   ├── Book.swift                # Book, Chapter, Transcript models
│   ├── BookSummary.swift         # Lightweight model for library
│   └── ReadingProgress.swift     # Progress tracking + persistence
│
├── ViewModels/
│   ├── LibraryViewModel.swift    # Library data loading
│   └── VoiceQAViewModel.swift    # Voice Q&A state management
│
├── Views/
│   ├── Library/
│   │   ├── LibraryView.swift     # Book grid
│   │   └── BookCardView.swift    # Book card component
│   ├── BookDetail/
│   │   └── BookDetailView.swift  # Book info + chapter list
│   ├── Player/
│   │   ├── PlayerView.swift      # Full-screen player
│   │   ├── MiniPlayerView.swift  # Bottom bar player
│   │   └── TextFollowAlongView.swift
│   ├── VoiceQA/
│   │   └── WaveformView.swift    # Audio visualizer
│   └── Common/
│       └── BookCoverView.swift   # Reusable cover component
│
├── Services/
│   ├── API/
│   │   └── APIClient.swift       # REST API client
│   ├── LiveAPI/
│   │   └── LiveAPIClient.swift   # LiveKit connection
│   ├── Audio/
│   │   ├── AudioPlayerService.swift    # AVPlayer wrapper
│   │   └── AudioSessionManager.swift   # Audio session config
│   └── Analytics/
│       └── AnalyticsService.swift      # PostHog tracking
│
├── Theme/
│   └── AppTheme.swift            # Colors, styles
│
└── Utils/
    └── TimeFormatter.swift       # Duration formatting
```

## Setup

### 1. Open Project

```bash
open ios/Sagevox/Sagevox.xcodeproj
```

### 2. Add Swift Packages

In Xcode: **File → Add Package Dependencies**

| Package | URL |
|---------|-----|
| LiveKit | `https://github.com/livekit/client-sdk-swift` |
| PostHog | `https://github.com/PostHog/posthog-ios` |

### 3. Configure API Keys

Copy the example config and add your keys:

```bash
cp ios/Sagevox/Sagevox/Config.plist.example ios/Sagevox/Sagevox/Config.plist
```

Edit `Config.plist`:

```xml
<dict>
    <key>PostHogAPIKey</key>
    <string>phc_your_key_here</string>
    <key>PostHogHost</key>
    <string>https://us.i.posthog.com</string>
</dict>
```

**Important:** `Config.plist` is gitignored to protect your keys.

### 4. Set Server URL

The server URL is configured in `APIClient.swift`:

```swift
// Default: http://localhost:8000
// Override via environment variable in Xcode scheme:
// SAGEVOX_SERVER_URL = https://your-backend.railway.app
```

To change for development:
1. Edit Scheme → Run → Arguments → Environment Variables
2. Add: `SAGEVOX_SERVER_URL` = `http://your-ip:8000`

### 5. Build and Run

Select your device/simulator and press **Cmd+R**.

## Architecture

### Data Flow

```
┌─────────────────┐
│   LibraryView   │ ← LibraryViewModel ← APIClient.fetchBooks()
└────────┬────────┘
         │ tap book
         ▼
┌─────────────────┐
│ BookDetailView  │ ← APIClient.fetchBook(id)
└────────┬────────┘
         │ play
         ▼
┌─────────────────┐
│   PlayerView    │ ← AudioPlayerService (AVPlayer)
│                 │ ← VoiceQAViewModel (LiveKit)
└─────────────────┘
```

### Voice Q&A Flow

1. User taps "Ask" button → audiobook pauses
2. `VoiceQAViewModel` requests token from `/engage/token`
3. Connects to LiveKit room with microphone enabled
4. Sends book context via data channel
5. User speaks → LiveKit agent responds
6. User says "resume" → agent sends command → playback resumes

## Analytics Events

| Event | When |
|-------|------|
| `book_opened` | User opens book detail |
| `playback_started` | Play button pressed |
| `playback_paused` | Pause button pressed |
| `playback_speed_changed` | Speed adjusted |
| `voice_qa_started` | Q&A session begins |
| `voice_qa_ended` | Q&A session ends |
| `voice_qa_error` | Connection failed |
| `text_follow_along_opened` | Text view opened |

## Testing

### Simulator Limitations

- Microphone works in Simulator (macOS mic)
- Real device recommended for voice Q&A testing

### Local Backend

1. Start backend: `cd backend && ./run_dev.sh`
2. Start agent: `cd backend && python agent.py dev`
3. Set `SAGEVOX_SERVER_URL=http://localhost:8000` in Xcode scheme
4. Run app on Simulator

## Deployment

See [DEPLOYMENT.md](../DEPLOYMENT.md) for TestFlight deployment instructions.

## Troubleshooting

### "Not connected to server"
- Check backend is running
- Verify `SAGEVOX_SERVER_URL` is correct
- On device: use your Mac's IP, not `localhost`

### Voice Q&A not connecting
- Check LiveKit credentials in backend `.env`
- Verify microphone permissions
- Check Console.app for LiveKit errors

### Audio not playing
- Check audio file URLs in Network inspector
- Verify backend `/books/` static files are served
