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

#import <Cocoa/Cocoa.h>

@class XLEngineBridge;

/// View controller for the inspector sidebar (Logic Pro-style).
///
/// Displays context-sensitive properties for the current selection
/// (models, effects, controllers). Uses NSStackView with disclosure groups
/// pattern from the AppKitInspector spike.
@interface XLInspectorViewController : NSViewController

@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Update inspector to show properties for the given object.
/// Object can be a model name, effect ID, controller name, etc.
- (void)inspectObject:(id)object;

/// Show model properties in the inspector.
- (void)inspectModel:(NSString *)modelName;

/// Show properties for multiple models.
- (void)inspectModels:(NSArray<NSString *> *)modelNames;

/// Clear the inspector (no selection).
- (void)clearInspector;

@end
