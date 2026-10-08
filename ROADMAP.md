# FolioReaderKit Roadmap

This is the umbrella plan for this fork. It brings together the open FolioReaderKit issues, the FolioReader-related issues from [YetAnotherEBookReader](https://github.com/drearycold/YetAnotherEBookReader) (YAEBR), and the remaining items from the earlier refactor plan (P0–P3, A-1 and B-1, all done). That plan lived in `.gemini/REFACTOR_PLAN.md` until its open items were folded in here; read it with `git show 33fcc5a:.gemini/REFACTOR_PLAN.md`. Codes such as A-2 and C-3 refer to it. Update the status column as work lands.

Status: ✅ done · 🔄 in progress · ⬜ not started · ⏸ deferred

YetAnotherEBookReader issues are never marked ✅ here and are never closed from this repo; see the working rules.

## Branches and working rules

| Branch | Role |
|---|---|
| `styling-optimization` | Integration branch for this umbrella. It merges into `master` once Phases 0–2 are done. |
| `codex/dsreader` | D.S.Reader RAG line: reference resolver and keyword search, after `9493f33`. It pairs with YAEBR's `codex/dsreader-advanced-qa-integration`. |
| `master` | Untouched until the umbrella PR. |

- YAEBR links this repository as a **local package**, so it builds against whatever branch is checked out. Keep the checkout on `styling-optimization` while the umbrella is in progress, and use worktrees for side work.
- After every merge or series of commits, run the FolioReaderKit tests **and** build YAEBR `main` against the checkout (commands below).
- When RAG work resumes, merge `styling-optimization` into `codex/dsreader`, not the other way round.
- **Never close YetAnotherEBookReader issues** from FolioReaderKit work. A FolioReaderKit fix can leave related problems in the app, so those issues stay open; rows below record the FolioReaderKit part only.

## Phases

### Phase 0: Converge branches ✅

| Item | Status | Notes |
|---|---|---|
| Bring the generic `codex/dsreader` prefix (`fac65e5`, `d6a74a3`, `9493f33`) into `styling-optimization` | ✅ | Merged in `0efa64a`. Adds `showCloseButton`, `forceBottomMenuTabBar`, `reserveSafeAreaInsidePageFrame` / `reservePageIndicatorInsidePageFrame` and the zero-margin fix. |
| Port the prefix's CSS tests to `FolioReaderCSSBuilder` | ✅ | They were the only uses of the removed `FolioReaderScript.cssInjection`. |
| YAEBR `main` builds against this checkout | ✅ | Its FolioReaderKit tests pass (`ReaderPreferenceRepositoryTests`, `FolioReaderProviderBookIdTests`, 54 tests). Re-checked on 2026-10-07 against `0979c7c` (custom-property styling, storyboard initializer, single scroll-direction rule), and again after the reused-config scroll-direction fix. |

### Phase 1: Docs and housekeeping 🔄

| Item | Status |
|---|---|
| This roadmap | ✅ |
| Fold the open items of `.gemini/REFACTOR_PLAN.md` into this roadmap and stop tracking that file | ✅ |
| CHANGELOG: breaking CSS API removal (`ReaderCSSGenerator`, `FolioReader.CssLevels` / `CssImgLevels`, `generateRuntimeStyle`, `cssGenerator`), `customStyleSheets`, scroll-direction default change (`e7fe701`), page-frame and close-button config | ✅ Brought up to date with the `--folio-*` styling and its `<body>` class change, the single scroll-direction rule (`0979c7c`), and the storyboard initializer |
| README: bookmarks, `customStyleSheets` usage, page-frame config | ✅ |
| `AGENTS.md`: fix drift (`Sources/FolioEPUBCore`, port in `EpubResourceServer`, stale line references) or point it at `CLAUDE.md` | ✅ |
| Delete `.travis.yml` (CocoaPods/workspace no longer exist); fix `.jazzy.yaml` and confirm `jazzy` runs | ✅ Deleted; `.jazzy.yaml` builds with `xcodebuild` and documents both modules (jazzy 0.15.5: 952 public symbols, 23% documented) |
| API reference on GitHub Pages: `docs/` untracked and git-ignored, `.github/workflows/docs.yml` runs jazzy and deploys on pushes to `master` | 🔄 Pages enabled with the Actions source; the first deploy happens when the workflow reaches `master` |

### Phase 2: CI (refactor plan C-3) 🔄

| Item | Status |
|---|---|
| GitHub Actions on macOS with Xcode 26: `xcodebuild test -scheme FolioReaderKit` on an iPhone simulator (includes snapshot and WebKit tests); build the Example and MultipleInstance-Example schemes (Storyboard-Example removed; MultipleInstance-Example covers the storyboard path) | 🔄 `.github/workflows/test.yml` added; every step's command passes locally. The first hosted run happens on the umbrella PR. |

### Phase 3: Styling optimization (measure first) ✅

| Item | Status | Notes |
|---|---|---|
| Unified CSS pipeline (`FolioReaderCSSBuilder` / `FolioReaderCSSInjector`), `customStyleSheets`, debug dumps gated on `.htmlStyling` | ✅ | `29c68ea`; snapshot test in `de3b5d9` |
| `os_signpost` intervals for each `didFinish` stage, plus resource-server request timing; baseline below | ✅ | `Signposts.swift`; baseline recorded |
| Fix the invalid `margin-*: --2.5vw` rules for padding level 0 (`.folioStyleBodyPadding*0 img.folioImg`); re-record the snapshot on purpose | ✅ | 4-line snapshot diff; recorded with `TEST_RUNNER_FOLIO_RECORD_SNAPSHOTS=1` |
| Inject only the selected font family's rules, as a runtime sheet, instead of every `UIFont.familyNames` entry on every page | ✅ | `RuntimeStyleJS` median 30.2 → 18.8 ms; live font switching checked on the simulator |
| Emit only the current level rules at runtime | ❌ dropped | `RuntimeStyleJS` is ~19 ms of a ~1.9 s page load; the fixed delays are the target (Phase 4) |
| Replace the ~400 per-value level rules with fixed rules that read `--folio-*` custom properties; font family becomes a property instead of a runtime sheet | ✅ | `ReaderStyleRenderingTests` computed-style snapshot unchanged |
| Stop tying the `folioImg` size limit to the text indent setting (fixed 84vh/84vw, the old default), and stop applying paragraph spacing to `<body>` under AllText | ✅ | Snapshot diff limited to `body` margins and image limits |

### Phase 4: Reader fixes driven by YAEBR issues

| Issue | Item | Status |
|---|---|---|
| YAEBR #99 | EPUB open performance. With `big.epub` (4,994 entries), `BookOpen` is 159 ms and `ParseEpub` 132 ms, so FolioReaderKit's parsing is not the bottleneck; time to the first page was dominated by the delays fixed above. Fixed: `viewWillAppear` re-parsed the book and re-applied the opening position on every reappearance (test: `ContainerLoadTests`). Still to check: a new `Archive` per resource request (Resource median 2–6 ms, low priority) and the YAEBR side of opening | 🔄 |
| YAEBR #57 | Paged mode: scrolling resets the content offset. Likely root cause found: when the host shows the reader again (YAEBR's SwiftUI tabs), the container re-parsed the book, re-applied the position it was opened at and reloaded, which jumped back. Fixed with the #99 guard; confirm in YAEBR | 🔄 |
| YAEBR #27, #17 | Rotation and resize precision. Rotation now restores to the last recorded CFI (the text at the top of the screen) via `handleAnchor`, falling back to `pageOffsetRate` when there is no usable CFI (`fa2cc7d`). Checked on the iPhone 17 simulator, 1984.epub, paged, 2026-10-07: a single rotation keeps the text (the portrait top line is on the landscape page, `TRANS3 restoring cfi=…/22/1:17`). **Repeated rotations drift backwards:** after each restore the reader records the new page's first text as the position, and a page usually starts before the anchor, so the next rotation restores from an earlier CFI. Two portrait/landscape round trips went `/22/1:17` → `/20/1:193` → `/16` → `/10/1:0`, ending near the chapter start without the user paging. Carrying extra rotation-only anchor state around was judged too inelegant. **Direction, from a model experiment:** in paged mode, record the middle of the visible text instead of its first character; restore stays "show the page that holds it". Model: a `WKWebView` with the reader's CSS and `-webkit-paged-x`, positions as character offsets (not through `getVisibleCFI` or CFI generation), 1984 ch. 1 and 3 and The Silver Chair ch. 6, starting at 20/50/80 %, layouts iPhone portrait/landscape, iPad portrait/landscape, a 320 pt split view and 20→26 px font, as 4 round trips between pairs and 20-step random sequences (252 runs, 25 excluded where WebKit timed out). Back in the start layout, recording the first character drifted back 4–10 pages after 4 round trips (up to 21 in random sequences) and was on the original page at 8/205 returns; recording the middle averaged ±0.3 pages, stayed within ±1 page in every pair test, and was on the original page at 135/200 returns, reaching 2–3 pages either way only in random sequences (half a large page can span about two small ones). Scroll mode needs no change: top-first recording restored to the top drifts −0.06 to −0.20 screens on average (worst 0.45), and a centered middle is no better. Old saved positions (page starts) still restore to the same page in paged mode. Not yet covered: vertical writing mode, and the real `getVisibleCFI` / CFI round trip | 🔄 |
| (from the `fa2cc7d` re-test) | In landscape the page frame doesn't keep clear of the Dynamic Island: the ends of the lines on that side run under it (iPhone 17 simulator, 1984.epub, paged). Check `reserveSafeAreaInsidePageFrame` and the frame calculation for left/right safe-area insets | ⬜ |
| (from the `0dc3047` review) | `FolioReaderPageFrameCalculator.anchorBoundsFrame` adds the reserved status bar height twice in horizontal writing mode (y = status bar + top margin + status bar again); the refactor kept it and marked it as historical. The frame places `FolioReaderAnchorPreview`, which is presented over the full screen, where one status bar height looks right. Check by tapping an in-book anchor link (a footnote) with the safe area reserved; 1984 and The Silver Chair have no such links, so this needs another book. The refactor itself was checked against the old calculator on 368,640 input combinations: identical apart from negative sizes now clamped to zero | ⬜ |
| YAEBR #48 | Sharing works end to end (chooser, then the system share sheet), but on iOS 16+ the menu item was labelled "S" and the chooser was anchored at the zero rect, under the status bar. Fixed: localized `Share` title, chooser anchored at the selection (`sharePresentationRect`), share sheet anchored in the web view's coordinates. Checked on the iPhone 17 simulator. Note: the Example app sets `allowSharing = false`  Also on iOS 16+, the highlight menu showed placeholder letters ("C", "R", "Y"/"G"/"B"/"P"/"U") for its icons; those and Share are now icon-only actions with VoiceOver labels (`MenuIconTests`), checked in light and dark mode | 🔄 FolioReaderKit part done; issue stays open |
| YAEBR #100, #41 | FolioReaderKit part only. Fixed a race: `save(readPosition:)` ran on a concurrent queue, so rapid saves could leave an older position winning and several marked `takePrecedence` (test: `testRapidSavesKeepOnlyTheLastPositionWithPrecedence`, which failed 3/3 before). Saves are now serialized. Sync itself stays in YAEBR | 🔄 FolioReaderKit part done; issue stays open |
| (lesson from YAEBR) | A failing highlight injection must not block page load or position restore. `Bridge.js` already reports per-highlight errors (`BridgeHighlightTests`), and JS errors can't stall the chain because `evaluateJavaScript` always calls back. The one stall, a released web view, now continues | ✅ |
| (from the baseline) | Replace the page-load chain's fixed `asyncAfter` delays with readiness signals (layout-settled callbacks), which make up most of the ~1.8 s per page | ✅ `WebViewLayoutWaiter`: overflow, runtime-style, page-info and padding waits; the old delay is now only a timeout. The waits in `setScrollDirection`, `updateViewerLayout` and after animated scrolls remain |
| (from the `259c031` review) | Layout waits on off-screen pages time out. When paging preloads a neighbouring chapter, its web view's `contentSize` is still 980×1614 while JS reports the laid-out size (804×662, 38994×662). 980 px is WebKit's fallback layout width, so the off-screen view apparently hasn't committed any layout at its real size since it loaded, and each of those waits runs to its timeout (about 0.2 s, the overflow stage). 1984.epub, paged, opening and paging six times: 2 of 18 waits, both preloads. Confirm the cause, then skip or defer the wait for off-screen pages, or re-measure when the page comes on screen. Check that page counts stay right for preloaded pages | ⬜ |
| (from `e7fe701`) | The unsaved scroll direction now comes from `config.scrollDirection`, so right-to-left books lost their paged default (`defaultScrollDirection`). Fixed with an RTL-aware fallback after parsing, since replaced by one rule, `ReaderPreferences.resolveScrollDirection` (saved choice, else configured direction, else paged for RTL), applied when the view loads and again after parsing (`0979c7c`). A stored `.defaultVertical` placeholder counts as no choice, so RTL books also page with YAEBR's provider. Unit-tested; no RTL sample book to check it end to end | ✅ |

### Phase 5: FolioReaderKit feature issues

| Issue | Item | Status |
|---|---|---|
| #6 | Xcode 26: re-verify after Phases 0 and 2, then close | ⬜ |
| #7 | Highlights: document them and demo them in the Example app. Keyword search lives on the RAG line, entangled with the reference resolver (`c0840b8`); decide with the RAG roadmap | ⏸ |
| #8 | Bookmarks: add an in-memory `FolioReaderBookmarkProvider`, plus a read-position provider, to the Example app and document them | ⬜ |

### Phase 6: Backlog (not scheduled)

- YAEBR #18 dual page mode.
- YAEBR #28 side-by-side reading. `MultipleInstance-Example` shows two readers on iPad.
- From the refactor plan: B-2 API docs, C-2 coverage, A-2 strict concurrency (start with `targeted`), B-3 accessibility, A-3 iOS 16 minimum.
- From the refactor plan: C-1, publish `FolioEPUBCore` as its own Foundation-only package (macOS, Linux) with an `async throws` parsing API.
- From the refactor plan's tech debt: legacy `@objc` protocols (11) and `NSObject` subclasses (21), counted before the A-1 split.

Out of scope here: YAEBR #62 (Readium), PDF issues (#93, #95, #96), app-only YAEBR issues, and the RAG line itself.

## Performance baseline

Record time from open to first page and the per-stage signposts before and after each Phase 3/4 change (iPhone 17 simulator, Debug). Measure with `1984.epub` (the Example's first book), The Silver Chair, or a book opened with `-FolioExampleBook`. The Population rows below came from a malformed EPUB that has since been removed, so compare them only with each other.

Collect with: `xcrun simctl spawn <device> log show --signpost --last 5m --style ndjson --predicate 'subsystem == "FolioReaderKit"'`, then pair the begin and end events by `signpostID`. (`xctrace record --launch` hung on the simulator, and `log stream` doesn't carry signposts.) `BookOpen`, `ParseEpub`, `OpenToFirstPage` and `PageLoad` are in the Points of Interest category; the per-page JS steps, `LayoutWait` and `Resource` are in the `Steps` category, so add `category == "Steps"` or `category == "PointsOfInterest"` to narrow it. An interval that ends early carries the reason as its end message (`replaced`, `failed`, `terminated`, `closed`, `error`). `Resource` stops when the response is handed to the server, before the entry is decompressed.

| Book (34 entries) | BookOpen | ParseEpub | Open → first page | PageLoad median / max | JS per page (sum) | RuntimeStyleJS median |
|---|---|---|---|---|---|---|
| Population (人口原理), 2026-10-06, before Phase 3 | 12.7 ms | 7.8 ms | 2,950 ms | 1,825 / 2,860 ms (n=5) | ≈ 40 ms | 30.2 ms |
| Population, after Phase 3 (selected font family only) | 12.9 ms | 7.9 ms | 2,859 ms | 1,919 / 2,774 ms (n=6) | ≈ 30 ms | 18.8 ms |
| big.epub (4,994 entries), fixed delays (`32eff91`) | 149 ms | 137 ms | 2,671 ms | 2,124 / 2,422 ms (n=3) | – | 5.3 ms |
| big.epub, layout waiter | 159 ms | 132 ms | 1,109 ms | 943 / 1,027 ms (n=2) | – | 12.8 ms |
| Population, layout waiter, vertical | 17.1 ms | 11.2 ms | 1,686 ms | 1,116 / 1,550 ms (n=3) | – | 19.9 ms |
| Population, layout waiter, horizontal paged | 27.4 ms | 8.1 ms | 1,529 ms | 1,036 / 1,410 ms (n=2) | – | 12.2 ms |

To profile a book that isn't bundled, copy it into the Example app's Documents and launch with `xcrun simctl launch <device> com.roswen9.FolioReaderExample -FolioExampleBook big.epub`; the first cover then opens it.

**After the layout waiter:** each layout wait settles in about 19 ms (median; under 75 ms in paged mode). Most of the remaining ~1 s per page is before `didFinish`: WebKit loading the chapter and running the user scripts, including the 14,000-line `readium-cfi.umd.js` on every chapter load. That is the next candidate.

**Finding:** more than 95% of each page load is the `didFinish` chain's fixed `asyncAfter` delays (0.2 s per stage plus `delaySec()`) and WebKit's own load, not CSS or JS work. Opening and parsing a small book is negligible, so #99 needs a many-entry EPUB to profile; none of the samples has more than 34 entries.

## Verification

```bash
# FolioReaderKit
xcodebuild test -scheme FolioReaderKit -destination 'platform=iOS Simulator,name=iPhone 17'
# Example apps
xcodebuild -project Example/Example.xcodeproj -scheme Example -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -project Example/Example.xcodeproj -scheme MultipleInstance-Example -destination 'generic/platform=iOS Simulator' build
# YAEBR main against this checkout (run from a sibling YetAnotherEBookReader checkout)
xcodebuild -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -destination 'platform=iOS Simulator,name=iPhone 17' build
```

## Issue replies

Draft replies to FolioReaderKit and YAEBR issues are kept locally in `.gemini/ISSUE_REPLY_DRAFTS.md`, which is git-ignored, so unposted text and its claims stay out of the tracked tree. YAEBR replies follow the working rules above: they never close the issue.
