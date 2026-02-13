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

/// Called when the user selects multiple models (Cmd+click or rubber-band)
- (void)previewView:(XLMetalPreviewView *)view didSelectModels:(NSArray<NSString *> *)modelNames;

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

/// Called when the user requests a bulk edit operation on multiple models
/// editType is one of: Active, Inactive, Tag Color, Preview, Pixel Size, Pixel Style,
/// Transparency, Controller Name, Controller Port, Controller Protocol, Dimming Curves
- (void)previewView:(XLMetalPreviewView *)view didRequestBulkEdit:(NSString *)editType;

/// Called when the user nudges a selected model with arrow keys.
/// @param deltaX World-space X offset (negative = left, positive = right)
/// @param deltaY World-space Y offset (negative = down, positive = up)
- (void)previewView:(XLMetalPreviewView *)view didNudgeModelWithDeltaX:(float)deltaX deltaY:(float)deltaY;

/// Returns the names of all currently selected models (from tree + preview).
/// Used by the context menu to determine single vs multi-selection state.
- (NSArray<NSString *> *)previewViewSelectedModelNames:(XLMetalPreviewView *)view;

/// Called when the user requests to delete the current preview/layout group
- (void)previewViewDidRequestDeletePreview:(XLMetalPreviewView *)view;

/// Called when the user requests to rename the current preview/layout group
- (void)previewViewDidRequestRenamePreview:(XLMetalPreviewView *)view;

/// Called when the user requests to print the layout image
- (void)previewViewDidRequestPrintLayoutImage:(XLMetalPreviewView *)view;

/// Called when the user requests to save the layout image to a file
- (void)previewViewDidRequestSaveLayoutImage:(XLMetalPreviewView *)view;

/// Called when the user requests to import models
- (void)previewViewDidRequestImportModels:(XLMetalPreviewView *)view;

/// Called when the user requests to import previews from another show
- (void)previewViewDidRequestImportPreviews:(XLMetalPreviewView *)view;

/// Called when the user requests node layout for a model
- (void)previewView:(XLMetalPreviewView *)view didRequestNodeLayout:(NSString *)modelName;

/// Called when the user requests wiring view for a model
- (void)previewView:(XLMetalPreviewView *)view didRequestWiringView:(NSString *)modelName;

/// Called when the user requests to export a model as a custom xLights model
- (void)previewView:(XLMetalPreviewView *)view didRequestExportAsCustomModel:(NSString *)modelName;

/// Called when the user requests to export a model as an .xmodel file
- (void)previewView:(XLMetalPreviewView *)view didRequestExportXModel:(NSString *)modelName;

/// Called when the user requests to add a model to an existing group
- (void)previewView:(XLMetalPreviewView *)view didRequestAddModel:(NSString *)modelName toGroup:(NSString *)groupName;

/// Called when the user requests to create a new group from selected models
- (void)previewView:(XLMetalPreviewView *)view didRequestCreateGroupFromModels:(NSArray<NSString *> *)modelNames;

/// Called when the user requests to lock or unlock multiple models
- (void)previewView:(XLMetalPreviewView *)view didRequestLockModels:(NSArray<NSString *> *)modelNames lock:(BOOL)lock;

/// Called when the user requests to delete multiple models
- (void)previewView:(XLMetalPreviewView *)view didRequestDeleteModels:(NSArray<NSString *> *)modelNames;

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

/// Grid spacing in world units (default: 50)
@property (nonatomic, assign) float gridSpacing;

/// Whether to center the grid at the world origin (default: YES)
@property (nonatomic, assign) BOOL gridCenterAtOrigin;

/// Grid line color as RGBA (default: 0.3, 0.3, 0.3, 0.4)
@property (nonatomic, assign) simd_float4 gridColor;

/// Whether to render in 3D perspective (YES) or 2D orthographic (NO)
@property (nonatomic, assign) BOOL show3D;

/// Extra padding factor for frameAllModels (0.0 = tight fit, 0.15 = 15% margin).
/// Default is 0.0. The sidebar model preview uses ~0.15 for breathing room.
@property (nonatomic, assign) float framePadding;

/// Optional set of model names to show. When non-nil and non-empty,
/// only models whose names are in this set will be loaded by reloadModels.
/// Set to nil to show all models (default behavior).
@property (nonatomic, copy, nullable) NSSet<NSString *> *visibleModelFilter;

#pragma mark - Background Image

/// File path to the background image (nil = no background image)
@property (nonatomic, strong, nullable) NSString *backgroundImagePath;

/// Brightness multiplier for the background image (0.0 = black, 1.0 = normal, 2.0 = overbright)
@property (nonatomic, assign) float backgroundBrightness;

/// Alpha/opacity for the background image (0.0 = transparent, 1.0 = opaque)
@property (nonatomic, assign) float backgroundAlpha;

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

/// Name of the currently selected model (nil if none).
/// For single selection: set this property directly.
/// For multi-selection: use selectedModelNames.
@property (nonatomic, strong, nullable) NSString *selectedModelName;

/// Names of all currently selected models in the preview.
/// For single selection this contains one element matching selectedModelName.
/// For multi-selection (Cmd+click, rubber-band) it may contain multiple names.
@property (nonatomic, copy, readonly) NSArray<NSString *> *selectedModelNames;

/// Select multiple models by name. Shows bounding box highlights for all,
/// manipulation handles only for the primary (last) model.
- (void)selectModels:(NSArray<NSString *> *)modelNames;

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

#pragma mark - Background Image Control

/// Set the background image from a file path. Pass nil to remove.
- (void)setBackgroundImage:(nullable NSString *)path;

/// Set the background image brightness (0.0-2.0, default 1.0)
- (void)setBackgroundBrightness:(float)brightness;

/// Set the background image alpha/opacity (0.0-1.0, default 1.0)
- (void)setBackgroundAlpha:(float)alpha;

/// Remove the background image
- (void)removeBackgroundImage;

#pragma mark - 2D Scrollbars

/// Whether scrollbars are enabled (default: YES, only visible in 2D mode)
@property (nonatomic, assign) BOOL scrollbarsEnabled;

/// Update scrollbar visibility and position based on current camera state.
/// Called automatically when camera changes; can be called manually after layout changes.
- (void)updateScrollbars;

@end
