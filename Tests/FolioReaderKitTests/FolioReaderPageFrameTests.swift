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

        // Pages that run down (`.vertical`, "Tiered") are paged too.
        let pagedDown = makeInput(
            writingMode: "vertical-rl",
            scrollDirection: .vertical,
            pagesDown: true,
            currentMarginTop: 10,
            currentMarginBottom: 20,
            currentMarginLeft: 30,
            currentMarginRight: 40,
            statusbarHeight: 44,
            pageIndicatorHeight: 70
        )
        XCTAssertEqual(
            FolioReaderPageFrameCalculator.webViewFrame(input: pagedDown),
            FolioReaderPageFrameCalculator.webViewFrame(input: paged)
        )

        let scrolled = makeInput(
            writingMode: "vertical-rl",
            scrollDirection: .horizontalWithScrollContent,
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

    /// WebKit's viewport is whole CSS pixels. YAEBR's reader toolbar left an iPad Pro 10.5" page
    /// 751.5 pt tall in landscape; in vertical writing the viewport follows the height, so the pages
    /// were laid out 781 px wide on 780 pt screens and the chapter never finished loading.
    func testWebViewFrameIsInWholePoints() {
        let landscape = makeInput(
            bounds: CGRect(x: 0, y: 0, width: 1112, height: 751.5),
            writingMode: "vertical-rl",
            scrollDirection: .horizontalWithPagedContent,
            currentMarginLeft: 30,
            currentMarginRight: 30,
            pageWidth: 1112,
            pageHeight: 751.5,
            reserveSafeAreaInsidePageFrame: false,
            reservePageIndicatorInsidePageFrame: false
        )
        XCTAssertEqual(
            FolioReaderPageFrameCalculator.webViewFrame(input: landscape),
            CGRect(x: 166, y: 0, width: 780, height: 751)
        )

        let halfPointStatusBar = makeInput(
            bounds: CGRect(x: 0, y: 0, width: 400.5, height: 800),
            statusbarHeight: 20.5
        )
        XCTAssertEqual(
            FolioReaderPageFrameCalculator.webViewFrame(input: halfPointStatusBar),
            CGRect(x: 0, y: 20.5, width: 400, height: 779)
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

    /// A spread's columns repeat `<body>`'s padding, so the gutter is two columns' padding; the
    /// frame adds as much again on the outside (a quarter of the margin, in the web view's width),
    /// so an outer margin is as wide as the gutter.
    func testSpreadInsetsTheOuterMarginsByTheColumnsPadding() {
        func spread(_ bounds: CGRect, left: Int = 30, right: Int = 30, minimumWidth: CGFloat? = 1000,
                    writingMode: String = "horizontal-tb", scrollDirection: FolioReaderScrollDirection = .horizontalWithPagedContent) -> CGRect {
            FolioReaderPageFrameCalculator.webViewFrame(input: makeInput(
                bounds: bounds,
                writingMode: writingMode,
                scrollDirection: scrollDirection,
                spreadMinimumWidth: minimumWidth,
                currentMarginTop: 10,
                currentMarginBottom: 10,
                currentMarginLeft: left,
                currentMarginRight: right,
                pageWidth: bounds.width,
                pageHeight: bounds.height
            ))
        }
        // iPad mini in landscape: 15vw margins, so 3.75% of the web view's width outside it and in
        // each column. 1133 = 1055 * 1.075 (39 + 39 points, rounded down).
        let landscape = CGRect(x: 0, y: 0, width: 1133, height: 744)
        XCTAssertEqual(spread(landscape), CGRect(x: 39, y: 37, width: 1055, height: 670))
        XCTAssertEqual(0.0375 * 1055, 39, accuracy: 1, "The columns' padding")
        XCTAssertEqual(spread(landscape, left: 30, right: 10), CGRect(x: 40, y: 37, width: 1080, height: 670))

        // The web view stays as wide as the media query asks: a 1024-point iPad only gets 24 points.
        XCTAssertEqual(spread(CGRect(x: 0, y: 0, width: 1024, height: 748)), CGRect(x: 12, y: 37, width: 1000, height: 674))
        // And landscape: 1001 points for a page 1000 high.
        XCTAssertEqual(spread(CGRect(x: 0, y: 0, width: 1012, height: 1110)), CGRect(x: 5, y: 55, width: 1002, height: 1000))

        // No spread, or no margins: the frame is the page's.
        let page = CGRect(x: 0, y: 37, width: 1133, height: 670)
        XCTAssertEqual(spread(landscape, minimumWidth: nil), page)
        XCTAssertEqual(spread(landscape, minimumWidth: .infinity), page)
        XCTAssertEqual(spread(landscape, minimumWidth: 1134), page)
        XCTAssertEqual(spread(landscape, left: 0, right: 0), page)
        XCTAssertEqual(spread(CGRect(x: 0, y: 0, width: 744, height: 1133)), CGRect(x: 0, y: 56, width: 744, height: 1021), "Portrait")
        XCTAssertEqual(spread(landscape, scrollDirection: .horizontalWithScrollContent), landscape)
        XCTAssertEqual(spread(landscape, writingMode: "vertical-rl"), CGRect(x: 169, y: 0, width: 795, height: 744))
    }

    /// A spread fits by the web view's size before its outer margins, which narrow it.
    func testFitsSpreadMeasuresThePageBeforeTheOuterMargins() {
        let input = makeInput(
            bounds: CGRect(x: 0, y: 0, width: 1024, height: 748),
            scrollDirection: .horizontalWithPagedContent,
            spreadMinimumWidth: 1000,
            currentMarginLeft: 30,
            currentMarginRight: 30,
            pageWidth: 1024,
            pageHeight: 748
        )
        XCTAssertTrue(FolioReaderPageFrameCalculator.fitsSpread(input: input, minimumWidth: 1024))
        XCTAssertFalse(FolioReaderPageFrameCalculator.fitsSpread(input: input, minimumWidth: 1025))
        XCTAssertLessThan(FolioReaderPageFrameCalculator.webViewFrame(input: input).width, 1024)
    }

    private func makeInput(
        bounds: CGRect = CGRect(x: 0, y: 0, width: 400, height: 800),
        writingMode: String = "horizontal-tb",
        scrollDirection: FolioReaderScrollDirection = .horizontalWithScrollContent,
        pagesDown: Bool = false,
        spreadMinimumWidth: CGFloat? = nil,
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
            pagesDown: pagesDown,
            spreadMinimumWidth: spreadMinimumWidth,
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
