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

/// A circular ring progress indicator styled after Final Cut Pro X / Apple Watch
/// activity rings. Shows render progress as a blue arc filling clockwise from
/// 12 o'clock.
///
/// States:
/// - Idle: Subtle gray ring outline
/// - Indeterminate: Short blue arc segment rotating continuously
/// - Determinate: Blue arc fills clockwise 0% -> 100%
@interface XLRenderProgressIndicator : NSView

/// Progress value from 0.0 to 1.0 for determinate mode.
@property (nonatomic, assign) CGFloat progress;

/// Whether the indicator is animating (indeterminate spinner).
@property (nonatomic, assign, getter=isAnimating) BOOL animating;

/// Whether a render operation is active. Controls visibility of the active ring.
@property (nonatomic, assign) BOOL renderActive;

/// Start indeterminate animation (spinning arc).
- (void)startAnimating;

/// Stop animation and return to idle state.
- (void)stopAnimating;

/// Set determinate progress with optional animation.
- (void)setProgress:(CGFloat)progress animated:(BOOL)animated;

@end
