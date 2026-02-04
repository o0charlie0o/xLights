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

/// Test pattern types
typedef NS_ENUM(NSInteger, XLPixelTestPattern) {
    XLPixelTestPatternOff = 0,
    XLPixelTestPatternAllOn,
    XLPixelTestPatternChase,
    XLPixelTestPatternChase3,
    XLPixelTestPatternChase4,
    XLPixelTestPatternChase5,
    XLPixelTestPatternAlternate,
    XLPixelTestPatternTwinkle5,
    XLPixelTestPatternTwinkle10,
    XLPixelTestPatternTwinkle25,
    XLPixelTestPatternTwinkle50,
    XLPixelTestPatternShimmer,
    XLPixelTestPatternRGBCycle,
    XLPixelTestPatternColorBlocks
};

/// Native macOS window for testing pixels on models.
@interface XLPixelTestDialog : NSWindowController

/// Engine bridge for controlling outputs
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Models to test (nil means test all selected channels)
@property (nonatomic, copy, nullable) NSArray<NSString *> *modelNames;

/// Current test pattern
@property (nonatomic, assign) XLPixelTestPattern testPattern;

/// Test color (foreground/highlight)
@property (nonatomic, strong) NSColor *testColor;

/// Background color
@property (nonatomic, strong) NSColor *backgroundColor;

/// Chase speed (1-100, higher = faster)
@property (nonatomic, assign) NSInteger chaseSpeed;

/// Whether output is active
@property (nonatomic, assign, readonly) BOOL isOutputActive;

/// Show the pixel test dialog
- (void)showWithCompletion:(void (^)(void))completion;

/// Start output to controllers
- (void)startOutput;

/// Stop output to controllers
- (void)stopOutput;

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

/// Generation source type for custom model generation
typedef NS_ENUM(NSInteger, XLCustomModelGenerationSource) {
    XLCustomModelGenerationSourceImage = 0,    // From image file
    XLCustomModelGenerationSourceSVGPath,       // From SVG path (placeholder)
    XLCustomModelGenerationSourceMathFunction,  // From math function (placeholder)
    XLCustomModelGenerationSourceGrid,          // Grid with custom spacing
    XLCustomModelGenerationSourceImport,        // Import from other formats (placeholder)
};

/// Native macOS window for generating custom models from various sources.
@interface XLGenerateCustomModelDialog : NSWindowController

/// Engine bridge for model operations
@property (nonatomic, weak, nullable) XLEngineBridge *engineBridge;

/// Selected generation source type
@property (nonatomic, assign) XLCustomModelGenerationSource generationSource;

/// Source image path (for image source)
@property (nonatomic, copy, nullable) NSString *sourceImagePath;

/// Source image (loaded)
@property (nonatomic, strong, nullable, readonly) NSImage *sourceImage;

/// Generated node count
@property (nonatomic, assign, readonly) NSInteger generatedNodeCount;

/// Generated custom model data string (for CustomModel property)
@property (nonatomic, copy, readonly, nullable) NSString *generatedModelData;

/// Model name
@property (nonatomic, copy) NSString *modelName;

/// Grid width (generated)
@property (nonatomic, assign, readonly) NSInteger gridWidth;

/// Grid height (generated)
@property (nonatomic, assign, readonly) NSInteger gridHeight;

#pragma mark - Image Source Parameters

/// Threshold for pixel detection (0-255)
@property (nonatomic, assign) NSInteger detectionThreshold;

/// Minimum brightness for node detection
@property (nonatomic, assign) NSInteger minimumBrightness;

/// Blur amount for preprocessing
@property (nonatomic, assign) NSInteger blurAmount;

/// Whether to invert the image (detect dark pixels instead of light)
@property (nonatomic, assign) BOOL invertDetection;

/// Scale factor for output (1 = 1 pixel = 1 node, 2 = 2x2 pixels = 1 node, etc.)
@property (nonatomic, assign) NSInteger scaleFactor;

#pragma mark - Grid Source Parameters

/// Number of columns for grid generation
@property (nonatomic, assign) NSInteger gridColumns;

/// Number of rows for grid generation
@property (nonatomic, assign) NSInteger gridRows;

/// Horizontal spacing between grid nodes (pixels)
@property (nonatomic, assign) NSInteger horizontalSpacing;

/// Vertical spacing between grid nodes (pixels)
@property (nonatomic, assign) NSInteger verticalSpacing;

/// Numbering direction for grid: @"leftright" (default), @"topbottom", @"rightleft", @"bottomtop"
@property (nonatomic, copy) NSString *gridNumberingDirection;

/// Whether to snake the numbering (alternate direction on each row/column)
@property (nonatomic, assign) BOOL gridSnakeNumbering;

/// Starting corner for grid numbering: @"topleft", @"topright", @"bottomleft", @"bottomright"
@property (nonatomic, copy) NSString *gridStartCorner;

#pragma mark - SVG Path Parameters (Placeholder)

/// SVG path data string (d attribute content)
@property (nonatomic, copy, nullable) NSString *svgPathData;

/// Number of nodes to place along the path
@property (nonatomic, assign) NSInteger svgNodeCount;

#pragma mark - Math Function Parameters (Placeholder)

/// Math function expression (e.g., "sin(x)", "x^2 + y^2")
@property (nonatomic, copy, nullable) NSString *mathExpression;

/// X range for math function
@property (nonatomic, assign) CGFloat mathXMin;
@property (nonatomic, assign) CGFloat mathXMax;

/// Y range for math function
@property (nonatomic, assign) CGFloat mathYMin;
@property (nonatomic, assign) CGFloat mathYMax;

/// Resolution for math function
@property (nonatomic, assign) NSInteger mathResolution;

#pragma mark - Methods

/// Show the dialog
- (void)showWithCompletion:(void (^)(BOOL accepted))completion;

/// Load an image from path
- (BOOL)loadImageFromPath:(NSString *)path;

/// Generate the custom model from current settings
- (BOOL)generateModel;

/// Get preview image showing detected pixels
- (NSImage * _Nullable)getPreviewImage;

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
