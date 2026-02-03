/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLBaseSheetController.h"

NS_ASSUME_NONNULL_BEGIN

@class XLEngineBridge;

#pragma mark - Model Chain Dialog

/// Native macOS sheet for configuring model chaining.
@interface XLModelChainDialog : XLBaseSheetController

/// Engine bridge for accessing model data
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Current model name
@property (nonatomic, copy) NSString *modelName;

/// Model to chain from (nil for start of chain)
@property (nonatomic, copy, nullable) NSString *chainFromModel;

/// Available models that can be chained from
@property (nonatomic, copy) NSArray<NSString *> *availableModels;

@end

#pragma mark - Strand Node Names Dialog

/// Native macOS sheet for naming strands and nodes.
@interface XLStrandNodeNamesDialog : XLBaseSheetController

/// Model name
@property (nonatomic, copy) NSString *modelName;

/// Number of strands
@property (nonatomic, assign) NSInteger strandCount;

/// Strand names (array of strand name arrays)
@property (nonatomic, copy) NSArray<NSString *> *strandNames;

/// Node names for each strand (array of arrays of node names)
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *nodeNames;

/// Number of nodes per strand
@property (nonatomic, copy) NSArray<NSNumber *> *nodesPerStrand;

@end

#pragma mark - Model Dimming Curve Dialog

/// Native macOS sheet for configuring model dimming curves.
@interface XLModelDimmingCurveDialog : XLBaseSheetController

/// Model name
@property (nonatomic, copy) NSString *modelName;

/// Dimming curve type (linear, gamma, log, etc.)
@property (nonatomic, copy) NSString *curveType;

/// Gamma value (for gamma curve type)
@property (nonatomic, assign) double gammaValue;

/// Brightness percentage (0-100)
@property (nonatomic, assign) NSInteger brightness;

/// Apply to all channels
@property (nonatomic, assign) BOOL applyToAllChannels;

/// Custom curve data points (x,y pairs from 0-255)
@property (nonatomic, copy, nullable) NSArray<NSValue *> *customCurvePoints;

@end

#pragma mark - Edit Aliases Dialog

/// Native macOS sheet for editing model/element aliases.
@interface XLEditAliasesDialog : XLBaseSheetController

/// Element name
@property (nonatomic, copy) NSString *elementName;

/// Current aliases
@property (nonatomic, copy) NSArray<NSString *> *aliases;

/// Add an alias
- (void)addAlias:(NSString *)alias;

/// Remove an alias at index
- (void)removeAliasAtIndex:(NSUInteger)index;

@end

#pragma mark - Submodel Generate Dialog

/// Native macOS sheet for generating submodels automatically.
@interface XLSubModelGenerateDialog : XLBaseSheetController

/// Model name
@property (nonatomic, copy) NSString *modelName;

/// Number of submodels to generate
@property (nonatomic, assign) NSInteger submodelCount;

/// Submodel naming prefix
@property (nonatomic, copy) NSString *namingPrefix;

/// Submodel type (horizontal, vertical, segments, etc.)
@property (nonatomic, copy) NSString *submodelType;

/// Whether to create overlapping submodels
@property (nonatomic, assign) BOOL allowOverlap;

@end

#pragma mark - Wiring Dialog

/// Native macOS window for viewing/editing model wiring diagram.
@interface XLWiringDialog : NSWindowController

/// Model name
@property (nonatomic, copy) NSString *modelName;

/// Engine bridge for accessing model data
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Show front view (default: YES)
@property (nonatomic, assign) BOOL showFrontView;

/// Show node numbers
@property (nonatomic, assign) BOOL showNodeNumbers;

/// Show controller connections
@property (nonatomic, assign) BOOL showControllerConnections;

/// Zoom level (1.0 = 100%)
@property (nonatomic, assign) double zoomLevel;

/// Show the wiring dialog
- (void)showWithCompletion:(void (^)(void))completion;

@end

#pragma mark - Pixel Test Dialog

/// Native macOS window for testing pixels on models.
@interface XLPixelTestDialog : NSWindowController

/// Engine bridge for controlling outputs
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Models to test
@property (nonatomic, copy) NSArray<NSString *> *modelNames;

/// Test mode (chase, highlight, static, etc.)
@property (nonatomic, copy) NSString *testMode;

/// Test color
@property (nonatomic, strong) NSColor *testColor;

/// Chase speed (ms per step)
@property (nonatomic, assign) NSInteger chaseSpeedMs;

/// Show the pixel test dialog
- (void)showWithCompletion:(void (^)(void))completion;

@end

#pragma mark - Seven Segment Dialog

/// Native macOS sheet for configuring seven-segment display models.
@interface XLSevenSegmentDialog : XLBaseSheetController

/// Number of digits
@property (nonatomic, assign) NSInteger digitCount;

/// Segment thickness
@property (nonatomic, assign) CGFloat segmentThickness;

/// Digit spacing
@property (nonatomic, assign) CGFloat digitSpacing;

/// Whether to include decimal points
@property (nonatomic, assign) BOOL includeDecimalPoints;

/// Whether to include colons
@property (nonatomic, assign) BOOL includeColons;

/// Node ordering (clockwise, counter-clockwise, etc.)
@property (nonatomic, copy) NSString *nodeOrdering;

@end

#pragma mark - Generate Custom Model Dialog

/// Native macOS window for generating custom models from images.
@interface XLGenerateCustomModelDialog : NSWindowController

/// Source image path
@property (nonatomic, copy, nullable) NSString *sourceImagePath;

/// Generated node count
@property (nonatomic, assign, readonly) NSInteger generatedNodeCount;

/// Threshold for pixel detection (0-255)
@property (nonatomic, assign) NSInteger detectionThreshold;

/// Minimum brightness for node detection
@property (nonatomic, assign) NSInteger minimumBrightness;

/// Model name
@property (nonatomic, copy) NSString *modelName;

/// Blur amount for preprocessing
@property (nonatomic, assign) NSInteger blurAmount;

/// Show the dialog
- (void)showWithCompletion:(void (^)(BOOL accepted))completion;

@end

#pragma mark - Path Generation Dialog

/// Native macOS sheet for path/polyline generation options.
@interface XLPathGenerationDialog : XLBaseSheetController

/// Number of nodes
@property (nonatomic, assign) NSInteger nodeCount;

/// Path type (linear, bezier, arc, etc.)
@property (nonatomic, copy) NSString *pathType;

/// Reverse direction
@property (nonatomic, assign) BOOL reverseDirection;

/// Generate as closed loop
@property (nonatomic, assign) BOOL closedLoop;

@end

#pragma mark - Auto Label Dialog

/// Native macOS sheet for auto-labeling model nodes.
@interface XLAutoLabelDialog : XLBaseSheetController

/// Starting label/number
@property (nonatomic, assign) NSInteger startNumber;

/// Label prefix
@property (nonatomic, copy) NSString *prefix;

/// Label suffix
@property (nonatomic, copy) NSString *suffix;

/// Increment step
@property (nonatomic, assign) NSInteger incrementStep;

/// Padding (number of digits)
@property (nonatomic, assign) NSInteger padding;

@end

NS_ASSUME_NONNULL_END
