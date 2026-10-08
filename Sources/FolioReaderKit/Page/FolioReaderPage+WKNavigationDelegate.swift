//
//  FolioReaderPage+WKNavigationDelegate.swift
//  FolioReaderKit
//

import UIKit
import WebKit
import SafariServices

extension FolioReaderPage {
    // MARK: - WKNavigation Delegate

    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard webView is FolioReaderWebView else {
            return
        }

        delegate?.pageWillLoad?(self)
    }
    
    public func webView(_ webView: WKWebView, didFail: WKNavigation!, withError: Error) {
        endLoadInterval(ifLoading: didFail)
        self.readerContainer?.alert(message: "LOAD FAIL WITH ERROR \(withError.localizedDescription)")
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        endLoadInterval(ifLoading: navigation)
    }

    /// iOS reclaims web content processes, mostly while the app is in the background. WebKit only
    /// reloads the page itself when this method isn't implemented, and then from the old URL: if the
    /// server had moved to another port, `handlePolicy` didn't recognise it and sent it to Safari.
    /// Reload from the server's port at the recorded position instead, now if the app is active, else
    /// when it becomes active (`FolioReaderContainer`); the server is suspended in the background.
    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loadInterval?.end("terminated")
        loadInterval = nil
        needsReload = true
        // Nothing may record or save a position from the dead page meanwhile.
        layoutAdapting = .initializing
        guard UIApplication.shared.applicationState == .active else { return }
        readerContainer?.restartResourceServer()
        folioReader.readerCenter?.reloadPages(all: false)
    }

    /// The reader's own resource server, on any port: pages, styles, fonts.
    static func isReaderServerURL(_ url: URL) -> Bool {
        url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(url.host ?? "")
    }

    /// Ends `loadInterval` if `navigation` is the load it measures. Starting another load cancels
    /// the previous one, and that cancellation must not end the new load's interval.
    private func endLoadInterval(ifLoading navigation: WKNavigation?) {
        guard let navigation = navigation, navigation === loadNavigation else { return }
        loadInterval?.end("failed")
        loadInterval = nil
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let webView = webView as? FolioReaderWebView else {
            return
        }
        let pageNumber = self.pageNumber
        
        print("\(#function) bridgeFinished pageNumber=\(String(describing: pageNumber))")
        var preprocessor = ""
        if folioReader.doClearClass {
            preprocessor.append("removeBodyClass();tweakStyleOnly();")
        }
        if folioReader.doWrapPara {
            preprocessor.append("removeOuterTable();reParagraph();removePSpace();")
        }
        
        preprocessor.append("document.body.style.minHeight = null;")
        
        self.layoutAdapting = .structure
        let preprocessInterval = FolioSignpost.begin("PreprocessJS", "page \(pageNumber)")
        self.webView?.js(preprocessor) {_ in
            preprocessInterval.end()
            guard self.pageNumber == pageNumber else { FolioLogger.log("bridgeFinished pageNumberMisMatch \(pageNumber) vs \(self.pageNumber)"); return }

            FolioLogger.log("bridgeFinished pageNumber=\(String(describing: self.pageNumber)) size=\(String(describing: self.book.spine.spineReferences[self.pageNumber-1].resource.size))")
            
            self.updateOverflowStyle(delay: 0.2) {
                guard self.pageNumber == pageNumber else { FolioLogger.log("bridgeFinished pageNumberMisMatch updateOverflowStyle \(pageNumber) vs \(self.pageNumber)"); return }
                FolioLogger.log("bridgeFinished updateOverflowStyle pageNumber=\(pageNumber)")

                if self.writingMode == "vertical-rl" {
                    self.setNeedsLayout()       //resize webViewFrame
                }
                
                self.updateRuntimeStyle(delay: 0.2) {
                    guard self.pageNumber == pageNumber else { FolioLogger.log("bridgeFinished pageNumberMisMatch updateRuntimeStyle \(pageNumber) vs \(self.pageNumber)"); return }

                    FolioLogger.log("bridgeFinished updateRuntimeStyle pageNumber=\(pageNumber)")
                    
                    self.injectHighlights() {
                        guard self.pageNumber == pageNumber else { FolioLogger.log("bridgeFinished pageNumberMisMatch injectHighlights \(pageNumber) vs \(self.pageNumber)"); return }
                        FolioLogger.log("bridgeFinished injectHighlights pageNumber=\(pageNumber)")

                        self.updatePageInfo() {
                            guard self.pageNumber == pageNumber else { FolioLogger.log("bridgeFinished pageNumberMisMatch updatePageInfo \(pageNumber) vs \(self.pageNumber)"); return }
                            FolioLogger.log("bridgeFinished updatePageInfo pageNumber=\(pageNumber)")

                            self.updateStyleBackgroundPadding(delay: 0.2, tryShrinking: false) {
                                FolioLogger.log("bridgeFinished updateStyleBackgroundPadding pageNumber=\(pageNumber)")
                                
                                guard self.pageNumber == pageNumber else { FolioLogger.log("bridgeFinished pageNumberMisMatch beforeShow \(pageNumber) vs \(self.pageNumber)"); return }
                                
                                self.layoutAdapting = nil
                                webView.isHidden = false
                                
                                self.loadInterval?.end("page \(pageNumber)")
                                self.loadInterval = nil
                                self.loadNavigation = nil
                                self.delegate?.pageDidLoad?(self)
                            }
                        }
                    }
                }
            }
        }
    
        // Add the custom class based onClick listener
        self.setupClassBasedOnClickListeners()

        refreshPageMode()

        if self.readerConfig.enableTTS && !self.book.hasAudio {
            webView.js("wrappingSentencesWithinPTags()")

            if let audioPlayer = self.folioReader.readerAudioPlayer, (audioPlayer.isPlaying() == true) {
                audioPlayer.readCurrentSentence()
            }
        }

        UIView.animate(withDuration: 0.2, animations: {webView.alpha = 1}, completion: { finished in
            webView.isColors = false
            self.webView?.createMenu(onHighlight: false)
        })
        
        let overlayColor = readerConfig.mediaOverlayColor ?? .yellow
        let colors = "\"\(overlayColor.hexString(false))\", \"\(overlayColor.highlightColor().hexString(false))\""
        webView.js("setMediaOverlayStyleColors(\(colors))")
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let handledAction = handlePolicy(for: navigationAction)
        let policy: WKNavigationActionPolicy = handledAction ? .allow : .cancel
        decisionHandler(policy)
    }
    
    private func handlePolicy(for navigationAction: WKNavigationAction) -> Bool {
        let request = navigationAction.request
        
        guard
            let webView = webView,
            let scheme = request.url?.scheme else {
                return true
        }

        guard let url = request.url else { return false }

        if scheme == "highlight" || scheme == "highlight-with-note" {
            folioReader.readerCenter?.invalidatePendingBarReveal()

            guard let decoded = url.absoluteString.removingPercentEncoding else { return false }
            let index = decoded.index(decoded.startIndex, offsetBy: 12)
            let rect = NSCoder.cgRect(for: String(decoded[index...]))

            webView.createMenu(onHighlight: true)
            webView.setMenuVisible(true, andRect: rect)
            menuIsVisible = true

            return false
        } else if scheme == "play-audio" {
            guard let decoded = url.absoluteString.removingPercentEncoding else { return false }
            let index = decoded.index(decoded.startIndex, offsetBy: 13)
            let playID = String(decoded[index...])
            let chapter = self.getChapter()
            let href = chapter?.href ?? ""
            self.folioReader.readerAudioPlayer?.playAudio(href, fragmentID: playID)

            return false
        } else if let referer = request.value(forHTTPHeaderField: "Referer"),
                  let refererURL = URL(string: referer),
                  refererURL.host == "localhost",
                  refererURL.port == Int(readerContainer?.pagePort ?? 0),
                  url.scheme == "http",
                  url.host == "localhost",
                  url.port == Int(readerContainer?.pagePort ?? 0),
                  let anchorFromURL = url.fragment {
            self.webView?.js("getClickAnchorOffset('\(anchorFromURL)')") { offset in
                // The preview covers the window, so place it in the window's coordinates.
                let snippetVC = FolioReaderAnchorPreview(
                    self.folioReader,
                    url,
                    CGFloat(truncating: NumberFormatter().number(from: offset ?? "0") ?? 0),
                    self.convert(self.anchorBoundsFrame(), to: nil)
                )

                snippetVC.anchorLabel.text = url.absoluteString

                snippetVC.modalPresentationStyle = .overFullScreen
                snippetVC.modalTransitionStyle = .crossDissolve
                
                self.folioReader.readerCenter?.present(snippetVC, animated: true, completion: nil)
            }
            return false
        } else if scheme == "file" || (url.scheme == "http" && url.host == "localhost" && (url.port ?? 0) == Int(readerContainer?.pagePort ?? 0)) {
            
            if navigationAction.navigationType == .linkActivated {
                self.pushNavigateWebViewScrollPositions()
            }
            
            // Handle internal url
            if !url.pathExtension.isEmpty {
                let pathComponent = (self.book.opfResource?.href as NSString?)?.deletingLastPathComponent
                guard let base = ((pathComponent == nil || pathComponent?.isEmpty == true) ? self.book.name : pathComponent)?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
                    return true
                }

                let path = url.path
                let splitedPath = path.components(separatedBy: base)

                // Return to avoid crash
                if (splitedPath.count <= 1 || splitedPath[1].isEmpty) {
                    return true
                }

                let href = splitedPath[1].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let hrefPage = (self.book.resources.findByHref(href)?.spineIndices.first ?? 0) + 1

                if (hrefPage == pageNumber) {
                    // Handle internal #anchor
                    guard let anchorFromURL = url.fragment else { return true }
                    self.webView?.js("getClickAnchorOffset('\(anchorFromURL)')") { offset in
                        print("getClickAnchorOffset offset=\(offset ?? "0")")
                        self.handleAnchor(anchorFromURL, offsetInWindow: CGFloat(truncating: NumberFormatter().number(from: offset ?? "0") ?? 0), avoidBeginningAnchors: false, animated: false)
                        
                    }
                } else {
                    // self.folioReader.readerCenter?.tempFragment = anchorFromURL
                    self.folioReader.readerCenter?.currentWebViewScrollPositions.removeValue(forKey: hrefPage - 1)
                    if let anchorFromURL = url.fragment {
                        self.webView?.js("getClickAnchorOffset('\(anchorFromURL)')") { offset in
                            print("getClickAnchorOffset offset=\(offset ?? "0")")
                            self.folioReader.readerCenter?.changePageWith(href: href, animated: true) {
                                DispatchQueue.main.asyncAfter(delay: 0.2) {
                                    guard self.folioReader.readerCenter?.currentPageNumber == hrefPage else { return }
                                    self.folioReader.readerCenter?.currentPage?.waitForLayoutFinish {
                                        self.folioReader.readerCenter?.currentPage?.handleAnchor(anchorFromURL, offsetInWindow: CGFloat(truncating: NumberFormatter().number(from: offset ?? "0") ?? 0), avoidBeginningAnchors: false, animated: true)
                                    }
                                }
                            }
                        }
                    } else if navigationAction.navigationType != .other {
                        self.folioReader.readerCenter?.changePageWith(href: href, animated: true) {
                            DispatchQueue.main.asyncAfter(delay: 0.2) {
                                guard self.folioReader.readerCenter?.currentPageNumber == hrefPage else { return }
                                guard let currentPage = self.folioReader.readerCenter?.currentPage else { return }
                                currentPage.waitForLayoutFinish {
                                    currentPage.scrollPageToChapterStart()
                                }
                            }
                        }
                    } else {    //triggered by datasource loading url
                        return true
                    }
                }
                return false
            }

            // Handle internal #anchor
            if let anchorFromURL = url.fragment {
                self.webView?.js("getClickAnchorOffset('\(anchorFromURL)')") { offset in
                    print("getClickAnchorOffset offset=\(offset ?? "0")")
                    self.handleAnchor(anchorFromURL, offsetInWindow: CGFloat(truncating: NumberFormatter().number(from: offset ?? "0") ?? 0), avoidBeginningAnchors: false, animated: false)
                }
                return false
            } else {
                return true
            }
        } else if Self.isReaderServerURL(url) {
            // The reader's server on a port it no longer uses. Never hand it to Safari, which can't
            // reach it: load the chapter again from the current port.
            needsReload = true
            DispatchQueue.main.async {
                self.folioReader.readerCenter?.reloadPages(all: false)
            }
            return false
        } else if scheme == "mailto" {
            print("Email")
            return true
        } else if url.absoluteString != "about:blank" && scheme.contains("http") && navigationAction.navigationType == .linkActivated {
            let safariVC = SFSafariViewController(url: url)
            safariVC.view.tintColor = self.readerConfig.tintColor
            self.folioReader.readerCenter?.present(safariVC, animated: true, completion: nil)
            return false
        } else {
            // Check if the url is a custom class based onClick listerner
            var isClassBasedOnClickListenerScheme = false
            for listener in self.readerConfig.classBasedOnClickListeners {

                if scheme == listener.schemeName,
                    let absoluteURLString = request.url?.absoluteString,
                    let range = absoluteURLString.range(of: "/clientX=") {
                    let baseURL = String(absoluteURLString[..<range.lowerBound])
                    let positionString = String(absoluteURLString[range.lowerBound...])
                    if let point = getEventTouchPoint(fromPositionParameterString: positionString) {
                        let attributeContentString = (baseURL.replacingOccurrences(of: "\(scheme)://", with: "").removingPercentEncoding)
                        // Call the on click action block
                        listener.onClickAction(attributeContentString, point)
                        // Mark the scheme as class based click listener scheme
                        isClassBasedOnClickListenerScheme = true
                    }
                }
            }

            if isClassBasedOnClickListenerScheme == false {
                // Try to open the url with the system if it wasn't a custom class based click listener
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url)
                    return false
                }
            } else {
                return false
            }
        }

        return true
    }

    fileprivate func getEventTouchPoint(fromPositionParameterString positionParameterString: String) -> CGPoint? {
        // Remove the parameter names: "/clientX=188&clientY=292" -> "188&292"
        var positionParameterString = positionParameterString.replacingOccurrences(of: "/clientX=", with: "")
        positionParameterString = positionParameterString.replacingOccurrences(of: "clientY=", with: "")
        // Separate both position values into an array: "188&292" -> [188],[292]
        let positionStringValues = positionParameterString.components(separatedBy: "&")
        // Multiply the raw positions with the screen scale and return them as CGPoint
        if
            positionStringValues.count == 2,
            let xPos = Int(positionStringValues[0]),
            let yPos = Int(positionStringValues[1]) {
            return CGPoint(x: xPos, y: yPos)
        }
        return nil
    }

    // MARK: - Class based click listener
    
    fileprivate func setupClassBasedOnClickListeners() {
        for listener in self.readerConfig.classBasedOnClickListeners {
            self.webView?.js("addClassBasedOnClickListener(\"\(listener.schemeName)\", \"\(listener.querySelector)\", \"\(listener.attributeName)\", \"\(listener.selectAll)\")")
        }
    }
}
