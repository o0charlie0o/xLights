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
#import <simd/simd.h>

@class XLCameraController;
@class XLMetalPreviewView;

/// Delegate protocol for the Metal preview view.
///
/// Informs the layout controller about user interactions:
/// model selection and camera changes.
@protocol XLMetalPreviewDelegate <NSObject>
@optional

/// Called when the user clicks on a model in the preview
- (void)previewView:(XLMetalPreviewView *)view didSelectModel:(NSString *)modelName;

/// Called when the camera position or orientation changes
- (void)previewView:(XLMetalPreviewView *)view didChangeCamera:(XLCameraController *)camera;

@end

/// Native NSView subclass backed by CAMetalLayer for the 3D model preview.
///
/// Replaces the wxWidgets wxMetalCanvas wrapper with a pure AppKit view.
/// Uses the existing Metal shader pipeline from xLights/graphics/metal/ for
/// model rendering. Manages its own render loop via CVDisplayLink and
/// supports ProMotion (120Hz) on capable displays.
///
/// Camera controls:
/// - Left-drag: orbit camera around target
/// - Right-drag or two-finger drag: pan camera
/// - Scroll wheel / pinch: zoom
/// - Double-click: frame selected model
///
/// Integration: the existing xlMetalGraphicsContext pipeline provides
/// shader state, pipeline descriptors, and draw calls. This view provides
/// the CAMetalLayer drawable surface and triggers rendering through
/// XLEngineBridge.
@interface XLMetalPreviewView : NSView

#pragma mark - Metal Device

/// The Metal device used for rendering
@property (nonatomic, strong, readonly) id<MTLDevice> metalDevice;

/// The Metal command queue
@property (nonatomic, strong, readonly) id<MTLCommandQueue> commandQueue;

/// The backing CAMetalLayer
@property (nonatomic, strong, readonly) CAMetalLayer *metalLayer;

#pragma mark - Appearance

/// Background clear color for the preview
@property (nonatomic, strong) NSColor *backgroundColor;

/// Whether to show the ground reference grid
@property (nonatomic, assign) BOOL showGrid;

/// Whether to render in 3D perspective (YES) or 2D orthographic (NO)
@property (nonatomic, assign) BOOL show3D;

#pragma mark - Camera

/// Camera controller managing orbit/pan/zoom
@property (nonatomic, strong, readonly) XLCameraController *cameraController;

/// Current camera position in world space
@property (nonatomic, readonly) simd_float3 cameraPosition;

/// Current camera target (look-at point)
@property (nonatomic, readonly) simd_float3 cameraTarget;

/// Current camera up vector
@property (nonatomic, readonly) simd_float3 cameraUp;

/// Current zoom level (camera distance)
@property (nonatomic, assign) CGFloat zoomLevel;

#pragma mark - Delegate

/// Delegate for user interaction callbacks
@property (nonatomic, weak) id<XLMetalPreviewDelegate> delegate;

#pragma mark - Render Loop

/// Start the display-link-based render loop
- (void)startRenderLoop;

/// Stop the render loop
- (void)stopRenderLoop;

/// Manually trigger a single frame render
- (void)renderFrame;

/// Mark the view as needing a redraw on the next display link cycle
- (void)setNeedsRender;

#pragma mark - Camera Control

/// Reset camera to default position and orientation
- (void)resetCamera;

/// Zoom to fit all models in view
- (void)frameAllModels;

/// Highlight a specific model by name (for selection sync with model tree)
- (void)highlightModel:(NSString *)modelName;

#pragma mark - MSAA

/// MSAA sample count (default: 4)
@property (nonatomic, assign) NSUInteger sampleCount;

@end
