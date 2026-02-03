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
@class XLSubModelsWindow;

@protocol XLNodeSelectionDelegate;
@protocol XLSubBufferPanelDelegate;
@protocol XLStrandGridDelegate;

/// Submodel info structure using C types for heap safety.
typedef struct XLSubModelInfo {
    char name[256];           // Submodel name
    char oldName[256];        // Original name (for rename tracking)
    BOOL isRanges;            // True for range-based, false for subbuffer
    BOOL vertical;            // For subbuffer orientation
    char bufferStyle[64];     // Buffer style (e.g., "Default")
    char subBuffer[1024];     // Subbuffer definition
    // Strands stored separately as they can be many
} XLSubModelInfo;

/// Maximum submodels and strands
#define XL_MAX_SUBMODELS 500
#define XL_MAX_STRANDS_PER_SUBMODEL 100
#define XL_MAX_STRAND_LENGTH 1024

/// Completion handler for submodels dialog
typedef void (^XLSubModelsCompletion)(BOOL saved);

/// View for visualizing model nodes with selection support.
@interface XLNodeSelectionView : NSView

/// Set node positions (normalized 0-1 coordinates)
@property (nonatomic, readonly) float *nodePositionsX;
@property (nonatomic, readonly) float *nodePositionsY;
@property (nonatomic, readonly) NSInteger nodeCount;

/// Set node data
- (void)setNodeCount:(NSInteger)count
          positionsX:(const float *)x
          positionsY:(const float *)y;

/// Selected node indices
@property (nonatomic, readonly) NSMutableIndexSet *selectedNodes;

/// Highlight color for selected nodes
@property (nonatomic, strong) NSColor *selectionColor;

/// Whether in selection mode
@property (nonatomic, assign) BOOL selectionEnabled;

/// Delegate for selection changes
@property (nonatomic, weak) id<XLNodeSelectionDelegate> delegate;

/// Clear selection
- (void)clearSelection;

/// Select nodes by range string (e.g., "1-10,15,20-25")
- (void)selectNodesFromRangeString:(NSString *)rangeString;

/// Get selected nodes as range string
- (NSString *)selectedNodesAsRangeString;

@end

@protocol XLNodeSelectionDelegate <NSObject>
@optional
- (void)nodeSelectionViewDidChangeSelection:(XLNodeSelectionView *)view;
@end

/// Subbuffer panel for defining rectangular regions of a model.
@interface XLSubBufferPanel : NSView

/// Get/set the subbuffer definition (x,y,width,height as percentages)
@property (nonatomic, copy) NSString *subBufferString;

/// Delegate for changes
@property (nonatomic, weak) id<XLSubBufferPanelDelegate> delegate;

@end

@protocol XLSubBufferPanelDelegate <NSObject>
@optional
- (void)subBufferPanelDidChange:(XLSubBufferPanel *)panel;
@end

/// Window controller for editing model submodels.
/// Allows creating, editing, and managing submodels (named subsets of a model's nodes).
@interface XLSubModelsWindow : NSWindowController

/// Engine bridge for model operations
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Initialize for a specific model
- (instancetype)initWithModelName:(NSString *)modelName;

/// Show the window and call completion when closed
- (void)showWithCompletion:(XLSubModelsCompletion)completion;

/// Whether changes require layout reload
@property (nonatomic, readonly) BOOL reloadLayout;

@end

/// Strand definition view - grid for entering node ranges per strand.
@interface XLStrandGridView : NSView <NSTableViewDataSource, NSTableViewDelegate>

/// Number of strands
@property (nonatomic, assign) NSInteger strandCount;

/// Get strand data at index
- (NSString *)strandAtIndex:(NSInteger)index;

/// Set strand data at index
- (void)setStrand:(NSString *)strand atIndex:(NSInteger)index;

/// Add a strand
- (void)addStrand;

/// Remove strand at index
- (void)removeStrandAtIndex:(NSInteger)index;

/// Move strand up/down
- (void)moveStrandAtIndex:(NSInteger)from toIndex:(NSInteger)to;

/// Delegate for changes
@property (nonatomic, weak) id<XLStrandGridDelegate> delegate;

@end

@protocol XLStrandGridDelegate <NSObject>
@optional
- (void)strandGridViewDidChange:(XLStrandGridView *)view;
@end
