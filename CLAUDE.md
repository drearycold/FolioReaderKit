# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

FolioReaderKit is an ePub reader/parser framework for iOS written in Swift. This repository is a modernized fork. It is distributed through SPM, parses books with async/await, takes persistence through dependency injection, and serves EPUB contents to `WKWebView` from a local `ReadiumGCDWebServer`. `AGENTS.md` covers much of the same ground, but some of its paths and line numbers are out of date (it predates the `FolioEPUBCore` split). Treat this file as the source of truth where the two disagree.

## Build & test

The package uses UIKit dependencies such as `MenuItemKit`, so `swift build` / `swift test` on macOS will fail. Build and test against an iOS Simulator instead:

```bash
xcodebuild build -scheme FolioReaderKit -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild test  -scheme FolioReaderKit -destination 'platform=iOS Simulator,name=iPhone 17'
# Single class / single test:
xcodebuild test -scheme FolioReaderKit -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FolioReaderKitTests/CSSGenerationTests
xcodebuild test -scheme FolioReaderKit -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FolioReaderKitTests/CSSGenerationTests/testGenerateRuntimeStyle
```

To see which simulators are installed, run `xcrun simctl list devices available`.

`CSSInjectionSnapshotTests` compares the generated style rules with `Tests/FolioReaderKitTests/__Snapshots__/CSSInjectionSnapshotTests/levelStyleRules.css`. After an intended styling change, re-record the snapshot by deleting that file, or by prefixing the test command with `TEST_RUNNER_FOLIO_RECORD_SNAPSHOTS=1`. The recording run fails on purpose, so run again to confirm, then review the snapshot diff in git.

- The repo has no linter or formatter config and no working CI. `.travis.yml` is stale: it references CocoaPods and `Example/Example.xcworkspace`, neither of which exists anymore.
- The example app is `Example/Example.xcodeproj`, an Xcode project that links the local package (there is no workspace and no `pod install`). Its schemes are Example, MultipleInstances-Example, and Storyboard-Example. Sample books and shared assets live in `Example/Shared/`.
- `FolioReaderKit.podspec` and `Sources/FolioReaderKit/FolioReaderKit.h` are legacy CocoaPods leftovers and are not part of the SPM build.
- Jazzy generates the docs in `docs/` from `.jazzy.yaml`. That config still points at a `FolioReaderKit.xcodeproj` that no longer exists.

## Package layout (Package.swift)

The single library product contains two targets:

- **`FolioEPUBCore`** (`Sources/FolioEPUBCore/`) handles UI-free EPUB parsing: `FREpubParserArchive`, `FRBook`, `FRSpine`, `FRResources`, `FRSmils`, `FRMetadata`, `FRTocReference`, and `FolioReaderError`. It depends only on `AEXML` and `ReadiumZIPFoundation`. Keep UIKit out of this target.
- **`FolioReaderKit`** (`Sources/FolioReaderKit/`) contains the reader UI, the web server, styling, and the JS bridge. It ships `Resources/Bridge.js`, `Style.css`, `readium-cfi.umd.js`, and `Images.xcassets` as processed resources, loaded through `Bundle.frameworkBundle()`.

Two dependencies are Readium forks and are imported under their fork names: `import ReadiumGCDWebServer` and `import ReadiumZIPFoundation`.

## Architecture: how a page gets on screen

1. **Entry.** The app calls `FolioReader.presentReader(...)` or `prepareReader(...)` with a `webServer: ReadiumGCDWebServer` argument. Don't remove that parameter. These calls build a `FolioReaderContainer`, which is the root `UIViewController`.
2. **Parsing.** The container parses the EPUB into an `FRBook` (from `FolioEPUBCore`). **The EPUB is never unzipped to disk.** `FRBook.archiveEntriesCache` maps paths to ZIP entries.
3. **Serving.** `EpubResourceServer` owns the `ReadiumGCDWebServer`. It binds to localhost on preferred port `46436` and falls back to any free port, so multiple concurrent reader instances work. It streams each requested entry straight out of the ZIP archive through an `AsyncStream`. A second handler serves `/_fonts/*.otf|ttf` from `Documents/Fonts`.
4. **Paging.** `FolioReaderCenter` (`Center/`) is a `UICollectionView` with one cell per spine item. Each cell (`FolioReaderPage`, `Page/`) holds a `FolioReaderWebView` that loads `http://localhost:<port>/<bookName>/<opfDir>/<href>`; the URL is built by `FolioReaderCenter.resourceURL`. `ReaderPaginationEngine` owns page and page-item navigation. The `Center/` code is split across many extension files by concern: delegation, layout, presentation, and so on.
5. **JS bridge.** JS posts `"<command> <body>"` strings to the `FolioReaderPage` message handler. `EpubJSBridge` parses them and dispatches through `EpubJSBridgeDelegate` (see `Page/FolioReaderPage+EpubJSBridge.swift`). Highlights are located with Readium CFI (`readium-cfi.umd.js`) and injected in `Bridge.js` (`injectHighlights`, `relocateHighlights`).

## Architecture: reader styling (CSS)

Styling works by **precomputing every class and then toggling classes on `<body>`**. Settings changes don't generate new CSS.

- `FolioReaderScript.cssInjection` builds one large stylesheet once, as a `WKUserScript` injected at document end. It contains `Style.css` plus one class for every level of every setting: font size, font weight 100–900, letter spacing 0–10, line height and margins 0–10, text indent 0–8, image max size, and body padding (`folioStyleBodyPadding{Left,Right,Top,Bottom}0–10`). `FolioReaderWebView` adds two more injected sheets, for user `@font-face` rules and for every `UIFont.familyNames` entry.
- `ReaderCSSGenerator.CssLevels` / `CssImgLevels` generate the selectors in the form `body.folioStyleL<level><Setting><value> <tag>`. The level comes from `StyleOverrideTypes` (`PNode`=p, `PlusTD`=td, `PlusSPAN`=span, `AllText`=all). The static helpers on `FolioReader` with the same names are deprecated shims.
- `FolioReaderPage.updateRuntimStyle(...)` (in `Page/FolioReaderPage+Layout.swift`; note the spelling) runs JS that removes `folioStyle\w+` classes and re-adds the right ones for the current preferences. It loops `styleOverride` down to 1, so higher override levels stack the lower ones. It also branches on `writingMode == 'vertical-rl'` (top/bottom padding and `MarginV`, instead of left/right and `MarginH`).
- `ReaderCSSGenerator.generateRuntimeStyle()` is effectively dead. Every rule it emits is commented out, and its only call site, in `Center/UICollectionViewDataSource.swift`, is commented out too. Do styling work in the class pipeline above.
- Theme and night mode are applied in JS with `themeMode(n)` / `nightMode(bool)` in `Bridge.js`. The native chrome (nav bar, page indicator, scrubber, collection background) is recolored in the `ReaderPreferences.nightMode` / `themeMode` setters, using `FolioReaderConfig.nightModeBackground` / `themeModeBackground`.

## Preferences & persistence (plug-in providers)

`FolioReader` itself holds no persisted state. `ReaderPreferences` (reached through `folioReader.preferences`) wraps every setting and reads or writes it through `FolioReaderPreferenceProvider`. The provider comes from the `FolioReaderDelegate.folioReaderPreferenceProvider(_:)` callback. If no provider is supplied, every read returns its default and every write is a no-op. Keys are defined in `ReaderPreferenceKeys.swift`.

The provider protocols are in `Providers/`: Preference, Highlight, Bookmark, ReadPosition, and Sharing. **If you change one, also update:**
- the example implementations in `Example/Example/ViewController.swift` (`FolioReaderUserDefaultsPreferenceProvider`, `FolioReaderInMemoryHighlightProvider`) and `Example/Example/FolioReaderUserDefaults.swift`
- the mocks in `Tests/FolioReaderKitTests/MockHelpers.swift` (`MockPreferenceProvider`, `MockHighlightProvider`, `MockBookmarkProvider`, `MockReadPositionProvider`, `MockFolioReaderDelegate`). Tests use `MockWKScriptMessage` / `MockScriptMessageHandler` to drive the JS bridge without a real `WKWebView`.

Setting changes that need pages to re-layout post `.folioReaderNeedRefreshPageMode`, which each `FolioReaderPage` observes. Reader state is auto-saved on `willResignActive` / `willTerminate`, guarded by `isReaderOpen` / `isReaderReady`.

## Conventions / gotchas

- The public API uses `open` classes with `public` initializers.
- Several enum cases and method names are misspelled on purpose and are part of the API, for example `FolioReaderScrollDirection.horitonzalWithPagedContent` and `updateRuntimStyle`. Search all call sites, including the `Example/` projects, before renaming anything.
- CSS class names are built from preference strings: spaces in a font name become `_`, and `.` is stripped from a font size. The Swift generator and the JS class toggling must stay in sync.
- `Sources/FolioReaderKit/Vendor/` (`HAControls`, `SMSegmentView`) contains vendored third-party UI code.
- `.gemini/` is git-ignored and holds local tool artifacts. Do not commit it.
