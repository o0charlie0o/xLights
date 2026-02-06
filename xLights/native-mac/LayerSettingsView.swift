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

// MARK: - Layer Settings View

/// Modern SwiftUI implementation of the Buffer/Layer Settings panel.
/// Provides controls for render style, transformations, blur, and roto-zoom effects.
/// Connected to the selected effect via EffectSelectionState.
struct LayerSettingsView: View {
    let engineBridge: XLEngineBridge
    @Bindable var effectSelectionState: EffectSelectionState

    @State private var selectedTab: LayerSettingsTab = .buffer

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(LayerSettingsTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider()

            // Tab content
            ScrollView {
                switch selectedTab {
                case .buffer:
                    BufferSettingsSection(state: effectSelectionState)
                case .rotoZoom:
                    RotoZoomSettingsSection(engineBridge: engineBridge)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Tab Enum

enum LayerSettingsTab: Int, CaseIterable, Identifiable {
    case buffer = 0
    case rotoZoom = 1

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .buffer: return "Buffer"
        case .rotoZoom: return "Roto-Zoom"
        }
    }
}

// MARK: - Buffer Settings Section

struct BufferSettingsSection: View {
    @Bindable var state: EffectSelectionState

    // Local @State mirrors for UI controls, synced with engine via onChange
    @State private var renderStyle: RenderStyle = .defaultStyle
    @State private var bufferStagger: Int = 0
    @State private var camera: String = "2D"
    @State private var transformation: BufferTransformation = .none
    @State private var blur: Double = 1
    @State private var overlayBackground: Bool = false

    // Prevents onChange handlers from writing back during programmatic loads
    @State private var isLoadingFromEngine: Bool = false

    private var hasSelection: Bool { state.selectedEffectId != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Render Style
            SettingsRow(label: "Render Style") {
                Picker("", selection: $renderStyle) {
                    ForEach(RenderStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .disabled(!hasSelection)
                .onChange(of: renderStyle) { _, newValue in
                    guard !isLoadingFromEngine else { return }
                    state.setParameter(key: "B_CHOICE_BufferStyle", value: newValue.settingsValue)
                }
            }

            // Buffer Stagger
            SettingsRow(label: "Buffer Stagger") {
                HStack(spacing: 4) {
                    TextField("", value: $bufferStagger, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .disabled(!hasSelection)
                        .onSubmit {
                            guard !isLoadingFromEngine else { return }
                            state.setParameter(key: "B_SPINCTRL_BufferStagger", value: "\(bufferStagger)")
                        }

                    Stepper("", value: $bufferStagger, in: -100...100)
                        .labelsHidden()
                        .disabled(!hasSelection)
                        .onChange(of: bufferStagger) { _, newValue in
                            guard !isLoadingFromEngine else { return }
                            state.setParameter(key: "B_SPINCTRL_BufferStagger", value: "\(newValue)")
                        }
                }
            }

            // Camera
            SettingsRow(label: "Camera") {
                Picker("", selection: $camera) {
                    Text("2D").tag("2D")
                    Text("3D").tag("3D")
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .disabled(!hasSelection)
                .onChange(of: camera) { _, newValue in
                    guard !isLoadingFromEngine else { return }
                    state.setParameter(key: "B_CHOICE_PerPreviewCamera", value: newValue)
                }
            }

            Divider()
                .padding(.vertical, 4)

            // Transformation
            SettingsRow(label: "Transformation") {
                Picker("", selection: $transformation) {
                    ForEach(BufferTransformation.allCases) { transform in
                        Text(transform.displayName).tag(transform)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .disabled(!hasSelection)
                .onChange(of: transformation) { _, newValue in
                    guard !isLoadingFromEngine else { return }
                    state.setParameter(key: "B_CHOICE_BufferTransform", value: newValue.settingsValue)
                }
            }

            Divider()
                .padding(.vertical, 4)

            // Blur
            SettingsRow(label: "Blur") {
                HStack(spacing: 8) {
                    Slider(value: $blur, in: 1...15, step: 1)
                        .disabled(!hasSelection)

                    Text("\(Int(blur))")
                        .frame(width: 30, alignment: .trailing)
                        .monospacedDigit()
                }
            }
            .onChange(of: blur) { _, newValue in
                guard !isLoadingFromEngine else { return }
                state.setParameter(key: "B_SLIDER_Blur", value: "\(Int(newValue))")
            }

            // Overlay Background
            Toggle("Overlay Background", isOn: $overlayBackground)
                .padding(.top, 4)
                .disabled(!hasSelection)
                .onChange(of: overlayBackground) { _, newValue in
                    guard !isLoadingFromEngine else { return }
                    state.setParameter(key: "B_CHECKBOX_OverlayBkg", value: newValue ? "1" : "0")
                }

            Spacer()
        }
        .padding(12)
        .onChange(of: state.selectedEffectId) { _, _ in
            loadFromState()
        }
        .onChange(of: state.parameters) { _, _ in
            loadFromState()
        }
        .onAppear {
            loadFromState()
        }
    }

    /// Load local UI state from EffectSelectionState.parameters
    private func loadFromState() {
        isLoadingFromEngine = true

        let params = state.parameters

        let styleStr = params["B_CHOICE_BufferStyle"] ?? "Default"
        renderStyle = RenderStyle(settingsValue: styleStr) ?? .defaultStyle

        bufferStagger = Int(params["B_SPINCTRL_BufferStagger"] ?? "0") ?? 0
        camera = params["B_CHOICE_PerPreviewCamera"] ?? "2D"

        let transformStr = params["B_CHOICE_BufferTransform"] ?? "None"
        transformation = BufferTransformation(settingsValue: transformStr) ?? .none

        blur = Double(Int(params["B_SLIDER_Blur"] ?? "1") ?? 1)
        overlayBackground = (params["B_CHECKBOX_OverlayBkg"] ?? "0") == "1"

        // Clear after the current run loop iteration so onChange handlers see the flag
        DispatchQueue.main.async {
            isLoadingFromEngine = false
        }
    }
}

// MARK: - Roto-Zoom Settings Section

struct RotoZoomSettingsSection: View {
    let engineBridge: XLEngineBridge

    @State private var preset: RotoZoomPreset = .none
    @State private var rotation: Double = 0
    @State private var rotations: Double = 0
    @State private var pivotPointX: Double = 50
    @State private var pivotPointY: Double = 50
    @State private var zoom: Double = 1.0
    @State private var zoomQuality: Double = 1
    @State private var xRotation: Double = 0
    @State private var xPivot: Double = 50
    @State private var yRotation: Double = 0
    @State private var yPivot: Double = 50
    @State private var rotationOrder: RotationOrder = .xyz

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Preset
            SettingsRow(label: "Preset") {
                Picker("", selection: $preset) {
                    ForEach(RotoZoomPreset.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .onChange(of: preset) { _, newValue in
                    applyPreset(newValue)
                }
            }

            Divider()
                .padding(.vertical, 4)

            // 2D Rotation Section
            Text("2D Rotation")
                .font(.headline)
                .foregroundColor(.secondary)

            // Rotation
            SliderRow(label: "Rotation", value: $rotation, range: 0...100, unit: "%")

            // Rotations (number of full rotations)
            SliderRow(label: "Rotations", value: $rotations, range: 0...20, unit: "x", decimals: 1)

            // Pivot Point X
            SliderRow(label: "Pivot X", value: $pivotPointX, range: 0...100, unit: "%")

            // Pivot Point Y
            SliderRow(label: "Pivot Y", value: $pivotPointY, range: 0...100, unit: "%")

            Divider()
                .padding(.vertical, 4)

            // Zoom Section
            Text("Zoom")
                .font(.headline)
                .foregroundColor(.secondary)

            // Zoom
            SliderRow(label: "Zoom", value: $zoom, range: 0...3, unit: "x", decimals: 1)

            // Zoom Quality
            SliderRow(label: "Quality", value: $zoomQuality, range: 1...10, step: 1, unit: "")

            Divider()
                .padding(.vertical, 4)

            // 3D Rotation Section
            Text("3D Rotation")
                .font(.headline)
                .foregroundColor(.secondary)

            // X Rotation
            SliderRow(label: "X Rotation", value: $xRotation, range: 0...360, unit: "°")

            // X Pivot
            SliderRow(label: "X Pivot", value: $xPivot, range: 0...100, unit: "%")

            // Y Rotation
            SliderRow(label: "Y Rotation", value: $yRotation, range: 0...360, unit: "°")

            // Y Pivot
            SliderRow(label: "Y Pivot", value: $yPivot, range: 0...100, unit: "%")

            // Rotation Order
            SettingsRow(label: "Rotation Order") {
                Picker("", selection: $rotationOrder) {
                    ForEach(RotationOrder.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            Spacer()
        }
        .padding(12)
    }

    private func applyPreset(_ preset: RotoZoomPreset) {
        switch preset {
        case .none:
            break
        case .rotateLeft:
            rotation = 0
            rotations = 1
            pivotPointX = 50
            pivotPointY = 50
        case .rotateRight:
            rotation = 100
            rotations = 1
            pivotPointX = 50
            pivotPointY = 50
        case .zoomIn:
            zoom = 2.0
            rotation = 0
            rotations = 0
        case .zoomOut:
            zoom = 0.5
            rotation = 0
            rotations = 0
        case .rotateAndZoom:
            rotation = 50
            rotations = 1
            zoom = 1.5
            pivotPointX = 50
            pivotPointY = 50
        }
    }
}

// MARK: - Helper Views

struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label)
                .frame(width: 100, alignment: .leading)
                .foregroundColor(.primary)

            content()
        }
    }
}

struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil  // Optional: only use step (with tick marks) when explicitly set
    var unit: String = ""
    var decimals: Int = 0

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 80, alignment: .leading)
                .foregroundColor(.primary)

            // Use step only when explicitly provided (shows tick marks)
            // Otherwise use continuous slider (no tick marks)
            if let step = step {
                Slider(value: $value, in: range, step: step)
            } else {
                Slider(value: $value, in: range)
            }

            Text(formattedValue)
                .frame(width: 50, alignment: .trailing)
                .monospacedDigit()
                .foregroundColor(.secondary)
        }
    }

    private var formattedValue: String {
        if decimals > 0 {
            return String(format: "%.\(decimals)f%@", value, unit)
        } else {
            return "\(Int(value))\(unit)"
        }
    }
}

// MARK: - Enums

enum RenderStyle: Int, CaseIterable, Identifiable {
    case defaultStyle = 0
    case perPreview = 1
    case perModelDefault = 2
    case perModelPerPreview = 3
    case singleLine = 4
    case asPixel = 5

    var id: Int { rawValue }

    /// Display name shown in the picker UI
    var displayName: String { settingsValue }

    /// The string value stored in effect settings (must match legacy xLights keys)
    var settingsValue: String {
        switch self {
        case .defaultStyle: return "Default"
        case .perPreview: return "Per Preview"
        case .perModelDefault: return "Per Model Default"
        case .perModelPerPreview: return "Per Model Per Preview"
        case .singleLine: return "Single Line"
        case .asPixel: return "As Pixel"
        }
    }

    init?(settingsValue: String) {
        switch settingsValue {
        case "Default", "": self = .defaultStyle
        case "Per Preview": self = .perPreview
        case "Per Model Default": self = .perModelDefault
        case "Per Model Per Preview": self = .perModelPerPreview
        case "Single Line": self = .singleLine
        case "As Pixel": self = .asPixel
        default: return nil
        }
    }
}

enum BufferTransformation: Int, CaseIterable, Identifiable {
    case none = 0
    case rotateCCW90 = 1
    case rotateCW90 = 2
    case rotate180 = 3
    case flipVertical = 4
    case flipHorizontal = 5
    case rotateCCW90FlipH = 6
    case rotateCW90FlipH = 7

    var id: Int { rawValue }

    /// Display name shown in the picker UI
    var displayName: String { settingsValue }

    /// The string value stored in effect settings (must match legacy xLights keys)
    var settingsValue: String {
        switch self {
        case .none: return "None"
        case .rotateCCW90: return "Rotate CC 90"
        case .rotateCW90: return "Rotate CW 90"
        case .rotate180: return "Rotate 180"
        case .flipVertical: return "Flip Vertical"
        case .flipHorizontal: return "Flip Horizontal"
        case .rotateCCW90FlipH: return "Rotate CC 90 Flip Horizontal"
        case .rotateCW90FlipH: return "Rotate CW 90 Flip Horizontal"
        }
    }

    init?(settingsValue: String) {
        switch settingsValue {
        case "None", "": self = .none
        case "Rotate CC 90": self = .rotateCCW90
        case "Rotate CW 90": self = .rotateCW90
        case "Rotate 180": self = .rotate180
        case "Flip Vertical": self = .flipVertical
        case "Flip Horizontal": self = .flipHorizontal
        case "Rotate CC 90 Flip Horizontal": self = .rotateCCW90FlipH
        case "Rotate CW 90 Flip Horizontal": self = .rotateCW90FlipH
        default: return nil
        }
    }
}

enum RotoZoomPreset: Int, CaseIterable, Identifiable {
    case none = 0
    case rotateLeft = 1
    case rotateRight = 2
    case zoomIn = 3
    case zoomOut = 4
    case rotateAndZoom = 5

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .rotateLeft: return "Rotate Left"
        case .rotateRight: return "Rotate Right"
        case .zoomIn: return "Zoom In"
        case .zoomOut: return "Zoom Out"
        case .rotateAndZoom: return "Rotate & Zoom"
        }
    }
}

enum RotationOrder: String, CaseIterable, Identifiable {
    case xyz = "X-Y-Z"
    case xzy = "X-Z-Y"
    case yxz = "Y-X-Z"
    case yzx = "Y-Z-X"
    case zxy = "Z-X-Y"
    case zyx = "Z-Y-X"

    var id: String { rawValue }
}

// MARK: - Preview

#Preview {
    let state = EffectSelectionState()
    LayerSettingsView(engineBridge: XLEngineBridge(), effectSelectionState: state)
        .frame(width: 350, height: 600)
}
