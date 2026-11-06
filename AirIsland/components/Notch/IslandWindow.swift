//
//  IslandWindow.swift
//  AirIsland
//
//  Created by Alexander on 2025-10-20.
//

import Cocoa
import SkyLightWindow
import Defaults
import Combine
import SwiftUI

/// Mounted only during explicit editing, on the rendered island surface.
/// Mouse-down observation never consumes the click destined for another view/app.
struct OutsideEditingClickMonitor: NSViewRepresentable {
    let action: () -> Void

    final class CaptureView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.setAccessibilityElement(false)
        context.coordinator.install(on: view)
        return view
    }

    func updateNSView(_ view: CaptureView, context: Context) {
        context.coordinator.action = action
    }

    static func dismantleNSView(_ view: CaptureView, coordinator: Coordinator) { coordinator.remove() }

    @MainActor final class Coordinator {
        var action: () -> Void
        private weak var view: NSView?
        private var localMonitor: Any?
        private var globalMonitor: Any?
        private var generation = UUID()
        private var dismissalQueued = false
        var isMonitoring: Bool { localMonitor != nil || globalMonitor != nil }

        init(action: @escaping () -> Void) { self.action = action }

        func install(on view: NSView) {
            self.view = view
            let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                self?.handleLocalEvent(event) ?? event
            }
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
                self?.receive(screenPoint: NSEvent.mouseLocation)
            }
        }

        func screenFrame() -> NSRect? {
            guard let view, let window = view.window, window.isVisible else { return nil }
            return window.convertToScreen(view.convert(view.bounds, to: nil))
        }

        func handleLocalEvent(_ event: NSEvent) -> NSEvent? {
            let point = event.window.map { $0.convertPoint(toScreen: event.locationInWindow) } ?? NSEvent.mouseLocation
            receive(screenPoint: point)
            return event
        }

        func receive(screenPoint: NSPoint) {
            guard isMonitoring, !dismissalQueued, let frame = screenFrame(),
                  !frame.contains(screenPoint) else { return }
            dismissalQueued = true
            let ticket = generation
            // Leave AppKit's event delivery and SwiftUI's current update first.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == ticket, self.isMonitoring,
                      self.screenFrame() != nil else { return }
                self.dismissalQueued = false
                self.action()
            }
        }

        func remove() {
            generation = UUID()
            if let localMonitor { NSEvent.removeMonitor(localMonitor) }
            if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
            localMonitor = nil
            globalMonitor = nil
            dismissalQueued = false
            view = nil
            action = {}
        }
    }
}

extension SkyLightOperator {
    func undelegateWindow(_ window: NSWindow) {
        typealias F_SLSRemoveWindowsFromSpaces = @convention(c) (Int32, CFArray, CFArray) -> Int32
        
        let handler = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW)
        guard let SLSRemoveWindowsFromSpaces = unsafeBitCast(
            dlsym(handler, "SLSRemoveWindowsFromSpaces"),
            to: F_SLSRemoveWindowsFromSpaces?.self
        ) else {
            return
        }
        
        // Remove the window from the SkyLight space
        _ = SLSRemoveWindowsFromSpaces(
            connection,
            [window.windowNumber] as CFArray,
            [space] as CFArray
        )
    }
}

class IslandWindow: NSPanel {
    private var isSkyLightEnabled: Bool = false
    
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )
        
        configureWindow()
        setupObservers()
    }
    
    private func configureWindow() {
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        level = .mainMenu + 3
        hasShadow = false
        isReleasedWhenClosed = false
        
        // Force dark appearance regardless of system setting
        appearance = NSAppearance(named: .darkAqua)
        
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
        
        // Apply initial sharing type setting
        updateSharingType()
    }
    
    private func setupObservers() {
        // Listen for changes to the hideFromScreenRecording setting
        Defaults.publisher(.hideFromScreenRecording)
            .sink { [weak self] _ in
                self?.updateSharingType()
            }
            .store(in: &observers)
    }
    
    private func updateSharingType() {
        if Defaults[.hideFromScreenRecording] {
            sharingType = .none
        } else {
            sharingType = .readWrite
        }
    }
    
    func enableSkyLight() {
        if !isSkyLightEnabled {
            SkyLightOperator.shared.delegateWindow(self)
            isSkyLightEnabled = true
        }
    }
    
    func disableSkyLight() {
        if isSkyLightEnabled {
            SkyLightOperator.shared.undelegateWindow(self)
            isSkyLightEnabled = false
        }
    }
    
    private var observers: Set<AnyCancellable> = []
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
