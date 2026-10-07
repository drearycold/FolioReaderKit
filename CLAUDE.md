# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

FolioReaderKit is an ePub reader/parser framework for iOS written in Swift. This repository is a modernized fork. It is distributed through SPM, parses books with async/await, takes persistence through dependency injection, and serves EPUB contents to `WKWebView` from a local `ReadiumGCDWebServer`. `AGENTS.md` is a short pointer to this file for other agents, and `ROADMAP.md` tracks the umbrella plan and its working rules. YetAnotherEBookReader builds against this checkout as a local package, so don't switch branches casually.

## Build & test

The package uses UIKit dependencies such as `MenuItemKit`, so `swift build` / `swift test` on macOS will fail. Build and test against an iOS Simulator instead:

```bash
xcodebuild build -scheme FolioReaderKit -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild test  -scheme FolioReaderKit -destination 'platform=iOS Simulator,name=iPhone 17'
# Single class / single test:
xcodebuild test -scheme FolioReaderKit -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FolioReaderKitTests/CSSGenerationTests
xcodebuild test -scheme FolioReaderKit -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FolioReaderKitTests/CSSGenerationTests/testEveryReferencedPropertyHasAValue
```

To see which simulators are installed, run `xcrun simctl list devices available`.

`ReaderStyleRenderingTests` renders a chapter-like page in a `WKWebView` under 60 style settings and compares the computed styles with `Tests/FolioReaderKitTests/__Snapshots__/ReaderStyleRenderingTests/computedStyles.txt`. It checks what WebKit applies, not the CSS text, so a refactor of the styling code should leave it unchanged. After an intended rendering change, re-record the snapshot by deleting that file, or by prefixing the test command with `TEST_RUNNER_FOLIO_RECORD_SNAPSHOTS=1`. The recording run fails on purpose, so run again to confirm, then review the snapshot diff in git.

- The repo has no linter or formatter config.
- CI is `.github/workflows/test.yml`, on a `macos-26` runner for pull requests and pushes to `master`. It runs the package tests on an iPhone simulator ("iPhone 17", or the first available iPhone) and builds the Example and Storyboard-Example schemes. It doesn't build YetAnotherEBookReader, which depends on a local checkout.
- The example app is `Example/Example.xcodeproj`, an Xcode project that links the local package (there is no workspace and no `pod install`). Its schemes are Example, MultipleInstances-Example, and Storyboard-Example. Sample books and shared assets live in `Example/Shared/`.
- `FolioReaderKit.podspec` and `Sources/FolioReaderKit/FolioReaderKit.h` are legacy CocoaPods leftovers and are not part of the SPM build.
- Jazzy generates the docs in `docs/` from `.jazzy.yaml`, which builds the SPM scheme for `generic/platform=iOS Simulator`. Jazzy itself isn't installed by the repo.

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

Styling works by **fixed rules that read `--folio-*` custom properties set on `<body>`**. Settings changes don't generate new CSS; they set new property values.

- All CSS strings, `<body>` classes, and property values come from `CSS/FolioReaderCSSBuilder.swift` (pure static functions). `baseStyleSheet()` is `Style.css` plus `settingRules`, which read every value from a `CustomProperty` (`var(--folio-font-size)` and so on). `customProperties(for: FolioReaderStyleState)` turns the settings into those values. `userFontFaceRules` produces `@font-face` rules for `FolioReaderConfig.userFontDescriptors`.
- `bodyClasses(for:)` chooses which elements the rules reach: `folioStyleHorizontal` or `folioStyleVertical` (left/right or top/bottom body padding), plus one `folioStyleScope<P|TD|SPAN|All>` class per override level up to `StyleOverrideTypes` (each level also applies all lower ones; `All` targets `<body>` itself). Keep rules gated by these classes: a `var()` whose property is unset resets the declaration instead of being ignored. `CSSGenerationTests.testEveryReferencedPropertyHasAValue` checks that every referenced property gets a value.
- `CSS/FolioReaderCSSInjector.swift` owns every `<style id=…>` element. It upserts them through self-contained JS that decodes base64 as UTF-8, so CSS is never escaped into a JS string. In cascade order, the ids are: `folio_bundle_style` and `folio_style_user_font_faces` (WKUserScripts added in `FolioReaderWebView.init`), `folio_custom_*` for documentBase sheets, `folio_style_overflow` (applied in `updateOverflowStyle`), then `folio_custom_*` for runtime sheets (applied in `updateRuntimeStyle`). Signposts in `Signposts.swift` time book opening and each page-load stage; see ROADMAP.md for how to read them.
- `FolioReaderConfig.customStyleSheets` (`FolioReaderStyleSheet` with `.documentBase` / `.runtime` stage) is the public extension point. Custom rules need `!important` to beat the built-in ones.
- `FolioReaderPage.updateRuntimeStyle` runs `FolioReaderCSSInjector.runtimeStyleSource(...)`, which swaps the `folioStyle*` classes, sets the `--folio-*` properties on `<body>`, and re-applies runtime custom sheets. `FolioReaderCSSInjectorTests` runs that script against the real `Bridge.js` in a `WKWebView`; generated JS needs explicit semicolons, because a line starting with `[` or `(` continues the previous statement. The chapter-HTML and computed-style debug dumps run only when `readerConfig.debug.contains(.htmlStyling)`.
- Theme and night mode are applied in JS with `themeMode(n)` / `nightMode(bool)` in `Bridge.js`. The native chrome (nav bar, page indicator, scrubber, collection background) is recolored in the `ReaderPreferences.nightMode` / `themeMode` setters, using `FolioReaderConfig.nightModeBackground` / `themeModeBackground`.

## Preferences & persistence (plug-in providers)

`FolioReader` itself holds no persisted state. `ReaderPreferences` (reached through `folioReader.preferences`) wraps every setting and reads or writes it through `FolioReaderPreferenceProvider`. The provider comes from the `FolioReaderDelegate.folioReaderPreferenceProvider(_:)` callback. If no provider is supplied, every read returns its default and every write is a no-op. Keys are defined in `ReaderPreferenceKeys.swift`.

The provider protocols are in `Providers/`: Preference, Highlight, Bookmark, ReadPosition, and Sharing. **If you change one, also update:**
- the example implementations in `Example/Example/ViewController.swift` (`FolioReaderUserDefaultsPreferenceProvider`, `FolioReaderInMemoryHighlightProvider`) and `Example/Example/FolioReaderUserDefaults.swift`
- the mocks in `Tests/FolioReaderKitTests/MockHelpers.swift` (`MockPreferenceProvider`, `MockHighlightProvider`, `MockBookmarkProvider`, `MockReadPositionProvider`, `MockFolioReaderDelegate`). Tests use `MockWKScriptMessage` / `MockScriptMessageHandler` to drive the JS bridge without a real `WKWebView`.

Setting changes that need pages to re-layout post `.folioReaderNeedRefreshPageMode`, which each `FolioReaderPage` observes. Reader state is auto-saved on `willResignActive` / `willTerminate`, guarded by `isReaderOpen` / `isReaderReady`.

## Conventions / gotchas

- The public API uses `open` classes with `public` initializers.
- Several enum cases and method names are misspelled on purpose and are part of the API, for example `FolioReaderScrollDirection.horitonzalWithPagedContent`. Search all call sites, including the `Example/` projects, before renaming anything.
- `Style.css` puts `-webkit-transition: all 0.6s` on `html` and `body`, so `getComputedStyle` right after a style change can return mid-transition values. Tests that read computed styles must turn transitions off, as `ReaderStyleRenderingTests` does.
- `Sources/FolioReaderKit/Vendor/` (`HAControls`, `SMSegmentView`) contains vendored third-party UI code.
- `.gemini/` is git-ignored and holds local tool artifacts. Do not commit it.
