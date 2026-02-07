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
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

@class XLEngineBridge;
@class XLCustomModelWindow;

@protocol XLCustomModelGridDelegate;
@protocol XLCustomModelLayerDelegate;

/// Node data structure for the custom model grid.
/// Uses C struct to avoid heap corruption from wxWidgets.
typedef struct XLCustomNode {
    int nodeNumber;     // Node number (1-based), 0 = empty
    uint8_t red;        // Color for display
    uint8_t green;
    uint8_t blue;
} XLCustomNode;

/// Maximum grid dimensions
#define XL_CUSTOM_MODEL_MAX_WIDTH 500
#define XL_CUSTOM_MODEL_MAX_HEIGHT 500
#define XL_CUSTOM_MODEL_MAX_DEPTH 50

/// Completion handler for custom model dialog
typedef void (^XLCustomModelCompletion)(BOOL saved);

/// Grid cell view for editing custom model nodes.
/// Displays node numbers and colors, supports selection and editing.
@interface XLCustomModelGridView : NSView

/// Grid dimensions
@property (nonatomic, assign) NSInteger gridWidth;
@property (nonatomic, assign) NSInteger gridHeight;
@property (nonatomic, assign) NSInteger currentLayer;

/// Cell size in points
@property (nonatomic, assign) CGFloat cellSize;

/// Whether to show wiring connections
@property (nonatomic, assign) BOOL showWiring;

/// Whether to show duplicate nodes highlighted
@property (nonatomic, assign) BOOL showDuplicates;

/// Auto-increment mode for painting
@property (nonatomic, assign) BOOL autoIncrement;

/// Single-click placement mode (place node on single click)
@property (nonatomic, assign) BOOL singleClickPlace;

/// Next node number to place
@property (nonatomic, assign) int nextNodeNumber;

/// Background image (optional)
@property (nonatomic, strong) NSImage *backgroundImage;
@property (nonatomic, assign) CGFloat backgroundAlpha;

/// Delegate for grid changes
@property (nonatomic, weak) id<XLCustomModelGridDelegate> delegate;

/// Get/set node at position
- (XLCustomNode)nodeAtX:(NSInteger)x y:(NSInteger)y layer:(NSInteger)layer;
- (void)setNode:(XLCustomNode)node atX:(NSInteger)x y:(NSInteger)y layer:(NSInteger)layer;

/// Clear all nodes
- (void)clearAll;

/// Clear selection
- (void)clearSelection;

/// Select cell at position
- (void)selectCellAtX:(NSInteger)x y:(NSInteger)y;

/// Get selected cells
- (NSArray<NSValue *> *)selectedCells;

/// Operations on selection
- (void)deleteSelectedCells;
- (void)copySelection;
- (void)pasteAtSelection;
- (void)cutSelection;

/// Flip operations
- (void)flipHorizontal;
- (void)flipVertical;
- (void)flipHorizontalSelected;
- (void)flipVerticalSelected;

/// Rotate operations
- (void)rotate90;

/// Reverse node numbering
- (void)reverseNodeNumbers;

/// Shift all node numbers by amount
- (void)shiftNodeNumbersBy:(int)amount;

/// Auto-wire selected cells horizontally (snake pattern, bottom-up)
- (void)wireSelectedHorizontal:(BOOL)leftToRight;

/// Auto-wire selected cells vertically (snake pattern, left-to-right)
- (void)wireSelectedVertical:(BOOL)topToBottom;

/// Resize grid preserving existing data
- (void)resizeGridToWidth:(NSInteger)width height:(NSInteger)height;

/// Find node by number
- (NSPoint)findNode:(int)nodeNumber;

/// Find duplicate nodes
- (NSArray<NSNumber *> *)findDuplicateNodes;

/// Compress unused space
- (void)compressSpace;

/// Expand space by factor
- (void)expandSpaceByFactor:(float)factor;

/// Import from data string (CSV-like format)
- (void)importFromString:(NSString *)data;

/// Export to data string
- (NSString *)exportToString;

/// Undo/redo
- (void)undo;
- (void)redo;
- (BOOL)canUndo;
- (BOOL)canRedo;

/// Zoom
- (void)zoomIn;
- (void)zoomOut;
- (void)zoomToFit;

@end

/// Delegate protocol for grid view
@protocol XLCustomModelGridDelegate <NSObject>
@optional
- (void)customModelGridDidChange:(XLCustomModelGridView *)grid;
- (void)customModelGrid:(XLCustomModelGridView *)grid didSelectCellAtX:(NSInteger)x y:(NSInteger)y;
- (void)customModelGrid:(XLCustomModelGridView *)grid didHoverOverCellAtX:(NSInteger)x y:(NSInteger)y;
@end

/// 3D preview view using Metal for custom model visualization.
@interface XLCustomModel3DPreview : MTKView

/// Set node positions for rendering
- (void)setNodePositions:(const XLCustomNode *)nodes
                   width:(NSInteger)width
                  height:(NSInteger)height
                   depth:(NSInteger)depth;

/// Update render colors (from output preview)
- (void)setNodeColors:(const uint8_t *)rgbData nodeCount:(NSInteger)count;

/// Camera rotation
@property (nonatomic, assign) float rotationX;
@property (nonatomic, assign) float rotationY;
@property (nonatomic, assign) float zoom;

/// Highlight specific node
@property (nonatomic, assign) int highlightedNode;

/// Show wiring
@property (nonatomic, assign) BOOL showWiring;

@end

/// Window controller for the custom model designer.
/// Provides a comprehensive interface for creating and editing custom model layouts.
@interface XLCustomModelWindow : NSWindowController

/// Engine bridge for model operations
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Initialize with model name for editing existing model
- (instancetype)initWithModelName:(NSString *)modelName;

/// Initialize for new model
- (instancetype)initForNewModel;

/// Show the window and call completion when closed
- (void)showWithCompletion:(XLCustomModelCompletion)completion;

/// Load existing model data from the engine bridge
- (void)loadModelFromBridge;

/// Get the model data after editing
@property (nonatomic, readonly) NSDictionary<NSString *, id> *modelData;

/// Whether changes were made
@property (nonatomic, readonly) BOOL hasChanges;

@end

/// Tab view for managing multiple layers in 3D custom models
@interface XLCustomModelLayerTabView : NSView

/// Number of layers
@property (nonatomic, assign) NSInteger layerCount;

/// Currently selected layer
@property (nonatomic, assign) NSInteger selectedLayer;

/// Delegate for layer changes
@property (nonatomic, weak) id<XLCustomModelLayerDelegate> delegate;

/// Add a new layer
- (void)addLayer;

/// Remove current layer
- (void)removeCurrentLayer;

/// Copy layer to another
- (void)copyLayer:(NSInteger)from to:(NSInteger)to;

@end

@protocol XLCustomModelLayerDelegate <NSObject>
- (void)layerTabView:(XLCustomModelLayerTabView *)tabView didSelectLayer:(NSInteger)layer;
- (void)layerTabViewDidAddLayer:(XLCustomModelLayerTabView *)tabView;
- (void)layerTabViewDidRemoveLayer:(XLCustomModelLayerTabView *)tabView;
@end
