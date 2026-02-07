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

// MARK: - Setup Tab View Wrapper

/// Wraps XLSetupViewController (AppKit) for use in SwiftUI.
struct XLSetupTabView: NSViewControllerRepresentable {
    let engineBridge: XLEngineBridge

    func makeNSViewController(context: Context) -> XLSetupViewController {
        let viewController = XLSetupViewController()
        viewController.engineBridge = engineBridge
        return viewController
    }

    func updateNSViewController(_ nsViewController: XLSetupViewController, context: Context) {
        // Update if needed when SwiftUI state changes
    }
}

// MARK: - Layout Tab View Wrapper

/// Wraps XLLayoutViewController (AppKit) for use in SwiftUI.
struct XLLayoutTabView: NSViewControllerRepresentable {
    let engineBridge: XLEngineBridge

    func makeNSViewController(context: Context) -> XLLayoutViewController {
        let viewController = XLLayoutViewController()
        viewController.engineBridge = engineBridge
        return viewController
    }

    func updateNSViewController(_ nsViewController: XLLayoutViewController, context: Context) {
        // Update if needed when SwiftUI state changes
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsViewController: XLLayoutViewController, context: Context) -> CGSize? {
        // Always fill all available space so the internal NSSplitView divider
        // doesn't cause SwiftUI to resize the entire container
        return CGSize(
            width: proposal.width ?? 800,
            height: proposal.height ?? 600
        )
    }
}

// MARK: - Sequencer Tab View Wrapper

/// Wraps XLSequencerViewController (AppKit) for use in SwiftUI.
struct XLSequencerTabView: NSViewControllerRepresentable {
    let engineBridge: XLEngineBridge

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSViewController(context: Context) -> XLSequencerViewController {
        let viewController = XLSequencerViewController()
        viewController.engineBridge = engineBridge
        context.coordinator.viewController = viewController
        context.coordinator.startObserving()
        // Store weak reference for direct access (e.g., house preview toggle)
        XLSwiftUIWindowHelper.shared.sequencerViewController = viewController
        return viewController
    }

    func updateNSViewController(_ nsViewController: XLSequencerViewController, context: Context) {
        // Update if needed when SwiftUI state changes
    }

    class Coordinator: @unchecked Sendable {
        weak var viewController: XLSequencerViewController?
        private var observer: NSObjectProtocol?

        func startObserving() {
            observer = NotificationCenter.default.addObserver(
                forName: XLSequenceDataDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.viewController?.reloadSequenceData()
                }
            }
        }

        deinit {
            if let observer = observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}

// MARK: - Inspector View Wrapper

/// Wraps XLInspectorViewController (AppKit) for use in SwiftUI.
struct XLInspectorView: NSViewControllerRepresentable {
    let engineBridge: XLEngineBridge

    func makeNSViewController(context: Context) -> XLInspectorViewController {
        let viewController = XLInspectorViewController()
        viewController.engineBridge = engineBridge
        return viewController
    }

    func updateNSViewController(_ nsViewController: XLInspectorViewController, context: Context) {
        // Update if needed when SwiftUI state changes
    }
}

// MARK: - Effect Properties Panel Wrapper

/// Wraps XLEffectPropertiesViewController (AppKit) for use in SwiftUI.
/// This displays effect parameter controls when an effect is selected in the sequencer.
struct XLEffectPropertiesView: NSViewControllerRepresentable {
    let engineBridge: XLEngineBridge

    func makeNSViewController(context: Context) -> XLEffectPropertiesViewController {
        let viewController = XLEffectPropertiesViewController()
        viewController.engineBridge = engineBridge
        return viewController
    }

    func updateNSViewController(_ nsViewController: XLEffectPropertiesViewController, context: Context) {
        // The view controller handles updates via notifications
    }
}

// MARK: - Generic NSView Wrapper

/// Generic wrapper for any NSView to embed in SwiftUI.
/// Useful for Metal-backed views, CALayer-backed views, etc.
struct NSViewWrapper<Wrapped: NSView>: NSViewRepresentable {
    let makeView: () -> Wrapped
    var updateView: ((Wrapped) -> Void)?

    init(_ makeView: @escaping () -> Wrapped) {
        self.makeView = makeView
    }

    init(_ makeView: @escaping () -> Wrapped, update: @escaping (Wrapped) -> Void) {
        self.makeView = makeView
        self.updateView = update
    }

    func makeNSView(context: Context) -> Wrapped {
        makeView()
    }

    func updateNSView(_ nsView: Wrapped, context: Context) {
        updateView?(nsView)
    }
}

// MARK: - Generic NSViewController Wrapper

/// Generic wrapper for any NSViewController to embed in SwiftUI.
struct NSViewControllerWrapper<Wrapped: NSViewController>: NSViewControllerRepresentable {
    let makeController: () -> Wrapped
    var updateController: ((Wrapped) -> Void)?

    init(_ makeController: @escaping () -> Wrapped) {
        self.makeController = makeController
    }

    init(_ makeController: @escaping () -> Wrapped, update: @escaping (Wrapped) -> Void) {
        self.makeController = makeController
        self.updateController = update
    }

    func makeNSViewController(context: Context) -> Wrapped {
        makeController()
    }

    func updateNSViewController(_ nsViewController: Wrapped, context: Context) {
        updateController?(nsViewController)
    }
}
