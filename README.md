Verse AltStore widget update

1. In GitHub upload the included VerseWidget folder to the repository root, replacing the existing files. Commit.
2. Edit .github/workflows/build.yml and replace ALL its text with the included build.yml. Commit.
3. Actions > Build Verse > Run workflow.
4. Download Verse-altstore from the successful run and extract Verse-altstore.ipa.
5. Install through AltStore over Verse. Keep app extensions. Use the same Apple account as before.
6. Open Verse and connect Spotify again; play a song and tap Sync.
7. Remove and re-add the Verse widget if its old message persists.

This workflow attaches App Group entitlements with an ad hoc signature so AltStore can detect and provision sharing. AltStore then signs for the device; the ad hoc signature alone is NOT installable.

The app and extension read AltStore's provisioned ALTAppGroups identifier and store Spotify credentials in that group's Keychain. Tokens are never stored in shared preferences or included in this source archive.

The old private login is not migrated automatically. Reconnect after updating. Native build and device installation must still be verified using GitHub and the iPhone. Widget refresh scheduling remains controlled by iOS.


# Verse: Experimental iPhone and CarPlay widget

This is native Swift source with a complete Xcode project. It is not a signed IPA, an installed app, or an App Store approved product. It has not been compiled with Xcode or tested on an iPhone; this workspace has no Apple SDK.

## What is included

- iPhone companion with Spotify PKCE sign-in. No Client Secret is embedded.
- Your supplied Spotify Client ID is configured.
- Automatic LRCLIB timed-lyric lookup and line highlighting in the foreground app.
- A small WidgetKit extension eligible for the CarPlay widget picker on iOS 26+.
- Experimental future timeline entries for the current song's lyric lines.
- Shared snapshot storage using an App Group; tokens in shared Keychain with After First Unlock protection.
- Original demo text, timing adjustment, manual synchronization and disconnect.

## Install using a Mac

1. Use Xcode 26 or newer and an iPhone on iOS 26 or newer. Open `VerseWidget.xcodeproj`.
2. Select the `Verse` scheme. In Signing & Capabilities, select your Apple development team on BOTH targets (`Verse` and `VerseLyrics`). Shared App Groups require a team that can provision that capability; a paid Apple Developer membership may be required.
3. Register the bundle IDs `com.alexfagan.verse` and `com.alexfagan.verse.widget`, the App Group `group.com.alexfagan.verse`, and enable the group for both targets. If any identifier is unavailable, rename it consistently in both targets, both entitlements, and `VerseConfig.appGroup` in `Shared/Models.swift`.
4. Both targets use the SAME provisioned App Group for Keychain sharing. There is no separate VerseKeychainGroup plist setting. For AltStore, use the included build.yml and retain the widget extension; Verse resolves ALTAppGroups at runtime. Do not put tokens into UserDefaults.
5. In Spotify's developer dashboard, add this ADDITIONAL redirect URI exactly: `verse-lyrics-alex-login://spotify/callback`. Keep the existing browser callback. The native app has a different sign-in session; browser tokens do not transfer automatically.
6. If Spotify asks for an iOS bundle ID in app settings, use the final main-app bundle ID. Confirm the current Spotify account is authorized for the development app and meets its Premium requirement.
7. Connect your iPhone to the Mac, select it as the run destination, enable Developer Mode if prompted, and Run the `Verse` scheme. Resolve signing or build errors in Xcode before continuing.
8. Open Verse and tap `Connect Spotify`. Authorize access. Play a song in Spotify and return to Verse to check lyrics, or tap `Try demo` for original test text. The demo disconnects Spotify.
9. While parked, connect CarPlay. On iPhone, open Settings → General → CarPlay → select your car → Widgets → Add Widget → Verse Lyrics. If it does not appear, first add the small Verse Lyrics widget to the iPhone Home Screen, launch Verse once, then reconnect CarPlay.

## Timing limits and behavior

The phone app samples Spotify roughly every four seconds while foregrounded and uses the supplied lyric timestamps to update its view. It does not own Spotify's audio playback. Pauses and seeks may take several seconds to detect. Its poll loop stops when the companion leaves the foreground.

The widget fetches Spotify and LRCLIB when iOS grants a timeline refresh, then schedules the known current song's line changes. This is experimental: Apple recommends timeline entries about five minutes apart and does not guarantee exact entry display times. Short lyric entries may be coalesced, delayed, or skipped. A widget cannot run our browser's animation loop. Song changes, pauses and seeks while the companion is backgrounded may remain stale until iOS grants another refresh. Timing and battery behavior must be measured on a real device. No artificial background audio or private API workaround is included.

Lyrics coverage varies; tracks can be instrumental, unsynced, missing, or have inaccurate timestamps. Only a constant timing offset is adjustable. The app sends track metadata to LRCLIB, never the Spotify access token. API access does not by itself establish publication rights for a lyrics catalog.

CarPlay suitability and review remain unverified. Apple's guide explicitly prohibits lyrics in CarPlay audio apps; this project is a WidgetKit extension, not a CarPlay audio-template app. That distinction is not a promise of approval. No CarPlay audio entitlement is requested.

Disconnect clears credentials and the shared snapshot. Cached widget pixels can remain briefly until iOS processes the reload.

## Checks done here

- Checked XML plists, entitlements and shared scheme.
- Checked Xcode project references and native source files.
- Checked LRC parser sample behavior and timeline date calculations using a portable model.
- No Swift compilation, code signing, device installation, CarPlay simulator run, or battery testing was possible here.

## References

- Apple CarPlay: https://developer.apple.com/carplay/
- Apple CarPlay Developer Guide: https://developer.apple.com/carplay/documentation/CarPlay-App-Programming-Guide.pdf
- Widget timing: https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date
- Spotify PKCE: https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow
- Spotify native redirects: https://developer.spotify.com/blog/2025-02-12-increasing-the-security-requirements-for-integrating-with-spotify
- LRCLIB: https://lrclib.net/docs
