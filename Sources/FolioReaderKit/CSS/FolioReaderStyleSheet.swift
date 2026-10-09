//
//  FolioReaderStyleSheet.swift
//  FolioReaderKit
//
//  Copyright © 2026 FolioReader. All rights reserved.
//

import Foundation

/// When a `FolioReaderStyleSheet` is applied to a page.
public enum FolioReaderCSSStage {
    /// Injected once at document end of every page load, before the page is shown.
    case documentBase
    /// Re-applied every time the reader refreshes its runtime style (settings changes, page loads).
    case runtime
}

/// Extra CSS supplied through `FolioReaderConfig.customStyleSheets`.
public struct FolioReaderStyleSheet {
    /// Identifies the sheet; it is injected as `<style id="folio_custom_<id>">`.
    public let id: String
    public let css: String
    public let stage: FolioReaderCSSStage

    public init(id: String, css: String, stage: FolioReaderCSSStage) {
        self.id = id
        self.css = css
        self.stage = stage
    }
}
