# AppFinder

[![Release](https://img.shields.io/github/v/release/nervouna/appfinder)](https://github.com/nervouna/appfinder/releases/latest)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-lightgrey)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

![AppFinder](docs/images/banner.jpg)

A keyboard launcher for macOS that opens apps and files from the Spotlight index. While its panel is open the input source is ABC, so a Chinese input method never catches your search; when the panel closes, the input source you had before comes back.


## Status

AppFinder is a personal project: its author built it to replace Raycast for opening apps and files, and to fix one thing Spotlight lacks, the input source switch. It also includes a basic offline calculator. It has no extensions, commands, clipboard history or web search. It needs macOS 26 or later and no account. The interface is in English and Simplified Chinese. Releases are notarized zip archives on the [releases page](https://github.com/nervouna/appfinder/releases).

## How it is built

Most of the code is written by Claude Code agents, on branches merged through pull requests, following the rules in [CLAUDE.md](CLAUDE.md): the product scope and non-goals, the architecture, and a measured check that the input source lock must pass before it changes. The design and its decisions are in [docs/design.md](docs/design.md). See [CONTRIBUTING.md](CONTRIBUTING.md) to report a bug or send a fix, and [SECURITY.md](SECURITY.md) for security problems.

## Install

1. Download `AppFinder-<version>.zip` from the [latest release](https://github.com/nervouna/appfinder/releases/latest).
2. Unzip it and move `AppFinder.app` to `/Applications`.
3. Open AppFinder. It has no Dock icon and no window; its icon, a magnifier with an A, appears in the menu bar.

On its first launch AppFinder adds itself to the login items. Turn this off with **Launch at Login** in its menu or **Launch at login** in Settings. If macOS waits for your approval, Settings says so: allow AppFinder in System Settings → General → Login Items.

## Use

- Press ⌘E to open the panel, type, and press Enter to open the selected app or file. ⌘Enter reveals it in Finder. Esc, ⌘E again or a click elsewhere closes the panel.
- Type an arithmetic expression to see the full equation without spaces, such as `1+2*3=7`, above search results. The calculation has no selection highlight: Enter copies the result and Cmd+Enter copies the full equation; both close the panel. Down selects an app or file below it; Up from the first item returns to the calculation. Supports `+`, `-`, `*`, `/`, `×`, `÷`, parentheses, decimals and negative numbers, entirely offline.
- Up and Down, or Ctrl+P and Ctrl+N, move the selection. A double click opens an app or file, or copies a calculation result.
- With an empty search the panel lists what you opened recently.
- Apps are found by their localized name, their other names (often the English one) and the pinyin of a Chinese name, in full or by initials: `jsq` finds 计算器 (Calculator). Matching is fuzzy, so the letters only have to appear in order.
- Files and folders are found by name, in your home folder, once you type two characters. AppFinder leaves out `~/Library`, hidden files, the inside of app bundles and packages, and build and dependency folders such as `node_modules`, `build` and `DerivedData`.
- Results you open often, and the searches you opened them with, rank higher next time. The boost fades over a few weeks.

The menu bar icon's menu has **Open AppFinder**, the current shortcut, **Settings…**, **Launch at Login** and **Quit AppFinder**. Opening AppFinder again while it runs also opens Settings.

### Settings

- **Shortcut**: click the shortcut, then press a new one. It needs ⌘, ⌥ or ⌃, or it must be a function key. **Restore Default** goes back to ⌘E. If another app holds the shortcut, Settings and the menu say it is not available.
- **Launch at login**.
- **Desktop, Documents and Downloads**: whether AppFinder may read these folders, with **Open Privacy Settings** when it may not (see below).

### The input source

When the panel opens, AppFinder selects the ABC keyboard layout (or, on a Mac without ABC, another enabled Latin layout) before your first key reaches the search field, and switches back if anything changes it while the panel is open. When the panel closes, by any route, it selects the input source that was active before, such as a Chinese input method, so the app behind gets its own input source back. Keys typed in the short moment while the panel is closing are dropped.

## Permissions

- **Desktop, Documents and Downloads.** Spotlight leaves files in these folders out of AppFinder's results until macOS has allowed AppFinder to access them. At launch AppFinder reads the three folders once, which makes macOS ask. Settings shows the status and opens Privacy & Security to change it.
- **Login item.** See [Install](#install).

AppFinder does not need the Accessibility or Input Monitoring permission. Its shortcut is a standard global hotkey.

## Privacy

AppFinder makes no network requests. It searches through the Spotlight index and keeps no index of its own. It stores two things on your Mac:

- `~/Library/Application Support/AppFinder/usage.json`: the paths of the apps and files you opened from it, how often and when, and the searches you opened them with. It is used only for ranking.
- Its settings (the shortcut, and whether the login item was set up) in the `io.damao.appfinder` defaults domain.

## Uninstall

1. Turn off **Launch at Login** in the menu, then choose **Quit AppFinder**.
2. Delete `/Applications/AppFinder.app`.
3. Delete `~/Library/Application Support/AppFinder`, and run `defaults delete io.damao.appfinder` to remove the settings.
4. Remove AppFinder from the folder permissions in System Settings → Privacy & Security → Files & Folders, if you granted them.

## Development

Requires macOS 26 and Xcode. Run from the root of the checkout:

```sh
swift test
scripts/build.sh debug
scripts/install.sh            # Release build to /Applications (needs the signing settings)
scripts/release.sh            # notarized zip in build/release/
```

Signing settings live in `${XDG_CONFIG_HOME:-$HOME/.config}/appfinder/signing.env` and are never committed; `scripts/install.sh` refuses unsigned builds. See [CLAUDE.md](CLAUDE.md) for the architecture, the Debug control channel and the input source check, and [docs/design.md](docs/design.md) for the design.

### Publish a release

Update the version in `AppFinder.xcodeproj/project.pbxproj` and commit it first. Publishing requires a clean `main` branch, the signing and notarization settings above, and an authenticated GitHub CLI (`gh`). Then run:

```sh
scripts/release.sh --publish
```

This runs the tests, builds and verifies the notarized archive, creates the version tag, pushes `main` and the tag, and uploads the ZIP and its SHA-256 file to a draft GitHub Release. It publishes the draft only after checking the uploaded assets. Release notes are generated automatically; add `--notes-file /path/to/release-notes.md` to supply your own.

If publishing is interrupted, rerun the same command at the same commit. Keep `build/release/`: its `release-commit`, ZIP and `.zip.sha256` files let the script reuse the verified archive and finish an incomplete draft without rebuilding or notarizing again. A draft that already has assets cannot be resumed without the matching local cache. Published releases and conflicting tags or assets are never overwritten.

Without `--publish`, the script only prepares the local archive. `--skip-notarize` is for local packaging checks and cannot be combined with `--publish`.

## License

MIT. See [LICENSE](LICENSE).
