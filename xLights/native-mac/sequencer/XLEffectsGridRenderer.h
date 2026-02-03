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
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

@class XLEffectsGridView;

/// Describes a single effect block for rendering.
/// IMPORTANT: This struct must NOT contain ObjC object pointers (NSColor *, NSString *, etc.)
/// because it is stored in NSValue via valueWithBytes:objCType: which bypasses ARC.
/// Use plain C types only.
typedef struct {
    CGFloat startTimeMS;
    CGFloat endTimeMS;
    NSInteger row;
    NSInteger layer;
    NSInteger effectIndex;
    uint32_t colorARGB;       // 0 means use palette color from effectIndex
    BOOL selected;
    BOOL locked;
    BOOL renderDisabled;
} XLEffectRenderInfo;

/// Manages Metal rendering for the effects grid.
///
/// Handles device/pipeline setup, vertex buffer management, and all draw calls.
/// Kept separate from the view to isolate Metal complexity.
@interface XLEffectsGridRenderer : NSObject

@property (nonatomic, readonly) id<MTLDevice> device;
@property (nonatomic, readonly) id<MTLCommandQueue> commandQueue;

- (instancetype)initWithLayer:(CAMetalLayer *)metalLayer;

/// Full draw pass: grid lines, effect blocks, selection, playback indicator.
/// Call from the view's display cycle.
///
/// Both effects and timing marks are passed as plain C arrays (pointer + count)
/// rather than NSArrays to avoid ObjC message sends during the render path.
/// This makes the hot path immune to heap corruption of ObjC object pointers.
- (void)drawInLayer:(CAMetalLayer *)layer
           viewSize:(CGSize)viewSize
       scrollOffset:(CGPoint)scrollOffset
          zoomLevel:(CGFloat)zoomLevel
          rowHeight:(CGFloat)rowHeight
          totalRows:(NSInteger)totalRows
   sequenceLengthMS:(CGFloat)sequenceLengthMS
            effects:(const XLEffectRenderInfo *)effects
        effectCount:(NSUInteger)effectCount
   selectedEffectID:(NSInteger)selectedEffectID
 playbackPositionMS:(CGFloat)playbackPositionMS
   timingMarkValues:(const CGFloat *)timingMarkValues
    timingMarkCount:(NSUInteger)timingMarkCount;

/// Map from effect type index to display color.
+ (NSColor *)colorForEffectIndex:(NSInteger)effectIndex;

@end
