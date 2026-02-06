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
@end

@interface XLRowHeadingsView : NSView
@property (nonatomic, weak) id<XLRowHeadingsDataSource> dataSource;
@property (nonatomic, weak) id<XLRowHeadingsDelegate> delegate;
@property (nonatomic, assign) CGFloat rowHeight;
@property (nonatomic, assign) CGFloat verticalScrollOffset;
@property (nonatomic, assign) NSInteger selectedRow;
- (void)reloadData;
@end
