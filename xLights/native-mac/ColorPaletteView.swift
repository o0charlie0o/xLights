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

// MARK: - Gradient Data Model

/// A single color stop in a gradient
struct GradientStop: Identifiable, Equatable {
    let id: UUID
    var position: Double  // 0.0-1.0
    var color: Color

    init(position: Double, color: Color) {
        self.id = UUID()
        self.position = position
        self.color = color
    }
}

/// Gradient color curve data matching legacy ColorCurve serialization
struct GradientData: Equatable {
    var isActive: Bool
    var stops: [GradientStop]    // min 2 stops, sorted by position
    var blendMode: String        // "Gradient", "None", "Random"
    var timecurve: Int           // 0=OverTime, 1=Right, 2=Down, 3=Left, 4=Up, 5=RadialIn, 6=RadialOut, 7=CW, 8=CCW
    var curveId: String          // "ID_BUTTON_Palette1" etc.

    /// Check if a string is a gradient (legacy ColorCurve format)
    static func isGradientString(_ s: String) -> Bool {
        return s.contains("Active=")
    }

    /// Parse a legacy ColorCurve serialized string
    static func fromLegacyString(_ s: String, defaultId: String = "") -> GradientData? {
        guard isGradientString(s) else { return nil }

        var active = false
        var curveId = defaultId
        var blendMode = "Gradient"
        var timecurve = 0
        var stops: [GradientStop] = []

        let tokens = s.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        for token in tokens {
            guard let eqPos = token.firstIndex(of: "=") else { continue }
            let key = String(token[token.startIndex..<eqPos])
            let value = String(token[token.index(after: eqPos)...])

            switch key {
            case "Active":
                active = (value == "TRUE")
            case "Id":
                curveId = value
            case "Type":
                blendMode = value
            case "Timecurve":
                timecurve = Int(value) ?? 0
            case "Values":
                let points = value.split(separator: ";").map(String.init)
                for point in points {
                    guard !point.isEmpty else { continue }
                    var pos: Double = 0
                    var colorHex = "#000000"
                    let parts = point.split(separator: "^").map(String.init)
                    for part in parts {
                        if part.hasPrefix("x=") {
                            pos = Double(String(part.dropFirst(2))) ?? 0
                        } else if part.hasPrefix("c=") {
                            colorHex = String(part.dropFirst(2))
                            // Legacy uses @ instead of , for multi-component colors
                            colorHex = colorHex.replacingOccurrences(of: "@", with: ",")
                        }
                    }
                    stops.append(GradientStop(position: pos, color: PaletteColor.fromHex(colorHex)))
                }
            default:
                break
            }
        }

        // Must have at least 1 stop
        if stops.isEmpty {
            stops.append(GradientStop(position: 0.5, color: .black))
        }

        return GradientData(
            isActive: active,
            stops: stops.sorted { $0.position < $1.position },
            blendMode: blendMode,
            timecurve: timecurve,
            curveId: curveId
        )
    }

    /// Serialize to legacy ColorCurve format (mirrors ColorCurve::Serialise in C++)
    func toLegacyString() -> String {
        guard isActive else {
            return "Active=FALSE|"
        }

        var res = "Active=TRUE|"
        res += "Id=\(curveId)|"

        if blendMode != "Gradient" {
            res += "Type=\(blendMode)|"
        }

        if timecurve != 0 {
            res += "Timecurve=\(timecurve)|"
        }

        res += "Values="
        let sortedStops = stops.sorted { $0.position < $1.position }
        for (idx, stop) in sortedStops.enumerated() {
            let hex = colorToHex(stop.color)
            res += "x=\(String(format: "%.3f", stop.position))^c=\(hex)"
            if idx < sortedStops.count - 1 {
                res += ";"
            }
        }
        res += "|"

        return res
    }

    /// Convert a SwiftUI Color to hex string
    private func colorToHex(_ color: Color) -> String {
        let nsColor = NSColor(color)
        guard let rgb = nsColor.usingColorSpace(.sRGB) else { return "#FFFFFF" }
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        return String(format: "#%02x%02x%02x", r, g, b)
    }

    /// Create a default 2-stop gradient from a solid color
    static func defaultGradient(from color: Color, index: Int) -> GradientData {
        return GradientData(
            isActive: true,
            stops: [
                GradientStop(position: 0, color: color),
                GradientStop(position: 1, color: .black)
            ],
            blendMode: "Gradient",
            timecurve: 0,
            curveId: "ID_BUTTON_Palette\(index + 1)"
        )
    }
}

// MARK: - Palette Color Model

/// Represents a single color in the 8-color palette
struct PaletteColor: Identifiable {
    let id: Int
    var color: Color
    var isEnabled: Bool
    var isLocked: Bool
    var gradient: GradientData?

    /// Whether this slot is in gradient mode
    var isGradient: Bool {
        gradient?.isActive == true
    }

    /// The serialized value for engine communication (hex or gradient string)
    var serializedValue: String {
        if let g = gradient, g.isActive {
            return g.toLegacyString()
        }
        return hexString
    }

    init(id: Int, color: Color = .red, isEnabled: Bool = true, isLocked: Bool = false) {
        self.id = id
        self.color = color
        self.isEnabled = isEnabled
        self.isLocked = isLocked
        self.gradient = nil
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
    /// Comma-separated color values (hex or gradient strings)
    var colorString: String
    /// Whether this palette was loaded from a .xpalette file (read-only source)
    var isFromFile: Bool

    init(name: String, colorString: String, isFromFile: Bool = false) {
        self.id = UUID()
        self.name = name
        self.colorString = colorString
        self.isFromFile = isFromFile
    }

    /// Extract the 8 color values from the color string (hex or gradient strings)
    var colorValues: [String] {
        // Split carefully: gradient strings contain commas inside color refs
        // but palette separator is comma-at-top-level
        // Legacy format: values are separated by commas, but gradient strings
        // don't contain top-level commas (they use | and ; internally)
        let components = colorString.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        var values: [String] = []
        for component in components {
            let trimmed = component.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            values.append(trimmed)
        }
        while values.count < kPaletteSize {
            values.append("#FFFFFF")
        }
        return Array(values.prefix(kPaletteSize))
    }

    /// Extract simple hex colors for swatch preview
    var hexColors: [String] {
        return colorValues.map { value in
            if GradientData.isGradientString(value) {
                // For preview, extract first stop color
                if let gradient = GradientData.fromLegacyString(value),
                   let firstStop = gradient.stops.first {
                    let nsColor = NSColor(firstStop.color)
                    guard let rgb = nsColor.usingColorSpace(.sRGB) else { return "#FFFFFF" }
                    let r = Int(rgb.redComponent * 255)
                    let g = Int(rgb.greenComponent * 255)
                    let b = Int(rgb.blueComponent * 255)
                    return String(format: "#%02X%02X%02X", r, g, b)
                }
                return "#FFFFFF"
            }
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") && trimmed.count >= 7 {
                return String(trimmed.prefix(7))
            }
            return "#FFFFFF"
        }
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

        // Listen for SET_COLOR_N keyboard shortcuts
        NotificationCenter.default.publisher(for: NSNotification.Name("XLSetPaletteColorNotification"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleSetPaletteColor(notification)
            }
            .store(in: &cancellables)

        // Listen for COLOR_UPDATE keyboard shortcut
        NotificationCenter.default.publisher(for: NSNotification.Name("XLColorUpdateRequestNotification"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleColorUpdateRequest(notification)
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

    private func handleSetPaletteColor(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let colorIndex = userInfo["colorIndex"] as? Int,
              let hexColor = userInfo["hexColor"] as? String else { return }

        guard colorIndex >= 0 && colorIndex < kPaletteSize else { return }

        let color = PaletteColor.fromHex(hexColor)
        setColor(at: colorIndex, color: color)
    }

    private func handleColorUpdateRequest(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let selectedIds = userInfo["selectedEffectIds"] as? [NSNumber],
              let bridge = engineBridge else { return }

        for effectIdNumber in selectedIds {
            let effectId = effectIdNumber.intValue
            for i in 0..<kPaletteSize {
                let colorKey = "C_BUTTON_Palette\(i + 1)"
                let enableKey = "C_CHECKBOX_Palette\(i + 1)"
                bridge.setEffectParameter(effectId, key: colorKey, value: colors[i].serializedValue)
                bridge.setEffectParameter(effectId, key: enableKey, value: colors[i].isEnabled ? "1" : "0")
            }
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
                if GradientData.isGradientString(colorValue) {
                    // Parse gradient data
                    let defaultId = "ID_BUTTON_Palette\(i + 1)"
                    if let gradientData = GradientData.fromLegacyString(colorValue, defaultId: defaultId) {
                        colors[i].gradient = gradientData
                        // Set fallback solid color to first stop
                        if let firstStop = gradientData.stops.first {
                            colors[i].color = firstStop.color
                        }
                    }
                } else {
                    // Solid color
                    colors[i].color = PaletteColor.fromHex(colorValue)
                    colors[i].gradient = nil
                }
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

    /// Update a color in the palette (solid mode - clears any gradient)
    func setColor(at index: Int, color: Color) {
        guard index >= 0 && index < kPaletteSize else { return }
        guard !colors[index].isLocked else { return }

        colors[index].color = color
        colors[index].gradient = nil

        // Update in engine
        if let bridge = engineBridge, let effectId = selectedEffectId {
            let key = "C_BUTTON_Palette\(index + 1)"
            let hexValue = colors[index].hexString
            bridge.setEffectParameter(effectId, key: key, value: hexValue)
        }
    }

    /// Set gradient data for a palette slot
    func setGradient(at index: Int, gradient: GradientData) {
        guard index >= 0 && index < kPaletteSize else { return }
        guard !colors[index].isLocked else { return }

        colors[index].gradient = gradient
        // Keep solid color in sync with first stop as fallback
        if let firstStop = gradient.stops.first {
            colors[index].color = firstStop.color
        }

        // Update in engine
        if let bridge = engineBridge, let effectId = selectedEffectId {
            let key = "C_BUTTON_Palette\(index + 1)"
            bridge.setEffectParameter(effectId, key: key, value: gradient.toLegacyString())
        }
    }

    /// Toggle between solid and gradient mode for a palette slot
    func toggleGradientMode(at index: Int) {
        guard index >= 0 && index < kPaletteSize else { return }
        guard !colors[index].isLocked else { return }

        if colors[index].isGradient {
            // Switch to solid - use first stop color
            if let firstStop = colors[index].gradient?.stops.first {
                colors[index].color = firstStop.color
            }
            colors[index].gradient = nil

            if let bridge = engineBridge, let effectId = selectedEffectId {
                let key = "C_BUTTON_Palette\(index + 1)"
                bridge.setEffectParameter(effectId, key: key, value: colors[index].hexString)
            }
        } else {
            // Switch to gradient - create default from current color
            let gradient = GradientData.defaultGradient(from: colors[index].color, index: index)
            setGradient(at: index, gradient: gradient)
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

    /// Get the current palette as a color string (preserving gradient data)
    func getCurrentPaletteString() -> String {
        return colors.map { $0.serializedValue }.joined(separator: ",") + ","
    }

    /// Apply a saved palette to the current colors
    func loadPalette(_ palette: SavedPalette) {
        let values = palette.colorValues
        for i in 0..<min(kPaletteSize, values.count) {
            let value = values[i]
            if GradientData.isGradientString(value) {
                let defaultId = "ID_BUTTON_Palette\(i + 1)"
                if let gradientData = GradientData.fromLegacyString(value, defaultId: defaultId) {
                    colors[i].gradient = gradientData
                    if let firstStop = gradientData.stops.first {
                        colors[i].color = firstStop.color
                    }
                }
            } else {
                colors[i].color = PaletteColor.fromHex(value)
                colors[i].gradient = nil
            }

            if let bridge = engineBridge, let effectId = selectedEffectId {
                let key = "C_BUTTON_Palette\(i + 1)"
                bridge.setEffectParameter(effectId, key: key, value: colors[i].serializedValue)
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

    /// Apply colors from a color string (for import)
    func applyColorsFromString(_ colorString: String) {
        let components = colorString.split(separator: ",").map(String.init)
        for i in 0..<min(kPaletteSize, components.count) {
            let value = components[i].trimmingCharacters(in: .whitespaces)
            if GradientData.isGradientString(value) {
                let defaultId = "ID_BUTTON_Palette\(i + 1)"
                if let gradientData = GradientData.fromLegacyString(value, defaultId: defaultId) {
                    colors[i].gradient = gradientData
                    if let firstStop = gradientData.stops.first {
                        colors[i].color = firstStop.color
                    }
                }
            } else if value.hasPrefix("#") {
                colors[i].color = PaletteColor.fromHex(value)
                colors[i].gradient = nil
            } else {
                continue
            }

            if let bridge = engineBridge, let effectId = selectedEffectId {
                let key = "C_BUTTON_Palette\(i + 1)"
                bridge.setEffectParameter(effectId, key: key, value: colors[i].serializedValue)
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
    @State private var editingGradientIndex: Int?

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
        GeometryReader { geometry in
            ScrollView([.vertical, .horizontal], showsIndicators: true) {
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
                .frame(minWidth: max(geometry.size.width, 200))
            }
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
        HStack(spacing: 4) {
            ForEach(0..<8) { index in
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
                    },
                    onToggleGradient: {
                        state.toggleGradientMode(at: index)
                    },
                    onEditGradient: {
                        editingGradientIndex = index
                    }
                )
                .popover(isPresented: Binding(
                    get: { editingGradientIndex == index },
                    set: { if !$0 { editingGradientIndex = nil } }
                )) {
                    if let gradient = state.colors[index].gradient {
                        GradientEditorPopover(
                            gradient: gradient,
                            onGradientChange: { newGradient in
                                state.setGradient(at: index, gradient: newGradient)
                            }
                        )
                    }
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
    let onToggleGradient: () -> Void
    let onEditGradient: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            // Color swatch — solid or gradient
            Group {
                if paletteColor.isGradient, let gradient = paletteColor.gradient {
                    GradientSwatchView(gradient: gradient)
                        .frame(minWidth: 22, maxWidth: .infinity, minHeight: 22, maxHeight: 22)
                        .cornerRadius(4)
                        .onTapGesture {
                            if paletteColor.isEnabled && !paletteColor.isLocked {
                                onEditGradient()
                            }
                        }
                } else {
                    NativeColorWell(
                        color: paletteColor.color,
                        isEnabled: paletteColor.isEnabled && !paletteColor.isLocked,
                        onColorChange: onColorChange
                    )
                    .frame(minWidth: 22, maxWidth: .infinity, minHeight: 22, maxHeight: 22)
                }
            }
            .overlay(
                Group {
                    if paletteColor.isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.white)
                            .shadow(radius: 1)
                    }
                }
            )
            .opacity(paletteColor.isEnabled ? 1.0 : 0.4)
            .contextMenu {
                if paletteColor.isGradient {
                    Button("Switch to Solid") {
                        onToggleGradient()
                    }
                } else {
                    Button("Switch to Gradient") {
                        onToggleGradient()
                    }
                }
            }

            // Enable/Lock controls
            HStack(spacing: 1) {
                Button {
                    onToggleEnabled()
                } label: {
                    Image(systemName: paletteColor.isEnabled ? "checkmark.square.fill" : "square")
                        .font(.system(size: 10))
                        .foregroundColor(paletteColor.isEnabled ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)

                Button {
                    onToggleLocked()
                } label: {
                    Image(systemName: paletteColor.isLocked ? "lock.fill" : "lock.open")
                        .font(.system(size: 8))
                        .foregroundColor(paletteColor.isLocked ? .orange : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minWidth: 22, maxWidth: .infinity)
    }
}

// MARK: - Gradient Swatch View

/// Renders a gradient preview from GradientData stops
struct GradientSwatchView: View {
    let gradient: GradientData

    var body: some View {
        let sortedStops = gradient.stops.sorted { $0.position < $1.position }
        let swiftUIStops = sortedStops.map { stop in
            Gradient.Stop(color: stop.color, location: stop.position)
        }

        if swiftUIStops.count >= 2 {
            LinearGradient(
                stops: swiftUIStops,
                startPoint: .leading,
                endPoint: .trailing
            )
        } else if let first = swiftUIStops.first {
            Rectangle().fill(first.color)
        } else {
            Rectangle().fill(Color.black)
        }
    }
}

// MARK: - Gradient Editor Popover

/// Popover editor for gradient color curves
struct GradientEditorPopover: View {
    @State private var localGradient: GradientData
    let onGradientChange: (GradientData) -> Void

    init(gradient: GradientData, onGradientChange: @escaping (GradientData) -> Void) {
        self._localGradient = State(initialValue: gradient)
        self.onGradientChange = onGradientChange
    }

    var body: some View {
        VStack(spacing: 12) {
            // Gradient preview bar
            GradientSwatchView(gradient: localGradient)
                .frame(height: 30)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(white: 0.4), lineWidth: 1)
                )

            // Stop list
            VStack(spacing: 6) {
                ForEach(Array(localGradient.stops.sorted { $0.position < $1.position }.enumerated()), id: \.element.id) { idx, stop in
                    GradientStopRow(
                        stop: stop,
                        canDelete: localGradient.stops.count > 2,
                        onColorChange: { newColor in
                            updateStopColor(id: stop.id, color: newColor)
                        },
                        onPositionChange: { newPos in
                            updateStopPosition(id: stop.id, position: newPos)
                        },
                        onDelete: {
                            deleteStop(id: stop.id)
                        }
                    )
                }
            }

            // Add stop button
            Button {
                addStop()
            } label: {
                Label("Add Color Stop", systemImage: "plus.circle")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Divider()

            // Direction picker
            HStack {
                Text("Direction:")
                    .font(.system(size: 11))
                Spacer()
                Picker("", selection: $localGradient.timecurve) {
                    Text("Over Time").tag(0)
                    Text("Right").tag(1)
                    Text("Down").tag(2)
                    Text("Left").tag(3)
                    Text("Up").tag(4)
                    Text("Radial In").tag(5)
                    Text("Radial Out").tag(6)
                    Text("Clockwise").tag(7)
                    Text("Counter-CW").tag(8)
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 120)
                .onChange(of: localGradient.timecurve) {
                    commitChange()
                }
            }

            // Blend mode
            HStack {
                Text("Blend:")
                    .font(.system(size: 11))
                Spacer()
                Picker("", selection: $localGradient.blendMode) {
                    Text("Gradient").tag("Gradient")
                    Text("Discrete").tag("None")
                    Text("Random").tag("Random")
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .onChange(of: localGradient.blendMode) {
                    commitChange()
                }
            }

            // Flip button
            Button {
                flipStops()
            } label: {
                Label("Flip Gradient", systemImage: "arrow.left.arrow.right")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 260)
    }

    private func updateStopColor(id: UUID, color: Color) {
        if let idx = localGradient.stops.firstIndex(where: { $0.id == id }) {
            localGradient.stops[idx].color = color
            commitChange()
        }
    }

    private func updateStopPosition(id: UUID, position: Double) {
        if let idx = localGradient.stops.firstIndex(where: { $0.id == id }) {
            localGradient.stops[idx].position = max(0, min(1, position))
            commitChange()
        }
    }

    private func deleteStop(id: UUID) {
        guard localGradient.stops.count > 2 else { return }
        localGradient.stops.removeAll { $0.id == id }
        commitChange()
    }

    private func addStop() {
        // Insert at midpoint of largest gap
        let sorted = localGradient.stops.sorted { $0.position < $1.position }
        var bestGap = 0.0
        var bestPos = 0.5
        var bestColor = Color.gray

        for i in 0..<(sorted.count - 1) {
            let gap = sorted[i + 1].position - sorted[i].position
            if gap > bestGap {
                bestGap = gap
                bestPos = (sorted[i].position + sorted[i + 1].position) / 2.0
                // Blend the two adjacent colors
                bestColor = sorted[i].color
            }
        }

        localGradient.stops.append(GradientStop(position: bestPos, color: bestColor))
        commitChange()
    }

    private func flipStops() {
        for i in 0..<localGradient.stops.count {
            localGradient.stops[i].position = 1.0 - localGradient.stops[i].position
        }
        commitChange()
    }

    private func commitChange() {
        onGradientChange(localGradient)
    }
}

// MARK: - Gradient Stop Row

/// A single row in the gradient editor showing a color stop
struct GradientStopRow: View {
    let stop: GradientStop
    let canDelete: Bool
    let onColorChange: (Color) -> Void
    let onPositionChange: (Double) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            // Color well
            NativeColorWell(
                color: stop.color,
                isEnabled: true,
                onColorChange: onColorChange
            )
            .frame(width: 24, height: 20)

            // Position slider
            Slider(
                value: Binding(
                    get: { stop.position },
                    set: { onPositionChange($0) }
                ),
                in: 0...1
            )
            .controlSize(.small)
            .frame(maxWidth: 120)

            // Position text
            Text(String(format: "%.0f%%", stop.position * 100))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 32, alignment: .trailing)

            // Delete button
            Button {
                onDelete()
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 11))
                    .foregroundColor(canDelete ? .red : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canDelete)
        }
    }
}

/// NSViewRepresentable wrapper around NSColorWell for single-click native color picker
struct NativeColorWell: NSViewRepresentable {
    let color: Color
    let isEnabled: Bool
    let onColorChange: (Color) -> Void

    func makeNSView(context: Context) -> NSColorWell {
        let well: NSColorWell
        if #available(macOS 13.0, *) {
            well = NSColorWell(style: .minimal)
        } else {
            well = NSColorWell()
        }
        well.color = NSColor(color)
        well.isEnabled = isEnabled
        well.isBordered = false
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        // Use a layer-backed view for rounded corners
        well.wantsLayer = true
        well.layer?.cornerRadius = 4
        well.layer?.masksToBounds = true
        return well
    }

    func updateNSView(_ well: NSColorWell, context: Context) {
        // Only update if the color actually differs to avoid fighting the picker
        let newNSColor = NSColor(color)
        if well.color != newNSColor {
            well.color = newNSColor
        }
        well.isEnabled = isEnabled
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onColorChange: onColorChange)
    }

    class Coordinator: NSObject {
        let onColorChange: (Color) -> Void
        init(onColorChange: @escaping (Color) -> Void) {
            self.onColorChange = onColorChange
        }
        @objc func colorChanged(_ sender: NSColorWell) {
            onColorChange(Color(sender.color))
        }
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
