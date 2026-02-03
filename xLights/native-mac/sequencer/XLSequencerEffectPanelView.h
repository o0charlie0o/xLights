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
#import "XLEffectPanelDescriptor.h"
#import "XLEffectPanelBuilder.h"

/// Container view that hosts a declaratively-built effect settings panel.
///
/// This view wraps XLEffectPanelBuilder to provide a self-contained effect
/// panel that can be dropped into a sidebar, inspector, or any other container.
/// It handles loading descriptors, building the panel, displaying placeholder
/// state, and forwarding settings changes via the builder delegate.
///
/// Typical usage:
/// @code
///   XLSequencerEffectPanelView *panelView = [[XLSequencerEffectPanelView alloc] initWithFrame:frame];
///   panelView.delegate = self;
///   [panelView loadEffectPanel:@"Bars" settings:currentSettings];
///   [containerView addSubview:panelView];
/// @endcode
@interface XLSequencerEffectPanelView : NSView

/// The descriptor for the currently loaded effect, or nil if placeholder state.
@property (nonatomic, strong, readonly) XLEffectPanelDescriptor *descriptor;

/// The current settings dictionary reflecting control state.
@property (nonatomic, strong, readonly) NSDictionary<NSString *, id> *settings;

/// Delegate receiving value change callbacks. Forwarded from the internal builder.
@property (nonatomic, weak) id<XLEffectPanelBuilderDelegate> delegate;

/// Load an effect panel for the given effect type with initial settings.
///
/// This replaces any previously loaded panel. If no descriptor is found for
/// the given effect name, a placeholder is shown instead.
///
/// @param effectName The effect name (e.g., "Bars", "Fire", "Color Wash").
/// @param settings Initial settings dictionary to populate controls.
- (void)loadEffectPanel:(NSString *)effectName
               settings:(NSDictionary<NSString *, id> *)settings;

/// Update settings on the currently loaded panel (e.g., for undo/redo).
///
/// Only keys present in the dictionary will be updated. Does nothing if
/// no panel is loaded.
///
/// @param settings Dictionary of key-value pairs to apply to controls.
- (void)updateSettings:(NSDictionary<NSString *, id> *)settings;

/// Retrieve the current settings from all controls.
///
/// @return Dictionary of all parameter key-value pairs, or empty dict if no panel loaded.
- (NSDictionary<NSString *, id> *)currentSettings;

/// Remove the current effect panel and show the placeholder state.
- (void)showPlaceholder;

@end
