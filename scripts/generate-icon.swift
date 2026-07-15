#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
  fputs("Usage: generate-icon.swift <output.png>\n", stderr)
  exit(2)
}

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let outer = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 220, yRadius: 220)
NSColor(calibratedWhite: 0.09, alpha: 1).setFill()
outer.fill()

let frameColor = NSColor(calibratedWhite: 0.96, alpha: 1)
frameColor.setStroke()
let crop = NSBezierPath()
crop.lineWidth = 54
crop.lineCapStyle = .round
let inset: CGFloat = 242
let arm: CGFloat = 170

crop.move(to: NSPoint(x: inset, y: inset + arm))
crop.line(to: NSPoint(x: inset, y: inset))
crop.line(to: NSPoint(x: inset + arm, y: inset))
crop.move(to: NSPoint(x: size.width - inset - arm, y: inset))
crop.line(to: NSPoint(x: size.width - inset, y: inset))
crop.line(to: NSPoint(x: size.width - inset, y: inset + arm))
crop.move(to: NSPoint(x: inset, y: size.height - inset - arm))
crop.line(to: NSPoint(x: inset, y: size.height - inset))
crop.line(to: NSPoint(x: inset + arm, y: size.height - inset))
crop.move(to: NSPoint(x: size.width - inset - arm, y: size.height - inset))
crop.line(to: NSPoint(x: size.width - inset, y: size.height - inset))
crop.line(to: NSPoint(x: size.width - inset, y: size.height - inset - arm))
crop.stroke()

let dotRect = NSRect(x: 407, y: 407, width: 210, height: 210)
NSColor.systemRed.setFill()
NSBezierPath(ovalIn: dotRect).fill()

image.unlockFocus()

guard
  let tiff = image.tiffRepresentation,
  let bitmap = NSBitmapImageRep(data: tiff),
  let png = bitmap.representation(using: .png, properties: [:])
else {
  fputs("Unable to render icon\n", stderr)
  exit(1)
}

try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
