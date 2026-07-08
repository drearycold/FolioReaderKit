//
//  FolioReaderConfigTests.swift
//  FolioReaderKitTests
//
//  Created by DeepMind Antigravity on 7/7/26.
//  Copyright © 2026 FolioReader. All rights reserved.
//

import XCTest
@testable import FolioReaderKit

class FolioReaderConfigTests: XCTestCase {
    
    func testFolioReaderScrollDirectionCollectionViewDirection() {
        XCTAssertEqual(FolioReaderScrollDirection.vertical.collectionViewScrollDirection(isWritingRTL: false), .vertical)
        XCTAssertEqual(FolioReaderScrollDirection.defaultVertical.collectionViewScrollDirection(isWritingRTL: false), .vertical)
        XCTAssertEqual(FolioReaderScrollDirection.horizontalWithPagedContent.collectionViewScrollDirection(isWritingRTL: false), .horizontal)
        XCTAssertEqual(FolioReaderScrollDirection.horizontalWithScrollContent.collectionViewScrollDirection(isWritingRTL: false), .horizontal)
    }
    
    func testIsDirectionShorthand() {
        let config = FolioReaderConfig()
        
        // 1. Default direction should be vertical (or defaultVertical)
        config.scrollDirection = .vertical
        XCTAssertEqual(config.isDirection("vert", "page", "scroll"), "vert")
        
        config.scrollDirection = .defaultVertical
        XCTAssertEqual(config.isDirection("vert", "page", "scroll"), "vert")
        
        // 2. Horizontal with paged content
        config.scrollDirection = .horizontalWithPagedContent
        XCTAssertEqual(config.isDirection("vert", "page", "scroll"), "page")
        
        // 3. Horizontal with scroll content
        config.scrollDirection = .horizontalWithScrollContent
        XCTAssertEqual(config.isDirection("vert", "page", "scroll"), "scroll")
    }
    
    func testConfigDefaults() {
        let config = FolioReaderConfig()
        XCTAssertEqual(config.scrollDirection, .horizontalWithScrollContent)
        XCTAssertFalse(config.shouldHideNavigationOnTap)
        XCTAssertTrue(config.canChangeFontStyle)
        XCTAssertTrue(config.allowSharing)
        XCTAssertTrue(config.showCloseButton)
    }
}
