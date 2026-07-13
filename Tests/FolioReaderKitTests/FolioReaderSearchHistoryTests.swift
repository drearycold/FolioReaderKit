import XCTest
@testable import FolioReaderKit

final class FolioReaderSearchHistoryTests: XCTestCase {
    func testHistoryIsIsolatedByReaderIdentifier() {
        let provider = MockPreferenceProvider()
        let first = FolioReaderSearchHistoryStore(provider: provider, identifier: "book-a")
        let second = FolioReaderSearchHistoryStore(provider: provider, identifier: "book-b")

        first.record("first")
        second.record("second")

        XCTAssertEqual(first.load(), ["first"])
        XCTAssertEqual(second.load(), ["second"])
    }

    func testHistoryTrimsDeduplicatesAccentInsensitiveAndKeepsNewestSpelling() {
        let provider = MockPreferenceProvider()
        let store = FolioReaderSearchHistoryStore(provider: provider, identifier: "book")

        store.record("  Café  ")
        store.record("CAFE")

        XCTAssertEqual(store.load(), ["CAFE"])
    }

    func testHistoryIsLimitedToOneHundredEntries() {
        let provider = MockPreferenceProvider()
        let store = FolioReaderSearchHistoryStore(provider: provider, identifier: "book")

        for index in 0..<105 {
            store.record("term-\(index)")
        }

        XCTAssertEqual(store.load().count, 100)
        XCTAssertEqual(store.load().first, "term-104")
        XCTAssertEqual(store.load().last, "term-5")
    }

    func testCorruptHistoryJSONFallsBackToEmpty() {
        let provider = MockPreferenceProvider()
        let key = FolioReaderSearchHistoryStore.preferenceKey(for: "book")
        provider.preference(setString: "not-json", for: key)

        XCTAssertTrue(FolioReaderSearchHistoryStore(provider: provider, identifier: "book").load().isEmpty)
    }
}
