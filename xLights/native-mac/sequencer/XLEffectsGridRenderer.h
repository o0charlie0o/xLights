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

/// Maximum length of effect type name stored in XLEffectRenderInfo
#define XL_EFFECT_TYPE_NAME_MAX 32

/// Maximum length of timing mark label stored in XLEffectRenderInfo
#define XL_LABEL_MAX 128

/// Number of distinct timing track colors in the shared palette.
#define XL_TIMING_COLOR_COUNT 8

/// Shared timing track color palette — single source of truth for row headers,
/// tick marks, and grid extension lines. Returns RGB components in [0,1].
static inline void XLTimingTrackColor(NSInteger colorIndex, CGFloat *r, CGFloat *g, CGFloat *b) {
    static const CGFloat kPalette[XL_TIMING_COLOR_COUNT][3] = {
        { 1.0,  0.25, 0.25 },  // 0: Red
        { 0.2,  1.0,  0.2  },  // 1: Neon green
        { 1.0,  0.95, 0.15 },  // 2: Yellow
        { 0.2,  0.9,  1.0  },  // 3: Cyan
        { 1.0,  0.5,  0.1  },  // 4: Orange
        { 0.7,  0.4,  1.0  },  // 5: Purple
        { 1.0,  0.45, 0.7  },  // 6: Hot pink
        { 0.4,  1.0,  0.7  },  // 7: Mint
    };
    NSUInteger idx = (NSUInteger)colorIndex % XL_TIMING_COLOR_COUNT;
    *r = kPalette[idx][0];
    *g = kPalette[idx][1];
    *b = kPalette[idx][2];
}

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
    NSInteger effectId;       // Real effect ID from NativeEffectProvider (for selection/inspector)
    uint32_t colorARGB;       // 0 means use palette color from effectIndex
    char effectTypeName[XL_EFFECT_TYPE_NAME_MAX];  // Effect type name for icon display
    BOOL selected;
    BOOL locked;
    BOOL renderDisabled;
    BOOL isTimingMark;        // YES for timing track marks (rendered as vertical ticks, not boxes)
    NSInteger timingTrackLayerCount; // Number of layers in parent timing track (1=plain timing, 3=lyric)
    NSInteger timingColorIndex;      // Sequential color index for timing tracks (0, 1, 2...)
    char label[XL_LABEL_MAX]; // Timing mark label text (phrases, words, phonemes)
    CGFloat fadeInMS;             // Fade in duration in milliseconds (0 = no fade)
    CGFloat fadeOutMS;            // Fade out duration in milliseconds (0 = no fade)
    BOOL isLinkedToSymbol;        // YES if linked to a symbol (cyan triangle indicator)
} XLEffectRenderInfo;

/// Manages Metal rendering for the effects grid.
///
/// Handles device/pipeline setup, vertex buffer management, and all draw calls.
/// Kept separate from the view to isolate Metal complexity.
@interface XLEffectsGridRenderer : NSObject

@property (nonatomic, readonly) id<MTLDevice> device;
@property (nonatomic, readonly) id<MTLCommandQueue> commandQueue;

/// Check if Metal is available on this system.
+ (BOOL)isMetalAvailable;

- (instancetype)initWithLayer:(CAMetalLayer *)metalLayer;

/// Full draw pass: grid lines, effect blocks, selection, playback indicator, drop preview.
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
    timingMarkCount:(NSUInteger)timingMarkCount
activeTimingColorIndex:(NSInteger)activeTimingColorIndex
   pinnedTimingRowCount:(NSInteger)pinnedTimingRowCount
      dropIndicator:(BOOL)showDropIndicator
            dropRow:(NSInteger)dropRow
        dropStartMS:(CGFloat)dropStartMS
          dropEndMS:(CGFloat)dropEndMS
   rubberBandActive:(BOOL)rubberBandActive
     rubberBandRect:(NSRect)rubberBandRect
  cellHighlightActive:(BOOL)cellHighlightActive
    cellHighlightRow:(NSInteger)cellHighlightRow
cellHighlightStartMS:(CGFloat)cellHighlightStartMS
  cellHighlightEndMS:(CGFloat)cellHighlightEndMS;

/// Map from effect type index to display color.
+ (NSColor *)colorForEffectIndex:(NSInteger)effectIndex;

@end
