//
//  CSSInjectionSnapshotTests.swift
//  FolioReaderKitTests
//
//  Copyright © 2026 FolioReader. All rights reserved.
//

import XCTest
@testable import FolioReaderKit

/// Guards the stylesheet injected into every page by `FolioReaderScript.cssInjection`.
///
/// `levelStyleRules` is compared against `__Snapshots__/CSSInjectionSnapshotTests/levelStyleRules.css`.
/// To re-record after an intended change, delete that file or run with
/// `TEST_RUNNER_FOLIO_RECORD_SNAPSHOTS=1 xcodebuild test ...`, then review the diff in git.
class CSSInjectionSnapshotTests: XCTestCase {

    func testLevelStyleRulesSnapshot() {
        assertSnapshot(FolioReaderScript.levelStyleRules.joined(separator: "\n") + "\n", named: "levelStyleRules.css")
    }

    func testBundleStyleSheetIsStyleCSSFollowedByLevelRules() throws {
        let styleURL = try XCTUnwrap(Bundle.frameworkBundle().url(forResource: "Style", withExtension: "css"))
        let styleCSS = try String(contentsOf: styleURL)

        XCTAssertEqual(
            FolioReaderScript.bundleStyleSheet,
            ([styleCSS] + FolioReaderScript.levelStyleRules).joined(separator: "\n")
        )
        XCTAssertEqual(
            FolioReaderScript.cssInjection.source,
            FolioReaderScript.cssInjectionSource(for: FolioReaderScript.bundleStyleSheet, id: "folio_bundle_style")
        )
    }

    func testBundleStyleSheetIsSafeInsideSingleQuotedJSString() {
        // cssInjectionSource embeds the CSS as `style.innerHTML = '...'` without escaping,
        // so a quote or backslash anywhere in it would silently break the whole injection.
        let styleSheet = FolioReaderScript.bundleStyleSheet
        XCTAssertFalse(styleSheet.contains("'"), "Use double quotes in Style.css and generated rules")
        XCTAssertFalse(styleSheet.contains("\\"), "Backslashes are not escaped by cssInjectionSource")
    }

    // MARK: - Snapshot helper

    /// Compares `actual` with `__Snapshots__/<TestClass>/<name>` next to this file, recording it
    /// when the file is missing or `FOLIO_RECORD_SNAPSHOTS` is set. Simulator test runs can write
    /// to the source tree because they share the host file system.
    private func assertSnapshot(_ actual: String, named name: String, file: StaticString = #filePath, line: UInt = #line) {
        let snapshotURL = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__", isDirectory: true)
            .appendingPathComponent("\(type(of: self))", isDirectory: true)
            .appendingPathComponent(name)

        let isRecording = ProcessInfo.processInfo.environment["FOLIO_RECORD_SNAPSHOTS"] != nil
        guard !isRecording, let expected = try? String(contentsOf: snapshotURL, encoding: .utf8) else {
            do {
                try FileManager.default.createDirectory(at: snapshotURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try actual.write(to: snapshotURL, atomically: true, encoding: .utf8)
                XCTFail("Recorded snapshot at \(snapshotURL.path); re-run without recording to verify.", file: file, line: line)
            } catch {
                XCTFail("Could not record snapshot at \(snapshotURL.path): \(error)", file: file, line: line)
            }
            return
        }

        guard actual != expected else { return }

        let actualLines = actual.components(separatedBy: "\n")
        let expectedLines = expected.components(separatedBy: "\n")
        let commonCount = min(actualLines.count, expectedLines.count)
        let firstDiff = (0..<commonCount).first { actualLines[$0] != expectedLines[$0] } ?? commonCount
        func lineAt(_ lines: [String], _ index: Int) -> String {
            lines.indices.contains(index) ? lines[index] : "<end of file>"
        }

        let attachment = XCTAttachment(string: actual)
        attachment.name = "actual-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTFail("""
            Snapshot \(name) differs (expected \(expectedLines.count) lines, got \(actualLines.count)). First difference at line \(firstDiff + 1):
              expected: \(lineAt(expectedLines, firstDiff))
              actual:   \(lineAt(actualLines, firstDiff))
            If the change is intended, re-record with TEST_RUNNER_FOLIO_RECORD_SNAPSHOTS=1.
            """, file: file, line: line)
    }
}
