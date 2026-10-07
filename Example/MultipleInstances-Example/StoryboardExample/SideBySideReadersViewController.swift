//
//  SideBySideReadersViewController.swift
//  MultipleInstance-Example
//
//  Copyright © 2026 FolioReader. All rights reserved.
//

import UIKit
import FolioReaderKit
import ReadiumGCDWebServer

/// Two readers embedded side by side in the storyboard.
///
/// Each embed segue creates its `FolioReaderContainer` through an `@IBSegueAction`, so the reader
/// gets an injected web server like one created in code. With one server per reader, the second
/// reader falls back to a free port while the first one holds the preferred one.
class SideBySideReadersViewController: UIViewController {

    @IBSegueAction func makeBookOneReader(_ coder: NSCoder) -> FolioReaderContainer? {
        makeReader(coder, identifier: "STORYBOARD_READER_ONE", scrollDirection: .horizontalWithScrollContent)
    }

    @IBSegueAction func makeBookTwoReader(_ coder: NSCoder) -> FolioReaderContainer? {
        makeReader(coder, identifier: "STORYBOARD_READER_TWO", scrollDirection: .vertical)
    }

    private func makeReader(_ coder: NSCoder, identifier: String, scrollDirection: FolioReaderScrollDirection) -> FolioReaderContainer? {
        let config = FolioReaderConfig(withIdentifier: identifier)
        config.scrollDirection = scrollDirection
        config.shouldHideNavigationOnTap = false

        // Print the chapter ID if one was clicked
        // A chapter in "The Silver Chair" looks like this "<section class="chapter" title="Chapter I" epub:type="chapter" id="id70364673704880">"
        // To know if a user tapped on a chapter we can listen to events on the class "chapter" and receive the id value
        let listener = ClassBasedOnClickListener(schemeName: "chaptertapped", querySelector: ".chapter", attributeName: "id", onClickAction: { (attributeContent: String?, touchPointRelativeToWebView: CGPoint?) in
            print("chapter with id: " + (attributeContent ?? "-") + " clicked")
        })
        config.classBasedOnClickListeners.append(listener)

        guard let bookPath = Bundle.main.path(forResource: "The Silver Chair", ofType: "epub") else { return nil }
        return FolioReaderContainer(
            coder: coder,
            config: config,
            folioReader: FolioReader(),
            epubPath: bookPath,
            webServer: ReadiumGCDWebServer()
        )
    }
}
