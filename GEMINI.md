# FolioReaderKit

## Project Overview

**FolioReaderKit** is an open-source ePub reader and parser framework for iOS written in Swift. It provides a comprehensive set of features for rendering and interacting with ePub 2 and ePub 3 documents. 

Key features include:
- Custom fonts and text sizing
- Text highlighting (with listing, editing, and deleting capabilities)
- Theming (Day/Night modes)
- Reading time/pages left estimation
- In-App Dictionary
- Media Overlays (Text-to-Speech synchronization)
- Right-to-Left (RTL) support
- Vertical and Horizontal scrolling
- Sharing of custom image quotes
- Support for multiple instances (parallel reading)

**Primary Technologies:**
- **Language:** Swift (5.3+)
- **Platform:** iOS (12.0+)
- **Dependency Managers:** Swift Package Manager (SPM), CocoaPods

**Key Dependencies (via SPM / Podspec):**
- XML Parsing: `AEXML`
- ZIP Handling: `ZipArchive` / `SSZipArchive` / `ZIPFoundation`
- Fonts: `FontBlaster`
- UI Components: `MenuItemKit`, `ZFDragableModalTransition`
- Data Persistence: `RealmSwift` (in SPM)
- HTML Parsing: `SwiftSoup` (in Podspec)

## Directory Structure

- `Sources/FolioReaderKit/`: Contains the core Swift source code for the framework, including:
  - `EPUBCore/`: ePub parsing, metadata, and resource handling.
  - `Center/`: Core reading view controllers, layout, and presentation logic.
  - `Models/`, `Providers/`, `Resources/`, `Vendor/`: Various supporting components and resources.
- `Example/`: Contains a sample iOS application demonstrating how to integrate and use FolioReaderKit, including multiple instances and storyboard setups.
- `Tests/`: Unit tests for the framework.
- `docs/`: Jazzy output (git-ignored), published to GitHub Pages by `.github/workflows/docs.yml`.
- Configuration Files: `Package.swift` (SPM), `FolioReaderKit.podspec` (CocoaPods).

## Building and Running

Since this is a framework, it is meant to be integrated into other iOS applications. However, you can build and run the provided `Example` project to see it in action.

### Using the Example Project

1. Navigate to the `Example` directory.
2. If dependencies are missing, run `pod install` within the `Example` directory.
3. Open `Example.xcworkspace` in Xcode.
4. Select an iOS Simulator or device and run the project (`Cmd + R`).

### Testing

The project contains unit tests in the `Tests/` directory.
You can run tests via the command line using Swift Package Manager or via Xcode:

```bash
swift test
```
Or, open `FolioReaderKit.xcodeproj` or `Example.xcworkspace` in Xcode, select the `FolioReaderKit` scheme, and press `Cmd + U`.

## Development Conventions

- The codebase is written in Swift and uses typical iOS/Cocoa Touch architectural patterns.
- Ensure that any changes maintain compatibility with iOS 12.0+ and Swift 5.3.
- When adding new features or modifying behavior, update or add unit tests in the `Tests/` directory.
- The project is available under the BSD license.
