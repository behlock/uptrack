# uptrack

A macOS menu-bar app that tracks your listening history across Spotify and Apple Music, with instant recall via a hotkey-triggered bezel

## Features

- Automatic tracking of currently-playing tracks from **Spotify** and **Apple Music**
- **Bezel HUD** for instant history recall — default hotkey `⌥⇧⇥`. Hold to cycle forward, arrow keys / Tab to navigate, release the modifier to dismiss
- **Direct playback** — pressing Enter or clicking an entry resumes that track in its original app
- **Menu-bar dropdown** with the 50 most recent tracks, source-app icons, and standard `⌘,` / `⌘Q` shortcuts

## Requirements

- macOS 26 or later

## Development

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen); it is not checked in.

```sh
brew install xcodegen swiftformat
xcodegen generate
xcodebuild test -project uptrack.xcodeproj -scheme uptrack -configuration Debug CODE_SIGNING_ALLOWED=NO
swiftformat --lint .
```

Regenerate the project after adding or removing source files. The version is declared once, in `project.yml` (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`).

Live logs:

```sh
log stream --predicate 'subsystem == "com.uptrack.app"' --level debug
```

Releases are built by the `Build & Release` workflow on a `v*` tag (`scripts/build-release.sh` mirrors it locally). See `docs/SCAFFOLDING.md` for the architecture and conventions.
