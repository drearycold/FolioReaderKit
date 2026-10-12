# FolioReaderKit

FolioReaderKit is an ePub reader and parser framework for iOS written in Swift.

This is a modernized fork of [FolioReader/FolioReaderKit](https://github.com/FolioReader/FolioReaderKit), which is archived. It is maintained for [D.S.Reader](https://github.com/drearycold/YetAnotherEBookReader) and is not affiliated with or endorsed by the original authors. The original code is © 2015–2018 Heberti Almeida, under the BSD 3-Clause license.

![License](https://img.shields.io/badge/license-BSD--3--Clause-green.svg)

## Features

- [x] ePub 2 and ePub 3 support
- [x] Custom Fonts
- [x] Custom Text Size
- [x] Text Highlighting
- [x] List / Edit / Delete Highlights
- [x] Themes / Day mode / Night mode
- [x] Handle Internal and External Links
- [x] Portrait / Landscape
- [x] Reading Time Left / Pages left
- [x] In-App Dictionary
- [x] Media Overlays (Sync text rendering with audio playback)
- [x] TTS - Text to Speech Support
- [x] Parse epub cover image
- [x] RTL Support
- [x] Vertical or/and Horizontal scrolling
- [x] Two pages side by side in landscape on iPad (paged, horizontal writing)
- [x] Two tiers to a screen for vertical writing in portrait on iPad, pages turning top to bottom
- [x] Share Custom Image Quotes **<sup>NEW</sup>**
- [x] Support multiple instances at same time, like parallel reading **<sup>NEW</sup>**
- [x] Add Notes to a Highlight
- [x] Bookmarks with notes
- [x] Custom CSS injection (`customStyleSheets`)
- [ ] Book Search

## Installation

**FolioReaderKit** is available through Swift Package Manager (SPM).

### Swift Package Manager

In Xcode, go to **File > Add Packages...** and enter the repository URL:

```text
https://github.com/drearycold/FolioReaderKit.git
```

This fork has no tagged releases: choose the **Branch** rule with `master`, its stable branch, and click **Add Package**.

## Requirements

- iOS 13.0+
- macOS 11.0+ (Catalyst)
- Xcode 12.0+

## Basic Usage

To get started, this is a simple usage sample of using the integrated view controller. Note that you now need to provide a `ReadiumGCDWebServer` instance to serve the EPUB content locally.

```swift
import FolioReaderKit
import ReadiumGCDWebServer

let webServer = ReadiumGCDWebServer()

func open(sender: AnyObject) {
    let config = FolioReaderConfig()
    let bookPath = Bundle.main.path(forResource: "book", ofType: "epub")
    let folioReader = FolioReader()
    
    // Provide the webServer instance required for serving EPUB resources
    folioReader.presentReader(
        parentViewController: self, 
        withEpubPath: bookPath!, 
        andConfig: config,
        folioReaderCenterDelegate: nil,
        webServer: webServer
    )
}
```

For more usage examples check the `Example` folder.

## Configuration

### Persistence providers

FolioReaderKit stores nothing itself. Return providers from your `FolioReaderDelegate`; any provider you omit falls back to defaults or no-ops:

| Delegate method | Protocol | Persists |
|---|---|---|
| `folioReaderPreferenceProvider(_:)` | `FolioReaderPreferenceProvider` | Font, size, theme, margins, scroll direction, … |
| `folioReaderHighlightProvider(_:)` | `FolioReaderHighlightProvider` | Highlights and highlight notes |
| `folioReaderBookmarkProvider(_:)` | `FolioReaderBookmarkProvider` | Bookmarks and bookmark notes |
| `folioReaderReadPositionProvider(_:)` | `FolioReaderReadPositionProvider` | Reading position |

`Example/Example/ViewController.swift` shows a `UserDefaults`-backed preference provider and in-memory highlight, bookmark and read-position providers.

- The `bookId` the reader passes to providers is the EPUB's file name without its extension.
- Bookmark removal, renaming and lookup pass only the bookmark's position, so keep one bookmark store per book.
- The reader opens at `FolioReaderConfig.savedPositionForCurrentBook` and doesn't look the position up itself. To reopen a book where it was left, set it from your read-position provider before presenting the reader, as the Example does.

### Custom CSS

Add your own CSS through `FolioReaderConfig.customStyleSheets`. A `.documentBase` sheet is injected once on every page load; a `.runtime` sheet is re-applied on every style refresh.

To override one of the reader's setting rules, a rule needs `!important` and a selector at least as specific as the reader's, such as `html body.folioStyleScopeP p`. At equal specificity yours wins, because it comes later. So `p { text-indent: 0 !important; }` loses, while `html:root body p { text-indent: 0 !important; }` wins. The current settings are available as `--folio-*` custom properties on `<body>`, for example `var(--folio-font-size)`. They update live, so a rule that reads them doesn't need to be a `.runtime` sheet:

```swift
config.customStyleSheets = [
    // Overrides the reader's paragraph rule.
    FolioReaderStyleSheet(id: "app-paragraphs", css: "html:root body p { text-indent: 0 !important; }", stage: .documentBase),
    // Follows the reader's font size setting.
    FolioReaderStyleSheet(id: "app-headings", css: "h1 { font-size: calc(var(--folio-font-size) * 1.6); }", stage: .documentBase)
]
```

### Page frame and chrome

| Option | Default | Effect |
|---|---|---|
| `showCloseButton` | `true` | Show the reader's close button |
| `forceBottomMenuTabBar` | `false` | Keep the settings tabs at the bottom on iPadOS |
| `reserveSafeAreaInsidePageFrame` | `true` | Inset pages by the status bar and safe area, including the Dynamic Island in landscape |
| `reservePageIndicatorInsidePageFrame` | `true` | Inset pages by the page indicator |

Set both `reserve…` options to `false` and the margins to `0` for edge-to-edge pages.

### Two-page spread

In paged mode, horizontal-writing books show two pages side by side while the page is landscape and wide enough. Each page's outer margin is about half a full-width page's, the same share of its width, and the gutter between the pages is as wide as one outer margin, as in a printed book. A spread counts as one page in page numbers and progress. Users choose "One Page" or "Two Pages" in the page menu on iPad (`ReaderPreferences.currentLandscapeSpread`, stored under `currentLandscapeSpread`).

| Option | Default | Effect |
|---|---|---|
| `landscapeSpread` | `true` | Two pages in landscape until the user chooses otherwise |
| `spreadMinimumWidth` | `1000` | The narrowest page, in points, that shows two pages: every iPad in landscape, no iPhone |

### Tiers for vertical writing

In `.vertical`, vertical-writing books page top to bottom, chapters too. On a portrait page at least `tiersMinimumHeight` tall, each screen shows two tiers, one above the other, so lines are half as long; otherwise one page. Rotating keeps the reading position, and each tier gets half the top and bottom margins of a full-height page. Users choose "Tiered" in the vertical-writing row of the page menu (Paged | Tiered | Scroll), shown where a portrait page can reach `tiersMinimumHeight` (the screen's long side less the status bar and page indicator): by default every iPad and no iPhone, which keep Paged | Scroll unless `.vertical` is already in effect. An infinite `tiersMinimumHeight` never shows two tiers. `.vertical` is the setting horizontal books scroll top to bottom with, so choosing Tiered in a vertical-writing book makes horizontal books scroll, and the other way round; horizontal chapters in a vertical-writing book (a cover, a colophon) scroll too.

| Option | Default | Effect |
|---|---|---|
| `tiersMinimumHeight` | `1000` | The shortest page, in points, that shows two tiers: iPads in portrait, no iPhone |

## Architecture & Migration

This fork features a modernized architecture:
- **SPM First**: Migrated from CocoaPods/Carthage to Swift Package Manager.
- **Local WebServer**: Uses `GCDWebServer` to serve EPUB assets via `http://localhost`, resolving `file://` URL restrictions in modern `WKWebView`.
- **Concurrency**: Adopts Swift `async/await` for EPUB parsing and extraction using `ZIPFoundation`.
- **Persistence**: Removed the hard dependency on `Realm`. Integrators must now provide their own persistence via the `FolioReaderPreferenceProvider`, `FolioReaderHighlightProvider`, and `FolioReaderBookmarkProvider` protocols.

## Authors

FolioReaderKit was created by [Heberti Almeida](https://github.com/hebertialmeida) and the [FolioReader contributors](https://github.com/FolioReader/FolioReaderKit/graphs/contributors). This fork is maintained by [drearycold](https://github.com/drearycold); report its issues [here](https://github.com/drearycold/FolioReaderKit/issues), not upstream.

## License
FolioReaderKit is available under the BSD 3-Clause license, which keeps the original copyright notice. See the [LICENSE](/LICENSE) file.