import XCTest
import FolioEPUBCore
@testable import FolioReaderKit

final class FolioReaderReferenceResolverTests: XCTestCase {
    func testReverseLookupReturnsPageCFIAndSnippet() async {
        let resolver = makeResolver(html: "<html><body><p>Before selected term after.</p></body></html>")

        let results = await resolver.reverseLookup(text: "selected", before: nil)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.page, 1)
        XCTAssertEqual(results.first?.href, "chapter.xhtml")
        XCTAssertTrue(results.first?.cfi?.hasPrefix("epubcfi(") == true)
        XCTAssertTrue(results.first?.context?.contains("Before selected term after.") == true)
    }

    func testReverseLookupReturnsEveryDuplicate() async {
        let resolver = makeResolver(html: "<html><body><p>term then term then term</p></body></html>")

        let results = await resolver.reverseLookup(text: "term", before: nil)

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(Set(results.compactMap(\.cfi)).count, 3)
    }

    func testReverseLookupReturnsEmptyWhenThereIsNoMatch() async {
        let resolver = makeResolver(html: "<html><body><p>unrelated text</p></body></html>")

        let results = await resolver.reverseLookup(text: "missing", before: nil)

        XCTAssertTrue(results.isEmpty)
    }

    func testLocationProvidersRemainUIIndependent() async {
        let expected = FolioReaderLocatorResult(page: 2, cfi: "epubcfi(/4/2)", text: "selected")
        let resolver = makeResolver(html: "", current: expected, selected: expected)

        let current = await resolver.currentLocation()
        let selected = await resolver.selectedTextLocation()

        XCTAssertEqual(current, expected)
        XCTAssertEqual(selected, expected)
    }

    private func makeResolver(html: String,
                              current: FolioReaderLocatorResult? = nil,
                              selected: FolioReaderLocatorResult? = nil) -> FolioReaderReferenceResolver {
        let book = FRBook()
        let resource = FRResource()
        resource.href = "chapter.xhtml"
        book.spine.spineReferences = [Spine(resource: resource)]
        return FolioReaderReferenceResolver(book: book,
                                            currentLocation: { current },
                                            selectedTextLocation: { selected },
                                            documentProvider: { _ in html })
    }
}
