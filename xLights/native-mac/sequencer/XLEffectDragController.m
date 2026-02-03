/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLEffectDragController.h"

@implementation XLEffectDragController

- (instancetype)init {
    self = [super init];
    if (self) {
        [self reset];
    }
    return self;
}

- (void)reset {
    _mode = XLDragModeNone;
    _thresholdExceeded = NO;
    _startPoint = NSZeroPoint;
    _currentPoint = NSZeroPoint;
    _startRow = -1;
    _currentRow = -1;
    _effectIndex = -1;
    _originalStartMS = 0;
    _originalEndMS = 0;
    _startTimeMS = 0;
    _newStartMS = 0;
    _newEndMS = 0;
    _isLeftEdge = NO;
    _snapEnabled = YES;
}

- (BOOL)isCrossRowDrag {
    return _mode == XLDragModeMove && _currentRow >= 0 && _currentRow != _startRow;
}

- (void)beginMoveAtPoint:(NSPoint)point
                     row:(NSInteger)row
             effectIndex:(NSInteger)effectIndex
            originalStart:(CGFloat)startMS
              originalEnd:(CGFloat)endMS
              mouseTimeMS:(CGFloat)timeMS
{
    _mode = XLDragModeMove;
    _thresholdExceeded = NO;
    _startPoint = point;
    _currentPoint = point;
    _startRow = row;
    _currentRow = row;
    _effectIndex = effectIndex;
    _originalStartMS = startMS;
    _originalEndMS = endMS;
    _startTimeMS = timeMS;
    _newStartMS = startMS;
    _newEndMS = endMS;
}

- (void)beginResizeAtPoint:(NSPoint)point
                       row:(NSInteger)row
               effectIndex:(NSInteger)effectIndex
              originalStart:(CGFloat)startMS
                originalEnd:(CGFloat)endMS
                mouseTimeMS:(CGFloat)timeMS
                 isLeftEdge:(BOOL)isLeftEdge
{
    _mode = XLDragModeResize;
    _thresholdExceeded = NO;
    _startPoint = point;
    _currentPoint = point;
    _startRow = row;
    _currentRow = row;
    _effectIndex = effectIndex;
    _originalStartMS = startMS;
    _originalEndMS = endMS;
    _startTimeMS = timeMS;
    _newStartMS = startMS;
    _newEndMS = endMS;
    _isLeftEdge = isLeftEdge;
}

- (void)beginRubberBandAtPoint:(NSPoint)point {
    _mode = XLDragModeRubberBand;
    _thresholdExceeded = NO;
    _startPoint = point;
    _currentPoint = point;
    _effectIndex = -1;
}

- (void)updateWithPoint:(NSPoint)point
               timeMS:(CGFloat)timeMS
                  row:(NSInteger)row
{
    _currentPoint = point;
    _currentRow = row;

    if (_mode == XLDragModeMove) {
        CGFloat deltaMS = timeMS - _startTimeMS;
        CGFloat duration = _originalEndMS - _originalStartMS;
        _newStartMS = _originalStartMS + deltaMS;
        _newEndMS = _newStartMS + duration;
    } else if (_mode == XLDragModeResize) {
        CGFloat deltaMS = timeMS - _startTimeMS;
        if (_isLeftEdge) {
            _newStartMS = _originalStartMS + deltaMS;
            _newEndMS = _originalEndMS;
        } else {
            _newStartMS = _originalStartMS;
            _newEndMS = _originalEndMS + deltaMS;
        }
    }
}

- (CGFloat)snappedStartMSUsingBlock:(CGFloat (^)(CGFloat timeMS))snapBlock
                        sequenceEnd:(CGFloat)sequenceLengthMS
{
    if (!snapBlock || !_snapEnabled) {
        CGFloat duration = _originalEndMS - _originalStartMS;
        return MAX(0, MIN(_newStartMS, sequenceLengthMS - duration));
    }

    CGFloat duration = _originalEndMS - _originalStartMS;
    CGFloat clampedStart = MAX(0, MIN(_newStartMS, sequenceLengthMS - duration));

    CGFloat snappedStart = snapBlock(clampedStart);
    CGFloat snappedEnd = snapBlock(clampedStart + duration);

    CGFloat snapDeltaStart = fabs(snappedStart - clampedStart);
    CGFloat snapDeltaEnd = fabs(snappedEnd - (clampedStart + duration));

    CGFloat result;
    if (snapDeltaStart <= snapDeltaEnd) {
        result = snappedStart;
    } else {
        result = snappedEnd - duration;
    }

    return MAX(0, MIN(result, sequenceLengthMS - duration));
}

- (void)snappedResizeUsingBlock:(CGFloat (^)(CGFloat timeMS))snapBlock
                    sequenceEnd:(CGFloat)sequenceLengthMS
                minimumWidthMS:(CGFloat)minWidthMS
{
    if (_isLeftEdge) {
        CGFloat newStart = MAX(0, MIN(_newStartMS, _newEndMS - minWidthMS));
        if (snapBlock && _snapEnabled) {
            newStart = snapBlock(newStart);
            newStart = MIN(newStart, _newEndMS - minWidthMS);
        }
        _newStartMS = newStart;
    } else {
        CGFloat newEnd = MAX(_newStartMS + minWidthMS, MIN(_newEndMS, sequenceLengthMS));
        if (snapBlock && _snapEnabled) {
            newEnd = snapBlock(newEnd);
            newEnd = MAX(_newStartMS + minWidthMS, newEnd);
        }
        _newEndMS = newEnd;
    }
}

@end
