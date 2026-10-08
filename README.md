![FolioReader logo](https://raw.githubusercontent.com/FolioReader/FolioReaderKit/assets/folioreader.png)
FolioReaderKit is an ePub reader and parser framework for iOS written in Swift.

![Version](https://img.shields.io/badge/version-1.4.0-blue.svg)
![License](https://img.shields.io/badge/license-BSD-green.svg)

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

Choose the dependency rule that suits your needs (e.g., Up to Next Major Version) and click **Add Package**.

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
| `reserveSafeAreaInsidePageFrame` | `true` | Inset pages by the status bar and safe area |
| `reservePageIndicatorInsidePageFrame` | `true` | Inset pages by the page indicator |

Set both `reserve…` options to `false` and the margins to `0` for edge-to-edge pages.

## Architecture & Migration

This fork features a modernized architecture:
- **SPM First**: Migrated from CocoaPods/Carthage to Swift Package Manager.
- **Local WebServer**: Uses `GCDWebServer` to serve EPUB assets via `http://localhost`, resolving `file://` URL restrictions in modern `WKWebView`.
- **Concurrency**: Adopts Swift `async/await` for EPUB parsing and extraction using `ZIPFoundation`.
- **Persistence**: Removed the hard dependency on `Realm`. Integrators must now provide their own persistence via the `FolioReaderPreferenceProvider`, `FolioReaderHighlightProvider`, and `FolioReaderBookmarkProvider` protocols.

## Author
[**Heberti Almeida**](https://github.com/hebertialmeida)

- Follow me on **Twitter**: [**@hebertialmeida**](https://twitter.com/hebertialmeida)
- Contact me on **LinkedIn**: [**hebertialmeida**](http://linkedin.com/in/hebertialmeida)

## License
FolioReaderKit is available under the BSD license. See the [LICENSE](/LICENSE) file.