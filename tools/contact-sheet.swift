// A contact sheet of a captured store set, one row per locale and one column per shot, for the
// one-minute look before anything is uploaded and as the record of what was. Runs on the Mac:
//
//     swift tools/contact-sheet.swift _scratch/store-shots/iphone69 docs/releases/1.2.7/evidence/store-shots-iphone69.png
//
// No Pillow on this Mac, so the sheet is drawn with AppKit.
import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: contact-sheet.swift <device folder> <output png>\n".utf8))
    exit(2)
}
let root = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
let names = ["01-home", "02-rooms", "03-defect-editor", "04-canton-overlay", "05-review", "06-signature", "07-record-cover", "08-photo-annex"]
let locales = ["en-US", "fr-FR", "de-DE", "it", "rm"].filter { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }
let tile = CGSize(width: 200, height: 420)
let gutter: CGFloat = 10
let labelWidth: CGFloat = 80
let width = labelWidth + CGFloat(names.count) * (tile.width + gutter) + gutter
let height = CGFloat(locales.count) * (tile.height + gutter) + gutter + 24
let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()
NSColor.white.setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()
let font = NSFont.systemFont(ofSize: 14)
let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
for (column, name) in names.enumerated() {
    let x = labelWidth + gutter + CGFloat(column) * (tile.width + gutter)
    NSString(string: name).draw(at: NSPoint(x: x, y: height - 20), withAttributes: attributes)
}
for (row, locale) in locales.enumerated() {
    let y = height - 24 - gutter - CGFloat(row + 1) * (tile.height + gutter) + gutter
    NSString(string: locale).draw(at: NSPoint(x: gutter, y: y + tile.height / 2), withAttributes: attributes)
    let tag = locale.split(separator: "-").first.map(String.init) ?? locale
    for (column, name) in names.enumerated() {
        let file = root.appendingPathComponent(locale).appendingPathComponent("\(tag)-\(name).png")
        guard let shot = NSImage(contentsOf: file) else { continue }
        let scale = min(tile.width / shot.size.width, tile.height / shot.size.height)
        let drawn = NSSize(width: shot.size.width * scale, height: shot.size.height * scale)
        let x = labelWidth + gutter + CGFloat(column) * (tile.width + gutter) + (tile.width - drawn.width) / 2
        shot.draw(in: NSRect(x: x, y: y, width: drawn.width, height: drawn.height), from: .zero, operation: .copy, fraction: 1)
    }
}
image.unlockFocus()
guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("could not encode the sheet\n".utf8))
    exit(1)
}
try png.write(to: output)
print("\(locales.count) rows, \(names.count) columns: \(output.path)")
