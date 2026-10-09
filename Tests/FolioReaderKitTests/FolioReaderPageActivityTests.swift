//
//  FolioReaderPageActivityTests.swift
//  FolioReaderKitTests
//
//  Copyright © 2026 FolioReader. All rights reserved.
//

import ReadiumGCDWebServer
import XCTest
@testable import FolioReaderKit

@MainActor
class FolioReaderPageActivityTests: XCTestCase {

    /// The overlay used to keep its first text ("Initializing...") whatever the page was doing, and
    /// left the text black on a clear background, unreadable in the dark themes.
    func testMessageFollowsWhatThePageIsDoing() {
        let overlay = FolioReaderPageActivity(folioReader: FolioReader())
        XCTAssertTrue(overlay.isHidden)

        overlay.activate(.initializing, false)
        XCTAssertFalse(overlay.isHidden)
        XCTAssertEqual(overlay.loadingLabelView.text, "Loading…")

        // The layout chain that follows a load keeps the load's message.
        overlay.activate(.structure, false)
        overlay.activate(.style, false)
        overlay.activate(.finalizing, false)
        XCTAssertEqual(overlay.loadingLabelView.text, "Loading…")

        overlay.deactivate()
        XCTAssertTrue(overlay.isHidden)

        // The same steps on a loaded page are a relayout.
        overlay.activate(.style, false)
        XCTAssertEqual(overlay.loadingLabelView.text, "Updating layout…")
        overlay.activate(.transition, false)
        XCTAssertEqual(overlay.loadingLabelView.text, "Updating layout…")

        // A new chapter can start loading before the relayout ends.
        overlay.activate(.initializing, false)
        XCTAssertEqual(overlay.loadingLabelView.text, "Loading…")
    }

    func testColorsAndTextComeFromTheReaderConfig() {
        let config = FolioReaderConfig()
        config.localizedPageLoading = "正在加载…"
        let folioReader = FolioReader()
        let container = FolioReaderContainer(withConfig: config, folioReader: folioReader, epubPath: "", webServer: ReadiumGCDWebServer())
        folioReader.readerContainer = container
        let theme = folioReader.themeMode

        let overlay = FolioReaderPageActivity(folioReader: folioReader)
        overlay.activate(.initializing, false)

        XCTAssertEqual(overlay.loadingLabelView.text, "正在加载…")
        XCTAssertEqual(overlay.backgroundColor, config.themeModeBackground[theme])
        XCTAssertEqual(overlay.loadingLabelView.textColor, config.themeModeTextColor[theme])
        XCTAssertEqual(overlay.loadingView.color, config.themeModeTextColor[theme])
        withExtendedLifetime(container) {}
    }
}
