/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#pragma once

#import <Cocoa/Cocoa.h>

#pragma mark - Section Header

/// Clickable disclosure section header with triangle and bold title.
///
/// Add to a parent NSStackView alongside a separate content view.
/// When toggled, hides the content view. The parent stack view's
/// default `detachesHiddenViews` behavior collapses the space.
@interface XLPropertySectionHeader : NSView

@property (nonatomic, strong, readonly) NSButton *disclosureButton;
@property (nonatomic, strong, readonly) NSTextField *titleLabel;
@property (nonatomic, weak) NSView *contentView;
@property (nonatomic, assign) BOOL expanded;

- (instancetype)initWithTitle:(NSString *)title;

@end

#pragma mark - Row Builder

/// Helper that builds label + control rows for property inspectors.
@interface XLPropertyRowBuilder : NSObject

+ (NSView *)rowWithLabel:(NSString *)label control:(NSView *)control;
+ (NSTextField *)editableTextField;
+ (NSTextField *)readOnlyTextField;
+ (NSTextField *)numericTextField;
+ (NSSlider *)sliderWithMin:(double)min max:(double)max value:(double)value;
+ (NSPopUpButton *)popUpWithItems:(NSArray<NSString *> *)items selectedTitle:(NSString *)selected;
+ (NSButton *)checkbox;

@end
