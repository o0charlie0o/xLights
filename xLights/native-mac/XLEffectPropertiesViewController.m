/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLEffectPropertiesViewController.h"
#import "effects/XLEffectPanelView.h"
#import "XLEngineBridge.h"
#import "dialogs/XLValueCurveWindow.h"

NSNotificationName const XLEffectSelectionDidChangeNotification = @"XLEffectSelectionDidChangeNotification";

@interface XLEffectPropertiesViewController () <XLEffectPanelViewDelegate>
@end

@implementation XLEffectPropertiesViewController {
    XLEffectPanelView *_effectPanelView;
    NSInteger _selectedEffectId;
    NSString *_selectedEffectType;
}

- (void)loadView {
    NSView *containerView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 250)];
    containerView.wantsLayer = YES;
    containerView.layer.backgroundColor = [[NSColor colorWithWhite:0.15 alpha:1.0] CGColor];

    // Create the effect panel view
    _effectPanelView = [[XLEffectPanelView alloc] initWithFrame:containerView.bounds];
    _effectPanelView.translatesAutoresizingMaskIntoConstraints = NO;
    _effectPanelView.delegate = self;
    [containerView addSubview:_effectPanelView];

    // Constraints for effect panel to fill container
    [NSLayoutConstraint activateConstraints:@[
        [_effectPanelView.topAnchor constraintEqualToAnchor:containerView.topAnchor],
        [_effectPanelView.bottomAnchor constraintEqualToAnchor:containerView.bottomAnchor],
        [_effectPanelView.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor],
        [_effectPanelView.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor],
    ]];

    self.view = containerView;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Start with no selection
    [_effectPanelView clearPanel];

    // Listen for effect selection changes
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(effectSelectionDidChange:)
                                                 name:XLEffectSelectionDidChangeNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Properties

- (NSInteger)selectedEffectId {
    return _selectedEffectId;
}

- (NSString *)selectedEffectType {
    return _selectedEffectType;
}

#pragma mark - Public Methods

- (void)selectEffect:(NSInteger)effectId {
    if (effectId == 0) {
        [self clearSelection];
        return;
    }

    // Get effect info from engine
    if (!_engineBridge) {
        NSLog(@"XLEffectPropertiesViewController: No engine bridge, cannot load effect %ld", (long)effectId);
        return;
    }

    NSDictionary *effectInfo = [_engineBridge getEffect:effectId];
    if (!effectInfo) {
        NSLog(@"XLEffectPropertiesViewController: Effect %ld not found", (long)effectId);
        [self clearSelection];
        return;
    }

    NSString *effectType = effectInfo[@"effectType"];
    if (!effectType || effectType.length == 0) {
        NSLog(@"XLEffectPropertiesViewController: Effect %ld has no type", (long)effectId);
        [self clearSelection];
        return;
    }

    _selectedEffectId = effectId;
    _selectedEffectType = effectType;

    // Update the effect panel view
    _effectPanelView.effectId = effectId;
    _effectPanelView.engineBridge = _engineBridge;

    // Load the panel for this effect type
    [_effectPanelView loadEffectPanel:effectType];

    // Refresh values from the engine
    [self refreshFromEngine];

    NSLog(@"XLEffectPropertiesViewController: Loaded panel for effect %ld (%@)", (long)effectId, effectType);
}

- (void)clearSelection {
    _selectedEffectId = 0;
    _selectedEffectType = nil;

    _effectPanelView.effectId = 0;
    [_effectPanelView clearPanel];
}

- (void)refreshFromEngine {
    if (_selectedEffectId == 0 || !_engineBridge) {
        return;
    }

    // The effect panel view handles refreshing from the effect's current values
    [_effectPanelView refreshFromEffect];
}

#pragma mark - Notification Handler

- (void)effectSelectionDidChange:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    if (!userInfo) {
        [self clearSelection];
        return;
    }

    NSNumber *effectIdNumber = userInfo[@"effectId"];
    NSInteger effectId = effectIdNumber ? [effectIdNumber integerValue] : 0;

    [self selectEffect:effectId];
}

#pragma mark - XLEffectPanelViewDelegate

- (void)effectPanel:(NSString *)effectName
    didChangeParameter:(NSString *)key
                 value:(NSString *)value
{
    // The XLEffectPanelView already writes the parameter to the engine bridge
    // in notifyParameterChange: before calling this delegate method.
    // Do NOT call setEffectParameter again here — that would cause a duplicate
    // write and 2x invalidation in the RenderEngine.
}

- (void)effectPanel:(NSString *)effectName
    editValueCurveForParameter:(NSString *)key
{
    if (_selectedEffectId == 0 || !_engineBridge || !key) return;

    // Get current value and parameter definition
    NSString *currentValue = [_engineBridge getEffectParameter:_selectedEffectId key:key] ?: @"";

    // Find min/max from parameter definitions
    float minValue = 0.0f;
    float maxValue = 100.0f;
    NSArray<NSDictionary *> *params = [_engineBridge getEffectParameters:effectName];
    for (NSDictionary *param in params) {
        if ([param[@"key"] isEqualToString:key]) {
            minValue = [param[@"minValue"] floatValue];
            maxValue = [param[@"maxValue"] floatValue];
            break;
        }
    }

    XLValueCurveWindow *vcWindow = [[XLValueCurveWindow alloc]
        initWithCurveData:currentValue.length > 0 ? currentValue : nil
                 minValue:minValue
                 maxValue:maxValue];
    vcWindow.engineBridge = _engineBridge;

    NSInteger effectId = _selectedEffectId;
    [vcWindow showWithCompletion:^(BOOL modified) {
        if (!modified) return;
        NSString *newData = [vcWindow curveDataString];
        if (newData) {
            [self->_engineBridge setEffectParameter:effectId key:key value:newData];
            [self refreshFromEngine];
        }
    }];
}

- (void)effectPanel:(NSString *)effectName
    didLockParameter:(NSString *)key
              locked:(BOOL)locked
{
    NSLog(@"XLEffectPropertiesViewController: Parameter %@.%@ %@", effectName, key, locked ? @"locked" : @"unlocked");
    // TODO: Handle bulk edit lock state
}

@end
