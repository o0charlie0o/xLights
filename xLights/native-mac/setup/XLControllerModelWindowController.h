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

/// Pasteboard type for dragging model names within the controller model dialog.
extern NSString * const XLControllerModelDragType;

#pragma mark - Port Model Entry

/// Maximum models per port row in the visual layout.
#define XL_CM_MAX_MODELS_PER_PORT 32

/// Represents a single model assigned to a port, as displayed in the visual layout.
typedef struct {
    char modelName[64];
    int channelCount;
    int pixelCount;
    int startChannel;
    int smartRemote;       // 0=None, 1=A, 2=B, etc.
    int stringNumber;      // 0-based string index for multi-string models
    BOOL isMain;           // YES if this is the primary string entry
} XLCMModelEntry;

/// Represents a port row in the visual controller layout.
typedef struct {
    int portNumber;
    int portType;          // 0=pixel, 1=serial, 2=PWM, 3=virtual matrix, 4=LED panel
    char protocol[64];
    int totalChannels;
    int maxChannels;
    BOOL isInvalid;        // Port exceeds controller capabilities
    XLCMModelEntry models[XL_CM_MAX_MODELS_PER_PORT];
    int modelCount;
} XLCMPortRow;

#pragma mark - Controller Port Layout View

/// Custom NSView that draws the visual controller port layout.
/// Ports are rendered as labeled rows on the left, with assigned models drawn
/// as colored rectangles to the right. Supports mouse-driven drag-and-drop,
/// hover highlighting, and context menus.
@interface XLControllerPortLayoutView : NSView <NSDraggingSource, NSDraggingDestination>

/// Scale factor for box/font sizing (default 1.0).
@property (nonatomic, assign) CGFloat boxScale;

/// Engine bridge for data access.
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Currently displayed controller name.
@property (nonatomic, copy) NSString *controllerName;

/// Reload port layout data from the engine bridge.
- (void)reloadPortLayout;

/// Total content height (for scroll view).
- (CGFloat)contentHeight;

/// Total content width (for scroll view).
- (CGFloat)contentWidth;

@end

#pragma mark - Model List Entry

/// Represents a model in the left-panel models list.
@interface XLCMModelListEntry : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) int channelCount;
@property (nonatomic, assign) int stringCount;
@property (nonatomic, copy) NSString *controllerName; // empty if unassigned
@property (nonatomic, assign) BOOL isAssignedToThisController;
@end

#pragma mark - Controller Model Window Controller

/// Native equivalent of the legacy ControllerModelDialog.
///
/// Displays a split-pane window with:
/// - LEFT: Available models list (unassigned and all models)
/// - RIGHT: Visual controller port layout with models as colored blocks
///
/// Users drag models from left to right to assign them to ports,
/// drag between ports to reorder, and use context menus for port/model settings.
///
/// Opened from the Setup tab when the user selects "Visualise" for a controller.
@interface XLControllerModelWindowController : NSWindowController <NSSplitViewDelegate,
    NSTableViewDataSource, NSTableViewDelegate>

/// Engine bridge for data operations.
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Initialize for the given controller.
/// @param controllerName Name of the controller to visualize.
/// @param engineBridge Engine bridge instance.
- (instancetype)initWithControllerName:(NSString *)controllerName
                          engineBridge:(XLEngineBridge *)engineBridge;

/// Show the window as a sheet attached to the given window.
- (void)showAsSheetForWindow:(NSWindow *)parentWindow;

/// Show the window as a standalone window.
- (void)showWindow:(id)sender;

@end
