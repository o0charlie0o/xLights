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
import UniformTypeIdentifiers

// MARK: - Color Palette Constants

private let kPaletteSize = 8
private let kUserDefaultsPalettesKey = "XLSavedPalettes"

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

// MARK: - Saved Palette Model

/// Represents a saved palette with a name and color data
struct SavedPalette: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    /// Comma-separated hex color string (e.g. "#FF0000,#00FF00,...,")
    var colorString: String
    /// Whether this palette was loaded from a .xpalette file (read-only source)
    var isFromFile: Bool

    init(name: String, colorString: String, isFromFile: Bool = false) {
        self.id = UUID()
        self.name = name
        self.colorString = colorString
        self.isFromFile = isFromFile
    }

    /// Extract the 8 hex color values from the color string
    var hexColors: [String] {
        let components = colorString.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        var colors: [String] = []
        for component in components {
            let trimmed = component.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            // Only include simple hex colors, skip Active= gradient entries
            if trimmed.hasPrefix("#") && trimmed.count == 7 {
                colors.append(trimmed)
            } else if trimmed.hasPrefix("#") {
                colors.append(String(trimmed.prefix(7)))
            }
        }
        while colors.count < kPaletteSize {
            colors.append("#FFFFFF")
        }
        return Array(colors.prefix(kPaletteSize))
    }
}

// MARK: - Palette Manager

/// Manages saving, loading, and importing palettes
final class PaletteManager {
    static let shared = PaletteManager()

    private init() {}

    /// Load all saved palettes from UserDefaults
    func loadSavedPalettes() -> [SavedPalette] {
        guard let data = UserDefaults.standard.data(forKey: kUserDefaultsPalettesKey),
              let palettes = try? JSONDecoder().decode([SavedPalette].self, from: data) else {
            return []
        }
        return palettes
    }

    /// Save palettes to UserDefaults
    func savePalettes(_ palettes: [SavedPalette]) {
        // Only persist user-created palettes, not file-based ones
        let userPalettes = palettes.filter { !$0.isFromFile }
        if let data = try? JSONEncoder().encode(userPalettes) {
            UserDefaults.standard.set(data, forKey: kUserDefaultsPalettesKey)
        }
    }

    /// Add or update a palette
    func savePalette(_ palette: SavedPalette, in palettes: inout [SavedPalette]) {
        if let index = palettes.firstIndex(where: { $0.id == palette.id }) {
            palettes[index] = palette
        } else {
            palettes.append(palette)
        }
        savePalettes(palettes)
    }

    /// Delete a palette
    func deletePalette(_ palette: SavedPalette, from palettes: inout [SavedPalette]) {
        palettes.removeAll { $0.id == palette.id }

        // If it was saved to a .xpalette file in the show folder, also remove the file
        if palette.isFromFile, let showPath = getShowFolderPath() {
            let filePath = (showPath as NSString).appendingPathComponent("Palettes/\(palette.name).xpalette")
            try? FileManager.default.removeItem(atPath: filePath)
        }

        savePalettes(palettes)
    }

    /// Load palettes from .xpalette files in the show folder and app resources
    func loadFilePalettes() -> [SavedPalette] {
        var palettes: [SavedPalette] = []

        // Load from show folder Palettes directory
        if let showPath = getShowFolderPath() {
            let palettesDir = (showPath as NSString).appendingPathComponent("Palettes")
            loadPalettesFromDirectory(palettesDir, into: &palettes)

            // Also check show folder root for .xpalette files
            loadPalettesFromDirectory(showPath, into: &palettes)
        }

        // Load from app bundle resources/palettes
        if let resourcePath = Bundle.main.resourcePath {
            let bundlePalettesDir = (resourcePath as NSString).appendingPathComponent("palettes")
            loadPalettesFromDirectory(bundlePalettesDir, into: &palettes)
        }

        return palettes
    }

    /// Load .xpalette files from a directory
    private func loadPalettesFromDirectory(_ directoryPath: String, into palettes: inout [SavedPalette]) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directoryPath) else { return }

        guard let contents = try? fm.contentsOfDirectory(atPath: directoryPath) else { return }

        for filename in contents where filename.hasSuffix(".xpalette") {
            let filePath = (directoryPath as NSString).appendingPathComponent(filename)
            guard let data = fm.contents(atPath: filePath),
                  let content = String(data: data, encoding: .utf8) else { continue }

            let colorString = content.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = (filename as NSString).deletingPathExtension

            // Skip if we already have a palette with the same colors
            let existingColors = colorString.split(separator: ",").map(String.init).joined(separator: ",")
            if palettes.contains(where: {
                $0.colorString.split(separator: ",").map(String.init).joined(separator: ",") == existingColors
            }) {
                continue
            }

            palettes.append(SavedPalette(name: name, colorString: colorString, isFromFile: true))
        }
    }

    /// Save a palette as a .xpalette file in the show folder
    func savePaletteToFile(_ palette: SavedPalette) -> Bool {
        guard let showPath = getShowFolderPath() else { return false }

        let palettesDir = (showPath as NSString).appendingPathComponent("Palettes")
        let fm = FileManager.default

        // Create Palettes directory if needed
        if !fm.fileExists(atPath: palettesDir) {
            try? fm.createDirectory(atPath: palettesDir, withIntermediateDirectories: true)
        }

        let filePath = (palettesDir as NSString).appendingPathComponent("\(palette.name).xpalette")
        return fm.createFile(atPath: filePath, contents: palette.colorString.data(using: .utf8))
    }

    /// Import a palette from a .xpalette file at a given URL
    func importPaletteFromFile(at url: URL) -> SavedPalette? {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else { return nil }

        let colorString = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = url.deletingPathExtension().lastPathComponent

        return SavedPalette(name: name, colorString: colorString, isFromFile: false)
    }

    /// Parse a comma-separated hex string (e.g. "#FF0000,#00FF00,#0000FF")
    func parsePaletteString(_ input: String) -> SavedPalette? {
        let cleaned = input.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "")
            .uppercased()

        let components = cleaned.split(separator: ",").map(String.init)
        let validColors = components.filter { component in
            let trimmed = component.trimmingCharacters(in: .whitespaces)
            guard trimmed.count == 7, trimmed.hasPrefix("#") else { return false }
            let hexPart = trimmed.dropFirst()
            return hexPart.allSatisfy { $0.isHexDigit }
        }

        guard !validColors.isEmpty, validColors.count <= 8 else { return nil }

        var colorString = validColors.joined(separator: ",") + ","
        // Pad to 8 colors
        var count = validColors.count
        while count < 8 {
            colorString += "#FFFFFF,"
            count += 1
        }

        return SavedPalette(name: "Imported", colorString: colorString, isFromFile: false)
    }

    /// Get the show folder path from the engine bridge
    private func getShowFolderPath() -> String? {
        // TODO: Pass engine bridge reference to PaletteManager for show folder access
        return nil
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

    // MARK: - Palette Management

    /// All available palettes (user-saved + file-based)
    var savedPalettes: [SavedPalette] = []

    /// The currently loaded palette (if any)
    var currentPaletteName: String?

    /// Load all available palettes from storage and files
    func loadAllPalettes() {
        let manager = PaletteManager.shared
        var all = manager.loadSavedPalettes()
        let filePalettes = manager.loadFilePalettes()

        // Merge file palettes, avoiding duplicates by name
        for fp in filePalettes {
            if !all.contains(where: { $0.name == fp.name }) {
                all.append(fp)
            }
        }

        savedPalettes = all
    }

    /// Get the current palette as a color string (matching legacy format)
    func getCurrentPaletteString() -> String {
        return colors.map { $0.hexString }.joined(separator: ",") + ","
    }

    /// Apply a saved palette to the current colors
    func loadPalette(_ palette: SavedPalette) {
        let hexColors = palette.hexColors
        for i in 0..<min(kPaletteSize, hexColors.count) {
            colors[i].color = PaletteColor.fromHex(hexColors[i])

            if let bridge = engineBridge, let effectId = selectedEffectId {
                let key = "C_BUTTON_Palette\(i + 1)"
                bridge.setEffectParameter(effectId, key: key, value: hexColors[i])
            }
        }
        currentPaletteName = palette.name
    }

    /// Save the current palette with a name
    func savePalette(name: String) {
        let colorString = getCurrentPaletteString()
        let palette = SavedPalette(name: name, colorString: colorString, isFromFile: false)
        PaletteManager.shared.savePalette(palette, in: &savedPalettes)
        _ = PaletteManager.shared.savePaletteToFile(palette)
        currentPaletteName = name
    }

    /// Update the current palette (re-save with existing name)
    func updateCurrentPalette() {
        guard let name = currentPaletteName else { return }

        let colorString = getCurrentPaletteString()
        if let index = savedPalettes.firstIndex(where: { $0.name == name }) {
            savedPalettes[index].colorString = colorString
            PaletteManager.shared.savePalettes(savedPalettes)
            _ = PaletteManager.shared.savePaletteToFile(savedPalettes[index])
        } else {
            savePalette(name: name)
        }
    }

    /// Delete a saved palette
    func deletePalette(_ palette: SavedPalette) {
        PaletteManager.shared.deletePalette(palette, from: &savedPalettes)
        if currentPaletteName == palette.name {
            currentPaletteName = nil
        }
    }

    /// Apply colors from a hex string (for import)
    func applyColorsFromString(_ colorString: String) {
        let components = colorString.split(separator: ",").map(String.init)
        for i in 0..<min(kPaletteSize, components.count) {
            let hex = components[i].trimmingCharacters(in: .whitespaces)
            guard hex.hasPrefix("#") else { continue }
            colors[i].color = PaletteColor.fromHex(hex)

            if let bridge = engineBridge, let effectId = selectedEffectId {
                let key = "C_BUTTON_Palette\(i + 1)"
                bridge.setEffectParameter(effectId, key: key, value: hex.uppercased())
            }
        }
        currentPaletteName = nil
    }

    /// Check if the current palette matches a saved palette
    func currentMatchesSaved(_ palette: SavedPalette) -> Bool {
        let currentString = getCurrentPaletteString()
        let currentColors = currentString.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces).uppercased()
        }.filter { !$0.isEmpty }

        let savedColors = palette.hexColors.map { $0.uppercased() }

        guard currentColors.count == savedColors.count else { return false }
        return zip(currentColors, savedColors).allSatisfy { $0 == $1 }
    }
}

// MARK: - Color Palette View

/// Main color palette view
struct ColorPaletteView: View {
    @Bindable var state: ColorPaletteState
    @State private var expandedSections: Set<String> = ["palette", "brightness", "hsv"]
    @State private var showingSaveAlert = false
    @State private var showingSaveAsAlert = false
    @State private var showingImportTextAlert = false
    @State private var showingDeleteConfirmation = false
    @State private var paletteNameInput = ""
    @State private var importTextInput = ""
    @State private var importErrorMessage: String?
    @State private var paletteToDelete: SavedPalette?
    @State private var showingFileImporter = false

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
                // Palette Management Bar
                paletteManagementBar

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
        .onAppear {
            state.loadAllPalettes()
        }
        .alert("Save Palette As", isPresented: $showingSaveAsAlert) {
            TextField("Palette Name", text: $paletteNameInput)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                let name = paletteNameInput.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    state.savePalette(name: name)
                }
            }
        } message: {
            Text("Enter a name for this palette.")
        }
        .alert("Import Palette", isPresented: $showingImportTextAlert) {
            TextField("e.g. #FF0000,#00FF00,#0000FF", text: $importTextInput)
            Button("Cancel", role: .cancel) {
                importErrorMessage = nil
            }
            Button("Import") {
                if let palette = PaletteManager.shared.parsePaletteString(importTextInput) {
                    state.applyColorsFromString(palette.colorString)
                    importErrorMessage = nil
                } else {
                    importErrorMessage = "Invalid format. Use comma-separated hex colors (e.g. #FF0000,#00FF00)."
                }
            }
        } message: {
            if let error = importErrorMessage {
                Text(error)
            } else {
                Text("Enter comma-separated hex colors (e.g. #FF0000,#00FF00,#0000FF).")
            }
        }
        .alert("Delete Palette", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                paletteToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let palette = paletteToDelete {
                    state.deletePalette(palette)
                    paletteToDelete = nil
                }
            }
        } message: {
            if let palette = paletteToDelete {
                Text("Are you sure you want to delete the palette \"\(palette.name)\"? This cannot be undone.")
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [UTType(filenameExtension: "xpalette") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                if let palette = PaletteManager.shared.importPaletteFromFile(at: url) {
                    state.applyColorsFromString(palette.colorString)
                    state.savedPalettes.append(palette)
                    PaletteManager.shared.savePalettes(state.savedPalettes)
                }
            case .failure:
                break
            }
        }
    }

    private func toggleSection(_ section: String) {
        if expandedSections.contains(section) {
            expandedSections.remove(section)
        } else {
            expandedSections.insert(section)
        }
    }

    // MARK: - Palette Management Bar

    private var paletteManagementBar: some View {
        HStack(spacing: 6) {
            // Palette picker menu
            Menu {
                if state.savedPalettes.isEmpty {
                    Text("No Saved Palettes")
                } else {
                    ForEach(state.savedPalettes) { palette in
                        Button {
                            state.loadPalette(palette)
                        } label: {
                            HStack {
                                PaletteSwatchLabel(palette: palette)
                                if state.currentPaletteName == palette.name {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 11))
                    Text(state.currentPaletteName ?? "Palette")
                        .font(.system(size: 11))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: NSColor(white: 0.22, alpha: 1.0)))
                .cornerRadius(4)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            // Palette action menu (hamburger)
            Menu {
                Button {
                    if state.currentPaletteName != nil {
                        state.updateCurrentPalette()
                    } else {
                        paletteNameInput = ""
                        showingSaveAsAlert = true
                    }
                } label: {
                    Label("Update Palette", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(state.currentPaletteName == nil)

                Button {
                    let nextNumber = state.savedPalettes.count + 1
                    let name = String(format: "PAL%03d", nextNumber)
                    state.savePalette(name: name)
                } label: {
                    Label("Save Palette", systemImage: "square.and.arrow.down")
                }
                .disabled(paletteAlreadySaved)

                Button {
                    paletteNameInput = state.currentPaletteName ?? ""
                    showingSaveAsAlert = true
                } label: {
                    Label("Save Palette As...", systemImage: "square.and.arrow.down.on.square")
                }

                Divider()

                Menu("Delete Palette") {
                    if deletablePalettes.isEmpty {
                        Text("No Palettes to Delete")
                    } else {
                        ForEach(deletablePalettes) { palette in
                            Button(role: .destructive) {
                                paletteToDelete = palette
                                showingDeleteConfirmation = true
                            } label: {
                                Text(palette.name)
                            }
                        }
                    }
                }

                Divider()

                Button {
                    showingFileImporter = true
                } label: {
                    Label("Import from File...", systemImage: "doc.badge.plus")
                }

                Button {
                    importTextInput = ""
                    importErrorMessage = nil
                    showingImportTextAlert = true
                } label: {
                    Label("Import from Text...", systemImage: "text.badge.plus")
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12))
                    .frame(width: 24, height: 20)
                    .background(Color(nsColor: NSColor(white: 0.22, alpha: 1.0)))
                    .cornerRadius(4)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .foregroundColor(.primary)
    }

    /// Check if the current palette colors already exist in saved palettes
    private var paletteAlreadySaved: Bool {
        state.savedPalettes.contains { state.currentMatchesSaved($0) }
    }

    /// Palettes that can be deleted (user-created ones, plus file-based ones from show folder)
    private var deletablePalettes: [SavedPalette] {
        state.savedPalettes.filter { !$0.isFromFile || hasFileInShowFolder($0) }
    }

    /// Check if a palette has a corresponding file in the show folder
    private func hasFileInShowFolder(_ palette: SavedPalette) -> Bool {
        // TODO: Implement show folder path access for palette file checking
        return false
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

// MARK: - Palette Swatch Label

/// Shows a small preview of palette colors next to the palette name
struct PaletteSwatchLabel: View {
    let palette: SavedPalette

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 1) {
                ForEach(Array(palette.hexColors.prefix(4).enumerated()), id: \.offset) { _, hex in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(PaletteColor.fromHex(hex))
                        .frame(width: 8, height: 12)
                }
            }
            Text(palette.name)
                .font(.system(size: 12))
        }
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
