//
//  FolioReaderPageFrameTests.swift
//  FolioReaderKitTests
//
//  Created by OpenAI on 7/8/26.
//  Copyright © 2026 FolioReader. All rights reserved.
//

import XCTest
@testable import FolioReaderKit

final class FolioReaderPageFrameTests: XCTestCase {

    func testZeroMarginsWithoutReservedComponentsUseFullBounds() {
        let input = makeInput(
            reserveSafeAreaInsidePageFrame: false,
            reservePageIndicatorInsidePageFrame: false
        )

        XCTAssertEqual(FolioReaderPageFrameCalculator.webViewFrame(input: input), input.bounds)
        XCTAssertEqual(FolioReaderPageFrameCalculator.anchorBoundsFrame(input: input), input.bounds)
    }

    func testNonzeroMarginsShrinkExpectedAxesWithoutReservedComponents() {
        let input = makeInput(
            scrollDirection: .horizontalWithPagedContent,
            currentMarginTop: 10,
            currentMarginBottom: 20,
            currentMarginLeft: 30,
            currentMarginRight: 40,
            reserveSafeAreaInsidePageFrame: false,
            reservePageIndicatorInsidePageFrame: false
        )

        XCTAssertEqual(
            FolioReaderPageFrameCalculator.webViewFrame(input: input),
            CGRect(x: 0, y: 40, width: 400, height: 680)
        )
        XCTAssertEqual(
            FolioReaderPageFrameCalculator.anchorBoundsFrame(input: input),
            CGRect(x: 60, y: 40, width: 260, height: 680)
        )
    }

    func testCompatibilityDefaultsReserveSafeAreaAndPageIndicator() {
        let config = FolioReaderConfig()
        XCTAssertTrue(config.reserveSafeAreaInsidePageFrame)
        XCTAssertTrue(config.reservePageIndicatorInsidePageFrame)

        let input = makeInput(
            statusbarHeight: 44,
            pageIndicatorHeight: 70,
            reserveSafeAreaInsidePageFrame: config.reserveSafeAreaInsidePageFrame,
            reservePageIndicatorInsidePageFrame: config.reservePageIndicatorInsidePageFrame
        )

        XCTAssertEqual(
            FolioReaderPageFrameCalculator.webViewFrame(input: input),
            CGRect(x: 0, y: 44, width: 400, height: 686)
        )
        XCTAssertEqual(
            FolioReaderPageFrameCalculator.anchorBoundsFrame(input: input),
            CGRect(x: 0, y: 44, width: 400, height: 686)
        )
    }

    /// `FolioReaderAnchorPreview` adds the link's offset in the web view to the anchor bounds' top.
    /// The status bar height used to be added twice, so the preview opened a status bar lower.
    func testHorizontalAnchorBoundsStartAtTheWebViewTop() {
        for scrollDirection in [FolioReaderScrollDirection.horizontalWithPagedContent, .horizontalWithScrollContent, .vertical] {
            for reserveSafeArea in [true, false] {
                let input = makeInput(
                    scrollDirection: scrollDirection,
                    currentMarginTop: 10,
                    currentMarginBottom: 20,
                    statusbarHeight: 62,
                    pageIndicatorHeight: 70,
                    reserveSafeAreaInsidePageFrame: reserveSafeArea
                )
                XCTAssertEqual(
                    FolioReaderPageFrameCalculator.anchorBoundsFrame(input: input).minY,
                    FolioReaderPageFrameCalculator.webViewFrame(input: input).minY,
                    "\(scrollDirection), reserve safe area: \(reserveSafeArea)"
                )
            }
        }
    }

    func testHiddenPageIndicatorDoesNotReserveIndicatorHeight() {
        let input = makeInput(
            statusbarHeight: 44,
            pageIndicatorHeight: 70,
            hidePageIndicator: true
        )

        XCTAssertEqual(
            FolioReaderPageFrameCalculator.webViewFrame(input: input),
            CGRect(x: 0, y: 44, width: 400, height: 756)
        )
    }

    func testPagedMarginsCombineWithReservedComponents() {
        let input = makeInput(
            scrollDirection: .horizontalWithPagedContent,
            currentMarginTop: 10,
            currentMarginBottom: 20,
            currentMarginLeft: 30,
            currentMarginRight: 40,
            statusbarHeight: 44,
            pageIndicatorHeight: 70
        )

        XCTAssertEqual(
            FolioReaderPageFrameCalculator.webViewFrame(input: input),
            CGRect(x: 0, y: 84, width: 400, height: 566)
        )
        XCTAssertEqual(
            FolioReaderPageFrameCalculator.anchorBoundsFrame(input: input),
            CGRect(x: 60, y: 84, width: 260, height: 566)
        )
    }

    func testVerticalWritingModeAppliesHorizontalMarginsOnlyWhenPaged() {
        let paged = makeInput(
            writingMode: "vertical-rl",
            scrollDirection: .horizontalWithPagedContent,
            currentMarginTop: 10,
            currentMarginBottom: 20,
            currentMarginLeft: 30,
            currentMarginRight: 40,
            statusbarHeight: 44,
            pageIndicatorHeight: 70
        )

        XCTAssertEqual(
            FolioReaderPageFrameCalculator.webViewFrame(input: paged),
            CGRect(x: 60, y: 44, width: 260, height: 686)
        )
        XCTAssertEqual(
            FolioReaderPageFrameCalculator.anchorBoundsFrame(input: paged),
            CGRect(x: 60, y: 84, width: 260, height: 566)
        )

        let scrolled = makeInput(
            writingMode: "vertical-rl",
            scrollDirection: .vertical,
            currentMarginTop: 10,
            currentMarginBottom: 20,
            currentMarginLeft: 30,
            currentMarginRight: 40,
            statusbarHeight: 44,
            pageIndicatorHeight: 70
        )

        XCTAssertEqual(
            FolioReaderPageFrameCalculator.webViewFrame(input: scrolled),
            CGRect(x: 0, y: 44, width: 400, height: 686)
        )
        XCTAssertEqual(
            FolioReaderPageFrameCalculator.anchorBoundsFrame(input: scrolled),
            CGRect(x: 60, y: 84, width: 260, height: 566)
        )
    }

    func testOversizedPagedMarginsCollapseHeightWithoutMovingOrigin() {
        let input = makeInput(
            scrollDirection: .horizontalWithPagedContent,
            currentMarginTop: 100,
            currentMarginBottom: 100,
            statusbarHeight: 44,
            pageIndicatorHeight: 70
        )

        XCTAssertEqual(
            FolioReaderPageFrameCalculator.webViewFrame(input: input),
            CGRect(x: 0, y: 444, width: 400, height: 0)
        )
        XCTAssertEqual(
            FolioReaderPageFrameCalculator.anchorBoundsFrame(input: input),
            CGRect(x: 0, y: 444, width: 400, height: 0)
        )
    }

    private func makeInput(
        bounds: CGRect = CGRect(x: 0, y: 0, width: 400, height: 800),
        writingMode: String = "horizontal-tb",
        scrollDirection: FolioReaderScrollDirection = .horizontalWithScrollContent,
        currentMarginTop: Int = 0,
        currentMarginBottom: Int = 0,
        currentMarginLeft: Int = 0,
        currentMarginRight: Int = 0,
        pageWidth: CGFloat = 400,
        pageHeight: CGFloat = 800,
        statusbarHeight: CGFloat = 0,
        pageIndicatorHeight: CGFloat = 0,
        hidePageIndicator: Bool = false,
        reserveSafeAreaInsidePageFrame: Bool = true,
        reservePageIndicatorInsidePageFrame: Bool = true
    ) -> FolioReaderPageFrameInput {
        FolioReaderPageFrameInput(
            bounds: bounds,
            writingMode: writingMode,
            scrollDirection: scrollDirection,
            currentMarginTop: currentMarginTop,
            currentMarginBottom: currentMarginBottom,
            currentMarginLeft: currentMarginLeft,
            currentMarginRight: currentMarginRight,
            pageWidth: pageWidth,
            pageHeight: pageHeight,
            statusbarHeight: statusbarHeight,
            pageIndicatorHeight: pageIndicatorHeight,
            hidePageIndicator: hidePageIndicator,
            reserveSafeAreaInsidePageFrame: reserveSafeAreaInsidePageFrame,
            reservePageIndicatorInsidePageFrame: reservePageIndicatorInsidePageFrame
        )
    }
}
