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

// MARK: - Layer Blending State

/// Observable state for layer blending settings.
/// Manages settings for the currently selected effect's layer.
@Observable
final class LayerBlendingState {
    /// Reference to the engine bridge
    weak var engineBridge: XLEngineBridge?

    /// The currently selected effect ID
    var selectedEffectId: Int?

    /// The layer index for multi-layer effects
    var layerIndex: Int = 0

    /// Whether settings are currently being loaded
    var isLoading: Bool = false

    // MARK: - Mix Settings
    var mixType: MixType = .normal
    var effectMixThreshold: Double = 0
    var layerMorph: Bool = false
    var canvas: Bool = false

    // MARK: - Color Adjustments
    var brightness: Double = 100
    var hueAdjust: Double = 0
    var saturationAdjust: Double = 0
    var valueAdjust: Double = 0
    var contrast: Double = 0
    var brightnessAsLevel: Bool = false

    // MARK: - Transitions
    var fadeIn: Double = 0
    var fadeOut: Double = 0
    var inTransitionType: TransitionType = .fade
    var outTransitionType: TransitionType = .fade
    var inTransitionAdjust: Double = 50
    var outTransitionAdjust: Double = 50
    var inTransitionReverse: Bool = false
    var outTransitionReverse: Bool = false

    // MARK: - Special Effects
    var sparkleFrequency: Int = 0
    var musicSparkles: Bool = false
    var chromaKey: Bool = false
    var chromaSensitivity: Double = 100
    var chromaColor: NSColor = .green

    // MARK: - State Control
    var freezeAtFrame: Int = 0
    var suppressUntil: Int = 0

    /// Combine cancellables for notification observation
    private var cancellables = Set<AnyCancellable>()

    init() {
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
            clearSelection()
            return
        }

        let effectId = effectIdNumber.intValue
        if effectId >= 0 {
            loadSettings(forEffectId: effectId)
        } else {
            clearSelection()
        }
    }

    func loadSettings(forEffectId effectId: Int) {
        selectedEffectId = effectId
        isLoading = true

        // TODO: Load actual settings from engine bridge
        // For now, use defaults

        isLoading = false
    }

    func clearSelection() {
        selectedEffectId = nil
        resetToDefaults()
    }

    func resetToDefaults() {
        mixType = .normal
        effectMixThreshold = 0
        layerMorph = false
        canvas = false

        brightness = 100
        hueAdjust = 0
        saturationAdjust = 0
        valueAdjust = 0
        contrast = 0
        brightnessAsLevel = false

        fadeIn = 0
        fadeOut = 0
        inTransitionType = .fade
        outTransitionType = .fade
        inTransitionAdjust = 50
        outTransitionAdjust = 50

        sparkleFrequency = 0
        musicSparkles = false
        chromaKey = false
        chromaSensitivity = 100
        chromaColor = .green

        freezeAtFrame = 0
        suppressUntil = 0
    }
}

// MARK: - Enums

enum MixType: String, CaseIterable, Identifiable {
    case normal = "Normal"
    case effect1 = "Effect 1"
    case effect2 = "Effect 2"
    case mask1 = "Mask 1"
    case mask2 = "Mask 2"
    case unmask1 = "Unmask 1"
    case unmask2 = "Unmask 2"
    case trueUnmask1 = "True Unmask 1"
    case trueUnmask2 = "True Unmask 2"
    case reveals1on2 = "1 Reveals 2"
    case reveals2on1 = "2 Reveals 1"
    case layered = "Layered"
    case average = "Average"
    case bottomTop = "Bottom-Top"
    case leftRight = "Left-Right"
    case shadow1on2 = "Shadow 1 on 2"
    case shadow2on1 = "Shadow 2 on 1"
    case additive = "Additive"
    case subtractive = "Subtractive"
    case asBrightness = "As Brightness"
    case max = "Max"
    case min = "Min"
    case highlight = "Highlight"
    case highlightVibrant = "Highlight Vibrant"

    var id: String { rawValue }
}

enum TransitionType: String, CaseIterable, Identifiable {
    case fade = "Fade"
    case wipe = "Wipe"
    case clock = "Clock"
    case fromMiddle = "From Middle"
    case square = "Square"
    case circleExplode = "Circle Explode"
    case circleImplode = "Circle Implode"
    case blinds = "Blinds"
    case blend = "Blend"
    case slideChecks = "Slide Checks"
    case slideChecksReverse = "Slide Checks Reverse"
    case slideBars = "Slide Bars"
    case slideBarsReverse = "Slide Bars Reverse"
    case fold = "Fold"
    case dissolve = "Dissolve"
    case circular = "Circular Swirl"
    case bowTie = "Bow Tie"
    case zoom = "Zoom"
    case doorway = "Doorway"
    case blobs = "Blobs"
    case pinwheel = "Pinwheel"
    case star = "Star"
    case shatter = "Shatter"

    var id: String { rawValue }
}

// BufferTransform and RotationOrder are defined in LayerSettingsView.swift

// MARK: - Layer Blending View

struct LayerBlendingView: View {
    let engineBridge: XLEngineBridge

    @State private var state = LayerBlendingState()

    @State private var mixSectionExpanded = true
    @State private var colorSectionExpanded = true
    @State private var transitionSectionExpanded = false
    @State private var specialSectionExpanded = false

    var body: some View {
        ScrollView {
            VStack(spacing: 1) {
                // Mix/Blending Section
                DisclosureSection(title: "Layer Blending", systemImage: "square.stack.3d.up", isExpanded: $mixSectionExpanded) {
                    mixSettingsContent
                }

                // Color Adjustments Section
                DisclosureSection(title: "Color Adjustments", systemImage: "paintpalette", isExpanded: $colorSectionExpanded) {
                    colorAdjustmentsContent
                }

                // Transitions Section
                DisclosureSection(title: "Transitions", systemImage: "arrow.left.arrow.right", isExpanded: $transitionSectionExpanded) {
                    transitionsContent
                }

                // Special Effects Section
                DisclosureSection(title: "Special Effects", systemImage: "sparkles", isExpanded: $specialSectionExpanded) {
                    specialEffectsContent
                }

                Spacer(minLength: 20)
            }
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: NSColor(white: 0.15, alpha: 1.0)))
        .onAppear {
            state.engineBridge = engineBridge
        }
    }

    // MARK: - Mix Settings Content

    private var mixSettingsContent: some View {
        VStack(spacing: 12) {
            // Mix Type
            LabeledPicker(label: "Mix Type", selection: $state.mixType) {
                ForEach(MixType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }

            // Effect Mix Threshold
            LabeledSlider(
                label: "Mix Threshold",
                value: $state.effectMixThreshold,
                range: 0...100,
                format: "%.0f%%"
            )

            // Checkboxes row
            HStack(spacing: 20) {
                Toggle("Layer Morph", isOn: $state.layerMorph)
                    .toggleStyle(.checkbox)
                Toggle("Canvas", isOn: $state.canvas)
                    .toggleStyle(.checkbox)
                Spacer()
            }
            .font(.system(size: 11))
        }
    }

    // MARK: - Color Adjustments Content

    private var colorAdjustmentsContent: some View {
        VStack(spacing: 10) {
            LabeledSlider(
                label: "Brightness",
                value: $state.brightness,
                range: 0...400,
                format: "%.0f%%"
            )

            LabeledSlider(
                label: "Hue Adjust",
                value: $state.hueAdjust,
                range: -100...100,
                format: "%.0f"
            )

            LabeledSlider(
                label: "Saturation",
                value: $state.saturationAdjust,
                range: -100...100,
                format: "%.0f"
            )

            LabeledSlider(
                label: "Value",
                value: $state.valueAdjust,
                range: -100...100,
                format: "%.0f"
            )

            LabeledSlider(
                label: "Contrast",
                value: $state.contrast,
                range: -100...100,
                format: "%.0f"
            )

            HStack {
                Toggle("Brightness as Level", isOn: $state.brightnessAsLevel)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                Spacer()
            }
        }
    }

    // MARK: - Transitions Content

    private var transitionsContent: some View {
        VStack(spacing: 12) {
            // Fade In/Out
            HStack(spacing: 16) {
                LabeledTextField(label: "Fade In", value: $state.fadeIn, format: "%.2f s", width: 60)
                LabeledTextField(label: "Fade Out", value: $state.fadeOut, format: "%.2f s", width: 60)
            }

            Divider().padding(.vertical, 4)

            // In Transition
            VStack(spacing: 8) {
                Text("In Transition")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                LabeledPicker(label: "Type", selection: $state.inTransitionType) {
                    ForEach(TransitionType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }

                LabeledSlider(
                    label: "Adjust",
                    value: $state.inTransitionAdjust,
                    range: 0...100,
                    format: "%.0f"
                )

                HStack {
                    Toggle("Reverse", isOn: $state.inTransitionReverse)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                    Spacer()
                }
            }

            Divider().padding(.vertical, 4)

            // Out Transition
            VStack(spacing: 8) {
                Text("Out Transition")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                LabeledPicker(label: "Type", selection: $state.outTransitionType) {
                    ForEach(TransitionType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }

                LabeledSlider(
                    label: "Adjust",
                    value: $state.outTransitionAdjust,
                    range: 0...100,
                    format: "%.0f"
                )

                HStack {
                    Toggle("Reverse", isOn: $state.outTransitionReverse)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                    Spacer()
                }
            }
        }
    }

    // MARK: - Special Effects Content

    private var specialEffectsContent: some View {
        VStack(spacing: 12) {
            // Sparkles
            Text("Sparkles")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            LabeledStepper(label: "Frequency", value: $state.sparkleFrequency, range: 0...200)

            HStack {
                Toggle("Music Sparkles", isOn: $state.musicSparkles)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                Spacer()
            }

            Divider().padding(.vertical, 4)

            // Chroma Key
            Text("Chroma Key")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Toggle("Enable", isOn: $state.chromaKey)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                Spacer()
            }

            if state.chromaKey {
                LabeledSlider(
                    label: "Sensitivity",
                    value: $state.chromaSensitivity,
                    range: 1...255,
                    format: "%.0f"
                )

                LabeledColorWell(label: "Color", color: $state.chromaColor)
            }

            Divider().padding(.vertical, 4)

            // State Control
            Text("State Control")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            LabeledStepper(label: "Freeze at Frame", value: $state.freezeAtFrame, range: 0...99999)
            LabeledStepper(label: "Suppress Until", value: $state.suppressUntil, range: 0...99999)
        }
    }
}

// MARK: - Reusable Components

struct DisclosureSection<Content: View>: View {
    let title: String
    let systemImage: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                        .frame(width: 16)

                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: NSColor(white: 0.2, alpha: 1.0)))
            }
            .buttonStyle(.plain)

            // Content
            if isExpanded {
                content()
                    .padding(12)
                    .background(Color(nsColor: NSColor(white: 0.17, alpha: 1.0)))
            }
        }
    }
}

struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    var divisor: Double = 1

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.primary)
                .frame(width: 80, alignment: .leading)

            Slider(value: $value, in: range)
                .controlSize(.small)

            Text(String(format: format, value / divisor))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .trailing)
        }
    }
}

struct LabeledPicker<SelectionValue: Hashable, Content: View>: View {
    let label: String
    @Binding var selection: SelectionValue
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.primary)
                .frame(width: 80, alignment: .leading)

            Picker("", selection: $selection) {
                content()
            }
            .labelsHidden()
            .controlSize(.small)
        }
    }
}

struct LabeledTextField: View {
    let label: String
    @Binding var value: Double
    let format: String
    var width: CGFloat = 80

    @State private var textValue: String = ""

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.primary)

            TextField("", text: $textValue)
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
                .controlSize(.small)
                .onAppear { textValue = String(format: "%.2f", value) }
                .onChange(of: value) { _, newValue in
                    textValue = String(format: "%.2f", newValue)
                }
                .onSubmit {
                    if let newValue = Double(textValue) {
                        value = newValue
                    }
                }
        }
    }
}

struct LabeledStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.primary)
                .frame(width: 80, alignment: .leading)

            Stepper(value: $value, in: range) {
                Text("\(value)")
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 50, alignment: .trailing)
            }
            .controlSize(.small)

            Spacer()
        }
    }
}

struct LabeledColorWell: View {
    let label: String
    @Binding var color: NSColor

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.primary)
                .frame(width: 80, alignment: .leading)

            ColorWellView(color: $color)
                .frame(width: 44, height: 22)

            Spacer()
        }
    }
}

struct ColorWellView: NSViewRepresentable {
    @Binding var color: NSColor

    func makeNSView(context: Context) -> NSColorWell {
        let colorWell = NSColorWell()
        colorWell.color = color
        colorWell.target = context.coordinator
        colorWell.action = #selector(Coordinator.colorChanged(_:))
        return colorWell
    }

    func updateNSView(_ nsView: NSColorWell, context: Context) {
        nsView.color = color
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: ColorWellView

        init(_ parent: ColorWellView) {
            self.parent = parent
        }

        @objc func colorChanged(_ sender: NSColorWell) {
            parent.color = sender.color
        }
    }
}

// MARK: - Preview

#Preview("Layer Blending Panel") {
    LayerBlendingView(engineBridge: XLEngineBridge())
        .frame(width: 320, height: 600)
}
