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

@class XLControllerInspectorViewController;
@class XLEngineBridge;

#pragma mark - Delegate Protocol

@protocol XLControllerInspectorDelegate <NSObject>

/// Called when a controller property has been modified through the inspector.
- (void)inspectorDidUpdateController:(XLControllerInspectorViewController *)inspector;

@end

#pragma mark - Disclosure Section

/// Reusable collapsible section view for inspector groups.
/// Displays a clickable header with disclosure triangle and title,
/// wrapping a content stack view that shows/hides with animation.
/// Collapsed/expanded state persists via NSUserDefaults.
@interface XLDisclosureSection : NSView

@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, strong, readonly) NSStackView *contentStackView;
@property (nonatomic, assign, getter=isExpanded) BOOL expanded;

- (instancetype)initWithTitle:(NSString *)title identifier:(NSString *)identifier;

/// Add a labeled row: label on the left, control on the right.
- (void)addRowWithLabel:(NSString *)label control:(NSView *)control;

/// Add a full-width view spanning the entire content area.
- (void)addFullWidthView:(NSView *)view;

@end

#pragma mark - Controller Inspector

/// NSViewController-based property inspector for lighting controllers.
///
/// Displays controller properties in collapsible disclosure groups
/// matching the Xcode inspector style. Designed for the Setup tab
/// sidebar in the native macOS xLights rebuild.
///
/// Sections:
///   - General (name, description, active state, ID)
///   - Connection (IP, serial port, protocol, universes, channels)
///   - Authentication (username/password, shown only for controllers supporting auth)
///   - Hardware (vendor/model/variant cascading dropdowns)
///   - Capabilities (read-only hardware limits)
///   - Upload (upload config, auto-upload, last upload time)
@interface XLControllerInspectorViewController : NSViewController

/// Delegate notified when controller properties change.
@property (nonatomic, weak) id<XLControllerInspectorDelegate> delegate;

/// Engine bridge for querying controller data and vendor lists.
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Populate the inspector with data from a controller dictionary.
///
/// Expected keys: @"name", @"description", @"active", @"id", @"ip",
/// @"protocol", @"startUniverse", @"universeCount", @"startChannel",
/// @"vendor", @"model", @"variant", @"maxChannels",
/// @"supportedProtocols", @"maxUniverses", @"supportsUpload",
/// @"autoUpload", @"lastUpload", @"type",
/// @"supportsAuth", @"authUsername"
- (void)setControllerData:(NSDictionary *)data;

/// Clear the inspector and show the empty/placeholder state.
- (void)clearInspector;

@end
