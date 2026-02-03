#pragma once

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
@class XLEffectPaletteView;

/// Delegate protocol for effect palette interactions.
@protocol XLEffectPaletteViewDelegate <NSObject>
@optional

/// Called when an effect type is selected (single click).
- (void)effectPaletteView:(XLEffectPaletteView *)paletteView didSelectEffectType:(NSString *)effectType;

/// Called when an effect type is double-clicked (apply to selection).
- (void)effectPaletteView:(XLEffectPaletteView *)paletteView didDoubleClickEffectType:(NSString *)effectType;

@end

/// A scrollable palette view that displays available effect types.
///
/// Effects can be dragged from this view onto the timeline (XLEffectsGridView)
/// to create new effects. The view displays effect types as items in a
/// collection view with icons and names.
///
/// This view uses the XLEffectTypePasteboardType for drag operations,
/// which is already supported by XLEffectsGridView.
@interface XLEffectPaletteView : NSView

/// The engine bridge used to fetch effect types.
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Delegate for selection callbacks.
@property (nonatomic, weak) id<XLEffectPaletteViewDelegate> delegate;

/// The currently selected effect type name, or nil if none.
@property (nonatomic, copy, readonly) NSString *selectedEffectType;

/// Height of each item in the palette. Default: 28.
@property (nonatomic, assign) CGFloat itemHeight;

/// Reload the effect types from the engine bridge.
- (void)reloadEffectTypes;

/// Select an effect type by name.
- (void)selectEffectType:(NSString *)effectType;

/// Filter effect types by search text. Pass nil or empty string to show all.
- (void)filterWithSearchText:(NSString *)searchText;

@end
