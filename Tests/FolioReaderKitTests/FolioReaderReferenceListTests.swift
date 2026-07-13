import XCTest
import FolioEPUBCore
@testable import FolioReaderKit

@MainActor
final class FolioReaderReferenceListTests: XCTestCase {
    func testLoadSectionKeepsMatchesInTheirRequestedPageGroup() async {
        let pages = [
            "<html><body><p>term on page one</p></body></html>",
            "<html><body><p>term on page two</p></body></html>"
        ]
        let book = makeBook(pageCount: pages.count)
        let resolver = FolioReaderReferenceResolver(book: book, documentProvider: { page in
            pages[safe: page - 1]
        })
        let list = FolioReaderReferenceList(
            folioReader: FolioReader(),
            readerConfig: FolioReaderConfig(),
            referenceResolver: resolver
        )
        let deepest = FolioReaderBookmark()
        deepest.page = 2

        let firstSection = await list.loadSection(
            bookId: "book",
            book: book,
            pageNumber: 1,
            refText: "term",
            deepest: deepest
        )
        let secondSection = await list.loadSection(
            bookId: "book",
            book: book,
            pageNumber: 2,
            refText: "term",
            deepest: deepest
        )

        XCTAssertEqual(firstSection.map(\.page), [1])
        XCTAssertEqual(secondSection.map(\.page), [2])
        XCTAssertEqual(firstSection.compactMap(\.pos), ["epubcfi(/2/2/4/2/1:0)"])
        XCTAssertEqual(secondSection.compactMap(\.pos), ["epubcfi(/4/2/4/2/1:0)"])
    }

    private func makeBook(pageCount: Int) -> FRBook {
        let book = FRBook()
        book.spine.spineReferences = (1...pageCount).map { index in
            let resource = FRResource()
            resource.href = "chapter\(index).xhtml"
            return Spine(resource: resource)
        }
        return book
    }
}
