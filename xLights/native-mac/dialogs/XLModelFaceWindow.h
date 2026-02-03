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
@class XLModelFaceWindow;

/// Phoneme definitions - standard phonemes for lip sync animation.
/// Using C arrays for heap corruption safety.
extern const char * const kPhonemeNames[];
extern const int kPhonemeCount;

/// Face type enum - matches wxWidgets choicebook pages.
typedef NS_ENUM(NSInteger, XLFaceType) {
    XLFaceTypeSingleNode = 0,    // Single LED per phoneme
    XLFaceTypeNodeRanges = 1,    // Node range strings per phoneme
    XLFaceTypeMatrix = 2         // Image-based matrix display
};

/// Face data structure for a single phoneme using C types.
typedef struct XLPhonemeData {
    char phonemeName[32];        // Phoneme identifier (AI, E, etc.)
    char nodeData[1024];         // Node numbers or ranges
    uint8_t colorRed;            // Custom color (if enabled)
    uint8_t colorGreen;
    uint8_t colorBlue;
    BOOL hasCustomColor;         // Whether custom color is set
} XLPhonemeData;

/// Matrix face data for image-based faces.
typedef struct XLMatrixFaceData {
    char phonemeName[32];        // Phoneme identifier
    char imagePath[1024];        // Path to image file
    int imageIndex;              // Index within multi-image file
} XLMatrixFaceData;

/// Maximum face definitions and phonemes.
#define XL_MAX_FACE_DEFINITIONS 100
#define XL_MAX_PHONEMES 12

/// Completion handler for model face dialog.
typedef void (^XLModelFaceCompletion)(BOOL saved);

/// Forward protocol declarations.
@protocol XLFaceNodeSelectionDelegate;
@protocol XLPhonemeGridDelegate;
@protocol XLMatrixFacePanelDelegate;

/// View for displaying model with selectable nodes for face mapping.
@interface XLFaceNodeSelectionView : NSView

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

/// Highlight nodes by phoneme (for preview).
- (void)highlightNodesForPhoneme:(NSString *)phoneme withData:(XLPhonemeData)data;

/// Clear highlight.
- (void)clearHighlight;

/// Selection mode.
@property (nonatomic, assign) BOOL selectionEnabled;

/// Delegate for selection changes.
@property (nonatomic, weak) id<XLFaceNodeSelectionDelegate> delegate;

/// Get selected nodes as range string.
- (NSString *)selectedNodesAsRangeString;

/// Clear selection.
- (void)clearSelection;

@end

@protocol XLFaceNodeSelectionDelegate <NSObject>
@optional
- (void)faceNodeSelectionViewDidChangeSelection:(XLFaceNodeSelectionView *)view;
@end

/// Grid view for editing phoneme-to-node mappings.
@interface XLPhonemeGridView : NSView <NSTableViewDataSource, NSTableViewDelegate>

/// Face type (single node, node ranges, or matrix).
@property (nonatomic, assign) XLFaceType faceType;

/// Get phoneme data at index.
- (XLPhonemeData)phonemeDataAtIndex:(NSInteger)index;

/// Set phoneme data at index.
- (void)setPhonemeData:(XLPhonemeData)data atIndex:(NSInteger)index;

/// Get all phoneme data.
- (void)getAllPhonemeData:(XLPhonemeData *)buffer count:(NSInteger)count;

/// Set all phoneme data.
- (void)setAllPhonemeData:(const XLPhonemeData *)buffer count:(NSInteger)count;

/// Enable custom colors.
@property (nonatomic, assign) BOOL customColorsEnabled;

/// Currently selected phoneme index.
@property (nonatomic, assign) NSInteger selectedPhonemeIndex;

/// Delegate for changes.
@property (nonatomic, weak) id<XLPhonemeGridDelegate> delegate;

@end

@protocol XLPhonemeGridDelegate <NSObject>
@optional
- (void)phonemeGridViewDidChange:(XLPhonemeGridView *)view;
- (void)phonemeGridView:(XLPhonemeGridView *)view didSelectPhoneme:(NSInteger)index;
- (void)phonemeGridView:(XLPhonemeGridView *)view requestsNodeSelectionForPhoneme:(NSInteger)index;
@end

/// Matrix face panel for image-based face animation.
@interface XLMatrixFacePanel : NSView

/// Get matrix face data at index.
- (XLMatrixFaceData)matrixDataAtIndex:(NSInteger)index;

/// Set matrix face data at index.
- (void)setMatrixData:(XLMatrixFaceData)data atIndex:(NSInteger)index;

/// Image placement mode.
@property (nonatomic, copy) NSString *imagePlacement;

/// Delegate for changes.
@property (nonatomic, weak) id<XLMatrixFacePanelDelegate> delegate;

@end

@protocol XLMatrixFacePanelDelegate <NSObject>
@optional
- (void)matrixFacePanelDidChange:(XLMatrixFacePanel *)panel;
- (void)matrixFacePanel:(XLMatrixFacePanel *)panel didSelectPhoneme:(NSInteger)index;
@end

/// Window controller for editing model face definitions.
/// Allows creating, editing, and managing face definitions for lip sync animation.
@interface XLModelFaceWindow : NSWindowController

/// Engine bridge for model operations.
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Initialize for a specific model.
- (instancetype)initWithModelName:(NSString *)modelName;

/// Show the window and call completion when closed.
- (void)showWithCompletion:(XLModelFaceCompletion)completion;

/// Output to lights preview toggle.
@property (nonatomic, assign) BOOL outputToLights;

/// Get face info dictionary.
- (NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *)faceInfo;

/// Set face info dictionary.
- (void)setFaceInfo:(NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *)info;

/// Whether changes require reload.
@property (nonatomic, readonly) BOOL needsReload;

@end
