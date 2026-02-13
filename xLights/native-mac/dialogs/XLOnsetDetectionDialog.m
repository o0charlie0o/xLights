/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLOnsetDetectionDialog.h"
#import "../sequencer/XLStemData.h"
#import "../audio/XLBandpassFilter.h"
#import "../audio/XLOnsetDetector.h"

static const CGFloat kLabelWidth = 110.0;
static const CGFloat kSliderWidth = 220.0;
static const CGFloat kValueLabelWidth = 70.0;
static const CGFloat kPreviewHeight = 60.0;

static const double kMinFrequency = 20.0;
static const double kMaxFrequency = 20000.0;
static const NSTimeInterval kFilterDebounceInterval = 0.15;

#pragma mark - Preset Definition

typedef struct {
    double lowHz;
    double highHz;
    double threshold;
    double minIntervalMS;
    XLOnsetMethod method;
    const char *name;
} XLOnsetPresetDef;

static const XLOnsetPresetDef kPresets[] = {
    { 20,   150,   0.30, 200, XLOnsetMethodEnergy,   "Kick" },
    { 150,  5000,  0.40, 120, XLOnsetMethodHFC,      "Snare" },
    { 5000, 16000, 0.50, 60,  XLOnsetMethodSpecFlux, "Hi-Hat" },
    { 80,   800,   0.35, 150, XLOnsetMethodEnergy,   "Toms" },
    { 20,   20000, 0.30, 50,  XLOnsetMethodDefault,  "Full Range" },
};
static const NSUInteger kPresetCount = sizeof(kPresets) / sizeof(kPresets[0]);

#pragma mark - Frequency Slider Helpers

/// Convert linear slider position (0..1) to frequency (log scale).
static double sliderToFrequency(double sliderValue) {
    double logMin = log(kMinFrequency);
    double logMax = log(kMaxFrequency);
    return exp(logMin + sliderValue * (logMax - logMin));
}

/// Convert frequency to linear slider position (0..1).
static double frequencyToSlider(double freq) {
    double logMin = log(kMinFrequency);
    double logMax = log(kMaxFrequency);
    return (log(freq) - logMin) / (logMax - logMin);
}

#pragma mark - XLFilteredWaveformPreview

/// Simple NSView that draws a bandpass-filtered waveform with onset markers.
@interface XLFilteredWaveformPreview : NSView

@property (nonatomic, assign) float *filteredSamples;
@property (nonatomic, assign) NSUInteger sampleCount;
@property (nonatomic, assign) double sampleRate;
@property (nonatomic, copy) NSArray<NSNumber *> *onsetTimesMS;
@property (nonatomic, strong) NSColor *waveformColor;

@end

@implementation XLFilteredWaveformPreview

- (BOOL)isOpaque {
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = self.bounds;
    CGFloat w = bounds.size.width;
    CGFloat h = bounds.size.height;
    CGFloat midY = h / 2.0;

    // Background
    [[NSColor colorWithWhite:0.12 alpha:1.0] setFill];
    NSRectFill(bounds);

    // Draw filtered waveform
    if (_filteredSamples && _sampleCount > 0 && w > 0) {
        NSColor *wfColor = _waveformColor ?: [NSColor cyanColor];
        [[wfColor colorWithAlphaComponent:0.5] setStroke];

        NSBezierPath *path = [NSBezierPath bezierPath];
        path.lineWidth = 1.0;

        NSUInteger samplesPerPixel = MAX(1, _sampleCount / (NSUInteger)w);

        for (NSUInteger px = 0; px < (NSUInteger)w; px++) {
            NSUInteger startSample = px * _sampleCount / (NSUInteger)w;
            NSUInteger endSample = MIN(startSample + samplesPerPixel, _sampleCount);

            float minVal = 0, maxVal = 0;
            for (NSUInteger s = startSample; s < endSample; s++) {
                float v = _filteredSamples[s];
                if (v < minVal) minVal = v;
                if (v > maxVal) maxVal = v;
            }

            CGFloat yMin = midY + minVal * midY;
            CGFloat yMax = midY + maxVal * midY;

            [path moveToPoint:NSMakePoint(px, yMin)];
            [path lineToPoint:NSMakePoint(px, yMax)];
        }

        [path stroke];
    }

    // Draw onset markers
    if (_onsetTimesMS.count > 0 && _sampleRate > 0) {
        [[NSColor orangeColor] setStroke];
        double totalDurationMS = (_sampleCount / _sampleRate) * 1000.0;
        if (totalDurationMS <= 0) return;

        for (NSNumber *onsetMS in _onsetTimesMS) {
            double ms = onsetMS.doubleValue;
            CGFloat x = (ms / totalDurationMS) * w;
            if (x < 0 || x > w) continue;

            NSBezierPath *line = [NSBezierPath bezierPath];
            line.lineWidth = 1.0;
            [line moveToPoint:NSMakePoint(x, 0)];
            [line lineToPoint:NSMakePoint(x, h)];
            [line stroke];
        }
    }
}

@end

#pragma mark - XLOnsetDetectionDialog

@interface XLOnsetDetectionDialog ()

// UI controls
@property (nonatomic, strong) NSTextField *trackNameField;
@property (nonatomic, strong) NSPopUpButton *presetPopup;
@property (nonatomic, strong) NSSlider *lowFreqSlider;
@property (nonatomic, strong) NSTextField *lowFreqLabel;
@property (nonatomic, strong) NSSlider *highFreqSlider;
@property (nonatomic, strong) NSTextField *highFreqLabel;
@property (nonatomic, strong) NSSlider *sensitivitySlider;
@property (nonatomic, strong) NSTextField *sensitivityLabel;
@property (nonatomic, strong) NSSlider *minIntervalSlider;
@property (nonatomic, strong) NSTextField *minIntervalLabel;
@property (nonatomic, strong) XLFilteredWaveformPreview *waveformPreview;
@property (nonatomic, strong) NSTextField *onsetCountLabel;

// Detection state
@property (nonatomic, strong) XLOnsetResult *currentOnsetResult;
@property (nonatomic, assign) float *filteredBuffer;
@property (nonatomic, assign) NSUInteger filteredSampleCount;
@property (nonatomic, assign) double filteredSampleRate;
@property (nonatomic, assign) NSUInteger filterGeneration;

// Debounce
@property (nonatomic, assign) BOOL stage1Pending;

// Result storage
@property (nonatomic, copy, readwrite) NSString *trackName;
@property (nonatomic, copy, readwrite) NSArray<NSNumber *> *detectedOnsets;

@end

@implementation XLOnsetDetectionDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Onset Detection";
        self.okButtonTitle = @"Create";
        self.minWidth = 480;
        self.minHeight = 400;
        _filterGeneration = 0;
        _filteredBuffer = NULL;
        _detectedOnsets = @[];
    }
    return self;
}

- (void)dealloc {
    if (_filteredBuffer) {
        free(_filteredBuffer);
        _filteredBuffer = NULL;
    }
}

#pragma mark - Build Content

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10;
    stack.edgeInsets = NSEdgeInsetsMake(4, 4, 4, 4);

    // 1. Track Name
    _trackNameField = [XLBaseSheetController createTextField];
    [_trackNameField.widthAnchor constraintGreaterThanOrEqualToConstant:kSliderWidth].active = YES;
    [stack addArrangedSubview:
        [XLBaseSheetController formRowWithLabel:@"Track Name:" control:_trackNameField labelWidth:kLabelWidth]];

    // 2. Preset
    _presetPopup = [XLBaseSheetController createPopUpButton];
    [_presetPopup removeAllItems];
    for (NSUInteger i = 0; i < kPresetCount; i++) {
        [_presetPopup addItemWithTitle:[NSString stringWithUTF8String:kPresets[i].name]];
    }
    [_presetPopup addItemWithTitle:@"Custom"];
    [_presetPopup setTarget:self];
    [_presetPopup setAction:@selector(presetChanged:)];
    [stack addArrangedSubview:
        [XLBaseSheetController formRowWithLabel:@"Preset:" control:_presetPopup labelWidth:kLabelWidth]];

    // 3. Low Frequency
    NSStackView *lowFreqRow = [self buildSliderRowWithLabel:@"Low Frequency:"
                                                    slider:&_lowFreqSlider
                                                valueLabel:&_lowFreqLabel
                                                  minValue:0.0
                                                  maxValue:1.0
                                                   initial:frequencyToSlider(20.0)
                                                    action:@selector(lowFreqChanged:)];
    [stack addArrangedSubview:lowFreqRow];

    // 4. High Frequency
    NSStackView *highFreqRow = [self buildSliderRowWithLabel:@"High Frequency:"
                                                     slider:&_highFreqSlider
                                                 valueLabel:&_highFreqLabel
                                                   minValue:0.0
                                                   maxValue:1.0
                                                    initial:frequencyToSlider(20000.0)
                                                     action:@selector(highFreqChanged:)];
    [stack addArrangedSubview:highFreqRow];

    // 5. Sensitivity
    NSStackView *sensRow = [self buildSliderRowWithLabel:@"Sensitivity:"
                                                 slider:&_sensitivitySlider
                                             valueLabel:&_sensitivityLabel
                                               minValue:0.01
                                               maxValue:1.0
                                                initial:0.3
                                                 action:@selector(sensitivityChanged:)];
    [stack addArrangedSubview:sensRow];

    // 6. Min Interval
    NSStackView *intervalRow = [self buildSliderRowWithLabel:@"Min Interval:"
                                                     slider:&_minIntervalSlider
                                                 valueLabel:&_minIntervalLabel
                                                   minValue:10.0
                                                   maxValue:500.0
                                                    initial:200.0
                                                     action:@selector(minIntervalChanged:)];
    [stack addArrangedSubview:intervalRow];

    // 7. Waveform preview
    _waveformPreview = [[XLFilteredWaveformPreview alloc] initWithFrame:NSZeroRect];
    _waveformPreview.waveformColor = _stemData.waveformColor;
    _waveformPreview.translatesAutoresizingMaskIntoConstraints = NO;
    [_waveformPreview.heightAnchor constraintEqualToConstant:kPreviewHeight].active = YES;
    [_waveformPreview.widthAnchor constraintGreaterThanOrEqualToConstant:kSliderWidth + kLabelWidth + kValueLabelWidth].active = YES;
    _waveformPreview.wantsLayer = YES;
    _waveformPreview.layer.cornerRadius = 4.0;
    _waveformPreview.layer.masksToBounds = YES;
    [stack addArrangedSubview:_waveformPreview];

    // 8. Onset count
    _onsetCountLabel = [NSTextField labelWithString:@"Detected: 0 onsets"];
    _onsetCountLabel.textColor = [NSColor secondaryLabelColor];
    _onsetCountLabel.font = [NSFont systemFontOfSize:11];
    [stack addArrangedSubview:_onsetCountLabel];

    return stack;
}

- (void)sheetDidLoad {
    // Apply default preset (Kick)
    [_presetPopup selectItemAtIndex:XLOnsetPresetKick];
    [self applyPreset:XLOnsetPresetKick];
}

#pragma mark - Slider Row Builder

- (NSStackView *)buildSliderRowWithLabel:(NSString *)label
                                  slider:(NSSlider * __strong *)outSlider
                              valueLabel:(NSTextField * __strong *)outLabel
                                minValue:(double)minValue
                                maxValue:(double)maxValue
                                 initial:(double)initial
                                  action:(SEL)action {
    NSSlider *slider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    slider.minValue = minValue;
    slider.maxValue = maxValue;
    slider.doubleValue = initial;
    slider.continuous = YES;
    slider.target = self;
    slider.action = action;
    slider.translatesAutoresizingMaskIntoConstraints = NO;
    [slider.widthAnchor constraintEqualToConstant:kSliderWidth].active = YES;

    NSTextField *valueField = [NSTextField labelWithString:@""];
    valueField.alignment = NSTextAlignmentLeft;
    valueField.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
    valueField.translatesAutoresizingMaskIntoConstraints = NO;
    [valueField.widthAnchor constraintEqualToConstant:kValueLabelWidth].active = YES;

    *outSlider = slider;
    *outLabel = valueField;

    // Build row: label + slider + value
    NSTextField *rowLabel = [NSTextField labelWithString:label];
    rowLabel.alignment = NSTextAlignmentRight;
    rowLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [rowLabel.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    NSStackView *row = [[NSStackView alloc] initWithFrame:NSZeroRect];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.spacing = 8;
    row.alignment = NSLayoutAttributeCenterY;
    [row addArrangedSubview:rowLabel];
    [row addArrangedSubview:slider];
    [row addArrangedSubview:valueField];

    return row;
}

#pragma mark - Preset Application

- (void)applyPreset:(XLOnsetPreset)preset {
    if (preset == XLOnsetPresetCustom) return;
    if ((NSUInteger)preset >= kPresetCount) return;

    const XLOnsetPresetDef *def = &kPresets[preset];

    _lowFreqSlider.doubleValue = frequencyToSlider(def->lowHz);
    _highFreqSlider.doubleValue = frequencyToSlider(def->highHz);
    _sensitivitySlider.doubleValue = def->threshold;
    _minIntervalSlider.doubleValue = def->minIntervalMS;

    [self updateAllValueLabels];
    [self updateTrackNameForPreset:preset];
    [self scheduleStage1];
}

- (void)updateTrackNameForPreset:(XLOnsetPreset)preset {
    NSString *presetName;
    if (preset == XLOnsetPresetCustom) {
        presetName = @"Custom";
    } else if ((NSUInteger)preset < kPresetCount) {
        presetName = [NSString stringWithUTF8String:kPresets[preset].name];
    } else {
        presetName = @"Custom";
    }
    NSString *stemName = _stemData.name ?: @"Stem";
    _trackNameField.stringValue = [NSString stringWithFormat:@"%@ - %@", stemName, presetName];
}

#pragma mark - Value Label Updates

- (void)updateAllValueLabels {
    [self updateLowFreqLabel];
    [self updateHighFreqLabel];
    [self updateSensitivityLabel];
    [self updateMinIntervalLabel];
}

- (void)updateLowFreqLabel {
    double freq = sliderToFrequency(_lowFreqSlider.doubleValue);
    if (freq >= 1000.0) {
        _lowFreqLabel.stringValue = [NSString stringWithFormat:@"%.1f kHz", freq / 1000.0];
    } else {
        _lowFreqLabel.stringValue = [NSString stringWithFormat:@"%.0f Hz", freq];
    }
}

- (void)updateHighFreqLabel {
    double freq = sliderToFrequency(_highFreqSlider.doubleValue);
    if (freq >= 1000.0) {
        _highFreqLabel.stringValue = [NSString stringWithFormat:@"%.1f kHz", freq / 1000.0];
    } else {
        _highFreqLabel.stringValue = [NSString stringWithFormat:@"%.0f Hz", freq];
    }
}

- (void)updateSensitivityLabel {
    _sensitivityLabel.stringValue = [NSString stringWithFormat:@"%.2f", _sensitivitySlider.doubleValue];
}

- (void)updateMinIntervalLabel {
    _minIntervalLabel.stringValue = [NSString stringWithFormat:@"%.0f ms", _minIntervalSlider.doubleValue];
}

#pragma mark - Control Actions

- (void)presetChanged:(id)sender {
    NSInteger idx = _presetPopup.indexOfSelectedItem;
    [self applyPreset:(XLOnsetPreset)idx];
}

- (void)lowFreqChanged:(id)sender {
    [self updateLowFreqLabel];
    [self switchToCustomPreset];
    [self scheduleStage1];
}

- (void)highFreqChanged:(id)sender {
    [self updateHighFreqLabel];
    [self switchToCustomPreset];
    [self scheduleStage1];
}

- (void)sensitivityChanged:(id)sender {
    [self updateSensitivityLabel];
    [self runStage2];
}

- (void)minIntervalChanged:(id)sender {
    [self updateMinIntervalLabel];
    [self runStage2];
}

- (void)switchToCustomPreset {
    if (_presetPopup.indexOfSelectedItem != XLOnsetPresetCustom) {
        [_presetPopup selectItemAtIndex:XLOnsetPresetCustom];
    }
}

#pragma mark - Two-Stage Detection

/// Stage 1: bandpass filter + onset detection on background thread.
/// Debounced by 150ms to avoid redundant work while dragging frequency sliders.
- (void)scheduleStage1 {
    _stage1Pending = YES;
    _filterGeneration++;
    NSUInteger generation = _filterGeneration;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kFilterDebounceInterval * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (generation != self.filterGeneration) return;
        if (!self.stage1Pending) return;
        self.stage1Pending = NO;
        [self runStage1WithGeneration:generation];
    });
}

- (void)runStage1WithGeneration:(NSUInteger)generation {
    XLAudioSampleData *audioData = _stemData.audioData;
    if (!audioData || !audioData.samples || audioData.sampleCount == 0) return;

    double lowHz = sliderToFrequency(_lowFreqSlider.doubleValue);
    double highHz = sliderToFrequency(_highFreqSlider.doubleValue);
    double threshold = _sensitivitySlider.doubleValue;
    double minIntervalMS = _minIntervalSlider.doubleValue;

    // Ensure low < high
    if (lowHz >= highHz) {
        double temp = lowHz;
        lowHz = highHz;
        highHz = temp;
    }

    // Determine onset method from current preset
    XLOnsetMethod method = XLOnsetMethodDefault;
    NSInteger presetIdx = _presetPopup.indexOfSelectedItem;
    if (presetIdx >= 0 && (NSUInteger)presetIdx < kPresetCount) {
        method = kPresets[presetIdx].method;
    }

    const float *samples = audioData.samples;
    NSUInteger sampleCount = audioData.sampleCount;
    NSUInteger channelCount = audioData.channelCount;
    double sampleRate = audioData.sampleRate;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if (generation != self.filterGeneration) return;

        // Mix to mono
        float *mono = [XLBandpassFilter mixToMono:samples
                                      sampleCount:sampleCount
                                     channelCount:channelCount];
        if (!mono) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self clearPreview];
            });
            return;
        }

        if (generation != self.filterGeneration) {
            free(mono);
            return;
        }

        // Apply bandpass filter
        float *filtered = [XLBandpassFilter applyBandpassToSamples:mono
                                                       sampleCount:sampleCount
                                                        sampleRate:sampleRate
                                                       lowCutoffHz:lowHz
                                                      highCutoffHz:highHz];
        free(mono);

        if (!filtered) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self clearPreview];
            });
            return;
        }

        if (generation != self.filterGeneration) {
            free(filtered);
            return;
        }

        // Run onset detection
        XLOnsetResult *result = [XLOnsetDetector detectOnsetsInSamples:filtered
                                                           sampleCount:sampleCount
                                                            sampleRate:sampleRate
                                                                method:method
                                                             threshold:threshold
                                                         minIntervalMS:minIntervalMS];

        if (generation != self.filterGeneration) {
            free(filtered);
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.filterGeneration) {
                free(filtered);
                return;
            }

            // Store filtered audio for preview
            if (self.filteredBuffer) {
                free(self.filteredBuffer);
            }
            self.filteredBuffer = filtered;
            self.filteredSampleCount = sampleCount;
            self.filteredSampleRate = sampleRate;
            self.currentOnsetResult = result;

            // Update preview with filtered waveform
            self.waveformPreview.filteredSamples = filtered;
            self.waveformPreview.sampleCount = sampleCount;
            self.waveformPreview.sampleRate = sampleRate;

            // Run Stage 2 to threshold and update
            [self runStage2];
        });
    });
}

/// Stage 2: re-threshold cached detection function (immediate, main thread).
- (void)runStage2 {
    if (!_currentOnsetResult) {
        [self updateOnsetCount:0];
        return;
    }

    double threshold = _sensitivitySlider.doubleValue;
    double minIntervalMS = _minIntervalSlider.doubleValue;

    NSArray<NSNumber *> *onsets = [_currentOnsetResult recomputeOnsetsWithThreshold:threshold
                                                                      minIntervalMS:minIntervalMS];

    _detectedOnsets = onsets ?: @[];

    // Update preview
    _waveformPreview.onsetTimesMS = _detectedOnsets;
    [_waveformPreview setNeedsDisplay:YES];

    [self updateOnsetCount:_detectedOnsets.count];
    [self updateOKButtonState];

    // Notify delegate
    if ([_onsetDelegate respondsToSelector:@selector(onsetDetectionDialog:didUpdatePreviewOnsets:forStemIndex:)]) {
        [_onsetDelegate onsetDetectionDialog:self
                       didUpdatePreviewOnsets:_detectedOnsets
                                forStemIndex:_stemIndex];
    }
}

- (void)clearPreview {
    _currentOnsetResult = nil;
    _detectedOnsets = @[];
    _waveformPreview.filteredSamples = NULL;
    _waveformPreview.sampleCount = 0;
    _waveformPreview.onsetTimesMS = @[];
    [_waveformPreview setNeedsDisplay:YES];
    [self updateOnsetCount:0];
}

- (void)updateOnsetCount:(NSUInteger)count {
    _onsetCountLabel.stringValue = [NSString stringWithFormat:@"Detected: %lu onset%@",
                                    (unsigned long)count, count == 1 ? @"" : @"s"];
}

#pragma mark - Validation

- (NSString *)validate {
    NSString *name = [_trackNameField.stringValue stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (name.length == 0) {
        return @"Track name cannot be empty.";
    }

    if (_existingTrackNames) {
        for (NSString *existing in _existingTrackNames) {
            if ([existing caseInsensitiveCompare:name] == NSOrderedSame) {
                return [NSString stringWithFormat:@"A timing track named \"%@\" already exists.", name];
            }
        }
    }

    if (_detectedOnsets.count == 0) {
        return @"No onsets detected. Adjust sensitivity or frequency range.";
    }

    return nil;
}

#pragma mark - OK / Dismiss

- (void)okClicked:(id)sender {
    _trackName = [_trackNameField.stringValue stringByTrimmingCharactersInSet:
                  [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [super okClicked:sender];
}

- (void)sheetWillDismiss {
    // Cancel any pending detection
    _filterGeneration++;

    // Clear delegate preview
    if ([_onsetDelegate respondsToSelector:@selector(onsetDetectionDialogDidDismiss:)]) {
        [_onsetDelegate onsetDetectionDialogDidDismiss:self];
    }

    // Free filtered buffer
    if (_filteredBuffer) {
        free(_filteredBuffer);
        _filteredBuffer = NULL;
    }
    _waveformPreview.filteredSamples = NULL;
    _currentOnsetResult = nil;
}

@end
