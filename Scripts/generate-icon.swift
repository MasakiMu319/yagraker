#!/usr/bin/env swift

import AppKit
import Foundation

func renderIcon(source: NSImage, pixelSize: Int, destination: URL) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "YagrakerIcon", code: 1)
    }

    bitmap.size = NSSize(width: pixelSize, height: pixelSize)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    defer { NSGraphicsContext.restoreGraphicsState() }

    let context = NSGraphicsContext.current!.cgContext
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    NSColor.clear.setFill()
    let bounds = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
    bounds.fill()
    source.draw(
        in: bounds,
        from: NSRect(origin: .zero, size: source.size),
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high]
    )

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "YagrakerIcon", code: 2)
    }
    try png.write(to: destination)
}

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: generate-icon.swift SOURCE.svg OUTPUT.icns\n".utf8))
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard let source = NSImage(contentsOf: sourceURL) else {
    FileHandle.standardError.write(Data("unable to load icon source: \(sourceURL.path)\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let fileManager = FileManager.default
let temporary = fileManager.temporaryDirectory
    .appendingPathComponent("Yagraker-\(UUID().uuidString).iconset", isDirectory: true)
try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: temporary) }

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]
for (name, size) in variants {
    try renderIcon(
        source: source,
        pixelSize: size,
        destination: temporary.appendingPathComponent(name)
    )
}

try fileManager.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", temporary.path, "-o", output.path]
try process.run()
process.waitUntilExit()
if process.terminationStatus != 0 {
    throw NSError(domain: "YagrakerIcon", code: Int(process.terminationStatus))
}
