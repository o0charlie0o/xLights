/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLTransportBarView.h"
#import "../XLEngineBridge.h"

static const CGFloat kTransportBarHeight = 44.0;
static const CGFloat kButtonSize = 24.0;
static const CGFloat kTimeFontSize = 10.0;
static const CGFloat kButtonSpacing = 2.0;
static const CGFloat kSectionSpacing = 12.0;

static const CGFloat kZoomSliderWidth = 80.0;

@interface XLTransportBarView ()

@property (nonatomic, strong) NSButton *rewindButton;
@property (nonatomic, strong) NSButton *playPauseButton;
@property (nonatomic, strong) NSButton *stopButton;
@property (nonatomic, strong) NSButton *fastForwardButton;
@property (nonatomic, strong) NSTextField *elapsedLabel;
@property (nonatomic, strong) NSTextField *separatorLabel;
@property (nonatomic, strong) NSTextField *totalLabel;
@property (nonatomic, strong) NSSlider *scrubSlider;
@property (nonatomic, strong) NSPopUpButton *ratePopup;
@property (nonatomic, strong) NSButton *loopButton;
@property (nonatomic, strong) NSButton *outputButton;
@property (nonatomic, strong) NSButton *renderButton;
@property (nonatomic, strong) NSView *topBorder;

// Zoom controls
@property (nonatomic, strong) NSImageView *zoomOutIcon;
@property (nonatomic, strong) NSSlider *zoomSlider;
@property (nonatomic, strong) NSImageView *zoomInIcon;
@property (nonatomic, strong) NSButton *fitToWindowButton;

@end

@implementation XLTransportBarView

#pragma mark - Initialization

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _playbackRate = 1.0;
        _totalDurationMS = 60000.0;
        _currentPositionMS = 0.0;
        _zoomLevel = 0.1;
        _minZoomLevel = 0.001;
        _maxZoomLevel = 5.0;
        [self setupView];
        [self setupControls];
        [self setupLayout];
        [self updateTimeDisplay];
        [self updatePlayPauseIcon];
        [self updateZoomSlider];
    }
    return self;
}

#pragma mark - View Setup

- (void)setupView {
    self.wantsLayer = YES;
    self.layer.backgroundColor = CGColorCreateGenericRGB(0.12, 0.12, 0.12, 1.0);

    _topBorder = [[NSView alloc] init];
    _topBorder.wantsLayer = YES;
    _topBorder.layer.backgroundColor = CGColorCreateGenericRGB(1.0, 1.0, 1.0, 0.2);
    _topBorder.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_topBorder];
}

- (void)setupControls {
    // Transport buttons
    _rewindButton = [self makeSymbolButton:@"backward.end.fill"
                               accessLabel:@"Rewind"
                                    action:@selector(rewindAction:)];

    _playPauseButton = [self makeSymbolButton:@"play.fill"
                                  accessLabel:@"Play"
                                       action:@selector(playPauseAction:)];

    _stopButton = [self makeSymbolButton:@"stop.fill"
                             accessLabel:@"Stop"
                                  action:@selector(stopAction:)];

    _fastForwardButton = [self makeSymbolButton:@"forward.end.fill"
                                    accessLabel:@"Fast Forward"
                                         action:@selector(fastForwardAction:)];

    // Time display labels
    NSFont *monoFont = [NSFont monospacedDigitSystemFontOfSize:kTimeFontSize weight:NSFontWeightMedium];

    _elapsedLabel = [NSTextField labelWithString:@"00:00.000"];
    _elapsedLabel.font = monoFont;
    _elapsedLabel.textColor = [NSColor labelColor];
    _elapsedLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _elapsedLabel.alignment = NSTextAlignmentRight;
    [_elapsedLabel setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self addSubview:_elapsedLabel];

    _separatorLabel = [NSTextField labelWithString:@"/"];
    _separatorLabel.font = monoFont;
    _separatorLabel.textColor = [NSColor secondaryLabelColor];
    _separatorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_separatorLabel setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self addSubview:_separatorLabel];

    _totalLabel = [NSTextField labelWithString:@"01:00.000"];
    _totalLabel.font = monoFont;
    _totalLabel.textColor = [NSColor secondaryLabelColor];
    _totalLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_totalLabel setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self addSubview:_totalLabel];

    // Scrub slider
    _scrubSlider = [[NSSlider alloc] init];
    _scrubSlider.translatesAutoresizingMaskIntoConstraints = NO;
    _scrubSlider.minValue = 0.0;
    _scrubSlider.maxValue = _totalDurationMS;
    _scrubSlider.doubleValue = 0.0;
    _scrubSlider.continuous = YES;
    _scrubSlider.target = self;
    _scrubSlider.action = @selector(scrubSliderAction:);
    _scrubSlider.controlSize = NSControlSizeSmall;
    [_scrubSlider setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_scrubSlider setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self addSubview:_scrubSlider];

    // Rate popup
    _ratePopup = [[NSPopUpButton alloc] init];
    _ratePopup.translatesAutoresizingMaskIntoConstraints = NO;
    _ratePopup.controlSize = NSControlSizeSmall;
    _ratePopup.font = [NSFont monospacedDigitSystemFontOfSize:9.0 weight:NSFontWeightRegular];
    [_ratePopup setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSArray *rates = @[@"0.25x", @"0.5x", @"0.75x", @"1.0x", @"1.5x", @"2.0x", @"4.0x"];
    for (NSString *rate in rates) {
        [_ratePopup addItemWithTitle:rate];
    }
    [_ratePopup selectItemWithTitle:@"1.0x"];
    _ratePopup.target = self;
    _ratePopup.action = @selector(ratePopupAction:);
    [self addSubview:_ratePopup];

    // Loop toggle
    _loopButton = [self makeSymbolButton:@"repeat"
                             accessLabel:@"Loop"
                                  action:@selector(loopToggleAction:)];
    [_loopButton setButtonType:NSButtonTypeToggle];
    _loopButton.state = NSControlStateValueOff;

    // Output toggle
    _outputButton = [self makeSymbolButton:@"lightbulb.fill"
                               accessLabel:@"Output"
                                    action:@selector(outputToggleAction:)];
    [_outputButton setButtonType:NSButtonTypeToggle];
    _outputButton.state = NSControlStateValueOff;

    // Render button
    _renderButton = [self makeSymbolButton:@"gearshape.fill"
                               accessLabel:@"Render"
                                    action:@selector(renderAction:)];

    // Zoom controls - minus icon, slider, plus icon
    _zoomOutIcon = [[NSImageView alloc] init];
    _zoomOutIcon.translatesAutoresizingMaskIntoConstraints = NO;
    _zoomOutIcon.imageScaling = NSImageScaleProportionallyDown;
    NSImage *zoomOutImage = [NSImage imageWithSystemSymbolName:@"minus.magnifyingglass"
                                      accessibilityDescription:@"Zoom Out"];
    if (zoomOutImage) {
        NSImageSymbolConfiguration *config =
            [NSImageSymbolConfiguration configurationWithPointSize:10
                                                            weight:NSFontWeightMedium
                                                             scale:NSImageSymbolScaleSmall];
        _zoomOutIcon.image = [zoomOutImage imageWithSymbolConfiguration:config];
    }
    _zoomOutIcon.contentTintColor = [NSColor secondaryLabelColor];
    [_zoomOutIcon setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self addSubview:_zoomOutIcon];

    _zoomSlider = [[NSSlider alloc] init];
    _zoomSlider.translatesAutoresizingMaskIntoConstraints = NO;
    _zoomSlider.minValue = 0.0;  // Will be log-scaled
    _zoomSlider.maxValue = 1.0;
    _zoomSlider.doubleValue = 0.5;
    _zoomSlider.continuous = YES;
    _zoomSlider.target = self;
    _zoomSlider.action = @selector(zoomSliderAction:);
    _zoomSlider.controlSize = NSControlSizeSmall;
    [_zoomSlider setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self addSubview:_zoomSlider];

    _zoomInIcon = [[NSImageView alloc] init];
    _zoomInIcon.translatesAutoresizingMaskIntoConstraints = NO;
    _zoomInIcon.imageScaling = NSImageScaleProportionallyDown;
    NSImage *zoomInImage = [NSImage imageWithSystemSymbolName:@"plus.magnifyingglass"
                                     accessibilityDescription:@"Zoom In"];
    if (zoomInImage) {
        NSImageSymbolConfiguration *config =
            [NSImageSymbolConfiguration configurationWithPointSize:10
                                                            weight:NSFontWeightMedium
                                                             scale:NSImageSymbolScaleSmall];
        _zoomInIcon.image = [zoomInImage imageWithSymbolConfiguration:config];
    }
    _zoomInIcon.contentTintColor = [NSColor secondaryLabelColor];
    [_zoomInIcon setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self addSubview:_zoomInIcon];

    // Fit to Window button
    _fitToWindowButton = [self makeSymbolButton:@"arrow.left.and.right.righttriangle.left.righttriangle.right"
                                    accessLabel:@"Fit to Window"
                                         action:@selector(fitToWindowAction:)];
}

- (NSButton *)makeSymbolButton:(NSString *)symbolName
                   accessLabel:(NSString *)accessLabel
                        action:(SEL)action {
    NSButton *button = [[NSButton alloc] init];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.bezelStyle = NSBezelStyleAccessoryBarAction;
    button.bordered = NO;
    button.imagePosition = NSImageOnly;
    button.imageScaling = NSImageScaleProportionallyDown;
    button.target = self;
    button.action = action;

    NSImage *image = [NSImage imageWithSystemSymbolName:symbolName
                                      accessibilityDescription:accessLabel];
    if (image) {
        NSImageSymbolConfiguration *config =
            [NSImageSymbolConfiguration configurationWithPointSize:12
                                                            weight:NSFontWeightMedium
                                                             scale:NSImageSymbolScaleMedium];
        button.image = [image imageWithSymbolConfiguration:config];
    }

    button.contentTintColor = [NSColor secondaryLabelColor];
    [button setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self addSubview:button];
    return button;
}

#pragma mark - Layout

- (void)setupLayout {
    [NSLayoutConstraint activateConstraints:@[
        // Top border
        [_topBorder.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_topBorder.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_topBorder.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_topBorder.heightAnchor constraintEqualToConstant:1.0],

        // Transport buttons - left group
        [_rewindButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:kSectionSpacing],
        [_rewindButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_rewindButton.widthAnchor constraintEqualToConstant:kButtonSize],
        [_rewindButton.heightAnchor constraintEqualToConstant:kButtonSize],

        [_playPauseButton.leadingAnchor constraintEqualToAnchor:_rewindButton.trailingAnchor constant:kButtonSpacing],
        [_playPauseButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_playPauseButton.widthAnchor constraintEqualToConstant:kButtonSize],
        [_playPauseButton.heightAnchor constraintEqualToConstant:kButtonSize],

        [_stopButton.leadingAnchor constraintEqualToAnchor:_playPauseButton.trailingAnchor constant:kButtonSpacing],
        [_stopButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_stopButton.widthAnchor constraintEqualToConstant:kButtonSize],
        [_stopButton.heightAnchor constraintEqualToConstant:kButtonSize],

        [_fastForwardButton.leadingAnchor constraintEqualToAnchor:_stopButton.trailingAnchor constant:kButtonSpacing],
        [_fastForwardButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_fastForwardButton.widthAnchor constraintEqualToConstant:kButtonSize],
        [_fastForwardButton.heightAnchor constraintEqualToConstant:kButtonSize],

        // Time display
        [_elapsedLabel.leadingAnchor constraintEqualToAnchor:_fastForwardButton.trailingAnchor constant:kSectionSpacing],
        [_elapsedLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_elapsedLabel.widthAnchor constraintGreaterThanOrEqualToConstant:62.0],

        [_separatorLabel.leadingAnchor constraintEqualToAnchor:_elapsedLabel.trailingAnchor constant:3.0],
        [_separatorLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

        [_totalLabel.leadingAnchor constraintEqualToAnchor:_separatorLabel.trailingAnchor constant:3.0],
        [_totalLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_totalLabel.widthAnchor constraintGreaterThanOrEqualToConstant:62.0],

        // Scrub slider - fills remaining space
        [_scrubSlider.leadingAnchor constraintEqualToAnchor:_totalLabel.trailingAnchor constant:kSectionSpacing],
        [_scrubSlider.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

        // Right-side controls
        [_ratePopup.leadingAnchor constraintEqualToAnchor:_scrubSlider.trailingAnchor constant:kSectionSpacing],
        [_ratePopup.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_ratePopup.widthAnchor constraintEqualToConstant:58.0],

        [_loopButton.leadingAnchor constraintEqualToAnchor:_ratePopup.trailingAnchor constant:kButtonSpacing],
        [_loopButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_loopButton.widthAnchor constraintEqualToConstant:kButtonSize],
        [_loopButton.heightAnchor constraintEqualToConstant:kButtonSize],

        [_outputButton.leadingAnchor constraintEqualToAnchor:_loopButton.trailingAnchor constant:kButtonSpacing],
        [_outputButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_outputButton.widthAnchor constraintEqualToConstant:kButtonSize],
        [_outputButton.heightAnchor constraintEqualToConstant:kButtonSize],

        [_renderButton.leadingAnchor constraintEqualToAnchor:_outputButton.trailingAnchor constant:kButtonSpacing],
        [_renderButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_renderButton.widthAnchor constraintEqualToConstant:kButtonSize],
        [_renderButton.heightAnchor constraintEqualToConstant:kButtonSize],

        // Zoom controls - after render button
        [_zoomOutIcon.leadingAnchor constraintEqualToAnchor:_renderButton.trailingAnchor constant:kSectionSpacing],
        [_zoomOutIcon.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_zoomOutIcon.widthAnchor constraintEqualToConstant:16.0],
        [_zoomOutIcon.heightAnchor constraintEqualToConstant:16.0],

        [_zoomSlider.leadingAnchor constraintEqualToAnchor:_zoomOutIcon.trailingAnchor constant:4.0],
        [_zoomSlider.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_zoomSlider.widthAnchor constraintEqualToConstant:kZoomSliderWidth],

        [_zoomInIcon.leadingAnchor constraintEqualToAnchor:_zoomSlider.trailingAnchor constant:4.0],
        [_zoomInIcon.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_zoomInIcon.widthAnchor constraintEqualToConstant:16.0],
        [_zoomInIcon.heightAnchor constraintEqualToConstant:16.0],

        // Fit to Window button after zoom controls
        [_fitToWindowButton.leadingAnchor constraintEqualToAnchor:_zoomInIcon.trailingAnchor constant:kButtonSpacing],
        [_fitToWindowButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_fitToWindowButton.widthAnchor constraintEqualToConstant:kButtonSize],
        [_fitToWindowButton.heightAnchor constraintEqualToConstant:kButtonSize],
        [_fitToWindowButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-kSectionSpacing],
    ]];
}

#pragma mark - Property Setters

- (void)setCurrentPositionMS:(CGFloat)currentPositionMS {
    _currentPositionMS = currentPositionMS;
    _scrubSlider.doubleValue = currentPositionMS;
    [self updateTimeDisplay];
}

- (void)setTotalDurationMS:(CGFloat)totalDurationMS {
    _totalDurationMS = totalDurationMS;
    _scrubSlider.maxValue = totalDurationMS;
    [self updateTimeDisplay];
}

- (void)setIsPlaying:(BOOL)isPlaying {
    _isPlaying = isPlaying;
    [self updatePlayPauseIcon];
}

- (void)setLoopEnabled:(BOOL)loopEnabled {
    _loopEnabled = loopEnabled;
    _loopButton.state = loopEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    _loopButton.contentTintColor = loopEnabled
        ? [NSColor controlAccentColor]
        : [NSColor secondaryLabelColor];
}

- (void)setOutputEnabled:(BOOL)outputEnabled {
    _outputEnabled = outputEnabled;
    _outputButton.state = outputEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    _outputButton.contentTintColor = outputEnabled
        ? [NSColor controlAccentColor]
        : [NSColor secondaryLabelColor];
}

- (void)setPlaybackRate:(CGFloat)playbackRate {
    _playbackRate = playbackRate;
    NSString *rateTitle = [NSString stringWithFormat:@"%.2gx", playbackRate];
    // Normalize formatting to match popup items
    if (playbackRate == 0.25) rateTitle = @"0.25x";
    else if (playbackRate == 0.5) rateTitle = @"0.5x";
    else if (playbackRate == 0.75) rateTitle = @"0.75x";
    else if (playbackRate == 1.0) rateTitle = @"1.0x";
    else if (playbackRate == 1.5) rateTitle = @"1.5x";
    else if (playbackRate == 2.0) rateTitle = @"2.0x";
    else if (playbackRate == 4.0) rateTitle = @"4.0x";

    [_ratePopup selectItemWithTitle:rateTitle];
}

- (void)setZoomLevel:(CGFloat)zoomLevel {
    _zoomLevel = MAX(_minZoomLevel, MIN(zoomLevel, _maxZoomLevel));
    [self updateZoomSlider];
}

- (void)setMinZoomLevel:(CGFloat)minZoomLevel {
    _minZoomLevel = minZoomLevel;
    [self updateZoomSlider];
}

- (void)setMaxZoomLevel:(CGFloat)maxZoomLevel {
    _maxZoomLevel = maxZoomLevel;
    [self updateZoomSlider];
}

#pragma mark - Display

- (void)updateTimeDisplay {
    _elapsedLabel.stringValue = [self formatTimeMS:_currentPositionMS];
    _totalLabel.stringValue = [self formatTimeMS:_totalDurationMS];
}

- (NSString *)formatTimeMS:(CGFloat)ms {
    NSInteger totalMS = (NSInteger)ms;
    if (totalMS < 0) totalMS = 0;
    NSInteger minutes = totalMS / 60000;
    NSInteger seconds = (totalMS % 60000) / 1000;
    NSInteger millis = totalMS % 1000;
    return [NSString stringWithFormat:@"%02ld:%02ld.%03ld",
            (long)minutes, (long)seconds, (long)millis];
}

- (void)updatePlayPauseIcon {
    NSString *symbolName = _isPlaying ? @"pause.fill" : @"play.fill";
    NSString *accessLabel = _isPlaying ? @"Pause" : @"Play";
    NSImage *image = [NSImage imageWithSystemSymbolName:symbolName
                                      accessibilityDescription:accessLabel];
    if (image) {
        NSImageSymbolConfiguration *config =
            [NSImageSymbolConfiguration configurationWithPointSize:12
                                                            weight:NSFontWeightMedium
                                                             scale:NSImageSymbolScaleMedium];
        _playPauseButton.image = [image imageWithSymbolConfiguration:config];
    }
    _playPauseButton.contentTintColor = _isPlaying
        ? [NSColor controlAccentColor]
        : [NSColor secondaryLabelColor];
}

- (void)updateZoomSlider {
    // Use logarithmic scaling for more intuitive zoom control
    // Convert zoomLevel to slider position (0.0 to 1.0)
    if (_maxZoomLevel <= _minZoomLevel || _minZoomLevel <= 0) return;

    CGFloat logMin = log(_minZoomLevel);
    CGFloat logMax = log(_maxZoomLevel);
    CGFloat logCurrent = log(_zoomLevel);

    CGFloat sliderPos = (logCurrent - logMin) / (logMax - logMin);
    sliderPos = MAX(0.0, MIN(1.0, sliderPos));
    _zoomSlider.doubleValue = sliderPos;
}

#pragma mark - Actions

- (void)rewindAction:(id)sender {
    self.currentPositionMS = 0.0;
    [_engineBridge seek:0];
    if ([_delegate respondsToSelector:@selector(transportBar:didSeekToPositionMS:)]) {
        [_delegate transportBar:self didSeekToPositionMS:0.0];
    }
}

- (void)playPauseAction:(id)sender {
    if (_isPlaying) {
        self.isPlaying = NO;
        [_engineBridge pause];
        if ([_delegate respondsToSelector:@selector(transportBarDidPause:)]) {
            [_delegate transportBarDidPause:self];
        }
    } else {
        self.isPlaying = YES;
        [_engineBridge play];
        if ([_delegate respondsToSelector:@selector(transportBarDidPlay:)]) {
            [_delegate transportBarDidPlay:self];
        }
    }
}

- (void)stopAction:(id)sender {
    self.isPlaying = NO;
    self.currentPositionMS = 0.0;
    [_engineBridge stop];
    [_engineBridge seek:0];
    if ([_delegate respondsToSelector:@selector(transportBarDidStop:)]) {
        [_delegate transportBarDidStop:self];
    }
}

- (void)fastForwardAction:(id)sender {
    self.currentPositionMS = _totalDurationMS;
    [_engineBridge seek:(NSInteger)_totalDurationMS];
    if ([_delegate respondsToSelector:@selector(transportBar:didSeekToPositionMS:)]) {
        [_delegate transportBar:self didSeekToPositionMS:_totalDurationMS];
    }
}

- (void)scrubSliderAction:(id)sender {
    CGFloat positionMS = _scrubSlider.doubleValue;
    _currentPositionMS = positionMS;
    [self updateTimeDisplay];
    [_engineBridge seek:(NSInteger)positionMS];
    if ([_delegate respondsToSelector:@selector(transportBar:didSeekToPositionMS:)]) {
        [_delegate transportBar:self didSeekToPositionMS:positionMS];
    }
}

- (void)ratePopupAction:(id)sender {
    NSString *title = _ratePopup.titleOfSelectedItem;
    CGFloat rate = [[title stringByReplacingOccurrencesOfString:@"x" withString:@""] doubleValue];
    if (rate <= 0.0) rate = 1.0;
    _playbackRate = rate;
    if ([_delegate respondsToSelector:@selector(transportBar:didChangePlaybackRate:)]) {
        [_delegate transportBar:self didChangePlaybackRate:rate];
    }
}

- (void)loopToggleAction:(id)sender {
    BOOL newState = (_loopButton.state == NSControlStateValueOn);
    self.loopEnabled = newState;
    if ([_delegate respondsToSelector:@selector(transportBar:didToggleLoop:)]) {
        [_delegate transportBar:self didToggleLoop:newState];
    }
}

- (void)outputToggleAction:(id)sender {
    BOOL newState = (_outputButton.state == NSControlStateValueOn);
    self.outputEnabled = newState;

    if (newState) {
        [_engineBridge startOutput];
    } else {
        [_engineBridge stopOutput];
    }

    if ([_delegate respondsToSelector:@selector(transportBar:didToggleOutput:)]) {
        [_delegate transportBar:self didToggleOutput:newState];
    }
}

- (void)renderAction:(id)sender {
    [_engineBridge renderAll];
}

- (void)zoomSliderAction:(id)sender {
    // Convert slider position (0.0 to 1.0) to zoom level using logarithmic scaling
    CGFloat sliderPos = _zoomSlider.doubleValue;

    if (_maxZoomLevel <= _minZoomLevel || _minZoomLevel <= 0) return;

    CGFloat logMin = log(_minZoomLevel);
    CGFloat logMax = log(_maxZoomLevel);
    CGFloat logZoom = logMin + sliderPos * (logMax - logMin);
    CGFloat newZoom = exp(logZoom);

    _zoomLevel = MAX(_minZoomLevel, MIN(newZoom, _maxZoomLevel));

    if ([_delegate respondsToSelector:@selector(transportBar:didChangeZoomLevel:)]) {
        [_delegate transportBar:self didChangeZoomLevel:_zoomLevel];
    }
}

- (void)fitToWindowAction:(id)sender {
    if ([_delegate respondsToSelector:@selector(transportBarDidRequestFitToWindow:)]) {
        [_delegate transportBarDidRequestFitToWindow:self];
    }
}

#pragma mark - Keyboard Support

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)keyDown:(NSEvent *)event {
    NSString *chars = event.charactersIgnoringModifiers;
    if ([chars length] == 0) {
        [super keyDown:event];
        return;
    }

    unichar key = [chars characterAtIndex:0];

    if (key == ' ') {
        [self playPauseAction:nil];
    } else if (key == 27) { // Escape
        [self stopAction:nil];
    } else {
        [super keyDown:event];
    }
}

#pragma mark - Intrinsic Content Size

- (NSSize)intrinsicContentSize {
    return NSMakeSize(NSViewNoIntrinsicMetric, kTransportBarHeight);
}

@end
