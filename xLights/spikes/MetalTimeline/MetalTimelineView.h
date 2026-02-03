#pragma once

#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <vector>
#import "TimelineTypes.h"

@interface MetalTimelineView : NSView

@property (nonatomic, readonly) id<MTLDevice> device;
@property (nonatomic, readonly) CAMetalLayer *metalLayer;

// Timeline state
@property (nonatomic) CGFloat scrollOffsetX;
@property (nonatomic) CGFloat scrollOffsetY;
@property (nonatomic) CGFloat zoomScale;
@property (nonatomic) double playheadPosition; // seconds

// Performance stats
@property (nonatomic, readonly) double lastFrameTime;
@property (nonatomic, readonly) double fps;

- (void)generateMockData:(int)numRows effectsPerRow:(int)effectsPerRow totalDuration:(double)duration;

@end
