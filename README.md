# Gif It

Gif It is a small, native macOS menu-bar app for recording a window as a GIF
or MP4. It uses Apple's system window picker, captures the cursor and optional
click rings, then copies the result to the clipboard or saves it to a folder.

The app is built with SwiftUI, AppKit, ScreenCaptureKit, AVFoundation, and
Image I/O. It has no third-party dependencies and does not require an Xcode
project.

## How it works

1. Press the global shortcut or choose **Capture Window…** from the menu bar.
2. Use macOS's **Share This Window** control to select a window.
3. Interact with the window while Gif It records it.
4. Press the shortcut again, choose **Stop Recording**, or use the floating
   Stop control.
5. Gif It converts and delivers the recording immediately.

The default shortcut is `Control-Option-G`. It can be changed in Settings.

## Features

- Native macOS single-window picker
- GIF and silent MP4 output
- Cursor capture and native mouse-click rings
- Configurable global start/stop shortcut
- Clipboard delivery or a persistent destination folder
- Floating recording indicator and menu-bar status
- Automatic stop after 30 seconds
- Recovery through **Save Last Recording As…** when conversion or delivery
  fails after a usable recording exists
- No network access, telemetry, or external encoder

## Requirements

- macOS 15 or newer
- Swift 6.2 and a compatible macOS SDK
- Screen Recording permission for the packaged application

## Download

ARM-based Mac builds are available from
[GitHub Releases](https://github.com/jcampuza/gif-it/releases/latest). Download
the release ZIP, extract `Gif It.app`, and move it to `/Applications`.

Release builds are currently ad-hoc signed rather than Apple-notarized. On the
first launch, macOS will block the app because it is from an unidentified
developer. After attempting to open it, go to **System Settings → Privacy &
Security** and choose **Open Anyway**. You only need to approve that downloaded
build once.

## Build and run

Create and run the packaged debug app:

```sh
swift test
./scripts/build-debug.sh
open "$HOME/Applications/Gif It Debug.app"
```

Create the optimized local release:

```sh
./scripts/build-release.sh
open "$HOME/Applications/Gif It.app"
```

The scripts install the bundles at:

- `~/Applications/Gif It Debug.app`
- `~/Applications/Gif It.app`

Set `GIF_IT_APP_PATH` to install somewhere else or
`GIF_IT_SIGNING_IDENTITY` to select a specific signing identity.

## Screen Recording permission and signing

macOS associates Screen Recording permission with a packaged app's bundle ID
and signing identity. Always test capture through the packaged app rather than
running the SwiftPM executable directly.

Debug and release use separate bundle identifiers and therefore receive
permission independently:

- `com.josephcampuzano.gif-it.debug`
- `com.josephcampuzano.gif-it`

For stable local permissions, create the reusable development identity once:

```sh
./scripts/setup-dev-signing.sh
./scripts/signing-status.sh
```

The first signed build may ask for the login keychain password. Choose
**Always Allow** so `/usr/bin/codesign` can reuse the development key without
prompting on each build.

On the first capture, macOS prompts for Screen Recording access. If macOS asks
for a relaunch after access is granted, quit and reopen the corresponding
packaged app.

## Recording defaults

- Format: looping GIF
- Destination: clipboard
- Capture: H.264 at 30 fps, maximum 1920×1080
- GIF conversion: 15 fps, maximum 960-pixel edge
- Cursor and click rings: enabled
- Maximum duration: 30 seconds
- Audio: disabled

GIF clipboard delivery publishes both GIF data and a file URL. MP4 clipboard
delivery publishes a persistent file URL. Clipboard artifacts are retained in
the app cache for compatibility with applications that read them after the
paste operation.

## Failure recovery

Recording shutdown is idempotent and bounded while waiting for the recording
output to finalize. Startup cancellation, native Stop Sharing, duplicate stop
requests, stale ScreenCaptureKit callbacks, conversion errors, and destination
errors all converge through the same cleanup and recovery flow.

If a usable recording exists after a failure, it remains available from the
menu through **Save Last Recording As…**. Empty and abandoned working files are
removed automatically. Save As stages its copy before atomically replacing an
existing destination.

## Architecture

The Swift package is split into three targets:

- `GifItCore` contains settings, capture state, artifact naming, and recovery
  policies without AppKit or ScreenCaptureKit dependencies.
- `GifItMac` contains ScreenCaptureKit recording, media conversion, clipboard
  and filesystem delivery, permissions, global shortcut registration, and the
  recording panel.
- `GifItApp` contains the SwiftUI menu-bar app, Settings UI, and main-actor
  workflow coordination.

Recording and conversion work run through isolated async services. The app
workflow uses explicit state transitions and injectable service boundaries so
failure behavior can be tested without a live capture session.

## Development

Run the full checks with:

```sh
swift format lint --recursive --strict Sources Tests Package.swift
swift test
swift build -c release
```

The test suite covers state transitions, startup cancellation, stale session
events, repeated stops, recovery policy, clipboard failures, folder failures,
atomic file replacement, cache pruning, GIF metadata, and settings persistence.

## Creating a release

Push a semantic version tag to build and publish an ARM-only GitHub Release:

```sh
VERSION=0.1.1
git tag "v$VERSION"
git push origin "v$VERSION"
```

The release workflow validates the source, creates an ad-hoc-signed app bundle,
checks its signature and version metadata, packages it with `ditto`, generates
a SHA-256 checksum, and attaches both files to the GitHub Release.

## Current scope

Gif It intentionally uses Apple's system content-sharing picker. The picker and
its **Share This Window** confirmation UI are owned by macOS and cannot be
restyled by the app.

Region capture, audio, trimming, captions, editing, launch at login, App Store
sandboxing, and an alternate custom window picker are not currently included.
