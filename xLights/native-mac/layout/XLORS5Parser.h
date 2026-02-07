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

/// Represents a parsed LOR S5 model with all its properties converted
/// to xLights-compatible model type and property dictionary.
@interface XLORS5ModelInfo : NSObject

/// The xLights model type (e.g., "Arches", "Tree", "Single Line")
@property (nonatomic, copy) NSString *xlightsModelType;

/// The original LOR model name
@property (nonatomic, copy) NSString *name;

/// The LOR S5 shape name (e.g., "Arch", "Tree 360 spirals")
@property (nonatomic, copy) NSString *shapeName;

/// The unique ID from the LOR file
@property (nonatomic, copy) NSString *modelId;

/// xLights-compatible properties dictionary (parm1, parm2, WorldPosX, etc.)
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *properties;

/// Whether this model had an unknown shape and fell back to Single Line
@property (nonatomic, assign) BOOL isUnknownShape;

@end

/// Represents a parsed LOR S5 model group.
@interface XLORS5GroupInfo : NSObject

/// The group name
@property (nonatomic, copy) NSString *name;

/// The unique ID from the LOR file
@property (nonatomic, copy) NSString *groupId;

/// Member model IDs (references to XLORS5ModelInfo.modelId)
@property (nonatomic, copy) NSArray<NSString *> *memberIds;

@end

/// Parser for LOR S5 preview files (.lorprev, LORPreviews.xml).
///
/// Reads the LOR S5 XML format and converts models to xLights-compatible
/// model types and properties. This is a native reimplementation of the
/// legacy LORPreview.cpp parser.
@interface XLORS5Parser : NSObject

/// Parse an LOR S5 preview file and return available preview names.
/// @param filePath Path to the LOR S5 preview file
/// @return Array of preview names found in the file, or nil on error
+ (nullable NSArray<NSString *> *)previewNamesInFile:(NSString *)filePath;

/// Parse all models from a specific preview in an LOR S5 file.
/// @param filePath Path to the LOR S5 preview file
/// @param previewName Name of the preview to parse (nil for first/only preview)
/// @param previewWidth The preview canvas width for coordinate scaling
/// @param previewHeight The preview canvas height for coordinate scaling
/// @param models On return, array of parsed model info objects
/// @param groups On return, array of parsed group info objects
/// @return YES if parsing succeeded
+ (BOOL)parseFile:(NSString *)filePath
      previewName:(nullable NSString *)previewName
     previewWidth:(int)previewWidth
    previewHeight:(int)previewHeight
           models:(NSArray<XLORS5ModelInfo *> *_Nullable *_Nonnull)models
           groups:(NSArray<XLORS5GroupInfo *> *_Nullable *_Nonnull)groups;

/// Parse a single LOR S5 model file (.lorprop).
/// @param filePath Path to the LOR S5 model file
/// @param previewWidth The preview canvas width for coordinate scaling
/// @param previewHeight The preview canvas height for coordinate scaling
/// @return Parsed model info, or nil on error
+ (nullable XLORS5ModelInfo *)parseModelFile:(NSString *)filePath
                                previewWidth:(int)previewWidth
                               previewHeight:(int)previewHeight;

@end

NS_ASSUME_NONNULL_END
