//
//  Sharing.swift
//  FolioReaderKit
//
//  Created by 京太郎 on 2021/9/14.
//  Copyright © 2021 FolioReader. All rights reserved.
//

import Foundation
import UIKit

extension FolioReaderCenter {
    /**
     Sharing chapter method.
     */
    @objc func shareChapter(_ sender: UIBarButtonItem) {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        guard let currentPage = currentPage else { return }

        currentPage.webView?.js("getBodyText()") { chapterText in
            guard let chapterText = chapterText else { return }
            // let htmlText = chapterText.replacingOccurrences(of: "[\\n\\r]+", with: "<br />", options: .regularExpression)
            let htmlText = chapterText.split(whereSeparator: \.isNewline).reduce("") { result, substring in
                return result + "<p>\(substring)</p>"
            }
            var subject = self.readerConfig.localizedShareChapterSubject
            var html = ""
            var text = ""
            var bookTitle = ""
            var chapterName = ""
            var authorName = ""
            var shareItems = [AnyObject]()

            // Get book title
            if let title = self.book.title {
                bookTitle = title
                subject += " “\(title)”"
            }

            // Get chapter name
            if let chapter = currentPage.getChapterName() {
                chapterName = chapter
            }

            // Get author name
            if let author = self.book.metadata.creators.first {
                authorName = author.name
            }

            // Sharing html and text
            html = "<html><body>"
            html += "<hr><div>\(htmlText)</div><hr>"
            html += "<center><p style=\"color:gray\">"+self.readerConfig.localizedShareAllExcerptsFrom+"</p>"
            html += "<b>\(bookTitle)</b><br />"
            html += self.readerConfig.localizedShareBy+" <i>\(authorName)</i><br />"
            
            if let bookShareLink = self.readerConfig.localizedShareWebLink {
                html += "<a href=\"\(bookShareLink.absoluteString)\">\(bookShareLink.absoluteString)</a>"
                shareItems.append(bookShareLink as AnyObject)
            }

            html += "</center></body></html>"
            text = "\(chapterName)\n\n“\(chapterText)” \n\n\(bookTitle) \n\(self.readerConfig.localizedShareBy) \(authorName)"

            let act = FolioReaderSharingProvider(subject: subject, text: text, html: html)
//            shareItems.insert(contentsOf: [act, "" as AnyObject], at: 0)
            shareItems.insert(contentsOf: [act], at: 0)

            let activityViewController = UIActivityViewController(activityItems: shareItems, applicationActivities: nil)
            activityViewController.excludedActivityTypes = [.print, .postToVimeo]

            // Pop style on iPad
            if let actv = activityViewController.popoverPresentationController {
                actv.barButtonItem = sender
            }

           self.present(activityViewController, animated: true, completion: nil)
        }
    }

    /**
     Sharing highlight method.
     */
    func shareHighlight(_ string: String, rect: CGRect) {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        var subject = readerConfig.localizedShareHighlightSubject
        var html = ""
        var text = ""
        var bookTitle = ""
        var chapterName = ""
        var authorName = ""
        var shareItems = [AnyObject]()

        // Get book title
        if let title = self.book.title {
            bookTitle = title
            subject += " “\(title)”"
        }

        // Get chapter name
        if let chapter = currentPage?.getChapterName() {
            chapterName = chapter
        }

        // Get author name
        if let author = self.book.metadata.creators.first {
            authorName = author.name
        }

        // Sharing html and text
        html = "<html><body>"
        html += "<br /><hr> <p>\(chapterName)</p>"
        html += "<p>\(string)</p> <hr><br />"
        html += "<center><p style=\"color:gray\">"+readerConfig.localizedShareAllExcerptsFrom+"</p>"
        html += "<b>\(bookTitle)</b><br />"
        html += readerConfig.localizedShareBy+" <i>\(authorName)</i><br />"

        if let bookShareLink = readerConfig.localizedShareWebLink {
            html += "<a href=\"\(bookShareLink.absoluteString)\">\(bookShareLink.absoluteString)</a>"
            shareItems.append(bookShareLink as AnyObject)
        }

        html += "</center></body></html>"
        text = "\(chapterName)\n\n“\(string)” \n\n\(bookTitle) \n\(readerConfig.localizedShareBy) \(authorName)"

        let act = FolioReaderSharingProvider(subject: subject, text: text, html: html)
        //shareItems.insert(contentsOf: [act, "" as AnyObject], at: 0)
        shareItems.insert(contentsOf: [act], at: 0)

        let activityViewController = UIActivityViewController(activityItems: shareItems, applicationActivities: nil)
        activityViewController.excludedActivityTypes = [.print, .postToVimeo]

        // Pop style on iPad
        if let actv = activityViewController.popoverPresentationController {
            // `rect` is in the web view's coordinates (the selection or the share menu).
            actv.sourceView = currentPage?.webView ?? currentPage
            actv.sourceRect = rect
        }

        present(activityViewController, animated: true, completion: nil)
    }
}
