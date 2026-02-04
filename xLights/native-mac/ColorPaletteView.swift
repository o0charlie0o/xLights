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
import Combine

// MARK: - Color Palette Constants

private let kPaletteSize = 8

// MARK: - Palette Color Model

/// Represents a single color in the 8-color palette
struct PaletteColor: Identifiable {
    let id: Int
    var color: Color
    var isEnabled: Bool
    var isLocked: Bool
    var isGradient: Bool
    var gradientColors: [Color]

    init(id: Int, color: Color = .red, isEnabled: Bool = true, isLocked: Bool = false) {
        self.id = id
        self.color = color
        self.isEnabled = isEnabled
        self.isLocked = isLocked
        self.isGradient = false
        self.gradientColors = []
    }

    /// Convert to hex string for serialization
    var hexString: String {
        let nsColor = NSColor(color)
        guard let rgb = nsColor.usingColorSpace(.sRGB) else { return "#FFFFFF" }
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// Create from hex string
    static func fromHex(_ hex: String) -> Color {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        return Color(red: r, green: g, blue: b)
    }
}

// MARK: - Color Palette State

/// Observable state for the color palette
@Observable
final class ColorPaletteState {
    /// The 8 palette colors
    var colors: [PaletteColor] = []

    /// Brightness (0-400, default 100)
    var brightness: Double = 100

    /// Contrast (0-100, default 0)
    var contrast: Double = 0

    /// Hue adjustment (-100 to 100)
    var hueAdjust: Double = 0

    /// Saturation adjustment (-100 to 100)
    var saturationAdjust: Double = 0

    /// Value/brightness adjustment (-100 to 100)
    var valueAdjust: Double = 0

    /// Sparkle frequency (0-200)
    var sparkleFrequency: Double = 0

    /// Music sparkles enabled
    var musicSparkles: Bool = false

    /// Reference to the engine bridge
    weak var engineBridge: XLEngineBridge?

    /// Currently selected effect ID
    var selectedEffectId: Int?

    /// Combine cancellables
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Initialize with default colors
        let defaultColors: [Color] = [
            .red, .green, .blue, .yellow,
            Color(red: 0, green: 1, blue: 1), // cyan
            Color(red: 1, green: 0, blue: 1), // magenta
            .orange, .purple
        ]

        colors = (0..<kPaletteSize).map { index in
            var paletteColor = PaletteColor(id: index, color: defaultColors[index])
            // Only first 2 colors enabled by default
            paletteColor.isEnabled = index < 2
            return paletteColor
        }

        setupNotificationObserver()
    }

    private func setupNotificationObserver() {
        // Listen for effect selection changes
        NotificationCenter.default.publisher(for: NSNotification.Name("XLEffectSelectionDidChangeNotification"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleEffectSelectionChange(notification)
            }
            .store(in: &cancellables)
    }

    private func handleEffectSelectionChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let effectIdNumber = userInfo["effectId"] as? NSNumber else {
            selectedEffectId = nil
            return
        }

        let effectId = effectIdNumber.intValue
        if effectId >= 0 {
            selectedEffectId = effectId
            loadColorsFromEffect()
        } else {
            selectedEffectId = nil
        }
    }

    /// Load color settings from the currently selected effect
    func loadColorsFromEffect() {
        guard let bridge = engineBridge,
              let effectId = selectedEffectId else { return }

        // Load palette colors
        for i in 0..<kPaletteSize {
            let colorKey = "C_BUTTON_Palette\(i + 1)"
            let enableKey = "C_CHECKBOX_Palette\(i + 1)"

            if let colorValue = bridge.getEffectParameter(effectId, key: colorKey) {
                colors[i].color = PaletteColor.fromHex(colorValue)
            }

            if let enableValue = bridge.getEffectParameter(effectId, key: enableKey) {
                colors[i].isEnabled = enableValue == "1"
            }
        }

        // Load adjustment values
        if let brightnessValue = bridge.getEffectParameter(effectId, key: "C_SLIDER_Brightness") {
            brightness = Double(brightnessValue) ?? 100
        }

        if let contrastValue = bridge.getEffectParameter(effectId, key: "C_SLIDER_Contrast") {
            contrast = Double(contrastValue) ?? 0
        }

        if let hueValue = bridge.getEffectParameter(effectId, key: "C_SLIDER_Color_HueAdjust") {
            hueAdjust = Double(hueValue) ?? 0
        }

        if let satValue = bridge.getEffectParameter(effectId, key: "C_SLIDER_Color_SaturationAdjust") {
            saturationAdjust = Double(satValue) ?? 0
        }

        if let valValue = bridge.getEffectParameter(effectId, key: "C_SLIDER_Color_ValueAdjust") {
            valueAdjust = Double(valValue) ?? 0
        }

        if let sparkleValue = bridge.getEffectParameter(effectId, key: "C_SLIDER_SparkleFrequency") {
            sparkleFrequency = Double(sparkleValue) ?? 0
        }
    }

    /// Update a color in the palette
    func setColor(at index: Int, color: Color) {
        guard index >= 0 && index < kPaletteSize else { return }
        guard !colors[index].isLocked else { return }

        colors[index].color = color

        // Update in engine
        if let bridge = engineBridge, let effectId = selectedEffectId {
            let key = "C_BUTTON_Palette\(index + 1)"
            let hexValue = colors[index].hexString
            bridge.setEffectParameter(effectId, key: key, value: hexValue)
        }
    }

    /// Toggle color enabled state
    func toggleEnabled(at index: Int) {
        guard index >= 0 && index < kPaletteSize else { return }

        colors[index].isEnabled.toggle()

        // Update in engine
        if let bridge = engineBridge, let effectId = selectedEffectId {
            let key = "C_CHECKBOX_Palette\(index + 1)"
            bridge.setEffectParameter(effectId, key: key, value: colors[index].isEnabled ? "1" : "0")
        }
    }

    /// Toggle color locked state
    func toggleLocked(at index: Int) {
        guard index >= 0 && index < kPaletteSize else { return }
        colors[index].isLocked.toggle()
    }

    /// Update brightness
    func setBrightness(_ value: Double) {
        brightness = value
        if let bridge = engineBridge, let effectId = selectedEffectId {
            bridge.setEffectParameter(effectId, key: "C_SLIDER_Brightness", value: String(Int(value)))
        }
    }

    /// Update contrast
    func setContrast(_ value: Double) {
        contrast = value
        if let bridge = engineBridge, let effectId = selectedEffectId {
            bridge.setEffectParameter(effectId, key: "C_SLIDER_Contrast", value: String(Int(value)))
        }
    }

    /// Update hue adjustment
    func setHueAdjust(_ value: Double) {
        hueAdjust = value
        if let bridge = engineBridge, let effectId = selectedEffectId {
            bridge.setEffectParameter(effectId, key: "C_SLIDER_Color_HueAdjust", value: String(Int(value)))
        }
    }

    /// Update saturation adjustment
    func setSaturationAdjust(_ value: Double) {
        saturationAdjust = value
        if let bridge = engineBridge, let effectId = selectedEffectId {
            bridge.setEffectParameter(effectId, key: "C_SLIDER_Color_SaturationAdjust", value: String(Int(value)))
        }
    }

    /// Update value adjustment
    func setValueAdjust(_ value: Double) {
        valueAdjust = value
        if let bridge = engineBridge, let effectId = selectedEffectId {
            bridge.setEffectParameter(effectId, key: "C_SLIDER_Color_ValueAdjust", value: String(Int(value)))
        }
    }

    /// Reset all adjustments to defaults
    func resetAdjustments() {
        brightness = 100
        contrast = 0
        hueAdjust = 0
        saturationAdjust = 0
        valueAdjust = 0

        if let bridge = engineBridge, let effectId = selectedEffectId {
            bridge.setEffectParameter(effectId, key: "C_SLIDER_Brightness", value: "100")
            bridge.setEffectParameter(effectId, key: "C_SLIDER_Contrast", value: "0")
            bridge.setEffectParameter(effectId, key: "C_SLIDER_Color_HueAdjust", value: "0")
            bridge.setEffectParameter(effectId, key: "C_SLIDER_Color_SaturationAdjust", value: "0")
            bridge.setEffectParameter(effectId, key: "C_SLIDER_Color_ValueAdjust", value: "0")
        }
    }
}

// MARK: - Color Palette View

/// Main color palette view
struct ColorPaletteView: View {
    @Bindable var state: ColorPaletteState
    @State private var expandedSections: Set<String> = ["palette", "brightness", "hsv"]

    /// Initialize with an engine bridge (creates internal state)
    init(engineBridge: XLEngineBridge?) {
        let newState = ColorPaletteState()
        newState.engineBridge = engineBridge
        self.state = newState
    }

    /// Initialize with existing state
    init(state: ColorPaletteState) {
        self.state = state
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Palette Colors Section
                CollapsibleSection(title: "Palette Colors", isExpanded: expandedSections.contains("palette")) {
                    paletteColorsGrid
                }
                .onTapGesture {
                    toggleSection("palette")
                }

                // Brightness & Contrast Section
                CollapsibleSection(title: "Brightness & Contrast", isExpanded: expandedSections.contains("brightness")) {
                    brightnessContrastControls
                }
                .onTapGesture {
                    toggleSection("brightness")
                }

                // HSV Adjustments Section
                CollapsibleSection(title: "Color Adjustments", isExpanded: expandedSections.contains("hsv")) {
                    hsvControls
                }
                .onTapGesture {
                    toggleSection("hsv")
                }

                // Sparkles Section
                CollapsibleSection(title: "Sparkles", isExpanded: expandedSections.contains("sparkles")) {
                    sparkleControls
                }
                .onTapGesture {
                    toggleSection("sparkles")
                }

                Spacer()
            }
            .padding(12)
        }
        .background(Color(nsColor: NSColor(white: 0.15, alpha: 1.0)))
    }

    private func toggleSection(_ section: String) {
        if expandedSections.contains(section) {
            expandedSections.remove(section)
        } else {
            expandedSections.insert(section)
        }
    }

    // MARK: - Palette Colors Grid

    private var paletteColorsGrid: some View {
        VStack(spacing: 8) {
            // First row (colors 1-4)
            HStack(spacing: 8) {
                ForEach(0..<4) { index in
                    PaletteColorCell(
                        paletteColor: state.colors[index],
                        onColorChange: { color in
                            state.setColor(at: index, color: color)
                        },
                        onToggleEnabled: {
                            state.toggleEnabled(at: index)
                        },
                        onToggleLocked: {
                            state.toggleLocked(at: index)
                        }
                    )
                }
            }

            // Second row (colors 5-8)
            HStack(spacing: 8) {
                ForEach(4..<8) { index in
                    PaletteColorCell(
                        paletteColor: state.colors[index],
                        onColorChange: { color in
                            state.setColor(at: index, color: color)
                        },
                        onToggleEnabled: {
                            state.toggleEnabled(at: index)
                        },
                        onToggleLocked: {
                            state.toggleLocked(at: index)
                        }
                    )
                }
            }
        }
    }

    // MARK: - Brightness & Contrast Controls

    private var brightnessContrastControls: some View {
        VStack(spacing: 12) {
            ColorLabeledSlider(
                label: "Brightness",
                value: Binding(
                    get: { state.brightness },
                    set: { state.setBrightness($0) }
                ),
                range: 0...400,
                defaultValue: 100
            )

            ColorLabeledSlider(
                label: "Contrast",
                value: Binding(
                    get: { state.contrast },
                    set: { state.setContrast($0) }
                ),
                range: 0...100,
                defaultValue: 0
            )
        }
    }

    // MARK: - HSV Controls

    private var hsvControls: some View {
        VStack(spacing: 12) {
            ColorLabeledSlider(
                label: "Hue",
                value: Binding(
                    get: { state.hueAdjust },
                    set: { state.setHueAdjust($0) }
                ),
                range: -100...100,
                defaultValue: 0
            )

            ColorLabeledSlider(
                label: "Saturation",
                value: Binding(
                    get: { state.saturationAdjust },
                    set: { state.setSaturationAdjust($0) }
                ),
                range: -100...100,
                defaultValue: 0
            )

            ColorLabeledSlider(
                label: "Value",
                value: Binding(
                    get: { state.valueAdjust },
                    set: { state.setValueAdjust($0) }
                ),
                range: -100...100,
                defaultValue: 0
            )

            Button("Reset All") {
                state.resetAdjustments()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Sparkle Controls

    private var sparkleControls: some View {
        VStack(spacing: 12) {
            ColorLabeledSlider(
                label: "Frequency",
                value: Binding(
                    get: { state.sparkleFrequency },
                    set: { newValue in
                        state.sparkleFrequency = newValue
                        if let bridge = state.engineBridge, let effectId = state.selectedEffectId {
                            bridge.setEffectParameter(effectId, key: "C_SLIDER_SparkleFrequency", value: String(Int(newValue)))
                        }
                    }
                ),
                range: 0...200,
                defaultValue: 0
            )

            Toggle("Music Sparkles", isOn: Binding(
                get: { state.musicSparkles },
                set: { newValue in
                    state.musicSparkles = newValue
                    if let bridge = state.engineBridge, let effectId = state.selectedEffectId {
                        bridge.setEffectParameter(effectId, key: "C_CHECKBOX_MusicSparkles", value: newValue ? "1" : "0")
                    }
                }
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: 11))
        }
    }
}

// MARK: - Palette Color Cell

/// Individual color cell in the palette grid
struct PaletteColorCell: View {
    let paletteColor: PaletteColor
    let onColorChange: (Color) -> Void
    let onToggleEnabled: () -> Void
    let onToggleLocked: () -> Void

    @State private var showingColorPicker = false

    var body: some View {
        VStack(spacing: 4) {
            // Color index label
            Text("\(paletteColor.id + 1)")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)

            // Color swatch button
            Button {
                if !paletteColor.isLocked {
                    showingColorPicker = true
                }
            } label: {
                RoundedRectangle(cornerRadius: 4)
                    .fill(paletteColor.color)
                    .frame(width: 44, height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(
                                paletteColor.isEnabled ? Color.white.opacity(0.5) : Color.gray.opacity(0.3),
                                lineWidth: paletteColor.isEnabled ? 2 : 1
                            )
                    )
                    .opacity(paletteColor.isEnabled ? 1.0 : 0.4)
                    .overlay(
                        // Lock icon overlay
                        Group {
                            if paletteColor.isLocked {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white)
                                    .shadow(radius: 1)
                            }
                        }
                    )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingColorPicker) {
                ColorPickerPopover(
                    color: paletteColor.color,
                    onColorChange: onColorChange
                )
            }

            // Enable/Disable checkbox
            HStack(spacing: 2) {
                Button {
                    onToggleEnabled()
                } label: {
                    Image(systemName: paletteColor.isEnabled ? "checkmark.square.fill" : "square")
                        .font(.system(size: 12))
                        .foregroundColor(paletteColor.isEnabled ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)

                Button {
                    onToggleLocked()
                } label: {
                    Image(systemName: paletteColor.isLocked ? "lock.fill" : "lock.open")
                        .font(.system(size: 10))
                        .foregroundColor(paletteColor.isLocked ? .orange : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Color Picker Popover

/// Color picker popover with system color picker
struct ColorPickerPopover: View {
    let color: Color
    let onColorChange: (Color) -> Void

    @State private var selectedColor: Color
    @Environment(\.dismiss) private var dismiss

    init(color: Color, onColorChange: @escaping (Color) -> Void) {
        self.color = color
        self.onColorChange = onColorChange
        _selectedColor = State(initialValue: color)
    }

    var body: some View {
        VStack(spacing: 12) {
            ColorPicker("", selection: $selectedColor, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 200, height: 200)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Apply") {
                    onColorChange(selectedColor)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

// MARK: - Collapsible Section

/// Collapsible section header with disclosure indicator
struct CollapsibleSection<Content: View>: View {
    let title: String
    let isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 12)

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(nsColor: NSColor(white: 0.2, alpha: 1.0)))
            .cornerRadius(4)

            // Content
            if isExpanded {
                content()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: NSColor(white: 0.18, alpha: 1.0)))
                    .cornerRadius(4)
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: - Labeled Slider

/// Slider with label and value display
struct ColorLabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)

                Spacer()

                Text(String(format: "%.0f", value))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 35, alignment: .trailing)

                // Reset to default button
                Button {
                    value = defaultValue
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(value != defaultValue ? 1.0 : 0.3)
            }

            Slider(value: $value, in: range)
                .controlSize(.small)
        }
    }
}

// MARK: - NSViewRepresentable for hosting in AppKit

/// Hosts the ColorPaletteView in an NSView for integration with AppKit
@objc(ColorPaletteHostingView)
@objcMembers
class ColorPaletteHostingView: NSView {
    private var hostingView: NSHostingView<ColorPaletteView>?
    private let state = ColorPaletteState()

    @objc var engineBridge: XLEngineBridge? {
        didSet {
            state.engineBridge = engineBridge
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupHostingView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupHostingView()
    }

    private func setupHostingView() {
        let swiftUIView = ColorPaletteView(state: state)
        let hosting = NSHostingView(rootView: swiftUIView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)

        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        hostingView = hosting
    }

    /// Reload colors from the current effect
    @objc func reloadColors() {
        state.loadColorsFromEffect()
    }
}

// MARK: - Preview

#Preview {
    ColorPaletteView(state: ColorPaletteState())
        .frame(width: 300, height: 600)
}
