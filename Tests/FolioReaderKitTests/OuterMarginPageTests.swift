//
//  OuterMarginPageTests.swift
//  FolioReaderKitTests
//
//  Copyright © 2026 FolioReader. All rights reserved.
//

import XCTest
import ReadiumGCDWebServer
@testable import FolioReaderKit

/// A spread's outer margins on a laid-out page: partly outside the web view
/// (`FolioReaderPageFrameCalculator.webViewLayout`), where a swipe still goes to the web view and
/// the page-item navigation steps by the web view's width, and moved by a margin change.
@MainActor
final class OuterMarginPageTests: XCTestCase {

    private var containers = [FolioReaderContainer]()

    override func tearDown() {
        containers.removeAll()
        super.tearDown()
    }

    /// A horizontal chapter in landscape on an iPad mini, paged, laid out as a spread at 15vw margins
    /// (39 points outside the web view on each side), as once it has loaded.
    private func makeSpreadPage() throws -> (FolioReader, MockFolioReaderDelegate, FolioReaderPage) {
        let delegate = MockFolioReaderDelegate()
        let folioReader = FolioReader()
        folioReader.delegate = delegate
        folioReader.preferences.currentHMarginLinked = false
        folioReader.preferences.currentMarginLeft = 30
        folioReader.preferences.currentMarginRight = 30
        let config = FolioReaderConfig()
        config.scrollDirection = .horizontalWithPagedContent
        config.reserveSafeAreaInsidePageFrame = false
        config.reservePageIndicatorInsidePageFrame = false
        let container = FolioReaderContainer(withConfig: config, folioReader: folioReader, epubPath: "", webServer: ReadiumGCDWebServer())
        containers.append(container)
        container.loadViewIfNeeded()
        let center = try XCTUnwrap(container.centerViewController)
        let size = CGSize(width: 1133, height: 744)
        center.pageWidth = size.width
        center.pageHeight = size.height
        let page = FolioReaderPage(frame: CGRect(origin: .zero, size: size))
        page.setup(withReaderContainer: container)
        page.spreadMinimumWidth = center.spreadMinimumWidth
        page.recordLayout()
        page.setNeedsLayout()
        page.layoutIfNeeded()
        page.webView?.isHidden = false
        return (folioReader, delegate, page)
    }

    /// A swipe that starts in a spread's outer margin goes to the web view, as one on the text does;
    /// the top margin, outside the web view in any paged page, keeps its dead zone. Until the page is
    /// laid out again the margins are the ones on screen, not the current settings'.
    func testSwipesInTheOuterMarginsGoToTheWebView() throws {
        let (_, delegate, page) = try makeSpreadPage()
        let webView = try XCTUnwrap(page.webView)
        XCTAssertEqual(webView.frame.minX, 39)
        XCTAssertEqual(webView.frame.width, 1055)
        XCTAssertGreaterThan(webView.frame.minY, 0, "The top margin insets the web view")

        let middle = webView.frame.midY
        XCTAssertTrue(page.hitTest(CGPoint(x: 20, y: middle), with: nil) === webView.scrollView, "Left margin")
        XCTAssertTrue(page.hitTest(CGPoint(x: 1113, y: middle), with: nil) === webView.scrollView, "Right margin")
        XCTAssertTrue(page.hitTest(CGPoint(x: 566, y: middle), with: nil)?.isDescendant(of: webView) == true, "The text")
        XCTAssertTrue(page.hitTest(CGPoint(x: 566, y: webView.frame.minY / 2), with: nil) === page.panDeadZoneTop, "Top margin")

        // Switched to scrolling, before the page is laid out again: still a spread on screen.
        page.readerConfig.applyEffectiveScrollDirection(.horizontalWithScrollContent)
        XCTAssertTrue(page.hitTest(CGPoint(x: 20, y: middle), with: nil) === webView.scrollView, "Left margin, as laid out")
        page.setNeedsLayout()
        page.layoutIfNeeded()
        XCTAssertEqual(webView.frame.minX, 0, "Scrolled pages fill the width")
        withExtendedLifetime(delegate) {}
    }

    /// The page-item navigation (`ReaderPaginationEngine.changePageItemToNext` and the like) and the
    /// page count step by the width the web view pages by, a spread's, not the page's.
    func testPagesStepByTheWebViewsWidth() throws {
        let (_, delegate, page) = try makeSpreadPage()
        XCTAssertEqual(page.pagingWidth, 1055)
        XCTAssertEqual(page.pageLengthAlongPages, 1055)
        withExtendedLifetime(delegate) {}
    }

    /// A margin change restyles the page (`updateRuntimeStyle`), which lays its frame out again: a
    /// spread's outer margins are partly outside the web view. 20vw margins put 5% of the web view's
    /// width outside it: 1133 = 1031 * 1.1 (51 + 51 points, rounded down).
    func testAMarginChangeMovesASpreadsWebView() throws {
        let (folioReader, delegate, page) = try makeSpreadPage()
        let webView = try XCTUnwrap(page.webView)
        let before = webView.frame
        folioReader.preferences.currentMarginLeft = 40
        folioReader.preferences.currentMarginRight = 40
        XCTAssertEqual(webView.frame, before, "Not the reader's current page: nothing restyled it")

        page.updateRuntimeStyle(delay: 0)
        page.layoutIfNeeded()
        XCTAssertEqual(webView.frame.minX, 51)
        XCTAssertEqual(webView.frame.width, 1031)
        waitUntil("the restyle to finish", timeout: 20) { page.layoutAdapting == nil }
        withExtendedLifetime(delegate) {}
    }
}
