//
//  Highlight+Helper.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 06/07/16.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit

/**
 HighlightStyle type, default is .Yellow.
 */
@objc public enum HighlightStyle: Int {
    case yellow
    case green
    case blue
    case pink
    case underline

    public init () {
        // Default style is `.yellow`
        self = .yellow
    }

    /**
     Return HighlightStyle for CSS class.
     */
    public static func styleForClass(_ className: String) -> HighlightStyle {
        switch className {
        case "highlight-yellow": return .yellow
        case "highlight-green": return .green
        case "highlight-blue": return .blue
        case "highlight-pink": return .pink
        case "highlight-underline": return .underline
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "pink": return .pink
        case "underline": return .underline
        default: return .yellow
        }
    }

    /**
     Return CSS class for HighlightStyle.
     */
    public static func classForStyle(_ style: Int) -> String {

        let enumStyle = (HighlightStyle(rawValue: style) ?? HighlightStyle())
        switch enumStyle {
        case .yellow: return "highlight-yellow"
        case .green: return "highlight-green"
        case .blue: return "highlight-blue"
        case .pink: return "highlight-pink"
        case .underline: return "highlight-underline"
        }
    }

    /// Color components for the style
    ///
    /// - Returns: Tuple of all color compnonents.
    private func colorComponents() -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        switch self {
        case .yellow: return (red: 255, green: 235, blue: 107, alpha: 0.9)
        case .green: return (red: 192, green: 237, blue: 114, alpha: 0.9)
        case .blue: return (red: 173, green: 216, blue: 255, alpha: 0.9)
        case .pink: return (red: 255, green: 176, blue: 202, alpha: 0.9)
        case .underline: return (red: 240, green: 40, blue: 20, alpha: 0.6)
        }
    }

    /**
     Return CSS class for HighlightStyle.
     */
    public static func colorForStyle(_ style: Int, nightMode: Bool = false) -> UIColor {
        let enumStyle = (HighlightStyle(rawValue: style) ?? HighlightStyle())
        let colors = enumStyle.colorComponents()
        return UIColor(red: colors.red/255, green: colors.green/255, blue: colors.blue/255, alpha: (nightMode ? colors.alpha : 1))
    }
}

/// :nodoc:
public typealias Completion = (_ error: NSError?) -> ()

