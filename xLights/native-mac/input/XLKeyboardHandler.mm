/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLKeyboardHandler.h"
#import <Carbon/Carbon.h>  // For kVK_* key codes

// Include the xlCore C++ header via Objective-C++ bridging
#ifdef __cplusplus
#include "../../xlCore/KeyBindings.h"
#endif

#pragma mark - Internal C++ Bridge

/**
 * Internal structure to hold binding match results.
 * We use this to bridge between the C++ KeyBindingMap and Objective-C.
 */
typedef struct {
    BOOL found;
    int keyCode;
    BOOL ctrl;
    BOOL alt;
    BOOL shift;
    BOOL rawCtrl;
    const char *actionType;
    const char *effectName;
    const char *effectSettings;
    const char *tip;
} XLKeyBindingMatch;

#pragma mark - NSEvent Key Code to xlCore KeyCode Mapping

/**
 * Maps macOS virtual key codes (from Carbon/HIToolbox) to xlCore::KeyCode values.
 * This is the core translation layer between macOS events and the platform-independent
 * key binding system.
 */
static int NSEventKeyCodeToXLCoreKeyCode(unsigned short keyCode, NSString *characters) {
    // Special keys first (non-printable)
    switch (keyCode) {
        // Function keys
        case kVK_F1:  return 0x110;  // xlCore::KeyCode::F1
        case kVK_F2:  return 0x111;
        case kVK_F3:  return 0x112;
        case kVK_F4:  return 0x113;
        case kVK_F5:  return 0x114;
        case kVK_F6:  return 0x115;
        case kVK_F7:  return 0x116;
        case kVK_F8:  return 0x117;
        case kVK_F9:  return 0x118;
        case kVK_F10: return 0x119;
        case kVK_F11: return 0x11A;
        case kVK_F12: return 0x11B;
        case kVK_F13: return 0x11C;
        case kVK_F14: return 0x11D;
        case kVK_F15: return 0x11E;
        case kVK_F16: return 0x11F;
        case kVK_F17: return 0x120;
        case kVK_F18: return 0x121;
        case kVK_F19: return 0x122;
        case kVK_F20: return 0x123;

        // Navigation keys
        case kVK_Home:           return 0x106;  // xlCore::KeyCode::Home
        case kVK_End:            return 0x107;  // xlCore::KeyCode::End
        case kVK_PageUp:         return 0x108;  // xlCore::KeyCode::PageUp
        case kVK_PageDown:       return 0x109;  // xlCore::KeyCode::PageDown
        case kVK_LeftArrow:      return 0x102;  // xlCore::KeyCode::Left
        case kVK_RightArrow:     return 0x104;  // xlCore::KeyCode::Right
        case kVK_UpArrow:        return 0x103;  // xlCore::KeyCode::Up
        case kVK_DownArrow:      return 0x105;  // xlCore::KeyCode::Down

        // Editing keys
        case kVK_Delete:         return 0x08;   // xlCore::KeyCode::Backspace (macOS Delete = Backspace)
        case kVK_ForwardDelete:  return 0x100;  // xlCore::KeyCode::Delete
        case kVK_Help:           return 0x101;  // xlCore::KeyCode::Insert (Help key on older Macs)

        // Control keys
        case kVK_Escape:         return 0x1B;   // xlCore::KeyCode::Escape
        case kVK_Tab:            return 0x09;   // xlCore::KeyCode::Tab
        case kVK_Return:         return 0x0D;   // xlCore::KeyCode::Return
        case kVK_Space:          return 0x20;   // xlCore::KeyCode::Space

        // Keypad equivalents
        case kVK_ANSI_KeypadEnter:   return 0x0D;   // Return
        case kVK_ANSI_KeypadClear:   return 0x100;  // Delete
        case kVK_ANSI_Keypad0:       return '0';
        case kVK_ANSI_Keypad1:       return '1';
        case kVK_ANSI_Keypad2:       return '2';
        case kVK_ANSI_Keypad3:       return '3';
        case kVK_ANSI_Keypad4:       return '4';
        case kVK_ANSI_Keypad5:       return '5';
        case kVK_ANSI_Keypad6:       return '6';
        case kVK_ANSI_Keypad7:       return '7';
        case kVK_ANSI_Keypad8:       return '8';
        case kVK_ANSI_Keypad9:       return '9';
        case kVK_ANSI_KeypadPlus:    return '+';
        case kVK_ANSI_KeypadMinus:   return '-';
        case kVK_ANSI_KeypadMultiply: return '*';
        case kVK_ANSI_KeypadDivide:  return '/';
        case kVK_ANSI_KeypadDecimal: return '.';
        case kVK_ANSI_KeypadEquals:  return '=';

        default:
            break;
    }

    // For printable characters, use the characters string
    // This handles keyboard layout variations automatically
    if (characters.length > 0) {
        unichar ch = [characters characterAtIndex:0];
        // xlCore uses uppercase for letter keys
        if (ch >= 'a' && ch <= 'z') {
            return (int)(ch - 32);  // Convert to uppercase ASCII
        }
        if (ch >= 'A' && ch <= 'Z') {
            return (int)ch;
        }
        // Other printable ASCII
        if (ch >= 32 && ch < 127) {
            return (int)ch;
        }
    }

    // Fallback for ANSI keyboard layout letter keys when characters is empty
    // (can happen with some modifier combinations)
    switch (keyCode) {
        case kVK_ANSI_A: return 'A';
        case kVK_ANSI_B: return 'B';
        case kVK_ANSI_C: return 'C';
        case kVK_ANSI_D: return 'D';
        case kVK_ANSI_E: return 'E';
        case kVK_ANSI_F: return 'F';
        case kVK_ANSI_G: return 'G';
        case kVK_ANSI_H: return 'H';
        case kVK_ANSI_I: return 'I';
        case kVK_ANSI_J: return 'J';
        case kVK_ANSI_K: return 'K';
        case kVK_ANSI_L: return 'L';
        case kVK_ANSI_M: return 'M';
        case kVK_ANSI_N: return 'N';
        case kVK_ANSI_O: return 'O';
        case kVK_ANSI_P: return 'P';
        case kVK_ANSI_Q: return 'Q';
        case kVK_ANSI_R: return 'R';
        case kVK_ANSI_S: return 'S';
        case kVK_ANSI_T: return 'T';
        case kVK_ANSI_U: return 'U';
        case kVK_ANSI_V: return 'V';
        case kVK_ANSI_W: return 'W';
        case kVK_ANSI_X: return 'X';
        case kVK_ANSI_Y: return 'Y';
        case kVK_ANSI_Z: return 'Z';

        // Number keys
        case kVK_ANSI_0: return '0';
        case kVK_ANSI_1: return '1';
        case kVK_ANSI_2: return '2';
        case kVK_ANSI_3: return '3';
        case kVK_ANSI_4: return '4';
        case kVK_ANSI_5: return '5';
        case kVK_ANSI_6: return '6';
        case kVK_ANSI_7: return '7';
        case kVK_ANSI_8: return '8';
        case kVK_ANSI_9: return '9';

        // Punctuation (ANSI layout)
        case kVK_ANSI_Minus:        return '-';
        case kVK_ANSI_Equal:        return '=';
        case kVK_ANSI_LeftBracket:  return '[';
        case kVK_ANSI_RightBracket: return ']';
        case kVK_ANSI_Backslash:    return '\\';
        case kVK_ANSI_Semicolon:    return ';';
        case kVK_ANSI_Quote:        return '\'';
        case kVK_ANSI_Comma:        return ',';
        case kVK_ANSI_Period:       return '.';
        case kVK_ANSI_Slash:        return '/';
        case kVK_ANSI_Grave:        return '`';

        default:
            return 0;  // xlCore::KeyCode::None
    }
}

/**
 * Convert NSEvent keyCode to a human-readable string for display.
 */
static NSString *KeyCodeToString(unsigned short keyCode) {
    switch (keyCode) {
        case kVK_F1:  return @"F1";
        case kVK_F2:  return @"F2";
        case kVK_F3:  return @"F3";
        case kVK_F4:  return @"F4";
        case kVK_F5:  return @"F5";
        case kVK_F6:  return @"F6";
        case kVK_F7:  return @"F7";
        case kVK_F8:  return @"F8";
        case kVK_F9:  return @"F9";
        case kVK_F10: return @"F10";
        case kVK_F11: return @"F11";
        case kVK_F12: return @"F12";
        case kVK_F13: return @"F13";
        case kVK_F14: return @"F14";
        case kVK_F15: return @"F15";
        case kVK_F16: return @"F16";
        case kVK_F17: return @"F17";
        case kVK_F18: return @"F18";
        case kVK_F19: return @"F19";
        case kVK_F20: return @"F20";

        case kVK_Home:          return @"Home";
        case kVK_End:           return @"End";
        case kVK_PageUp:        return @"Page Up";
        case kVK_PageDown:      return @"Page Down";
        case kVK_LeftArrow:     return @"Left";
        case kVK_RightArrow:    return @"Right";
        case kVK_UpArrow:       return @"Up";
        case kVK_DownArrow:     return @"Down";

        case kVK_Delete:        return @"Delete";
        case kVK_ForwardDelete: return @"Forward Delete";
        case kVK_Escape:        return @"Escape";
        case kVK_Tab:           return @"Tab";
        case kVK_Return:        return @"Return";
        case kVK_Space:         return @"Space";

        default:
            return nil;  // Will use characters instead
    }
}

#pragma mark - XLKeyboardHandler Implementation

@interface XLKeyboardHandler () {
#ifdef __cplusplus
    std::unique_ptr<xlCore::KeyBindingMap> _bindingMap;
#else
    void *_bindingMap;
#endif
}

@property (nonatomic, readwrite) BOOL bindingsLoaded;
@property (nonatomic, readwrite, copy, nullable) NSString *showFolderPath;

@end

@implementation XLKeyboardHandler

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
#ifdef __cplusplus
        _bindingMap = std::make_unique<xlCore::KeyBindingMap>();
        _bindingMap->loadDefaults();
        _bindingsLoaded = YES;
#else
        _bindingsLoaded = NO;
#endif
    }
    return self;
}

- (instancetype)initWithShowFolderPath:(NSString *)path {
    self = [super init];
    if (self) {
        _showFolderPath = [path copy];
#ifdef __cplusplus
        _bindingMap = std::make_unique<xlCore::KeyBindingMap>();
#endif
        [self loadKeyBindings];
    }
    return self;
}

- (void)dealloc {
#ifdef __cplusplus
    _bindingMap.reset();
#endif
}

#pragma mark - Key Binding Management

- (void)loadKeyBindings {
#ifdef __cplusplus
    if (!_bindingMap) {
        _bindingMap = std::make_unique<xlCore::KeyBindingMap>();
    }

    if (_showFolderPath.length > 0) {
        NSString *keyBindingsPath = [_showFolderPath stringByAppendingPathComponent:@"key_bindings.xml"];
        std::string pathStr = keyBindingsPath.UTF8String ?: "";

        if (_bindingMap->loadFromFile(pathStr)) {
            _bindingsLoaded = YES;
            NSLog(@"XLKeyboardHandler: Loaded %lu key bindings from %@",
                  (unsigned long)_bindingMap->getBindings().size(), keyBindingsPath);
        } else {
            // loadFromFile creates defaults if file doesn't exist
            _bindingsLoaded = YES;
            NSLog(@"XLKeyboardHandler: Using default key bindings (no file at %@)", keyBindingsPath);
        }
    } else {
        _bindingMap->loadDefaults();
        _bindingsLoaded = YES;
        NSLog(@"XLKeyboardHandler: Using default key bindings (no show folder specified)");
    }
#else
    _bindingsLoaded = NO;
    NSLog(@"XLKeyboardHandler: C++ support not available, key bindings disabled");
#endif
}

- (void)reloadKeyBindings {
    [self loadKeyBindings];
}

- (void)setShowFolderPath:(NSString *)path {
    if (![_showFolderPath isEqualToString:path]) {
        _showFolderPath = [path copy];
        [self loadKeyBindings];
    }
}

- (NSUInteger)bindingCount {
#ifdef __cplusplus
    if (_bindingMap) {
        return _bindingMap->getBindings().size();
    }
#endif
    return 0;
}

#pragma mark - Event Handling

- (BOOL)handleKeyEvent:(NSEvent *)event inScope:(XLKeyScope)scope {
    if (!_bindingsLoaded || !_delegate) {
        return NO;
    }

#ifdef __cplusplus
    // Parse modifier flags
    // macOS convention: Cmd is the primary modifier (maps to "control" in bindings)
    // Control key maps to "rawControl"
    NSEventModifierFlags flags = event.modifierFlags;
    bool cmd = (flags & NSEventModifierFlagCommand) != 0;
    bool option = (flags & NSEventModifierFlagOption) != 0;
    bool control = (flags & NSEventModifierFlagControl) != 0;
    bool shift = (flags & NSEventModifierFlagShift) != 0;

    // Get the key code
    // For character keys, use charactersIgnoringModifiers to get the base character
    NSString *characters = event.charactersIgnoringModifiers;
    int xlKeyCode = NSEventKeyCodeToXLCoreKeyCode(event.keyCode, characters);

    if (xlKeyCode == 0) {
        // Unknown key
        if ([_delegate respondsToSelector:@selector(keyPressedWithNoBinding:inScope:)]) {
            [_delegate keyPressedWithNoBinding:event inScope:scope];
        }
        return NO;
    }

    // Convert to xlCore KeyCode enum
    xlCore::KeyCode key = static_cast<xlCore::KeyCode>(xlKeyCode);

    // Convert scope
    xlCore::KeyScope xlScope;
    switch (scope) {
        case XLKeyScopeAll:      xlScope = xlCore::KeyScope::All; break;
        case XLKeyScopeSetup:    xlScope = xlCore::KeyScope::Setup; break;
        case XLKeyScopeLayout:   xlScope = xlCore::KeyScope::Layout; break;
        case XLKeyScopeSequence: xlScope = xlCore::KeyScope::Sequence; break;
        default:                 xlScope = xlCore::KeyScope::Invalid; break;
    }

    // Look up the binding
    // macOS Cmd key maps to "control" in key bindings (standard macOS behavior)
    // macOS Control key maps to "rawControl"
    auto binding = _bindingMap->find(key, cmd, option, shift, control, xlScope);

    if (!binding) {
        // No binding found
        if ([_delegate respondsToSelector:@selector(keyPressedWithNoBinding:inScope:)]) {
            [_delegate keyPressedWithNoBinding:event inScope:scope];
        }
        return NO;
    }

    // Found a binding - call delegate
    NSString *actionType = [NSString stringWithUTF8String:binding->getType().c_str()];
    NSString *effectName = nil;
    NSString *effectSettings = nil;

    if (!binding->getEffectName().empty()) {
        effectName = [NSString stringWithUTF8String:binding->getEffectName().c_str()];
    }
    if (!binding->getEffectString().empty()) {
        effectSettings = [NSString stringWithUTF8String:binding->getEffectString().c_str()];
    }

    return [_delegate performKeyAction:actionType
                            effectName:effectName
                        effectSettings:effectSettings
                               inScope:scope];
#else
    return NO;
#endif
}

- (BOOL)hasBindingForKeyEvent:(NSEvent *)event inScope:(XLKeyScope)scope {
    if (!_bindingsLoaded) {
        return NO;
    }

#ifdef __cplusplus
    NSEventModifierFlags flags = event.modifierFlags;
    bool cmd = (flags & NSEventModifierFlagCommand) != 0;
    bool option = (flags & NSEventModifierFlagOption) != 0;
    bool control = (flags & NSEventModifierFlagControl) != 0;
    bool shift = (flags & NSEventModifierFlagShift) != 0;

    NSString *characters = event.charactersIgnoringModifiers;
    int xlKeyCode = NSEventKeyCodeToXLCoreKeyCode(event.keyCode, characters);

    if (xlKeyCode == 0) {
        return NO;
    }

    xlCore::KeyCode key = static_cast<xlCore::KeyCode>(xlKeyCode);

    xlCore::KeyScope xlScope;
    switch (scope) {
        case XLKeyScopeAll:      xlScope = xlCore::KeyScope::All; break;
        case XLKeyScopeSetup:    xlScope = xlCore::KeyScope::Setup; break;
        case XLKeyScopeLayout:   xlScope = xlCore::KeyScope::Layout; break;
        case XLKeyScopeSequence: xlScope = xlCore::KeyScope::Sequence; break;
        default:                 xlScope = xlCore::KeyScope::Invalid; break;
    }

    auto binding = _bindingMap->find(key, cmd, option, shift, control, xlScope);
    return binding != nullptr;
#else
    return NO;
#endif
}

#pragma mark - Binding Information

- (NSString *)tooltipForAction:(NSString *)actionType {
#ifdef __cplusplus
    std::string tip = xlCore::getBindingTip(actionType.UTF8String ?: "");
    if (!tip.empty()) {
        return [NSString stringWithUTF8String:tip.c_str()];
    }
#endif
    return nil;
}

- (NSString *)shortcutStringForAction:(NSString *)actionType {
#ifdef __cplusplus
    if (!_bindingMap) return nil;

    std::string type = actionType.UTF8String ?: "";
    for (const auto& binding : _bindingMap->getBindings()) {
        if (binding.getType() == type && !binding.isDisabled()) {
            std::string desc = binding.keyDescription();
            return [NSString stringWithUTF8String:desc.c_str()];
        }
    }
#endif
    return nil;
}

- (NSString *)macOSShortcutStringForAction:(NSString *)actionType {
#ifdef __cplusplus
    if (!_bindingMap) return nil;

    std::string type = actionType.UTF8String ?: "";
    for (const auto& binding : _bindingMap->getBindings()) {
        if (binding.getType() == type && !binding.isDisabled()) {
            NSMutableString *result = [NSMutableString string];

            // Use macOS standard modifier symbols
            // Control in bindings -> Cmd on macOS
            if (binding.requiresControl()) {
                [result appendString:@"\u2318"];  // Command symbol
            }
            // RawControl in bindings -> Control on macOS
            if (binding.requiresRawControl()) {
                [result appendString:@"\u2303"];  // Control symbol
            }
            if (binding.requiresAlt()) {
                [result appendString:@"\u2325"];  // Option symbol
            }
            if (binding.requiresShift()) {
                [result appendString:@"\u21E7"];  // Shift symbol
            }

            // Get the key name
            std::string keyStr = xlCore::KeyBinding::encodeKey(binding.getKey(), binding.requiresShift());
            [result appendString:[NSString stringWithUTF8String:keyStr.c_str()]];

            return result;
        }
    }
#endif
    return nil;
}

- (NSArray<NSString *> *)actionsInScope:(XLKeyScope)scope {
#ifdef __cplusplus
    if (!_bindingMap) return @[];

    xlCore::KeyScope xlScope;
    switch (scope) {
        case XLKeyScopeAll:      xlScope = xlCore::KeyScope::All; break;
        case XLKeyScopeSetup:    xlScope = xlCore::KeyScope::Setup; break;
        case XLKeyScopeLayout:   xlScope = xlCore::KeyScope::Layout; break;
        case XLKeyScopeSequence: xlScope = xlCore::KeyScope::Sequence; break;
        default:                 xlScope = xlCore::KeyScope::Invalid; break;
    }

    NSMutableArray *actions = [NSMutableArray array];
    for (const auto& binding : _bindingMap->getBindings()) {
        if (!binding.isDisabled() && binding.inScope(xlScope)) {
            NSString *action = [NSString stringWithUTF8String:binding.getType().c_str()];
            if (![actions containsObject:action]) {
                [actions addObject:action];
            }
        }
    }
    return actions;
#else
    return @[];
#endif
}

#pragma mark - Key Code Utilities

+ (NSString *)stringFromKeyCode:(unsigned short)keyCode {
    NSString *special = KeyCodeToString(keyCode);
    if (special) {
        return special;
    }

    // For character keys, use TIS to get the character
    TISInputSourceRef currentKeyboard = TISCopyCurrentKeyboardInputSource();
    if (currentKeyboard) {
        CFDataRef layoutData = (CFDataRef)TISGetInputSourceProperty(currentKeyboard, kTISPropertyUnicodeKeyLayoutData);
        if (layoutData) {
            const UCKeyboardLayout *keyboardLayout = (const UCKeyboardLayout *)CFDataGetBytePtr(layoutData);

            UInt32 keysDown = 0;
            UniChar chars[4];
            UniCharCount realLength;

            UCKeyTranslate(keyboardLayout,
                          keyCode,
                          kUCKeyActionDisplay,
                          0,
                          LMGetKbdType(),
                          kUCKeyTranslateNoDeadKeysBit,
                          &keysDown,
                          sizeof(chars) / sizeof(chars[0]),
                          &realLength,
                          chars);

            CFRelease(currentKeyboard);

            if (realLength > 0) {
                return [[NSString stringWithCharacters:chars length:realLength] uppercaseString];
            }
        }
        CFRelease(currentKeyboard);
    }

    return [NSString stringWithFormat:@"Key%d", keyCode];
}

+ (int)xlCoreKeyCodeFromNSEventKeyCode:(unsigned short)keyCode
                            characters:(NSString *)characters {
    return NSEventKeyCodeToXLCoreKeyCode(keyCode, characters);
}

+ (void)parseModifierFlags:(NSEventModifierFlags)flags
                       cmd:(BOOL *)outCmd
                    option:(BOOL *)outOption
                   control:(BOOL *)outControl
                     shift:(BOOL *)outShift {
    if (outCmd) *outCmd = (flags & NSEventModifierFlagCommand) != 0;
    if (outOption) *outOption = (flags & NSEventModifierFlagOption) != 0;
    if (outControl) *outControl = (flags & NSEventModifierFlagControl) != 0;
    if (outShift) *outShift = (flags & NSEventModifierFlagShift) != 0;
}

@end
