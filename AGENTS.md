# Repository Guidelines

Gif It is a macOS 15+ Swift Package Manager app. Keep pure models and state in
`GifItCore`, macOS frameworks in `GifItMac`, and SwiftUI presentation in
`GifItApp`. The app has no third-party dependencies or Xcode project.

Run `swift test` after changes. Use `./scripts/build-debug.sh` for permission and
capture testing because macOS Screen Recording permission depends on a stable
packaged bundle identity.
