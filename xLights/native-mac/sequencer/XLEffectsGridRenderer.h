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
typedef struct {
    CGFloat startTimeMS;
    CGFloat endTimeMS;
    NSInteger row;
    NSInteger layer;
    NSInteger effectIndex;
    NSColor *color;
    NSString *effectName;
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
- (void)drawInLayer:(CAMetalLayer *)layer
           viewSize:(CGSize)viewSize
       scrollOffset:(CGPoint)scrollOffset
          zoomLevel:(CGFloat)zoomLevel
          rowHeight:(CGFloat)rowHeight
        totalRows:(NSInteger)totalRows
   sequenceLengthMS:(CGFloat)sequenceLengthMS
            effects:(NSArray<NSValue *> *)effects
   selectedEffectID:(NSInteger)selectedEffectID
playbackPositionMS:(CGFloat)playbackPositionMS
     timingMarksMS:(NSArray<NSNumber *> *)timingMarksMS;

/// Map from effect type index to display color.
+ (NSColor *)colorForEffectIndex:(NSInteger)effectIndex;

@end
