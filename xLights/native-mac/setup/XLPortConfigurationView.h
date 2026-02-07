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

@class XLPortConfigurationView;
@class XLEngineBridge;

#pragma mark - Port Entry C Struct (Heap Corruption Immunity)

/// Maximum string length for port entry fields.
/// Using fixed-size C arrays avoids heap allocation that can be corrupted.
#define XL_PORT_MAX_STRING_LEN 64
#define XL_PORT_MAX_MODELS 16
#define XL_PORT_MAX_PORTS 128

/// Port type enumeration
typedef NS_ENUM(NSInteger, XLPortType) {
    XLPortTypePixel = 0,
    XLPortTypeSerial,
    XLPortTypePWM,
    XLPortTypeVirtualMatrix,
    XLPortTypeLEDPanel
};

/// Validation status for a port
typedef NS_ENUM(NSInteger, XLPortValidationStatus) {
    XLPortValidationOK = 0,
    XLPortValidationWarning,
    XLPortValidationError
};

/// C struct for port configuration data.
/// Using C struct with fixed arrays instead of Objective-C objects
/// to avoid heap corruption issues when wxWidgets/C++ is active.
typedef struct {
    int portNumber;
    XLPortType portType;
    char protocol[XL_PORT_MAX_STRING_LEN];
    int32_t startChannel;
    int32_t endChannel;
    int32_t channelCount;
    int pixelCount;
    int brightness;
    float gamma;
    int nullPixelsStart;
    int nullPixelsEnd;
    char colorOrder[XL_PORT_MAX_STRING_LEN];
    int groupCount;
    BOOL reverse;
    int zigZag;
    char smartRemoteType[XL_PORT_MAX_STRING_LEN];
    int smartRemoteIndex;  // 0=None, 1=A, 2=B, etc.

    // Model assignment
    char assignedModelName[XL_PORT_MAX_STRING_LEN];
    char assignedModelNames[XL_PORT_MAX_MODELS][XL_PORT_MAX_STRING_LEN];
    int assignedModelCount;

    // Validation
    XLPortValidationStatus validationStatus;
    char validationMessage[XL_PORT_MAX_STRING_LEN * 2];

    // UI state
    BOOL isExpanded;
    BOOL isSelected;
} XLPortEntry;

/// C struct for port configuration data source.
/// Manages an array of XLPortEntry items with fixed maximum capacity.
typedef struct {
    XLPortEntry ports[XL_PORT_MAX_PORTS];
    int portCount;
    int pixelPortCount;
    int serialPortCount;
    char controllerName[XL_PORT_MAX_STRING_LEN];
} XLPortDataSource;

#pragma mark - Delegate Protocol

/// Delegate protocol for port configuration user interactions.
@protocol XLPortConfigurationViewDelegate <NSObject>

@optional

/// Called when a port is selected.
- (void)portConfigurationView:(XLPortConfigurationView *)view
          didSelectPortAtIndex:(NSInteger)index;

/// Called when a port property is edited.
- (void)portConfigurationView:(XLPortConfigurationView *)view
              didEditPortAtIndex:(NSInteger)index
                        property:(NSString *)property
                           value:(id)value;

/// Called when user requests assigning a model to a port via dropdown.
- (void)portConfigurationView:(XLPortConfigurationView *)view
    didRequestAssignModelToPort:(NSInteger)portIndex;

/// Called when a model is dropped onto a port (drag and drop).
- (void)portConfigurationView:(XLPortConfigurationView *)view
                  didDropModel:(NSString *)modelName
                      onPortAtIndex:(NSInteger)portIndex;

/// Called when user requests removing a model from a port.
- (void)portConfigurationView:(XLPortConfigurationView *)view
    didRequestRemoveModelAtIndex:(NSInteger)modelIndex
                    fromPortAtIndex:(NSInteger)portIndex;

/// Called when validation errors should be shown for a port.
- (void)portConfigurationView:(XLPortConfigurationView *)view
    didRequestShowValidationForPortAtIndex:(NSInteger)portIndex;

@end

#pragma mark - Column Identifiers

extern NSString * const XLPortColumnPort;
extern NSString * const XLPortColumnType;
extern NSString * const XLPortColumnProtocol;
extern NSString * const XLPortColumnModel;
extern NSString * const XLPortColumnStartChannel;
extern NSString * const XLPortColumnChannels;
extern NSString * const XLPortColumnPixels;
extern NSString * const XLPortColumnBrightness;
extern NSString * const XLPortColumnGamma;
extern NSString * const XLPortColumnColorOrder;
extern NSString * const XLPortColumnNullPixels;
extern NSString * const XLPortColumnSmartRemote;
extern NSString * const XLPortColumnStatus;

#pragma mark - View Class

/// NSTableView-based port configuration grid for the Setup tab.
///
/// Displays all ports on the currently selected controller with columns for
/// port number, protocol, assigned model, start channel, channel count,
/// brightness, gamma, color order, and validation status.
///
/// Uses C struct arrays (XLPortEntry/XLPortDataSource) instead of NSArray/NSDictionary
/// to avoid heap corruption when wxWidgets/C++ is active in the same process.
///
/// Supports:
/// - Inline editing of port properties
/// - Model assignment via dropdown or drag-and-drop
/// - Visual indicators for unassigned ports and conflicts
/// - Validation warnings for channel overlaps
@interface XLPortConfigurationView : NSViewController <NSTableViewDataSource, NSTableViewDelegate>

/// The table view displaying the port grid.
@property (nonatomic, strong, readonly) NSTableView *tableView;

/// Delegate for user interaction callbacks.
@property (nonatomic, weak) id<XLPortConfigurationViewDelegate> delegate;

/// Engine bridge used to fetch port data.
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Name of the currently displayed controller.
@property (nonatomic, copy, readonly) NSString *controllerName;

/// Load ports for the specified controller.
- (void)loadPortsForController:(NSString *)controllerName;

/// Reload the current port data from the engine bridge.
- (void)reloadData;

/// Clear the port display (when no controller is selected).
- (void)clearPorts;

/// Select a port by index.
- (void)selectPortAtIndex:(NSInteger)index;

/// Returns the index of the currently selected port, or -1 if none.
- (NSInteger)selectedPortIndex;

/// Access the port data source (read-only).
- (const XLPortDataSource *)portDataSource;

/// Validate all ports and return YES if no errors.
- (BOOL)validatePorts;

/// Register for model drag types (call after view is loaded).
- (void)registerForModelDrag;

/// Configure the port grid for the specified number of pixel and serial ports.
/// Clears existing port entries and creates new defaults based on controller capabilities.
- (void)configureForPixelPorts:(NSInteger)pixelPorts serialPorts:(NSInteger)serialPorts;

/// Set the available protocols for pixel and serial ports.
/// Pass nil to use default protocol lists.
- (void)setAvailablePixelProtocols:(nullable NSArray<NSString *> *)pixelProtocols
                   serialProtocols:(nullable NSArray<NSString *> *)serialProtocols;

/// Show or hide the Smart Remote column based on controller capabilities.
- (void)setSmartRemotesVisible:(BOOL)visible;

@end
