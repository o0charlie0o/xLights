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

// MARK: - Effect Selection State

/// Observable state for the currently selected effect.
/// This is the single source of truth for effect selection across the app.
@Observable
final class EffectSelectionState {
    /// The currently selected effect ID, or nil if no effect is selected
    var selectedEffectId: Int?

    /// The effect type name (e.g., "Bars", "Fire")
    var effectType: String?

    /// The effect's current parameters loaded from the engine
    var parameters: [String: String] = [:]

    /// Whether we're currently loading effect data
    var isLoading: Bool = false

    /// Reference to the engine bridge
    weak var engineBridge: XLEngineBridge?

    /// Combine cancellables for notification observation
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupNotificationObserver()
    }

    private func setupNotificationObserver() {
        // Listen for effect selection changes from the sequencer
        NotificationCenter.default.publisher(for: NSNotification.Name("XLEffectSelectionDidChangeNotification"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleEffectSelectionChange(notification)
            }
            .store(in: &cancellables)
    }

    private func handleEffectSelectionChange(_ notification: Notification) {
        print("EffectSelectionState: Received selection notification")
        guard let userInfo = notification.userInfo else {
            print("EffectSelectionState: No userInfo in notification")
            clearSelection()
            return
        }

        print("EffectSelectionState: userInfo = \(userInfo)")

        if let effectIdNumber = userInfo["effectId"] as? NSNumber {
            let effectId = effectIdNumber.intValue
            print("EffectSelectionState: effectId = \(effectId)")
            // effectId >= 0 is valid (0 can be a valid effect ID)
            // Use -1 as sentinel for "no selection"
            if effectId >= 0 {
                selectEffect(id: effectId)
            } else {
                clearSelection()
            }
        } else {
            print("EffectSelectionState: No effectId in userInfo")
            clearSelection()
        }
    }

    /// Select an effect by ID and load its data
    func selectEffect(id: Int) {
        guard let bridge = engineBridge else {
            print("EffectSelectionState: No engine bridge available")
            clearSelection()
            return
        }

        isLoading = true

        // Get effect info from engine
        guard let effectInfo = bridge.getEffect(id) as? [String: Any] else {
            print("EffectSelectionState: Effect \(id) not found")
            clearSelection()
            isLoading = false
            return
        }

        guard let effectType = effectInfo["effectType"] as? String, !effectType.isEmpty else {
            print("EffectSelectionState: Effect \(id) has no type")
            clearSelection()
            isLoading = false
            return
        }

        self.selectedEffectId = id
        self.effectType = effectType

        // Load parameter values
        loadParameters()

        isLoading = false
        print("EffectSelectionState: Selected effect \(id) (\(effectType))")
    }

    /// Clear the current selection
    func clearSelection() {
        selectedEffectId = nil
        effectType = nil
        parameters = [:]
        isLoading = false
    }

    /// Load parameter values from the engine
    private func loadParameters() {
        guard let bridge = engineBridge,
              let effectId = selectedEffectId,
              let effectType = effectType else {
            print("EffectSelectionState.loadParameters: missing bridge, effectId, or effectType")
            return
        }

        print("EffectSelectionState.loadParameters: Getting parameters for effect type '\(effectType)'")

        // Get parameter definitions for this effect type
        let rawParamDefs = bridge.getEffectParameters(effectType)
        print("EffectSelectionState.loadParameters: getEffectParameters returned: \(String(describing: rawParamDefs))")

        guard let paramDefs = rawParamDefs as? [[String: Any]] else {
            print("EffectSelectionState.loadParameters: Could not cast to [[String: Any]]")
            return
        }

        print("EffectSelectionState.loadParameters: Found \(paramDefs.count) parameter definitions")

        var newParams: [String: String] = [:]
        for paramDef in paramDefs {
            if let key = paramDef["key"] as? String {
                if let value = bridge.getEffectParameter(effectId, key: key) {
                    newParams[key] = value
                    print("EffectSelectionState.loadParameters: \(key) = \(value)")
                }
            }
        }
        parameters = newParams
        print("EffectSelectionState.loadParameters: Loaded \(newParams.count) parameters")
    }

    /// Update a parameter value
    func setParameter(key: String, value: String) {
        guard let bridge = engineBridge,
              let effectId = selectedEffectId else {
            return
        }

        if bridge.setEffectParameter(effectId, key: key, value: value) {
            parameters[key] = value
        }
    }
}

// MARK: - Effect Properties View

/// SwiftUI view displaying effect parameters for the selected effect.
struct EffectPropertiesView: View {
    @Bindable var state: EffectSelectionState

    var body: some View {
        VStack(spacing: 0) {
            if state.isLoading {
                loadingView
            } else if let effectType = state.effectType {
                effectPanelView(effectType: effectType)
            } else {
                placeholderView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: NSColor(white: 0.15, alpha: 1.0)))
    }

    // MARK: - Subviews

    private var placeholderView: some View {
        VStack {
            Spacer()
            Text("Select an effect")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Click on an effect in the timeline to edit its properties")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
            Text("Loading...")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)
            Spacer()
        }
    }

    private func effectPanelView(effectType: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(effectType)
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                if let effectId = state.selectedEffectId {
                    Text("ID: \(effectId)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: NSColor(white: 0.2, alpha: 1.0)))

            Divider()

            // Parameters scroll view
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if let paramDefs = getParameterDefinitions(for: effectType) {
                        ForEach(paramDefs, id: \.key) { param in
                            parameterRow(param: param)
                        }
                    } else {
                        Text("No parameters available")
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
                .padding(12)
            }
        }
    }

    private func parameterRow(param: ParameterDefinition) -> some View {
        HStack {
            Text(param.displayLabel)
                .font(.system(size: 11))
                .foregroundColor(.primary)
                .frame(width: 120, alignment: .leading)

            parameterControl(param: param)
        }
    }

    @ViewBuilder
    private func parameterControl(param: ParameterDefinition) -> some View {
        let currentValue = state.parameters[param.key] ?? param.defaultValue

        switch param.type {
        case .int, .float:
            sliderControl(param: param, currentValue: currentValue)

        case .bool:
            Toggle("", isOn: Binding(
                get: { currentValue == "1" || currentValue.lowercased() == "true" },
                set: { newValue in
                    state.setParameter(key: param.key, value: newValue ? "1" : "0")
                }
            ))
            .labelsHidden()

        case .choice:
            if let choices = param.choices {
                Picker("", selection: Binding(
                    get: { currentValue },
                    set: { newValue in
                        state.setParameter(key: param.key, value: newValue)
                    }
                )) {
                    ForEach(choices, id: \.self) { choice in
                        Text(choice).tag(choice)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 150)
            }

        case .string:
            TextField("", text: Binding(
                get: { currentValue },
                set: { newValue in
                    state.setParameter(key: param.key, value: newValue)
                }
            ))
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .frame(maxWidth: 150)

        default:
            Text(currentValue)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    private func sliderControl(param: ParameterDefinition, currentValue: String) -> some View {
        let doubleValue = Double(currentValue) ?? param.minValue

        return HStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { doubleValue },
                    set: { newValue in
                        let stringValue = param.type == .int
                            ? String(Int(newValue))
                            : String(format: "%.2f", newValue)
                        state.setParameter(key: param.key, value: stringValue)
                    }
                ),
                in: param.minValue...param.maxValue
            )
            .frame(maxWidth: 120)

            Text(param.type == .int ? String(Int(doubleValue)) : String(format: "%.1f", doubleValue))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    // MARK: - Helper Methods

    private func getParameterDefinitions(for effectType: String) -> [ParameterDefinition]? {
        guard let bridge = state.engineBridge,
              let paramDicts = bridge.getEffectParameters(effectType) as? [[String: Any]] else {
            return nil
        }

        return paramDicts.compactMap { dict -> ParameterDefinition? in
            guard let key = dict["key"] as? String else { return nil }

            let displayLabel = dict["displayLabel"] as? String ?? key
            let typeString = dict["type"] as? String ?? "string"
            let type = ParameterType(rawValue: typeString) ?? .string
            let minValue = dict["minValue"] as? Double ?? 0
            let maxValue = dict["maxValue"] as? Double ?? 100
            let defaultValue = dict["defaultValue"] as? String ?? "0"
            let choices = dict["choices"] as? [String]

            return ParameterDefinition(
                key: key,
                displayLabel: displayLabel,
                type: type,
                minValue: minValue,
                maxValue: maxValue,
                defaultValue: defaultValue,
                choices: choices
            )
        }
    }
}

// MARK: - Supporting Types

struct ParameterDefinition: Identifiable {
    var id: String { key }

    let key: String
    let displayLabel: String
    let type: ParameterType
    let minValue: Double
    let maxValue: Double
    let defaultValue: String
    let choices: [String]?
}

enum ParameterType: String {
    case int = "int"
    case float = "float"
    case bool = "bool"
    case choice = "choice"
    case color = "color"
    case string = "string"
    case file = "file"
    case font = "font"
}

// MARK: - Preview

#Preview {
    let state = EffectSelectionState()
    state.effectType = "Bars"
    state.selectedEffectId = 1

    return EffectPropertiesView(state: state)
        .frame(width: 400, height: 300)
}
