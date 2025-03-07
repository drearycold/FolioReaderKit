//
//  FolioReaderPageIndicator.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 10/09/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit

class FolioReaderPageIndicator: UIView {
    var pagesLabel: UILabel!
    var minutesLabel: UILabel!
    var infoLabel: UILabel!
    
    fileprivate var readerConfig: FolioReaderConfig
    fileprivate var folioReader: FolioReader

    init(frame: CGRect, readerConfig: FolioReaderConfig, folioReader: FolioReader) {
        self.readerConfig = readerConfig
        self.folioReader = folioReader

        super.init(frame: frame)

        //let color = self.folioReader.isNight(self.readerConfig.nightModeBackground, UIColor.white)
        let color = self.readerConfig.themeModeBackground[self.folioReader.themeMode]
        backgroundColor = color
        layer.shadowColor = color.cgColor
        layer.shadowOffset = CGSize(width: 0, height: -6)
        layer.shadowOpacity = 1
        layer.shadowRadius = 4
        layer.shadowPath = UIBezierPath(rect: bounds).cgPath
        layer.rasterizationScale = UIScreen.main.scale
        layer.shouldRasterize = true

        pagesLabel = UILabel(frame: CGRect.zero)
        pagesLabel.font = UIFont(name: "Avenir-Light", size: 10)!
        pagesLabel.textAlignment = NSTextAlignment.right
        addSubview(pagesLabel)

        minutesLabel = UILabel(frame: CGRect.zero)
        minutesLabel.font = UIFont(name: "Avenir-Light", size: 10)!
        minutesLabel.textAlignment = NSTextAlignment.right
        //        minutesLabel.alpha = 0
        addSubview(minutesLabel)
        
        infoLabel = UILabel(frame: CGRect.zero)
        infoLabel.font = UIFont(name: "Avenir-Light", size: 12)!
        infoLabel.textAlignment = .center
        addSubview(infoLabel)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("storyboards are incompatible with truth and beauty")
    }

    func reloadView(updateShadow: Bool) {
        minutesLabel.sizeToFit()
        pagesLabel.sizeToFit()
        
        let fullW = pagesLabel.frame.width + minutesLabel.frame.width
        minutesLabel.frame.origin = CGPoint(x: frame.width/2-fullW/2, y: 2)
        pagesLabel.frame.origin = CGPoint(x: minutesLabel.frame.origin.x+minutesLabel.frame.width, y: 2)
        
        #if DEBUG
        infoLabel.frame = CGRect(origin: .init(x: 10, y: 22), size: .init(width: frame.width, height: 18))
        #endif
        
        if updateShadow {
            layer.shadowPath = UIBezierPath(rect: bounds).cgPath
            self.reloadColors()
        }
    }

    func reloadColors() {
        //let color = self.folioReader.isNight(self.readerConfig.nightModeBackground, UIColor.white)
        let color = self.readerConfig.themeModeBackground[self.folioReader.themeMode]
        backgroundColor = color

        // Animate the shadow color change
        let animation = CABasicAnimation(keyPath: "shadowColor")
        let currentColor = UIColor(cgColor: layer.shadowColor!)
        animation.fromValue = currentColor.cgColor
        animation.toValue = color.cgColor
        animation.fillMode = CAMediaTimingFillMode.forwards
        animation.isRemovedOnCompletion = false
        animation.duration = 0.6
        animation.delegate = self
        animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut)
        layer.add(animation, forKey: "shadowColor")

        minutesLabel.textColor = self.folioReader.isNight(UIColor(white: 1, alpha: 0.3), UIColor(white: 0, alpha: 0.6))
        pagesLabel.textColor = self.folioReader.isNight(UIColor(white: 1, alpha: 0.6), UIColor(white: 0, alpha: 0.9))
        infoLabel.textColor = self.folioReader.isNight(UIColor(white: 1, alpha: 0.6), UIColor(white: 0, alpha: 0.9))
    }

    func reloadViewWithPage(_ page: Int) {
        guard let readerPage = self.folioReader.readerCenter?.currentPage,
              let totalPages = readerPage.totalPages,
              let totalMinutes = readerPage.totalMinutes else { return }
        
        var pagesRemaining = self.folioReader.needsRTLChange ? totalPages-(totalPages-page+1) : totalPages-page
        if pagesRemaining >= totalPages {
            pagesRemaining = totalPages - 1
        }
        if pagesRemaining < 0 {
            pagesRemaining = 0
        }

        var pagesLabelText = readerPage.currentChapterName ?? ""
        if pagesRemaining == 1 {
            pagesLabelText += " · " + self.readerConfig.localizedReaderOnePageLeft
        } else {
            pagesLabelText += " · \(pagesRemaining) " + self.readerConfig.localizedReaderManyPagesLeft
        }
        
        let pagePercent = readerPage.getPageProgress() 
        let bookPercent = readerPage.getBookProgress()
        
        pagesLabelText += " · \(String(format: "%.2f", pagePercent))% \(String(format: "%.2f", bookPercent))%"
        
        pagesLabel.text = pagesLabelText

        let minutesRemaining: Int
        if totalPages == 0 {
            minutesRemaining = 0
        } else {
            minutesRemaining = Int(ceil(CGFloat((pagesRemaining * totalMinutes)/totalPages)))
        }
        if minutesRemaining > 1 {
            minutesLabel.text = "\(minutesRemaining) " + self.readerConfig.localizedReaderManyMinutes+" ·"
        } else if minutesRemaining == 1 {
            minutesLabel.text = self.readerConfig.localizedReaderOneMinute+" ·"
        } else {
            minutesLabel.text = self.readerConfig.localizedReaderLessThanOneMinute+" ·"
        }
        
        reloadView(updateShadow: false)
    }
}

extension FolioReaderPageIndicator: CAAnimationDelegate {
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        // Set the shadow color to the final value of the animation is done
        if let keyPath = anim.value(forKeyPath: "keyPath") as? String , keyPath == "shadowColor" {
            //let color = self.folioReader.isNight(self.readerConfig.nightModeBackground, UIColor.white)
            let color = self.readerConfig.themeModeBackground[self.folioReader.themeMode]
            layer.shadowColor = color.cgColor
        }
    }
}
