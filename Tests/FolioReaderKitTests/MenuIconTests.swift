//
//  MenuIconTests.swift
//  FolioReaderKitTests
//
//  Copyright © 2026 FolioReader. All rights reserved.
//

import ReadiumGCDWebServer
import XCTest
@testable import FolioReaderKit

/// On iOS 16+ the edit menu shows an action's title and drops its image, so the icon items must
/// have no title; they used to show placeholder letters ("C", "R", "S", "Y", …).
@MainActor
class MenuIconTests: XCTestCase {

    func testIconActionHasNoTitleAndAnAccessibilityLabel() {
        let action = WebViewMenuManager.iconAction("Yellow", image: UIImage(readerImageNamed: "yellow-marker")) { _ in }
        XCTAssertEqual(action.title, "")
        XCTAssertEqual(action.accessibilityLabel, "Yellow")
        XCTAssertEqual(action.image?.accessibilityLabel, "Yellow")
    }

    func testSwatchesKeepTheirColorsAndSymbolsFollowTheMenu() {
        let swatch = WebViewMenuManager.iconAction("Pink", image: UIImage(readerImageNamed: "pink-marker")) { _ in }
        XCTAssertEqual(swatch.image?.renderingMode, .alwaysOriginal)
        let symbol = WebViewMenuManager.iconAction("Share", image: UIImage(systemName: "square.and.arrow.up")) { _ in }
        XCTAssertEqual(symbol.image?.renderingMode, .alwaysTemplate)
    }

    func testLabellingDoesNotTouchSharedImages() {
        _ = WebViewMenuManager.iconAction("Remove Highlight", image: UIImage(systemName: "trash")) { _ in }
        _ = WebViewMenuManager.iconAction("Blue", image: UIImage(readerImageNamed: "blue-marker")) { _ in }
        XCTAssertNotEqual(UIImage(systemName: "trash")?.accessibilityLabel, "Remove Highlight")
        XCTAssertNotEqual(UIImage(readerImageNamed: "blue-marker")?.accessibilityLabel, "Blue")
    }

    func testHighlightMenusShowIconsWithoutPlaceholderTitles() {
        let config = FolioReaderConfig()
        config.allowSharing = true
        let folioReader = FolioReader()
        let container = FolioReaderContainer(withConfig: config, folioReader: folioReader, epubPath: "", webServer: ReadiumGCDWebServer())
        let webView = FolioReaderWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), readerContainer: container)
        let manager = WebViewMenuManager(webView: webView)

        webView.isSharingHighlight = true
        let highlightMenu = manager.menuElementsForCurrentState().compactMap { $0 as? UIAction }
        XCTAssertEqual(highlightMenu.map(\.title), ["", config.localizedHighlightNote, "", ""])
        XCTAssertEqual(highlightMenu.compactMap(\.accessibilityLabel), [config.localizedHighlightColors, config.localizedRemoveHighlight, config.localizedShare])
        XCTAssertTrue(highlightMenu.filter { $0.title.isEmpty }.allSatisfy { $0.image != nil })

        webView.isSharingHighlight = false
        webView.isColors = true
        let colorsMenu = manager.menuElementsForCurrentState().compactMap { $0 as? UIAction }
        XCTAssertEqual(colorsMenu.map(\.title), ["", "", "", "", ""])
        XCTAssertEqual(colorsMenu.compactMap(\.accessibilityLabel), [
            config.localizedHighlightYellow, config.localizedHighlightGreen, config.localizedHighlightBlue,
            config.localizedHighlightPink, config.localizedHighlightUnderline,
        ])

        webView.isColors = false
        let selectionMenu = manager.menuElementsForCurrentState().compactMap { $0 as? UIAction }
        XCTAssertEqual(selectionMenu.last?.title, "", "Share is an icon in the selection menu too")
        XCTAssertEqual(selectionMenu.last?.accessibilityLabel, config.localizedShare)
        withExtendedLifetime(container) {}
    }
}
