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

/// Observable state for the currently selected effect(s).
/// This is the single source of truth for effect selection across the app.
/// Supports both single selection and bulk (multi-) selection.
@Observable
final class EffectSelectionState {
    /// The primary selected effect ID, or nil if no effect is selected
    var selectedEffectId: Int?

    /// The primary effect type name (e.g., "Bars", "Fire")
    var effectType: String?

    /// All selected effect IDs (for multi-selection)
    var selectedEffectIds: [Int] = []

    /// Effect types for all selected effects (in same order as selectedEffectIds)
    var selectedEffectTypes: [String] = []

    /// The effect's current parameters loaded from the engine (for single selection)
    var parameters: [String: String] = [:]

    /// Whether we're in bulk edit mode (multiple effects selected)
    var isBulkMode: Bool { selectedEffectIds.count > 1 }

    /// Number of selected effects
    var selectionCount: Int { selectedEffectIds.count }

    /// Common effect types across all selected effects (for bulk mode)
    var commonEffectTypes: Set<String> {
        Set(selectedEffectTypes)
    }

    /// Whether all selected effects are the same type
    var allSameType: Bool { commonEffectTypes.count == 1 }

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
        guard let userInfo = notification.userInfo else {
            clearSelection()
            return
        }

        // Extract multi-selection arrays
        let effectIds = (userInfo["selectedEffectIds"] as? [NSNumber])?.map { $0.intValue } ?? []
        let effectTypes = (userInfo["selectedEffectTypes"] as? [String]) ?? []

        // Update multi-selection state
        selectedEffectIds = effectIds.filter { $0 >= 0 }
        selectedEffectTypes = effectTypes.filter { !$0.isEmpty }

        // Extract primary selection
        if let effectIdNumber = userInfo["effectId"] as? NSNumber {
            let effectId = effectIdNumber.intValue

            // effectId >= 0 is valid (0 can be a valid effect ID)
            // Use -1 as sentinel for "no selection"
            if effectId >= 0 {
                selectEffect(id: effectId)
            } else {
                clearSelection()
            }
        } else {
            clearSelection()
        }
    }

    /// Select an effect by ID and load its data
    func selectEffect(id: Int) {
        guard let bridge = engineBridge else {
            clearSelection()
            return
        }

        isLoading = true

        // Get effect info from engine
        guard let rawResult = bridge.getEffect(id),
              let effectInfo = rawResult as? [String: Any],
              let effectType = effectInfo["effectType"] as? String, !effectType.isEmpty else {
            clearSelection()
            isLoading = false
            return
        }

        self.selectedEffectId = id
        self.effectType = effectType

        // Load parameter values (only for single selection or bulk edit of same type)
        if !isBulkMode || allSameType {
            loadParameters()
        } else {
            parameters = [:]
        }

        isLoading = false
    }

    /// Clear the current selection
    func clearSelection() {
        selectedEffectId = nil
        effectType = nil
        selectedEffectIds = []
        selectedEffectTypes = []
        parameters = [:]
        isLoading = false
    }

    /// Load parameter values from the engine
    private func loadParameters() {
        guard let bridge = engineBridge,
              let effectId = selectedEffectId,
              let effectType = effectType else {
            return
        }

        // Get parameter definitions for this effect type
        guard let paramDefs = bridge.getEffectParameters(effectType) as? [[String: Any]] else {
            return
        }

        var newParams: [String: String] = [:]
        for paramDef in paramDefs {
            if let key = paramDef["key"] as? String {
                if let value = bridge.getEffectParameter(effectId, key: key) {
                    newParams[key] = value
                }
            }
        }

        // Also load buffer/layer settings (B_ prefixed keys)
        let bufferKeys = [
            "B_CHOICE_BufferStyle",
            "B_CHOICE_BufferTransform",
            "B_SPINCTRL_BufferStagger",
            "B_CHOICE_PerPreviewCamera",
            "B_SLIDER_Blur",
            "B_CHECKBOX_OverlayBkg"
        ]
        for key in bufferKeys {
            if let value = bridge.getEffectParameter(effectId, key: key) {
                newParams[key] = value
            }
        }

        parameters = newParams
    }

    /// Update a parameter value for single selection or all selected effects in bulk mode
    func setParameter(key: String, value: String) {
        guard let bridge = engineBridge else { return }

        if isBulkMode {
            // Apply to all selected effects
            for effectId in selectedEffectIds {
                _ = bridge.setEffectParameter(effectId, key: key, value: value)
            }
            parameters[key] = value
        } else if let effectId = selectedEffectId {
            // Single selection
            if bridge.setEffectParameter(effectId, key: key, value: value) {
                parameters[key] = value
            }
        }
    }

    /// Delete all selected effects
    func deleteSelectedEffects() -> Bool {
        guard let bridge = engineBridge, !selectedEffectIds.isEmpty else { return false }

        for effectId in selectedEffectIds {
            _ = bridge.deleteEffect(effectId)
        }

        clearSelection()
        return true
    }
}

// MARK: - Effect Properties View

/// SwiftUI view displaying effect parameters for the selected effect.
/// Supports both single selection and bulk (multi-) selection editing.
struct EffectPropertiesView: View {
    @Bindable var state: EffectSelectionState
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            if state.isLoading {
                loadingView
            } else if state.isBulkMode {
                bulkEditView
            } else if let effectType = state.effectType {
                effectPanelView(effectType: effectType)
            } else {
                placeholderView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: NSColor(white: 0.15, alpha: 1.0)))
        .alert("Delete Selected Effects?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                _ = state.deleteSelectedEffects()
                // Post notification to trigger grid reload
                NotificationCenter.default.post(
                    name: NSNotification.Name("XLEffectsDidDeleteNotification"),
                    object: nil
                )
            }
        } message: {
            Text("Are you sure you want to delete \(state.selectionCount) effect\(state.selectionCount == 1 ? "" : "s")? This action cannot be undone.")
        }
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

    // MARK: - Bulk Edit View

    private var bulkEditView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header showing selection count
            HStack {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundColor(.accentColor)
                Text("\(state.selectionCount) effects selected")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: NSColor(white: 0.2, alpha: 1.0)))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Effect types summary
                    effectTypesSummary

                    Divider()

                    // Common parameters (only if all same type)
                    if state.allSameType, let effectType = state.effectType {
                        commonParametersSection(effectType: effectType)
                    } else {
                        mixedTypesMessage
                    }

                    Divider()

                    // Bulk actions
                    bulkActionsSection
                }
                .padding(12)
            }
        }
    }

    private var effectTypesSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Selected Types")
                .font(.caption)
                .foregroundColor(.secondary)

            if state.allSameType, let type = state.effectType {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(type)
                        .font(.system(size: 12))
                }
            } else {
                ForEach(Array(state.commonEffectTypes).sorted(), id: \.self) { type in
                    HStack {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundColor(.secondary)
                        Text(type)
                            .font(.system(size: 11))
                    }
                }
            }
        }
    }

    private var mixedTypesMessage: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Mixed effect types")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            Text("Parameter editing is only available when all selected effects are the same type. Select effects of the same type to edit their parameters.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(Color(nsColor: NSColor(white: 0.18, alpha: 1.0)))
        .cornerRadius(6)
    }

    private func commonParametersSection(effectType: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Common Parameters")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("Changes apply to all \(state.selectionCount) effects")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }

            if let paramDefs = getParameterDefinitions(for: effectType) {
                ForEach(paramDefs, id: \.key) { param in
                    parameterRow(param: param)
                }
            } else {
                Text("No parameters available")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var bulkActionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bulk Actions")
                .font(.caption)
                .foregroundColor(.secondary)

            Button(action: {
                showDeleteConfirmation = true
            }) {
                HStack {
                    Image(systemName: "trash.fill")
                    Text("Delete Selected (\(state.selectionCount))")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }

    // MARK: - Single Effect Panel

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
            if let choices = param.choices, !choices.isEmpty {
                // Ensure current value is always in the list
                let allChoices = choices.contains(currentValue) ? choices : [currentValue] + choices
                Picker("", selection: Binding(
                    get: { currentValue },
                    set: { newValue in
                        state.setParameter(key: param.key, value: newValue)
                    }
                )) {
                    ForEach(allChoices, id: \.self) { choice in
                        Text(choice).tag(choice)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 150)
            } else {
                // No choices available — show as text field
                TextField("", text: Binding(
                    get: { currentValue },
                    set: { newValue in
                        state.setParameter(key: param.key, value: newValue)
                    }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(maxWidth: 150)
            }

        case .valueCurve, .colorCurve:
            Text(currentValue.count > 40 ? String(currentValue.prefix(40)) + "..." : currentValue)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .help(currentValue)

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
    case valueCurve = "valueCurve"
    case colorCurve = "colorCurve"
}

// MARK: - Preview

#Preview {
    let state = EffectSelectionState()
    state.effectType = "Bars"
    state.selectedEffectId = 1

    return EffectPropertiesView(state: state)
        .frame(width: 400, height: 300)
}
