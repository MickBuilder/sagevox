# SageVox Deployment Guide

Step-by-step guide to deploy SageVox backend on Railway and iOS app on TestFlight.

## Prerequisites

- [Railway](https://railway.app) account
- [LiveKit Cloud](https://cloud.livekit.io) account with credentials
- [Google AI Studio](https://aistudio.google.com/apikey) Gemini API key
- [Apple Developer Program](https://developer.apple.com/programs/) membership ($99/year)
- Xcode 15+ installed
- Converted audiobooks in `backend/books/` directory

---

## Part 1: Backend Deployment (Railway)

### Step 1: Prepare Your Repository

Ensure your project is in a Git repository:

```bash
cd /path/to/sagevox
git init  # if not already
git add .
git commit -m "Prepare for deployment"
```

Push to GitHub:

```bash
git remote add origin https://github.com/yourusername/sagevox.git
git push -u origin main
```

### Step 2: Create Railway Project

1. Go to [railway.app](https://railway.app) and sign in
2. Click **"New Project"**
3. Select **"Deploy from GitHub repo"**
4. Choose your `sagevox` repository
5. Railway will detect the project - select the `backend` folder as root

### Step 3: Configure Build Settings

In Railway dashboard, go to your service → **Settings**:

**Build:**
- Root Directory: `backend`
- Build Command: `pip install .`
- Start Command: `uvicorn app.main:app --host 0.0.0.0 --port $PORT`

Or create `backend/railway.json`:

```json
{
  "build": {
    "builder": "nixpacks"
  },
  "deploy": {
    "startCommand": "uvicorn app.main:app --host 0.0.0.0 --port $PORT",
    "healthcheckPath": "/health",
    "healthcheckTimeout": 30
  }
}
```

### Step 4: Add Environment Variables

In Railway → **Variables**, add:

```
GOOGLE_API_KEY=your-gemini-api-key
LIVEKIT_URL=wss://your-app.livekit.cloud
LIVEKIT_API_KEY=your-livekit-api-key
LIVEKIT_API_SECRET=your-livekit-api-secret
CORS_ALLOW_ORIGINS=["*"]
DEBUG=false
```

### Step 5: Add Volume for Books

Since books are stored on disk:

1. In Railway dashboard → **+ New** → **Volume**
2. Mount path: `/app/books`
3. In Variables, add: `BOOKS_DIR=/app/books`

### Step 6: Upload Books to Volume

Option A: Use Railway CLI

```bash
# Install Railway CLI
npm install -g @railway/cli

# Login
railway login

# Link to project
railway link

# Upload books
railway run cp -r books/* /app/books/
```

Option B: SSH into container (Railway Pro)

```bash
railway shell
# Then upload via scp or other method
```

Option C: Add books to repo (simple, not recommended for large files)

Put books in `backend/books/` and they'll deploy with the code.

### Step 7: Deploy Voice Agent

The LiveKit agent needs to run separately. Create a second Railway service:

1. In same project → **+ New** → **Empty Service**
2. Connect to same GitHub repo
3. Settings:
   - Root Directory: `backend`
   - Start Command: `python agent.py start`
4. Add same environment variables as the API service

### Step 8: Generate Domain

1. Go to API service → **Settings** → **Networking**
2. Click **"Generate Domain"**
3. Note your URL: `https://sagevox-backend-xxxx.railway.app`

### Step 9: Verify Deployment

```bash
# Health check
curl https://your-app.railway.app/health

# List books
curl https://your-app.railway.app/api/books
```

---

## Part 2: iOS Deployment (TestFlight)

### Step 1: Update Server URL

In `ios/Sagevox/Sagevox/Services/API/APIClient.swift`, update the default URL:

```swift
static let serverURL: URL = {
    if let urlString = ProcessInfo.processInfo.environment["SAGEVOX_SERVER_URL"],
       let url = URL(string: urlString) {
        return url
    }
    // Production URL
    return URL(string: "https://your-app.railway.app")!
}()
```

Or better - add to `Config.plist`:

```xml
<key>ServerURL</key>
<string>https://your-app.railway.app</string>
```

### Step 2: Configure App Signing

1. Open Xcode → **Sagevox** target → **Signing & Capabilities**
2. Team: Select your Apple Developer account
3. Bundle Identifier: `com.yourcompany.sagevox` (must be unique)
4. Signing Certificate: Automatically manage signing ✓

### Step 3: Set Version & Build Number

1. Go to **Sagevox** target → **General**
2. Set Version: `1.0.0`
3. Set Build: `1` (increment for each TestFlight upload)

### Step 4: Create App in App Store Connect

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. **My Apps** → **+** → **New App**
3. Fill in:
   - Platform: iOS
   - Name: SageVox
   - Primary Language: English
   - Bundle ID: Select from dropdown (matches Xcode)
   - SKU: `sagevox-001`
4. Click **Create**

### Step 5: Archive the App

1. In Xcode, select **Any iOS Device (arm64)** as destination
2. **Product** → **Archive**
3. Wait for archive to complete
4. Organizer window opens automatically

### Step 6: Upload to App Store Connect

1. In Organizer, select your archive
2. Click **"Distribute App"**
3. Select **"App Store Connect"**
4. Click **"Upload"**
5. Wait for upload and processing (5-30 minutes)

### Step 7: Submit for Beta Review

1. In App Store Connect → Your App → **TestFlight** tab
2. Wait for build to appear (shows "Processing")
3. Once ready, click the build
4. Fill in **"What to Test"** description
5. Click **"Submit for Review"**

Beta review usually takes < 24 hours.

### Step 8: Add Testers

**Internal Testers** (immediate access, up to 100):
1. TestFlight → **Internal Testing** → **+**
2. Add team members by email
3. They receive TestFlight invite immediately

**External Testers** (after beta approval, up to 10,000):
1. TestFlight → **External Testing** → **+** → **Create New Group**
2. Name your group (e.g., "Beta Testers")
3. Add builds to the group
4. **Add Testers** → Enter emails or create public link

### Step 9: Tester Installation

Testers receive an email:
1. Install **TestFlight** app from App Store
2. Open email on iPhone → tap **"View in TestFlight"**
3. Tap **"Install"** in TestFlight
4. App appears on home screen

---

## Part 3: Post-Deployment Checklist

### Verify Everything Works

- [ ] Backend health check returns 200
- [ ] Books API returns your books
- [ ] Audio files stream correctly
- [ ] iOS app loads library
- [ ] Playback works
- [ ] Voice Q&A connects and responds
- [ ] Analytics events appear in PostHog

### Monitor

**Railway:**
- Check logs: Railway dashboard → Logs
- Monitor usage: Railway dashboard → Usage

**PostHog:**
- View events: PostHog → Events
- Create dashboards for key metrics

**TestFlight:**
- View crashes: App Store Connect → TestFlight → Crashes
- Read feedback: TestFlight → Feedback

---

## Updating the App

### Backend Updates

```bash
git add .
git commit -m "Update backend"
git push
# Railway auto-deploys from main branch
```

### iOS Updates

1. Increment Build number in Xcode
2. Archive and upload (Steps 5-6)
3. New build auto-submits if previous was approved
4. Testers get update notification

---

## Troubleshooting

### Railway: Build Fails

Check logs for missing dependencies. Ensure `pyproject.toml` lists all requirements.

### Railway: Agent Won't Start

Verify LiveKit credentials are correct. Check agent logs for connection errors.

### TestFlight: Build Processing Stuck

Usually resolves in 30 min. If longer, check for errors in App Store Connect.

### TestFlight: Beta Review Rejected

Common reasons:
- Crashes on launch (test thoroughly first)
- Missing privacy descriptions in Info.plist
- Placeholder content

---

## Cost Estimates

| Service | Free Tier | Paid |
|---------|-----------|------|
| Railway | $5/month credit | ~$5-20/month |
| LiveKit Cloud | 50 monthly participant-hours | Pay as you go |
| Gemini API | Free tier available | Pay per token |
| Apple Developer | - | $99/year |
| PostHog | 1M events/month free | Pay as you grow |

---

## Security Notes

- Never commit API keys to Git
- Use Railway's encrypted variables
- `Config.plist` is gitignored
- Consider adding API rate limiting for production
- Monitor for unusual usage patterns
