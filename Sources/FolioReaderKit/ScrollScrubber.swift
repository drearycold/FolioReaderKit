//
//  ScrollScrubber.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 7/14/16.
//  Copyright © 2016 FolioReader. All rights reserved.
//

import UIKit

func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
    switch (lhs, rhs) {
    case let (l?, r?):
        return l < r
    case (nil, _?):
        return true
    default:
        return false
    }
}

func > <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
    switch (lhs, rhs) {
    case let (l?, r?):
        return l > r
    default:
        return rhs < lhs
    }
}

enum ScrollType: Int {
    case page
    // `chapter` is only for the collection view if vertical with horizontal content is used
    case chapter
}

enum ScrollDirection: Int {
    case none
    case right
    case left
    case up
    case down

    init() {
        self = .none
    }
}

class ScrollScrubber: NSObject, UIScrollViewDelegate {
    weak var delegate: FolioReaderCenter?
    var showSpeed = 0.6
    var hideSpeed = 0.6
    var hideDelay = 1.0

    var visible = false
    var usingSlider = false
    let slider = UISlider()
    var hideTimer: Timer!
    var scrollStart: CGFloat!
    var scrollDelta: CGFloat!
    var scrollDeltaTimer: Timer!

    fileprivate weak var readerContainer: FolioReaderContainer?

    fileprivate var readerConfig: FolioReaderConfig {
        guard let readerContainer = readerContainer else { return FolioReaderConfig() }
        return readerContainer.readerConfig
    }

    fileprivate var folioReader: FolioReader {
        guard let readerContainer = readerContainer else { return FolioReader() }
        return readerContainer.folioReader
    }

    var frame: CGRect {
        didSet {
            self.slider.frame = frame
            self.slider.maximumValue = Float(frame.height)
            if frame.height > frame.width {
                slider.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi / 2))
            } else {
                slider.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi))
            }
        }
    }

    init(frame:CGRect, withReaderContainer readerContainer: FolioReaderContainer) {
        self.frame = frame
        self.readerContainer = readerContainer

        super.init()

        slider.layer.anchorPoint = CGPoint(x: 0, y: 0)
        slider.alpha = 0
        self.reloadColors()

        slider.addTarget(self, action: #selector(ScrollScrubber.sliderChange(_:)), for: .valueChanged)
        slider.addTarget(self, action: #selector(ScrollScrubber.sliderTouchDown(_:)), for: .touchDown)
        slider.addTarget(self, action: #selector(ScrollScrubber.sliderTouchUp(_:)), for: .touchUpInside)
        slider.addTarget(self, action: #selector(ScrollScrubber.sliderTouchUp(_:)), for: .touchUpOutside)
        
        if #available(iOS 14.0, *),
           #available(macCatalyst 14.0, *) {
            if self.readerContainer?.traitCollection.userInterfaceIdiom == .mac {
                return
            }
        }
        // less obtrusive knob and fixes jump: http://stackoverflow.com/a/22301039/484780
        let thumbImg = UIImage(readerImageNamed: "knob")
        let thumbImgColor = thumbImg?.imageTintColor(readerConfig.tintColor)?.withRenderingMode(.alwaysOriginal)
        slider.setThumbImage(thumbImgColor, for: UIControl.State())
        slider.setThumbImage(thumbImgColor, for: .selected)
        slider.setThumbImage(thumbImgColor, for: .highlighted)
    }

    func reloadColors() {
        if #available(iOS 14.0, *),
           #available(macCatalyst 14.0, *),
           self.readerContainer?.traitCollection.userInterfaceIdiom == .mac {
                return
        }
        slider.minimumTrackTintColor = readerConfig.tintColor
        slider.maximumTrackTintColor = folioReader.isNight(readerConfig.nightModeSeparatorColor, readerConfig.menuSeparatorColor)
    }

    // MARK: - slider events

    @objc func sliderTouchDown(_ slider:UISlider) {
        usingSlider = true
        show()
    }

    @objc func sliderTouchUp(_ slider:UISlider) {
        usingSlider = false
        hideAfterDelay()
    }

    @objc func sliderChange(_ slider:UISlider) {
        guard let currentPage = delegate?.currentPage, let scrollView = currentPage.webView?.scrollView else { return }
        let movePosition = (height() * CGFloat(slider.value))
        let offset = currentPage.byWritingMode(
            readerConfig.isDirection(CGPoint(x: 0, y: movePosition), CGPoint(x: movePosition, y: 0), CGPoint(x: 0, y: movePosition)),
            CGPoint(x: scrollView.contentSize.width - scrollView.frame.width - movePosition, y: 0)
        )
        scrollView.setContentOffset(offset, animated: false)
    }

    // MARK: - show / hide

    func show() {
        cancelHide()

        visible = true

        if slider.alpha <= 0 {
            UIView.animate(withDuration: showSpeed, animations: {

                self.slider.alpha = 1

            }, completion: { (Bool) -> Void in
                self.hideAfterDelay()
            })
        } else {
            slider.alpha = 1
            if usingSlider == false {
                hideAfterDelay()
            }
        }
    }


    @objc func hide() {
        visible = false
        resetScrollDelta()
        UIView.animate(withDuration: hideSpeed, animations: {
            self.slider.alpha = 0
        })
    }

    func hideAfterDelay() {
        cancelHide()
        hideTimer = Timer.scheduledTimer(timeInterval: hideDelay, target: self, selector: #selector(ScrollScrubber.hide), userInfo: nil, repeats: false)
    }

    func cancelHide() {

        if hideTimer != nil {
            hideTimer.invalidate()
            hideTimer = nil
        }

        if visible == false {
            slider.layer.removeAllAnimations()
        }

        visible = true
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {

        if scrollDeltaTimer != nil {
            scrollDeltaTimer.invalidate()
            scrollDeltaTimer = nil
        }

        if scrollStart == nil {
            scrollStart = scrollView.contentOffset.forDirection(withConfiguration: readerConfig)
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard readerConfig.scrollDirection != .horitonzalWithPagedContent else { return }

        if visible && usingSlider == false {
            setSliderVal()
        }

        if (slider.alpha > 0) {
            self.show()
        } else if let currentPage = delegate?.currentPage,
                  scrollStart != nil {
            scrollDelta = currentPage.byWritingMode(
                scrollView.contentOffset.forDirection(withConfiguration: readerConfig) - scrollStart,
                scrollStart - scrollView.contentOffset.x)
            guard let pageHeight = folioReader.readerCenter?.pageHeight,
                (scrollDeltaTimer == nil && scrollDelta > (pageHeight * 0.2 ) || (scrollDelta * -1) > (pageHeight * 0.2)) else {
                    return
            }

            self.show()
            self.resetScrollDelta()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        resetScrollDelta()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        scrollDeltaTimer = Timer(timeInterval:0.5, target: self, selector: #selector(ScrollScrubber.resetScrollDelta), userInfo: nil, repeats: false)
        RunLoop.current.add(scrollDeltaTimer, forMode: RunLoop.Mode.common)
    }

    @objc func resetScrollDelta() {
        if scrollDeltaTimer != nil {
            scrollDeltaTimer.invalidate()
            scrollDeltaTimer = nil
        }

        scrollStart = delegate?.currentPage?.byWritingMode(
            (scrollView()?.contentOffset.forDirection(withConfiguration: readerConfig) ?? 0),
            scrollView()?.contentOffset.x ?? 0) ?? 0
        
        scrollDelta = 0
    }

    func setSliderVal() {
        let value = Float(Int(scrollTop() / height() * CGFloat(slider.maximumValue)))
        guard value != slider.value
        else {
            return
        }
        slider.setValue(value, animated: true)
    }

    // MARK: - utility methods

    fileprivate func scrollView() -> UIScrollView? {
        return delegate?.currentPage?.webView?.scrollView
    }

    fileprivate func height() -> CGFloat {
        guard let currentPage = delegate?.currentPage,
            let pageHeight = folioReader.readerCenter?.pageHeight,
            let pageWidth = folioReader.readerCenter?.pageWidth,
            let webView = currentPage.webView else {
                return 0
        }

        return currentPage.byWritingMode(
            webView.scrollView.contentSize.height - pageHeight + 44,
            webView.scrollView.contentSize.width - pageWidth
        )
    }
    
    fileprivate func scrollTop() -> CGFloat {
        guard let currentPage = delegate?.currentPage, let webView = currentPage.webView else {
            return 0
        }
        return currentPage.byWritingMode(
            webView.scrollView.contentOffset.forDirection(withConfiguration: readerConfig),
            webView.scrollView.contentSize.width - webView.scrollView.contentOffset.x - webView.scrollView.frame.width
        )
        
    }
}
