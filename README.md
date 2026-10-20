# AppFinder

A keyboard launcher for macOS that opens apps and files, and keeps the input source on ABC while you type a search.

- Press ⌘E (configurable) to open the panel, type, press Enter to open, Cmd+Enter to reveal in Finder, Esc to close.
- Apps and files come from the Spotlight index. Apps are found by their localized name, their English name and their pinyin (`jsq` finds 计算器). Files are found by name in your home folder.
- Results you open often, and the queries you open them with, rank higher next time.
- While the panel is open the input source is ABC; when it closes, the input source you had before (for example a Chinese input method) comes back.
- Menu bar app, no Dock icon, launches at login.

Requires macOS 26 or later.

## Development

```sh
swift test
scripts/build.sh debug
scripts/install.sh            # Release build to /Applications (needs the signing settings)
scripts/release.sh            # notarized zip in build/release/
```

See `CLAUDE.md` for the architecture and `docs/design.md` for the design.

## License

MIT
