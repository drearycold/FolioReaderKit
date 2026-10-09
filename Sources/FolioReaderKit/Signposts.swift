//
//  Signposts.swift
//  FolioReaderKit
//
//  Copyright © 2026 FolioReader. All rights reserved.
//

import os.signpost

/// `os_signpost` intervals for profiling book opening and page loads. They cost almost nothing
/// unless a trace is recording. All use the `FolioReaderKit` subsystem, in two categories:
///
/// - `milestones` (Points of Interest, so Instruments shows them by default): `BookOpen` (archive
///   open through the first `reloadData`), `ParseEpub`, `OpenToFirstPage`, and `PageLoad` (web view
///   load request until the page is shown).
/// - `steps` (category `Steps`, in the os_signpost instrument or `log show`), the work inside them,
///   kept out of the host app's Points of Interest because there are several per page: the
///   JavaScript round-trips of the page load chain (`PreprocessJS`, `OverflowJS`, `OverflowCSS`,
///   `RuntimeStyleJS`, `HighlightsJS`, `PaddingJS`), `LayoutWait`, and `Resource`.
///
/// `Resource` runs from the HTTP request until its response is handed to the server, which
/// includes opening the archive and finding the entry. The entry is decompressed afterwards, while
/// the server streams the body, so that time is not included.
///
/// An interval that ends without its work finishing says why in its end message: `replaced` (the
/// cell started another page), `failed`, `terminated` (web content process), `closed`, or `error`.
enum FolioSignpost {
    static let milestones = OSLog(subsystem: "FolioReaderKit", category: .pointsOfInterest)
    static let steps = OSLog(subsystem: "FolioReaderKit", category: "Steps")

    struct Interval {
        let log: OSLog
        let name: StaticString
        let id: OSSignpostID

        func end(_ message: String = "") {
            os_signpost(.end, log: log, name: name, signpostID: id, "%{public}s", message)
        }
    }

    static func begin(_ name: StaticString, _ message: String = "", log: OSLog = steps) -> Interval {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id, "%{public}s", message)
        return Interval(log: log, name: name, id: id)
    }
}
