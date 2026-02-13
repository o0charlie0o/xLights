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
    var sidebarVisible: Bool = false

    // Top panel visibility - each panel can be toggled independently
    var visibleTopPanels: Set<XLTopPanelTab> = [.effects, .colors, .layerBlending, .layerSettings]

    // Persisted sizes for split views
    var sidebarWidth: CGFloat = 250
    var inspectorWidth: CGFloat = 300
    var topPanelHeight: CGFloat = 250

    // Panel width proportions (0.0-1.0) - stored as proportion of total width
    // When panels are shown/hidden, widths are recalculated to maintain proportions
    var panelWidthProportions: [XLTopPanelTab: CGFloat] = [
        .effects: 0.25,
        .colors: 0.25,
        .layerBlending: 0.25,
        .layerSettings: 0.25
    ]

    // Render progress state
    var isRendering: Bool = false
    var renderProgress: Double = 0.0

    // State synced from ObjC sequencer VC
    var housePreviewVisible: Bool = false
    var snapEnabled: Bool = true
    var songRegionOverlayVisible: Bool = true
    var commandPaletteVisible: Bool = false

    // Shared engine bridge - created once, passed to all view controllers
    let engineBridge: XLEngineBridge

    // Effect selection state - shared across sequencer and properties panel
    let effectSelectionState: EffectSelectionState

    // Computed property for whether any top panel is visible
    var topPanelVisible: Bool {
        !visibleTopPanels.isEmpty
    }

    private var commandPaletteObserver: Any?

    init() {
        engineBridge = XLEngineBridge()
        effectSelectionState = EffectSelectionState()
        effectSelectionState.engineBridge = engineBridge
        loadState()

        // Sync command palette visibility state for toolbar button
        commandPaletteObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("XLCommandPaletteVisibilityChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let visible = (notification.userInfo?["visible"] as? Bool) ?? false
            self?.commandPaletteVisible = visible
        }
    }

    func toggleTopPanel(_ panel: XLTopPanelTab) {
        if visibleTopPanels.contains(panel) {
            visibleTopPanels.remove(panel)
        } else {
            visibleTopPanels.insert(panel)
        }
    }

    private func loadState() {
        let defaults = UserDefaults.standard
        if let tabIndex = defaults.object(forKey: "XLCurrentTab") as? Int,
           let tab = XLTab(rawValue: tabIndex) {
            currentTab = tab
        }
        if let panelBits = defaults.object(forKey: "XLVisibleTopPanels") as? Int {
            visibleTopPanels = XLTopPanelTab.setFromBitmask(panelBits)
        }
        if defaults.object(forKey: "XLInspectorVisible") != nil {
            inspectorVisible = defaults.bool(forKey: "XLInspectorVisible")
        }
        if defaults.object(forKey: "XLSidebarVisible") != nil {
            sidebarVisible = defaults.bool(forKey: "XLSidebarVisible")
        }
        if defaults.object(forKey: "XLSidebarWidth") != nil {
            sidebarWidth = defaults.double(forKey: "XLSidebarWidth")
        }
        if defaults.object(forKey: "XLInspectorWidth") != nil {
            inspectorWidth = defaults.double(forKey: "XLInspectorWidth")
        }
        if defaults.object(forKey: "XLTopPanelHeight") != nil {
            topPanelHeight = defaults.double(forKey: "XLTopPanelHeight")
        }
        if defaults.object(forKey: "XLSongRegionOverlay") != nil {
            songRegionOverlayVisible = defaults.bool(forKey: "XLSongRegionOverlay")
        }
        if let widthsDict = defaults.dictionary(forKey: "XLPanelWidthProportions") as? [String: Double] {
            for (key, value) in widthsDict {
                if let rawValue = Int(key), let tab = XLTopPanelTab(rawValue: rawValue) {
                    panelWidthProportions[tab] = CGFloat(value)
                }
            }
        }
    }

    func saveState() {
        let defaults = UserDefaults.standard
        defaults.set(currentTab.rawValue, forKey: "XLCurrentTab")
        defaults.set(XLTopPanelTab.bitmask(from: visibleTopPanels), forKey: "XLVisibleTopPanels")
        defaults.set(inspectorVisible, forKey: "XLInspectorVisible")
        defaults.set(sidebarVisible, forKey: "XLSidebarVisible")
        defaults.set(sidebarWidth, forKey: "XLSidebarWidth")
        defaults.set(inspectorWidth, forKey: "XLInspectorWidth")
        defaults.set(topPanelHeight, forKey: "XLTopPanelHeight")
        defaults.set(songRegionOverlayVisible, forKey: "XLSongRegionOverlay")
        // Save panel width proportions
        var widthsDict: [String: Double] = [:]
        for (tab, proportion) in panelWidthProportions {
            widthsDict[String(tab.rawValue)] = Double(proportion)
        }
        defaults.set(widthsDict, forKey: "XLPanelWidthProportions")
    }

    /// Get the width for a panel given the total available width and visible panels
    func panelWidth(for panel: XLTopPanelTab, totalWidth: CGFloat, visiblePanels: [XLTopPanelTab]) -> CGFloat {
        guard visiblePanels.contains(panel) else { return 0 }

        // Calculate total proportion of visible panels
        let totalProportion = visiblePanels.reduce(0.0) { $0 + (panelWidthProportions[$1] ?? 0.25) }
        let panelProportion = panelWidthProportions[panel] ?? 0.25

        // Normalize to get actual width
        let handleWidth: CGFloat = CGFloat(max(0, visiblePanels.count - 1)) * 2.0
        let availableWidth = totalWidth - handleWidth
        return (panelProportion / totalProportion) * availableWidth
    }

    /// Adjust panel widths when dragging a resize handle between two panels
    func adjustPanelWidths(leftPanel: XLTopPanelTab, rightPanel: XLTopPanelTab, delta: CGFloat, totalWidth: CGFloat, visiblePanels: [XLTopPanelTab]) {
        let handleWidth: CGFloat = CGFloat(max(0, visiblePanels.count - 1)) * 2.0
        let availableWidth = totalWidth - handleWidth
        guard availableWidth > 0 else { return }

        // Calculate total proportion of visible panels for normalization
        let totalProportion = visiblePanels.reduce(0.0) { $0 + (panelWidthProportions[$1] ?? 0.25) }

        // Convert delta to proportion change
        let deltaProportion = (delta / availableWidth) * totalProportion

        // Get current proportions
        let leftProportion = panelWidthProportions[leftPanel] ?? 0.25
        let rightProportion = panelWidthProportions[rightPanel] ?? 0.25

        // Calculate new proportions with minimum width constraint (10% of total)
        let minProportion: CGFloat = 0.1 * totalProportion / CGFloat(visiblePanels.count)
        let newLeftProportion = max(minProportion, leftProportion + deltaProportion)
        let newRightProportion = max(minProportion, rightProportion - deltaProportion)

        // Only apply if both panels would remain above minimum
        if newLeftProportion >= minProportion && newRightProportion >= minProportion {
            panelWidthProportions[leftPanel] = newLeftProportion
            panelWidthProportions[rightPanel] = newRightProportion
        }
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

// MARK: - Top Panel Tab Enum

enum XLTopPanelTab: Int, CaseIterable, Identifiable, Hashable {
    case effects = 0
    case colors = 1
    case layerBlending = 2
    case layerSettings = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .effects: return "Effects"
        case .colors: return "Colors"
        case .layerBlending: return "Blending"
        case .layerSettings: return "Settings"
        }
    }

    // Bitmask helpers for UserDefaults persistence
    var bitmask: Int { 1 << rawValue }

    static func bitmask(from set: Set<XLTopPanelTab>) -> Int {
        set.reduce(0) { $0 | $1.bitmask }
    }

    static func setFromBitmask(_ bits: Int) -> Set<XLTopPanelTab> {
        var result = Set<XLTopPanelTab>()
        for tab in allCases {
            if bits & tab.bitmask != 0 {
                result.insert(tab)
            }
        }
        return result
    }
}

// MARK: - Main Content View

/// Main SwiftUI content view using NavigationSplitView for Logic Pro X-style layout.
/// This replaces the NSSplitViewController-based approach that was fighting Auto Layout.
struct XLMainContentView: View {
    @Bindable var appState: XLAppState

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                // Sidebar: Model preview and effect assist (like legacy xLights)
                // Uses HStack with conditional visibility instead of NavigationSplitView
                // to avoid animation glitches and layout breaks when toggling panels
                if appState.sidebarVisible {
                    sidebarContent
                        .frame(width: appState.sidebarWidth)
                    Divider()
                }

                // Main content area with inspector
                HStack(spacing: 0) {
                    // Main content + top panel (at top, like regular xLights)
                    mainContentWithTopPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Inspector (right side) - always in hierarchy but zero-width when hidden
                    if appState.inspectorVisible {
                        Divider()
                        inspectorPanel
                            .frame(width: appState.inspectorWidth)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .toolbar {
                toolbarContent
            }
            .modifier(RenderProgressPoller(appState: appState))
            .onDisappear {
                appState.saveState()
            }

            // Command palette overlay
            XLCommandPaletteOverlay()
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebarContent: some View {
        if appState.currentTab == .sequencer {
            VStack(spacing: 0) {
                // Model Preview (top)
                VStack(spacing: 0) {
                    HStack {
                        Text("Model Preview")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .windowBackgroundColor))

                    XLSidebarModelPreview(
                        engineBridge: appState.engineBridge,
                        effectSelectionState: appState.effectSelectionState
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                // Effect Assist (bottom)
                VStack(spacing: 0) {
                    HStack {
                        Text("Effect Assist")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .windowBackgroundColor))

                    effectAssistContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(nsColor: .controlBackgroundColor))
        } else {
            // Tab list for other tabs
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
        }
    }

    // MARK: - Effect Assist Content

    @ViewBuilder
    private var effectAssistContent: some View {
        if let effectType = appState.effectSelectionState.effectType, !effectType.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: effectAssistIcon(for: effectType))
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)
                Text(effectType)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("Select an effect")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func effectAssistIcon(for effectType: String) -> String {
        switch effectType.lowercased() {
        case "text": return "textformat"
        case "pictures": return "photo"
        case "faces": return "face.smiling"
        case "fire": return "flame"
        case "bars": return "chart.bar"
        case "butterfly": return "ladybug"
        case "circles": return "circle.grid.3x3"
        case "colorwash": return "paintbrush"
        case "curtain": return "blinds.vertical.closed"
        case "fireworks": return "sparkles"
        case "garlands": return "leaf"
        case "kaleidoscope": return "hexagon"
        case "life": return "square.grid.3x3"
        case "marquee": return "arrow.right"
        case "meteors": return "cloud.rain"
        case "morph": return "wand.and.stars"
        case "music": return "music.note"
        case "on": return "power"
        case "plasma": return "cloud.sun"
        case "ripple": return "wave.3.right"
        case "shimmer": return "sparkle"
        case "single strand": return "line.diagonal"
        case "snowflakes": return "snowflake"
        case "snowstorm": return "cloud.snow"
        case "spirals": return "tornado"
        case "spirograph": return "circle.dotted"
        case "strobe": return "bolt"
        case "twinkle": return "star"
        case "video": return "video"
        case "wave": return "waveform.path.ecg"
        default: return "sparkles"
        }
    }

    // MARK: - Main Content with Top Panel

    @ViewBuilder
    private var mainContentWithTopPanel: some View {
        // Using VStack instead of VSplitView to avoid SwiftUI bugs when toggling panels
        VStack(spacing: 0) {
            // Top panel (like regular xLights) - only on sequencer tab
            if appState.topPanelVisible && appState.currentTab == .sequencer {
                topPanelWithTabs
                    .frame(height: appState.topPanelHeight)

                // Draggable resize handle
                TopPanelResizeHandle(height: $appState.topPanelHeight)
                    .frame(height: 2)
            }

            // Tab content area - takes all available space
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Top Panel with Toggles

    @ViewBuilder
    private var topPanelWithTabs: some View {
        VStack(spacing: 0) {
            // Multi-select toggle buttons (centered)
            HStack(spacing: 0) {
                Spacer()
                topPanelToggleButtons
                Spacer()
            }
            .padding(.vertical, 6)

            Divider()

            // Visible panels side by side
            topPanelContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Top Panel Toggle Buttons

    @ViewBuilder
    private var topPanelToggleButtons: some View {
        HStack(spacing: 1) {
            ForEach(XLTopPanelTab.allCases) { tab in
                Button {
                    appState.toggleTopPanel(tab)
                } label: {
                    Text(tab.title)
                        .font(.system(size: 12))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }
                .buttonStyle(TopPanelToggleButtonStyle(
                    isSelected: appState.visibleTopPanels.contains(tab),
                    isFirst: tab == XLTopPanelTab.allCases.first,
                    isLast: tab == XLTopPanelTab.allCases.last
                ))
            }
        }
        .background(Color(nsColor: .separatorColor))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    // MARK: - Top Panel Content

    @ViewBuilder
    private var topPanelContent: some View {
        let visiblePanels = XLTopPanelTab.allCases.filter { appState.visibleTopPanels.contains($0) }

        if visiblePanels.isEmpty {
            Color.clear
        } else {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ForEach(Array(visiblePanels.enumerated()), id: \.element.id) { index, panel in
                        panelView(for: panel)
                            .frame(
                                width: appState.panelWidth(for: panel, totalWidth: geometry.size.width, visiblePanels: visiblePanels),
                                height: geometry.size.height
                            )

                        // Add resize handle between panels (not after the last one)
                        if index < visiblePanels.count - 1 {
                            let leftPanel = panel
                            let rightPanel = visiblePanels[index + 1]
                            HorizontalPanelResizeHandle(
                                leftPanel: leftPanel,
                                rightPanel: rightPanel,
                                totalWidth: geometry.size.width,
                                visiblePanels: visiblePanels,
                                appState: appState
                            )
                            .frame(width: 2)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func panelView(for panel: XLTopPanelTab) -> some View {
        switch panel {
        case .effects:
            EffectPaletteGridView(engineBridge: appState.engineBridge)
        case .colors:
            ColorPaletteView(engineBridge: appState.engineBridge)
        case .layerBlending:
            LayerBlendingView(engineBridge: appState.engineBridge)
        case .layerSettings:
            LayerSettingsView(engineBridge: appState.engineBridge,
                              effectSelectionState: appState.effectSelectionState)
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

    // MARK: - Inspector Panel

    @ViewBuilder
    private var inspectorPanel: some View {
        // Context-sensitive inspector:
        // - When on sequencer tab with effect selected: show effect properties
        // - Layout tab: show model properties (updated via notifications)
        // - Otherwise: show general inspector
        if appState.currentTab == .sequencer {
            EffectPropertiesView(state: appState.effectSelectionState)
        } else {
            XLInspectorView(engineBridge: appState.engineBridge)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Tab buttons on the left side of the toolbar
        ToolbarItemGroup(placement: .navigation) {
            Button {
                appState.sidebarVisible.toggle()
            } label: {
                Label("Sidebar", systemImage: "sidebar.left")
            }
            .buttonStyle(ToolbarToggleButtonStyle(isActive: appState.sidebarVisible))
            .help("Model Preview Sidebar")

            ForEach(XLTab.allCases) { tab in
                Button {
                    appState.currentTab = tab
                } label: {
                    Label(tab.title, systemImage: tab.icon)
                }
                .buttonStyle(TabToolbarButtonStyle(isActive: appState.currentTab == tab))
                .help(tab.title)
            }
        }

        // Playback controls centered in toolbar
        // Route through sequencer VC so transport bar, playback controller,
        // and timeline all stay in sync.
        ToolbarItemGroup(placement: .principal) {
            Button {
                XLSwiftUIWindowHelper.shared.sequencerViewController?.seekToStart(nil)
            } label: {
                Label("Go to Beginning", systemImage: "backward.end.fill")
            }
            .help("Go to Beginning")

            Button {
                XLSwiftUIWindowHelper.shared.sequencerViewController?.play()
            } label: {
                Label("Play", systemImage: "play.fill")
            }

            Button {
                XLSwiftUIWindowHelper.shared.sequencerViewController?.pause()
            } label: {
                Label("Pause", systemImage: "pause.fill")
            }

            Button {
                XLSwiftUIWindowHelper.shared.sequencerViewController?.stop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }

            Button {
                appState.isRendering = true
                appState.renderProgress = 0.0
                XLSwiftUIWindowHelper.shared.sequencerViewController?.renderAll()
            } label: {
                RenderProgressRing(
                    isRendering: appState.isRendering,
                    progress: appState.renderProgress
                )
            }
            .help("Render All")
        }

        // Panel toggles on the right — blue tint when active
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                XLCommandPaletteState.shared.toggle()
            } label: {
                Label("Command Palette", systemImage: "command")
            }
            .buttonStyle(ToolbarToggleButtonStyle(isActive: appState.commandPaletteVisible))
            .help("Command Palette (⇧⌘K)")

            Button {
                // Toggle all panels on/off
                if appState.visibleTopPanels.isEmpty {
                    appState.visibleTopPanels = [.effects, .colors, .layerBlending, .layerSettings]
                } else {
                    appState.visibleTopPanels.removeAll()
                }
            } label: {
                Label("Palettes", systemImage: "rectangle.split.1x2")
            }
            .buttonStyle(ToolbarToggleButtonStyle(isActive: appState.topPanelVisible))

            Button {
                appState.snapEnabled.toggle()
                XLSwiftUIWindowHelper.shared.setSnapEnabled(appState.snapEnabled)
            } label: {
                Label("Snap", systemImage: "arrow.right.to.line")
            }
            .buttonStyle(ToolbarToggleButtonStyle(isActive: appState.snapEnabled))
            .help("Snap to Timing Marks")

            Button {
                XLSwiftUIWindowHelper.shared.toggleHousePreview()
            } label: {
                Label("Preview", systemImage: "eye.fill")
            }
            .buttonStyle(ToolbarToggleButtonStyle(isActive: appState.housePreviewVisible))
            .help("House Preview (⇧⌘P)")

            Button {
                appState.songRegionOverlayVisible.toggle()
                XLSwiftUIWindowHelper.shared.setSongRegionOverlayVisible(appState.songRegionOverlayVisible)
            } label: {
                Label("Song Regions", systemImage: "rectangle.split.3x1")
            }
            .buttonStyle(ToolbarToggleButtonStyle(isActive: appState.songRegionOverlayVisible))
            .help("Show Song Regions in Grid")

            Button {
                appState.inspectorVisible.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .buttonStyle(ToolbarToggleButtonStyle(isActive: appState.inspectorVisible))
        }
    }
}

// MARK: - Render Progress Ring

/// A circular progress indicator for the toolbar render button.
/// Shows a palette icon when idle, an animated spinning ring when rendering
/// with indeterminate progress, or a filling arc for determinate progress.
struct RenderProgressRing: View {
    let isRendering: Bool
    let progress: Double

    @State private var rotation: Double = 0

    private let ringSize: CGFloat = 18
    private let lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            if isRendering {
                // Track ring
                Circle()
                    .stroke(Color.secondary.opacity(0.3), lineWidth: lineWidth)
                    .frame(width: ringSize, height: ringSize)

                if progress > 0.01 {
                    // Determinate progress arc
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .frame(width: ringSize, height: ringSize)
                        .rotationEffect(.degrees(-90))
                } else {
                    // Indeterminate spinner
                    Circle()
                        .trim(from: 0, to: 0.25)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .frame(width: ringSize, height: ringSize)
                        .rotationEffect(.degrees(rotation))
                        .onAppear {
                            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                                rotation = 360
                            }
                        }
                        .onDisappear {
                            rotation = 0
                        }
                }
            } else {
                Image(systemName: "paintpalette.fill")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isRendering)
    }
}

// MARK: - Render Progress Poller

/// Polls the engine bridge for render progress and updates XLAppState.
struct RenderProgressPoller: ViewModifier {
    let appState: XLAppState
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    func body(content: Content) -> some View {
        content.onReceive(timer) { _ in
            let bridge = appState.engineBridge
            let rendering = bridge.isRendering()
            appState.isRendering = rendering
            if rendering {
                appState.renderProgress = Double(bridge.getRenderProgress())
            } else if appState.renderProgress > 0 {
                appState.renderProgress = 0
            }
        }
    }
}

// MARK: - Top Panel Toggle Button Style

struct TopPanelToggleButtonStyle: ButtonStyle {
    let isSelected: Bool
    let isFirst: Bool
    let isLast: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isSelected ? .white : .primary)
            .background(
                isSelected
                    ? Color.accentColor
                    : Color(nsColor: .controlBackgroundColor)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

// MARK: - Top Panel Resize Handle

/// A draggable handle for resizing the top panel height.
/// Provides visual feedback and cursor change on hover.
/// Uses NSView-based drag tracking for smooth, low-latency resizing.
struct TopPanelResizeHandle: NSViewRepresentable {
    @Binding var height: CGFloat

    private let minHeight: CGFloat = 100
    private let maxHeight: CGFloat = 500

    func makeNSView(context: Context) -> ResizeHandleNSView {
        let view = ResizeHandleNSView()
        view.onDrag = { delta in
            let newHeight = self.height + delta
            self.height = min(max(newHeight, self.minHeight), self.maxHeight)
        }
        return view
    }

    func updateNSView(_ nsView: ResizeHandleNSView, context: Context) {
        // No updates needed
    }
}

/// AppKit view for smooth drag handling without SwiftUI gesture overhead.
class ResizeHandleNSView: NSView {
    var onDrag: ((CGFloat) -> Void)?

    private var isDragging = false
    private var isHovering = false
    private var lastY: CGFloat = 0
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        updateAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 2)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        NSCursor.resizeUpDown.push()
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        NSCursor.pop()
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        lastY = event.locationInWindow.y
        updateAppearance()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let currentY = event.locationInWindow.y
        // Negate delta: dragging down (negative Y change) should increase height
        let delta = -(currentY - lastY)
        lastY = currentY
        onDrag?(delta)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        updateAppearance()
    }

    private func updateAppearance() {
        if isDragging || isHovering {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.5).cgColor
        } else {
            layer?.backgroundColor = NSColor.separatorColor.cgColor
        }
    }
}

// MARK: - Horizontal Panel Resize Handle

/// A draggable handle for resizing panels horizontally within the top panel area.
/// Uses NSView-based drag tracking for smooth, low-latency resizing.
struct HorizontalPanelResizeHandle: NSViewRepresentable {
    let leftPanel: XLTopPanelTab
    let rightPanel: XLTopPanelTab
    let totalWidth: CGFloat
    let visiblePanels: [XLTopPanelTab]
    let appState: XLAppState

    func makeNSView(context: Context) -> HorizontalResizeHandleNSView {
        let view = HorizontalResizeHandleNSView()
        view.onDrag = { [appState] delta in
            appState.adjustPanelWidths(
                leftPanel: leftPanel,
                rightPanel: rightPanel,
                delta: delta,
                totalWidth: totalWidth,
                visiblePanels: visiblePanels
            )
        }
        return view
    }

    func updateNSView(_ nsView: HorizontalResizeHandleNSView, context: Context) {
        // Update the callback with current values
        nsView.onDrag = { [appState] delta in
            appState.adjustPanelWidths(
                leftPanel: leftPanel,
                rightPanel: rightPanel,
                delta: delta,
                totalWidth: totalWidth,
                visiblePanels: visiblePanels
            )
        }
    }
}

/// AppKit view for smooth horizontal drag handling.
class HorizontalResizeHandleNSView: NSView {
    var onDrag: ((CGFloat) -> Void)?

    private var isDragging = false
    private var isHovering = false
    private var lastX: CGFloat = 0
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        updateAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 2, height: NSView.noIntrinsicMetric)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        NSCursor.resizeLeftRight.push()
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        NSCursor.pop()
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        lastX = event.locationInWindow.x
        updateAppearance()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let currentX = event.locationInWindow.x
        let delta = currentX - lastX
        lastX = currentX
        onDrag?(delta)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        updateAppearance()
    }

    private func updateAppearance() {
        if isDragging || isHovering {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.5).cgColor
        } else {
            layer?.backgroundColor = NSColor.separatorColor.cgColor
        }
    }
}

// MARK: - Tab Toolbar Button Style

/// Custom button style for tab buttons in the toolbar.
/// Shows blue accent color when the tab is active, secondary color when inactive.
/// SwiftUI `.tint()` does NOT work on macOS toolbar buttons, so we use a custom ButtonStyle.
struct TabToolbarButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isActive ? .accentColor : .secondary)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// MARK: - Toolbar Toggle Button Style

/// Custom button style for toggle buttons in the right side of the toolbar.
/// Shows blue accent color when active, secondary color when inactive.
struct ToolbarToggleButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isActive ? .accentColor : .secondary)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// MARK: - Sidebar Model Preview

/// NSViewRepresentable wrapping XLMetalPreviewView for the sidebar.
/// Shows only the model(s) affected by the currently selected effect,
/// zoomed to fit. When the sequence isn't playing, loops a preview of the
/// selected effect's time range so the user can see the effect live.
struct XLSidebarModelPreview: NSViewRepresentable {
    let engineBridge: XLEngineBridge
    let effectSelectionState: EffectSelectionState

    func makeNSView(context: Context) -> XLMetalPreviewView {
        let preview = XLMetalPreviewView(frame: .zero)
        preview.engineBridge = engineBridge
        preview.show3D = false
        preview.showGrid = false
        preview.scrollbarsEnabled = false
        preview.backgroundColor = NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        preview.showEffectColors = true
        preview.framePadding = 0.15

        // Register on the singleton so the playback controller can always find it
        XLSwiftUIWindowHelper.shared.sidebarPreviewView = preview

        // Observe effect selection to filter visible models and start preview loop
        context.coordinator.start(preview: preview, bridge: engineBridge)

        return preview
    }

    func updateNSView(_ nsView: XLMetalPreviewView, context: Context) {
        // Ensure singleton always has the current view
        if XLSwiftUIWindowHelper.shared.sidebarPreviewView !== nsView {
            XLSwiftUIWindowHelper.shared.sidebarPreviewView = nsView
        }
    }

    static func dismantleNSView(_ nsView: XLMetalPreviewView, coordinator: Coordinator) {
        if XLSwiftUIWindowHelper.shared.sidebarPreviewView === nsView {
            XLSwiftUIWindowHelper.shared.sidebarPreviewView = nil
        }
        nsView.stopRenderLoop()
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        private var selectionObserver: NSObjectProtocol?
        private var playbackStartObserver: NSObjectProtocol?
        private var playbackStopObserver: NSObjectProtocol?
        private var previewTimer: Timer?
        private var currentModelName: String?
        private var playbackActive = false

        // Effect preview loop state
        private var effectStartMS: Int = 0
        private var effectEndMS: Int = 0
        private var loopPositionMS: Int = 0
        private var frameTimeMS: Int = 50
        private weak var previewView: XLMetalPreviewView?
        private weak var bridge: XLEngineBridge?
        private var effectModelName: String?
        private var resolvedModelNames: Set<String> = []

        private var renderQueue = DispatchQueue(label: "sidebar.preview.render", qos: .utility)
        private var renderInProgress = false

        // Coalescing: defer heavy selection work during rapid-fire events (drag)
        private var pendingSelectionWork: DispatchWorkItem?
        private var isCleared = false

        /// Resolve a model/group name to the set of individual model names.
        private func resolveModelNames(_ name: String, bridge: XLEngineBridge) -> Set<String> {
            if let groupInfo = bridge.getModelGroup(name) as? [String: Any],
               let members = groupInfo["modelNames"] as? [String], !members.isEmpty {
                var result = Set<String>()
                for member in members {
                    result.formUnion(resolveModelNames(member, bridge: bridge))
                }
                return result
            }
            return [name]
        }

        func start(preview: XLMetalPreviewView, bridge: XLEngineBridge) {
            self.previewView = preview
            self.bridge = bridge
            self.frameTimeMS = max(Int(bridge.getFrameTimeMS()), 20)

            selectionObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("XLEffectSelectionDidChangeNotification"),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleSelectionChange(notification)
            }

            playbackStartObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("XLPlaybackDidStartNotification"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.playbackActive = true
                self?.stopPreviewLoop()
            }

            playbackStopObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("XLPlaybackDidStopNotification"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.playbackActive = false
                self.loopPositionMS = self.effectStartMS
                self.startPreviewLoopIfNeeded()
            }
        }

        private func handleSelectionChange(_ notification: Notification) {
            guard let preview = previewView, let bridge = bridge else { return }

            let effectId = (notification.userInfo?["effectId"] as? NSNumber)?.intValue ?? -1

            if effectId < 0 {
                // Deselection: clear immediately but skip if already cleared
                pendingSelectionWork?.cancel()
                pendingSelectionWork = nil
                if !isCleared {
                    stopPreviewLoop()
                    currentModelName = nil
                    effectModelName = nil
                    resolvedModelNames = []
                    preview.visibleModelFilter = nil
                    preview.clearRenderedPixels()
                    preview.reloadModels()
                    preview.setNeedsRender()
                    isCleared = true
                }
                return
            }

            // Coalesce rapid-fire selection events (e.g. during drag)
            pendingSelectionWork?.cancel()

            let work = DispatchWorkItem { [weak self] in
                self?.processSelection(effectId: effectId, bridge: bridge, preview: preview)
            }
            pendingSelectionWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: work)
        }

        private func processSelection(effectId: Int, bridge: XLEngineBridge, preview: XLMetalPreviewView) {
            guard self.previewView === preview else { return }

            guard let effectInfo = bridge.getEffect(effectId) as? [String: Any],
                  let modelName = effectInfo["modelName"] as? String, !modelName.isEmpty else {
                return
            }

            isCleared = false

            let startMS = (effectInfo["startTimeMS"] as? NSNumber)?.intValue ?? 0
            let endMS = (effectInfo["endTimeMS"] as? NSNumber)?.intValue ?? 0

            let modelChanged = modelName != currentModelName
            let rangeChanged = startMS != effectStartMS || endMS != effectEndMS

            currentModelName = modelName
            effectModelName = modelName
            effectStartMS = startMS
            effectEndMS = endMS
            loopPositionMS = startMS

            if modelChanged {
                resolvedModelNames = resolveModelNames(modelName, bridge: bridge)
                preview.visibleModelFilter = resolvedModelNames
                preview.reloadModels()
                preview.frameAllModels()
            }

            // Only restart the preview loop if the time range changed or no timer exists
            if rangeChanged || previewTimer == nil {
                startPreviewLoopIfNeeded()
            }
        }

        private func startPreviewLoopIfNeeded() {
            stopPreviewLoop()

            guard effectEndMS > effectStartMS else { return }

            let interval = TimeInterval(frameTimeMS) / 1000.0
            previewTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                self?.previewLoopTick()
            }
        }

        private func previewLoopTick() {
            guard let bridge = bridge, let preview = previewView else {
                stopPreviewLoop()
                return
            }

            // During playback, the playback controller feeds pixel data directly
            guard !playbackActive else { return }

            // Skip if a render is still in flight to prevent queue pile-up
            guard !renderInProgress else { return }

            let timeMS = loopPositionMS

            // Advance position for next tick, wrapping at effect end
            loopPositionMS += frameTimeMS
            if loopPositionMS >= effectEndMS {
                loopPositionMS = effectStartMS
            }

            let models = Array(resolvedModelNames)
            guard !models.isEmpty else { return }

            renderInProgress = true
            renderQueue.async { [weak self] in
                var buffers: [(String, [String: Any])] = []
                for name in models {
                    bridge.renderModelFrame(name, timeMS: Int(timeMS))
                    if let fb = bridge.getFrameBuffer(name) as? [String: Any] {
                        buffers.append((name, fb))
                    }
                }

                DispatchQueue.main.async {
                    guard let self else { return }
                    self.renderInProgress = false
                    guard self.previewView === preview else { return }

                    for (name, fb) in buffers {
                        if let pixels = fb["pixels"] as? Data,
                           let width = (fb["width"] as? NSNumber)?.uintValue,
                           let height = (fb["height"] as? NSNumber)?.uintValue,
                           pixels.count > 0, width > 0, height > 0 {
                            preview.setRenderedPixels(pixels, forModel: name,
                                                      width: UInt(width), height: UInt(height))
                        }
                    }
                    preview.updatePreview(forTime: Int(timeMS))
                }
            }
        }

        private func stopPreviewLoop() {
            previewTimer?.invalidate()
            previewTimer = nil
        }

        func stop() {
            stopPreviewLoop()
            if let observer = selectionObserver {
                NotificationCenter.default.removeObserver(observer)
                selectionObserver = nil
            }
            if let observer = playbackStartObserver {
                NotificationCenter.default.removeObserver(observer)
                playbackStartObserver = nil
            }
            if let observer = playbackStopObserver {
                NotificationCenter.default.removeObserver(observer)
                playbackStopObserver = nil
            }
        }

        deinit {
            stop()
        }
    }
}

// MARK: - Color Palette View (Placeholder)

// ColorPaletteView is now implemented in ColorPaletteView.swift
// LayerBlendingView is now implemented in LayerBlendingView.swift

// MARK: - Preview

#Preview {
    XLMainContentView(appState: XLAppState())
        .frame(width: 1400, height: 900)
}
