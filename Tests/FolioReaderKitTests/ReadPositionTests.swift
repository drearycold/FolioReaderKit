import UIKit
import XCTest
@testable import FolioReaderKit

class ReadPositionTests: XCTestCase {
    
    class MockFolioReaderDelegate: NSObject, FolioReaderDelegate {
        let positionProvider = MockReadPositionProvider()
        
        func folioReaderReadPositionProvider(_ folioReader: FolioReader) -> FolioReaderReadPositionProvider {
            return positionProvider
        }
    }
    
    func testCentralizedSaveLogicClearsPrecedence() {
        let folioReader = FolioReader()
        let delegate = MockFolioReaderDelegate()
        folioReader.delegate = delegate
        
        let bookId = "testBook"
        let p1 = FolioReaderReadPosition(deviceId: "d1", structuralStyle: .bundle, positionTrackingStyle: .linear, structuralRootPageNumber: 1, pageNumber: 1, cfi: "cfi1")
        p1.takePrecedence = true
        
        let p2 = FolioReaderReadPosition(deviceId: "d1", structuralStyle: .bundle, positionTrackingStyle: .linear, structuralRootPageNumber: 1, pageNumber: 2, cfi: "cfi2")
        p2.takePrecedence = true
        
        // 1. Save p1 with precedence
        folioReader.save(readPosition: p1, for: bookId)
        
        let expectation1 = XCTestExpectation(description: "Async save p1")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { expectation1.fulfill() }
        wait(for: [expectation1], timeout: 1.0)
        
        XCTAssertTrue(p1.takePrecedence)
        
        // 2. Save p2 with precedence. It should clear p1's precedence.
        folioReader.save(readPosition: p2, for: bookId)
        
        let expectation2 = XCTestExpectation(description: "Async save p2")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { expectation2.fulfill() }
        wait(for: [expectation2], timeout: 1.0)
        
        XCTAssertFalse(p1.takePrecedence, "p1's precedence should be cleared")
        XCTAssertTrue(p2.takePrecedence, "p2 should maintain its precedence")
        
        let allPositions = delegate.positionProvider.folioReaderReadPosition(folioReader, allByBookId: bookId)
        XCTAssertEqual(allPositions.count, 2)
        XCTAssertEqual(allPositions.filter { $0.takePrecedence }.count, 1)
    }

    /// Rapid saves (scrolling, then the app resigning active) must apply in order: the last saved
    /// position is the only one left with precedence.
    func testRapidSavesKeepOnlyTheLastPositionWithPrecedence() {
        let folioReader = FolioReader()
        let delegate = MockFolioReaderDelegate()
        folioReader.delegate = delegate
        let bookId = "rapidBook"

        var saved = [FolioReaderReadPosition]()
        for page in 1...200 {
            let position = FolioReaderReadPosition(deviceId: "d1", structuralStyle: .bundle, positionTrackingStyle: .linear, structuralRootPageNumber: 1, pageNumber: page, cfi: "cfi\(page)")
            position.takePrecedence = true
            saved.append(position)
            folioReader.save(readPosition: position, for: bookId)
        }

        let drained = XCTestExpectation(description: "saves applied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { drained.fulfill() }
        wait(for: [drained], timeout: 3.0)

        let withPrecedence = delegate.positionProvider.folioReaderReadPosition(folioReader, allByBookId: bookId).filter { $0.takePrecedence }
        XCTAssertEqual(withPrecedence.count, 1, "Exactly one position keeps precedence")
        XCTAssertEqual(withPrecedence.first?.pageNumber, 200, "The last saved position wins")
    }

    func testRestorableCFIRejectsChapterStartFallbacks() {
        XCTAssertTrue(FolioReaderCenter.isRestorableCFI("epubcfi(/6/4[chap01]!/4/2/1:12)", pageNumber: 3))
        XCTAssertFalse(FolioReaderCenter.isRestorableCFI("epubcfi(/6/2)", pageNumber: 3), "Chapter start of page 3")
        XCTAssertFalse(FolioReaderCenter.isRestorableCFI("epubcfi(/2/2)", pageNumber: 3), "Book start on a later page")
        XCTAssertTrue(FolioReaderCenter.isRestorableCFI("epubcfi(/2/4/1:0)", pageNumber: 1))
        XCTAssertFalse(FolioReaderCenter.isRestorableCFI("", pageNumber: 1))
    }

    /// A pinned position can be the provider's own opening record; saving it again kept that record's
    /// precedence, date and device. It is saved as this device's position now.
    func testRecordedAgainIsThisDevicesPositionNow() {
        let opened = FolioReaderReadPosition(deviceId: "another device", structuralStyle: .bundle, positionTrackingStyle: .level1, structuralRootPageNumber: 2, pageNumber: 3, cfi: "epubcfi(/6/6/4/2/1:5)")
        opened.takePrecedence = true
        opened.epoch = Date(timeIntervalSince1970: 0)
        opened.snippet = "snippet"
        opened.chapterProgress = 0.4

        let saved = opened.recordedAgain()
        XCTAssertFalse(saved === opened)
        XCTAssertEqual(saved.deviceId, UIDevice.current.name)
        XCTAssertFalse(saved.takePrecedence)
        XCTAssertGreaterThan(saved.epoch, Date(timeIntervalSinceNow: -60))
        XCTAssertEqual(saved.cfi, opened.cfi)
        XCTAssertEqual(saved.pageNumber, opened.pageNumber)
        XCTAssertEqual(saved.structuralStyle, opened.structuralStyle)
        XCTAssertEqual(saved.positionTrackingStyle, opened.positionTrackingStyle)
        XCTAssertEqual(saved.structuralRootPageNumber, opened.structuralRootPageNumber)
        XCTAssertEqual(saved.snippet, opened.snippet)
        XCTAssertEqual(saved.chapterProgress, opened.chapterProgress)
        XCTAssertTrue(opened.takePrecedence, "The provider's record is left alone")
    }
}
