# Pomofantasy

A macOS menu bar Pomodoro timer with focus-enhancing features.

## Features

- **Menu Bar Timer** - Always visible countdown in your menu bar
- **25/5 Pomodoro Technique** - 25-minute focus sessions with 5-minute breaks
- **Website Blocking** - Blocks distracting sites during focus time (Facebook, Twitter, YouTube, Reddit, etc.)
- **Voice Announcements** - Optional voice feedback for timer events
- **Bilingual Support** - English and Spanish
- **System Notifications** - Get notified when sessions complete
- **Whitelist** - Allow specific sites even during focus time

## Requirements

- macOS 13.0+
- Xcode 14+

## Installation

1. Clone the repository
2. Open `pomofantasy.xcodeproj` in Xcode
3. Build and run (⌘R)

## Usage

Click the timer in your menu bar to:
- Start/pause the timer
- Skip to break or work mode
- Reset the current session
- Configure website blocking and whitelist
- Toggle voice announcements and language

## Website Blocking

When enabled, the app blocks common distracting websites by modifying `/etc/hosts`. Administrator privileges are required. You can whitelist specific sites in the settings panel.

## License

MIT
