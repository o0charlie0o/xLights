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

@class XLRowHeadingsView;

typedef NS_ENUM(NSInteger, XLElementType) {
    XLElementTypeModel = 0,
    XLElementTypeSubmodel = 1,
    XLElementTypeStrand = 2,
    XLElementTypeTiming = 3,
    XLElementTypeModelGroup = 4,
};

@protocol XLRowHeadingsDataSource <NSObject>
@required
- (NSInteger)numberOfRowsInRowHeadings:(XLRowHeadingsView *)view;
- (NSString *)rowHeadings:(XLRowHeadingsView *)view nameForRow:(NSInteger)row;
- (XLElementType)rowHeadings:(XLRowHeadingsView *)view elementTypeForRow:(NSInteger)row;
- (BOOL)rowHeadings:(XLRowHeadingsView *)view isExpandableAtRow:(NSInteger)row;
- (BOOL)rowHeadings:(XLRowHeadingsView *)view isExpandedAtRow:(NSInteger)row;
- (NSInteger)rowHeadings:(XLRowHeadingsView *)view indentLevelForRow:(NSInteger)row;
@optional
- (NSInteger)rowHeadings:(XLRowHeadingsView *)view timingColorIndexForRow:(NSInteger)row;
@end

@protocol XLRowHeadingsDelegate <NSObject>
@optional
- (void)rowHeadings:(XLRowHeadingsView *)view didToggleExpandAtRow:(NSInteger)row;
- (void)rowHeadings:(XLRowHeadingsView *)view didSelectRow:(NSInteger)row;
- (void)rowHeadings:(XLRowHeadingsView *)view didReorderRow:(NSInteger)fromRow toRow:(NSInteger)toRow;
- (NSMenu *)rowHeadings:(XLRowHeadingsView *)view contextMenuForRow:(NSInteger)row;
- (void)rowHeadings:(XLRowHeadingsView *)view didChangeVerticalScrollOffset:(CGFloat)offsetY;

// Layer management
- (void)rowHeadings:(XLRowHeadingsView *)view insertLayerAboveRow:(NSInteger)row;
- (void)rowHeadings:(XLRowHeadingsView *)view insertLayerBelowRow:(NSInteger)row;
- (void)rowHeadings:(XLRowHeadingsView *)view insertMultipleLayersBelowRow:(NSInteger)row count:(NSInteger)count;
- (void)rowHeadings:(XLRowHeadingsView *)view deleteLayerAtRow:(NSInteger)row;
- (void)rowHeadings:(XLRowHeadingsView *)view deleteMultipleLayersAtRow:(NSInteger)row;
- (void)rowHeadings:(XLRowHeadingsView *)view deleteUnusedLayersAtRow:(NSInteger)row;
- (void)rowHeadings:(XLRowHeadingsView *)view editLayerNameAtRow:(NSInteger)row;
- (void)rowHeadingsCollapseAllModels:(XLRowHeadingsView *)view;
- (void)rowHeadingsCollapseAllLayers:(XLRowHeadingsView *)view;

// Model operations
- (void)rowHeadings:(XLRowHeadingsView *)view toggleStrandsAtRow:(NSInteger)row;
- (void)rowHeadings:(XLRowHeadingsView *)view showAllEffectsAtRow:(NSInteger)row;
- (void)rowHeadings:(XLRowHeadingsView *)view toggleRenderDisabledAtRow:(NSInteger)row;
- (void)rowHeadingsEnableRenderOnAllModels:(XLRowHeadingsView *)view;
- (void)rowHeadings:(XLRowHeadingsView *)view playModelAtRow:(NSInteger)row;
- (void)rowHeadings:(XLRowHeadingsView *)view exportModelAtRow:(NSInteger)row;
- (void)rowHeadings:(XLRowHeadingsView *)view selectAllModelEffectsAtRow:(NSInteger)row;
- (void)rowHeadings:(XLRowHeadingsView *)view copyModelEffectsAtRow:(NSInteger)row;
- (void)rowHeadings:(XLRowHeadingsView *)view cutModelEffectsAtRow:(NSInteger)row;
- (void)rowHeadings:(XLRowHeadingsView *)view pasteModelEffectsAtRow:(NSInteger)row;
- (void)rowHeadings:(XLRowHeadingsView *)view deleteModelEffectsAtRow:(NSInteger)row;
- (void)rowHeadings:(XLRowHeadingsView *)view copyModelEffectsIncludingSubmodelsAtRow:(NSInteger)row;
- (BOOL)rowHeadingsIsRenderDisabledAtRow:(XLRowHeadingsView *)view row:(NSInteger)row;
- (BOOL)rowHeadingsHasAnyRenderDisabled:(XLRowHeadingsView *)view;

// Timing track operations
- (void)rowHeadingsAddTimingTrack:(XLRowHeadingsView *)view;
- (void)rowHeadings:(XLRowHeadingsView *)view renameTimingTrackAtRow:(NSInteger)row;
- (void)rowHeadings:(XLRowHeadingsView *)view deleteTimingTrackAtRow:(NSInteger)row;
- (void)rowHeadings:(XLRowHeadingsView *)view importTimingTrackAtRow:(NSInteger)row;
- (void)rowHeadings:(XLRowHeadingsView *)view exportTimingTrackAtRow:(NSInteger)row;
- (void)rowHeadingsHideAllTimingTracks:(XLRowHeadingsView *)view;
- (void)rowHeadingsShowAllTimingTracks:(XLRowHeadingsView *)view;
- (void)rowHeadings:(XLRowHeadingsView *)view importNotesAtRow:(NSInteger)row;
- (void)rowHeadings:(XLRowHeadingsView *)view importLyricsAtRow:(NSInteger)row;
- (void)rowHeadings:(XLRowHeadingsView *)view breakdownPhrasesAtRow:(NSInteger)row;
- (void)rowHeadings:(XLRowHeadingsView *)view breakdownWordsAtRow:(NSInteger)row;
@end

@interface XLRowHeadingsView : NSView
@property (nonatomic, weak) id<XLRowHeadingsDataSource> dataSource;
@property (nonatomic, weak) id<XLRowHeadingsDelegate> delegate;
@property (nonatomic, assign) CGFloat rowHeight;
@property (nonatomic, assign) CGFloat verticalScrollOffset;
@property (nonatomic, assign) NSInteger selectedRow;
/// Number of timing track rows pinned at the top (frozen rows). Set by the sequencer VC.
@property (nonatomic, assign) NSInteger pinnedTimingRowCount;
- (void)reloadData;
@end
