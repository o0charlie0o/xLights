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

    // Top panel visibility - each panel can be toggled independently
    var visibleTopPanels: Set<XLTopPanelTab> = [.effects, .colors, .layerBlending, .layerSettings]

    // Persisted sizes for split views
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

    // Shared engine bridge - created once, passed to all view controllers
    let engineBridge: XLEngineBridge

    // Effect selection state - shared across sequencer and properties panel
    let effectSelectionState: EffectSelectionState

    // Computed property for whether any top panel is visible
    var topPanelVisible: Bool {
        !visibleTopPanels.isEmpty
    }

    init() {
        engineBridge = XLEngineBridge()
        effectSelectionState = EffectSelectionState()
        effectSelectionState.engineBridge = engineBridge
        loadState()
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
        if defaults.object(forKey: "XLInspectorWidth") != nil {
            inspectorWidth = defaults.double(forKey: "XLInspectorWidth")
        }
        if defaults.object(forKey: "XLTopPanelHeight") != nil {
            topPanelHeight = defaults.double(forKey: "XLTopPanelHeight")
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
        defaults.set(inspectorWidth, forKey: "XLInspectorWidth")
        defaults.set(topPanelHeight, forKey: "XLTopPanelHeight")
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

    // Split view column visibility
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        ZStack {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                // Sidebar: Tab selection (could add more sidebar items later)
                sidebarContent
            } detail: {
                // Detail: Main content area with inspector
                // Using HStack with explicit frame control instead of HSplitView
                // to avoid SwiftUI split view bugs when toggling panels
                HStack(spacing: 0) {
                    // Main content + top panel (at top, like regular xLights)
                    mainContentWithTopPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Inspector (right side) - always in hierarchy but zero-width when hidden
                    // Layout tab has its own properties panel in its split view, so hide the global inspector
                    if appState.inspectorVisible && appState.currentTab != .layout {
                        Divider()
                        inspectorPanel
                            .frame(width: appState.inspectorWidth)
                    }
                }
            }
            .navigationSplitViewStyle(.balanced)
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
        // - Layout tab has its own properties panel in its split view
        // - Otherwise: show general inspector
        if appState.currentTab == .sequencer {
            EffectPropertiesView(state: appState.effectSelectionState)
        } else if appState.currentTab == .layout {
            EmptyView()
        } else {
            XLInspectorView(engineBridge: appState.engineBridge)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
                XLSwiftUIWindowHelper.shared.sequencerViewController?.renderAll()
            } label: {
                RenderProgressRing(
                    isRendering: appState.isRendering,
                    progress: appState.renderProgress
                )
            }
            .help("Render All")
        }

        // Panel toggles on the right
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                XLCommandPaletteState.shared.toggle()
            } label: {
                Label("Command Palette", systemImage: "command")
            }
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

            Button {
                XLSwiftUIWindowHelper.shared.toggleHousePreview()
            } label: {
                Label("Preview", systemImage: "eye.fill")
            }
            .help("House Preview (⇧⌘P)")

            Button {
                appState.inspectorVisible.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
        }
    }
}

// MARK: - Render Progress Ring

/// A circular progress indicator for the toolbar render button.
/// Shows a gear icon when idle, an animated spinning ring when rendering
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
                Image(systemName: "gearshape.fill")
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

// MARK: - Color Palette View (Placeholder)

// ColorPaletteView is now implemented in ColorPaletteView.swift
// LayerBlendingView is now implemented in LayerBlendingView.swift

// MARK: - Preview

#Preview {
    XLMainContentView(appState: XLAppState())
        .frame(width: 1400, height: 900)
}
