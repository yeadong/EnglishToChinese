//
//  UIImage.swift
//  MindSurf
//
//  Created by 陈亚东 on 2025/5/2.
//

import UIKit

extension UIImage {
    static func transparentWhite1x1() -> UIImage {
        let size = CGSize(width: 1, height: 1)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        UIColor.white.withAlphaComponent(0.0).setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return image
    }
}
