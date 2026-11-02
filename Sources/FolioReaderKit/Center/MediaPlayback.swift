import UIKit

extension FolioReaderCenter {
    func updateMediaVisibility() {
        guard isViewLoaded, let collectionView = collectionView else { return }
        let current = currentPage
        let readerVisible = readerContainer?.mediaReaderVisible ?? false
        for case let page as FolioReaderPage in collectionView.visibleCells {
            let script = "folioSetReaderVisible(\(readerVisible)); folioSetMediaPageVisible(\(page === current));"
            guard page.mediaVisibilityScript != script else { continue }
            page.mediaVisibilityScript = script
            page.webView?.js(script)
        }
    }

    func pauseVideos() {
        guard isViewLoaded, let collectionView = collectionView else { return }
        for case let page as FolioReaderPage in collectionView.visibleCells {
            page.webView?.js("folioPauseVideos(true)")
        }
    }
}
