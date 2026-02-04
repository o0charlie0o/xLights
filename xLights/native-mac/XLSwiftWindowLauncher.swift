/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

import SwiftUI
import AppKit

// MARK: - Window Controller

/// SwiftUI-based main window controller.
/// This replaces XLMainWindowController (ObjC/AppKit) to solve window resize issues.
/// Notification posted when sequence data changes and views should reload
let XLSequenceDataDidChangeNotification = NSNotification.Name("XLSequenceDataDidChangeNotification")

/// Global reference to the engine bridge for ObjC access
/// nonisolated(unsafe) because it's only set/accessed from main thread
nonisolated(unsafe) private var sSwiftEngineBridge: XLEngineBridge?

@MainActor
final class XLSwiftWindowController: NSWindowController, NSWindowDelegate {

    private let appState: XLAppState

    init() {
        appState = XLAppState()
        // Store engine bridge in global for ObjC access
        sSwiftEngineBridge = appState.engineBridge

        // Create window with standard macOS chrome
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1600, height: 1000),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Hide title but keep the toolbar area
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        window.minSize = NSSize(width: 1024, height: 600)

        // Dark appearance
        window.appearance = NSAppearance(named: .darkAqua)

        super.init(window: window)

        window.delegate = self

        // Create SwiftUI content view and host it
        let contentView = XLMainContentView(appState: appState)
        let hostingController = NSHostingController(rootView: contentView)

        // Set as content view controller - SwiftUI handles all the layout
        window.contentViewController = hostingController

        // Restore saved window frame
        restoreWindowFrame()

        NSLog("NativeUI [SwiftUI]: Window created with frame: %@", NSStringFromRect(window.frame))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Frame Persistence

    private func restoreWindowFrame() {
        if let frameString = UserDefaults.standard.string(forKey: "XLMainWindowFrame"),
           let window = self.window {
            let frame = NSRectFromString(frameString)
            if frame.size.width > 0 && frame.size.height > 0 {
                window.setFrame(frame, display: false)
            }
        }
    }

    private func saveWindowFrame() {
        if let window = self.window {
            let frameString = NSStringFromRect(window.frame)
            UserDefaults.standard.set(frameString, forKey: "XLMainWindowFrame")
        }
        appState.saveState()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        saveWindowFrame()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if let window = self.window {
            NSLog("NativeUI [SwiftUI]: windowDidBecomeKey frame=%@ styleMask=%lu",
                  NSStringFromRect(window.frame),
                  window.styleMask.rawValue)
        }
    }
}

// MARK: - ObjC-Callable Launcher

/// Static holder for the window controller to prevent deallocation.
/// nonisolated(unsafe) because this is only accessed from the main thread via DispatchQueue.main
nonisolated(unsafe) private var sSwiftWindowController: XLSwiftWindowController?

/// Launch the native SwiftUI-based window.
/// Call this from ObjC/C++ code to show the new native macOS UI.
///
/// Usage from ObjC:
/// ```objc
/// XLLaunchSwiftUIWindow();
/// ```
@_cdecl("XLLaunchSwiftUIWindow")
@MainActor
public func XLLaunchSwiftUIWindow() -> Int32 {
    DispatchQueue.main.async {
        NSLog("NativeUI [SwiftUI launcher]: Creating SwiftUI window controller")

        sSwiftWindowController = XLSwiftWindowController()

        if let window = sSwiftWindowController?.window {
            window.makeKeyAndOrderFront(nil)

            NSLog("NativeUI [SwiftUI launcher]: Window shown, frame=%@ isVisible=%d",
                  NSStringFromRect(window.frame),
                  window.isVisible)
        }
    }

    return 1
}

/// Close the native SwiftUI window if open.
@_cdecl("XLCloseSwiftUIWindow")
@MainActor
public func XLCloseSwiftUIWindow() {
    DispatchQueue.main.async {
        sSwiftWindowController?.close()
        sSwiftWindowController = nil
        sSwiftEngineBridge = nil
    }
}

// MARK: - ObjC-Accessible Helper Class

/// Helper class to provide ObjC-accessible interface to SwiftUI window state.
/// Use this instead of @_cdecl functions for ObjC interop with object types.
@objc(XLSwiftUIWindowHelper)
public final class XLSwiftUIWindowHelper: NSObject, @unchecked Sendable {

    /// Shared instance for ObjC access
    @objc public static let shared = XLSwiftUIWindowHelper()

    private override init() {
        super.init()
    }

    /// Get the engine bridge from the SwiftUI window controller.
    /// Returns nil if no SwiftUI window is active.
    @objc public var engineBridge: XLEngineBridge? {
        let bridge = sSwiftEngineBridge
        NSLog("XLSwiftUIWindowHelper.engineBridge: returning %@", bridge != nil ? "bridge" : "nil")
        return bridge
    }

    /// Check if the SwiftUI window is the current key window.
    @objc public var isSwiftUIWindowKey: Bool {
        guard let swiftWindow = sSwiftWindowController?.window else {
            NSLog("XLSwiftUIWindowHelper.isSwiftUIWindowKey: no swift window controller, returning false")
            return false
        }
        let isKey = swiftWindow.isKeyWindow
        NSLog("XLSwiftUIWindowHelper.isSwiftUIWindowKey: swiftWindow.isKeyWindow = %d", isKey)
        return isKey
    }

    /// Notify the SwiftUI window that sequence data has changed and views should reload.
    @objc public func notifySequenceDataChanged() {
        NSLog("XLSwiftUIWindowHelper.notifySequenceDataChanged: posting notification")
        NotificationCenter.default.post(name: XLSequenceDataDidChangeNotification, object: nil)
    }
}
