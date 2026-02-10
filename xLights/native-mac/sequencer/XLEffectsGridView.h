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
#import "XLEffectsGridRenderer.h"

@class XLEffectsGridView;
@class XLUndoController;

// Drag pasteboard type for effects dragged from the palette
extern NSPasteboardType const XLEffectTypePasteboardType;

// Notification names for clipboard operations
extern NSNotificationName const XLEffectsGridDidCopyNotification;
extern NSNotificationName const XLEffectsGridDidPasteNotification;
extern NSNotificationName const XLEffectsGridDidCutNotification;

/// Hit location within an effect block (mirrors existing EffectsGrid HitLocation enum).
typedef NS_ENUM(NSInteger, XLEffectHitLocation) {
    XLEffectHitLocationNone,
    XLEffectHitLocationLeftEdge,
    XLEffectHitLocationCenter,
    XLEffectHitLocationRightEdge,
    // Smart Tool zones (Option/Alt held)
    XLEffectHitLocationSmartFadeIn,
    XLEffectHitLocationSmartFadeOut,
    XLEffectHitLocationSmartBrightness,
    XLEffectHitLocationSmartSparkles,
};

/// Provides effect/element data for the grid to render.
@protocol XLEffectsGridDataSource <NSObject>
@required

/// Total number of visible rows (elements with their layers expanded).
- (NSInteger)numberOfRowsInEffectsGrid:(XLEffectsGridView *)gridView;

/// Display name for a given row.
- (NSString *)effectsGrid:(XLEffectsGridView *)gridView nameForRow:(NSInteger)row;

/// Element type for a given row (0=model, 1=submodel, 2=strand, 3=timing).
- (NSInteger)effectsGrid:(XLEffectsGridView *)gridView elementTypeForRow:(NSInteger)row;

/// Number of effects in a given row.
- (NSInteger)effectsGrid:(XLEffectsGridView *)gridView numberOfEffectsInRow:(NSInteger)row;

/// Effect render info for a specific effect in a row.
/// Caller should fill the XLEffectRenderInfo struct via the provided pointer.
- (XLEffectRenderInfo)effectsGrid:(XLEffectsGridView *)gridView
                  effectInfoForRow:(NSInteger)row
                    atIndex:(NSInteger)effectIndex;

/// Total sequence duration in milliseconds.
- (CGFloat)sequenceLengthMSForEffectsGrid:(XLEffectsGridView *)gridView;

@optional

/// Timing marks from the active timing track (array of NSNumber containing ms values).
- (NSArray<NSNumber *> *)timingMarksForEffectsGrid:(XLEffectsGridView *)gridView;

/// The timing grid snap interval in milliseconds (e.g. 50ms for 20fps).
/// Used for arrow-key nudge and snap-to-grid. Returns 0 or not implemented means no snap.
- (CGFloat)timingGridSnapIntervalMSForEffectsGrid:(XLEffectsGridView *)gridView;

@end

/// Receives interaction events from the effects grid.
@protocol XLEffectsGridDelegate <NSObject>
@optional

/// An effect was selected (single click).
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didSelectEffectAtRow:(NSInteger)row
          effectIndex:(NSInteger)effectIndex;

/// An effect was double-clicked (open editor).
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didDoubleClickEffectAtRow:(NSInteger)row
              effectIndex:(NSInteger)effectIndex;

/// A time position was clicked on an empty area.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didClickAtTimeMS:(CGFloat)timeMS
                 row:(NSInteger)row;

/// The playback position was changed by user interaction.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didChangePlaybackPositionMS:(CGFloat)positionMS;

/// The zoom level changed.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didChangeZoomLevel:(CGFloat)zoomLevel;

/// The scroll offset changed.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didChangeScrollOffset:(CGPoint)scrollOffset;

/// The mouse cursor position changed (for syncing cursor line in waveform).
/// Position is -1 when the mouse has exited the grid.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didMoveCursorToTimeMS:(CGFloat)timeMS;

/// An effect was moved to a new time position (same row, horizontal only).
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didMoveEffectAtRow:(NSInteger)fromRow
          effectIndex:(NSInteger)effectIndex
            toTimeMS:(CGFloat)newStartTimeMS;

/// An effect was moved to a different row and/or time position.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didMoveEffectAtRow:(NSInteger)fromRow
          effectIndex:(NSInteger)effectIndex
                toRow:(NSInteger)toRow
            toTimeMS:(CGFloat)newStartTimeMS;

/// Batch move: move an effect by engine ID to a new time (same row). No reload -- caller handles.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didBatchMoveEffectId:(NSInteger)effectId
               toTimeMS:(CGFloat)newStartTimeMS;

/// Batch move: move an effect by engine ID to a different row. No reload -- caller handles.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didBatchMoveEffectId:(NSInteger)effectId
               fromRow:(NSInteger)fromRow
                 toRow:(NSInteger)toRow
             toTimeMS:(CGFloat)newStartTimeMS;

/// Called after all batch moves complete, before the grid reloads. Delegate should refresh its data source.
- (void)effectsGridDidCompleteBatchMoves:(XLEffectsGridView *)gridView;

/// An effect was resized (start or end time changed).
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didResizeEffectAtRow:(NSInteger)row
           effectIndex:(NSInteger)effectIndex
         newStartTimeMS:(CGFloat)startTimeMS
           newEndTimeMS:(CGFloat)endTimeMS;

/// Context menu requested at a position. Return nil to use default menu.
- (NSMenu *)effectsGrid:(XLEffectsGridView *)gridView
    contextMenuForRow:(NSInteger)row
           effectIndex:(NSInteger)effectIndex
              atTimeMS:(CGFloat)timeMS;

/// Selection rectangle completed (rubber-band select).
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didSelectRangeFromRow:(NSInteger)startRow
                    toRow:(NSInteger)endRow
              fromTimeMS:(CGFloat)startTimeMS
                toTimeMS:(CGFloat)endTimeMS;

/// Request to create a new effect from a palette drag-and-drop.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestCreateEffectOfType:(NSString *)effectType
                           atRow:(NSInteger)row
                     startTimeMS:(CGFloat)startTimeMS
                       endTimeMS:(CGFloat)endTimeMS;

/// Request to delete effects at the given indices.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestDeleteEffects:(NSIndexSet *)effectIndices;

/// Multi-selection changed. Called when selectedEffectIndices changes.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didChangeSelection:(NSIndexSet *)selectedIndices;

/// Forward a key event to the delegate for handling via key bindings.
/// Return YES if the delegate handled the event, NO if the grid view should handle it locally.
/// This is called FIRST, before the grid view's own key handling.
- (BOOL)effectsGrid:(XLEffectsGridView *)gridView shouldHandleKeyEvent:(NSEvent *)event;

/// Request to split an effect at the given time position.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestSplitEffectAtIndex:(NSInteger)effectIndex
                        atTimeMS:(CGFloat)timeMS;

/// Request to duplicate an effect.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestDuplicateEffectAtIndex:(NSInteger)effectIndex
                          direction:(NSInteger)direction;

/// Request to create timing marks from the selected effects.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestCreateTimingFromEffects:(NSIndexSet *)effectIndices;

/// Request to lock or unlock effects.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestSetLocked:(BOOL)locked
             forEffects:(NSIndexSet *)effectIndices;

/// Request to enable or disable rendering of effects.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestSetRenderDisabled:(BOOL)disabled
                     forEffects:(NSIndexSet *)effectIndices;

/// Request to edit an effect's description.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestEditDescriptionForEffectAtIndex:(NSInteger)effectIndex;

/// Request to reset an effect to defaults.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestResetEffectAtIndex:(NSInteger)effectIndex;

/// Request to open the effect presets panel.
- (void)effectsGridDidRequestEffectPresets:(XLEffectsGridView *)gridView;

/// Request to create random effects for the selected range.
- (void)effectsGridDidRequestCreateRandomEffects:(XLEffectsGridView *)gridView;

/// Request to edit an effect's timing (start/end time).
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestEditTimingForEffectAtIndex:(NSInteger)effectIndex;

// --- Smart Tool Operations ---

/// Smart Tool: set a parameter on an effect during drag (fade, brightness, sparkles).
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestSetSmartToolParameter:(NSString *)key
                              value:(NSString *)value
                       forEffectId:(NSInteger)effectId;

/// Smart Tool: get a parameter value from an effect.
- (NSString *)effectsGrid:(XLEffectsGridView *)gridView
    smartToolParameterValue:(NSString *)key
               forEffectId:(NSInteger)effectId;

/// Smart Tool: notify delegate that smart tool drag completed.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didCompleteSmartToolDragForEffectIds:(NSArray<NSNumber *> *)effectIds
                               parameter:(NSString *)parameterKey;

// --- Timing Track Operations ---

/// Request to breakdown a phrase timing mark into words.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestBreakdownPhraseAtIndex:(NSInteger)effectIndex;

/// Request to breakdown all selected phrases into words.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestBreakdownSelectedPhrases:(NSIndexSet *)effectIndices;

/// Request to breakdown a word timing mark into phonemes.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestBreakdownWordAtIndex:(NSInteger)effectIndex;

/// Request to breakdown all selected words into phonemes.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestBreakdownSelectedWords:(NSIndexSet *)effectIndices;

/// Request to divide (halve) timing marks.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestDivideTimingsAtIndex:(NSInteger)effectIndex;

/// Request to auto-label timing marks.
- (void)effectsGridDidRequestAutoLabelTimings:(XLEffectsGridView *)gridView;

/// Request to add "-shimmer" suffix to phoneme labels.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestAddShimmerAtIndex:(NSInteger)effectIndex;

/// Request to remove "-shimmer" suffix from phoneme labels.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestRemoveShimmerAtIndex:(NSInteger)effectIndex;

/// Request to create alternating phonemes.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestCreateAlternatingPhonemesAtIndex:(NSInteger)effectIndex;

/// Request to find a text label in timing marks.
- (void)effectsGridDidRequestFindTimingLabel:(XLEffectsGridView *)gridView;

/// Request to find the next occurrence of the current search text.
- (void)effectsGridDidRequestFindNextTimingLabel:(XLEffectsGridView *)gridView;

/// Request to find the previous occurrence of the current search text.
- (void)effectsGridDidRequestFindPreviousTimingLabel:(XLEffectsGridView *)gridView;

/// Request to replace all occurrences of text in timing labels.
- (void)effectsGridDidRequestReplaceAllTimingLabels:(XLEffectsGridView *)gridView;

// --- Alignment Operations ---

/// Alignment operation types.
typedef NS_ENUM(NSInteger, XLAlignmentType) {
    XLAlignmentTypeStartTimes,
    XLAlignmentTypeEndTimes,
    XLAlignmentTypeBothTimes,
    XLAlignmentTypeCenterpoints,
    XLAlignmentTypeMatchDuration,
    XLAlignmentTypeShiftStartTimes,
    XLAlignmentTypeShiftEndTimes,
    XLAlignmentTypeToClosestTimingMark,
    XLAlignmentTypeCloseGap,
};

/// Request to align selected effects.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestAlignEffects:(NSIndexSet *)effectIndices
           alignmentType:(XLAlignmentType)alignmentType;

// --- Symbol Library Operations ---

/// Request to create a symbol from the given effect.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestCreateSymbolFromEffectAtIndex:(NSInteger)effectIndex;

/// Request to unlink effects from their symbols.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestUnlinkFromSymbol:(NSIndexSet *)effectIndices;

/// Request to link effects to an existing symbol.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestLinkEffects:(NSIndexSet *)effectIndices
           toSymbolIndex:(NSInteger)symbolIndex;

@end

/// Metal-backed NSView that renders the sequencer effects timeline.
///
/// This is the native macOS equivalent of the wxWidgets EffectsGrid class.
/// Uses CAMetalLayer for GPU-accelerated rendering of effect blocks, grid lines,
/// timing marks, selection highlights, and the playback position indicator.
///
/// Designed for 60fps+ rendering with support for 100+ models and 1000+ effects
/// via virtual scrolling and frustum culling.
@interface XLEffectsGridView : NSView <NSDraggingDestination>

/// Data source providing element and effect information.
@property (nonatomic, weak) id<XLEffectsGridDataSource> dataSource;

/// Delegate receiving interaction events.
@property (nonatomic, weak) id<XLEffectsGridDelegate> delegate;

/// Undo controller for managing undo/redo operations.
/// If not set, undo operations will not be registered.
@property (nonatomic, strong) XLUndoController *undoController;

/// Horizontal zoom level (pixels per millisecond). Default: 0.1
@property (nonatomic, assign) CGFloat zoomLevel;

/// Minimum zoom level. Default: 0.001 (very zoomed out).
@property (nonatomic, assign) CGFloat minZoomLevel;

/// Maximum zoom level. Default: 5.0 (very zoomed in).
@property (nonatomic, assign) CGFloat maxZoomLevel;

/// Current playback position in milliseconds. -1 means no position shown.
@property (nonatomic, assign) CGFloat playbackPositionMS;

/// Current scroll offset (x=horizontal time scroll, y=vertical row scroll).
@property (nonatomic, assign) CGPoint scrollOffset;

/// Height of each row in points. Default: 22.
@property (nonatomic, assign) CGFloat rowHeight;

/// Currently selected effect index, or -1 if none (primary selection).
@property (nonatomic, assign) NSInteger selectedEffectID;

/// Multi-selection: set of selected effect indices within the effectRenderInfos array.
@property (nonatomic, strong, readonly) NSMutableIndexSet *selectedEffectIndices;

/// Whether to snap effect edges to timing marks during drag/resize. Default: YES.
@property (nonatomic, assign) BOOL snapToTimingMarks;

/// Disable drawing SF Symbol icons on effect blocks (for performance testing). Default: NO.
@property (nonatomic, assign) BOOL disableIconDrawing;

/// Color index of the active timing track (-1 if none). Set by VC to color grid extension lines.
@property (nonatomic, assign) NSInteger activeTimingColorIndex;

/// Number of timing track rows pinned at the top of the grid (frozen rows).
/// These rows do not scroll vertically. Set by the sequencer VC after sorting rows.
@property (nonatomic, assign) NSInteger pinnedTimingRowCount;

/// Available symbol names for the "Link to Symbol" context menu.
/// Set by the view controller; the grid view uses these to populate the submenu.
@property (nonatomic, copy) NSArray<NSString *> *availableSymbolNames;

/// Reload all data from the data source and redraw.
- (void)reloadData;

/// Scroll so the given time is visible.
- (void)scrollToTimeMS:(CGFloat)timeMS;

/// Set the playback position, optionally animating.
- (void)setPlaybackPositionMS:(CGFloat)positionMS animated:(BOOL)animated;

/// Convert a view point to a (timeMS, row) coordinate.
- (void)convertPoint:(NSPoint)viewPoint toTimeMS:(CGFloat *)outTimeMS row:(NSInteger *)outRow;

/// Convert a (timeMS, row) to a view point.
- (NSPoint)pointForTimeMS:(CGFloat)timeMS row:(NSInteger)row;

/// Force a redraw on the next display cycle.
- (void)setNeedsDisplay;

/// Select all effects in the given row.
- (void)selectAllEffectsInRow:(NSInteger)row;

/// Clear all selections.
- (void)clearSelection;

/// Zoom and scroll to fit the currently selected effects in view.
- (void)zoomToSelection;

/// Return the real effect ID (from NativeEffectProvider) for a flat render index, or -1 if invalid.
- (NSInteger)effectIdAtRenderIndex:(NSUInteger)index;

/// Show an inline text field editor over a timing mark label for editing.
/// @param row The grid row of the timing mark
/// @param startMS Start time of the timing mark in ms
/// @param endMS End time of the timing mark in ms
/// @param currentLabel The current label text
/// @param completion Called with the new label when editing completes, or nil if cancelled
- (void)beginEditingLabelAtRow:(NSInteger)row
                       startMS:(CGFloat)startMS
                         endMS:(CGFloat)endMS
                  currentLabel:(NSString *)currentLabel
             completionHandler:(void (^)(NSString * _Nullable newLabel))completion;

/// Whether a cell (empty area) is currently selected for keyboard effect insertion.
@property (nonatomic, assign, readonly) BOOL hasCellSelection;

/// Row of the selected cell.
@property (nonatomic, assign, readonly) NSInteger cellSelectionRow;

/// Start time of the selected cell in milliseconds.
@property (nonatomic, assign, readonly) CGFloat cellSelectionStartMS;

/// End time of the selected cell in milliseconds.
@property (nonatomic, assign, readonly) CGFloat cellSelectionEndMS;

/// Clear the cell selection highlight.
- (void)clearCellSelection;

/// Set the cell selection to a specific row and time range.
/// Used after duplication to move the selection to the duplicated area.
- (void)setCellSelectionRow:(NSInteger)row startMS:(CGFloat)startMS endMS:(CGFloat)endMS;

/// Return the row for a render effect at the given index, or -1 if invalid.
- (NSInteger)rowForRenderIndex:(NSUInteger)index;

/// Return the start time in ms for a render effect at the given index, or -1 if invalid.
- (CGFloat)startMSForRenderIndex:(NSUInteger)index;

/// Return the end time in ms for a render effect at the given index, or -1 if invalid.
- (CGFloat)endMSForRenderIndex:(NSUInteger)index;

@end
