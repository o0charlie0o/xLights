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

@class XLEffectsGridView;

/// Tracks the state of a drag operation on the effects grid.
///
/// This helper class encapsulates the state needed during a drag-to-move or
/// drag-to-resize operation, keeping the main view class cleaner. It also
/// computes snapped positions and validates drop targets.
typedef NS_ENUM(NSInteger, XLDragMode) {
    XLDragModeNone,
    XLDragModeMove,       // Moving effect(s) to a new position/row
    XLDragModeResize,     // Resizing an effect edge
    XLDragModeRubberBand, // Rubber band selection rectangle
    XLDragModePaletteDrop // Drag from palette to create new effect
};

@interface XLEffectDragController : NSObject

/// Current drag mode.
@property (nonatomic, assign) XLDragMode mode;

/// Whether the drag threshold has been exceeded.
@property (nonatomic, assign) BOOL thresholdExceeded;

/// The initial mouse-down point in view coordinates.
@property (nonatomic, assign) NSPoint startPoint;

/// The current mouse position in view coordinates.
@property (nonatomic, assign) NSPoint currentPoint;

/// The row where the drag started.
@property (nonatomic, assign) NSInteger startRow;

/// The current target row during drag.
@property (nonatomic, assign) NSInteger currentRow;

/// The effect index being dragged (-1 if none).
@property (nonatomic, assign) NSInteger effectIndex;

/// Original start time of the dragged effect in ms.
@property (nonatomic, assign) CGFloat originalStartMS;

/// Original end time of the dragged effect in ms.
@property (nonatomic, assign) CGFloat originalEndMS;

/// Time at the initial mouse-down point in ms.
@property (nonatomic, assign) CGFloat startTimeMS;

/// Computed new start time during the drag.
@property (nonatomic, assign) CGFloat newStartMS;

/// Computed new end time during the drag.
@property (nonatomic, assign) CGFloat newEndMS;

/// Whether this is a cross-row drag (target row differs from start row).
@property (nonatomic, readonly) BOOL isCrossRowDrag;

/// Whether the user is resizing the left edge (vs right edge).
@property (nonatomic, assign) BOOL isLeftEdge;

/// Whether snap-to-grid is currently active (respects Option key override).
@property (nonatomic, assign) BOOL snapEnabled;

/// Reset all state to idle.
- (void)reset;

/// Begin a move drag for the given effect.
- (void)beginMoveAtPoint:(NSPoint)point
                     row:(NSInteger)row
             effectIndex:(NSInteger)effectIndex
            originalStart:(CGFloat)startMS
              originalEnd:(CGFloat)endMS
              mouseTimeMS:(CGFloat)timeMS;

/// Begin a resize drag for the given effect edge.
- (void)beginResizeAtPoint:(NSPoint)point
                       row:(NSInteger)row
               effectIndex:(NSInteger)effectIndex
              originalStart:(CGFloat)startMS
                originalEnd:(CGFloat)endMS
                mouseTimeMS:(CGFloat)timeMS
                 isLeftEdge:(BOOL)isLeftEdge;

/// Begin a rubber band selection.
- (void)beginRubberBandAtPoint:(NSPoint)point;

/// Update the drag with a new mouse position and computed time/row.
- (void)updateWithPoint:(NSPoint)point
               timeMS:(CGFloat)timeMS
                  row:(NSInteger)row;

/// Compute the snapped start time for a move, given a snap function block.
/// The block takes a time in ms and returns the snapped time.
- (CGFloat)snappedStartMSUsingBlock:(CGFloat (^)(CGFloat timeMS))snapBlock
                        sequenceEnd:(CGFloat)sequenceLengthMS;

/// Compute the snapped edge time for a resize.
- (void)snappedResizeUsingBlock:(CGFloat (^)(CGFloat timeMS))snapBlock
                    sequenceEnd:(CGFloat)sequenceLengthMS
                minimumWidthMS:(CGFloat)minWidthMS;

@end
