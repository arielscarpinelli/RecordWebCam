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
            let lineWidth: CGFloat = 2

            // White border
            let borderRect = bounds.insetBy(dx: lineWidth, dy: lineWidth)
            ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
            ctx.cgContext.setLineWidth(lineWidth)
            ctx.cgContext.strokeEllipse(in: borderRect)

            // Red inner circle
            let gap: CGFloat = lineWidth
            let redCircleRect = borderRect.insetBy(dx: gap, dy: gap)
            ctx.cgContext.setFillColor(UIColor.red.cgColor)
            ctx.cgContext.fillEllipse(in: redCircleRect)
        }
        return image
    }

    static func stopIcon(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let bounds = CGRect(origin: .zero, size: size)
            let lineWidth: CGFloat = 2

            // White border
            let borderRect = bounds.insetBy(dx: lineWidth, dy: lineWidth)
            ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
            ctx.cgContext.setLineWidth(lineWidth)
            ctx.cgContext.strokeEllipse(in: borderRect)

            // Red inner square
            let gap: CGFloat = lineWidth
            let innerBounds = borderRect.insetBy(dx: gap, dy: gap)
            let squareSize = innerBounds.width * 0.65
            let squareRect = CGRect(x: innerBounds.origin.x + (innerBounds.width - squareSize) / 2,
                                    y: innerBounds.origin.y + (innerBounds.height - squareSize) / 2,
                                    width: squareSize,
                                    height: squareSize)

            ctx.cgContext.setFillColor(UIColor.red.cgColor)
            ctx.cgContext.fill(squareRect)
        }
        return image
    }
}
