/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLRenderProgressIndicator.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kRingLineWidth = 3.0;
static const CGFloat kSpinnerArcLength = 0.25; // fraction of full circle for spinner

@implementation XLRenderProgressIndicator {
    CAShapeLayer *_trackLayer;
    CAShapeLayer *_progressLayer;
    BOOL _indeterminate;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.masksToBounds = NO;
        [self setupLayers];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        self.wantsLayer = YES;
        self.layer.masksToBounds = NO;
        [self setupLayers];
    }
    return self;
}

- (void)setupLayers {
    // Track ring (always visible — use tertiaryLabelColor for good visibility in dark mode)
    _trackLayer = [CAShapeLayer layer];
    _trackLayer.fillColor = nil;
    _trackLayer.strokeColor = [NSColor.tertiaryLabelColor CGColor];
    _trackLayer.lineWidth = kRingLineWidth;
    _trackLayer.lineCap = kCALineCapRound;
    [self.layer addSublayer:_trackLayer];

    // Progress arc (blue, fills clockwise from 12 o'clock)
    _progressLayer = [CAShapeLayer layer];
    _progressLayer.fillColor = nil;
    _progressLayer.strokeColor = [NSColor systemBlueColor].CGColor;
    _progressLayer.lineWidth = kRingLineWidth;
    _progressLayer.lineCap = kCALineCapRound;
    _progressLayer.strokeStart = 0.0;
    _progressLayer.strokeEnd = 0.0;
    [self.layer addSublayer:_progressLayer];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window) {
        [self updatePaths];
    }
}

- (void)layout {
    [super layout];
    [self updatePaths];
}

- (void)updatePaths {
    CGRect bounds = self.bounds;
    CGPoint center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    CGFloat radius = (MIN(bounds.size.width, bounds.size.height) - kRingLineWidth) / 2.0;

    // Start at 12 o'clock (-pi/2), go clockwise
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path appendBezierPathWithArcWithCenter:center
                                     radius:radius
                                 startAngle:90  // NSBezierPath: 90 = 12 o'clock
                                   endAngle:-270
                                  clockwise:YES];

    // Convert NSBezierPath to CGPath
    CGMutablePathRef cgPath = CGPathCreateMutable();
    NSInteger elementCount = [path elementCount];
    NSPoint points[3];
    for (NSInteger i = 0; i < elementCount; i++) {
        NSBezierPathElement element = [path elementAtIndex:i associatedPoints:points];
        switch (element) {
            case NSBezierPathElementMoveTo:
                CGPathMoveToPoint(cgPath, NULL, points[0].x, points[0].y);
                break;
            case NSBezierPathElementLineTo:
                CGPathAddLineToPoint(cgPath, NULL, points[0].x, points[0].y);
                break;
            case NSBezierPathElementCurveTo:
                CGPathAddCurveToPoint(cgPath, NULL,
                                     points[0].x, points[0].y,
                                     points[1].x, points[1].y,
                                     points[2].x, points[2].y);
                break;
            case NSBezierPathElementClosePath:
                CGPathCloseSubpath(cgPath);
                break;
            default:
                break;
        }
    }

    _trackLayer.path = cgPath;
    _progressLayer.path = cgPath;
    CGPathRelease(cgPath);
}

#pragma mark - Public API

- (void)setProgress:(CGFloat)progress {
    [self setProgress:progress animated:NO];
}

- (void)setProgress:(CGFloat)progress animated:(BOOL)animated {
    _progress = MAX(0.0, MIN(1.0, progress));

    if (_indeterminate) {
        [self stopIndeterminateAnimation];
        _indeterminate = NO;
    }

    if (animated) {
        CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
        anim.fromValue = @(_progressLayer.strokeEnd);
        anim.toValue = @(_progress);
        anim.duration = 0.25;
        anim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        _progressLayer.strokeEnd = _progress;
        [_progressLayer addAnimation:anim forKey:@"progressAnimation"];
    } else {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        _progressLayer.strokeEnd = _progress;
        [CATransaction commit];
    }
}

- (void)setRenderActive:(BOOL)renderActive {
    _renderActive = renderActive;
    if (!renderActive) {
        [self stopAnimating];
        [self setProgress:0.0 animated:NO];
    }
}

- (void)setAnimating:(BOOL)animating {
    if (animating) {
        [self startAnimating];
    } else {
        [self stopAnimating];
    }
}

- (void)startAnimating {
    _animating = YES;
    _renderActive = YES;
    _indeterminate = YES;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _progressLayer.strokeStart = 0.0;
    _progressLayer.strokeEnd = kSpinnerArcLength;
    [CATransaction commit];

    CABasicAnimation *rotation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    rotation.fromValue = @0;
    rotation.toValue = @(2.0 * M_PI);
    rotation.duration = 1.0;
    rotation.repeatCount = HUGE_VALF;
    rotation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [_progressLayer addAnimation:rotation forKey:@"spinAnimation"];
}

- (void)stopAnimating {
    _animating = NO;
    _indeterminate = NO;
    [self stopIndeterminateAnimation];

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _progressLayer.strokeStart = 0.0;
    _progressLayer.strokeEnd = 0.0;
    [CATransaction commit];
}

- (void)stopIndeterminateAnimation {
    [_progressLayer removeAnimationForKey:@"spinAnimation"];
}

#pragma mark - Drawing

- (BOOL)isFlipped {
    return NO;
}

- (NSSize)intrinsicContentSize {
    return NSMakeSize(20, 20);
}

@end
