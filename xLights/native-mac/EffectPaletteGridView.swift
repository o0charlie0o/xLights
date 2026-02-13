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
import UniformTypeIdentifiers

// MARK: - Custom Pasteboard Type

/// The pasteboard type identifier matching the Objective-C XLEffectTypePasteboardType
let XLEffectTypePasteboardType = NSPasteboard.PasteboardType("com.xlights.effectType")

// MARK: - Effect Icon Mapping

/// Maps effect type names to SF Symbol names for visual representation
let effectIconMapping: [String: String] = [
    "Adjust": "slider.horizontal.3",
    "Arpeggio": "music.note.list",
    "Bars": "chart.bar.fill",
    "Butterfly": "bird.fill",
    "Candle": "flame",
    "Circles": "circle.grid.3x3.fill",
    "ColorWash": "paintbrush.fill",
    "Curtain": "rectangle.split.2x1.fill",
    "DMX": "slider.vertical.3",
    "Duplicate": "plus.square.on.square",
    "Faces": "face.smiling.fill",
    "Fan": "fan.fill",
    "Fill": "square.fill",
    "Fire": "flame.fill",
    "Fireworks": "sparkles",
    "Galaxy": "staroflife.fill",
    "Garlands": "leaf.fill",
    "Glediator": "square.grid.3x3.fill",
    "Guitar": "guitars.fill",
    "Kaleidoscope": "camera.filters",
    "Life": "heart.fill",
    "Lightning": "bolt.fill",
    "Lines": "line.3.horizontal",
    "Liquid": "drop.fill",
    "Marquee": "text.badge.star",
    "Meteors": "moonphase.waning.crescent",
    "Morph": "arrow.triangle.2.circlepath",
    "MovingHead": "light.beacon.max.fill",
    "Music": "music.note",
    "Off": "power.circle",
    "On": "lightbulb.fill",
    "Piano": "pianokeys",
    "Pictures": "photo.fill",
    "Pinwheel": "rotate.3d",
    "Plasma": "waveform",
    "Ripple": "drop.circle.fill",
    "Servo": "gearshape.2.fill",
    "Shader": "paintpalette.fill",
    "Shape": "star.fill",
    "Shimmer": "sparkle",
    "Shockwave": "waveform.circle.fill",
    "SingleStrand": "line.diagonal",
    "Sketch": "pencil.tip",
    "Snowflakes": "snowflake",
    "Snowstorm": "cloud.snow.fill",
    "Spirals": "tornado",
    "Spirograph": "circle.circle",
    "State": "switch.2",
    "Strobe": "light.max",
    "Tendril": "leaf.arrow.circlepath",
    "Text": "textformat",
    "Tree": "tree.fill",
    "Twinkle": "sparkles",
    "Video": "video.fill",
    "VUMeter": "chart.bar.fill",
    "Warp": "arrow.up.and.down.and.arrow.left.and.right",
    "Wave": "water.waves"
]

/// Returns the SF Symbol name for a given effect type, or a default icon
func iconForEffect(_ name: String) -> String {
    return effectIconMapping[name] ?? "questionmark.square.fill"
}

/// Compute a consistent hash for a string (matching Objective-C XLSimpleStringHash)
func simpleStringHash(_ string: String) -> UInt {
    var hash: UInt = 0
    for char in string.utf16 {
        hash = hash &* 31 &+ UInt(char)
    }
    return hash
}

/// Compute color for effect type name (matching XLSequencerViewController algorithm)
func colorForEffectTypeName(_ name: String) -> Color {
    let hash = simpleStringHash(name)
    let hue = Double(hash % 360) / 360.0
    return Color(hue: hue, saturation: 0.7, brightness: 0.7)
}

/// Compute NSColor for effect type name (for AppKit views)
func nsColorForEffectTypeName(_ name: String) -> NSColor {
    let hash = simpleStringHash(name)
    let hue = CGFloat(hash % 360) / 360.0
    return NSColor(hue: hue, saturation: 0.7, brightness: 0.7, alpha: 1.0)
}

// MARK: - Effect Type Info

struct EffectTypeItem: Identifiable, Hashable {
    let id: String
    let name: String
    let color: Color

    init(name: String) {
        self.id = name
        self.name = name
        // Generate a color using consistent hash (matches Objective-C XLSequencerViewController)
        self.color = colorForEffectTypeName(name)
    }
}

// MARK: - Effect Palette Grid View

/// A horizontal grid of effect types for dragging onto the timeline.
/// This replaces the vertical list palette that was on the right side of the sequencer.
struct EffectPaletteGridView: View {
    let engineBridge: XLEngineBridge

    @State private var effectTypes: [EffectTypeItem] = []
    @State private var searchText: String = ""
    @State private var selectedEffect: String?

    private var filteredEffects: [EffectTypeItem] {
        if searchText.isEmpty {
            return effectTypes
        }
        return effectTypes.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // Grid layout - adaptive columns for vertical scrolling
    private let columns = [
        GridItem(.adaptive(minimum: 70, maximum: 90), spacing: 4)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header with search
            headerView

            Divider()

            // Effect grid - vertical scrolling
            ScrollView(.vertical, showsIndicators: true) {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(filteredEffects) { effect in
                        EffectGridCell(
                            effect: effect,
                            isSelected: selectedEffect == effect.name,
                            onSelect: { selectedEffect = effect.name }
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .background(Color(nsColor: NSColor(white: 0.15, alpha: 1.0)))
        .onAppear {
            loadEffectTypes()
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack {
            Text("Effects")
                .font(.headline)
                .foregroundColor(.secondary)

            Spacer()

            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))

                TextField("Search", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 12))
                    .frame(width: 120)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: NSColor(white: 0.2, alpha: 1.0)))
            .cornerRadius(6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Data Loading

    private func loadEffectTypes() {
        guard let types = engineBridge.getEffectTypes(), !types.isEmpty else {
            effectTypes = []
            return
        }

        // Sort alphabetically ascending (A-Z)
        let sortedTypes = types.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        effectTypes = sortedTypes.map { EffectTypeItem(name: $0) }
    }
}

// MARK: - Effect Grid Cell (SwiftUI wrapper for AppKit drag source)

struct EffectGridCell: View {
    let effect: EffectTypeItem
    let isSelected: Bool
    var onSelect: () -> Void

    var body: some View {
        DraggableEffectCellView(
            effectName: effect.name,
            isSelected: isSelected,
            onSelect: onSelect
        )
        .frame(width: 70, height: 70)
    }
}

// MARK: - AppKit Drag Source View

/// NSViewRepresentable wrapper that provides proper AppKit drag source support
struct DraggableEffectCellView: NSViewRepresentable {
    let effectName: String
    let isSelected: Bool
    var onSelect: () -> Void

    func makeNSView(context: Context) -> EffectDragSourceView {
        let view = EffectDragSourceView()
        view.effectName = effectName
        view.effectColor = nsColorForEffectTypeName(effectName)
        view.isSelected = isSelected
        view.onSelect = onSelect
        return view
    }

    func updateNSView(_ nsView: EffectDragSourceView, context: Context) {
        nsView.effectName = effectName
        nsView.effectColor = nsColorForEffectTypeName(effectName)
        nsView.isSelected = isSelected
        nsView.onSelect = onSelect
        nsView.needsDisplay = true
    }
}

/// Custom NSView that can initiate drags with the correct pasteboard type
class EffectDragSourceView: NSView, NSDraggingSource {
    var effectName: String = ""
    var effectColor: NSColor = .gray
    var isSelected: Bool = false
    var onSelect: (() -> Void)?

    private var mouseDownLocation: NSPoint = .zero
    private let dragThreshold: CGFloat = 3.0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = self.bounds

        // Draw selection background if selected
        if isSelected {
            NSColor.controlAccentColor.withAlphaComponent(0.3).setFill()
            let bgPath = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
            bgPath.fill()

            NSColor.controlAccentColor.setStroke()
            bgPath.lineWidth = 2
            bgPath.stroke()
        }

        // Draw effect icon (colored square with SF Symbol)
        let iconSize: CGFloat = 32
        let iconX = (bounds.width - iconSize) / 2
        let iconY: CGFloat = 6
        let iconRect = NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize)

        effectColor.setFill()
        let iconPath = NSBezierPath(roundedRect: iconRect, xRadius: 6, yRadius: 6)
        iconPath.fill()

        // Draw SF Symbol icon
        let symbolName = iconForEffect(effectName)
        if let symbolImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: effectName) {
            // Configure symbol with hierarchical rendering for white color
            var config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            config = config.applying(.init(paletteColors: [.white]))

            if let configuredImage = symbolImage.withSymbolConfiguration(config) {
                // Center the symbol in the icon rect
                let imageSize = configuredImage.size
                let drawX = iconRect.midX - imageSize.width / 2
                let drawY = iconRect.midY - imageSize.height / 2
                configuredImage.draw(in: NSRect(x: drawX, y: drawY, width: imageSize.width, height: imageSize.height))
            }
        } else {
            // Fallback: draw first letter if symbol not found
            let letter = String(effectName.prefix(1)).uppercased()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 14),
                .foregroundColor: NSColor.white
            ]
            let letterSize = letter.size(withAttributes: attributes)
            let letterX = iconRect.midX - letterSize.width / 2
            let letterY = iconRect.midY - letterSize.height / 2
            letter.draw(at: NSPoint(x: letterX, y: letterY), withAttributes: attributes)
        }

        // Draw effect name
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let fullNameAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]

        let nameY = iconY + iconSize + 4
        let nameRect = NSRect(x: 4, y: nameY, width: bounds.width - 8, height: bounds.height - nameY - 4)
        effectName.draw(in: nameRect, withAttributes: fullNameAttributes)
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow

        // Double-click to add effect to selected cell
        if event.clickCount == 2 {
            onSelect?()
            NotificationCenter.default.post(
                name: Notification.Name("XLApplyEffectFromCommandPalette"),
                object: nil,
                userInfo: ["effectName": effectName]
            )
            return
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let currentLocation = event.locationInWindow
        let dx = currentLocation.x - mouseDownLocation.x
        let dy = currentLocation.y - mouseDownLocation.y
        let distance = sqrt(dx * dx + dy * dy)

        // Only start drag if mouse moved beyond threshold
        if distance > dragThreshold {
            startDrag(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let currentLocation = event.locationInWindow
        let dx = currentLocation.x - mouseDownLocation.x
        let dy = currentLocation.y - mouseDownLocation.y
        let distance = sqrt(dx * dx + dy * dy)

        // If didn't drag, treat as click for selection
        if distance <= dragThreshold {
            onSelect?()
        }
    }

    private func startDrag(with event: NSEvent) {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(effectName, forType: XLEffectTypePasteboardType)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)

        // Create drag image from view
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        draw(bounds)
        image.unlockFocus()

        draggingItem.setDraggingFrame(bounds, contents: image)

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return context == .outsideApplication ? [] : .copy
    }
}

// MARK: - Preview

#Preview {
    EffectPaletteGridView(engineBridge: XLEngineBridge())
        .frame(width: 250, height: 400)
}
