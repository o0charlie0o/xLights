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

@end
