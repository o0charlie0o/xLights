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

@class XLEngineBridge;
@class XLBufferPanel;

/// Buffer style presets - matches wxWidgets buffer style choices.
typedef NS_ENUM(NSInteger, XLBufferStyle) {
    XLBufferStyleDefault = 0,
    XLBufferStylePerPreview,
    XLBufferStylePerPreviewCamera,
    XLBufferStyleSingleLine,
    XLBufferStyleAsPixel,
    XLBufferStyleHorizontalPerStrand,
    XLBufferStyleVerticalPerStrand,
    XLBufferStyleHorizontalPerNode,
    XLBufferStyleVerticalPerNode,
    XLBufferStyleHorizontalPerModel,
    XLBufferStyleVerticalPerModel,
    XLBufferStyleHorizontalStack,
    XLBufferStyleVerticalStack,
    XLBufferStyleOverlayCenter,
    XLBufferStyleOverlayScaled,
    XLBufferStyleSubBuffer
};

/// Buffer transform options.
typedef NS_ENUM(NSInteger, XLBufferTransform) {
    XLBufferTransformNone = 0,
    XLBufferTransformFlipHorizontal,
    XLBufferTransformFlipVertical,
    XLBufferTransformFlipBoth,
    XLBufferTransformRotate90,
    XLBufferTransformRotate180,
    XLBufferTransformRotate270,
    XLBufferTransformRotate90FlipHorizontal,
    XLBufferTransformRotate90FlipVertical
};

/// Rotation order for 3D transforms.
typedef NS_ENUM(NSInteger, XLRotationOrder) {
    XLRotationOrderXYZ = 0,
    XLRotationOrderXZY,
    XLRotationOrderYXZ,
    XLRotationOrderYZX,
    XLRotationOrderZXY,
    XLRotationOrderZYX
};

/// Buffer settings structure using C types for heap safety.
typedef struct XLBufferSettings {
    // Buffer tab
    int bufferStyle;
    int bufferTransform;
    int bufferStagger;
    int blur;
    BOOL overlayBackground;
    char cameraName[64];

    // RotoZoom tab
    float rotation;              // 0-100, mapped to 0-360
    float rotations;             // 0-200, div 10 = 0-20
    float pivotX;                // 0-100
    float pivotY;                // 0-100
    float zoom;                  // 0-30, div 10 = 0-3
    int zoomQuality;             // 1-10
    float xRotation;             // 0-360
    float yRotation;             // 0-360
    float xPivot;                // 0-100
    float yPivot;                // 0-100
    int rotationOrder;           // XLRotationOrder

    // SubBuffer
    float subBufferLeft;         // -100 to 99
    float subBufferBottom;       // -100 to 99
    float subBufferRight;        // 1 to 200
    float subBufferTop;          // 1 to 200
} XLBufferSettings;

/// Buffer panel constants - matches wxWidgets defines.
#define XL_BLUR_MIN 1
#define XL_BLUR_MAX 15
#define XL_ROTATION_MIN 0
#define XL_ROTATION_MAX 100
#define XL_ZOOM_MIN 0
#define XL_ZOOM_MAX 30
#define XL_ZOOM_DIVISOR 10.0f
#define XL_ROTATIONS_MIN 0
#define XL_ROTATIONS_MAX 200
#define XL_ROTATIONS_DIVISOR 10.0f
#define XL_PIVOT_MIN 0
#define XL_PIVOT_MAX 100
#define XL_XY_ROTATION_MIN 0
#define XL_XY_ROTATION_MAX 360
#define XL_SUBBUFFER_LEFT_MIN (-100)
#define XL_SUBBUFFER_LEFT_MAX 99
#define XL_SUBBUFFER_RIGHT_MIN 1
#define XL_SUBBUFFER_RIGHT_MAX 200

/// Forward protocol declarations.
@protocol XLBufferPanelDelegate;
@protocol XLSubBufferSelectionDelegate;

/// Delegate protocol for buffer panel changes.
@protocol XLBufferPanelDelegate <NSObject>
@optional
- (void)bufferPanelSettingsDidChange:(XLBufferPanel *)panel;
- (void)bufferPanel:(XLBufferPanel *)panel requestsValueCurveForParameter:(NSString *)parameterName;
@end

/// View for interactive sub-buffer region selection.
@interface XLSubBufferSelectionView : NSView

/// SubBuffer bounds (as percentages 0-100 or -100 to 200).
@property (nonatomic, assign) float leftBound;
@property (nonatomic, assign) float bottomBound;
@property (nonatomic, assign) float rightBound;
@property (nonatomic, assign) float topBound;

/// Get sub-buffer string.
- (NSString *)subBufferString;

/// Set from sub-buffer string.
- (void)setFromSubBufferString:(NSString *)string;

/// Delegate for changes.
@property (nonatomic, weak) id<XLSubBufferSelectionDelegate> delegate;

@end

@protocol XLSubBufferSelectionDelegate <NSObject>
@optional
- (void)subBufferSelectionViewDidChange:(XLSubBufferSelectionView *)view;
@end

/// Native AppKit panel for buffer/layer management settings.
/// Replaces the wxWidgets BufferPanel for the native macOS build.
@interface XLBufferPanel : NSView

/// Initialize with default settings.
- (instancetype)initWithFrame:(NSRect)frame;

/// Engine bridge for model data.
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Delegate for changes.
@property (nonatomic, weak) id<XLBufferPanelDelegate> delegate;

/// Get current buffer settings.
- (XLBufferSettings)bufferSettings;

/// Set buffer settings.
- (void)setBufferSettings:(XLBufferSettings)settings;

/// Get buffer settings as string (for effect persistence).
- (NSString *)bufferString;

/// Set from buffer string.
- (void)setFromBufferString:(NSString *)string;

/// Update available buffer styles for model.
- (void)updateBufferStylesForModel:(NSString *)modelName;

/// Update camera choices for model.
- (void)updateCameraChoicesForModel:(NSString *)modelName;

/// Set default controls based on model.
- (void)setDefaultControlsForModel:(NSString *)modelName optionBased:(BOOL)optionBased;

/// Reset to defaults.
- (void)resetToDefaults;

/// Validate settings.
- (void)validateSettings;

/// Whether the panel should reset when a new effect is selected.
@property (nonatomic, assign) BOOL resetOnEffectChange;

#pragma mark - Buffer Tab Controls

/// Buffer style popup.
@property (nonatomic, readonly) NSPopUpButton *bufferStylePopup;

/// Buffer transform popup.
@property (nonatomic, readonly) NSPopUpButton *bufferTransformPopup;

/// Buffer stagger stepper.
@property (nonatomic, readonly) NSStepper *bufferStaggerStepper;

/// Camera choice popup.
@property (nonatomic, readonly) NSPopUpButton *cameraPopup;

/// Blur slider.
@property (nonatomic, readonly) NSSlider *blurSlider;

/// Overlay background checkbox.
@property (nonatomic, readonly) NSButton *overlayBackgroundCheckbox;

#pragma mark - RotoZoom Tab Controls

/// Rotation slider.
@property (nonatomic, readonly) NSSlider *rotationSlider;

/// Rotations slider.
@property (nonatomic, readonly) NSSlider *rotationsSlider;

/// Pivot X slider.
@property (nonatomic, readonly) NSSlider *pivotXSlider;

/// Pivot Y slider.
@property (nonatomic, readonly) NSSlider *pivotYSlider;

/// Zoom slider.
@property (nonatomic, readonly) NSSlider *zoomSlider;

/// Zoom quality slider.
@property (nonatomic, readonly) NSSlider *zoomQualitySlider;

/// X Rotation slider (3D).
@property (nonatomic, readonly) NSSlider *xRotationSlider;

/// Y Rotation slider (3D).
@property (nonatomic, readonly) NSSlider *yRotationSlider;

/// X Pivot slider (3D).
@property (nonatomic, readonly) NSSlider *xPivotSlider;

/// Y Pivot slider (3D).
@property (nonatomic, readonly) NSSlider *yPivotSlider;

/// Rotation order popup.
@property (nonatomic, readonly) NSPopUpButton *rotationOrderPopup;

/// Preset popup.
@property (nonatomic, readonly) NSPopUpButton *presetPopup;

#pragma mark - SubBuffer Tab

/// Sub-buffer selection view.
@property (nonatomic, readonly) XLSubBufferSelectionView *subBufferView;

@end
