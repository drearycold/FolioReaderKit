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
    private func makeLaidOutPage(_ config: FolioReaderConfig, size: CGSize) throws -> (FolioReaderContainer, FolioReaderCenter, FolioReaderPage) {
        let container = FolioReaderContainer(withConfig: config, folioReader: FolioReader(), epubPath: "", webServer: ReadiumGCDWebServer())
        containers.append(container)
        container.loadViewIfNeeded()
        let center = try XCTUnwrap(container.centerViewController)
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
