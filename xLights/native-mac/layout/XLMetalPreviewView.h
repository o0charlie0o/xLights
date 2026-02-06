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
@class XLManipulationHandlesRenderer;
@class XLEngineBridge;

/// Delegate protocol for the Metal preview view.
///
/// Informs the layout controller about user interactions:
/// model selection, camera changes, and handle manipulation.
@protocol XLMetalPreviewDelegate <NSObject>
@optional

/// Called when the user clicks on a model in the preview
- (void)previewView:(XLMetalPreviewView *)view didSelectModel:(NSString *)modelName;

/// Called when the camera position or orientation changes
- (void)previewView:(XLMetalPreviewView *)view didChangeCamera:(XLCameraController *)camera;

/// Called when a handle manipulation begins
- (void)previewView:(XLMetalPreviewView *)view didBeginManipulatingModel:(NSString *)modelName;

/// Called during handle manipulation with transform delta
- (void)previewView:(XLMetalPreviewView *)view didManipulateModelWithDelta:(simd_float3)delta;

/// Called when handle manipulation ends
- (void)previewView:(XLMetalPreviewView *)view didEndManipulatingModel:(NSString *)modelName;

/// Called when the preview receives a key event it doesn't handle (e.g. spacebar)
- (void)previewView:(XLMetalPreviewView *)view didReceiveKeyEvent:(NSEvent *)event;

/// Called when the user requests to lock or unlock a model via context menu
- (void)previewView:(XLMetalPreviewView *)view didRequestLockModel:(NSString *)modelName lock:(BOOL)lock;

/// Called when the user requests to delete a model via context menu
- (void)previewView:(XLMetalPreviewView *)view didRequestDeleteModel:(NSString *)modelName;

/// Called when the user requests to flip a model via context menu
- (void)previewView:(XLMetalPreviewView *)view didRequestFlipModel:(NSString *)modelName horizontal:(BOOL)horizontal;

/// Called when the user requests to align multiple models
- (void)previewView:(XLMetalPreviewView *)view didRequestAlignModels:(NSString *)alignment;

/// Called when the user requests to distribute multiple models
- (void)previewView:(XLMetalPreviewView *)view didRequestDistributeModels:(NSString *)direction;

/// Called when the user requests to resize multiple models to match
- (void)previewView:(XLMetalPreviewView *)view didRequestResizeModels:(NSString *)dimension;

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

/// Engine bridge for querying model data
@property (nonatomic, weak) XLEngineBridge *engineBridge;

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

/// Reload model data from the engine bridge
- (void)reloadModels;

/// Select a model by name
- (void)selectModel:(NSString *)modelName;

#pragma mark - MSAA

/// MSAA sample count (default: 4)
@property (nonatomic, assign) NSUInteger sampleCount;

#pragma mark - Manipulation Handles

/// The manipulation handles renderer
@property (nonatomic, strong, readonly) XLManipulationHandlesRenderer *handlesRenderer;

/// Name of the currently selected model (nil if none)
@property (nonatomic, strong, nullable) NSString *selectedModelName;

/// Set model transform for manipulation handles
/// @param position World position of the model center
/// @param scale Scale factors (x, y, z)
/// @param rotation Rotation angles in degrees (x, y, z)
/// @param boundingBoxMin Minimum corner of model bounding box (local space)
/// @param boundingBoxMax Maximum corner of model bounding box (local space)
/// @param renderWidth Width of model in render units
/// @param renderHeight Height of model in render units
/// @param renderDepth Depth of model in render units
/// @param isLocked Whether the model is locked
/// @param supportsZScaling Whether the model supports Z scaling
- (void)setModelTransformWithPosition:(simd_float3)position
                                scale:(simd_float3)scale
                             rotation:(simd_float3)rotation
                       boundingBoxMin:(simd_float3)boundingBoxMin
                       boundingBoxMax:(simd_float3)boundingBoxMax
                          renderWidth:(float)renderWidth
                         renderHeight:(float)renderHeight
                          renderDepth:(float)renderDepth
                             isLocked:(BOOL)isLocked
                     supportsZScaling:(BOOL)supportsZScaling;

/// Clear model selection (hides manipulation handles)
- (void)clearModelSelection;

/// Set the current manipulation tool mode
/// 0 = Translate, 1 = Scale, 2 = Rotate
- (void)setToolMode:(NSInteger)mode;

/// Set the active manipulation axis
/// -1 = None, 0 = X, 1 = Y, 2 = Z
- (void)setActiveAxis:(NSInteger)axis;

/// Toggle between tool modes (translate -> scale -> rotate -> translate)
- (void)toggleToolMode;

/// Set grid snap size (0 = disabled)
- (void)setGridSnapSize:(float)snapSize;

/// Set angle snap increment in degrees (0 = disabled)
- (void)setAngleSnapDegrees:(float)angleDegrees;

/// Enable/disable edge snapping to other models
- (void)setEdgeSnapEnabled:(BOOL)enabled;

#pragma mark - Real-Time Preview Rendering

/// Whether real-time preview rendering is active (during playback)
@property (nonatomic, assign) BOOL previewRenderingActive;

/// Current playback position in milliseconds (for preview sync)
@property (nonatomic, assign) NSInteger playbackPositionMS;

/// Sequence duration in milliseconds
@property (nonatomic, assign) NSInteger sequenceDurationMS;

/// Frame time in milliseconds
@property (nonatomic, assign) NSInteger frameTimeMS;

/// Update preview for the current playback position.
/// Called during playback to render model pixel data at the current time.
- (void)updatePreviewForTime:(NSInteger)timeMS;

/// Set rendered pixel data for a model.
/// @param modelName The name of the model
/// @param pixelData RGBA pixel data
/// @param width Width of the pixel buffer
/// @param height Height of the pixel buffer
- (void)setRenderedPixels:(NSData *)pixelData
                 forModel:(NSString *)modelName
                    width:(NSUInteger)width
                   height:(NSUInteger)height;

/// Clear all rendered pixel data (stop showing preview colors)
- (void)clearRenderedPixels;

/// Set whether to show rendered effect colors on models vs static layout colors
@property (nonatomic, assign) BOOL showEffectColors;

@end
