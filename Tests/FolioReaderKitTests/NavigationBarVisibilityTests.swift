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

        let buttons = readerCenter.navigationItem.leftBarButtonItems ?? []
        XCTAssertEqual(buttons.map(\.action), [
            #selector(FolioReaderCenter.closeReader(_:)),
            #selector(FolioReaderCenter.presentChapterList(_:)),
            #selector(FolioReaderCenter.presentBookmarkList(_:))
        ])
        XCTAssertTrue(buttons.allSatisfy { $0.target === readerCenter })
    }

    func testConfigureNavBarButtonsCanHideCloseButton() {
        let (readerCenter, _) = makeReaderCenter(showCloseButton: false)

        readerCenter.configureNavBarButtons()

        let buttons = readerCenter.navigationItem.leftBarButtonItems ?? []
        XCTAssertEqual(buttons.map(\.action), [
            #selector(FolioReaderCenter.presentChapterList(_:)),
            #selector(FolioReaderCenter.presentBookmarkList(_:))
        ])
        XCTAssertTrue(buttons.allSatisfy { $0.target === readerCenter })
    }

    func testReferencePresentationDoesNotDependOnCloseButton() {
        let (readerCenter, _) = makeReaderCenter(showCloseButton: false)

        let navigationController = readerCenter.presentReferenceList(
            selectedText: "Selected text",
            selectedCFI: "/4/2:3"
        )

        XCTAssertEqual(readerCenter.tempRefText, "Selected text")
        XCTAssertEqual(readerCenter.tempRefCFI, "/4/2:3")
        XCTAssertEqual(readerCenter.folioReader.preferences.currentAnnotationMenuIndex, 0)
        let pageController = navigationController.viewControllers.first as? FolioReaderAnnotationPageVC
        XCTAssertEqual(pageController?.segmentedControlItems.first, "Reference")
    }

    func testBookmarkPresentationWithoutReferenceKeepsOriginalTabs() {
        let (readerCenter, _) = makeReaderCenter()

        let navigationController = readerCenter.presentBookmarkList()

        let pageController = navigationController.viewControllers.first as? FolioReaderAnnotationPageVC
        XCTAssertEqual(pageController?.segmentedControlItems, [
            readerCenter.readerConfig.localizedBookmarksTitle,
            readerCenter.readerConfig.localizedHighlightsTitle
        ])
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
