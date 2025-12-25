# WallpaperFree (Live)

<p align="center">
  <img width="544" height="976" alt="Screenshot 2025-12-25 at 21 52 36" src="https://github.com/user-attachments/assets/1b69d0e0-0dd2-4fb1-829d-6059ca37851f" />
</p>

A native macOS application that lets you set video files as animated desktop wallpapers on one or multiple monitors.

## Features

- **Multi-monitor support** - Set different videos on each connected display
- **Video library management** - Add, organize, and preview your video collection
- **Persistent settings** - Your wallpaper configurations are saved and automatically restored on launch
- **Volume control** - Adjust playback volume with a convenient slider
- **System integration** - Automatically handles screen configuration changes and system wake events
- **Lightweight** - Runs efficiently in the background without interfering with your workflow

## Requirements

- macOS 12.0 or later
- Swift 5.7+
- Xcode 14.0+

## Installation

1. Clone this repository
2. Open `WallpaperFree.xcodeproj` in Xcode
3. Build and run the project

## Usage

### Adding Videos

1. Click the "Add" button in the My Collection section
2. Select one or more video files from your system
3. Thumbnails will be automatically generated for each video

### Setting Wallpapers

1. Select a video from the picker for each screen you want to configure
2. Toggle the switch to enable/disable the wallpaper for that screen
3. Settings are saved automatically

### Volume Control

Use the slider at the bottom of the window to adjust playback volume for all active wallpapers.

## Technical Details

### Architecture

The application is built using SwiftUI and follows a clean architecture pattern:

- **Models** - `VideoFile` and `ScreenSettings` for data representation
- **SettingsManager** - Handles persistent storage using UserDefaults
- **WallpaperEngine** - Core engine that manages video playback and window positioning
- **UI Components** - Modular SwiftUI views for library and screen management

### Key Technologies

- **AVFoundation** - Video playback with `AVQueuePlayer` and `AVPlayerLooper` for seamless looping
- **AppKit** - Window management and screen detection
- **SwiftUI** - Modern declarative UI framework
- **Combine** - Reactive data flow

### Window Management

The application creates borderless windows at desktop level that:
- Don't interfere with mouse events
- Stay behind all other windows
- Span across all spaces
- Adjust automatically to screen configuration changes

### Persistence

Settings are stored in UserDefaults and include:
- Video library paths
- Per-screen video assignments
- Enable/disable states
- Volume preferences

## Known Limitations

- Only local video files are supported (no streaming URLs)
- Videos must be in formats supported by AVFoundation
- The application requires appropriate permissions to access video files

## Future Enhancements

- HTML/web content support as wallpapers
- Playlist support for rotating wallpapers
- Per-screen volume control
- Playback speed adjustment
- Custom start time for videos

## License

This project is provided as-is for personal use.
