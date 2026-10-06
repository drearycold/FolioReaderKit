//
//  Signposts.swift
//  FolioReaderKit
//
//  Copyright © 2026 FolioReader. All rights reserved.
//

import os.signpost

/// `os_signpost` intervals in the Points of Interest category, for profiling book opening and page
/// loads in Instruments (Logging or Points of Interest). They cost almost nothing unless a trace is
/// recording.
///
/// Intervals: `BookOpen` (archive open through first `reloadData`), `ParseEpub`, `OpenToFirstPage`,
/// `PageLoad` (web view load request until the page is shown, including the chain's fixed delays),
/// the JavaScript round-trips inside that chain (`PreprocessJS`, `OverflowJS`, `OverflowCSS`,
/// `RuntimeStyleJS`, `HighlightsJS`, `PaddingJS`), and `Resource` (HTTP request until the response
/// is ready).
enum FolioSignpost {
    static let log = OSLog(subsystem: "FolioReaderKit", category: .pointsOfInterest)

    struct Interval {
        let name: StaticString
        let id: OSSignpostID

        func end(_ message: String = "") {
            os_signpost(.end, log: FolioSignpost.log, name: name, signpostID: id, "%{public}s", message)
        }
    }

    static func begin(_ name: StaticString, _ message: String = "") -> Interval {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id, "%{public}s", message)
        return Interval(name: name, id: id)
    }
}
