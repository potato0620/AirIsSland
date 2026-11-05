//
//  SettingsWindowController.swift
//  AirIsland
//
//  Created by Alexander on 2025-06-14.
//

import AppKit
import SwiftUI
import Defaults

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    private let navigation = SettingsNavigation()
    private var navigationHeader: NSHostingView<SettingsNavigationHeader>?
    
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        super.init(window: window)
        
        setupWindow()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    private func setupWindow() {
        guard let window = window else { return }
        
        window.minSize = NSSize(width: 760, height: 600)
        window.title = String(localized: "AirIsland Settings")
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        // Navigation is a native titlebar accessory aligned with the detail column.
        // Content stays inside contentLayoutRect instead of drawing under the toolbar.
        let toolbar = NSToolbar(identifier: "AirIslandSettingsTitlebar")
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.isMovableByWindowBackground = true
        
        // Make it behave like a regular app window with proper Spaces support
        window.collectionBehavior = [.managed, .participatesInCycle, .fullScreenAuxiliary]
        
        // Ensure proper window behavior
        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = false
        
        // Configure window to be a standard document-style window
        window.isRestorable = true
        window.identifier = NSUserInterfaceItemIdentifier("AirIslandSettingsWindow")
        
        // Create the SwiftUI content
        let settingsView = SettingsView(navigation: navigation)
        let hostingView = NSHostingView(rootView: settingsView)
        window.contentView = hostingView

        let header = NSHostingView(rootView: SettingsNavigationHeader(navigation: navigation))
        header.sizingOptions = []
        header.frame = NSRect(x: 0, y: 0,
                              width: window.frame.width - SettingsView.sidebarWidth,
                              height: SettingsView.headerHeight)
        navigationHeader = header
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .right
        accessory.view = header
        window.addTitlebarAccessoryViewController(accessory)
        
        // Handle window closing
        window.delegate = self
    }
    
    func showWindow() {
        // Set app to regular mode first
        NSApp.setActivationPolicy(.regular)
        
        // If window is already visible, bring it to front properly
        if window?.isVisible == true {
            NSApp.activate(ignoringOtherApps: true)
            window?.orderFrontRegardless()
            window?.makeKeyAndOrderFront(nil)
            return
        }
        
        // Show the window with proper ordering
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        window?.center()
        
        // Activate the app and ensure window gets focus
        NSApp.activate(ignoringOtherApps: true)
        
        // Force window to front after activation
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }
    
    override func close() {
        super.close()
        relinquishFocus()
    }
    
    private func relinquishFocus() {
        window?.orderOut(nil)
        
        // Set app back to accessory mode immediately
        NSApp.setActivationPolicy(.accessory)
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) {
        guard let window, let navigationHeader else { return }
        navigationHeader.setFrameSize(NSSize(
            width: max(0, window.frame.width - SettingsView.sidebarWidth),
            height: navigationHeader.frame.height))
    }

    func windowWillClose(_ notification: Notification) {
        relinquishFocus()
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        // Ensure app is in regular mode when window becomes key
        NSApp.setActivationPolicy(.regular)
    }
    
}
