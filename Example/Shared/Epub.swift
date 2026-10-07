//
//  Epub.swift
//  Example
//
//  Created by Kevin Delord on 18/05/2017.
//  Copyright © 2017 FolioReader. All rights reserved.
//

import Foundation
import FolioReaderKit

enum Epub: Int {
    case bookOne = 0
    case bookTwo

    var name: String {
        switch self {
        case .bookOne:      return "Population" // standard eBook
        case .bookTwo:      return "The Silver Chair" // audio-eBook
        }
    }

    var shouldHideNavigationOnTap: Bool {
        switch self {
        case .bookOne:      return false
        case .bookTwo:      return true
        }
    }

    var scrollDirection: FolioReaderScrollDirection {
        switch self {
        case .bookOne:      return .horizontalWithPagedContent
        case .bookTwo:      return .horizontalWithPagedContent
        }
    }

    /// For profiling large books without bundling them: launch with `-FolioExampleBook <file.epub>`
    /// after copying that file into the app's Documents folder, and the first cover opens it.
    var bookPath: String? {
        if self == .bookOne,
           let override = UserDefaults.standard.string(forKey: "FolioExampleBook"),
           let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let path = documents.appendingPathComponent(override).path
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return Bundle.main.path(forResource: self.name, ofType: "epub")
    }

    var readerIdentifier: String {
        switch self {
        case .bookOne:      return "READER_ONE"
        case .bookTwo:      return "READER_TWO"
        }
    }
}
