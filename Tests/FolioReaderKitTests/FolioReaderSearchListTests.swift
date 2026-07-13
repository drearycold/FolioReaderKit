import XCTest
import ReadiumGCDWebServer
@testable import FolioReaderKit

@MainActor
final class FolioReaderSearchListTests: XCTestCase {
    func testSearchListShowsInitialAndGroupsResultsAfterDebounce() async {
        let result = FolioReaderLocatorResult(page: 1, cfi: "epubcfi(/2/2:6)",
                                               context: "A café result", tocPath: ["Chapter One"])
        let resolver = StubSearchResolver(results: [result])
        let config = FolioReaderConfig()
        let list = FolioReaderSearchList(folioReader: FolioReader(), readerConfig: config, resolver: resolver)
        list.loadViewIfNeeded()

        XCTAssertEqual(list.state, .initial)
        list.searchController.searchBar.text = "cafe"
        list.updateSearchResults(for: list.searchController)
        XCTAssertEqual(list.state, .loading)

        try? await Task.sleep(nanoseconds: 450_000_000)

        XCTAssertEqual(list.state, .results)
        XCTAssertEqual(list.sections.count, 1)
        XCTAssertEqual(list.sections.first?.title, "Chapter One")
        XCTAssertEqual(list.sections.first?.results, [result])
    }

    func testNewSearchGenerationPreventsOldResultsFromReplacingIt() async {
        let oldResult = FolioReaderLocatorResult(page: 1, cfi: "old", context: "old result")
        let newResult = FolioReaderLocatorResult(page: 2, cfi: "new", context: "new result")
        let resolver = StubSearchResolver(resultsByQuery: ["old": [oldResult], "new": [newResult]], oldQueryDelay: 0.4)
        let list = FolioReaderSearchList(folioReader: FolioReader(), readerConfig: FolioReaderConfig(), resolver: resolver)
        list.loadViewIfNeeded()

        list.searchController.searchBar.text = "old"
        list.updateSearchResults(for: list.searchController)
        try? await Task.sleep(nanoseconds: 350_000_000)
        list.searchController.searchBar.text = "new"
        list.updateSearchResults(for: list.searchController)
        try? await Task.sleep(nanoseconds: 800_000_000)

        XCTAssertEqual(list.sections.first?.results, [newResult])
    }

    func testSelectingOldResultsWhileNewQueryIsPendingDoesNothing() async {
        let config = FolioReaderConfig(withIdentifier: "pending-selection-book")
        let folioReader = FolioReader()
        let delegate = MockFolioReaderDelegate()
        folioReader.delegate = delegate
        let container = FolioReaderContainer(
            withConfig: config,
            folioReader: folioReader,
            epubPath: "",
            webServer: ReadiumGCDWebServer()
        )
        let readerCenter = FolioReaderCenter(withContainer: container)
        container.centerViewController = readerCenter
        readerCenter.loadViewIfNeeded()

        let oldResult = FolioReaderLocatorResult(page: 1, cfi: "old", context: "apple result")
        let newResult = FolioReaderLocatorResult(page: 2, cfi: "new", context: "banana result")
        let resolver = StubSearchResolver(resultsByQuery: [
            "apple": [oldResult],
            "banana": [newResult]
        ])
        let list = FolioReaderSearchList(folioReader: folioReader, readerConfig: config, resolver: resolver)
        list.loadViewIfNeeded()

        list.searchController.searchBar.text = "apple"
        list.updateSearchResults(for: list.searchController)
        try? await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertEqual(readerCenter.searchSession.query, "apple")
        XCTAssertEqual(list.sections.flatMap(\.results), [oldResult])

        list.searchController.searchBar.text = "banana"
        list.updateSearchResults(for: list.searchController)
        list.tableView(list.tableView, didSelectRowAt: IndexPath(row: 0, section: 0))

        let store = FolioReaderSearchHistoryStore(provider: delegate.preferenceProvider, identifier: config.identifier)
        XCTAssertNotNil(list.searchController.searchResultsUpdater)
        XCTAssertNotNil(list.searchController.searchBar.delegate)
        XCTAssertTrue(store.load().isEmpty)
        XCTAssertEqual(readerCenter.searchSession.query, "apple")
        XCTAssertEqual(readerCenter.searchSession.results, [oldResult])
        XCTAssertEqual(list.sections.flatMap(\.results), [oldResult])
    }

    func testSelectingResultsWhileExpansionIsPendingDoesNothing() async {
        let config = FolioReaderConfig(withIdentifier: "pending-expansion-book")
        config.searchResultLimit = 2
        let folioReader = FolioReader()
        let delegate = MockFolioReaderDelegate()
        folioReader.delegate = delegate
        let container = FolioReaderContainer(
            withConfig: config,
            folioReader: folioReader,
            epubPath: "",
            webServer: ReadiumGCDWebServer()
        )
        let readerCenter = FolioReaderCenter(withContainer: container)
        container.centerViewController = readerCenter
        readerCenter.loadViewIfNeeded()

        let resolver = ExpansionStubSearchResolver(expansionDelay: 0.3)
        let list = FolioReaderSearchList(folioReader: folioReader, readerConfig: config, resolver: resolver)
        list.loadViewIfNeeded()
        list.searchController.searchBar.text = "term"
        list.updateSearchResults(for: list.searchController)
        try? await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertEqual(readerCenter.searchSession.results.map(\.page), [2, 3])

        list.loadLaterResults()
        list.tableView(list.tableView, didSelectRowAt: IndexPath(row: 0, section: 0))

        let store = FolioReaderSearchHistoryStore(provider: delegate.preferenceProvider, identifier: config.identifier)
        XCTAssertNotNil(list.searchController.searchResultsUpdater)
        XCTAssertNotNil(list.searchController.searchBar.delegate)
        XCTAssertTrue(store.load().isEmpty)
        XCTAssertEqual(readerCenter.searchSession.results.map(\.page), [2, 3])
    }

    func testCloseButtonUsesSearchSpecificAction() {
        let list = FolioReaderSearchList(folioReader: FolioReader(), readerConfig: FolioReaderConfig())
        list.loadViewIfNeeded()

        XCTAssertTrue(list.navigationItem.leftBarButtonItem?.target === list)
        XCTAssertEqual(list.navigationItem.leftBarButtonItem?.action, #selector(FolioReaderSearchList.closeSearch(_:)))

        list.closeSearch(list.navigationItem.leftBarButtonItem!)

        XCTAssertNil(list.searchController.searchResultsUpdater)
        XCTAssertNil(list.searchController.searchBar.delegate)
    }

    func testSelectingResultStopsSearchUpdatesBeforeDismissal() async {
        let config = FolioReaderConfig()
        let folioReader = FolioReader()
        let delegate = MockFolioReaderDelegate()
        folioReader.delegate = delegate
        let store = FolioReaderSearchHistoryStore(provider: delegate.preferenceProvider, identifier: config.identifier)
        let container = FolioReaderContainer(
            withConfig: config,
            folioReader: folioReader,
            epubPath: "",
            webServer: ReadiumGCDWebServer()
        )
        let readerCenter = FolioReaderCenter(withContainer: container)
        container.centerViewController = readerCenter
        readerCenter.loadViewIfNeeded()

        let result = FolioReaderLocatorResult(page: 1, cfi: "epubcfi(/2/2:6)", context: "term result")
        let list = FolioReaderSearchList(
            folioReader: folioReader,
            readerConfig: config,
            resolver: StubSearchResolver(results: [result])
        )
        list.loadViewIfNeeded()
        let searchNavigationController = FolioReaderNavigationController(rootViewController: list)
        searchNavigationController.loadViewIfNeeded()
        let window = UIWindow(frame: UIScreen.main.bounds)
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        host.present(searchNavigationController, animated: false)

        list.searchController.searchBar.text = "term"
        list.updateSearchResults(for: list.searchController)
        try? await Task.sleep(nanoseconds: 450_000_000)

        list.tableView(list.tableView, didSelectRowAt: IndexPath(row: 0, section: 0))

        XCTAssertNil(list.searchController.searchResultsUpdater)
        XCTAssertNil(list.searchController.searchBar.delegate)
        XCTAssertEqual(store.load(), ["term"])
    }

    func testInitialSearchPrefersForwardResultsThenWrapsEarlierResults() async {
        let config = FolioReaderConfig()
        config.searchResultLimit = 2
        let forwardResult = FolioReaderLocatorResult(page: 2, cfi: "forward", context: "forward")
        let backwardResult = FolioReaderLocatorResult(page: 1, cfi: "backward", context: "backward")
        let resolver = DirectionalStubSearchResolver(forward: [forwardResult], backward: [backwardResult])
        let list = FolioReaderSearchList(folioReader: FolioReader(), readerConfig: config, resolver: resolver)
        list.loadViewIfNeeded()

        list.searchController.searchBar.text = "term"
        list.updateSearchResults(for: list.searchController)
        try? await Task.sleep(nanoseconds: 800_000_000)

        XCTAssertEqual(list.sections.flatMap(\.results).map(\.page), [1, 2])
        XCTAssertEqual(resolver.directions, [.forward, .backward])
    }

    func testSelectingRecentHistoryStartsANewSearch() async {
        let config = FolioReaderConfig(withIdentifier: "history-book")
        let folioReader = FolioReader()
        let delegate = MockFolioReaderDelegate()
        folioReader.delegate = delegate
        let store = FolioReaderSearchHistoryStore(provider: delegate.preferenceProvider, identifier: config.identifier)
        store.record("previous term")

        let list = FolioReaderSearchList(
            folioReader: folioReader,
            readerConfig: config,
            resolver: StubSearchResolver(results: [])
        )
        list.loadViewIfNeeded()

        XCTAssertEqual(list.history, ["previous term"])
        list.tableView(list.tableView, didSelectRowAt: IndexPath(row: 0, section: 0))

        XCTAssertEqual(list.searchController.searchBar.text, "previous term")
        XCTAssertEqual(list.state, .loading)
    }

    func testClosingInFlightQueryKeepsTheLastCompleteSession() async {
        let config = FolioReaderConfig()
        let folioReader = FolioReader()
        let container = FolioReaderContainer(
            withConfig: config,
            folioReader: folioReader,
            epubPath: "",
            webServer: ReadiumGCDWebServer()
        )
        let readerCenter = FolioReaderCenter(withContainer: container)
        container.centerViewController = readerCenter
        readerCenter.loadViewIfNeeded()

        let oldResult = FolioReaderLocatorResult(page: 1, cfi: "old", context: "old")
        let newResult = FolioReaderLocatorResult(page: 2, cfi: "new", context: "new")
        let resolver = StubSearchResolver(resultsByQuery: ["old": [oldResult], "new": [newResult]], oldQueryDelay: 0.1)
        let list = FolioReaderSearchList(folioReader: folioReader, readerConfig: config, resolver: resolver)
        list.loadViewIfNeeded()

        list.searchController.searchBar.text = "old"
        list.updateSearchResults(for: list.searchController)
        try? await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertEqual(readerCenter.searchSession.query, "old")

        list.searchController.searchBar.text = "new"
        list.updateSearchResults(for: list.searchController)
        list.closeSearch(list.navigationItem.leftBarButtonItem!)

        let reopened = FolioReaderSearchList(folioReader: folioReader, readerConfig: config, resolver: resolver)
        reopened.loadViewIfNeeded()

        XCTAssertEqual(reopened.searchController.searchBar.text, "old")
        XCTAssertEqual(reopened.sections.flatMap(\.results), [oldResult])
    }

    func testExpandingBothDirectionsMergesInNaturalOrder() async {
        let config = FolioReaderConfig()
        config.searchResultLimit = 2
        let resolver = ExpansionStubSearchResolver()
        let list = FolioReaderSearchList(folioReader: FolioReader(), readerConfig: config, resolver: resolver)
        list.loadViewIfNeeded()

        list.searchController.searchBar.text = "term"
        list.updateSearchResults(for: list.searchController)
        try? await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertEqual(list.sections.flatMap(\.results).map(\.page), [2, 3])

        list.loadEarlierResults()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(list.sections.flatMap(\.results).map(\.page), [1, 2, 3])

        list.loadLaterResults()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(list.sections.flatMap(\.results).map(\.page), [1, 2, 3, 4])
    }

    func testBackwardBatchesKeepNearestResultsAndExpandContinuously() async {
        let config = FolioReaderConfig()
        config.searchResultLimit = 2
        let resolver = BackwardBatchSearchResolver()
        let list = FolioReaderSearchList(folioReader: FolioReader(), readerConfig: config, resolver: resolver)
        list.loadViewIfNeeded()

        list.searchController.searchBar.text = "term"
        list.updateSearchResults(for: list.searchController)
        try? await Task.sleep(nanoseconds: 450_000_000)

        XCTAssertEqual(list.sections.flatMap(\.results).map(\.page), [4, 5])

        list.loadEarlierResults()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(list.sections.flatMap(\.results).map(\.page), [2, 3, 4, 5])

        list.loadEarlierResults()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(list.sections.flatMap(\.results).map(\.page), [1, 2, 3, 4, 5])
    }

    func testRecentHistoryCellDisplaysStoredText() {
        let config = FolioReaderConfig(withIdentifier: "history-cell-book")
        let folioReader = FolioReader()
        let delegate = MockFolioReaderDelegate()
        folioReader.delegate = delegate
        let store = FolioReaderSearchHistoryStore(provider: delegate.preferenceProvider, identifier: config.identifier)
        store.record("previous term")

        let list = FolioReaderSearchList(
            folioReader: folioReader,
            readerConfig: config,
            resolver: StubSearchResolver(results: [])
        )
        list.loadViewIfNeeded()

        let cell = list.tableView(list.tableView, cellForRowAt: IndexPath(row: 0, section: 0))

        XCTAssertEqual(cell.textLabel?.text, "previous term")
    }

    func testCompletedDebounceDoesNotRecordHistoryUntilExplicitSubmit() async {
        let config = FolioReaderConfig(withIdentifier: "history-submit-book")
        let folioReader = FolioReader()
        let delegate = MockFolioReaderDelegate()
        folioReader.delegate = delegate
        let store = FolioReaderSearchHistoryStore(provider: delegate.preferenceProvider, identifier: config.identifier)
        let list = FolioReaderSearchList(
            folioReader: folioReader,
            readerConfig: config,
            resolver: StubSearchResolver(results: [FolioReaderLocatorResult(page: 1, cfi: "cfi", context: "term")])
        )
        list.loadViewIfNeeded()

        list.searchController.searchBar.text = "term"
        list.updateSearchResults(for: list.searchController)
        try? await Task.sleep(nanoseconds: 450_000_000)

        XCTAssertTrue(store.load().isEmpty)

        list.searchBarSearchButtonClicked(list.searchController.searchBar)

        XCTAssertEqual(store.load(), ["term"])
    }

    func testClosingCompletedSearchRecordsHistory() async {
        let config = FolioReaderConfig(withIdentifier: "history-close-book")
        let folioReader = FolioReader()
        let delegate = MockFolioReaderDelegate()
        folioReader.delegate = delegate
        let store = FolioReaderSearchHistoryStore(provider: delegate.preferenceProvider, identifier: config.identifier)
        let list = FolioReaderSearchList(
            folioReader: folioReader,
            readerConfig: config,
            resolver: StubSearchResolver(results: [FolioReaderLocatorResult(page: 1, cfi: "cfi", context: "term")])
        )
        list.loadViewIfNeeded()

        list.searchController.searchBar.text = "term"
        list.updateSearchResults(for: list.searchController)
        try? await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertTrue(store.load().isEmpty)

        list.closeSearch(list.navigationItem.leftBarButtonItem!)

        XCTAssertEqual(store.load(), ["term"])
    }

    func testIntMaxSearchLimitUsesSaturatedIncrement() async {
        let config = FolioReaderConfig()
        config.searchResultLimit = Int.max
        let resolver = LimitRecordingSearchResolver()
        let list = FolioReaderSearchList(folioReader: FolioReader(), readerConfig: config, resolver: resolver)
        list.loadViewIfNeeded()

        list.searchController.searchBar.text = "term"
        list.updateSearchResults(for: list.searchController)
        try? await Task.sleep(nanoseconds: 450_000_000)

        XCTAssertEqual(resolver.limits, [Int.max, Int.max])
        XCTAssertEqual(list.state, .results)
    }
}

private final class StubSearchResolver: FolioReaderSearching {
    private let resultsByQuery: [String: [FolioReaderLocatorResult]]
    private let defaultResults: [FolioReaderLocatorResult]
    private let oldQueryDelay: UInt64

    init(results: [FolioReaderLocatorResult], oldQueryDelay: Double = 0) {
        self.defaultResults = results
        self.resultsByQuery = [:]
        self.oldQueryDelay = UInt64(oldQueryDelay * 1_000_000_000)
    }

    init(resultsByQuery: [String: [FolioReaderLocatorResult]], oldQueryDelay: Double = 0) {
        self.defaultResults = []
        self.resultsByQuery = resultsByQuery
        self.oldQueryDelay = UInt64(oldQueryDelay * 1_000_000_000)
    }

    func search(_ query: FolioReaderSearchQuery) async -> [FolioReaderLocatorResult] {
        if query.text == "old", oldQueryDelay > 0 {
            try? await Task.sleep(nanoseconds: oldQueryDelay)
        }
        return resultsByQuery[query.text] ?? defaultResults
    }
}

private final class DirectionalStubSearchResolver: FolioReaderSearching {
    let forwardResults: [FolioReaderLocatorResult]
    let backwardResults: [FolioReaderLocatorResult]
    private(set) var directions = [FolioReaderSearchDirection]()

    init(forward: [FolioReaderLocatorResult], backward: [FolioReaderLocatorResult]) {
        self.forwardResults = forward
        self.backwardResults = backward
    }

    func search(_ query: FolioReaderSearchQuery) async -> [FolioReaderLocatorResult] {
        directions.append(query.direction)
        return query.direction == .forward ? forwardResults : backwardResults
    }
}

private final class ExpansionStubSearchResolver: FolioReaderSearching {
    private let expansionDelay: UInt64

    init(expansionDelay: Double = 0) {
        self.expansionDelay = UInt64(expansionDelay * 1_000_000_000)
    }

    func search(_ query: FolioReaderSearchQuery) async -> [FolioReaderLocatorResult] {
        if query.anchor != nil, expansionDelay > 0 {
            try? await Task.sleep(nanoseconds: expansionDelay)
        }
        switch query.direction {
        case .forward:
            if query.anchor?.page == nil {
                return [result(page: 2), result(page: 3), result(page: 4)]
            }
            return [result(page: 4)]
        case .backward:
            if query.anchor?.page == nil {
                return [result(page: 1)]
            }
            return [result(page: 1)]
        }
    }

    private func result(page: Int) -> FolioReaderLocatorResult {
        FolioReaderLocatorResult(page: page, cfi: "cfi-\(page)", context: "term \(page)")
    }
}

private final class BackwardBatchSearchResolver: FolioReaderSearching {
    func search(_ query: FolioReaderSearchQuery) async -> [FolioReaderLocatorResult] {
        switch query.direction {
        case .forward:
            return []
        case .backward:
            if query.anchor?.page == nil {
                return (1...5).map(result)
            }
            if query.anchor?.page == 4 {
                return (1...3).map(result)
            }
            return [result(page: 1)]
        }
    }

    private func result(page: Int) -> FolioReaderLocatorResult {
        FolioReaderLocatorResult(page: page, cfi: "backward-\(page)", context: "term \(page)")
    }
}

private final class LimitRecordingSearchResolver: FolioReaderSearching {
    private(set) var limits = [Int?]()

    func search(_ query: FolioReaderSearchQuery) async -> [FolioReaderLocatorResult] {
        limits.append(query.limit)
        if query.direction == .forward {
            return [FolioReaderLocatorResult(page: 1, cfi: "cfi", context: "term")]
        }
        return []
    }
}
