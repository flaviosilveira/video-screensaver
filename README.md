# video-screensaver

Turn any video into a native macOS screensaver (`.saver`). No Aerial,
SaveHollywood or other third-party host: just Apple's `ScreenSaver.framework`
and AVFoundation, built with the Swift compiler that ships with Xcode.

```bash
./make-saver.sh ~/Movies/beach.mp4 Beach --install
```

Then open **System Settings → Screen Saver** and pick *Beach*.

## How it works

- `Sources/VideoSaverView.swift` is a `ScreenSaverView` subclass. It plays the
  bundled video with `AVQueuePlayer` + `AVPlayerLooper` (seamless loop), muted,
  with no controls, in an `AVPlayerLayer` using aspect-fill, so any aspect
  ratio fills the screen without distortion. Retina scale follows the window.
- macOS creates one view per display and one for the Settings preview, so
  multiple monitors and preview mode work without special code.
- Playback is torn down on `stopAnimation` and on the
  `com.apple.screensaver.willstop` distributed notification. Since macOS 14
  the `legacyScreenSaver` host often skips `stopAnimation` and keeps old
  instances alive, so the notification is what actually frees the player.
- `make-saver.sh` stamps a unique class name per saver (`<Name>VideoSaverView`).
  All installed savers load into the same `legacyScreenSaver` process, and
  two bundles with the same Objective-C class would clash, with one saver
  showing the other's video.

## Requirements

- macOS 14 or later
- Xcode or the Command Line Tools (`xcrun swiftc`, `codesign`)

## Usage

```
./make-saver.sh <video.mp4|mov|m4v> <Name> [--install]
```

- `Name` is letters and digits, starting with a letter. It becomes the name
  shown in System Settings and the bundle id `com.local.<name>.screensaver`.
- The bundle is written to `build/<Name>.saver` and signed ad hoc.
- The video is copied into the bundle as is, with no re-encoding, so the
  saver is self-contained. H.264 or HEVC video works best, and any audio
  track is ignored.
- `--install` copies it to `~/Library/Screen Savers/`. An existing saver with
  the same name is moved to `<Name>.saver.backup-<timestamp>` first.

To replace the video, run the script again with the new file and the same
name.

## Uninstall

```bash
rm -rf ~/Library/Screen\ Savers/Beach.saver
```

Pick another screensaver in System Settings first if it is the active one.

## Limitations

- Apple calls `.saver` bundles legacy, but they still load through the
  `legacyScreenSaver` host as of macOS 27. A future release could drop them.
  Apple has no public API for third-party screensavers that replaces this.
- If System Settings shows an old build after reinstalling, quit System
  Settings and run `killall legacyScreenSaver` (`--install` does this).
- Ad-hoc signed bundles run on the Mac that built them. To share one with
  other Macs, sign it with a Developer ID and notarize it.
- Builds for the current machine's architecture only.
