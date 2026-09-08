# uptrack

A macOS menu-bar app that tracks what you play in Spotify and Apple Music, and lets you jump back to any recent track with a hotkey.

- Press `⌥⇧⇥` to open the history bezel. Keep holding to cycle, use arrows or Tab to navigate, release to dismiss.
- Press Enter or click a track to resume it in the app it came from.

## Development

```sh
brew install xcodegen swiftformat
xcodegen generate   # rerun after adding or removing source files
xcodebuild test -project uptrack.xcodeproj -scheme uptrack -configuration Debug CODE_SIGNING_ALLOWED=NO
swiftformat --lint .
```

Pushing a `v*` tag builds a release; `scripts/build-release.sh` does the same locally. Architecture notes are in `docs/SCAFFOLDING.md`.
