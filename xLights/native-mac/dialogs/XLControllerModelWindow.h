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
@class XLControllerModelWindow;

@protocol XLControllerPortsViewDelegate;
@protocol XLUnassignedModelsViewDelegate;

/// Port configuration structure using C types for heap safety.
typedef struct XLPortConfig {
    int portNumber;           // 1-based port number
    char protocol[32];        // e.g., "ws2811", "dmx"
    int startChannel;         // Starting channel
    int pixelCount;           // Number of pixels
    BOOL smartRemote;         // Using smart remote
    int smartRemoteType;      // Smart remote type ID
    int brightness;           // Port brightness (0-100)
    int nullPixels;           // Null pixels at start
    int endNullPixels;        // Null pixels at end
    char colorOrder[8];       // e.g., "RGB", "GRB"
    int groupCount;           // Pixel grouping
    float gamma;              // Gamma correction
} XLPortConfig;

/// Model assignment to port structure.
typedef struct XLModelAssignment {
    char modelName[256];      // Model name
    int portNumber;           // Assigned port (0 if unassigned)
    int startChannel;         // Start channel on port
    int channelCount;         // Number of channels
    int stringNumber;         // String number for multi-string models
    BOOL hasWarning;          // Configuration warning
    char warning[256];        // Warning message
} XLModelAssignment;

/// Maximum ports and models
#define XL_MAX_PORTS 256
#define XL_MAX_PORT_MODELS 1000

/// Completion handler for controller model dialog
typedef void (^XLControllerModelCompletion)(BOOL saved);

/// View that displays controller ports and model assignments.
/// Supports drag-and-drop for model assignment.
@interface XLControllerPortsView : NSView

/// Number of ports
@property (nonatomic, assign) NSInteger portCount;

/// Display scale (zoom)
@property (nonatomic, assign) CGFloat displayScale;

/// Font scale for labels
@property (nonatomic, assign) CGFloat fontScale;

/// Set port configuration
- (void)setPortConfig:(XLPortConfig)config atIndex:(NSInteger)index;

/// Get port configuration
- (XLPortConfig)portConfigAtIndex:(NSInteger)index;

/// Set models for a port
- (void)setModels:(const XLModelAssignment *)models count:(NSInteger)count forPort:(NSInteger)port;

/// Scroll offset
@property (nonatomic, assign) NSPoint scrollOffset;

/// Delegate for interactions
@property (nonatomic, weak) id<XLControllerPortsViewDelegate> delegate;

@end

@protocol XLControllerPortsViewDelegate <NSObject>
@optional
- (void)controllerPortsView:(XLControllerPortsView *)view didSelectPort:(NSInteger)port;
- (void)controllerPortsView:(XLControllerPortsView *)view didSelectModel:(NSString *)modelName onPort:(NSInteger)port;
- (void)controllerPortsView:(XLControllerPortsView *)view didDropModel:(NSString *)modelName onPort:(NSInteger)port atPosition:(NSInteger)position;
- (void)controllerPortsView:(XLControllerPortsView *)view requestContextMenuForPort:(NSInteger)port atPoint:(NSPoint)point;
- (void)controllerPortsView:(XLControllerPortsView *)view requestContextMenuForModel:(NSString *)modelName atPoint:(NSPoint)point;
@end

/// View that displays unassigned models for drag-and-drop.
@interface XLUnassignedModelsView : NSView

/// Set unassigned model names
- (void)setModelNames:(NSArray<NSString *> *)names;

/// Filter string
@property (nonatomic, copy) NSString *filterString;

/// Hide models assigned to other controllers
@property (nonatomic, assign) BOOL hideOtherControllerModels;

/// Scroll offset
@property (nonatomic, assign) CGFloat scrollOffset;

/// Delegate
@property (nonatomic, weak) id<XLUnassignedModelsViewDelegate> delegate;

@end

@protocol XLUnassignedModelsViewDelegate <NSObject>
@optional
- (void)unassignedModelsView:(XLUnassignedModelsView *)view didSelectModel:(NSString *)modelName;
- (void)unassignedModelsView:(XLUnassignedModelsView *)view didDoubleClickModel:(NSString *)modelName;
- (void)unassignedModelsView:(XLUnassignedModelsView *)view didBeginDragForModel:(NSString *)modelName;
@end

/// Window controller for controller-to-model mapping.
/// Displays ports on the controller and allows drag-and-drop assignment of models.
@interface XLControllerModelWindow : NSWindowController

/// Engine bridge for controller operations
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Initialize for a specific controller
- (instancetype)initWithControllerName:(NSString *)controllerName;

/// Show the window and call completion when closed
- (void)showWithCompletion:(XLControllerModelCompletion)completion;

/// Print the controller layout
- (void)printLayout;

/// Export to CSV
- (void)exportToCSV:(NSURL *)url;

@end
