//
//  AppIcons.swift
//  AirIsland
//
//  Created by Harsh Vardhan  Goswami  on 16/08/24.
//

import AppKit
import SwiftUI

func AppIcon(for bundleID: String) -> Image? {
    AppIconAsNSImage(for: bundleID).map { Image(nsImage: $0) }
}

func AppIconAsNSImage(for bundleID: String) -> NSImage? {
    guard !bundleID.isEmpty else { return nil }
    let workspace = NSWorkspace.shared
    // Prefer the actual running installation over a stale Launch Services path.
    guard let appURL = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .first(where: { $0.bundleURL != nil })?.bundleURL
        ?? workspace.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
    return applicationIcon(in: appURL)
}

func applicationIcon(in appURL: URL) -> NSImage? {
    guard let bundle = Bundle(url: appURL) else { return nil }
    // A declared icon file remains available while Icon Services is still
    // preparing its cache. Do not store the generic application placeholder.
    if let name = bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
       !name.isEmpty,
       let url = bundle.url(forResource: name, withExtension: nil)
            ?? bundle.url(forResource: name, withExtension: "icns") {
        guard let image = NSImage(contentsOf: url), image.isValid else { return nil }
        image.size = NSSize(width: 256, height: 256)
        return image
    }
    let workspace = NSWorkspace.shared
    let image = workspace.icon(forFile: appURL.path)
    guard image.isValid, let data = image.tiffRepresentation,
          data != workspace.icon(for: .applicationBundle).tiffRepresentation,
          let copy = image.copy() as? NSImage else { return nil }
    copy.size = NSSize(width: 256, height: 256)
    return copy
}

