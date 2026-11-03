import XCTest
import ReadiumGCDWebServer
@testable import FolioReaderKit

@MainActor
final class ReaderTapTests: XCTestCase {
    private func fixture(hidden: Bool) -> (TapReaderCenter, FolioReaderNavigationController, FolioReaderPage, DeferredTapWebView, ResettableTap) {
        let config = FolioReaderConfig()
        config.shouldHideNavigationOnTap = true
        let container = FolioReaderContainer(withConfig: config, folioReader: FolioReader(), epubPath: "", webServer: ReadiumGCDWebServer())
        let center = TapReaderCenter(withContainer: container)
        let navigation = FolioReaderNavigationController(rootViewController: center)
        container.centerViewController = center
        container.centerNavigationController = navigation
        navigation.loadViewIfNeeded()
        center.loadViewIfNeeded()
        navigation.setNavigationBarHidden(hidden, animated: false)
        let page = FolioReaderPage(frame: CGRect(x: 0, y: 0, width: 402, height: 662))
        page.readerContainer = container
        page.pageNumber = 1
        let webView = DeferredTapWebView(frame: page.bounds, readerContainer: container)
        page.webView = webView
        center.displayedPage = page
        let tap = ResettableTap()
        page.tapStartLocation = tap.point
        page.tapStartPageNumber = page.pageNumber
        return (center, navigation, page, webView, tap)
    }

    func testTapHidesBarsAfterRecognizerResetsDuringMediaCheck() {
        let (_, navigation, page, webView, tap) = fixture(hidden: false)
        page.handleTapGesture(tap)
        tap.point = .zero // UIKit resets a completed recognizer before the JS callback arrives.
        webView.completeMediaCheck(hit: false)
        XCTAssertTrue(navigation.isNavigationBarHidden)
    }

    func testTapRevealsBarsAfterRecognizerResetsDuringMediaCheck() {
        let (_, navigation, page, webView, tap) = fixture(hidden: true)
        page.handleTapGesture(tap)
        tap.point = .zero
        webView.completeMediaCheck(hit: false)
        waitUntil("bars revealed") { !navigation.isNavigationBarHidden }
    }

    func testMediaTapDoesNotToggleBars() {
        for hidden in [false, true] {
            let (center, navigation, page, webView, tap) = fixture(hidden: hidden)
            page.handleTapGesture(tap)
            tap.point = .zero
            webView.completeMediaCheck(hit: true)
            XCTAssertEqual(navigation.isNavigationBarHidden, hidden)
            XCTAssertNil(center.pendingBarRevealWorkItem)
        }
    }

    func testMovedTapDoesNotToggleBars() {
        let (_, navigation, page, webView, tap) = fixture(hidden: false)
        tap.point.x += 20
        page.handleTapGesture(tap)
        webView.completeMediaCheck(hit: false)
        XCTAssertFalse(navigation.isNavigationBarHidden)
    }

    func testScrollStartingDuringMediaCheckPreventsToggle() {
        let (center, navigation, page, webView, tap) = fixture(hidden: false)
        page.handleTapGesture(tap)
        center.isScrolling = true
        webView.completeMediaCheck(hit: false)
        XCTAssertFalse(navigation.isNavigationBarHidden)
    }

    func testReusedPageDoesNotHandleOldTap() {
        let (_, navigation, page, webView, tap) = fixture(hidden: false)
        page.handleTapGesture(tap)
        page.loadGeneration += 1
        webView.completeMediaCheck(hit: false)
        XCTAssertFalse(navigation.isNavigationBarHidden)
    }
}

@MainActor
private final class TapReaderCenter: FolioReaderCenter {
    var displayedPage: FolioReaderPage?
    override var currentPage: FolioReaderPage? { displayedPage }
}

@MainActor
private final class DeferredTapWebView: FolioReaderWebView {
    private var mediaCheck: JSCallback?
    override func js(_ script: String, completion: JSCallback? = nil) {
        if script.contains("folioMediaAtPoint") { mediaCheck = completion }
        else if script == "getSelectedText()" { completion?("") }
    }
    func completeMediaCheck(hit: Bool) {
        let completion = mediaCheck
        mediaCheck = nil
        completion?(hit ? "true" : "false")
    }
}

@MainActor
private final class ResettableTap: UITapGestureRecognizer {
    var point = CGPoint(x: 120, y: 180)
    override func location(in view: UIView?) -> CGPoint { point }
}
