# Security

AppFinder runs at login, registers a global shortcut, changes the selected input source, and opens apps and files on your behalf. It can read your Desktop, Documents and Downloads folders once you allow it, and it keeps a record of what you opened and the searches you used. It is not sandboxed. Release builds are signed with a Developer ID and notarized; debug builds also host a local control channel for tests, which release builds do not contain.

## Reporting a vulnerability

Please do not open a public issue for a security problem. Report it privately through GitHub: **Security → Report a vulnerability** on this repository ([direct link](https://github.com/nervouna/appfinder/security/advisories/new)). Include what you did, what happened, and the release or commit you tested.

You will get an answer within a week. Fixes land on `main`; there are no maintained release branches.

## In scope

- A way for another process or a crafted file name to make AppFinder open, run or reveal something you did not choose
- Keys typed into the panel reaching another app, or the input source not being given back
- The usage record or search text leaving the Mac
- A release build that contains debug control code

## Out of scope

- Anything that needs an already compromised user account or administrator access
- Debug builds, which are for development only
- What Spotlight itself indexes or what the opened apps do
