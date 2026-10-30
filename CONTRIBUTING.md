# Contributing

AppFinder is a personal project, but bug reports and fixes are welcome.

## Issues

- **Bugs:** use the bug report form. For input source problems, name the input method you switch from and how the panel was closed (Esc, Enter, the shortcut, a click elsewhere). A suggested fix is a bonus.
- **Security problems:** report them privately, see [SECURITY.md](SECURITY.md).
- **Feature ideas:** open an issue to discuss it first. AppFinder stays small on purpose: [CLAUDE.md](CLAUDE.md) lists its non-goals (extensions, commands, clipboard, AI, window switching, web search, an index of its own), so not every idea will fit.

## How the project is developed

Most of the code is written by Claude agents on branches merged through pull requests. [CLAUDE.md](CLAUDE.md) holds the rules they follow; they apply to human contributions too. In short:

- Keep logic in `AppFinderCore`, with unit tests. `swift test` passes, and `scripts/build.sh release` builds.
- The input source lock is the reason AppFinder exists. Change it only with the check in CLAUDE.md (`scripts/check-input-source.py`, which takes over the screen), and say in the pull request how you checked it.
- Control code stays in Debug builds; a Release binary must not contain it.
- Never commit signing settings, and never edit or reset the macOS privacy database (TCC).
- Commits, docs and comments in English. Commit messages follow Conventional Commits (`type(scope): message`).

## Pull requests

Describe the change, list the commands you ran and their results, and note anything you could not check.
