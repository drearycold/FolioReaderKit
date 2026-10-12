//
//  FolioReaderMenu.swift
//  FolioReaderKit
//
//  Created by 京太郎 on 2021/9/22.
//

import Foundation
import UIKit

class FolioReaderMenu: UIViewController, UIGestureRecognizerDelegate {
    public var menuView = UIView()
    
    var readerConfig: FolioReaderConfig
    var folioReader: FolioReader
    
    let segmentFont = UIFont(name: "Avenir-Light", size: 17) ?? .systemFont(ofSize: 17)
    let separaterTag = -9999
    
    init(folioReader: FolioReader, readerConfig: FolioReaderConfig) {
        self.readerConfig = readerConfig
        self.folioReader = folioReader

        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func reloadColors() {
        let backgroundColor = self.readerConfig.themeModeBackground[self.folioReader.themeMode]
        let separatorColor = self.folioReader.isNight(self.readerConfig.nightModeSeparatorColor, self.readerConfig.menuSeparatorColor)
        menuView.backgroundColor = backgroundColor
        menuView.subviews.forEach { subview in
            if subview.tag == separaterTag {
                subview.backgroundColor = separatorColor
            } else {
                subview.backgroundColor = backgroundColor
            }
            if let label = subview as? UILabel,
               label.textColor != .systemRed {
                label.textColor = self.readerConfig.themeModeTextColor[self.folioReader.themeMode]
            }
            if let button = subview as? UIButton {
                button.setTitleColor(self.readerConfig.themeModeTextColor[self.folioReader.themeMode], for: .normal)
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Do any additional setup after loading the view.
        self.view.backgroundColor = UIColor.clear
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        reloadColors()
    }

    /// Lays the rows out for every size the view takes. `viewWillAppear` is too early: the menu
    /// tab bar controller is reused, and its view keeps the size it last had (the old orientation
    /// after a rotation) until the presentation animator sizes it.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        layoutSubviews(frame: view.bounds)
    }

    func layoutSubviews(frame: CGRect) {
        preconditionFailure("This method must be overriden")
    }
}
