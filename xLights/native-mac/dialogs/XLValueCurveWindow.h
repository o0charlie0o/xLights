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
@class XLValueCurveWindow;

@protocol XLValueCurveViewDelegate;

/// Curve type definitions using C struct to avoid heap corruption
typedef struct XLCurveTypeDef {
    const char *typeId;       // Internal identifier
    const char *displayName;  // User-visible name
    const char *iconName;     // SF Symbol name (optional)
    int parameterCount;       // Number of parameters (0-4)
} XLCurveTypeDef;

/// Point on the curve for editing
typedef struct XLCurvePoint {
    float x;  // 0.0 to 1.0
    float y;  // 0.0 to 1.0
} XLCurvePoint;

/// Maximum number of custom curve points
#define XL_MAX_CURVE_POINTS 100

/// Completion handler for value curve editing
/// Returns YES if curve was modified, NO if cancelled
typedef void (^XLValueCurveCompletion)(BOOL modified);

/// View that renders and allows editing of value curves.
/// Uses Metal/CALayer for smooth rendering of bezier curves.
@interface XLValueCurveView : NSView

/// The current curve type (e.g., "Flat", "Ramp", "Custom", etc.)
@property (nonatomic, copy) NSString *curveType;

/// Parameters for the current curve type (normalized 0-1)
@property (nonatomic, assign) float parameter1;
@property (nonatomic, assign) float parameter2;
@property (nonatomic, assign) float parameter3;
@property (nonatomic, assign) float parameter4;

/// Whether the curve wraps values outside 0-1
@property (nonatomic, assign) BOOL wrapValues;

/// Custom curve points (for Custom curve type)
@property (nonatomic, readonly) XLCurvePoint *customPoints;
@property (nonatomic, assign) NSInteger customPointCount;

/// Minimum and maximum Y values for display/scaling
@property (nonatomic, assign) float minValue;
@property (nonatomic, assign) float maxValue;

/// Time offset for timing track synchronization
@property (nonatomic, assign) float timeOffset;

/// Whether editing is enabled
@property (nonatomic, assign) BOOL editable;

/// Index of currently selected/grabbed point (-1 if none)
@property (nonatomic, assign) NSInteger selectedPointIndex;

/// Delegate for curve changes
@property (nonatomic, weak) id<XLValueCurveViewDelegate> delegate;

/// Add a custom point at the specified position
- (void)addPointAtX:(float)x y:(float)y;

/// Remove the point at the specified index
- (void)removePointAtIndex:(NSInteger)index;

/// Delete the currently selected point
- (void)deleteSelectedPoint;

/// Undo the last point modification
- (void)undo;

/// Get the Y value at a given X position (0-1)
- (float)valueAtX:(float)x;

/// Flip the curve horizontally
- (void)flipHorizontal;

/// Flip the curve vertically
- (void)flipVertical;

/// Reverse the curve (flip both axes)
- (void)reverse;

@end

/// Delegate protocol for value curve view
@protocol XLValueCurveViewDelegate <NSObject>
@optional
/// Called when the curve is modified
- (void)valueCurveViewDidChange:(XLValueCurveView *)view;
/// Called when a point is selected
- (void)valueCurveView:(XLValueCurveView *)view didSelectPointAtIndex:(NSInteger)index;
@end

/// Window controller for the value curve editor dialog.
/// Presents as a separate window (not a sheet) due to complexity.
@interface XLValueCurveWindow : NSWindowController

/// Engine bridge for accessing presets and timing tracks
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Initialize with curve data string (e.g., "Ramp,100,0")
- (instancetype)initWithCurveData:(NSString *)curveData
                         minValue:(float)minValue
                         maxValue:(float)maxValue;

/// Show the window and call completion when closed
- (void)showWithCompletion:(XLValueCurveCompletion)completion;

/// Get the modified curve data string
- (NSString *)curveDataString;

/// Whether the curve was modified
@property (nonatomic, readonly) BOOL wasModified;

@end

/// Panel view for embedding value curve editing in other UI
@interface XLValueCurvePanel : NSView

/// The curve view for rendering/editing
@property (nonatomic, readonly) XLValueCurveView *curveView;

/// Curve type popup
@property (nonatomic, readonly) NSPopUpButton *curveTypePopup;

/// Parameter sliders
@property (nonatomic, readonly) NSSlider *parameter1Slider;
@property (nonatomic, readonly) NSSlider *parameter2Slider;
@property (nonatomic, readonly) NSSlider *parameter3Slider;
@property (nonatomic, readonly) NSSlider *parameter4Slider;

/// Initialize with a curve data string
- (instancetype)initWithCurveData:(NSString *)curveData
                         minValue:(float)minValue
                         maxValue:(float)maxValue;

/// Get/set curve data
- (NSString *)curveDataString;
- (void)setCurveDataString:(NSString *)curveData;

/// Target/action for curve changes
@property (nonatomic, weak) id target;
@property (nonatomic, assign) SEL action;

@end
