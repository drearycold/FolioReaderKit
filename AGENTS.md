# AGENTS.md

The agent guidance for this repository lives in **[CLAUDE.md](CLAUDE.md)**: build and test commands, architecture, the CSS pipeline, persistence providers, and conventions. Read it before making changes. It is tool-neutral despite the file name. Plans and status are in [ROADMAP.md](ROADMAP.md).

The essentials, in case you read only this file:

- Build and test against an iOS Simulator, never `swift build` (UIKit dependencies):
  ```bash
  xcodebuild test -scheme FolioReaderKit -destination 'platform=iOS Simulator,name=iPhone 17'
  ```
- `master` is the stable branch. Branch from it and open pull requests against it; YetAnotherEBookReader follows it as a remote Swift package (see ROADMAP.md, "Branches and working rules").
- If you change a provider protocol in `Sources/FolioReaderKit/Providers/`, update the Example implementations and `Tests/FolioReaderKitTests/MockHelpers.swift`.
- After an intended styling change, re-record the CSS snapshot in `Tests/FolioReaderKitTests/__Snapshots__/` on purpose (see CLAUDE.md), and review the diff.
- `.gemini/` is git-ignored local tool state; don't commit new files there.
