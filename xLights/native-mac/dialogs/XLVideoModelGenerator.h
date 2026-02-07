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
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Processing state for the video-based model generation workflow
typedef NS_ENUM(NSInteger, XLVideoGenState) {
    XLVideoGenStateChooseVideo = 0,
    XLVideoGenStateFindingStart,
    XLVideoGenStateReadingFrames,
    XLVideoGenStateIdentifyingBulbs,
    XLVideoGenStateReviewModel,
};

/// Represents a single detected pixel location with its node number
@interface XLDetectedNode : NSObject
@property (nonatomic, assign) NSPoint location;
@property (nonatomic, assign) NSInteger nodeNumber;  // 1-based
+ (instancetype)nodeWithLocation:(NSPoint)location number:(NSInteger)number;
@end

/// Encapsulates a processed video frame with brightness data
@interface XLProcessedFrame : NSObject
@property (nonatomic, strong) NSBitmapImageRep *bitmap;
@property (nonatomic, assign) NSTimeInterval timestamp;
@property (nonatomic, assign) NSInteger width;
@property (nonatomic, assign) NSInteger height;

- (instancetype)initWithBitmap:(NSBitmapImageRep *)bitmap timestamp:(NSTimeInterval)timestamp;

/// Get the brightness (0-255) of pixel at (x,y)
- (uint8_t)brightnessAtX:(NSInteger)x y:(NSInteger)y;

/// Get the red channel (0-255) of pixel at (x,y)
- (uint8_t)redAtX:(NSInteger)x y:(NSInteger)y;

/// Get the green channel (0-255) of pixel at (x,y)
- (uint8_t)greenAtX:(NSInteger)x y:(NSInteger)y;

/// Get the blue channel (0-255) of pixel at (x,y)
- (uint8_t)blueAtX:(NSInteger)x y:(NSInteger)y;

/// Create a greyscale copy of this frame
- (XLProcessedFrame *)greyscaleCopy;

/// Create a copy with background subtracted
- (XLProcessedFrame *)subtractBackground:(XLProcessedFrame *)background scale:(float)scale;

/// Compute frame delta (total brightness change) from another frame
- (NSInteger)frameDeltaFrom:(XLProcessedFrame *)other;

/// Extract single-channel image as a new frame (0=red, 1=green, 2=blue)
- (XLProcessedFrame *)channelImage:(NSInteger)channel;

/// Apply minimum operation with another frame (pixel-wise min)
- (void)applyMinWith:(XLProcessedFrame *)other;

/// Apply threshold to create binary image (pixels above threshold = 255, below = 0)
- (void)applyThreshold:(uint8_t)threshold;

/// Apply blur with given radius
- (void)applyBlur:(NSInteger)radius;

/// Apply contrast adjustment (-100 to 100)
- (void)applyContrast:(NSInteger)contrast;

/// Apply gamma correction
- (void)applyGamma:(float)gamma;

/// Find the brightest connected region and return its center
- (NSPoint)findBrightestRegionCenter;

/// Find all bright pixel clusters and return their centers with sizes
- (NSArray<NSValue *> *)findBrightPixelCenters:(NSInteger)minSeparation;

@end

/// Core video-based custom model generator using AVFoundation.
/// Implements the same algorithm as the legacy GenerateCustomModelDialog:
/// 1. Open video file
/// 2. Scan for start flash pattern (all-on, all-off, all-on, all-off)
/// 3. Read encoded frames (base-3 color encoding per node)
/// 4. Process frames to identify individual node locations
/// 5. Generate custom model data grid
@interface XLVideoModelGenerator : NSObject

/// Video file URL
@property (nonatomic, strong, nullable) NSURL *videoURL;

/// Video duration in seconds
@property (nonatomic, assign, readonly) NSTimeInterval videoDuration;

/// Video frame rate
@property (nonatomic, assign, readonly) float videoFrameRate;

/// Video dimensions
@property (nonatomic, assign, readonly) CGSize videoDimensions;

/// Current processing state
@property (nonatomic, assign) XLVideoGenState state;

/// Expected number of nodes/pixels
@property (nonatomic, assign) NSInteger expectedNodeCount;

/// Whether the camera is steady (stationary mount)
@property (nonatomic, assign) BOOL isSteadyCamera;

/// Start frame timestamp (detected or manually set)
@property (nonatomic, assign) NSTimeInterval startFrameTime;

/// Whether start frame was successfully detected
@property (nonatomic, assign, readonly) BOOL startFrameDetected;

/// First frame of the video (for preview)
@property (nonatomic, strong, readonly, nullable) NSImage *firstFrameImage;

/// Start frame image (all lights on)
@property (nonatomic, strong, readonly, nullable) NSImage *startFrameImage;

/// Detected nodes after identification
@property (nonatomic, copy, readonly) NSArray<XLDetectedNode *> *detectedNodes;

/// Image processing parameters
@property (nonatomic, assign) NSInteger blur;           // 0-20
@property (nonatomic, assign) NSInteger sensitivity;     // 0-255 threshold
@property (nonatomic, assign) NSInteger contrast;        // -100 to 100
@property (nonatomic, assign) float gamma;               // 0.1 to 5.0
@property (nonatomic, assign) NSInteger saturation;      // 0-100
@property (nonatomic, assign) NSInteger minSeparation;   // minimum pixel distance between nodes
@property (nonatomic, assign) NSInteger despeckle;       // erode/dilate amount

/// Crop rectangle (normalized 0-1 coordinates)
@property (nonatomic, assign) NSRect cropRect;

/// Progress callback (0.0 to 1.0)
@property (nonatomic, copy, nullable) void (^progressCallback)(float progress);

/// Frame display callback for live preview during processing
@property (nonatomic, copy, nullable) void (^frameDisplayCallback)(NSImage *frame);

/// Status message callback
@property (nonatomic, copy, nullable) void (^statusCallback)(NSString *status);

#pragma mark - Video Loading

/// Load a video file and extract basic metadata
- (BOOL)loadVideoFromURL:(NSURL *)url error:(NSError **)error;

/// Get a specific frame from the video at the given time
- (nullable NSImage *)frameAtTime:(NSTimeInterval)time;

/// Get a processed frame at the given time
- (nullable XLProcessedFrame *)processedFrameAtTime:(NSTimeInterval)time;

#pragma mark - Start Frame Detection

/// Scan the first portion of the video for the start flash pattern.
/// Returns YES if a valid start pattern was found.
- (BOOL)findStartFrame;

/// Manually set the start frame time
- (void)setManualStartTime:(NSTimeInterval)time;

#pragma mark - Frame Reading

/// Read all node frames from the video based on expected node count.
/// Must be called after start frame is found.
- (BOOL)readNodeFrames;

#pragma mark - Bulb Identification

/// Process the read frames and identify node locations.
/// Returns the number of nodes found.
- (NSInteger)identifyNodes;

#pragma mark - Model Data Generation

/// Generate custom model data string from detected nodes.
/// Format: semicolon-separated rows, comma-separated columns with node numbers.
- (nullable NSString *)generateModelData;

/// Generate custom model data with specified grid dimensions
- (nullable NSString *)generateModelDataWithWidth:(NSInteger)width height:(NSInteger)height;

/// Get the bounding box of detected nodes
- (NSRect)detectedNodesBounds;

/// Get statistics about the detection
- (NSDictionary<NSString *, id> *)detectionStatistics;

/// Get a preview image showing detected node positions
- (nullable NSImage *)detectionPreviewImage;

/// Cancel any ongoing processing
- (void)cancel;

/// Reset all state
- (void)reset;

@end

NS_ASSUME_NONNULL_END
