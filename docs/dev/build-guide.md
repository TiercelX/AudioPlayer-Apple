# Build Guide

## Prerequisites

### Required software
- Xcode 15.0 or later
- macOS 14.0 or later (for development)
- Homebrew (for FFmpeg installation)

### Optional software
- FFmpeg (for TrueHD support)
- SwiftLint (for code style)

## Quick start

### 1. Clone repository
```bash
git clone <repo-url>
cd AudioPlayerMac
```

### 2. Install FFmpeg
```bash
brew install ffmpeg
```

### 3. Build and run
```bash
# Build (auto-copies .app to worktree)
./scripts/quick-build.sh

# Run from worktree
open AudioPlayerMac/build/Products/Debug/AudioPlayerMac.app
```

## Build output location

xcodebuild writes build products to Xcode DerivedData by default:

```
~/Library/Developer/Xcode/DerivedData/AudioPlayerMac-<hash>/Build/Products/Debug/AudioPlayerMac.app
```

The `quick-build.sh` script automatically copies the built `.app` back into the
worktree after a successful build so that each branch/worktree carries its own
binary:

```
AudioPlayerMac/build/Products/Debug/AudioPlayerMac.app
AudioPlayerMac/build/Products/Release/AudioPlayerMac.app   # for Release builds
```

When using `xcodebuild` directly, add `-derivedDataPath` to keep the build
inside the worktree:

```bash
xcodebuild -project AudioPlayerMac/AudioPlayerMac.xcodeproj   -scheme AudioPlayerMac -configuration Debug   -derivedDataPath AudioPlayerMac/build build
```

## Xcode project setup

### Open project
```bash
open AudioPlayerMac.xcodeproj
```

### Configure signing
1. Select AudioPlayerMac target
2. Go to "Signing & Capabilities"
3. Select your development team
4. Update bundle identifier if needed

### Configure build settings
1. Select AudioPlayerMac target
2. Go to "Build Settings"
3. Verify:
   - Swift Language Version: Swift 5
   - macOS Deployment Target: macOS 12.0

## FFmpeg integration

### Option 1: Homebrew (Recommended for development)

1. Install FFmpeg:
   ```bash
   brew install ffmpeg
   ```

2. Configure Xcode:
   - Select AudioPlayerMac target
   - Go to "Build Settings"
   - Add to "Header Search Paths":
     - `/opt/homebrew/include` (Apple Silicon)
     - `/usr/local/include` (Intel)
   - Add to "Library Search Paths":
     - `/opt/homebrew/lib` (Apple Silicon)
     - `/usr/local/lib` (Intel)
   - Add to "Other Linker Flags":
     - `-lavformat -lavcodec -lswresample -lavutil`

3. Create bridging header:
   - Create file `AudioPlayerMac-Bridging-Header.h`
   - Add: `#include "FFmpegBridge.h"`
   - Set "Objective-C Bridging Header" to `AudioPlayerMac/AudioPlayerMac-Bridging-Header.h`

### Option 2: Manual FFmpeg build

1. Build FFmpeg:
   ```bash
   # Download FFmpeg
   git clone https://git.ffmpeg.org/ffmpeg.git
   cd ffmpeg
   
   # Configure for Apple Silicon
   ./configure \
       --prefix=/usr/local/ffmpeg-mac-arm64 \
       --enable-static \
       --disable-shared \
       --disable-programs \
       --disable-doc \
       --arch=arm64 \
       --target-os=darwin
   
   # Build
   make -j$(sysctl -n hw.ncpu)
   make install
   ```

2. Configure Xcode:
   - Add to "Header Search Paths": `/usr/local/ffmpeg-mac-arm64/include`
   - Add to "Library Search Paths": `/usr/local/ffmpeg-mac-arm64/lib`
   - Add to "Other Linker Flags": `-lavformat -lavcodec -lswresample -lavutil -lz -lbz2`

## Building

### Debug build
```bash
xcodebuild -scheme AudioPlayerMac -configuration Debug build
```

### Release build
```bash
xcodebuild -scheme AudioPlayerMac -configuration Release build
```

### Clean build
```bash
xcodebuild -scheme AudioPlayerMac -configuration Debug clean build
```

### Build to specific directory
```bash
xcodebuild -scheme AudioPlayerMac -configuration Debug -derivedDataPath build build
```

## Running

### From Xcode
1. Open AudioPlayerMac.xcodeproj
2. Select AudioPlayerMac scheme
3. Click Run (⌘R)

### From command line
```bash
# Build
xcodebuild -scheme AudioPlayerMac -configuration Debug -derivedDataPath build build

# Run
open build/Build/Products/Debug/AudioPlayerMac.app
```

## Testing

### Unit tests
```bash
xcodebuild -scheme AudioPlayerMac -configuration Debug test
```

### Smoke tests
```bash
./AudioPlayerMac/scripts/run-playback-smoke.sh [media-directory]
```

### Format tests

Format testing is integrated into the smoke test. Provide a media directory
containing test files:
```bash
./AudioPlayerMac/scripts/run-playback-smoke.sh /path/to/media
```

## Troubleshooting

### Build errors

#### "FFmpegBridge.h not found"
- Check Header Search Paths
- Ensure FFmpeg is installed
- Verify bridging header path

#### "Undefined symbols for architecture"
- Check Library Search Paths
- Check Other Linker Flags
- Ensure FFmpeg libraries are linked

#### "No such module 'AVFoundation'"
- Ensure Xcode is up to date
- Check macOS deployment target
- Clean build folder

### Runtime errors

#### "FFmpeg not loaded"
- Check FFmpeg installation
- Verify library paths
- Check for missing dependencies

#### "No audio output"
- Check audio device
- Check system volume
- Check audio session

## Project structure

```
AudioPlayerMac/
├── AudioPlayerMac.xcodeproj
├── AudioPlayerMac/
│   ├── App/
│   │   ├── AudioPlayerMacApp.swift
│   │   └── AppState.swift
│   ├── Core/
│   │   ├── AudioEngine.swift
│   │   ├── PlaybackController.swift
│   │   └── DecoderRouter.swift
│   ├── Decoders/
│   │   ├── AVFoundation/
│   │   ├── FFmpeg/
│   │   └── Common/
│   ├── UI/
│   │   ├── MainWindow.swift
│   │   └── PlayerControlsView.swift
│   └── Utilities/
├── docs/
│   ├── dev/
│   └── bug/
├── scripts/
└── test-files/
```

## Development workflow

### 1. Create feature branch
```bash
git checkout -b feature/my-feature
```

### 2. Implement changes
- Write code
- Add tests
- Update documentation

### 3. Build and test
```bash
xcodebuild -scheme AudioPlayerMac -configuration Debug build
./AudioPlayerMac/scripts/run-playback-smoke.sh
```

### 4. Commit and push
```bash
git add .
git commit -m "Implement my feature"
git push origin feature/my-feature
```

### 5. Create pull request
- Go to GitHub
- Create pull request
- Wait for review

## IDE setup

### Xcode extensions
- SwiftLint (code style)
- SourceLint (static analysis)

### VS Code extensions
- Swift (Swift language support)
- CodeLLDB (debugging)

## Environment variables

| Variable | Description | Default |
|----------|-------------|---------|
| `AUDIOPLAYER_LOG_LEVEL` | Log level | `info` |
| `AUDIOPLAYER_CACHE_DIR` | Cache directory | `~/Library/Caches/AudioPlayerMac` |
| `AUDIOPLAYER_FFMPEG_PATH` | FFmpeg path | Auto-detect |

## Build configurations

### Debug
- No optimization
- Debug symbols enabled
- Assertions enabled
- Logging enabled

### Release
- Full optimization
- Debug symbols disabled
- Assertions disabled
- Logging disabled

## Performance tips

### Build speed
- Use derived data path
- Enable build parallelization
- Use incremental builds

### Runtime performance
- Use Release configuration for testing
- Enable optimizations
- Profile with Instruments

## Continuous integration

### GitHub Actions
```yaml
# .github/workflows/build.yml

name: Build

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: macos-14
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Install FFmpeg
      run: brew install ffmpeg
    
    - name: Build
      run: |
        xcodebuild -scheme AudioPlayerMac -configuration Debug build
    
    - name: Test
      run: |
        xcodebuild -scheme AudioPlayerMac -configuration Debug test
```

## Support

For build issues:
1. Check this guide
2. Search GitHub issues
3. Create new issue with:
   - macOS version
   - Xcode version
   - Error message
   - Steps to reproduce
