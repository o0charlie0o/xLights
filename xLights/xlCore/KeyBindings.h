/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#pragma once

#include <string>
#include <vector>
#include <memory>
#include <optional>
#include <functional>

namespace xlCore {

/// Key scope determines where key bindings are active
enum class KeyScope {
    All,        ///< Active everywhere
    Setup,      ///< Active in setup tab
    Layout,     ///< Active in layout tab
    Sequence,   ///< Active in sequencer
    Invalid     ///< Invalid binding
};

/// Virtual key codes (platform-independent)
/// Uses values compatible with wxWidgets WXK_* constants for easier bridging.
/// Printable ASCII characters (32-126) use their ASCII values directly.
/// Special keys use values >= 0x100 to avoid conflicts.
enum class KeyCode : int {
    None = 0,

    // Printable characters use their ASCII values (32-126)
    // e.g., Space = 0x20 (32), 'A' = 0x41 (65), etc.

    // Navigation and control keys (non-printable, >= 0x100)
    Backspace = 0x08,   // ASCII backspace
    Tab = 0x09,         // ASCII tab
    Return = 0x0D,      // ASCII carriage return (Enter)
    Escape = 0x1B,      // ASCII escape
    Space = 0x20,       // ASCII space (also printable)

    // Special keys (use high values to avoid ASCII conflicts)
    Delete = 0x100,
    Insert = 0x101,

    // Arrow keys
    Left = 0x102,
    Up = 0x103,
    Right = 0x104,
    Down = 0x105,

    // Home/End/Page
    Home = 0x106,
    End = 0x107,
    PageUp = 0x108,
    PageDown = 0x109,

    // Pause
    Pause = 0x10A,

    // Function keys
    F1 = 0x110,
    F2 = 0x111,
    F3 = 0x112,
    F4 = 0x113,
    F5 = 0x114,
    F6 = 0x115,
    F7 = 0x116,
    F8 = 0x117,
    F9 = 0x118,
    F10 = 0x119,
    F11 = 0x11A,
    F12 = 0x11B,
    F13 = 0x11C,
    F14 = 0x11D,
    F15 = 0x11E,
    F16 = 0x11F,
    F17 = 0x120,
    F18 = 0x121,
    F19 = 0x122,
    F20 = 0x123,
    F21 = 0x124,
    F22 = 0x125,
    F23 = 0x126,
    F24 = 0x127,
};

/// Converts scope enum to string
std::string scopeToString(KeyScope scope);

/// Converts string to scope enum
KeyScope stringToScope(const std::string& str);

/**
 * @brief Represents a single key binding configuration
 *
 * Supports standard key bindings, effect shortcuts, preset shortcuts,
 * and apply-setting shortcuts. Each binding tracks the key combination
 * (key + modifiers), type, scope, and optional effect/preset data.
 */
class KeyBinding {
public:
    /// Unique ID counter for bindings
    static int nextId();

    // Static key encoding/decoding methods

    /// Encode a key code to its string representation (e.g., "SPACE", "F1", "a")
    static std::string encodeKey(KeyCode key, bool shift) noexcept;

    /// Decode a string to key code
    static KeyCode decodeKey(const std::string& key) noexcept;

    /// Check if a character requires shift to type (e.g., !, @, #)
    static bool isShiftedKey(int ch) noexcept;

    /// Parse a key string like "CTRL+ALT+a" into components
    static std::string parseKey(const std::string& key, bool& ctrl, bool& alt,
                                bool& shift, bool& rawCtrl) noexcept;

    /// Get list of all possible key codes that can be bound
    static const std::vector<KeyCode>& getPossibleKeys();

    // Constructors

    /// Default constructor - creates disabled binding
    KeyBinding() = default;

    /// Standard binding constructor with key code
    KeyBinding(KeyCode key, bool disabled, const std::string& type,
               bool ctrl = false, bool alt = false, bool shift = false, bool rawCtrl = false);

    /// Standard binding constructor with string key
    KeyBinding(const std::string& key, bool disabled, const std::string& type,
               bool ctrl = false, bool alt = false, bool shift = false, bool rawCtrl = false);

    /// Effect binding constructor with key code
    KeyBinding(KeyCode key, bool disabled, const std::string& effectName,
               const std::string& effectSettings, const std::string& version,
               bool ctrl = false, bool alt = false, bool shift = false, bool rawCtrl = false);

    /// Effect binding constructor with string key
    KeyBinding(const std::string& key, bool disabled, const std::string& effectName,
               const std::string& effectSettings, const std::string& version,
               bool ctrl = false, bool alt = false, bool shift = false, bool rawCtrl = false);

    /// Preset binding constructor with key code
    KeyBinding(bool disabled, KeyCode key, const std::string& presetName,
               bool ctrl, bool alt, bool shift, bool rawCtrl);

    /// Preset binding constructor with string key
    KeyBinding(bool disabled, const std::string& key, const std::string& presetName,
               bool ctrl, bool alt, bool shift, bool rawCtrl);

    /// Apply-setting binding constructor with key code
    KeyBinding(bool disabled, KeyCode key, const std::string& settings,
               const std::string& version, bool ctrl, bool alt, bool shift, bool rawCtrl,
               bool isApplySetting);

    /// Apply-setting binding constructor with string key
    KeyBinding(bool disabled, const std::string& key, const std::string& settings,
               const std::string& version, bool ctrl, bool alt, bool shift, bool rawCtrl,
               bool isApplySetting);

    // Accessors

    int getId() const noexcept { return _id; }
    const std::string& getType() const noexcept { return _type; }
    KeyCode getKey() const noexcept { return _key; }
    const std::string& getEffectString() const noexcept { return _effectString; }
    const std::string& getEffectName() const noexcept { return _effectName; }
    const std::string& getEffectDataVersion() const noexcept { return _effectDataVersion; }
    bool requiresRawControl() const noexcept { return _rawCtrl; }
    bool requiresControl() const noexcept { return _ctrl; }
    bool requiresAlt() const noexcept { return _alt; }
    bool requiresShift() const noexcept { return _shift; }
    bool isDisabled() const noexcept { return _disabled; }
    KeyScope getScope() const noexcept { return _scope; }
    const std::string& getTip() const noexcept { return _tip; }

    /// Check if binding is active in given scope
    bool inScope(KeyScope scope) const noexcept { return scope == _scope || _scope == KeyScope::All; }

    /// Check if this binding matches the given key
    bool isKey(KeyCode key) const noexcept { return _key == key; }

    // Mutators

    void setControl(bool ctrl) { _ctrl = ctrl; }
    void setRawControl(bool rawCtrl) { _rawCtrl = rawCtrl; }
    void setShift(bool shift) { _shift = shift; }
    void setAlt(bool alt) { _alt = alt; }
    void setKey(const std::string& key);
    void setKey(KeyCode key);
    void setEffectName(const std::string& effect) { _effectName = effect; }
    void setEffectString(const std::string& effectString) { _effectString = effectString; }
    void setDisabled(bool disabled) { _disabled = disabled; }

    // Description methods

    /// Get human-readable description of the binding
    std::string description() const noexcept;

    /// Get human-readable description of just the key combination
    std::string keyDescription() const noexcept;

    // Comparison methods

    /// Check if this binding conflicts with another (same key combo, overlapping scope)
    bool isDuplicateKey(const KeyBinding& other) const;

    /// Check if a key is equivalent (e.g., numpad vs regular)
    bool isEquivalentKey(KeyCode key) const noexcept;

    /// Compare control key states, accounting for platform differences
    static bool isControlEqual(const KeyBinding& binding, bool ctrl, bool rawCtrl);

private:
    void initFromType(const std::string& type);
    void initTip(const std::string& type);

    int _id = -1;
    std::string _type;
    std::string _effectName;
    std::string _effectString;
    std::string _effectDataVersion;
    std::string _tip;
    bool _ctrl = false;
    bool _rawCtrl = false;  // macOS Cmd key
    bool _alt = false;
    bool _shift = false;
    bool _disabled = true;
    KeyScope _scope = KeyScope::Invalid;
    KeyCode _key = KeyCode::None;
};

/**
 * @brief Manages a collection of key bindings
 *
 * Handles loading, saving, and lookup of key bindings from XML files.
 * Compatible with the legacy xLights key_bindings.xml format.
 */
class KeyBindingMap {
public:
    KeyBindingMap() = default;

    /// Load default key bindings
    void loadDefaults() noexcept;

    /// Load bindings from XML file
    /// @param path Full path to key_bindings.xml
    /// @return true if loaded successfully
    bool loadFromFile(const std::string& path) noexcept;

    /// Save bindings to the originally opened file
    bool save() const noexcept;

    /// Save bindings to specified XML file
    /// @param path Full path to save to
    /// @return true if saved successfully
    bool saveToFile(const std::string& path) const noexcept;

    /// Add a new key binding
    /// @return The ID of the added binding
    int addBinding(const KeyBinding& binding);

    /// Delete a binding by ID
    void deleteBinding(int id);

    /// Find a binding matching the given key combination and scope
    /// @param key The key code pressed
    /// @param ctrl Control key state
    /// @param alt Alt key state
    /// @param shift Shift key state
    /// @param rawCtrl Raw control (Cmd on macOS) state
    /// @param scope Current application scope
    /// @return Shared pointer to matching binding, or nullptr if not found
    std::shared_ptr<const KeyBinding> find(KeyCode key, bool ctrl, bool alt,
                                           bool shift, bool rawCtrl,
                                           KeyScope scope) const noexcept;

    /// Get all bindings (mutable)
    std::vector<KeyBinding>& getBindings() { return _bindings; }

    /// Get all bindings (const)
    const std::vector<KeyBinding>& getBindings() const { return _bindings; }

    /// Get a specific binding by ID
    KeyBinding* getBinding(int id);
    const KeyBinding* getBinding(int id) const;

    /// Check if a binding would conflict with existing bindings
    bool isDuplicateKey(const KeyBinding& binding) const;

    /// Dump all bindings to a string for debugging
    std::string dump() const noexcept;

    /// Get the path of the currently loaded file
    const std::string& getFilePath() const { return _filePath; }

private:
    std::vector<KeyBinding> _bindings;
    std::string _filePath;
};

/// Get the list of all known binding types and their default scopes
const std::vector<std::pair<std::string, KeyScope>>& getKeyBindingTypes();

/// Get the list of default key bindings
const std::vector<KeyBinding>& getDefaultBindings();

/// Get the tooltip text for a binding type
std::string getBindingTip(const std::string& type);

} // namespace xlCore
