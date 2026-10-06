//
//  FolioReaderWebView.swift
//  FolioReaderKit
//
//  Created by Hans Seiffert on 21.09.16.
//  Copyright (c) 2016 Folio Reader. All rights reserved.
//

import WebKit
import FolioEPUBCore
import UIKit

public typealias JSCallback = (String?) ->()

/// The custom WebView used in each page
open class FolioReaderWebView: WKWebView {
    var isColors = false
    var isSharingHighlight = false
    
    var mDictView : UINavigationController?
    
    open var additionalMenuItems = [UIMenuItem]()
    
    fileprivate(set) var cssOverflowProperty = "scroll"

    lazy var highlightManager = WebViewHighlightManager(webView: self)
    lazy var menuManager = WebViewMenuManager(webView: self)

    weak var readerContainer: FolioReaderContainer?

    var readerConfig: FolioReaderConfig {
        guard let readerContainer = readerContainer else { return FolioReaderConfig() }
        return readerContainer.readerConfig
    }

    var book: FRBook {
        guard let readerContainer = readerContainer else { return FRBook() }
        return readerContainer.book
    }

    var folioReader: FolioReader {
        guard let readerContainer = readerContainer else { return FolioReader() }
        return readerContainer.folioReader
    }

    init(frame: CGRect, readerContainer: FolioReaderContainer) {
        self.readerContainer = readerContainer
        
        let configuration = WKWebViewConfiguration()
        configuration.dataDetectorTypes = .link
        if let wkProcessorPool = readerContainer.folioReader.readerCenter?.wkProcessorPool {
            configuration.processPool = wkProcessorPool
        }
        super.init(frame: frame, configuration: configuration)
        FolioReaderScript.bridgeJS.addIfNeeded(to: self)
        FolioReaderScript.readiumCFIJS.addIfNeeded(to: self)

        Self.bundleStyleScript.addIfNeeded(to: self)
        // Font families are rebuilt per web view: fonts registered after the first page still get classes.
        FolioReaderCSSInjector.userScript(
            id: FolioReaderCSSInjector.StyleID.fontFamilies,
            css: FolioReaderCSSBuilder.fontFamilyRules(familyNames: UIFont.familyNames)
        ).addIfNeeded(to: self)
        FolioReaderCSSInjector.userScript(
            id: FolioReaderCSSInjector.StyleID.userFontFaces,
            css: FolioReaderCSSBuilder.userFontFaceRules(descriptors: readerContainer.readerConfig.userFontDescriptors)
        ).addIfNeeded(to: self)
        for sheet in FolioReaderCSSInjector.customSheets(readerContainer.readerConfig.customStyleSheets, stage: .documentBase) {
            FolioReaderCSSInjector.userScript(id: sheet.id, css: sheet.css).addIfNeeded(to: self)
        }
    }

    /// `Style.css` plus all level rules; identical for every web view, so built once.
    private static let bundleStyleScript = FolioReaderCSSInjector.userScript(
        id: FolioReaderCSSInjector.StyleID.bundle,
        css: FolioReaderCSSBuilder.baseStyleSheet()
    )

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UIMenuController

    func superCanPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        return super.canPerformAction(action, withSender: sender)
    }

    open override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        return menuManager.canPerformAction(action, withSender: sender)
    }

    // MARK: - UIMenuController - Actions

    @objc func share(_ sender: Any?) {
        menuManager.share(sender)
    }

    func colors(_ sender: Any?) {
        menuManager.colors(sender)
    }

    func remove(_ sender: Any?) {
        menuManager.remove(sender)
    }

    @objc func highlight(_ sender: Any?) {
        highlightManager.highlight(sender)
    }
    
    @objc func highlightWithNote(_ sender: Any?) {
        highlightManager.highlightWithNote(sender)
    }
    
    func handleHighlightReturn(_ jsonData: Data, withNote: Bool = false, original: FolioReaderHighlight? = nil, completion: ((FolioReaderHighlight?, FolioReaderHighlightError?) -> Void)? = nil) {
        highlightManager.handleHighlightReturn(jsonData, withNote: withNote, original: original, completion: completion)
    }
    
    @objc func updateHighlightNote(_ sender: Any?) {
        highlightManager.updateHighlightNote(sender)
    }

    @objc func define(_ sender: Any?) {
        menuManager.define(sender)
    }

    @objc func lookup(_ sender: Any?) {
        menuManager.lookup(sender)
    }
    
    @objc func reference(_ sender: Any?) {
        menuManager.reference(sender)
    }
    
    @objc func play(_ sender: Any?) {
        menuManager.play(sender)
    }
    
    func setYellow(_ sender: Any?) {
        highlightManager.setYellow(sender)
    }

    func setGreen(_ sender: Any?) {
        highlightManager.setGreen(sender)
    }

    func setBlue(_ sender: Any?) {
        highlightManager.setBlue(sender)
    }

    func setPink(_ sender: Any?) {
        highlightManager.setPink(sender)
    }

    func setUnderline(_ sender: Any?) {
        highlightManager.setUnderline(sender)
    }

    func changeHighlightStyle(_ sender: Any?, style: FolioReaderHighlightStyle) {
        highlightManager.changeHighlightStyle(sender, style: style)
    }

    // MARK: - Create and show menu

    func createMenu(onHighlight: Bool) {
        menuManager.createMenu(onHighlight: onHighlight)
    }
    
    open func setMDictView(mDictView: UINavigationController) {
        self.mDictView = mDictView
    }

    var isMenuVisible: Bool {
        if #available(iOS 16.0, *) {
            return menuManager.isMenuVisible
        } else {
            return UIMenuController.shared.isMenuVisible
        }
    }

    open func setMenuVisible(_ menuVisible: Bool, animated: Bool = true, andRect rect: CGRect = CGRect.zero) {
        menuManager.setMenuVisible(menuVisible, animated: animated, andRect: rect)
    }

    open override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)

        guard #available(iOS 16.0, *) else { return }
        guard readerConfig.useReaderMenuController else { return }

        let actions = menuManager.menuElementsForCurrentState()
        let customMenu = UIMenu(title: "", options: .displayInline, children: actions)
        builder.insertSibling(customMenu, afterMenu: .standardEdit)
    }
    
    // MARK: - Java Script Bridge
    
    open func js(_ script: String) async -> String? {
        if let result = try? await evaluateJavaScript(script) {
            let output = "\(result)"
            if output.isEmpty {
                return nil
            } else {
                return output
            }
        } else {
            return nil
        }
    }
    
    open func js(_ script: String, completion: JSCallback? = nil) {
        evaluateJavaScript(script) { result, error in
            let output: String?
            if let result = result {
                let stringResult = "\(result)"
                if stringResult.isEmpty {
                    output = nil
                } else {
                    output = stringResult
                }
            } else {
                output = nil
            }
            if  let nsError = error as NSError?,
                let url = nsError.userInfo["WKJavaScriptExceptionSourceURL"] as? NSURL,
                url.absoluteString == "undefined"
            {
                // skip debugPrint - html hasn't loaded yet
            } else if let error = error {
                debugPrint("evaluateJavaScript(\(script)) returned an error:", error, "url:", self.url?.absoluteString ?? "NOURL")
            }
            completion?(output)
        }
    }
    
    // MARK: WebView
    
    func clearTextSelection() {
        // Forces text selection clearing
        // @NOTE: this doesn't seem to always work
        
        self.isUserInteractionEnabled = false
        self.isUserInteractionEnabled = true
    }
    
    func setupScrollDirection() {
        switch self.readerConfig.scrollDirection {
        case .vertical, .defaultVertical, .horizontalWithScrollContent:
            scrollView.isPagingEnabled = false
            cssOverflowProperty = "scroll"
            scrollView.bounces = true
            break
        case .horizontalWithPagedContent:
            scrollView.isPagingEnabled = true
            cssOverflowProperty = "-webkit-paged-x"
            scrollView.bounces = false
            break
        }
    }
}
