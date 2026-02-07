/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import <Foundation/Foundation.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

@class XLSpaceNavigatorManager;

/// Delegate protocol for receiving 3D input device events.
///
/// The motion callback provides normalized translation and rotation vectors
/// with values in the range [-1, 1] for each axis. Translation maps to
/// camera pan and rotation maps to camera orbit.
@protocol XLSpaceNavigatorDelegate <NSObject>
@optional

/// Called when the 3D device reports motion data.
/// @param manager The manager that detected the motion
/// @param translation Normalized translation vector (x=right, y=up, z=forward)
/// @param rotation Normalized rotation vector (rx=pitch, ry=yaw, rz=roll)
- (void)spaceNavigator:(XLSpaceNavigatorManager *)manager
        didReceiveMotionWithTranslation:(simd_float3)translation
                               rotation:(simd_float3)rotation;

/// Called when a device button is pressed.
/// @param manager The manager that detected the button press
/// @param buttonIndex Zero-based button index
/// @param buttonName Human-readable button name (e.g. "BUTTON_FIT", "BUTTON_TOP")
- (void)spaceNavigator:(XLSpaceNavigatorManager *)manager
       didPressButton:(NSUInteger)buttonIndex
                 name:(NSString *)buttonName;

/// Called when a 3D device is connected.
/// @param manager The manager
/// @param deviceName Human-readable device name
- (void)spaceNavigator:(XLSpaceNavigatorManager *)manager
      deviceConnected:(NSString *)deviceName;

/// Called when a 3D device is disconnected.
/// @param manager The manager
- (void)spaceNavigatorDeviceDisconnected:(XLSpaceNavigatorManager *)manager;

@end

/// Manages 3Dconnexion SpaceMouse/SpaceNavigator device input on macOS.
///
/// Supports two connection methods:
/// 1. Official 3DconnexionClient framework (if the driver is installed)
/// 2. Direct HID access via IOKit (no driver required)
///
/// Usage:
///   [XLSpaceNavigatorManager.sharedManager startWithDelegate:self];
///   // ... receive delegate callbacks ...
///   [XLSpaceNavigatorManager.sharedManager stop];
///
/// The manager normalizes all axis values to [-1, 1] range so consumers
/// don't need to know which connection method is active.
@interface XLSpaceNavigatorManager : NSObject

/// Shared singleton instance
@property (class, nonatomic, readonly) XLSpaceNavigatorManager *sharedManager;

/// The delegate receiving motion and button events
@property (nonatomic, weak, nullable) id<XLSpaceNavigatorDelegate> delegate;

/// Whether a 3D input device is currently connected and active
@property (nonatomic, readonly) BOOL isDeviceConnected;

/// Human-readable name of the connected device (nil if no device)
@property (nonatomic, readonly, nullable) NSString *connectedDeviceName;

/// Whether the official 3DconnexionClient driver is being used (vs IOKit HID)
@property (nonatomic, readonly) BOOL usingOfficialDriver;

/// Start listening for 3D device events.
/// Attempts the official 3DconnexionClient framework first, falls back to IOKit HID.
- (void)startWithDelegate:(id<XLSpaceNavigatorDelegate>)delegate;

/// Stop listening for 3D device events and release resources.
- (void)stop;

@end

NS_ASSUME_NONNULL_END
