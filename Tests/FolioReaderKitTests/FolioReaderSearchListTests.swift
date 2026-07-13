import XCTest
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
        try? await Task.sleep(nanoseconds: 450_000_000)

        XCTAssertEqual(list.sections.first?.results, [newResult])
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
