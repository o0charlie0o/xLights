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

// MARK: - Command Definition

struct XLCommand: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let icon: String?
    let category: String
    let shortcut: String?
    let action: () -> Void

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: XLCommand, rhs: XLCommand) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Command Palette State

class XLCommandPaletteState: ObservableObject {
    nonisolated(unsafe) static let shared = XLCommandPaletteState()

    @Published var isVisible = false
    @Published var searchText = ""
    @Published var selectedIndex = 0
    @Published var commands: [XLCommand] = []

    var filteredCommands: [XLCommand] {
        if searchText.isEmpty {
            return commands
        }
        let words = searchText.lowercased().split(separator: " ").map(String.init)
        if words.isEmpty {
            return commands
        }
        return commands.filter { command in
            let searchable = [
                command.title.lowercased(),
                command.category.lowercased(),
                command.subtitle?.lowercased() ?? ""
            ].joined(separator: " ")
            return words.allSatisfy { searchable.contains($0) }
        }
    }

    private init() {
        // queue: nil means the closure runs synchronously on the posting thread.
        // Since all notifications are posted from the main thread (event monitor),
        // this ensures @Published changes are picked up by SwiftUI immediately.
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("XLToggleCommandPalette"),
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.toggle()
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("XLDismissCommandPalette"),
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.hide()
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("XLCommandPaletteInput"),
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.handleInput(notification)
        }
    }

    func show() {
        searchText = ""
        selectedIndex = 0
        loadCommands()
        isVisible = true
        XLSetCommandPaletteVisible(true)
    }

    func hide() {
        isVisible = false
        XLSetCommandPaletteVisible(false)
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func handleInput(_ notification: Notification) {
        guard let action = notification.userInfo?["action"] as? String else {
            NSLog("CommandPalette: handleInput called with no action in userInfo")
            return
        }

        NSLog("CommandPalette: handleInput action='%@' searchText='%@' selectedIndex=%d filteredCount=%d",
              action, searchText, selectedIndex, filteredCommands.count)

        switch action {
        case "type":
            if let text = notification.userInfo?["text"] as? String {
                searchText += text
                selectedIndex = 0
                NSLog("CommandPalette: typed '%@' -> searchText='%@' filteredCount=%d",
                      text, searchText, filteredCommands.count)
                for (i, cmd) in filteredCommands.prefix(5).enumerated() {
                    NSLog("CommandPalette:   [%d] %@", i, cmd.title)
                }
            }
        case "backspace":
            if !searchText.isEmpty {
                searchText.removeLast()
                selectedIndex = 0
                NSLog("CommandPalette: backspace -> searchText='%@' filteredCount=%d", searchText, filteredCommands.count)
            }
        case "clearAll":
            searchText = ""
            selectedIndex = 0
            NSLog("CommandPalette: clearAll -> filteredCount=%d", filteredCommands.count)
        case "up":
            let count = filteredCommands.count
            NSLog("CommandPalette: up -> count=%d selectedIndex=%d", count, selectedIndex)
            if count > 0 {
                selectedIndex = (selectedIndex - 1 + count) % count
                NSLog("CommandPalette: up -> new selectedIndex=%d", selectedIndex)
            }
        case "down":
            let count = filteredCommands.count
            NSLog("CommandPalette: down -> count=%d selectedIndex=%d", count, selectedIndex)
            if count > 0 {
                selectedIndex = (selectedIndex + 1) % count
                NSLog("CommandPalette: down -> new selectedIndex=%d", selectedIndex)
            }
        case "execute":
            let filtered = filteredCommands
            NSLog("CommandPalette: execute -> selectedIndex=%d filteredCount=%d", selectedIndex, filtered.count)
            if selectedIndex < filtered.count {
                let command = filtered[selectedIndex]
                NSLog("CommandPalette: executing '%@'", command.title)
                hide()
                command.action()
            }
        default:
            NSLog("CommandPalette: unknown action '%@'", action)
            break
        }
    }
}

// MARK: - Command Palette View

struct XLCommandPaletteView: View {
    @ObservedObject var state: XLCommandPaletteState

    var body: some View {
        let filtered = state.filteredCommands
        VStack(spacing: 0) {
            // Search field display (input handled via event monitor)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))

                Text(state.searchText.isEmpty ? "Type a command..." : state.searchText)
                    .font(.system(size: 14))
                    .foregroundColor(state.searchText.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !state.searchText.isEmpty {
                    Button(action: {
                        state.searchText = ""
                        state.selectedIndex = 0
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Commands list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { index, command in
                            CommandRow(
                                command: command,
                                isSelected: index == state.selectedIndex
                            )
                            .id(command.id)
                            .onTapGesture {
                                state.selectedIndex = index
                                state.hide()
                                command.action()
                            }
                        }

                        if filtered.isEmpty {
                            Text("No commands found")
                                .foregroundColor(.secondary)
                                .font(.system(size: 13))
                                .padding(.vertical, 20)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 300)
                .onChange(of: state.selectedIndex) { _, newIndex in
                    if newIndex < filtered.count {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(filtered[newIndex].id, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(width: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Command Loading

extension XLCommandPaletteState {
    func loadCommands() {
        commands = [
            // File commands
            XLCommand(title: "New Sequence", subtitle: "Create a new sequence", icon: "doc.badge.plus", category: "File", shortcut: "⌘N") {
                print("New Sequence")
            },
            XLCommand(title: "Open Sequence", subtitle: "Open an existing sequence", icon: "folder", category: "File", shortcut: "⌘O") {
                print("Open Sequence")
            },
            XLCommand(title: "Save", subtitle: "Save current sequence", icon: "square.and.arrow.down", category: "File", shortcut: "⌘S") {
                print("Save")
            },
            XLCommand(title: "Export Video", subtitle: "Export sequence as video file", icon: "film", category: "File", shortcut: nil) {
                print("Export Video")
            },

            // Edit commands
            XLCommand(title: "Undo", subtitle: "Undo last action", icon: "arrow.uturn.backward", category: "Edit", shortcut: "⌘Z") {
                print("Undo")
            },
            XLCommand(title: "Redo", subtitle: "Redo last undone action", icon: "arrow.uturn.forward", category: "Edit", shortcut: "⇧⌘Z") {
                print("Redo")
            },
            XLCommand(title: "Cut", subtitle: "Cut selected effects", icon: "scissors", category: "Edit", shortcut: "⌘X") {
                print("Cut")
            },
            XLCommand(title: "Copy", subtitle: "Copy selected effects", icon: "doc.on.doc", category: "Edit", shortcut: "⌘C") {
                print("Copy")
            },
            XLCommand(title: "Paste", subtitle: "Paste effects from clipboard", icon: "doc.on.clipboard", category: "Edit", shortcut: "⌘V") {
                print("Paste")
            },
            XLCommand(title: "Select All", subtitle: "Select all effects in row", icon: "checkmark.circle", category: "Edit", shortcut: "⌘A") {
                print("Select All")
            },

            // View commands
            XLCommand(title: "Zoom In", subtitle: "Zoom in on timeline", icon: "plus.magnifyingglass", category: "View", shortcut: "⌘+") {
                print("Zoom In")
            },
            XLCommand(title: "Zoom Out", subtitle: "Zoom out on timeline", icon: "minus.magnifyingglass", category: "View", shortcut: "⌘-") {
                print("Zoom Out")
            },
            XLCommand(title: "Zoom to Fit", subtitle: "Fit entire sequence in view", icon: "arrow.left.and.right.righttriangle.left.righttriangle.right", category: "View", shortcut: "⌘0") {
                print("Zoom to Fit")
            },
            XLCommand(title: "Zoom to Selection", subtitle: "Zoom to fit selected effects or waveform region", icon: "selection.pin.in.out", category: "View", shortcut: "Y") {
                NotificationCenter.default.post(name: NSNotification.Name("XLZoomToSelection"), object: nil)
            },
            XLCommand(title: "Toggle Inspector", subtitle: "Show or hide the inspector panel", icon: "sidebar.right", category: "View", shortcut: nil) {
                print("Toggle Inspector")
            },
            XLCommand(title: "Toggle Palettes", subtitle: "Show or hide effect palettes", icon: "rectangle.split.1x2", category: "View", shortcut: nil) {
                print("Toggle Palettes")
            },

            // Playback commands
            XLCommand(title: "Play/Pause", subtitle: "Toggle playback", icon: "play.fill", category: "Playback", shortcut: "Space") {
                print("Play/Pause")
            },
            XLCommand(title: "Stop", subtitle: "Stop playback and reset", icon: "stop.fill", category: "Playback", shortcut: nil) {
                print("Stop")
            },
            XLCommand(title: "Go to Start", subtitle: "Jump to beginning of sequence", icon: "backward.end.fill", category: "Playback", shortcut: "⌘←") {
                print("Go to Start")
            },
            XLCommand(title: "Go to End", subtitle: "Jump to end of sequence", icon: "forward.end.fill", category: "Playback", shortcut: "⌘→") {
                print("Go to End")
            },

            // Effect commands
            XLCommand(title: "Add Effect", subtitle: "Add a new effect at cursor", icon: "plus.circle", category: "Effects", shortcut: nil) {
                print("Add Effect")
            },
            XLCommand(title: "Delete Effect", subtitle: "Delete selected effects", icon: "trash", category: "Effects", shortcut: "⌫") {
                print("Delete Effect")
            },
            XLCommand(title: "Duplicate Effect", subtitle: "Duplicate selected effects", icon: "plus.square.on.square", category: "Effects", shortcut: "⌘D") {
                print("Duplicate Effect")
            },
            XLCommand(title: "Fill Region from Timing", subtitle: "Copy effect to every timing mark in region", icon: "rectangle.stack.badge.plus", category: "Effects", shortcut: nil) {
                NotificationCenter.default.post(name: NSNotification.Name("XLFillRegionFromTiming"), object: nil, userInfo: ["asSymbol": false])
            },
            XLCommand(title: "Fill Region from Timing as Symbol", subtitle: "Fill region with symbol-linked copies", icon: "link.badge.plus", category: "Effects", shortcut: nil) {
                NotificationCenter.default.post(name: NSNotification.Name("XLFillRegionFromTiming"), object: nil, userInfo: ["asSymbol": true])
            },

            // Timing commands
            XLCommand(title: "Add Timing Mark", subtitle: "Add timing mark at cursor", icon: "metronome", category: "Timing", shortcut: "T") {
                print("Add Timing Mark")
            },
            XLCommand(title: "Snap to Grid", subtitle: "Toggle snap to grid", icon: "square.grid.3x3", category: "Timing", shortcut: nil) {
                print("Snap to Grid")
            },

            // Render commands
            XLCommand(title: "Render All", subtitle: "Render entire sequence", icon: "cpu", category: "Render", shortcut: "⌘R") {
                print("Render All")
            },
            XLCommand(title: "Render Selection", subtitle: "Render selected effects only", icon: "cpu", category: "Render", shortcut: nil) {
                print("Render Selection")
            },

            // Tools
            XLCommand(title: "Check Sequence", subtitle: "Validate sequence for errors", icon: "checkmark.shield", category: "Tools", shortcut: nil) {
                print("Check Sequence")
            },
            XLCommand(title: "Package Sequence", subtitle: "Package sequence for sharing", icon: "shippingbox", category: "Tools", shortcut: nil) {
                print("Package Sequence")
            },
            XLCommand(title: "Preferences", subtitle: "Open application preferences", icon: "gearshape", category: "Settings", shortcut: "⌘,") {
                print("Preferences")
            },
        ]
    }
}

// MARK: - Command Row

struct CommandRow: View {
    let command: XLCommand
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Icon
            if let iconName = command.icon {
                Image(systemName: iconName)
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .white : .secondary)
                    .frame(width: 20)
            } else {
                Color.clear.frame(width: 20)
            }

            // Title and subtitle
            VStack(alignment: .leading, spacing: 1) {
                Text(command.title)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .white : .primary)

                if let subtitle = command.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                }
            }

            Spacer()

            // Category badge
            Text(command.category)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.15))
                )

            // Keyboard shortcut
            if let shortcut = command.shortcut {
                Text(shortcut)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .padding(.horizontal, 4)
    }
}

// MARK: - Command Palette Overlay

struct XLCommandPaletteOverlay: View {
    @ObservedObject var state = XLCommandPaletteState.shared

    var body: some View {
        ZStack {
            if state.isVisible {
                // Dimmed background
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        state.hide()
                    }

                // Command palette
                VStack {
                    XLCommandPaletteView(state: state)
                        .padding(.top, 80)
                    Spacer()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: state.isVisible)
    }
}
