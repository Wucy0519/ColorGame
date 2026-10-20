import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size, flipped: false) { rect in
    let card = NSBezierPath(roundedRect: rect.insetBy(dx: 72, dy: 72), xRadius: 210, yRadius: 210)
    NSColor(srgbRed: 0.075, green: 0.078, blue: 0.094, alpha: 1).setFill()
    card.fill()

    let tile: CGFloat = 248
    let gap: CGFloat = 36
    let side = tile * 2 + gap
    let originX = (1024 - side) / 2
    let originY = (1024 - side) / 2
    let same = NSColor(srgbRed: 0.286, green: 0.545, blue: 0.608, alpha: 1)
    let odd = NSColor(srgbRed: 0.925, green: 0.573, blue: 0.314, alpha: 1)
    for row in 0..<2 {
        for column in 0..<2 {
            let color = (row == 1 && column == 1) ? odd : same
            let tileRect = NSRect(
                x: originX + CGFloat(column) * (tile + gap),
                y: originY + CGFloat(row) * (tile + gap),
                width: tile,
                height: tile
            )
            color.setFill()
            NSBezierPath(roundedRect: tileRect, xRadius: 52, yRadius: 52).fill()
        }
    }
    return true
}

guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("无法生成图标\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: output))
