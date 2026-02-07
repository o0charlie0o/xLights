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

@class XLEngineBridge;

/// Color theme types for the wiring diagram
typedef NS_ENUM(NSInteger, XLWiringTheme) {
    XLWiringThemeDark = 0,
    XLWiringThemeGray,
    XLWiringThemeLight
};

/// NSView that renders a per-model node wiring diagram.
/// Shows nodes as numbered circles with connecting lines indicating physical wiring order.
/// Supports zoom/pan, front/rear view, color themes, rotation, and font size adjustment.
/// Ported from the legacy WiringDialog (wxWidgets bitmap-based rendering).
@interface XLNodeWiringView : NSView

/// Engine bridge for accessing model node data
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Model name to display
@property (nonatomic, copy, nullable) NSString *modelName;

/// Whether to show rear view (default: YES, matching legacy behavior)
@property (nonatomic, assign) BOOL rearView;

/// Current color theme
@property (nonatomic, assign) XLWiringTheme colorTheme;

/// Font size for node labels (default: 12)
@property (nonatomic, assign) NSInteger fontSize;

/// Current rotation in degrees (0, 90, 180, 270)
@property (nonatomic, assign) NSInteger rotation;

/// Load node data from the engine bridge for the specified model
- (void)loadModelData;

/// Reset zoom and pan to default
- (void)resetView;

/// Export the diagram as PNG data
- (NSData *)exportAsPNG;

/// Export the diagram as a large (4096x2048) PNG
- (NSData *)exportAsLargePNG;

/// Get a bitmap suitable for printing
- (NSImage *)imageForPrinting;

/// Copy the diagram to the system clipboard as PNG
- (void)copyToClipboard;

@end

NS_ASSUME_NONNULL_END
