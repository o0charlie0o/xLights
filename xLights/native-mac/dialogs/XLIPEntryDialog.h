/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLBaseSheetController.h"

NS_ASSUME_NONNULL_BEGIN

/// Native macOS sheet for entering IP addresses.
///
/// Validates IP addresses and hostnames before allowing submission.
@interface XLIPEntryDialog : XLBaseSheetController

/// The entered IP address or hostname
@property (nonatomic, copy) NSString *ipAddress;

/// Whether to allow empty input (default: YES)
@property (nonatomic, assign) BOOL allowsEmptyInput;

/// Whether to allow hostnames in addition to IP addresses (default: YES)
@property (nonatomic, assign) BOOL allowsHostnames;

/// Prompt text shown above the input field
@property (nonatomic, copy) NSString *promptText;

@end

NS_ASSUME_NONNULL_END
