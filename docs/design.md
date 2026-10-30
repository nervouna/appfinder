# AppFinder v0.1 design

AppFinder is a keyboard launcher for macOS that opens apps and files. It replaces the two uses of Raycast that remain (open an app, open a file) and adds the one thing Spotlight cannot do: while its panel is open the input source is locked to ABC, and when the panel closes the previous input source (typically a Chinese input method) comes back.

## Scope of v0.1

1. A global hotkey toggles a floating panel with a search field and a result list. The panel never activates AppFinder (non-activating `NSPanel`), so the app in front stays the active app and gets the focus back when the panel closes.
2. Search covers installed apps and files, both from the system Spotlight index. AppFinder builds no index of its own.
3. Fuzzy matching, ranked by match quality and boosted by how often and how recently an item was opened from AppFinder.
4. Keys: Enter opens the selected item, Cmd+Enter reveals it in Finder, Esc closes the panel, Up/Down (and Ctrl+P/Ctrl+N) move the selection. The hotkey pressed while the panel is open closes it. Clicking outside closes it.
5. ABC lock: while the panel is open the input source is ABC and cannot be switched away from it; on close the input source that was active before is restored. This must hold every time, including from and back to a third-party Chinese input method (InkFlow).
6. Launch at login, no Dock icon, a menu bar item (Open, Settings, Quit).
7. The hotkey is configurable in a small Settings window, which also has the launch-at-login switch.

Non-goals for v0.1: extensions, commands, clipboard history, AI, window switching, web search, a custom file index, Mac App Store distribution.

## Default hotkey

| Who | Shortcut |
| --- | --- |
| Raycast (`raycastGlobalHotkey = "Command-14"`, key code 14 = E) | ⌘E |
| Spotlight (symbolic hotkeys 64 / 65, both enabled) | ⌘Space, ⌥⌘Space |
| Input source switching (symbolic hotkeys 60 / 61) | ⌃Space, ⌃⌥Space |
| Piccolo (25 bindings) | ⌃⌥ + letters, digits, arrows, Return, brackets; ⌃⌥⇧ + brackets |

Default: **⌘E**, the shortcut the owner's hands already use for Raycast. It collides with nothing above except Raycast itself, so Raycast has to be quit (or its hotkey cleared by the owner) before AppFinder is used. A global ⌘E also takes "Use Selection for Find" away from every app, which is already the case today with Raycast. AppFinder logs and shows in its menu when the system refuses to register the hotkey.

## Architecture

- Swift 6, AppKit for the panel (search field and result table: predictable focus and key handling in a non-activating panel), SwiftUI for the Settings window. Minimum macOS 26. Not sandboxed (TIS input source selection and system-wide Spotlight queries), hardened runtime on.
- Bundle ID `io.damao.appfinder`. Signed with Developer ID (team T7976FL2LP), notarized for releases.
- Layout follows Piccolo:
  - `Package.swift` with `AppFinderCore` (pure logic: fuzzy matcher, ranking, usage model, hotkey model, pinyin keys if accepted; no AppKit, fully unit tested) and `AppFinderSystem` (adapters: Carbon hotkey, TIS input sources, Spotlight queries, login item, usage file).
  - `AppFinder.xcodeproj` with one thin app target (`App/`, file-system-synchronized group): panel, menu bar item, Settings, wiring.
  - `scripts/build.sh`, `install.sh`, `release.sh` like Piccolo's; signing settings from `${XDG_CONFIG_HOME:-$HOME/.config}/appfinder/signing.env`, never committed.
  - A Debug-only control channel (same-user `CFMessagePort`, `io.damao.appfinder.control`) with a few commands (`panel.show`, `panel.hide`, `panel.state`, `search`, `inputSource.current`), so that the input source behaviour can be checked over hundreds of rounds by a script. Release builds contain none of it.

### Speed

The panel, its views and the app catalog exist from launch on. The hotkey handler only positions the panel on the screen with the mouse pointer, clears the field and orders it front; no query, disk access or view creation happens on that path. The time from the Carbon callback to the panel on screen is logged in Debug builds; the target is under one frame.

### Search

- Apps: a live `NSMetadataQuery` for `kMDItemContentTypeTree == "com.apple.application-bundle"` in `/Applications`, `~/Applications`, `/System/Applications` and `/System/Library/CoreServices/Applications`, plus Finder. Apps nested in other bundles are left out. The catalog stays in memory and follows installs and removals. Each app is matched on its display name (localized, e.g. 系统设置) and its alternate names (`kMDItemAlternateNames`: `System Settings`, `Preferences`, ...), so both the Chinese and the English name find it.
- Files: from the second typed character, a Spotlight query (debounced, the previous one cancelled) for items whose file name contains every typed word, in the home folder, without `~/Library`, hidden paths, bundle contents and `node_modules`. The matches are then ranked by the same fuzzy scorer. Apps are listed first, files after.
- Fuzzy scoring: subsequence match, case and diacritic insensitive, with bonuses for a match at the start, at word boundaries (space, `-`, `_`, `.`, camelCase) and for consecutive characters, and penalties for gaps.
- Usage boost: every open from AppFinder is recorded (item, time, the query typed) in `~/Library/Application Support/AppFinder/usage.json`. The rank adds a frecency term (count with a half-life of about two weeks) and a stronger term when the current query is a prefix of a query that previously led to the item.

### Calculator

- Arithmetic is evaluated locally as the query changes, with no prefix or mode switch. Supports the four basic operations (`+`, `-`, `*`, `/`, `×`, `÷`), parentheses, decimal numbers, unary signs and whitespace, with conventional precedence. A lone number remains a search query.
- A complete equation such as `1+2*3=7` appears in a 64 pt calculation row with no icon or selection fill, above any matching apps and files. The 22 pt equation and smaller secondary shortcut hints align with the section heading. The displayed and copied equation omits whitespace while preserving the typed numbers, operators and parentheses. Parsing still validates the original input, so whitespace cannot merge separate numbers into a valid expression. With no app or file selected, Enter copies only the result and Cmd+Enter copies the equation. Both close through the existing input-source restore path. Down selects the first app or file; Up from that first item returns to the unselected calculation state. App and file rows retain their open and reveal actions. Asynchronous search updates preserve the current selection, including the calculation's no-selection state. Cmd+C still copies selected search-field text.
- Incomplete or invalid expressions do not retain a previous result. Complete expressions that divide by zero or exceed the supported numeric range show an error and cannot be copied. They do not automatically select an app or file below the error.
- Decimal arithmetic avoids binary floating-point tails such as `0.1+0.2=0.30000000000000004`. Results omit redundant trailing zeros and retain Decimal's available precision; display and clipboard use the same value. No calculation history is stored.

### ABC lock and restore

Facts on this Mac: the current source is InkFlow (`io.damao.inputmethod.inkflow.Hans`), ABC (`com.apple.keylayout.ABC`) is enabled, and "Automatically switch to a document's input source" is on (`TextInputGlobalPropertyPerContextInput = 1`), so the system itself remembers an input source per text context.

The known macOS issue: after `TISSelectInputSource` to a CJK input method, the menu bar shows the new source, but the focused text field keeps the old one until the focus moves to another window (reported for Kawa, macism and on the Apple developer forums; still present on macOS 26). macism works around it by selecting the source and then making a window of its own key for a short time (150 ms by default on macOS 26), so the client's input context is activated again with the new source when the focus returns.

AppFinder's sequence uses the fact that the panel is itself such a focus round trip:

- Open: remember the current input source. Make the panel key and the search field first responder; on the field's `NSTextInputContext` set `allowedInputSourceLocales` to Roman input sources only (this is the lock: Ctrl+Space cannot pick InkFlow inside the field) and `selectedKeyboardInputSource` to ABC; also select ABC with TIS. Then verify that the current source is ABC and retry when it is not.
- Close: end editing in the field (its context deactivates), select the remembered source with TIS while the panel still holds the key focus, wait until the system reports the change (bounded), then order the panel out, so that the app behind it gets the focus and activates its input context with the restored source. The panel is made transparent at the start of the close, so it looks instant. When the previous source was ABC, nothing is selected.
- Enter (open an item) restores first, then opens, so the opened app starts with the restored source.

Measured outcome (details in `CLAUDE.md`, "Input source lock"): the sequence above holds for Esc, the hotkey and Enter (300 automated rounds, plus real key presses). A click elsewhere moves the focus before AppFinder can act, and there selecting the source alone failed once in five rounds; there the panel takes the focus back for a moment, invisibly, as macism does. The panel is ordered on screen before it takes the focus and before the source switch, which blocks for 15 to 45 ms.

The exact order and the wait were fixed by measurement on macOS 27, not assumed: a Debug script toggles the panel over a test app hundreds of times and checks, every round, the TIS current source, InkFlow's own activation and deactivation log lines (`io.damao.inputmethod.inkflow`), and that a probe key typed into the app's field after close is composed by InkFlow. If the per-window context rules make one of the steps above unnecessary, it is dropped.

## Decisions

The owner approved the scope above on 2026-10-21 and decided the open questions:

1. **Pinyin matching**: app names match pinyin and pinyin initials (`jisuanqi`, `jsq` → 计算器), precomputed with `CFStringTransform` whenever the catalog changes. File names do not (that would need an own index of file names). English names match through `kMDItemAlternateNames` either way.
2. **Default hotkey**: ⌘E, as Raycast today.
3. **Distribution**: Developer ID signed and notarized releases (`scripts/release.sh`), private GitHub repository.
4. **Calculator (2026-10-31)**: show the full equation, Enter copies the result, Cmd+Enter copies the equation, and both close the panel. Start with basic arithmetic. The final result layout has no icon or selection fill, uses a larger equation and subdued shortcut hints, and displays and copies equations without whitespace.
