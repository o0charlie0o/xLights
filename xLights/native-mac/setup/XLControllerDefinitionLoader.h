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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Represents a single controller variant parsed from a .xcontroller XML file.
/// After inheritance resolution, all properties from base AbstractVariants are merged in.
@interface XLControllerVariantInfo : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) NSInteger maxPixelPort;
@property (nonatomic, assign) NSInteger maxSerialPort;
@property (nonatomic, assign) NSInteger maxPixelPortChannels;
@property (nonatomic, assign) NSInteger maxSerialPortChannels;
@property (nonatomic, assign) NSInteger maxInputUniverses;
@property (nonatomic, assign) BOOL supportsUpload;
@property (nonatomic, assign) BOOL supportsInputOnlyUpload;
@property (nonatomic, assign) BOOL supportsAutoLayout;
@property (nonatomic, assign) BOOL supportsSmartRemotes;
@property (nonatomic, strong) NSArray<NSString *> *pixelProtocols;
@property (nonatomic, strong) NSArray<NSString *> *serialProtocols;
@property (nonatomic, strong) NSArray<NSString *> *inputProtocols;

@end

/// Represents a controller model (e.g., "F16V4") containing one or more variants.
@interface XLControllerModelInfo : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSArray<XLControllerVariantInfo *> *variants;

@end

/// Represents a vendor (e.g., "Falcon") containing one or more controller models.
@interface XLControllerVendorInfo : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSArray<XLControllerModelInfo *> *models;

@end

/// Singleton that parses all .xcontroller XML files from the app bundle's
/// controllers/ resource directory and provides vendor/model/variant lookup.
///
/// Mirrors the data loading logic from the legacy ControllerCaps C++ class
/// but uses native NSXMLParser and Obj-C data structures.
///
/// The parser performs a two-pass approach:
///   1. First pass: collect all AbstractVariant definitions (keyed by "Vendor:Name")
///   2. Second pass: parse Controller/Variant elements and resolve Base inheritance
@interface XLControllerDefinitionLoader : NSObject

/// Returns the shared singleton instance. Parses on first access.
+ (instancetype)sharedLoader;

/// Force a reload of all .xcontroller files (e.g., after app resource update).
- (void)reload;

/// Returns sorted list of all vendor names.
- (NSArray<NSString *> *)availableVendors;

/// Returns sorted list of model names for the given vendor.
- (NSArray<NSString *> *)modelsForVendor:(NSString *)vendor;

/// Returns sorted list of variant names for the given vendor and model.
- (NSArray<NSString *> *)variantsForVendor:(NSString *)vendor model:(NSString *)model;

/// Returns the full vendor info object, or nil if not found.
- (nullable XLControllerVendorInfo *)vendorInfoForName:(NSString *)vendor;

/// Returns the full model info object, or nil if not found.
- (nullable XLControllerModelInfo *)modelInfoForVendor:(NSString *)vendor model:(NSString *)model;

/// Returns the variant info for a specific vendor/model/variant, or nil if not found.
- (nullable XLControllerVariantInfo *)variantInfoForVendor:(NSString *)vendor
                                                     model:(NSString *)model
                                                   variant:(NSString *)variant;

/// Returns whether a given vendor supports any Ethernet input protocols.
- (BOOL)vendorSupportsEthernet:(NSString *)vendor;

/// Returns whether a given vendor supports any serial input protocols.
- (BOOL)vendorSupportsSerial:(NSString *)vendor;

@end

NS_ASSUME_NONNULL_END
