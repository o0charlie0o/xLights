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

/// Data structure representing a port on a controller
@interface XLWiringPort : NSObject

@property (nonatomic, assign) NSInteger portNumber;
@property (nonatomic, copy) NSString *protocol;
@property (nonatomic, assign) NSInteger startChannel;
@property (nonatomic, assign) NSInteger channelCount;
@property (nonatomic, assign) NSInteger brightness;
@property (nonatomic, assign) CGFloat gamma;
@property (nonatomic, copy) NSString *colorOrder;
@property (nonatomic, copy, nullable) NSString *modelName;

@end

/// Data structure representing a controller in the wiring diagram
@interface XLWiringController : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy, nullable) NSString *ip;
@property (nonatomic, copy, nullable) NSString *vendor;
@property (nonatomic, copy, nullable) NSString *model;
@property (nonatomic, assign) NSInteger startChannel;
@property (nonatomic, assign) NSInteger endChannel;
@property (nonatomic, strong) NSMutableArray<XLWiringPort *> *ports;

@end

/// Data structure representing a model in the wiring diagram
@interface XLWiringModel : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, assign) NSInteger nodeCount;
@property (nonatomic, assign) NSInteger channelCount;
@property (nonatomic, assign) NSInteger startChannel;
@property (nonatomic, assign) NSInteger endChannel;
@property (nonatomic, copy, nullable) NSString *controllerName;
@property (nonatomic, assign) NSInteger port;
@property (nonatomic, strong, nullable) NSColor *displayColor;

@end

/// Custom NSView that renders a wiring diagram showing controller ports and model connections
@interface XLWiringDiagramView : NSView

/// Engine bridge for accessing controller and model data
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Zoom level (1.0 = 100%)
@property (nonatomic, assign) CGFloat zoomLevel;

/// Show model channel information
@property (nonatomic, assign) BOOL showChannelInfo;

/// Show port numbers
@property (nonatomic, assign) BOOL showPortNumbers;

/// Show unassigned models
@property (nonatomic, assign) BOOL showUnassignedModels;

/// Selected controller (nil for all)
@property (nonatomic, copy, nullable) NSString *selectedController;

/// Currently hovered model name (for highlighting)
@property (nonatomic, copy, nullable) NSString *hoveredModelName;

/// Reload data from the engine bridge
- (void)reloadData;

/// Export the diagram as a PDF
- (NSData *)exportAsPDF;

/// Export the diagram as PNG image
- (NSData *)exportAsPNG;

/// Get the ideal content size for the diagram
- (NSSize)idealContentSize;

@end

NS_ASSUME_NONNULL_END
