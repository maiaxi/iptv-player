# IPTV Player

A native IPTV player for macOS (SwiftUI + libmpv). Supports Xtream Codes accounts and M3U playlists.

- Live TV, movies and series by category, with search
- Favorites and recently watched
- What's on now for each channel, from the provider's XMLTV guide
- Player with auto-hiding controls, full screen, channel list, audio and subtitle tracks
- English and Portuguese, following the system language

## Install

Download the `.dmg` from [Releases](../../releases), drag **IPTV Player** into Applications, then
allow it once in System Settings → Privacy & Security → **Open Anyway** (the app isn't signed by
Apple).

Requires Apple silicon and macOS 15 or later.

## Build

```sh
./scripts/build-app.sh          # builds build/IPTV Player.app
./scripts/make-dmg.sh           # builds build/IPTV-Player-<version>.dmg for sharing
open "build/IPTV Player.app"
```

libmpv and FFmpeg come from [MPVKit](https://github.com/mpvkit/MPVKit) (prebuilt, LGPL) and are
linked statically, so the app doesn't need Homebrew.

For development: `swift build`. With only the Command Line Tools, use
`SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk swift build`: the macOS 27 SDK needs
full Xcode for SwiftUI's macros.

`IPTV_AUTOPLAY=<url> .build/debug/IPTVPlayer` opens the player straight away with that stream (debug
builds only).

## Player shortcuts

| Key | Action |
|---|---|
| Space / click | Pause |
| Double-click / F | Full screen |
| ↑ ↓ | Previous / next channel |
| ← → (⇧ for 1 min) | Back / forward 10 s |
| M | Mute |
| + − | Volume |
| L | Channel list |

## Translations

UI strings are written in English in the code. Translations live in
`Resources/<language>.lproj/Localizable.strings` (keys are the English strings; `Int` interpolations
become `%lld`, `String` ones `%@`) and are copied into the app by `build-app.sh`. To add a language,
add a new `.lproj` and list it under `CFBundleLocalizations` in `Resources/Info.plist`.

## Notes

- No Intel build: the Swift toolchain in the macOS 27 Command Line Tools no longer ships the x86_64
  runtime.
- Sources (including passwords) are stored in `~/Library/Application Support/IPTVPlayer/sources.json`,
  readable only by the current user. The library is cached for 12 h (⌘R refreshes).
