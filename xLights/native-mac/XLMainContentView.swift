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

// MARK: - App State

/// Observable state object shared across the SwiftUI hierarchy.
@Observable
final class XLAppState {
    var currentTab: XLTab = .sequencer
    var inspectorVisible: Bool = true
    var bottomPanelVisible: Bool = true

    // Persisted sizes for split views
    var inspectorWidth: CGFloat = 300
    var bottomPanelHeight: CGFloat = 250

    // Shared engine bridge - created once, passed to all view controllers
    let engineBridge: XLEngineBridge

    init() {
        engineBridge = XLEngineBridge()
        loadState()
    }

    private func loadState() {
        let defaults = UserDefaults.standard
        if let tabIndex = defaults.object(forKey: "XLCurrentTab") as? Int,
           let tab = XLTab(rawValue: tabIndex) {
            currentTab = tab
        }
        if defaults.object(forKey: "XLInspectorVisible") != nil {
            inspectorVisible = defaults.bool(forKey: "XLInspectorVisible")
        }
        if defaults.object(forKey: "XLBottomPanelVisible") != nil {
            bottomPanelVisible = defaults.bool(forKey: "XLBottomPanelVisible")
        }
        if defaults.object(forKey: "XLInspectorWidth") != nil {
            inspectorWidth = defaults.double(forKey: "XLInspectorWidth")
        }
        if defaults.object(forKey: "XLBottomPanelHeight") != nil {
            bottomPanelHeight = defaults.double(forKey: "XLBottomPanelHeight")
        }
    }

    func saveState() {
        let defaults = UserDefaults.standard
        defaults.set(currentTab.rawValue, forKey: "XLCurrentTab")
        defaults.set(inspectorVisible, forKey: "XLInspectorVisible")
        defaults.set(bottomPanelVisible, forKey: "XLBottomPanelVisible")
        defaults.set(inspectorWidth, forKey: "XLInspectorWidth")
        defaults.set(bottomPanelHeight, forKey: "XLBottomPanelHeight")
    }
}

// MARK: - Tab Enum

enum XLTab: Int, CaseIterable, Identifiable {
    case setup = 0
    case layout = 1
    case sequencer = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .setup: return "Setup"
        case .layout: return "Layout"
        case .sequencer: return "Sequencer"
        }
    }

    var icon: String {
        switch self {
        case .setup: return "gearshape.2"
        case .layout: return "square.grid.3x3"
        case .sequencer: return "waveform"
        }
    }
}

// MARK: - Main Content View

/// Main SwiftUI content view using NavigationSplitView for Logic Pro X-style layout.
/// This replaces the NSSplitViewController-based approach that was fighting Auto Layout.
struct XLMainContentView: View {
    @Bindable var appState: XLAppState

    // Split view column visibility
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar: Tab selection (could add more sidebar items later)
            sidebarContent
        } detail: {
            // Detail: Main content area with bottom panel
            HSplitView {
                // Main content + bottom panel (vertical split)
                mainContentWithBottomPanel

                // Inspector (right side)
                if appState.inspectorVisible {
                    inspectorPanel
                        .frame(minWidth: 220, idealWidth: appState.inspectorWidth, maxWidth: 500)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            toolbarContent
        }
        .onDisappear {
            appState.saveState()
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebarContent: some View {
        List(selection: Binding(
            get: { appState.currentTab },
            set: { appState.currentTab = $0 }
        )) {
            ForEach(XLTab.allCases) { tab in
                Label(tab.title, systemImage: tab.icon)
                    .tag(tab)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("xLights")
    }

    // MARK: - Main Content with Bottom Panel

    @ViewBuilder
    private var mainContentWithBottomPanel: some View {
        VSplitView {
            // Tab content area
            tabContent
                .frame(minHeight: 300)

            // Bottom panel (properties/effects)
            if appState.bottomPanelVisible {
                bottomPanel
                    .frame(minHeight: 150, idealHeight: appState.bottomPanelHeight, maxHeight: 500)
            }
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch appState.currentTab {
        case .setup:
            XLSetupTabView(engineBridge: appState.engineBridge)
        case .layout:
            XLLayoutTabView(engineBridge: appState.engineBridge)
        case .sequencer:
            XLSequencerTabView(engineBridge: appState.engineBridge)
        }
    }

    // MARK: - Bottom Panel

    @ViewBuilder
    private var bottomPanel: some View {
        VStack(spacing: 0) {
            // Divider at top
            Divider()

            // Placeholder for effect properties panel
            ZStack {
                Color(nsColor: NSColor(white: 0.15, alpha: 1.0))
                Text("Effect Properties Panel")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Inspector Panel

    @ViewBuilder
    private var inspectorPanel: some View {
        XLInspectorView(engineBridge: appState.engineBridge)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .principal) {
            Picker("Tab", selection: $appState.currentTab) {
                ForEach(XLTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 250)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                appState.engineBridge.play()
            } label: {
                Label("Play", systemImage: "play.fill")
            }

            Button {
                appState.engineBridge.pause()
            } label: {
                Label("Pause", systemImage: "pause.fill")
            }

            Button {
                appState.engineBridge.stop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }

            Button {
                appState.engineBridge.renderAll()
            } label: {
                Label("Render", systemImage: "gearshape.fill")
            }
        }

        ToolbarItemGroup(placement: .automatic) {
            Button {
                withAnimation {
                    appState.inspectorVisible.toggle()
                }
            } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }

            Button {
                withAnimation {
                    appState.bottomPanelVisible.toggle()
                }
            } label: {
                Label("Properties", systemImage: "rectangle.split.1x2")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    XLMainContentView(appState: XLAppState())
        .frame(width: 1400, height: 900)
}
