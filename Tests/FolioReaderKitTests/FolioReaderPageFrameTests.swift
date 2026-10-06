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
            CGRect(x: 0, y: 88, width: 400, height: 686)
        )
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
