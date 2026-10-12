//
//  KeptPageTests.swift
//  FolioReaderKitTests
//
//  Copyright © 2026 FolioReader. All rights reserved.
//

import XCTest
import ReadiumGCDWebServer
@testable import FolioReaderKit

/// Chapters the collection view keeps next to the current one. Only the current page follows a
/// rotation or a scroll-direction change itself; a kept page showed its old layout when it came
/// back, and a right-to-left book's page showed mirrored text.
@MainActor
final class KeptPageTests: XCTestCase {

    private var containers = [FolioReaderContainer]()

    override func tearDown() {
        containers.removeAll()
        super.tearDown()
    }

    /// A page that has laid its chapter out at `size`, with the current settings (what
    /// `FolioReaderCenter.loadChapter` records).
    private func makeLaidOutPage(_ config: FolioReaderConfig, folioReader: FolioReader = FolioReader(), size: CGSize) throws -> (FolioReaderContainer, FolioReaderCenter, FolioReaderPage) {
        let container = FolioReaderContainer(withConfig: config, folioReader: folioReader, epubPath: "", webServer: ReadiumGCDWebServer())
        containers.append(container)
        container.loadViewIfNeeded()
        let center = try XCTUnwrap(container.centerViewController)
        // The page margins are fractions of the page size (`webViewFrame()`).
        center.pageWidth = size.width
        center.pageHeight = size.height
        let page = FolioReaderPage(frame: CGRect(origin: .zero, size: size))
        page.setup(withReaderContainer: container)
        page.loadedPort = container.pagePort
        page.spreadMinimumWidth = center.spreadMinimumWidth
        page.recordLayout()
        return (container, center, page)
    }

    func testAKeptPageReloadsAfterARotationOrAScrollDirectionChange() throws {
        let config = FolioReaderConfig()
        config.scrollDirection = .horizontalWithPagedContent
        let (container, center, page) = try makeLaidOutPage(config, size: CGSize(width: 744, height: 1133))
        XCTAssertFalse(center.shouldReload(page), "Nothing changed since it was laid out")

        page.frame.size = CGSize(width: 1133, height: 744)
        XCTAssertTrue(center.shouldReload(page), "Rotated: its padding and offset fit the old size")

        // The current page records the new size when it is laid out again.
        page.recordLayout()
        XCTAssertFalse(center.shouldReload(page))

        container.readerConfig.applyEffectiveScrollDirection(.vertical)
        XCTAssertTrue(center.shouldReload(page), "Its overflow style is for paged content")
    }

    /// A reader whose settings a test can change (`MockPreferenceProvider`).
    private func makeFolioReader() -> (FolioReader, MockFolioReaderDelegate) {
        let delegate = MockFolioReaderDelegate()
        let folioReader = FolioReader()
        folioReader.delegate = delegate
        return (folioReader, delegate)
    }

    /// The setters style only the current page; a kept page is styled again when shown, and keeps
    /// its chapter: its layout is still the current one.
    func testAKeptPageIsStyledAgainAfterAStyleSettingChanges() throws {
        let (folioReader, delegate) = makeFolioReader()
        let config = FolioReaderConfig()
        config.scrollDirection = .horizontalWithPagedContent
        let (_, center, page) = try makeLaidOutPage(config, folioReader: folioReader, size: CGSize(width: 744, height: 1133))
        XCTAssertFalse(center.hasOtherStyle(page), "Not styled yet: its load styles it with the settings in effect then")

        page.recordStyle(page.currentStyleState())
        XCTAssertFalse(center.hasOtherStyle(page), "Nothing changed since it was styled")

        folioReader.preferences.currentFontSize = "28px"
        XCTAssertTrue(center.hasOtherStyle(page), "Its text is laid out at the old size")
        XCTAssertFalse(center.shouldReload(page), "Styling it again is enough")

        page.recordStyle(page.currentStyleState())
        folioReader.preferences.currentLineHeight += 1
        XCTAssertTrue(center.hasOtherStyle(page))
        page.recordStyle(page.currentStyleState())
        folioReader.preferences.currentHMarginLinked = false
        folioReader.preferences.currentMarginLeft += 5
        XCTAssertTrue(center.hasOtherStyle(page), "Horizontal writing pads the body on the left")
        XCTAssertFalse(center.shouldReload(page))
        withExtendedLifetime(delegate) {}
    }

    /// In horizontal writing the top and bottom margins inset the web view in paged mode, which the
    /// layout check covers, and do nothing in scroll mode: neither is a style change.
    func testATopMarginChangeIsALayoutChangeInPagedModeOnly() throws {
        let (folioReader, delegate) = makeFolioReader()
        folioReader.preferences.currentVMarginLinked = false
        let config = FolioReaderConfig()
        config.scrollDirection = .horizontalWithPagedContent
        let (container, center, page) = try makeLaidOutPage(config, folioReader: folioReader, size: CGSize(width: 744, height: 1133))
        page.recordStyle(page.currentStyleState())

        folioReader.preferences.currentMarginTop += 10
        XCTAssertFalse(center.hasOtherStyle(page))
        XCTAssertTrue(center.shouldReload(page), "The web view is shorter now")

        container.readerConfig.applyEffectiveScrollDirection(.horizontalWithScrollContent)
        page.recordLayout()
        folioReader.preferences.currentMarginTop += 10
        XCTAssertFalse(center.hasOtherStyle(page))
        XCTAssertFalse(center.shouldReload(page))
        withExtendedLifetime(delegate) {}
    }

    func testAKeptPageTakesTheCurrentTheme() throws {
        let (folioReader, delegate) = makeFolioReader()
        let (container, center, page) = try makeLaidOutPage(FolioReaderConfig(), folioReader: folioReader, size: CGSize(width: 744, height: 1133))
        page.recordStyle(page.currentStyleState())
        XCTAssertFalse(center.hasOtherTheme(page))

        // Through the provider: the setter recolors the reader's chrome.
        delegate.preferenceProvider.preference(setInt: 2, for: ReaderPreferenceKey.themeMode.rawKey)
        XCTAssertTrue(center.hasOtherTheme(page))
        XCTAssertFalse(center.hasOtherStyle(page), "A theme needs no relayout")

        page.applyTheme(folioReader.themeMode)
        XCTAssertFalse(center.hasOtherTheme(page))
        XCTAssertEqual(page.panDeadZoneTop?.backgroundColor, container.readerConfig.themeModeBackground[2], "The page margins")
    }

    /// The collection view applies a cell's layout attributes, whose transform is the identity,
    /// whenever they change; for a reused cell that is after `willDisplay`.
    func testApplyingLayoutAttributesKeepsARightToLeftPageMirrored() throws {
        let (container, _, page) = try makeLaidOutPage(FolioReaderConfig(), size: CGSize(width: 744, height: 1133))
        let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: 0, section: 0))

        page.apply(attributes)
        XCTAssertEqual(page.transform, .identity, "Left to right")

        container.book.spine.pageProgressionDirection = "rtl"
        page.transform = .identity
        page.apply(attributes)
        XCTAssertEqual(page.transform, CGAffineTransform(scaleX: -1, y: 1))
    }
}
