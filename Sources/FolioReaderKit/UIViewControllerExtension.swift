//
//  UIViewControllerExtension.swift
//  FolioReaderKit
//
//  Created by Antigravity on 2026/07/06.
//

import UIKit

internal extension UIViewController {
    
    func setCloseButton(withConfiguration readerConfig: FolioReaderConfig,
                        folioReader: FolioReader? = nil,
                        action: Selector? = nil) {
        let color = folioReader?.preferences.navTextColor() ?? readerConfig.tintColor
        let closeImage = UIImage(readerImageNamed: "icon-navbar-close")?.imageTintColor(color)?.withRenderingMode(.alwaysOriginal)
        let closeAction = action ?? #selector(dismiss as () -> Void)
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(image: closeImage, style: .plain, target: self, action: closeAction)
    }
    
    @objc func dismiss() {
        self.dismiss(nil)
    }
    
    func dismiss(_ completion: (() -> Void)?) {
        DispatchQueue.main.async {
            self.dismiss(animated: true, completion: {
                completion?()
            })
        }
    }
    
    // MARK: - NavigationBar
    
    func setTransparentNavigation() {
        let navBar = self.navigationController?.navigationBar
        navBar?.setBackgroundImage(UIImage(), for: UIBarMetrics.default)
        navBar?.isHidden = true
        navBar?.isTranslucent = true
    }
    
    func setTranslucentNavigation(_ translucent: Bool = true, color: UIColor, tintColor: UIColor = UIColor.white, titleColor: UIColor = UIColor.black, andFont font: UIFont = UIFont.systemFont(ofSize: 17)) {
        let navBar = self.navigationController?.navigationBar

        let appearance = UINavigationBarAppearance()
        if translucent {
            appearance.configureWithDefaultBackground()
            appearance.backgroundColor = color.withAlphaComponent(0.5)
        } else {
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = color
        }
        appearance.titleTextAttributes = [.foregroundColor: titleColor, .font: font]

        navBar?.standardAppearance = appearance
        navBar?.scrollEdgeAppearance = appearance
        navBar?.compactAppearance = appearance

        navBar?.isHidden = false
        navBar?.isTranslucent = translucent
        navBar?.tintColor = tintColor
    }
}

extension UIView {
    func findHairlineImageView() -> UIImageView? {
        if self.isKind(of: UIImageView.classForCoder()) && self.bounds.height <= 1 {
            return self as? UIImageView
        }
        for subView in self.subviews {
            if let imageView = subView.findHairlineImageView() {
                return imageView
            }
        }
        return nil
    }
}
