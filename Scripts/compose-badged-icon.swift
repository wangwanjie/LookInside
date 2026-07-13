import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 4 else {
    fputs("usage: compose-badged-icon.swift <base.png> <badge.png> <output.png>\n", stderr)
    exit(2)
}

func loadImage(_ path: String) -> CGImage? {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let source = CGImageSourceCreateWithURL(url, nil) else {
        return nil
    }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

let basePath = args[1]
let badgePath = args[2]
let outputPath = args[3]

guard let baseImage = loadImage(basePath) else {
    fputs("failed to read base image\n", stderr)
    exit(1)
}

guard let badgeImage = loadImage(badgePath) else {
    fputs("failed to read badge image\n", stderr)
    exit(1)
}

let width = baseImage.width
let height = baseImage.height
let minSide = min(width, height)
let badgeSide = Int((Double(minSide) * 0.31).rounded())
let margin = Int((Double(minSide) * 0.055).rounded())
let borderWidth = max(6, Int((Double(badgeSide) * 0.035).rounded()))
let cornerRadius = Double(badgeSide) * 0.18

let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
guard let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: width * 4,
    space: colorSpace,
    bitmapInfo: bitmapInfo
) else {
    fputs("failed to create output context\n", stderr)
    exit(1)
}

let fullRect = CGRect(x: 0, y: 0, width: width, height: height)
context.clear(fullRect)
context.interpolationQuality = .high
context.draw(baseImage, in: fullRect)

let badgeRect = CGRect(
    x: width - badgeSide - margin,
    y: margin,
    width: badgeSide,
    height: badgeSide
)
let badgePathRounded = CGPath(
    roundedRect: badgeRect,
    cornerWidth: cornerRadius,
    cornerHeight: cornerRadius,
    transform: nil
)

context.saveGState()
context.addPath(badgePathRounded)
context.clip()
context.draw(badgeImage, in: badgeRect)
context.restoreGState()

context.addPath(badgePathRounded)
context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
context.setLineWidth(CGFloat(borderWidth))
context.strokePath()

guard let outputImage = context.makeImage() else {
    fputs("failed to create output image\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: outputPath) as CFURL
guard let destination = CGImageDestinationCreateWithURL(outputURL, UTType.png.identifier as CFString, 1, nil) else {
    fputs("failed to create png destination\n", stderr)
    exit(1)
}

CGImageDestinationAddImage(destination, outputImage, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("failed to write output png\n", stderr)
    exit(1)
}

print("wrote \(outputPath) (\(width)x\(height), badge \(badgeSide)x\(badgeSide), margin \(margin))")
