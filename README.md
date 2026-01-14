# VoxCap

Personal iOS app to translate Chinese videos to English captions.

## Features

- **In-app Browser**: Browse any Chinese video website
- **Video Detection**: Automatically finds videos on pages (MP4, HLS streams)
- **Video Download**: Download videos directly to your device
- **Chinese Transcription**: WhisperKit converts Chinese speech to text (on-device)
- **English Translation**: OPUS-MT translates Chinese to English (on-device)
- **Caption Player**: Watch videos with synced English captions
- **Export**: Save subtitles as SRT or VTT files

## Privacy

- **100% on-device processing** - No data leaves your phone
- **No API keys required** - Everything runs locally
- **No tracking** - No analytics or telemetry

## Requirements

- macOS with Xcode 15+
- iPhone running iOS 17+
- Apple ID (free, no paid developer account needed)

## Setup Instructions

### 1. Create Xcode Project

1. Open Xcode
2. File → New → Project
3. Select **iOS → App**
4. Configure:
   - Product Name: `VoxCap`
   - Team: Your Apple ID
   - Organization Identifier: `com.yourname` (anything unique)
   - Interface: **SwiftUI**
   - Language: **Swift**
5. Click **Next** and save to any location

### 2. Add Source Files

Copy all files from this repository into your Xcode project:

```
VoxCap/
├── App/
│   └── VoxCapApp.swift          → Replace the auto-generated App file
├── Views/
│   ├── BrowserView.swift
│   ├── VideoListView.swift
│   ├── PlayerView.swift
│   └── SettingsView.swift
├── Services/
│   ├── VideoDetector.swift
│   ├── VideoDownloader.swift
│   ├── TranscriptionService.swift
│   └── TranslationService.swift
├── Models/
│   ├── DetectedVideo.swift
│   ├── Subtitle.swift
│   └── VideoStore.swift
└── Resources/
    └── Info.plist               → Merge with existing Info.plist
```

**To add files in Xcode:**
1. Right-click on VoxCap folder in navigator
2. Select "Add Files to VoxCap..."
3. Navigate to the source files
4. Make sure "Copy items if needed" is checked
5. Click Add

### 3. Add WhisperKit Package

1. File → Add Package Dependencies
2. Enter URL: `https://github.com/argmaxinc/WhisperKit`
3. Click **Add Package**
4. Select **WhisperKit** and click **Add Package**

### 4. Configure Info.plist

Ensure your Info.plist includes:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
<key>NSMicrophoneUsageDescription</key>
<string>VoxCap needs microphone access for audio capture.</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>VoxCap uses speech recognition to transcribe Chinese audio.</string>
```

### 5. Build & Run

1. Connect your iPhone via USB
2. Select your iPhone as the run destination
3. Click the Play button (or Cmd+R)
4. Trust the developer on your iPhone:
   - Settings → General → VPN & Device Management
   - Tap your developer account
   - Tap "Trust"

### 6. App Expiration (Free Apple ID)

With a free Apple ID, the app expires after **7 days**. To reinstall:
1. Open Xcode
2. Connect iPhone
3. Click Run (Cmd+R)

The app and all your downloaded videos will be preserved.

## Usage

### Browsing & Downloading

1. Open the **Browse** tab
2. Enter a Chinese video website URL
3. Navigate to a video
4. When videos are detected, tap the blue bar at the bottom
5. Tap the download button next to any video

### Processing Videos

1. Open the **Videos** tab
2. Find your downloaded video
3. Tap **Process** to transcribe and translate
4. First time: Model downloads (~500MB)
5. Wait for processing to complete

### Watching with Captions

1. Tap a processed video to open the player
2. English captions appear automatically
3. Use the menu (⋯) to:
   - Show/hide Chinese text
   - Change caption size
   - Export SRT/VTT subtitles

## Tech Stack

| Component | Technology |
|-----------|------------|
| UI | SwiftUI |
| Browser | WKWebView |
| Speech-to-Text | WhisperKit (Whisper small) |
| Translation | OPUS-MT (CoreML) |
| Video | AVFoundation |

## Troubleshooting

### Videos not detected

Some sites use DRM or obfuscated video URLs. Try:
- Refreshing the page
- Playing the video first
- Some sites may not be supported

### Transcription fails

- Ensure Whisper model is downloaded (Settings tab)
- Check available storage space
- Try a shorter video first

### Download fails

- Check internet connection
- Some sites block downloads (403 error)
- Try a different video quality if available

## Known Limitations

- DRM-protected content cannot be downloaded
- Some sites actively block video extraction
- Translation quality varies (OPUS-MT is good but not perfect)
- First transcription is slow (model initialization)

## License

For personal use only. Uses open-source components:
- [WhisperKit](https://github.com/argmaxinc/WhisperKit) - MIT License
- [OPUS-MT](https://github.com/Helsinki-NLP/Opus-MT) - CC-BY 4.0
