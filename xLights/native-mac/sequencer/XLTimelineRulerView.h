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
#import <QuartzCore/QuartzCore.h>

@class XLTimelineRulerView;

/// Plain-C struct for passing song region data to the ruler view.
typedef struct {
    NSInteger regionId;
    NSInteger startTimeMS;
    NSInteger endTimeMS;
    CGFloat colorR, colorG, colorB, colorA;
    char name[128];
} XLSongRegion;

/// Delegate protocol for timeline ruler events.
@protocol XLTimelineRulerDelegate <NSObject>

@optional

/// Called when the playback position changes via click or drag.
- (void)timelineRuler:(XLTimelineRulerView *)ruler didChangePlaybackPosition:(NSTimeInterval)positionSeconds;

/// Called when the zoom level changes.
- (void)timelineRuler:(XLTimelineRulerView *)ruler didChangeZoomLevel:(CGFloat)pixelsPerMillisecond;

/// Called when the zoom level changes with a center point for the zoom operation.
- (void)timelineRuler:(XLTimelineRulerView *)ruler didChangeZoomLevel:(CGFloat)pixelsPerMillisecond centeredOnPointX:(CGFloat)pointX;

/// Called when the scroll offset changes (e.g. from momentum scrolling).
- (void)timelineRuler:(XLTimelineRulerView *)ruler didChangeScrollOffset:(CGFloat)scrollOffset;

/// Called when the user begins scrubbing (mouse down + drag).
- (void)timelineRuler:(XLTimelineRulerView *)ruler didBeginScrubbing:(NSTimeInterval)positionSeconds;

/// Called when the user ends scrubbing (mouse up after drag).
- (void)timelineRuler:(XLTimelineRulerView *)ruler didEndScrubbing:(NSTimeInterval)positionSeconds;

/// Called when the user Option+clicks to create a timing mark.
- (void)timelineRuler:(XLTimelineRulerView *)ruler didRequestTimingMarkAtSeconds:(NSTimeInterval)positionSeconds;

/// Called when a timing mark is dragged to a new position.
- (void)timelineRuler:(XLTimelineRulerView *)ruler didMoveTimingMarkId:(NSInteger)markId toSeconds:(NSTimeInterval)positionSeconds;

/// Called when a timing mark is deleted (via context menu or key).
- (void)timelineRuler:(XLTimelineRulerView *)ruler didRequestDeleteTimingMarkId:(NSInteger)markId;

/// Called when the user requests "Zoom to Selection" from the context menu.
- (void)timelineRulerDidRequestZoomToSelection:(XLTimelineRulerView *)ruler;

/// Called when the user requests "Reset Zoom" from the context menu.
- (void)timelineRulerDidRequestResetZoom:(XLTimelineRulerView *)ruler;

/// Called when a timing tag is toggled. position is in milliseconds, or -1 to clear.
- (void)timelineRuler:(XLTimelineRulerView *)ruler didToggleTimingTag:(NSInteger)tagIndex atPositionMS:(NSInteger)positionMS;

/// Called when all timing tags are cleared.
- (void)timelineRulerDidRequestClearAllTimingTags:(XLTimelineRulerView *)ruler;

/// Returns YES if the sequencer currently has a time selection (for enabling "Zoom to Selection").
- (BOOL)timelineRulerHasTimeSelection:(XLTimelineRulerView *)ruler;

// --- Song Structure Region Delegate Methods ---

/// Called when the user Option+clicks or uses context menu to add a boundary.
- (void)timelineRuler:(XLTimelineRulerView *)ruler didRequestAddSongRegionBoundaryAtTimeMS:(NSInteger)timeMS;

/// Called when a boundary is dragged to a new position.
- (void)timelineRuler:(XLTimelineRulerView *)ruler didMoveSongRegionBoundaryAtIndex:(NSInteger)idx toTimeMS:(NSInteger)timeMS;

/// Called when a boundary is deleted (via context menu or key).
- (void)timelineRuler:(XLTimelineRulerView *)ruler didRequestDeleteSongRegionBoundaryAtIndex:(NSInteger)idx;

/// Called when a region's name or color is edited.
- (void)timelineRuler:(XLTimelineRulerView *)ruler didEditSongRegionId:(NSInteger)regionId name:(NSString *)name color:(NSColor *)color;

/// Called when the user selects a region.
- (void)timelineRuler:(XLTimelineRulerView *)ruler didSelectSongRegionId:(NSInteger)regionId;

/// Called when the user requests clearing all song structure regions.
- (void)timelineRulerDidRequestClearSongStructure:(XLTimelineRulerView *)ruler;

@end

/// CALayer-backed timeline ruler view for the native macOS sequencer.
///
/// Displays time markers at adaptive intervals based on zoom level,
/// a red playback position indicator, and supports click-to-seek
/// and drag-to-scrub interactions.
///
/// Reference: xLights/sequencer/TimeLine.h/cpp (wxWidgets original)
/// Design reference: Logic Pro X / Final Cut Pro X timeline ruler
@interface XLTimelineRulerView : NSView

#pragma mark - Delegate

@property (nonatomic, weak) id<XLTimelineRulerDelegate> delegate;

#pragma mark - Sequence Properties

/// Total sequence duration in seconds.
@property (nonatomic, assign) NSTimeInterval sequenceDuration;

/// Frame rate of the sequence (frames per second, e.g. 20 or 40).
@property (nonatomic, assign) NSInteger frameRate;

#pragma mark - Playback State

/// Current playback position in seconds.
@property (nonatomic, assign) NSTimeInterval playbackPosition;

/// Playback rate multiplier (1.0 = normal speed). Used for interpolation.
@property (nonatomic, assign) CGFloat playbackRate;

/// Whether playback is currently active.
@property (nonatomic, assign, getter=isPlaying) BOOL playing;

#pragma mark - View State

/// Zoom level: pixels per millisecond. Higher = more zoomed in.
@property (nonatomic, assign) CGFloat zoomLevel;

/// Horizontal scroll offset in points (synced with effects grid).
@property (nonatomic, assign) CGFloat scrollOffset;

#pragma mark - Methods

/// Set playback position with optional animation of the playhead.
- (void)setPlaybackPosition:(NSTimeInterval)position animated:(BOOL)animated;

/// Scroll the view so that the given time is visible.
- (void)scrollToTime:(NSTimeInterval)time;

/// Convert an x coordinate (in view space) to a time in seconds.
- (NSTimeInterval)timeForPoint:(CGFloat)x;

/// Convert a time in seconds to an x coordinate (in view space).
- (CGFloat)pointForTime:(NSTimeInterval)time;

#pragma mark - Timing Marks

/// Array of timing marks to display. Each dictionary should have:
/// id (NSNumber), startTimeMS (NSNumber), label (NSString optional)
@property (nonatomic, copy) NSArray<NSDictionary *> *timingMarks;

/// Whether timing marks are editable (can be created/moved/deleted). Default: YES.
@property (nonatomic, assign) BOOL timingMarksEditable;

/// The ID of the currently selected timing mark, or -1 if none.
@property (nonatomic, assign) NSInteger selectedTimingMarkId;

/// Reload timing marks from the data source and redraw.
- (void)reloadTimingMarks;

#pragma mark - Song Structure Regions

/// Song regions to display (C array, caller-managed). Set via setSongRegions:count:.
@property (nonatomic, readonly) XLSongRegion *songRegions;
@property (nonatomic, readonly) NSInteger songRegionCount;

/// The regionId of the currently selected song region, or -1 if none.
@property (nonatomic, assign) NSInteger selectedSongRegionId;

/// Set song regions data. Copies the array.
- (void)setSongRegions:(const XLSongRegion *)regions count:(NSInteger)count;

/// Reload song regions rendering.
- (void)reloadSongRegions;

#pragma mark - Timing Tags (Bookmarks)

/// Timing tag positions in milliseconds (10 slots, indexed 0-9).
/// A value of -1 means the tag is unset.
@property (nonatomic, readonly) NSInteger *timingTagPositions;

/// Set a timing tag position. Use positionMS = -1 to clear a tag.
- (void)setTimingTag:(NSInteger)tagIndex toPositionMS:(NSInteger)positionMS;

/// Clear all timing tags.
- (void)clearAllTimingTags;

/// Returns the number of active timing tags.
- (NSInteger)activeTimingTagCount;

#pragma mark - Preview Timing Marks (Onset Detection)

/// Preview timing marks (onset detection preview). Array of NSNumber (milliseconds).
/// Drawn as translucent orange lines. Set to nil to clear.
@property (nonatomic, copy, nullable) NSArray<NSNumber *> *previewTimingMarks;

@end
