/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLSpaceNavigatorManager.h"
#import <dlfcn.h>
#import <IOKit/hid/IOHIDManager.h>

#pragma mark - 3DconnexionClient Framework Types & Constants

// Constants from the 3DconnexionClient framework
#define kConnexionClientModeTakeOver    1
#define kConnexionMaskAll               0x3fff
#define kConnexionMaskAllButtons        0xFFFFFFFF
#define kConnexionCmdHandleButtons      2
#define kConnexionCmdHandleAxis         3
#define kConnexionCmdAppSpecific        10
#define kConnexionMsgDeviceState        '3dSR'
#define kConnexionCtlGetDeviceID        '3did'

#pragma pack(push, 2)
typedef struct {
    uint16_t version;
    uint16_t client;
    uint16_t command;
    int16_t  param;
    int32_t  value;
    uint64_t time;
    uint8_t  report[8];
    uint16_t buttons8;
    int16_t  axis[6]; // tx, ty, tz, rx, ry, rz
    uint16_t address;
    uint32_t buttons;
} ConnexionDeviceState;
#pragma pack(pop)

// Driver function pointer types
typedef void (*AddedHandler)(uint32_t);
typedef void (*RemovedHandler)(uint32_t);
typedef void (*MessageHandler)(uint32_t, uint32_t msg_type, void *msg_arg);

typedef int16_t  (*SetConnexionHandlers_ptr)(MessageHandler, AddedHandler, RemovedHandler, bool);
typedef void     (*CleanupConnexionHandlers_ptr)(void);
typedef uint16_t (*RegisterConnexionClient_ptr)(uint32_t signature, const char *name,
                                                uint16_t mode, uint32_t mask);
typedef void     (*SetConnexionClientButtonMask_ptr)(uint16_t clientID, uint32_t buttonMask);
typedef void     (*UnregisterConnexionClient_ptr)(uint16_t clientID);
typedef int16_t  (*ConnexionClientControl_ptr)(uint16_t clientID, uint32_t message,
                                               int32_t param, int32_t *result);

#pragma mark - Known 3Dconnexion Device IDs

// Vendor IDs
static const uint16_t kVendorLogitech     = 0x046d;
static const uint16_t kVendor3Dconnexion  = 0x256F;

// Product IDs (from legacy Mouse3DManager)
static const uint16_t kKnownProductIDs[] = {
    0xc603, // spacemouse plus XT
    0xc605, // cadman
    0xc606, // spacemouse classic
    0xc621, // spaceball 5000
    0xc623, // space traveller
    0xc625, // space pilot
    0xc626, // space navigator
    0xc627, // space explorer
    0xc628, // space navigator for notebooks
    0xc629, // space pilot pro
    0xc62b, // space mouse pro
    0xc62e, // spacemouse wireless (USB cable)
    0xc62f, // spacemouse wireless receiver
    0xc631, // spacemouse pro wireless
    0xc632, // spacemouse pro wireless receiver
    0xc633, // spacemouse enterprise
    0xc635, // spacemouse compact
    0xc636, // spacemouse module
    0xc640, // nulooq
    0xc652, // 3Dconnexion universal receiver
};
static const size_t kKnownProductIDCount = sizeof(kKnownProductIDs) / sizeof(kKnownProductIDs[0]);

#pragma mark - Button Name Table

static NSString * const kButtonNames[] = {
    @"BUTTON_MENU",    @"BUTTON_FIT",      @"BUTTON_TOP",    @"BUTTON_LEFT",
    @"BUTTON_RIGHT",   @"BUTTON_FRONT",    @"BUTTON_BOTTOM",
    @"BUTTON_11",      @"BUTTON_ROLL",     @"BUTTON_12",
    @"BUTTON_ISO1",    @"BUTTON_ISO2",
    @"BUTTON_1",       @"BUTTON_2",        @"BUTTON_3",      @"BUTTON_4",
    @"BUTTON_5",       @"BUTTON_6",        @"BUTTON_7",      @"BUTTON_8",
    @"BUTTON_9",       @"BUTTON_10",
    @"BUTTON_ESC",     @"BUTTON_ALT",
    @"BUTTON_SHIFT",   @"BUTTON_CTRL",     @"BUTTON_LOCK",
    @"BUTTON_V1",      @"BUTTON_V2",       @"BUTTON_V3",
    @"BUTTON_ENTER",   @"BUTTON_TAB",      @"BUTTON_DELETE",  @"BUTTON_SPACE",
    @"BUTTON_BACK",
};
static const size_t kButtonNameCount = sizeof(kButtonNames) / sizeof(kButtonNames[0]);

#pragma mark - Static Driver State

// 3DconnexionClient framework loaded state (shared across instances, same as legacy)
static void *sDriverModule = NULL;
static BOOL sDriverLoaded = NO;
static uint16_t sClientID = 0;

// Function pointers
static SetConnexionHandlers_ptr         sSetConnexionHandlers = NULL;
static CleanupConnexionHandlers_ptr     sCleanupConnexionHandlers = NULL;
static RegisterConnexionClient_ptr      sRegisterConnexionClient = NULL;
static SetConnexionClientButtonMask_ptr sSetConnexionClientButtonMask = NULL;
static UnregisterConnexionClient_ptr    sUnregisterConnexionClient = NULL;
static ConnexionClientControl_ptr       sConnexionClientControl = NULL;

// Weak reference to active manager for C callbacks
static __weak XLSpaceNavigatorManager *sActiveManager = nil;

#pragma mark - Private Interface (forward declaration for C callbacks)

@interface XLSpaceNavigatorManager () {
    // IOKit HID fallback
    IOHIDManagerRef _hidManager;
    dispatch_queue_t _hidQueue;
    BOOL _running;
}

@property (nonatomic, readwrite) BOOL isDeviceConnected;
@property (nonatomic, readwrite, nullable) NSString *connectedDeviceName;
@property (nonatomic, readwrite) BOOL usingOfficialDriver;

- (NSString *)deviceNameForVendor:(int16_t)vendorID product:(int16_t)productID;
- (void)handleDeviceConnected:(NSString *)name;
- (void)handleDeviceDisconnected;
- (void)handleMotionWithTranslation:(simd_float3)translation rotation:(simd_float3)rotation;
- (void)handleButtonPress:(uint32_t)buttonIndex;

@end

#pragma mark - 3DconnexionClient C Callbacks

static void CXDeviceAdded(uint32_t unused) {
    XLSpaceNavigatorManager *mgr = sActiveManager;
    if (!mgr) return;

    int32_t result = 0;
    sConnexionClientControl(sClientID, kConnexionCtlGetDeviceID, 0, &result);
    int16_t vendorID = result >> 16;
    int16_t productID = result & 0xffff;

    sSetConnexionClientButtonMask(sClientID, kConnexionMaskAllButtons);

    NSString *name = [mgr deviceNameForVendor:vendorID product:productID];
    [mgr handleDeviceConnected:name];
}

static void CXDeviceRemoved(uint32_t unused) {
    XLSpaceNavigatorManager *mgr = sActiveManager;
    if (!mgr) return;
    [mgr handleDeviceDisconnected];
}

static void CXDeviceEvent(uint32_t unused, uint32_t msg_type, void *msg_arg) {
    if (msg_type != kConnexionMsgDeviceState) return;

    ConnexionDeviceState *s = (ConnexionDeviceState *)msg_arg;
    if (s->client != sClientID) return;

    XLSpaceNavigatorManager *mgr = sActiveManager;
    if (!mgr) return;

    switch (s->command) {
        case kConnexionCmdHandleAxis: {
            // Normalize axes to [-1, 1] range (max reported value ~2500)
            simd_float3 t = {
                (float)s->axis[0] / 2500.0f,
                (float)s->axis[1] / 2500.0f,
                (float)s->axis[2] / 2500.0f
            };
            simd_float3 r = {
                (float)s->axis[3] / 2500.0f,
                (float)s->axis[4] / 2500.0f,
                (float)s->axis[5] / 2500.0f
            };
            // Clamp to [-1, 1]
            for (int i = 0; i < 3; i++) {
                t[i] = fmaxf(-1.0f, fminf(1.0f, t[i]));
                r[i] = fmaxf(-1.0f, fminf(1.0f, r[i]));
            }
            [mgr handleMotionWithTranslation:t rotation:r];
            break;
        }
        case kConnexionCmdHandleButtons: {
            uint32_t buttons = s->buttons;
            for (uint32_t i = 0; i < 32; i++) {
                if (buttons & (1u << i)) {
                    [mgr handleButtonPress:i];
                }
            }
            break;
        }
        default:
            break;
    }
}

@implementation XLSpaceNavigatorManager

#pragma mark - Singleton

+ (XLSpaceNavigatorManager *)sharedManager {
    static XLSpaceNavigatorManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[XLSpaceNavigatorManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _isDeviceConnected = NO;
        _usingOfficialDriver = NO;
        _running = NO;
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

#pragma mark - Public API

- (void)startWithDelegate:(id<XLSpaceNavigatorDelegate>)delegate {
    if (_running) return;

    _delegate = delegate;
    _running = YES;
    sActiveManager = self;

    // Try the official 3DconnexionClient framework first
    if ([self loadOfficialDriver]) {
        NSLog(@"XLSpaceNavigatorManager: Using official 3DconnexionClient driver");
        _usingOfficialDriver = YES;
        return;
    }

    // Fall back to IOKit HID
    NSLog(@"XLSpaceNavigatorManager: Official driver not found, using IOKit HID fallback");
    _usingOfficialDriver = NO;
    [self startIOKitHID];
}

- (void)stop {
    if (!_running) return;
    _running = NO;
    sActiveManager = nil;

    if (_usingOfficialDriver) {
        [self unloadOfficialDriver];
    } else {
        [self stopIOKitHID];
    }

    _isDeviceConnected = NO;
    _connectedDeviceName = nil;
}

#pragma mark - Official 3DconnexionClient Framework

- (BOOL)loadOfficialDriver {
    if (sDriverLoaded) return YES;

    sDriverModule = dlopen("/Library/Frameworks/3DconnexionClient.framework/3DconnexionClient",
                           RTLD_LAZY | RTLD_LOCAL);
    if (!sDriverModule) return NO;

    sSetConnexionHandlers = (SetConnexionHandlers_ptr)dlsym(sDriverModule, "SetConnexionHandlers");
    if (!sSetConnexionHandlers) {
        dlclose(sDriverModule);
        sDriverModule = NULL;
        return NO;
    }

    sCleanupConnexionHandlers = (CleanupConnexionHandlers_ptr)dlsym(sDriverModule, "CleanupConnexionHandlers");
    sRegisterConnexionClient = (RegisterConnexionClient_ptr)dlsym(sDriverModule, "RegisterConnexionClient");
    sSetConnexionClientButtonMask = (SetConnexionClientButtonMask_ptr)dlsym(sDriverModule, "SetConnexionClientButtonMask");
    sUnregisterConnexionClient = (UnregisterConnexionClient_ptr)dlsym(sDriverModule, "UnregisterConnexionClient");
    sConnexionClientControl = (ConnexionClientControl_ptr)dlsym(sDriverModule, "ConnexionClientControl");

    const BOOL separateThread = YES;
    int16_t error = sSetConnexionHandlers(CXDeviceEvent, CXDeviceAdded, CXDeviceRemoved, separateThread);
    if (error) {
        dlclose(sDriverModule);
        sDriverModule = NULL;
        return NO;
    }

    // Register as 'xlts' (same four-char code as legacy xLights)
    sClientID = sRegisterConnexionClient('xlts', "\007xLights",
                                          kConnexionClientModeTakeOver, kConnexionMaskAll);
    sSetConnexionClientButtonMask(sClientID, kConnexionMaskAllButtons);
    sDriverLoaded = YES;

    return YES;
}

- (void)unloadOfficialDriver {
    if (!sDriverLoaded) return;

    if (sUnregisterConnexionClient) {
        sUnregisterConnexionClient(sClientID);
    }
    if (sCleanupConnexionHandlers) {
        sCleanupConnexionHandlers();
    }
    if (sDriverModule) {
        dlclose(sDriverModule);
        sDriverModule = NULL;
    }

    sDriverLoaded = NO;
    sClientID = 0;
}

#pragma mark - IOKit HID Fallback

static BOOL isKnownVendor(uint16_t vendorID) {
    return vendorID == kVendorLogitech || vendorID == kVendor3Dconnexion;
}

static BOOL isKnownProduct(uint16_t productID) {
    for (size_t i = 0; i < kKnownProductIDCount; i++) {
        if (kKnownProductIDs[i] == productID) return YES;
    }
    return NO;
}

- (void)startIOKitHID {
    _hidManager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (!_hidManager) {
        NSLog(@"XLSpaceNavigatorManager: Failed to create IOHIDManager");
        return;
    }

    // Match HID devices with Usage Page 1 (Generic Desktop) and Usage 8 (Multi-axis Controller)
    NSDictionary *matchDict = @{
        @(kIOHIDDeviceUsagePageKey): @(0x01),  // Generic Desktop
        @(kIOHIDDeviceUsageKey): @(0x08),       // Multi-axis Controller
    };
    IOHIDManagerSetDeviceMatching(_hidManager, (__bridge CFDictionaryRef)matchDict);

    // Set callbacks
    IOHIDManagerRegisterDeviceMatchingCallback(_hidManager, HIDDeviceMatched, (__bridge void *)self);
    IOHIDManagerRegisterDeviceRemovalCallback(_hidManager, HIDDeviceRemoved, (__bridge void *)self);
    IOHIDManagerRegisterInputValueCallback(_hidManager, HIDInputValueCallback, (__bridge void *)self);

    _hidQueue = dispatch_queue_create("org.xlights.spacenavigator.hid", DISPATCH_QUEUE_SERIAL);
    IOHIDManagerScheduleWithRunLoop(_hidManager, CFRunLoopGetMain(), kCFRunLoopDefaultMode);

    IOReturn ret = IOHIDManagerOpen(_hidManager, kIOHIDOptionsTypeNone);
    if (ret != kIOReturnSuccess) {
        NSLog(@"XLSpaceNavigatorManager: Failed to open IOHIDManager (0x%x)", ret);
        CFRelease(_hidManager);
        _hidManager = NULL;
    }
}

- (void)stopIOKitHID {
    if (_hidManager) {
        IOHIDManagerClose(_hidManager, kIOHIDOptionsTypeNone);
        IOHIDManagerUnscheduleFromRunLoop(_hidManager, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
        CFRelease(_hidManager);
        _hidManager = NULL;
    }
    _hidQueue = nil;
}

#pragma mark - IOKit HID Callbacks

static void HIDDeviceMatched(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
    XLSpaceNavigatorManager *mgr = (__bridge XLSpaceNavigatorManager *)context;

    uint16_t vendorID = [(NSNumber *)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDVendorIDKey)) unsignedShortValue];
    uint16_t productID = [(NSNumber *)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductIDKey)) unsignedShortValue];

    if (!isKnownVendor(vendorID) || !isKnownProduct(productID)) return;

    NSString *name = [mgr deviceNameForVendor:vendorID product:productID];
    NSLog(@"XLSpaceNavigatorManager: HID device matched: %@", name);
    [mgr handleDeviceConnected:name];
}

static void HIDDeviceRemoved(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
    XLSpaceNavigatorManager *mgr = (__bridge XLSpaceNavigatorManager *)context;

    uint16_t vendorID = [(NSNumber *)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDVendorIDKey)) unsignedShortValue];
    if (isKnownVendor(vendorID)) {
        NSLog(@"XLSpaceNavigatorManager: HID device removed");
        [mgr handleDeviceDisconnected];
    }
}

static void HIDInputValueCallback(void *context, IOReturn result, void *sender, IOHIDValueRef value) {
    XLSpaceNavigatorManager *mgr = (__bridge XLSpaceNavigatorManager *)context;
    if (!mgr.isDeviceConnected) return;

    IOHIDElementRef element = IOHIDValueGetElement(value);
    uint32_t usagePage = IOHIDElementGetUsagePage(element);
    uint32_t usage = IOHIDElementGetUsage(element);
    CFIndex intValue = IOHIDValueGetIntegerValue(value);

    if (usagePage == 0x01) {
        // Generic Desktop usage page - axis data
        // Usage 0x30=X, 0x31=Y, 0x32=Z (translation)
        // Usage 0x33=Rx, 0x34=Ry, 0x35=Rz (rotation)

        CFIndex logicalMin = IOHIDElementGetLogicalMin(element);
        CFIndex logicalMax = IOHIDElementGetLogicalMax(element);
        float range = (float)(logicalMax - logicalMin);
        float normalized = 0.0f;
        if (range > 0) {
            normalized = ((float)intValue - (float)logicalMin) / range * 2.0f - 1.0f;
        } else {
            // Fallback: normalize assuming ~350 max like legacy HID path
            normalized = (float)intValue / 350.0f;
        }
        normalized = fmaxf(-1.0f, fminf(1.0f, normalized));

        // Apply deadzone
        if (fabsf(normalized) < 0.01f) normalized = 0.0f;

        [mgr handleHIDAxisUsage:usage value:normalized];

    } else if (usagePage == 0x09) {
        // Button usage page
        if (intValue != 0) {
            uint32_t buttonIndex = usage - 1; // HID buttons are 1-based
            [mgr handleButtonPress:buttonIndex];
        }
    }
}

#pragma mark - HID Axis Accumulation

/// Accumulates individual HID axis reports into a complete motion event.
/// SpaceMouse devices send each axis as a separate HID value callback,
/// so we buffer them and dispatch when we have a complete set or after a timeout.
- (void)handleHIDAxisUsage:(uint32_t)usage value:(float)value {
    static simd_float3 accumulatedTranslation = {0, 0, 0};
    static simd_float3 accumulatedRotation = {0, 0, 0};
    static uint8_t axesSeen = 0;

    switch (usage) {
        case 0x30: accumulatedTranslation.x = value; axesSeen |= 0x01; break; // X
        case 0x31: accumulatedTranslation.y = value; axesSeen |= 0x02; break; // Y
        case 0x32: accumulatedTranslation.z = value; axesSeen |= 0x04; break; // Z
        case 0x33: accumulatedRotation.x = value;    axesSeen |= 0x08; break; // Rx
        case 0x34: accumulatedRotation.y = value;    axesSeen |= 0x10; break; // Ry
        case 0x35: accumulatedRotation.z = value;    axesSeen |= 0x20; break; // Rz
        default: return;
    }

    // Dispatch when we have at least translation or rotation complete
    BOOL hasTranslation = (axesSeen & 0x07) == 0x07;
    BOOL hasRotation = (axesSeen & 0x38) == 0x38;

    if (hasTranslation || hasRotation) {
        simd_float3 t = accumulatedTranslation;
        simd_float3 r = accumulatedRotation;

        // Check if all zero (device at rest)
        float tMag = fabsf(t.x) + fabsf(t.y) + fabsf(t.z);
        float rMag = fabsf(r.x) + fabsf(r.y) + fabsf(r.z);
        if (tMag > 0.001f || rMag > 0.001f) {
            [self handleMotionWithTranslation:t rotation:r];
        }

        // Reset after dispatch
        if (hasTranslation && hasRotation) {
            accumulatedTranslation = (simd_float3){0, 0, 0};
            accumulatedRotation = (simd_float3){0, 0, 0};
            axesSeen = 0;
        }
    }
}

#pragma mark - Event Dispatch (Thread-Safe)

- (void)handleMotionWithTranslation:(simd_float3)translation rotation:(simd_float3)rotation {
    id<XLSpaceNavigatorDelegate> delegate = _delegate;
    if (!delegate) return;

    if ([NSThread isMainThread]) {
        if ([delegate respondsToSelector:@selector(spaceNavigator:didReceiveMotionWithTranslation:rotation:)]) {
            [delegate spaceNavigator:self didReceiveMotionWithTranslation:translation rotation:rotation];
        }
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([delegate respondsToSelector:@selector(spaceNavigator:didReceiveMotionWithTranslation:rotation:)]) {
                [delegate spaceNavigator:self didReceiveMotionWithTranslation:translation rotation:rotation];
            }
        });
    }
}

- (void)handleButtonPress:(uint32_t)buttonIndex {
    id<XLSpaceNavigatorDelegate> delegate = _delegate;
    if (!delegate) return;

    NSString *name;
    if (buttonIndex < kButtonNameCount) {
        name = kButtonNames[buttonIndex];
    } else {
        name = [NSString stringWithFormat:@"BUTTON_%u", buttonIndex];
    }

    if ([NSThread isMainThread]) {
        if ([delegate respondsToSelector:@selector(spaceNavigator:didPressButton:name:)]) {
            [delegate spaceNavigator:self didPressButton:buttonIndex name:name];
        }
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([delegate respondsToSelector:@selector(spaceNavigator:didPressButton:name:)]) {
                [delegate spaceNavigator:self didPressButton:buttonIndex name:name];
            }
        });
    }
}

- (void)handleDeviceConnected:(NSString *)name {
    _isDeviceConnected = YES;
    _connectedDeviceName = name;

    id<XLSpaceNavigatorDelegate> delegate = _delegate;
    if (!delegate) return;

    if ([NSThread isMainThread]) {
        if ([delegate respondsToSelector:@selector(spaceNavigator:deviceConnected:)]) {
            [delegate spaceNavigator:self deviceConnected:name];
        }
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([delegate respondsToSelector:@selector(spaceNavigator:deviceConnected:)]) {
                [delegate spaceNavigator:self deviceConnected:name];
            }
        });
    }
}

- (void)handleDeviceDisconnected {
    _isDeviceConnected = NO;
    _connectedDeviceName = nil;

    id<XLSpaceNavigatorDelegate> delegate = _delegate;
    if (!delegate) return;

    if ([NSThread isMainThread]) {
        if ([delegate respondsToSelector:@selector(spaceNavigatorDeviceDisconnected:)]) {
            [delegate spaceNavigatorDeviceDisconnected:self];
        }
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([delegate respondsToSelector:@selector(spaceNavigatorDeviceDisconnected:)]) {
                [delegate spaceNavigatorDeviceDisconnected:self];
            }
        });
    }
}

#pragma mark - Device Name Lookup

- (NSString *)deviceNameForVendor:(int16_t)vendorID product:(int16_t)productID {
    NSString *vendor;
    switch ((uint16_t)vendorID) {
        case kVendorLogitech:    vendor = @"Logitech"; break;
        case kVendor3Dconnexion: vendor = @"3Dconnexion"; break;
        default:                 vendor = @"Unknown"; break;
    }

    NSString *product;
    switch ((uint16_t)productID) {
        case 0xc603: product = @"SpaceMouse Plus XT"; break;
        case 0xc605: product = @"CadMan"; break;
        case 0xc606: product = @"SpaceMouse Classic"; break;
        case 0xc621: product = @"Spaceball 5000"; break;
        case 0xc623: product = @"Space Traveller"; break;
        case 0xc625: product = @"Space Pilot"; break;
        case 0xc626: product = @"Space Navigator"; break;
        case 0xc627: product = @"Space Explorer"; break;
        case 0xc628: product = @"Space Navigator for Notebooks"; break;
        case 0xc629: product = @"Space Pilot Pro"; break;
        case 0xc62b: product = @"SpaceMouse Pro"; break;
        case 0xc62e: product = @"SpaceMouse Wireless"; break;
        case 0xc62f: product = @"SpaceMouse Wireless Receiver"; break;
        case 0xc631: product = @"SpaceMouse Pro Wireless"; break;
        case 0xc632: product = @"SpaceMouse Pro Wireless Receiver"; break;
        case 0xc633: product = @"SpaceMouse Enterprise"; break;
        case 0xc635: product = @"SpaceMouse Compact"; break;
        case 0xc636: product = @"SpaceMouse Module"; break;
        case 0xc640: product = @"NuLOOQ"; break;
        case 0xc652: product = @"3Dconnexion Universal Receiver"; break;
        default:     product = [NSString stringWithFormat:@"Unknown (0x%04X)", (uint16_t)productID]; break;
    }

    return [NSString stringWithFormat:@"%@ %@", vendor, product];
}

@end
