import XCTest
import ReadiumGCDWebServer
@testable import FolioReaderKit

@MainActor
final class NavigationBarVisibilityTests: XCTestCase {
    private func makeReaderCenter(
        hideBars: Bool = false,
        showCloseButton: Bool = true,
        forceBottomMenuTabBar: Bool = false
    ) -> (FolioReaderCenter, FolioReaderNavigationController) {
        let readerConfig = FolioReaderConfig()
        readerConfig.hideBars = hideBars
        readerConfig.showCloseButton = showCloseButton
        readerConfig.forceBottomMenuTabBar = forceBottomMenuTabBar

        let folioReader = FolioReader()
        let readerContainer = FolioReaderContainer(
            withConfig: readerConfig,
            folioReader: folioReader,
            epubPath: "",
            webServer: ReadiumGCDWebServer()
        )

        let readerCenter = FolioReaderCenter(withContainer: readerContainer)
        let navigationController = FolioReaderNavigationController(rootViewController: readerCenter)
        readerContainer.centerViewController = readerCenter
        readerContainer.centerNavigationController = navigationController

        navigationController.loadViewIfNeeded()
        readerCenter.loadViewIfNeeded()

        return (readerCenter, navigationController)
    }

    private func waitForMainQueue() {
        let expectation = expectation(description: "main queue")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testWillBeginDraggingHidesVisibleBars() {
        let (readerCenter, navigationController) = makeReaderCenter()
        navigationController.setNavigationBarHidden(false, animated: false)

        readerCenter.scrollHandler.scrollViewWillBeginDragging(readerCenter.collectionView)

        XCTAssertTrue(navigationController.isNavigationBarHidden)
    }

    func testDidScrollDoesNotHideBarsForProgrammaticScrollUpdates() {
        let (readerCenter, navigationController) = makeReaderCenter()
        navigationController.setNavigationBarHidden(false, animated: false)

        readerCenter.scrollHandler.scrollViewDidScroll(readerCenter.collectionView)

        XCTAssertFalse(navigationController.isNavigationBarHidden)
    }

    func testDidEndDraggingWithoutDecelerationClearsScrollingState() {
        let (readerCenter, _) = makeReaderCenter()

        readerCenter.scrollHandler.scrollViewWillBeginDragging(readerCenter.collectionView)
        XCTAssertTrue(readerCenter.isScrolling)

        readerCenter.scrollHandler.scrollViewDidEndDragging(readerCenter.collectionView, willDecelerate: false)

        XCTAssertFalse(readerCenter.isScrolling)
    }

    func testDidEndDeceleratingClearsScrollingState() {
        let (readerCenter, _) = makeReaderCenter()

        readerCenter.scrollHandler.scrollViewWillBeginDragging(readerCenter.collectionView)
        readerCenter.scrollHandler.scrollViewDidEndDragging(readerCenter.collectionView, willDecelerate: true)
        XCTAssertTrue(readerCenter.isScrolling)

        readerCenter.scrollHandler.scrollViewDidEndDecelerating(readerCenter.collectionView)

        XCTAssertFalse(readerCenter.isScrolling)
    }

    func testPendingRevealIsCancelledByDrag() {
        let (readerCenter, navigationController) = makeReaderCenter()
        navigationController.setNavigationBarHidden(true, animated: false)

        readerCenter.requestBarReveal(after: 0.05)
        readerCenter.scrollHandler.scrollViewWillBeginDragging(readerCenter.collectionView)
        waitForMainQueue()

        XCTAssertTrue(navigationController.isNavigationBarHidden)
    }

    func testHideBarsConfigurationPreventsReveal() {
        let (readerCenter, navigationController) = makeReaderCenter(hideBars: true)
        navigationController.setNavigationBarHidden(true, animated: false)

        readerCenter.showBars()
        readerCenter.requestBarReveal(after: 0.05)
        waitForMainQueue()

        XCTAssertTrue(navigationController.isNavigationBarHidden)
    }

    func testConfigureNavBarButtonsShowsCloseButtonByDefault() {
        let (readerCenter, _) = makeReaderCenter()

        readerCenter.configureNavBarButtons()

        XCTAssertEqual(readerCenter.navigationItem.leftBarButtonItems?.count, 3)
        XCTAssertTrue(readerCenter.navigationItem.leftBarButtonItems?.first?.target === readerCenter)
        XCTAssertEqual(readerCenter.navigationItem.leftBarButtonItems?.first?.action, #selector(FolioReaderCenter.closeReader(_:)))
    }

    func testConfigureNavBarButtonsCanHideCloseButton() {
        let (readerCenter, _) = makeReaderCenter(showCloseButton: false)

        readerCenter.configureNavBarButtons()

        XCTAssertEqual(readerCenter.navigationItem.leftBarButtonItems?.count, 2)
        XCTAssertFalse(readerCenter.navigationItem.leftBarButtonItems?.contains { $0.action == #selector(FolioReaderCenter.closeReader(_:)) } ?? true)
    }

    func testConfigureMenuTabBarPlacementUsesTabBarModeOnModernIOS() {
        guard #available(iOS 18.0, *) else { return }
        let (readerCenter, _) = makeReaderCenter()
        let tabBarController = UITabBarController()

        readerCenter.configureMenuTabBarPlacement(tabBarController)

        XCTAssertEqual(tabBarController.mode, .tabBar)
        XCTAssertFalse(tabBarController.traitOverrides.contains(UITraitHorizontalSizeClass.self))
    }

    func testConfigureMenuTabBarPlacementCanForceBottomPlacementOnModernIPadOS() {
        guard #available(iOS 18.0, *) else { return }
        let (readerCenter, _) = makeReaderCenter(forceBottomMenuTabBar: true)
        let tabBarController = UITabBarController()

        readerCenter.configureMenuTabBarPlacement(tabBarController)

        XCTAssertEqual(tabBarController.mode, .tabBar)
        XCTAssertEqual(tabBarController.traitOverrides.horizontalSizeClass, .compact)
    }
}
