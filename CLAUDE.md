# AppFinder

AppFinder is a macOS menu bar launcher that opens apps and files. It replaces the owner's use of Raycast for those two things and adds what Spotlight lacks: while its panel is open the input source is locked to ABC, and the previous input source (the owner's own InkFlow input method) comes back when it closes. Design and decisions: `docs/design.md`.

Personal project, single user. Write commits, docs and comments in English; Conventional Commits (`type(scope): message`).

## Product scope

1. Menu bar app, no Dock icon (`LSUIElement`), launches at login (registers itself once on the first launch of a Release build; the switch is in the menu and in Settings).
2. A global hotkey (default ⌘E, as Raycast had; configurable in Settings) toggles a floating, non-activating panel.
3. Apps and files come from the Spotlight index; AppFinder keeps no index of its own. Apps match on the localized name, the alternate names and their pinyin (full and initials); files match on their name, in the home folder.
4. Fuzzy matching, ranked by match quality plus a usage boost (decaying use count and the queries that led to an item).
5. Enter opens, Cmd+Enter reveals in Finder, Esc closes, Up/Down and Ctrl+P/Ctrl+N move. A click elsewhere closes.
6. ABC lock and restore, every time, also from and back to a third-party Chinese input method.

Non-goals: extensions, commands, clipboard, AI, window switching, web search, an own file index, Mac App Store.

## Architecture

- Swift 6, AppKit panel, SwiftUI Settings. Minimum macOS 26. Not sandboxed, hardened runtime. Bundle ID `io.damao.appfinder`.
- `Package.swift`:
  - `AppFinderCore`: pure logic, unit tested. `SearchKey` (folded name with word starts), `FuzzyMatcher` (optimal alignment, fzf v2 style), `Pinyin` (system transliteration plus a table of polyphonic readings, `alternateReadings`), `SearchItem`, `Ranker`, `UsageBook`, `Shortcut`, `FileFilter`.
  - `AppFinderSystem`: `TISInputSources` and `InputSourceLock`, `CarbonHotkey`, `AppCatalog` (live `NSMetadataQuery`), `FileSearch` (`MDQuery` on a serial queue), `UsageStore` (`~/Library/Application Support/AppFinder/usage.json`), `LoginItem`.
  - `AppFinderControl`: the Debug control channel (`CFMessagePort`). `appfinderctl`: its command line client.
- `AppFinder.xcodeproj` (file-system-synchronized groups, edited by hand, no generators): the app (`App/`) and the Debug-only test app `AppFinderFixture` (`Fixture/`). `AppFinderControl` is linked into the app in Debug only (build-only dependency plus `OTHER_LDFLAGS`), and all control code is under `#if DEBUG`; a Release binary must not contain it.
- `App/SearchController.swift` holds the panel logic: open, close, results, keys, the lock. The panel never makes AppFinder the active app, so there is no menu bar: the Edit shortcuts (⌘A, ⌘C, ⌘X, ⌘V, ⌘Z, ⇧⌘Z) are handled by the panel itself, with an undo manager of its own. The list is a plain table whose height is computed from its rows and grows up to eight rows before it scrolls. The glass view is clipped to its rounded corners, or the window server draws the shadow and a hard rim around the whole rectangle. Settings (`App/Settings.swift`) keeps the shortcut in AppFinder's defaults domain.
- Texts: `App/Localizable.xcstrings`, English and Simplified Chinese, written by hand, macOS terms (设置, 快捷键, 登录时打开).

## Input source lock

This is the reason AppFinder exists; change it only with the check below. Measured on macOS 27 with InkFlow, "Automatically switch to a document's input source" on:

- `TISSelectInputSource` blocks for 15 to 45 ms (rarely about 500 ms, InkFlow's activation). So the panel is ordered on screen and drawn first (`orderFrontRegardless` + `CATransaction.flush`, 3 to 10 ms), and only then takes the key focus and selects ABC. The hotkey is still held at that point, and later keys wait in the queue until ABC is selected.
- The search field's input context gets `allowedInputSourceLocales = [NSAllRomanInputSourcesLocaleIdentifier]` while open, and a change of the selected source while open selects ABC again.
- Close (Esc, hotkey, Enter): the panel goes transparent at once, the field resigns, the remembered source is selected while the panel still has the key focus, then the panel orders out after the system reports it (plus `Tuning.settle`). The app behind gets the focus back and activates its text with the restored source. 300 rounds of this passed; even with no settle at all.
- Close by a click elsewhere: the focus has already moved. The system's per-document switching does not restore InkFlow reliably (AppFinder never becomes the active app, so ABC can get recorded for the document behind the panel), and selecting the source after the focus moved can leave the menu bar on InkFlow while keys still go to ABC (the known CJK issue, reproduced once in five). So the panel takes the key focus back for a moment, invisibly, selects the source, waits `Tuning.refocusSettle` and lets go (macism's workaround). Checked with real clicks.
- Keys typed while the panel is closing are swallowed (typically 30 to 80 ms).

## Protected folders

Spotlight leaves files in Desktop, Documents and Downloads out of AppFinder's results until the user allowed AppFinder to access each folder (`mdfind` in a terminal still finds them). `FolderAccess.check()` reads the three folders at launch, off the main thread, which makes the system ask once; Settings shows whether access is allowed and links to Privacy & Security. Never reset or edit TCC.

## Build, sign, run

- `swift test` runs the unit tests.
- `scripts/build.sh [debug|release]` builds `build/AppFinder.app` (and in Debug `build/AppFinderFixture.app`).
- `scripts/install.sh [debug|release]` (default `release`) builds, replaces `/Applications/AppFinder.app` and launches it. It refuses ad-hoc builds.
- `scripts/release.sh [--skip-notarize]` builds a Developer ID signed, notarized and stapled `build/release/AppFinder-<version>.zip`.
- Signing settings are never committed: scripts source `${XDG_CONFIG_HOME:-$HOME/.config}/appfinder/signing.env` (`APPFINDER_CODESIGN_IDENTITY`, `APPFINDER_TEAM_ID`, `APPFINDER_NOTARY_*`). Never read or print the notary key files.
- Icon: `App/AppIcon.icon` is an Icon Composer document (four SVG layers with light and dark colours) that Xcode compiles into `Assets.car` and `AppIcon.icns`; geometry, palette and the reasons in `design/README.md`. After changing it, `scripts/render-icon.sh` renders `design/icon-preview.png` (all appearances, with `ictool`), and `scripts/check-icon-render.sh` checks a Release build's icon and renders it as the system draws it.

## Debug control channel and the input source check

- A Debug build serves `io.damao.appfinder.control`: `status`, `panel.show` (the hotkey's path), `panel.toggle`, `panel.hide` (Esc's path; answers after the source is handed back), `panel.state` (rows, input source, `lastOpen` and `lastClose` with timings), `panel.query {text, waitMs}`, `panel.probe`, `panel.key {keyCode, command?, shift?}` (a key press through `NSApp.sendEvent`), `inputSource.current`, `tuning.set {settleMs, reportTimeoutMs}`, `settings.open`, `settings.close`. Try them with `swift run appfinderctl app <command> '<json>'`.
- The fixture (`io.damao.appfinder.fixture`, a window with one text view) serves `state`, `focus`, `select {id}` (selects a source from inside its text view), `probe`, `clear`, `quit`.
- A probe types "ni" into the field or text view through its input context with key events from a private `CGEventSource`; `composed` says whether an input method made marked text of it. That is the ground truth: TIS and the context's `selectedKeyboardInputSource` can both report InkFlow while keys still go to ABC.
- `scripts/check-input-source.py [--rounds N] [--focus-lost]` runs the Debug AppFinder over the fixture and probes both sides every round. It takes the front of the screen; tell the owner before running it. The fixture cannot take the key focus back from the panel by itself, so `--focus-lost` mostly reports "focus not taken"; check the click path with real clicks (computer use) instead.
