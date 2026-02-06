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

@class XLEngineBridge;

/// Manages saving, loading, and organizing effect presets.
///
/// An effect preset captures the full settings map and palette of an effect,
/// allowing users to save frequently-used configurations and apply them later.
/// Presets are stored as plist files in <showfolder>/Presets/.
@interface XLEffectPresetsWindowController : NSWindowController <NSOutlineViewDataSource, NSOutlineViewDelegate>

/// Engine bridge for reading/writing effect parameters.
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Initialize with an engine bridge.
- (instancetype)initWithEngineBridge:(XLEngineBridge *)engineBridge;

/// Reload presets from disk.
- (void)reloadPresets;

/// Set the current effect ID that Save/Load buttons will operate on.
- (void)setCurrentEffectId:(NSInteger)effectId;

/// Save the current effect as a new preset.
/// @param effectId The effect ID to save from.
- (void)savePresetFromEffect:(NSInteger)effectId;

/// Apply a preset to the given effect.
/// @param presetName The name of the preset to load.
/// @param effectId The effect ID to apply settings to.
/// @return YES if the preset was applied successfully.
- (BOOL)applyPreset:(NSString *)presetName toEffect:(NSInteger)effectId;

/// Get all preset names, optionally filtered by effect type.
/// @param effectType Effect type to filter by (nil for all).
/// @return Array of preset name strings.
- (NSArray<NSString *> *)presetNamesForEffectType:(NSString *)effectType;

/// Delete a preset by name.
/// @param presetName The preset to delete.
/// @return YES if deleted successfully.
- (BOOL)deletePreset:(NSString *)presetName;

/// Rename a preset.
/// @param oldName Current preset name.
/// @param newName New preset name.
/// @return YES if renamed successfully.
- (BOOL)renamePreset:(NSString *)oldName toName:(NSString *)newName;

@end
