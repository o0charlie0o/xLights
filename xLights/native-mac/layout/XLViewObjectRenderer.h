/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <simd/simd.h>

@class XLViewObject;

NS_ASSUME_NONNULL_BEGIN

/// Renders view objects (Image overlays, Gridlines, etc.) using Metal.
///
/// Uses the same vertex format as the existing grid renderer (float3 position + float4 color)
/// for gridlines, and a world-space textured quad pipeline for image objects.
///
/// The renderer maintains Metal buffers and textures for each view object and
/// rebuilds them when object properties change.
@interface XLViewObjectRenderer : NSObject

/// Initialize with a Metal device and MSAA sample count
- (instancetype)initWithDevice:(id<MTLDevice>)device sampleCount:(NSUInteger)sampleCount;

/// Add or update a view object. Rebuilds Metal resources as needed.
- (void)addOrUpdateObject:(XLViewObject *)object;

/// Remove a view object by name
- (void)removeObjectWithName:(NSString *)name;

/// Remove all view objects
- (void)removeAllObjects;

/// Get all current view object names
- (NSArray<NSString *> *)objectNames;

/// Get a view object by name
- (nullable XLViewObject *)objectWithName:(NSString *)name;

/// Render all view objects into the given encoder.
/// @param encoder The render command encoder
/// @param viewProjection Combined view-projection matrix from the camera
- (void)renderWithEncoder:(id<MTLRenderCommandEncoder>)encoder
           viewProjection:(simd_float4x4)viewProjection;

/// Mark a specific object as needing its Metal resources rebuilt
- (void)invalidateObject:(NSString *)name;

/// Mark all objects as needing rebuild
- (void)invalidateAll;

@end

NS_ASSUME_NONNULL_END
