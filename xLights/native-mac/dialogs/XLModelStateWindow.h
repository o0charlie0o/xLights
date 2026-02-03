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
@class XLModelStateWindow;

/// State type enum - matches wxWidgets choicebook pages.
typedef NS_ENUM(NSInteger, XLStateType) {
    XLStateTypeSingleNode = 0,   // Single LED per state
    XLStateTypeNodeRanges = 1    // Node range strings per state
};

/// State data structure using C types for heap safety.
typedef struct XLStateData {
    char stateName[256];         // State name
    char nodeData[1024];         // Node numbers or ranges
    uint8_t colorRed;            // Custom color (if enabled)
    uint8_t colorGreen;
    uint8_t colorBlue;
    BOOL hasCustomColor;         // Whether custom color is set
    BOOL active;                 // Whether state is active
} XLStateData;

/// Maximum states per definition.
#define XL_MAX_STATE_DEFINITIONS 100
#define XL_MAX_STATES_PER_DEF 500

/// Completion handler for model state dialog.
typedef void (^XLModelStateCompletion)(BOOL saved);

/// Forward protocol declarations.
@protocol XLStateNodeSelectionDelegate;
@protocol XLStateGridDelegate;

/// View for displaying model with selectable nodes for state mapping.
@interface XLStateNodeSelectionView : NSView

/// Set node positions (normalized 0-1 coordinates).
@property (nonatomic, readonly) float *nodePositionsX;
@property (nonatomic, readonly) float *nodePositionsY;
@property (nonatomic, readonly) NSInteger nodeCount;

/// Set node data.
- (void)setNodeCount:(NSInteger)count
          positionsX:(const float *)x
          positionsY:(const float *)y;

/// Selected node indices.
@property (nonatomic, readonly) NSMutableIndexSet *selectedNodes;

/// Highlight nodes for state preview.
- (void)highlightNodesForState:(NSString *)stateName withData:(XLStateData)data;

/// Clear highlight.
- (void)clearHighlight;

/// Selection mode.
@property (nonatomic, assign) BOOL selectionEnabled;

/// Color draw mode for preview.
@property (nonatomic, copy) NSString *colorDrawMode;

/// Delegate for selection changes.
@property (nonatomic, weak) id<XLStateNodeSelectionDelegate> delegate;

/// Get selected nodes as range string.
- (NSString *)selectedNodesAsRangeString;

/// Clear selection.
- (void)clearSelection;

@end

@protocol XLStateNodeSelectionDelegate <NSObject>
@optional
- (void)stateNodeSelectionViewDidChangeSelection:(XLStateNodeSelectionView *)view;
@end

/// Grid view for editing state-to-node mappings.
@interface XLStateGridView : NSView <NSTableViewDataSource, NSTableViewDelegate>

/// State type (single node or node ranges).
@property (nonatomic, assign) XLStateType stateType;

/// Number of states.
@property (nonatomic, readonly) NSInteger stateCount;

/// Get state data at index.
- (XLStateData)stateDataAtIndex:(NSInteger)index;

/// Set state data at index.
- (void)setStateData:(XLStateData)data atIndex:(NSInteger)index;

/// Add a new state.
- (void)addStateWithName:(NSString *)name;

/// Insert state at index.
- (void)insertStateAtIndex:(NSInteger)index withName:(NSString *)name;

/// Remove state at index.
- (void)removeStateAtIndex:(NSInteger)index;

/// Move state.
- (void)moveStateAtIndex:(NSInteger)from toIndex:(NSInteger)to;

/// Sort states alphabetically.
- (void)sortStates;

/// Enable custom colors.
@property (nonatomic, assign) BOOL customColorsEnabled;

/// Currently selected state index.
@property (nonatomic, assign) NSInteger selectedStateIndex;

/// Delegate for changes.
@property (nonatomic, weak) id<XLStateGridDelegate> delegate;

@end

@protocol XLStateGridDelegate <NSObject>
@optional
- (void)stateGridViewDidChange:(XLStateGridView *)view;
- (void)stateGridView:(XLStateGridView *)view didSelectState:(NSInteger)index;
- (void)stateGridView:(XLStateGridView *)view requestsNodeSelectionForState:(NSInteger)index;
@end

/// Window controller for editing model state definitions.
/// Allows creating, editing, and managing state definitions for DMX fixtures.
@interface XLModelStateWindow : NSWindowController

/// Engine bridge for model operations.
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Initialize for a specific model.
- (instancetype)initWithModelName:(NSString *)modelName;

/// Show the window and call completion when closed.
- (void)showWithCompletion:(XLModelStateCompletion)completion;

/// Output to lights preview toggle.
@property (nonatomic, assign) BOOL outputToLights;

/// Get state info dictionary.
- (NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *)stateInfo;

/// Set state info dictionary.
- (void)setStateInfo:(NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *)info;

/// Import 7-segment display states.
- (void)import7SegmentStates;

/// Whether changes require reload.
@property (nonatomic, readonly) BOOL needsReload;

@end
