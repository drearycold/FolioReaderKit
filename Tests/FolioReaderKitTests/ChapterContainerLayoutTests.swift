import XCTest
import ReadiumGCDWebServer
@testable import FolioReaderKit

@MainActor
final class ChapterContainerLayoutTests: XCTestCase {
    private var containers = [FolioReaderContainer]()

    override func tearDown() {
        containers.removeAll()
        super.tearDown()
    }

    private func makeCenter(_ direction: FolioReaderScrollDirection) throws -> FolioReaderCenter {
        let config = FolioReaderConfig()
        config.scrollDirection = direction
        config.hideBars = true
        config.hidePageIndicator = true
        let container = FolioReaderContainer(
            withConfig: config, folioReader: FolioReader(), epubPath: "",
            webServer: ReadiumGCDWebServer()
        )
        containers.append(container)
        container.loadViewIfNeeded()
        let center = try XCTUnwrap(container.centerViewController)
        center.loadViewIfNeeded()
        center.view.frame = CGRect(x: 0, y: 0, width: 744, height: 1046)
        center.viewDidLayoutSubviews()
        center.totalPages = 5
        center.collectionView.reloadData()
        center.collectionView.layoutIfNeeded()
        return center
    }

    /// Loading the neighbour exposed by a held drag must not pull the chapter container back
    /// to a whole-page origin. 125.5 pt is the displacement just before the recorded snap.
    func testANeighbourFinishingLoadingPreservesTheChapterDrag() throws {
        let center = try makeCenter(.horizontalWithScrollContent)
        center.isScrolling = true
        let offset = CGPoint(x: 125.5, y: 0)
        center.collectionView.contentOffset = offset
        center.collectionView.layoutIfNeeded()
        let neighbour = try XCTUnwrap(center.collectionView.cellForItem(at: IndexPath(item: 1, section: 0)) as? FolioReaderPage)
        // UIKit rounds offsets to the device's pixel grid (the iPhone is 3x, the recorded iPad 2x).
        let offsetBeforeLoad = center.collectionView.contentOffset

        center.pageDidLoad(neighbour)

        XCTAssertEqual(center.collectionView.contentOffset, offsetBeforeLoad)
    }

    /// UIKit may lay out the controller while dragging or decelerating, on either chapter axis.
    /// Even after the midpoint, a layout pass must leave the native paging motion in control.
    func testAnUnchangedLayoutPreservesIntermediateOffsetsOnBothAxes() throws {
        for direction: FolioReaderScrollDirection in [.horizontalWithScrollContent, .vertical] {
            let center = try makeCenter(direction)
            for fraction: CGFloat in [0.2, 0.65] {
                let offset = direction == .vertical
                    ? CGPoint(x: 0, y: center.pageHeight * (1 + fraction))
                    : CGPoint(x: center.pageWidth * (1 + fraction), y: 0)
                center.collectionView.contentOffset = offset
                center.collectionView.layoutIfNeeded()
                let offsetBeforeLayout = center.collectionView.contentOffset

                center.viewDidLayoutSubviews()

                XCTAssertEqual(center.collectionView.contentOffset, offsetBeforeLayout, "\(direction), \(fraction)")
            }
        }
    }

    func testARealResizeKeepsTheChapterOnBothAxes() throws {
        for direction: FolioReaderScrollDirection in [.horizontalWithScrollContent, .vertical] {
            let center = try makeCenter(direction)
            center.collectionView.contentOffset = direction == .vertical
                ? CGPoint(x: 0, y: center.pageHeight * 2)
                : CGPoint(x: center.pageWidth * 2, y: 0)
            center.collectionView.layoutIfNeeded()
            XCTAssertEqual(center.currentPageNumber, 3)

            center.screenBounds = CGRect(x: 0, y: 0, width: 1133, height: 657)
            center.updateSubviewFrames()
            center.collectionView.layoutIfNeeded()

            let expected = direction == .vertical
                ? CGPoint(x: 0, y: 657 * 2)
                : CGPoint(x: 1133 * 2, y: 0)
            XCTAssertEqual(center.collectionView.contentOffset, expected)
            XCTAssertEqual(center.currentPageNumber, 3)
        }
    }

    func testExplicitChapterNavigationStillPositionsTheContainer() throws {
        let center = try makeCenter(.horizontalWithScrollContent)

        center.changePageWith(indexPath: IndexPath(item: 2, section: 0), retryDelaySec: 0)

        XCTAssertEqual(center.collectionView.contentOffset, CGPoint(x: center.pageWidth * 2, y: 0))
        XCTAssertEqual(center.currentPageNumber, 3)
    }
}
