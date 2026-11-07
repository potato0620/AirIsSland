import AppKit

@main struct AppIconTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }

    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func player(_ name: String, rgba: [UInt8]) throws -> URL {
            let app = root.appendingPathComponent(name + ".app")
            let resources = app.appendingPathComponent("Contents/Resources")
            try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
            let info = ["CFBundleIdentifier": "local.airisland.icon-test." + name,
                        "CFBundlePackageType": "APPL", "CFBundleIconFile": "Player.png"]
            let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            for pixel in 0..<(32 * 32) { for channel in 0..<4 { rep.bitmapData![pixel * 4 + channel] = rgba[channel] } }
            try rep.representation(using: .png, properties: [:])!.write(to: resources.appendingPathComponent("Player.png"))
            return app
        }
        func pixel(_ image: NSImage?) -> NSColor {
            guard let data = image?.tiffRepresentation, let rep = NSBitmapImageRep(data: data),
                  let pixel = rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)?.usingColorSpace(.deviceRGB)
            else { fatalError("Missing decoded player icon") }
            return pixel
        }
        let red = try player("Red", rgba: [255, 0, 0, 255])
        let blue = try player("Blue", rgba: [0, 0, 255, 255])
        check(pixel(applicationIcon(in: red)).redComponent > 0.9, "Declared app icon was replaced by a system placeholder")
        check(pixel(applicationIcon(in: blue)).blueComponent > 0.9, "Changing source reused the previous player icon")
        let resource = red.appendingPathComponent("Contents/Resources/Player.png")
        let validData = try Data(contentsOf: resource)
        try Data().write(to: resource)
        check(applicationIcon(in: red) == nil, "A failed icon load exposed a generic application badge")
        try validData.write(to: resource)
        check(pixel(applicationIcon(in: red)).redComponent > 0.9, "A failed load prevented recovery on the next lookup")
        check(AppIconAsNSImage(for: "") == nil, "An empty source displayed an unrelated app")
        check(AppIconAsNSImage(for: "local.airisland.missing." + UUID().uuidString) == nil,
              "An unknown source displayed a generic placeholder")
        print("PASS: native player resources, source changes, failed-load recovery and no generic badge for missing sources")
    }
}
