# FolioReaderKit Roadmap

This is the umbrella plan for this fork. It brings together the open FolioReaderKit issues, the FolioReader-related issues from [YetAnotherEBookReader](https://github.com/drearycold/YetAnotherEBookReader) (YAEBR), and the remaining items from the earlier refactor roadmap ([`.gemini/REFACTOR_PLAN.md`](.gemini/REFACTOR_PLAN.md), which covers P0–P3, A-1 and B-1, all done). Update the status column as work lands.

Status: ✅ done · 🔄 in progress · ⬜ not started · ⏸ deferred

## Branches and working rules

| Branch | Role |
|---|---|
| `styling-optimization` | Integration branch for this umbrella. It merges into `master` once Phases 0–2 are done. |
| `codex/dsreader` | D.S.Reader RAG line: reference resolver and keyword search, after `9493f33`. It pairs with YAEBR's `codex/dsreader-advanced-qa-integration`. |
| `master` | Untouched until the umbrella PR. |

- YAEBR links this repository as a **local package**, so it builds against whatever branch is checked out. Keep the checkout on `styling-optimization` while the umbrella is in progress, and use worktrees for side work.
- After every merge or series of commits, run the FolioReaderKit tests **and** build YAEBR `main` against the checkout (commands below).
- When RAG work resumes, merge `styling-optimization` into `codex/dsreader`, not the other way round.

## Phases

### Phase 0: Converge branches ✅

| Item | Status | Notes |
|---|---|---|
| Bring the generic `codex/dsreader` prefix (`fac65e5`, `d6a74a3`, `9493f33`) into `styling-optimization` | ✅ | Merged in `0efa64a`. Adds `showCloseButton`, `forceBottomMenuTabBar`, `reserveSafeAreaInsidePageFrame` / `reservePageIndicatorInsidePageFrame` and the zero-margin fix. |
| Port the prefix's CSS tests to `FolioReaderCSSBuilder` | ✅ | They were the only uses of the removed `FolioReaderScript.cssInjection`. |
| YAEBR `main` builds against this checkout | ✅ | Its FolioReaderKit tests pass (`ReaderPreferenceRepositoryTests`, `FolioReaderProviderBookIdTests`). |

### Phase 1: Docs and housekeeping 🔄

| Item | Status |
|---|---|
| This roadmap | ✅ |
| CHANGELOG: breaking CSS API removal (`ReaderCSSGenerator`, `FolioReader.CssLevels` / `CssImgLevels`, `generateRuntimeStyle`, `cssGenerator`), `customStyleSheets`, scroll-direction default change (`e7fe701`), page-frame and close-button config | ✅ |
| README: bookmarks, `customStyleSheets` usage, page-frame config | ✅ |
| `AGENTS.md`: fix drift (`Sources/FolioEPUBCore`, port in `EpubResourceServer`, stale line references) or point it at `CLAUDE.md` | ✅ |
| Delete `.travis.yml` (CocoaPods/workspace no longer exist); fix `.jazzy.yaml` and confirm `jazzy` runs | 🔄 Deleted and fixed; the jazzy `xcodebuild` arguments build, but jazzy itself is not installed here, so the run is unconfirmed |

### Phase 2: CI (REFACTOR_PLAN C-3) 🔄

| Item | Status |
|---|---|
| GitHub Actions on macOS with Xcode 26: `xcodebuild test -scheme FolioReaderKit` on an iPhone simulator (includes snapshot and WebKit tests); build the Example and Storyboard-Example schemes | 🔄 `.github/workflows/test.yml` added; every step's command passes locally. The first hosted run happens on the umbrella PR. |

### Phase 3: Styling optimization (measure first)

| Item | Status | Notes |
|---|---|---|
| Unified CSS pipeline (`FolioReaderCSSBuilder` / `FolioReaderCSSInjector`), `customStyleSheets`, debug dumps gated on `.htmlStyling` | ✅ | `29c68ea`; snapshot test in `de3b5d9` |
| `os_signpost` intervals for each `didFinish` stage, plus resource-server request timing; baseline below | ⬜ | |
| Fix the invalid `margin-*: --2.5vw` rules for padding level 0 (`.folioStyleBodyPadding*0 img.folioImg`); re-record the snapshot on purpose | ⬜ | 4-line snapshot diff |
| Inject only the selected font family's rules, as a runtime sheet, instead of every `UIFont.familyNames` entry on every page | ⬜ | |
| Emit only the current level rules at runtime | ⏸ | Only if the baseline shows style cost matters |

### Phase 4: Reader fixes driven by YAEBR issues

| Issue | Item | Status |
|---|---|---|
| YAEBR #99 | EPUB open performance. Profile first. Candidates: re-parse on every `viewWillAppear` (no once-only guard); a new `Archive` per resource request in `EpubResourceServer`; main-actor work in `tempFixForHighlights` / `updateBundleInfo` | ⬜ |
| YAEBR #57 | Paged mode: scrolling resets the content offset. Reproduce in the Example app, fix, add a regression test | ⬜ |
| YAEBR #27, #17 | Rotation and resize precision. Replace `pageOffsetRate` restore with a CFI or element anchor (`readium-cfi` is bundled; `FolioReaderReadPosition.cfi` exists) | ⬜ |
| YAEBR #48 | `isShare` no longer exists; sharing is `allowSharing` plus `isSharingHighlight`. Re-test in YAEBR, then close or fix | ⬜ |
| YAEBR #100, #41 | FolioReaderKit part only: round-trip tests for `FolioReaderReadPosition` (`cfi`, `takePrecedence`) through `FolioReaderReadPositionProvider` | ⬜ |
| (lesson from YAEBR) | A failing highlight injection must not block page load or position restore. WebKit test for the `didFinish` chain | ⬜ |
| (from `e7fe701`) | The unsaved scroll direction now comes from `config.scrollDirection`, so right-to-left books lost their paged default (`defaultScrollDirection`). Fixed with an RTL-aware fallback after parsing (`ReaderPreferences.parsedBookScrollDirection`). Unit-tested; no RTL sample book to check it end to end | ✅ |

### Phase 5: FolioReaderKit feature issues

| Issue | Item | Status |
|---|---|---|
| #6 | Xcode 26: re-verify after Phases 0 and 2, then close | ⬜ |
| #7 | Highlights: document them and demo them in the Example app. Keyword search lives on the RAG line, entangled with the reference resolver (`c0840b8`); decide with the RAG roadmap | ⏸ |
| #8 | Bookmarks: add an in-memory `FolioReaderBookmarkProvider`, plus a read-position provider, to the Example app and document them | ⬜ |

### Phase 6: Backlog (not scheduled)

- YAEBR #18 dual page mode.
- YAEBR #28 side-by-side reading. `MultipleInstance-Example` shows two readers on iPad.
- REFACTOR_PLAN: B-2 API docs, C-2 coverage, A-2 strict concurrency (start with `targeted`), B-3 accessibility, A-3 iOS 16 minimum.

Out of scope here: YAEBR #62 (Readium), PDF issues (#93, #95, #96), app-only YAEBR issues, and the RAG line itself.

## Performance baseline

Record time from open to first page and the per-stage signposts before and after each Phase 3/4 change (iPhone 17 simulator, Debug).

| Book | Open → first page | Runtime style | Notes |
|---|---|---|---|
| The Silver Chair | – | – | |
| Population (人口原理) | – | – | |
| EPUB with many entries | – | – | |

## Verification

```bash
# FolioReaderKit
xcodebuild test -scheme FolioReaderKit -destination 'platform=iOS Simulator,name=iPhone 17'
# Example apps
xcodebuild -project Example/Example.xcodeproj -scheme Example -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -project Example/Example.xcodeproj -scheme Storyboard-Example -destination 'platform=iOS Simulator,name=iPhone 17' build
# YAEBR main against this checkout (run from a sibling YetAnotherEBookReader checkout)
xcodebuild -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -destination 'platform=iOS Simulator,name=iPhone 17' build
```

## Draft issue replies (not posted)

**FolioReaderKit #6, Xcode 26**
> Re-verified with Xcode 26 on the iPhone 17 simulator after the latest integration work. The package builds and its test suite passes. Closing this. If you still hit a build error, please reopen with the compiler output and how you integrate the package.

**FolioReaderKit #7, highlights and search**
> Highlights are supported: select text and choose Highlight, or Highlight with a note. To persist them, supply a `FolioReaderHighlightProvider` through `FolioReaderDelegate.folioReaderHighlightProvider(_:)`. In-book keyword search is being developed on a feature branch. We'll update this issue when it lands on `master`.

**FolioReaderKit #8, bookmarks**
> Bookmarks are supported through the `FolioReaderBookmarkProvider` protocol, which you return from `FolioReaderDelegate.folioReaderBookmarkProvider(_:)`. The reader includes a bookmark list and bookmark notes. The Example app will gain an in-memory bookmark provider to show the integration.

**YAEBR #48, `isShare` broken**
> FolioReaderKit no longer has `isShare`. Sharing is now controlled by `FolioReaderConfig.allowSharing` and the Share action in the selection menu. We'll re-test sharing in the app and close this if it works.
