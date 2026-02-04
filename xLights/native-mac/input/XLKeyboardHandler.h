/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Key scope determines where key bindings are active.
 * Mirrors xlCore::KeyScope enum values.
 */
typedef NS_ENUM(NSInteger, XLKeyScope) {
    XLKeyScopeAll = 0,      ///< Active everywhere
    XLKeyScopeSetup = 1,    ///< Active in setup tab
    XLKeyScopeLayout = 2,   ///< Active in layout tab
    XLKeyScopeSequence = 3, ///< Active in sequencer
    XLKeyScopeInvalid = 4   ///< Invalid binding
};

/**
 * Protocol for handling keyboard actions.
 * Implement this to receive action callbacks when key bindings match.
 */
@protocol XLKeyboardActionDelegate <NSObject>

/**
 * Called when a key binding matches and should be executed.
 *
 * @param actionType The type of action (e.g., "PLAY", "SAVE_SEQUENCE", "EFFECT")
 * @param effectName For EFFECT/PRESET types, the effect or preset name
 * @param effectSettings For EFFECT/APPLYSETTING types, the effect settings string
 * @param scope The current scope where the key was pressed
 * @return YES if the action was handled, NO otherwise
 */
- (BOOL)performKeyAction:(NSString *)actionType
              effectName:(nullable NSString *)effectName
          effectSettings:(nullable NSString *)effectSettings
                 inScope:(XLKeyScope)scope;

@optional

/**
 * Called when a key is pressed but no binding was found.
 * Allows delegate to handle unbound keys.
 */
- (void)keyPressedWithNoBinding:(NSEvent *)event inScope:(XLKeyScope)scope;

@end

/**
 * Native macOS keyboard event handler that integrates with the xlCore key binding system.
 *
 * This class intercepts keyboard events and routes them to the appropriate actions
 * based on the loaded key bindings configuration. It handles the conversion between
 * macOS-specific key codes and modifiers to the xlCore key binding format.
 *
 * Usage:
 *   XLKeyboardHandler *handler = [[XLKeyboardHandler alloc] initWithShowFolderPath:showPath];
 *   handler.delegate = self;
 *
 *   // In your view controller's keyDown:
 *   - (void)keyDown:(NSEvent *)event {
 *       if (![self.keyboardHandler handleKeyEvent:event inScope:self.currentScope]) {
 *           [super keyDown:event];
 *       }
 *   }
 */
@interface XLKeyboardHandler : NSObject

/// Delegate that receives action callbacks
@property (nonatomic, weak, nullable) id<XLKeyboardActionDelegate> delegate;

/// Whether key bindings have been successfully loaded
@property (nonatomic, readonly) BOOL bindingsLoaded;

/// Path to the show folder (where key_bindings.xml is located)
@property (nonatomic, readonly, nullable) NSString *showFolderPath;

/// Number of bindings currently loaded
@property (nonatomic, readonly) NSUInteger bindingCount;

#pragma mark - Initialization

/**
 * Initialize with path to show folder containing key_bindings.xml
 *
 * @param path Full path to the show folder
 * @return Initialized handler, or nil if path is invalid
 */
- (nullable instancetype)initWithShowFolderPath:(nullable NSString *)path;

/**
 * Initialize with default bindings (no custom key_bindings.xml)
 */
- (instancetype)init;

#pragma mark - Key Binding Management

/**
 * Load or reload key bindings from the show folder.
 * If no key_bindings.xml exists, default bindings will be used.
 */
- (void)loadKeyBindings;

/**
 * Reload key bindings (alias for loadKeyBindings for convenience)
 */
- (void)reloadKeyBindings;

/**
 * Update the show folder path and reload bindings.
 *
 * @param path New path to the show folder
 */
- (void)setShowFolderPath:(nullable NSString *)path;

#pragma mark - Event Handling

/**
 * Handle a keyboard event and attempt to match it to a binding.
 *
 * This method converts the NSEvent to xlCore key codes and modifiers,
 * looks up a matching binding, and if found, calls the delegate.
 *
 * @param event The keyboard event to handle
 * @param scope The current application scope
 * @return YES if the event was handled (binding found and delegate returned YES), NO otherwise
 */
- (BOOL)handleKeyEvent:(NSEvent *)event inScope:(XLKeyScope)scope;

/**
 * Check if a key event would match any binding without executing it.
 *
 * @param event The keyboard event to check
 * @param scope The current application scope
 * @return YES if a binding exists for this key combination
 */
- (BOOL)hasBindingForKeyEvent:(NSEvent *)event inScope:(XLKeyScope)scope;

#pragma mark - Binding Information

/**
 * Get the tooltip text for an action type.
 *
 * @param actionType The action type (e.g., "PLAY", "SAVE_SEQUENCE")
 * @return Human-readable description of the action
 */
- (nullable NSString *)tooltipForAction:(NSString *)actionType;

/**
 * Get the key combination string for an action type.
 * Returns the first matching binding if multiple exist.
 *
 * @param actionType The action type to look up
 * @return Key combination string (e.g., "Cmd+S") or nil if not bound
 */
- (nullable NSString *)shortcutStringForAction:(NSString *)actionType;

/**
 * Get a human-readable key combination string formatted for macOS.
 * Uses standard macOS modifier symbols.
 *
 * @param actionType The action type to look up
 * @return Formatted string with macOS symbols or nil if not bound
 */
- (nullable NSString *)macOSShortcutStringForAction:(NSString *)actionType;

/**
 * Get all actions that are bound in a specific scope.
 *
 * @param scope The scope to filter by (XLKeyScopeAll returns all bindings)
 * @return Array of action type strings
 */
- (NSArray<NSString *> *)actionsInScope:(XLKeyScope)scope;

#pragma mark - Key Code Utilities

/**
 * Convert an NSEvent key code to a human-readable string.
 *
 * @param keyCode The NSEvent keyCode value
 * @return String representation (e.g., "A", "Space", "F1")
 */
+ (NSString *)stringFromKeyCode:(unsigned short)keyCode;

/**
 * Get the xlCore KeyCode value from an NSEvent key code.
 *
 * @param keyCode The NSEvent keyCode value
 * @param characters The event's characters (for letter keys)
 * @return xlCore KeyCode integer value
 */
+ (int)xlCoreKeyCodeFromNSEventKeyCode:(unsigned short)keyCode
                            characters:(nullable NSString *)characters;

/**
 * Convert NSEventModifierFlags to individual modifier booleans.
 *
 * @param flags The modifier flags from NSEvent
 * @param outCmd Set to YES if Command key is held
 * @param outOption Set to YES if Option key is held
 * @param outControl Set to YES if Control key is held
 * @param outShift Set to YES if Shift key is held
 */
+ (void)parseModifierFlags:(NSEventModifierFlags)flags
                       cmd:(BOOL *)outCmd
                    option:(BOOL *)outOption
                   control:(BOOL *)outControl
                     shift:(BOOL *)outShift;

@end

NS_ASSUME_NONNULL_END
