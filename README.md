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

Runs on Apple silicon and Intel Macs with macOS 15 or later.

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

Local builds target this Mac's architecture. With full Xcode, `ARCHS="arm64 x86_64" ./scripts/make-dmg.sh`
builds a universal app; `VERSION` and `BUILD_NUMBER` override the version in `Info.plist`.

## Releases

GitHub Actions builds a universal DMG on every push to `main` and every pull request (kept as a
workflow artifact). To publish a release, push a version tag:

```sh
git tag v1.2.3 && git push origin v1.2.3
```

The workflow builds the app as version 1.2.3 and attaches the DMG to the `v1.2.3` release, creating
it if needed.

### Auto-updates

The app updates itself with [Sparkle](https://sparkle-project.org): it checks
`releases/latest/download/appcast.xml` once a day, and **IPTV Player → Check for Updates…** checks
right away. The release workflow signs each DMG and writes that `appcast.xml` with
`scripts/make-appcast.sh`.

Updates are signed with an EdDSA key. The public half is `SUPublicEDKey` in `Resources/Info.plist`;
the private half is the `SPARKLE_ED_PRIVATE_KEY` repository secret, with a copy in the maintainer's
login keychain (account `dev.maiaxi.iptvplayer`). If the private key is lost, installed copies can't
verify new updates any more, so keep that keychain item backed up.

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

- Intel builds need full Xcode (the Swift toolchain in the macOS 27 Command Line Tools no longer
  ships the x86_64 runtime), so universal builds come from GitHub Actions.
- Sources (including passwords) are stored in `~/Library/Application Support/IPTVPlayer/sources.json`,
  readable only by the current user. The library is cached for 12 h (⌘R refreshes).
