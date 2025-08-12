//
//  UIImage+icons.swift
//  RecordWebCam
//
//  Created by Jules on 8/12/25.
//

import UIKit

extension UIImage {
    static func recordIcon(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let bounds = CGRect(origin: .zero, size: size)

            // White border
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: bounds)

            // Red inner circle
            let innerBounds = bounds.insetBy(dx: 2, dy: 2)
            UIColor.red.setFill()
            ctx.cgContext.fillEllipse(in: innerBounds)
        }
        return image
    }

    static func stopIcon(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let bounds = CGRect(origin: .zero, size: size)
            let squareSize = size.width / 2.0
            let squareRect = CGRect(x: (size.width - squareSize) / 2.0,
                                    y: (size.height - squareSize) / 2.0,
                                    width: squareSize,
                                    height: squareSize)

            UIColor.red.setFill()
            ctx.cgContext.fill(squareRect)
        }
        return image
    }
}
